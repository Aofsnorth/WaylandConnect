use ashpd::desktop::screencast::{CursorMode, Screencast, SourceType};
use ashpd::desktop::PersistMode;
use ashpd::WindowIdentifier;
use pipewire as pw;
use libspa as spa;
use std::os::unix::io::OwnedFd;
use std::sync::{Arc, Mutex};
use std::sync::atomic::{AtomicBool, Ordering};
use log::{info, error};



#[allow(clippy::type_complexity)]
pub struct ScreenCapture {
    last_frame: Arc<Mutex<Option<(Vec<u8>, u32, u32)>>>, // Data, Width, Height
    exclusion_rect: Arc<Mutex<Option<(f64, f64, f64, f64)>>>, // nx, ny, nw, nh (Normalized)
    running: Arc<AtomicBool>,
}

impl ScreenCapture {
    pub fn new() -> Self {
        Self {
            last_frame: Arc::new(Mutex::new(None)),
            exclusion_rect: Arc::new(Mutex::new(None)),
            running: Arc::new(AtomicBool::new(false)),
        }
    }

    pub fn get_latest_frame(&self) -> Option<(Vec<u8>, u32, u32)> {
        self.last_frame.lock().unwrap().clone()
    }

    pub fn set_exclusion_rect(&self, rect: Option<(f64, f64, f64, f64)>) {
        if let Ok(mut r) = self.exclusion_rect.lock() {
            *r = rect;
        }
    }

    pub fn start(&self) {
        if self.running.load(Ordering::SeqCst) {
            return;
        }
        self.running.store(true, Ordering::SeqCst);

        let frame_store = self.last_frame.clone();
        let excl_store = self.exclusion_rect.clone();
        let running_c = self.running.clone();

        std::thread::spawn(move || {
            use std::io::Write;
            let mut stdout = std::io::stdout();

            println!("🚀 [Capture] Thread started.");
            let _ = stdout.flush();

            let rt = tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()
                .unwrap();

            let result = rt.block_on(async {
                println!("🔍 [Capture] Creating Portal proxy...");
                let _ = std::io::stdout().flush();
                let screencast = Screencast::new().await?;
                
                println!("🔍 [Capture] Creating session...");
                let _ = std::io::stdout().flush();
                let session = screencast.create_session().await?;

                println!("🔍 [Capture] Selecting sources (Monitor, Hidden cursor)...");
                screencast.select_sources(
                    &session,
                    CursorMode::Hidden,
                    SourceType::Monitor.into(), 
                    false,
                    None,
                    PersistMode::DoNot,
                ).await?;

                println!("🔍 [Capture] Starting session (Waiting for User/Portal)...");
                let request = screencast.start(&session, &WindowIdentifier::default()).await?;
                
                println!("🔍 [Capture] Getting PipeWire stream info...");
                let streams = request.response()?;
                let stream_info = streams.streams().first().ok_or("No streams available")?;
                let node_id = stream_info.pipe_wire_node_id();
                
                println!("🔍 [Capture] Opening PipeWire remote FD...");
                let fd = screencast.open_pipe_wire_remote(&session).await?;
                
                println!("🔍 [Capture] FD obtained: {:?}", fd);
                Ok::<(OwnedFd, u32), Box<dyn std::error::Error>>((fd, node_id))
            });

            match result {
                Ok((fd, node_id)) => {
                    println!("✅ [Capture] Portal approved! Session established. Node ID: {}", node_id);
                    info!("✅ [Capture] Session established. Node ID: {}", node_id);
                    if let Err(e) = run_pipewire_loop(fd, node_id, frame_store, excl_store, running_c) {
                        error!("❌ [Capture] PipeWire Loop Error: {}", e);
                    }
                },
                Err(e) => {
                    println!("❌ [Capture] Failed to start session: {}", e);
                    error!("❌ [Capture] Failed to start session: {}", e);
                    running_c.store(false, Ordering::SeqCst);
                }
            }
        });
    }
}

