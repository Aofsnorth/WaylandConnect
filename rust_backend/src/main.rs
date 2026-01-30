
mod protocol;
mod adapter;
mod server;
mod media_manager;
mod pointer_manager;
mod audio_analyzer;
mod app_manager;
mod screen_streamer;
mod session_state;
mod event_handler;
mod tls_utils;

use std::sync::Arc;

use log::info;
use crate::server::InputServer;

#[tokio::main(flavor = "multi_thread", worker_threads = 4)]
async fn main() -> anyhow::Result<()> {
    env_logger::Builder::from_default_env()
        .filter_level(log::LevelFilter::Debug)
        .init();

    info!("----------------------------------------------------------------");
    info!("Starting WaylandConnect Backend (uinput mode)...");

    // 1. Initialize UInput Adapter (Create Virtual Mouse)
    let uinput_adapter = crate::adapter::UInputAdapter::new()?;
    info!("Virtual mouse created successfully.");

    // 2. Wrap in Arc
    let adapter_arc = Arc::new(uinput_adapter);

    // 3. Start Server
    let args: Vec<String> = std::env::args().collect();
    let port: u16 = if args.len() > 1 {
        args[1].parse().unwrap_or(wc_core::constants::DEFAULT_SERVER_PORT)
    } else {
        wc_core::constants::DEFAULT_SERVER_PORT
    };

    let server = InputServer::new(adapter_arc).await?;
    server.run(port).await?;

    Ok(())
}
