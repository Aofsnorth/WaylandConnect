use image::imageops::FilterType;
use image::{ImageBuffer, Rgba};
use std::sync::{Arc, Mutex};
use log::{info, error};
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Instant;
use ashpd::desktop::screencast::{CursorMode, Screencast, SourceType};
use ashpd::desktop::PersistMode;
use ashpd::WindowIdentifier;
use pipewire as pw;
use libspa as spa;
use std::os::unix::io::OwnedFd;
use crate::pointer_manager::PointerManager;
use wc_processing::Magnifier;
use wc_core::types::Resolution;

pub struct StreamConfig {
    pub width: u32,
    pub height: u32,
    pub fps: u32,
    pub monitor: i32,
}

pub struct ScreenStreamer {
    last_frame: Arc<Mutex<Option<Vec<u8>>>>,
    running: Arc<AtomicBool>,
    config: Arc<Mutex<StreamConfig>>,
    pointer_manager: Option<Arc<PointerManager>>,
}

impl ScreenStreamer {
    pub fn new() -> Self {
        Self {
            last_frame: Arc::new(Mutex::new(None)),
            running: Arc::new(AtomicBool::new(false)),
            config: Arc::new(Mutex::new(StreamConfig {
                width: 854,
                height: 480,
                fps: 30,
                monitor: 0,
            })),
            pointer_manager: None,
        }
    }

    pub fn set_pointer_manager(&mut self, pm: Arc<PointerManager>) {
        self.pointer_manager = Some(pm);
    }

    pub fn stop(&self) {
        if self.running.load(Ordering::SeqCst) {
             self.running.store(false, Ordering::SeqCst);
             if let Ok(mut frame) = self.last_frame.lock() {
                 *frame = None;
             }
             info!("🛑 Mirroring stopped.");
        }
    }

    pub fn get_latest_frame(&self) -> Option<Vec<u8>> {
        self.last_frame.lock().unwrap().clone()
    }

    pub fn start(&self, width: u32, height: u32, fps: u32, monitor: i32) {
        {
            let mut cfg = self.config.lock().unwrap();
            cfg.width = width;
            cfg.height = height;
            cfg.fps = fps;
            cfg.monitor = monitor;
        }

        if self.running.load(Ordering::SeqCst) {
            info!("📽️ Screen streamer already running, updated config to {}x{} @ {}fps", width, height, fps);
            return;
        }
        self.running.store(true, Ordering::SeqCst);
        
        let frame_c = self.last_frame.clone();
        let config_c = self.config.clone();
        let running_c = self.running.clone();
        let pm_c = self.pointer_manager.clone();

        std::thread::spawn(move || {
            info!("🚀 Initializing Wayland Screen Capture via XDG Portal...");
            let rt = tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()
                .unwrap();

            let result = rt.block_on(async {
                info!("📡 Requesting Screen Cast Session...");
                let screencast = Screencast::new().await?;
                let session = screencast.create_session().await?;

                info!("👆 Please select the screen/window in the System Portal popup.");
                screencast.select_sources(
                    &session,
                    CursorMode::Hidden,
                    SourceType::Monitor | SourceType::Window,
                    false,
                    None,
                    PersistMode::DoNot,
                ).await?;

                info!("🚀 Starting Screencast session...");
                let request = screencast.start(&session, &WindowIdentifier::default()).await?;
                let streams = request.response()?;
                let stream_info = streams.streams().first().ok_or("No streams available")?;
                let node_id = stream_info.pipe_wire_node_id();
                
                info!("🏗️ Opening PipeWire remote...");
                let fd = screencast.open_pipe_wire_remote(&session).await?;
                Ok::<(OwnedFd, u32), Box<dyn std::error::Error>>((fd, node_id))
            });

            match result {
                Ok((fd, node_id)) => {
                    info!("✅ Screen Cast Session established. Node ID: {}", node_id);
                    if let Err(e) = run_pipewire_loop(fd, node_id, frame_c, config_c, running_c, pm_c) {
                        error!("PipeWire Loop Error: {}", e);
                    }
                },
                Err(e) => {
                    error!("❌ Failed to set up Screen Cast Session. Make sure to approve the portal request: {}", e);
                    running_c.store(false, Ordering::SeqCst);
                }
            }
        });
    }
}

