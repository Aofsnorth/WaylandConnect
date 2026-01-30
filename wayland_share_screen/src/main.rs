#![deny(warnings)]
use ashpd::desktop::screencast::{CursorMode, Screencast, SourceType, PersistMode};
use ashpd::WindowIdentifier;
use pipewire as pw;
use std::os::unix::io::OwnedFd;
use log::info;
use libspa as spa;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    env_logger::init_from_env(env_logger::Env::default().default_filter_or("info"));

    info!("🚀 Phase 1: Initiating Wayland Screen Capture...");

    let screencast = Screencast::new().await?;
    let session = screencast.create_session().await?;

    screencast
        .select_sources(
            &session,
            CursorMode::Metadata,
            SourceType::Monitor | SourceType::Window,
            false,
            None,
            PersistMode::DoNot,
        )
        .await?;

    info!("📡 Requesting screen selection from user...");
    // ashpd::desktop::screencast::Screencast::start returns ashpd::desktop::Request<Streams> 
    let request = screencast.start(&session, &WindowIdentifier::default()).await?;
    let streams = request.response()?;

    let stream_info = streams.streams().first().expect("No streams available");
    let node_id = stream_info.pipe_wire_node_id();
    info!("🔗 Attached to PipeWire Node ID: {}", node_id);

    let fd = screencast.open_pipe_wire_remote(&session).await?;
    setup_pipewire(fd, node_id).await?;
    
    Ok(())
}

async fn setup_pipewire(fd: OwnedFd, node_id: u32) -> Result<(), Box<dyn std::error::Error>> {
    pw::init();

    let mainloop = pw::main_loop::MainLoop::new(None)?;
    let context = pw::context::Context::new(&mainloop)?;
    let core = context.connect_fd(fd, None)?;

    let mut props = pw::properties::Properties::new();
    props.insert(*pw::keys::STREAM_MONITOR, "true");

    let stream = pw::stream::Stream::new(
        &core,
        "wayland-share-consumer",
        props,
    )?;

    let _listener = stream
        .add_local_listener::<()>()
        .process(move |stream, _user_data| {
            if let Some(mut buffer) = stream.dequeue_buffer() {
                let datas = buffer.datas_mut();
                if let Some(data) = datas.get_mut(0) {
                    let chunk = data.chunk();
                    let offset = chunk.offset();
                    let size = chunk.size();
                    
                    if let Some(map) = data.data() {
                        let _frame_slice = &map[offset as usize..(offset + size as u32) as usize];
                        // Process frame
                    }
                }
            }
        })
        .register()?;

    // Use libspa builder to create the Pod
    let mut buf = Vec::with_capacity(1024);
    let mut builder = spa::pod::builder::Builder::new(&mut buf);

    let res = spa::pod::builder::builder_add!(
        &mut builder,
        Object(
            spa::sys::SPA_TYPE_OBJECT_Format,
            spa::sys::SPA_PARAM_EnumFormat,
        ) {
            spa::sys::SPA_FORMAT_mediaType => Id(spa::utils::Id(spa::sys::SPA_MEDIA_TYPE_video)),
            spa::sys::SPA_FORMAT_mediaSubtype => Id(spa::utils::Id(spa::sys::SPA_MEDIA_SUBTYPE_raw)),
            spa::sys::SPA_FORMAT_VIDEO_format => Id(spa::utils::Id(spa::sys::SPA_VIDEO_FORMAT_BGRx)),
        }
    );

    if res.is_err() {
        return Err("Failed to build pod".into());
    }

    let pod = spa::pod::Pod::from_bytes(&buf).ok_or("Failed to parse Pod")?;
    let mut params = [pod];

    stream.connect(
        spa::utils::Direction::Input,
        Some(node_id),
        pw::stream::StreamFlags::AUTOCONNECT | pw::stream::StreamFlags::MAP_BUFFERS,
        &mut params,
    )?;

    info!("🏁 PipeWire stream connected. Waiting for frames...");
    mainloop.run();

    Ok(())
}
