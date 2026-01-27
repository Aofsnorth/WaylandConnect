mod protocol;
mod adapter;
mod server;
mod media_manager;
mod pointer_manager;

use std::sync::Arc;
use env_logger;
use log::info;
use crate::server::InputServer;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Initialize Logger to File
    use std::fs::OpenOptions;
    let log_file = OpenOptions::new()
        .create(true)
        .write(true)
        .append(true)
        .open("/tmp/wayland_connect_backend.log")
        .unwrap();
    
    let target = env_logger::Target::Pipe(Box::new(log_file));
    env_logger::Builder::from_default_env()
        .target(target)
        .filter_level(log::LevelFilter::Info)
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
        args[1].parse().unwrap_or(12345)
    } else {
        12345
    };

    let server = InputServer::new(adapter_arc);
    server.run(port).await?;

    Ok(())
}