#[allow(clippy::too_many_arguments, clippy::type_complexity)]
fn run_pipewire_loop(
    fd: OwnedFd,
    node_id: u32,
    frame_store: Arc<Mutex<Option<(Vec<u8>, u32, u32)>>>,
    excl_store: Arc<Mutex<Option<(f64, f64, f64, f64)>>>,
    running: Arc<AtomicBool>,
) -> Result<(), Box<dyn std::error::Error>> {
    pw::init();

    let mainloop = pw::main_loop::MainLoop::new(None)?;
    let context = pw::context::Context::new(&mainloop)?;
    let core = context.connect_fd(fd, None)?;

    let mut props = pw::properties::Properties::new();
    props.insert(*pw::keys::STREAM_MONITOR, "true");

    let stream = pw::stream::Stream::new(&core, "pointer-magnifier", props)?;

    let _listener = stream
        .add_local_listener::<()>()
        .process(move |stream, _user_data| {
            if !running.load(Ordering::SeqCst) { return; }

            if let Some(mut buffer) = stream.dequeue_buffer() {
                let datas = buffer.datas_mut();
                if let Some(data) = datas.get_mut(0) {
                    let chunk = data.chunk();
                    let offset = chunk.offset();
                    let size = chunk.size();
                    let stride = chunk.stride();

                    if let Some(map) = data.data() {
                        if size > 0 {
                            let frame_slice = &map[offset as usize..(offset + size) as usize];
                            
                            let width = stride as u32 / 4; 
                            let height = size / stride as u32;

                            if let Ok(mut f_guard) = frame_store.lock() {
                                // Initialize or resize if needed
                                if f_guard.is_none() || f_guard.as_ref().unwrap().1 != width || f_guard.as_ref().unwrap().2 != height {
                                    println!("🎬 [Capture] Initializing/Resizing Buffer: {}x{}", width, height);
                                    *f_guard = Some((frame_slice.to_vec(), width, height));
                                } else if let Some((ref mut clean_vec, _cw, _ch)) = *f_guard {
                                    // RECONSTRUCTION LOOP
                                    // Copy everything EXCEPT the exclusion rect
                                    let excl = *excl_store.lock().unwrap();
                                    
                                    if let Some((nx, ny, nw, nh)) = excl {
                                        let src_stride = (width * 4) as usize;
                                        
                                        // Convert normalized to pixel coordinates
                                        let ex = (nx * width as f64) as i32;
                                        let ey = (ny * height as f64) as i32;
                                        let ew = (nw * width as f64) as i32;
                                        let eh = (nh * height as f64) as i32;

                                        for y in 0..height {
                                            let is_y_in = y as i32 >= ey && (y as i32) < (ey + eh);
                                            let row_start = y as usize * src_stride;
                                            
                                            if !is_y_in {
                                                // Whole row is safe
                                                clean_vec[row_start..row_start + src_stride].copy_from_slice(&frame_slice[row_start..row_start + src_stride]);
                                            } else {
                                                // Partial row: optimize with slice copies
                                                // Copy pixels BEFORE ex
                                                let left_end = ex.max(0).min(width as i32) as usize * 4;
                                                if left_end > 0 {
                                                    clean_vec[row_start..row_start + left_end].copy_from_slice(&frame_slice[row_start..row_start + left_end]);
                                                }
                                                
                                                // Skip [ex, ex+ew)
                                                
                                                // Copy pixels AFTER ex+ew
                                                let right_start = (ex + ew).max(0).min(width as i32) as usize * 4;
                                                if right_start < src_stride {
                                                    clean_vec[row_start + right_start..row_start + src_stride].copy_from_slice(&frame_slice[row_start + right_start..row_start + src_stride]);
                                                }
                                            }
                                        }
                                    } else {
                                        // No exclusion: Fast full copy
                                        clean_vec.copy_from_slice(frame_slice);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        })
        .register()?;

    // Negotiate BGRx (standard for Wayland capture)
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

    mainloop.run();
    Ok(())
}