fn run_pipewire_loop(
    fd: OwnedFd, 
    node_id: u32, 
    frame_store: Arc<Mutex<Option<Vec<u8>>>>,
    config: Arc<Mutex<StreamConfig>>,
    running: Arc<AtomicBool>,
    pointer_manager: Option<Arc<PointerManager>>,
) -> Result<(), Box<dyn std::error::Error>> {
    pw::init();

    let mainloop = pw::main_loop::MainLoop::new(None)?;
    let context = pw::context::Context::new(&mainloop)?;
    let core = context.connect_fd(fd, None)?;

    let mut props = pw::properties::Properties::new();
    props.insert(*pw::keys::STREAM_MONITOR, "true");

    let stream = pw::stream::Stream::new(&core, "wayland-connect-consumer", props)?;

    let mut last_capture_time = Instant::now();
    let _listener = stream
        .add_local_listener::<()>()
        .process(move |stream, _user_data| {
            if !running.load(Ordering::SeqCst) { return; }

            // Check if we should process this frame based on target FPS
            let target_fps = {
                let cfg = config.lock().unwrap();
                cfg.fps
            };

            let min_interval = 1000 / target_fps.max(1);
            if last_capture_time.elapsed().as_millis() < min_interval as u128 {
                // Peek and drop buffer if we're exceeding FPS
                if let Some(_buffer) = stream.dequeue_buffer() {
                    // Buffer dropped
                }
                return;
            }

            if let Some(mut buffer) = stream.dequeue_buffer() {
                let datas = buffer.datas_mut();
                    if let Some(data) = datas.get_mut(0) {
                        let chunk = data.chunk();
                        let offset = chunk.offset();
                        let size = chunk.size();
                        let stride = chunk.stride();

                        if let Some(map) = data.data() {
                            if size > 0 {
                                // info!("📸 Received frame from PipeWire: size={}", size);
                                let frame_slice = &map[offset as usize..(offset + size) as usize];
                            
                            let in_w = stride as u32 / 4; 
                            let in_h = size / stride as u32;

                            let (target_w, target_h) = {
                                let cfg = config.lock().unwrap();
                                (cfg.width, cfg.height)
                            };

                            let (zoom, px, py) = if let Some(pm) = &pointer_manager {
                                pm.get_zoom_and_coords("")
                            } else {
                                (1.0, 0.5, 0.5)
                            };

                                let final_img_buffer = if zoom > 1.05 {
                                    if in_w.is_multiple_of(60) { // Simple limiter
                                        info!("🔍 Magnifier Active: zoom={:.2} @ ({:.2}, {:.2})", zoom, px, py);
                                    }
                                    let magnifier = Magnifier::new(zoom, target_w, target_h);
                                    let processed = magnifier.process(
                                        frame_slice, 
                                        Resolution { width: in_w, height: in_h },
                                        (px * in_w as f32) as i32,
                                        (py * in_h as f32) as i32
                                    );
                                    ImageBuffer::<Rgba<u8>, _>::from_raw(target_w, target_h, processed.to_vec())
                                } else if let Some(img_buffer) = ImageBuffer::<Rgba<u8>, _>::from_raw(in_w, in_h, frame_slice.to_vec()) {
                                    // Nearest neighbor is much faster than gaussian/triangle
                                    Some(image::imageops::resize(&img_buffer, target_w, target_h, FilterType::Nearest))
                                } else {
                                    None
                                };

                                if let Some(img) = final_img_buffer {
                                    let mut jpg_data = Vec::new();
                                    let mut cursor = std::io::Cursor::new(&mut jpg_data);
                                    
                                    // Use JPEG encoder with optimized quality (60) to reduce network load & encoding time
                                    let mut encoder = image::codecs::jpeg::JpegEncoder::new_with_quality(&mut cursor, 60);
                                    if encoder.encode_image(&img).is_ok() {
                                         let len = jpg_data.len();
                                         if let Ok(mut f) = frame_store.lock() {
                                             *f = Some(jpg_data);
                                             info!("🖼️ [SIGNAL] Frame captured and stored. Size: {} bytes (Quality: 60)", len);
                                             last_capture_time = Instant::now();
                                         }
                                    }
                                }
                        }
                    }
                }
            }
        })
        .register()?;

    let mut buf = Vec::with_capacity(1024);
    let mut builder = spa::pod::builder::Builder::new(&mut buf);
    let _ = spa::pod::builder::builder_add!(
        &mut builder,
        Object(spa::sys::SPA_TYPE_OBJECT_Format, spa::sys::SPA_PARAM_EnumFormat) {
            spa::sys::SPA_FORMAT_mediaType => Id(spa::utils::Id(spa::sys::SPA_MEDIA_TYPE_video)),
            spa::sys::SPA_FORMAT_mediaSubtype => Id(spa::utils::Id(spa::sys::SPA_MEDIA_SUBTYPE_raw)),
            spa::sys::SPA_FORMAT_VIDEO_format => Id(spa::utils::Id(spa::sys::SPA_VIDEO_FORMAT_BGRx)),
        }
    );

    let pod = spa::pod::Pod::from_bytes(&buf).expect("Failed to parse Pod");
    let mut params = [pod];

    stream.connect(
        spa::utils::Direction::Input,
        Some(node_id),
        pw::stream::StreamFlags::AUTOCONNECT | pw::stream::StreamFlags::MAP_BUFFERS,
        &mut params,
    )?;

    info!("🔗 PipeWire stream connected to node {}. Waiting for first frame...", node_id);

    mainloop.run();
    Ok(())
}
