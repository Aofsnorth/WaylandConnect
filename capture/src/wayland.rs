use anyhow::Result;
use async_trait::async_trait;
use wc_core::traits::ScreenCapturer;
use wc_core::types::{FrameInfo, Resolution, PixelFormat};
use bytes::Bytes;
use tracing::{info, error, instrument};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
// use tokio::sync::mpsc;

// Platform-Specific imports
#[cfg(target_os = "linux")]
use {
    ashpd::desktop::screencast::{CursorMode, Screencast, SourceType, PersistMode},
    ashpd::WindowIdentifier,
    pipewire as pw,
    libspa as spa,
    std::os::unix::io::OwnedFd,
};

// Placeholder for non-linux systems to compile
#[cfg(not(target_os = "linux"))]
pub struct WaylandCapturer {}

#[cfg(not(target_os = "linux"))]
impl Default for WaylandCapturer {
    fn default() -> Self {
        Self {}
    }
}

#[cfg(not(target_os = "linux"))]
#[async_trait]
impl ScreenCapturer for WaylandCapturer {
    async fn start(&mut self) -> wc_core::error::Result<FrameInfo> {
        Err(wc_core::error::WcError::Platform("Not supported on this OS".into()))
    }
    async fn next_frame(&mut self) -> wc_core::error::Result<Bytes> {
        Err(wc_core::error::WcError::Platform("Not supported on this OS".into()))
    }
}

#[cfg(target_os = "linux")]
pub struct WaylandCapturer {
    running: Arc<AtomicBool>,
    // We will use a channel to send frames from the PW thread to the async world
    frame_rx: Option<tokio::sync::mpsc::Receiver<Bytes>>,
    resolution: Resolution,
}

#[cfg(target_os = "linux")]
impl WaylandCapturer {
    pub fn new() -> Self {
        Self {
            running: Arc::new(AtomicBool::new(false)),
            frame_rx: None,
            resolution: Resolution { width: 0, height: 0},
        }
    }
}

#[cfg(target_os = "linux")]
impl Default for WaylandCapturer {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(target_os = "linux")]
#[async_trait]
impl ScreenCapturer for WaylandCapturer {
    #[instrument(skip(self))]
    async fn start(&mut self) -> wc_core::error::Result<FrameInfo> {
        info!("Initializing Wayland Screen Capture...");
        
        let screencast = Screencast::new().await
            .map_err(|e| wc_core::error::WcError::Capture(format!("Failed to connect to Portal: {}", e)))?;
            
        let session = screencast.create_session().await
            .map_err(|e| wc_core::error::WcError::Capture(format!("Failed to create session: {}", e)))?;

        screencast.select_sources(
            &session,
            CursorMode::Metadata,
            SourceType::Monitor | SourceType::Window,
            false,
            None,
            PersistMode::DoNot,
        ).await.map_err(|e| wc_core::error::WcError::Capture(format!("Failed to select sources: {}", e)))?;

        info!("Waiting for user to select screen...");
        let response = screencast.start(&session, &WindowIdentifier::default()).await
            .map_err(|e| wc_core::error::WcError::Capture(format!("Failed to start session: {}", e)))?;

        let streams = response.response()
            .map_err(|e| wc_core::error::WcError::Capture(format!("Invalid response: {}", e)))?;
            
        let stream_info = streams.streams().first().ok_or_else(|| wc_core::error::WcError::Capture("No streams selected".into()))?;
        let node_id = stream_info.pipe_wire_node_id();

        let fd = screencast.open_pipe_wire_remote(&session).await
            .map_err(|e| wc_core::error::WcError::Capture(format!("Failed to open PipeWire remote: {}", e)))?;

        info!("PipeWire Node ID: {}", node_id);

        let (tx, rx) = tokio::sync::mpsc::channel(10);
        self.frame_rx = Some(rx);
        self.running.store(true, Ordering::SeqCst);

        let running_clone = self.running.clone();
        
        // Spawn the dedicated PipeWire thread
        std::thread::spawn(move || {
            if let Err(e) = run_pipewire_loop(fd, node_id, tx, running_clone) {
                error!("PipeWire Loop Error: {}", e);
            }
        });

        // Negotiated resolution (Placeholder for now, implementation should get this from the format event)
        // For a real robust impl, we'd wait for the first format event in the channel or similar.
        self.resolution = Resolution { width: 1920, height: 1080 }; // TODO: Read from PW

        Ok(FrameInfo {
            resolution: self.resolution,
            format: PixelFormat::Bgr888, // Common
            stride: self.resolution.width * 4,
        })
    }

