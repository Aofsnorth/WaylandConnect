use anyhow::{Result, Context};
use tracing::{info, error, warn};
use wc_config::loader::load_config;
use wc_platform::{LinuxInputInjector, InputInjector, MouseButton, ScrollAxis, KeyCode};
use wc_transport::protocol::Packet;
use wc_processing::AudioAnalyzer;
use tokio::signal;
use tokio::sync::{mpsc, broadcast};

#[tokio::main]
async fn main() -> Result<()> {
    // 1. Initialize Logging
    wc_common::logging::init_logger();

    info!("🚀 Wayland Connect Daemon v0.1.0 Starting...");

    // 2. Load Configuration
    let config = load_config().context("Failed to load configuration")?;
    info!("🔧 Configuration loaded successfully.");

    // 3. Initialize Platform Input (Simulating Mouse/Index)
    info!("⌨️ Initializing Input Injector...");
    let _input = match LinuxInputInjector::new() {
        Ok(inj) => {
            info!("✅ Input Injector ready (/dev/uinput)");
            Some(inj)
        },
        Err(e) => {
            error!("❌ Failed to initialize Input Injector: {}", e);
            warn!("⚠️  Continuing without Input support (Check permissions for /dev/uinput)");
            None
        }
    };

    // 4. Initialize Audio Analysis (Visualizer)
    info!("🎵 Initializing Audio Analyzer...");
    let mut audio = AudioAnalyzer::new();
    if let Err(e) = audio.start() {
        error!("❌ Failed to start Audio Analyzer: {}", e);
    } else {
        info!("✅ Audio Analysis started.");
    }

    // 5. Initialize Screen Capture (Lazy init on connection usually, but we check support here)
    info!("📸 Checking Screen Capture support...");
    match wc_capture::get_capturer().start().await {
        Ok(_) => info!("✅ Screen Capture supported (Test start successful)"),
        Err(e) => warn!("⚠️  Screen Capture verify failed: {} (This might be expected if no session is active yet)", e),
    }

    // 6. Start Transport Server
    let bind_addr = format!("0.0.0.0:{}", config.network.port).parse()?;
    
    // Create communication channels
    let (tx, mut rx) = mpsc::channel(100);
    let (broadcast_tx, _) = broadcast::channel::<Packet>(1024); // Large buffer for video frames
    
    // Start TCP Server (Primary for current Android Client)
    let tcp_server = wc_transport::tcp::TcpServer::new(bind_addr, tx, broadcast_tx.clone());
    let server_handle = tokio::spawn(async move {
        if let Err(e) = tcp_server.run().await {
            error!("🔥 TCP Server crashed: {}", e);
        }
    });

    // Input Processing Loop (from Client to Linux)
    let mut input_injector = _input;
    let b_tx_ctrl = broadcast_tx.clone();
    tokio::spawn(async move {
        while let Some(packet) = rx.recv().await {
            if let Some(ref mut inj) = input_injector {
                match packet {
                    Packet::MouseMove { dx, dy } => {
                        let _ = inj.move_mouse(dx as i32, dy as i32).await;
                    },
                    Packet::MouseClick { button, state: _ } => {
                         let btn = match button.as_str() {
                             "right" => MouseButton::Right,
                             "middle" => MouseButton::Middle,
                             _ => MouseButton::Left,
                         };
                         let _ = inj.click(btn).await;
                    },
                    Packet::MouseScroll { axis: _, amount } => {
                        let _ = inj.scroll(ScrollAxis::Vertical, amount as i32).await;
                    },
                    Packet::KeyPress { key } => {
                        let key_code = match key.as_str() {
                            "Escape" => KeyCode::Escape,
                            "Tab" => KeyCode::Tab,
                            "Enter" => KeyCode::Enter,
                            "Control_L" => KeyCode::ControlLeft,
                            "Alt_L" => KeyCode::AltLeft,
                            "Backspace" => KeyCode::Backspace,
                            "Super_L" => KeyCode::SuperLeft,
                            "space" => KeyCode::Space,
                            k if k.len() == 1 => KeyCode::Char(k.chars().next().unwrap()),
                            _ => KeyCode::Unknown(0),
                        };
                        let _ = inj.key_press(key_code).await;
                    },
                    Packet::Handshake { version, device_name } => {
                        info!("🤝 Handshake from {}: v{}", device_name, version);
                        // Send back ControlResponse (Success / Trusted)
                        let _ = b_tx_ctrl.send(Packet::ControlResponse {
                            status: "success".to_string(),
                            message: "Trusted".to_string(),
                            data: Some(serde_json::json!({
                                "server_name": "WaylandConnect Linux"
                            })),
                        });
                    },
                    Packet::ControlRequest { action, params: _ } => {
                        if action == "media_get_status" {
                             // This is a bit complex because we need to return the status.
                             // For now, we broadcast it to everyone as an update.
                             // In a real app, we might want unicast, but broadcast works for simple discovery.
                             // We'll placeholder the metadata here or fetch from a shared state.
                             let dummy_metadata = serde_json::json!({
                                 "title": "WaylandConnect Audio",
                                 "artist": "System Broadcast",
                                 "status": "Playing",
                                 "position": 0,
                                 "duration": 0,
                             });
                             let _ = b_tx_ctrl.send(Packet::MediaMetadata { metadata: dummy_metadata });
                        }
                    },
                    _ => {}
                }
            }
        }
    });

    // Audio/Spectrum Broadcast Loop
    let b_tx_audio = broadcast_tx.clone();
    let audio_magnitudes = audio.magnitudes.clone();
    tokio::spawn(async move {
        let mut interval = tokio::time::interval(tokio::time::Duration::from_millis(50)); // 20fps for visualizer
        loop {
            interval.tick().await;
            let mags = {
                let lock = audio_magnitudes.lock().unwrap();
                lock.clone()
            };
            if !mags.is_empty() {
                 let low = mags.iter().take(10).sum::<f32>() / 10.0;
                 let mid = mags.iter().skip(10).take(50).sum::<f32>() / 50.0;
                 let high = mags.iter().skip(60).take(100).sum::<f32>() / 100.0;
                 let _ = b_tx_audio.send(Packet::Spectrum { low, mid, high });
            }
        }
    });

    // 7. Start Video Pipeline
    info!("🎥 Starting Video Pipeline...");
    let mut capturer = wc_capture::get_capturer(); 
    let magnifier = wc_processing::Magnifier::new(
        config.video.magnifier_scale, 
        config.video.width, 
        config.video.height
    );
    let mut encoder = wc_codecs::DummyEncoder;
    let mut frame_count = 0;
    
    let _frame_info = capturer.start().await.context("Failed to start screen capture")?;

    let b_tx_video = broadcast_tx.clone();
    let pipeline_handle = tokio::spawn(async move {
        loop {
            match capturer.next_frame().await {
                Ok(bytes) => {
                    let mut final_frame = bytes;
                    
                    if config.video.magnifier_enabled {
                        final_frame = magnifier.process(&final_frame, wc_core::types::Resolution { width: 1920, height: 1080 }, 960, 540);
                    }

                    match wc_core::traits::VideoEncoder::encode(&mut encoder, &final_frame) {
                         Ok(encoded) => {
                             frame_count += 1;
                             
                             // Send to Clients
                             let packet = Packet::VideoFrame {
                                 timestamp: frame_count,
                                 keyframe: true,
                                 data: encoded.to_vec(),
                             };
                             let _ = b_tx_video.send(packet);

                             if frame_count % 60 == 0 {
                                 info!("⚡ Encoded & Broadcasted frame {}", frame_count);
                             }
                         },
                         Err(e) => error!("Encoding failed: {}", e),
                    }
                },
                Err(e) => {
                    error!("Capture error: {}", e);
                    tokio::time::sleep(tokio::time::Duration::from_secs(1)).await;
                }
            }
        }
    });

    // 7. Wait for Shutdown Signal
    info!("✅ Daemon fully running. Press Ctrl+C to stop.");
    match signal::ctrl_c().await {
        Ok(()) => {
            info!("🛑 Shutdown signal received.");
        },
        Err(err) => {
            error!("Unable to listen for shutdown signal: {}", err);
        },
    }

    server_handle.abort();
    pipeline_handle.abort();
    info!("👋 Daemon Shut Down.");

    Ok(())
}