    async fn next_frame(&mut self) -> wc_core::error::Result<Bytes> {
        if let Some(rx) = &mut self.frame_rx {
             rx.recv().await.ok_or_else(|| wc_core::error::WcError::Capture("Stream ended".into()))
        } else {
             Err(wc_core::error::WcError::Capture("Stream not started".into()))
        }
    }
}

// PipeWire Logic (Isolated)
#[cfg(target_os = "linux")]
fn run_pipewire_loop(
    fd: OwnedFd,
    node_id: u32,
    tx: tokio::sync::mpsc::Sender<Bytes>,
    running: Arc<AtomicBool>,
) -> Result<()> {
    pw::init();

    let mainloop = pw::main_loop::MainLoop::new(None)?;
    let context = pw::context::Context::new(&mainloop)?;
    let core = context.connect_fd(fd, None)?;

    let mut props = pw::properties::Properties::new();
    props.insert(*pw::keys::STREAM_MONITOR, "true");

    let stream = pw::stream::Stream::new(&core, "wc-capture", props)?;

    let _listener = stream
        .add_local_listener::<()>()
        .process(move |stream, _user_data| {
            if !running.load(Ordering::SeqCst) {
                 // mainloop.quit(); // If we had access to it, or just return
                 return; 
            }
            
            if let Some(mut buffer) = stream.dequeue_buffer() {
                let datas = buffer.datas_mut();
                if let Some(data) = datas.get_mut(0) {
                     let chunk = data.chunk();
                     let size = chunk.size();
                     let offset = chunk.offset();

                     if let Some(map) = data.data() {
                         if size > 0 {
                             let slice = &map[offset as usize..(offset + size) as usize];
                             // Zero-copy impossible across threads like this without shared mem
                             // Copy the frame
                             let bytes = Bytes::copy_from_slice(slice);
                             // Non-blocking send, drop if full (strategy: latest frame preferred)
                             let _ = tx.blocking_send(bytes); 
                         }
                     }
                }
            }
        })
        .register()?;

     // Negotiate Formats: BGRx (Preferred), RGBx (Fallback)
     let mut params = Vec::new();
     
     // 1. BGRx
     let mut buf1 = Vec::with_capacity(1024);
     let mut b1 = spa::pod::builder::Builder::new(&mut buf1);
     let _ = spa::pod::builder::builder_add!(
        &mut b1,
        Object(
            spa::sys::SPA_TYPE_OBJECT_Format,
            spa::sys::SPA_PARAM_EnumFormat,
        ) {
            spa::sys::SPA_FORMAT_mediaType => Id(spa::utils::Id(spa::sys::SPA_MEDIA_TYPE_video)),
            spa::sys::SPA_FORMAT_mediaSubtype => Id(spa::utils::Id(spa::sys::SPA_MEDIA_SUBTYPE_raw)),
            spa::sys::SPA_FORMAT_VIDEO_format => Id(spa::utils::Id(spa::sys::SPA_VIDEO_FORMAT_BGRx)),
        }
    );
    if let Some(pod) = spa::pod::Pod::from_bytes(&buf1) { params.push(pod); }

     // 2. RGBx
     let mut buf2 = Vec::with_capacity(1024);
     let mut b2 = spa::pod::builder::Builder::new(&mut buf2);
     let _ = spa::pod::builder::builder_add!(
        &mut b2,
        Object(
            spa::sys::SPA_TYPE_OBJECT_Format,
            spa::sys::SPA_PARAM_EnumFormat,
        ) {
            spa::sys::SPA_FORMAT_mediaType => Id(spa::utils::Id(spa::sys::SPA_MEDIA_TYPE_video)),
            spa::sys::SPA_FORMAT_mediaSubtype => Id(spa::utils::Id(spa::sys::SPA_MEDIA_SUBTYPE_raw)),
            spa::sys::SPA_FORMAT_VIDEO_format => Id(spa::utils::Id(spa::sys::SPA_VIDEO_FORMAT_RGBx)),
        }
    );
    if let Some(pod) = spa::pod::Pod::from_bytes(&buf2) { params.push(pod); }

     stream.connect(
        spa::utils::Direction::Input,
        Some(node_id),
        pw::stream::StreamFlags::AUTOCONNECT | pw::stream::StreamFlags::MAP_BUFFERS,
        &mut params,
    )?;

    mainloop.run();
    Ok(())
}
