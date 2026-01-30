use tokio::net::TcpListener;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio_rustls::TlsAcceptor;
use crate::protocol::InputEvent;
use crate::adapter::InputAdapter;
use crate::media_manager::MediaManager;
use crate::pointer_manager::PointerManager;
use crate::audio_analyzer::AudioAnalyzer;
use crate::screen_streamer::ScreenStreamer;
use crate::session_state::STATE;
use crate::event_handler::EventHandler;
use std::sync::Arc;
use log::{info, error, debug};
use std::collections::HashMap;
use tokio::sync::mpsc::Sender;
use std::sync::Mutex as StdMutex;

pub struct ConnectionRegistry {
    pub channels: StdMutex<HashMap<String, (Sender<Vec<u8>>, bool)>>,
}

impl ConnectionRegistry {
    pub fn new() -> Self {
        Self { channels: StdMutex::new(HashMap::new()) }
    }

    pub fn add(&self, addr: String, tx: Sender<Vec<u8>>) {
        let mut channels = self.channels.lock().unwrap();
        channels.insert(addr, (tx, false)); // Default to not a dashboard
    }

    pub fn mark_as_dashboard(&self, addr: &str) {
        let mut channels = self.channels.lock().unwrap();
        if let Some(entry) = channels.get_mut(addr) {
            entry.1 = true;
            info!("🖥️  Connection {} marked as DASHBOARD", addr);
        }
    }

    pub fn remove(&self, addr: &str) {
        let mut channels = self.channels.lock().unwrap();
        channels.remove(addr);
    }

    pub async fn broadcast_to_dashboard(&self, packet: &crate::protocol::ControlResponse) {
        let bin = match rmp_serde::encode::to_vec_named(packet) {
            Ok(b) => b,
            Err(_) => return,
        };
        let mut msg = (bin.len() as u32).to_be_bytes().to_vec();
        msg.extend_from_slice(&bin);

        let targets: Vec<Sender<Vec<u8>>> = {
            let channels = self.channels.lock().unwrap();
            let found = channels.iter()
                .filter(|(_, (_, is_dashboard))| *is_dashboard)
                .map(|(_, (tx, _))| tx.clone())
                .collect::<Vec<_>>();
            
            info!("📡 Dashboard broadcast: Found {} registered dashboard(s) out of {} total connections. Active Addrs: {:?}", 
                found.len(), channels.len(), channels.keys().collect::<Vec<_>>());
            found
        };

        for tx in targets {
            info!("   -> Sending MirrorRequest to registered dashboard");
            let _ = tx.send(msg.clone()).await;
        }
    }

    pub async fn send_to(&self, key: &str, packet: &crate::protocol::ControlResponse) {
        let bin = match rmp_serde::encode::to_vec_named(packet) {
            Ok(b) => b,
            Err(_) => return,
        };
        let mut msg = (bin.len() as u32).to_be_bytes().to_vec();
        msg.extend_from_slice(&bin);

        let targets = {
            let channels = self.channels.lock().unwrap();
            // Try direct match first (for connection_addr)
            if let Some((tx, _)) = channels.get(key) {
                vec![tx.clone()]
            } else {
                // Try matching by IP (key might be just IP)
                channels.iter()
                    .filter(|(addr, _)| addr.starts_with(key))
                    .map(|(_, (tx, _))| tx.clone())
                    .collect::<Vec<_>>()
            }
        };

        for tx in targets {
            let _ = tx.send(msg.clone()).await;
        }
    }
}

pub struct InputServer {
    adapter: Arc<dyn InputAdapter + Send + Sync>,
    media_manager: Arc<MediaManager>,
    pointer_manager: Arc<PointerManager>,
    audio_analyzer: Arc<AudioAnalyzer>,
    screen_streamer: Arc<ScreenStreamer>,
    registry: Arc<ConnectionRegistry>,
}

impl InputServer {
    pub async fn new(adapter: Arc<dyn InputAdapter + Send + Sync>) -> anyhow::Result<Self> {
        let audio_analyzer = Arc::new(AudioAnalyzer::new());
        audio_analyzer.start();
        
        let pointer_manager = Arc::new(PointerManager::new());
        let mut screen_streamer = ScreenStreamer::new();
        screen_streamer.set_pointer_manager(pointer_manager.clone());
        
        Ok(Self { 
            adapter,
            media_manager: Arc::new(MediaManager::new().await?),
            pointer_manager,
            audio_analyzer,
            screen_streamer: Arc::new(screen_streamer),
            registry: Arc::new(ConnectionRegistry::new()),
        })
    }

    pub async fn run(&self, port: u16) -> anyhow::Result<()> {
        let (tls_config, fingerprint) = crate::tls_utils::load_tls_config()?;
        let acceptor = TlsAcceptor::from(tls_config);
        
        let listener = TcpListener::bind(format!("0.0.0.0:{}", port)).await?;
        info!("🔐 TLS Wayland Connect Server (Binary Mode) listening on 0.0.0.0:{}", port);

        let handler = Arc::new(EventHandler {
            adapter: self.adapter.clone(),
            media_manager: self.media_manager.clone(),
            pointer_manager: self.pointer_manager.clone(),
            screen_streamer: self.screen_streamer.clone(),
            registry: self.registry.clone(),
            audio_analyzer: self.audio_analyzer.clone(),
            fingerprint: fingerprint.clone(),
        });

        // UDP Discovery Responder
        let fp_c = fingerprint.clone();
        tokio::spawn(async move {
            let socket = match std::net::UdpSocket::bind(wc_core::constants::DISCOVERY_ADDR) {
                Ok(s) => s,
                Err(e) => {
                    log::error!("❌ Failed to bind UDP Discovery socket: {}", e);
                    return;
                }
            };
            socket.set_broadcast(true).unwrap();
            let mut buf = [0u8; 1024];
            log::info!("📡 UDP Discovery Responder active on port {}", wc_core::constants::DISCOVERY_PORT);
            
            loop {
                if let Ok((amt, src)) = socket.recv_from(&mut buf) {
                    let msg = String::from_utf8_lossy(&buf[..amt]);
                    if msg.contains("discovery") {
                        let response = crate::protocol::ControlResponse::DiscoveryResponse {
                            server_name: get_server_host_name(),
                            fingerprint: Some(fp_c.clone()),
                        };
                        if let Ok(bin) = rmp_serde::encode::to_vec_named(&response) {
                             let mut packet = (bin.len() as u32).to_be_bytes().to_vec();
                             packet.extend_from_slice(&bin);
                             let _ = socket.send_to(&packet, src);
                        }
                    }
                }
            }
        });

        loop {
            let (socket, addr) = listener.accept().await?;
            let handler = handler.clone();
            let acceptor = acceptor.clone();
            let audio_analyzer = self.audio_analyzer.clone();
            let screen_streamer = self.screen_streamer.clone();
            let media_manager = self.media_manager.clone();
            let registry = self.registry.clone();
            
            tokio::spawn(async move {
                let socket = match acceptor.accept(socket).await {
                    Ok(s) => s,
                    Err(e) => {
                        error!("❌ TLS Handshake failed: {}", e);
                        return;
                    }
                };

                let _ = socket.get_ref().0.set_nodelay(true); // Disable Nagle before splitting - critical for real-time audio!
                let (mut reader, mut writer) = tokio::io::split(socket);
                let device_addr = addr.to_string(); // Use IP:Port for absolute uniqueness
                
                let mut device_ip = addr.ip().to_string();
                if device_ip.starts_with("::ffff:") {
                    device_ip = device_ip.replace("::ffff:", "");
                }
                if device_ip == "::1" {
                    device_ip = "127.0.0.1".to_string();
                }
                let (tx, mut rx) = tokio::sync::mpsc::channel::<Vec<u8>>(64); // Increased buffer to handle audio + frame bursts
                info!("🔌 New connection from: {}", device_addr);
                registry.add(device_addr.clone(), tx.clone());
                
                // Writer Task
                tokio::spawn(async move {
                    while let Some(msg) = rx.recv().await {
                        if writer.write_all(&msg).await.is_err() { break; }
                        let _ = writer.flush().await;
                    }
                });

                // Metadata Task
                let audio_analyzer_m = audio_analyzer.clone();
                let media_manager_m = media_manager.clone();
                let tx_m = tx.clone();
                tokio::spawn(async move {
                    loop {
                        if let Some(metadata) = media_manager_m.get_current_player_metadata().await {
                            audio_analyzer_m.set_target_app(Some(metadata.player_name.clone()));
                            
                            // Update global playing state
                            {
                                let mut state = STATE.lock().unwrap();
                                state.media_playing = metadata.status == "Playing";
                            }

                            let pkt = crate::protocol::ControlResponse::MediaStatus { metadata: Some(metadata) };
                            if let Ok(bin) = rmp_serde::encode::to_vec_named(&pkt) {
                                let mut msg = (bin.len() as u32).to_be_bytes().to_vec();
                                msg.extend_from_slice(&bin);
                                if let Err(_) = tx_m.send(msg).await { break; }
                            }
                        }
                        tokio::time::sleep(tokio::time::Duration::from_secs(3)).await;
                    }
                });

                // Spectrum Task (Fast & High Priority)
                let tx_s = tx.clone();
                let device_ip_s = device_ip.clone();
                let audio_analyzer_s = audio_analyzer.clone();
                tokio::spawn(async move {
                    let mut was_playing = true;
                    loop {
                        tokio::time::sleep(tokio::time::Duration::from_millis(16)).await;
                        let (is_trusted, media_playing) = {
                            let state = STATE.lock().unwrap();
                            let trusted = state.devices.values().any(|d| d.ip == device_ip_s && d.status == "Trusted");
                            (trusted, state.media_playing)
                        };
                        if !is_trusted { continue; }

                        if !media_playing {
                            if was_playing {
                                let spectrum_pkt = crate::protocol::BinaryPacket::Spectrum { bands: vec![0.0; 7] };
                                if let Ok(bin) = rmp_serde::encode::to_vec_named(&spectrum_pkt) {
                                    let mut msg = (bin.len() as u32).to_be_bytes().to_vec();
                                    msg.extend_from_slice(&bin);
                                    let _ = tx_s.try_send(msg);
                                }
                                was_playing = false;
                            }
                            continue;
                        }
                        
                        was_playing = true;
                        let bands = audio_analyzer_s.get_levels();
                        let spectrum_pkt = crate::protocol::BinaryPacket::Spectrum { bands };
                        if let Ok(bin) = rmp_serde::encode::to_vec_named(&spectrum_pkt) {
                            let mut msg = (bin.len() as u32).to_be_bytes().to_vec();
                            msg.extend_from_slice(&bin);
                            let _ = tx_s.try_send(msg); 
                        }
                    }
                });

                // Screen Frame Task (Lower Priority, Heavy)
                let tx_f = tx.clone();
                let device_ip_f = device_ip.clone();
                let screen_streamer_f = screen_streamer.clone();
                tokio::spawn(async move {
                    let mut last_frame_data: Option<Vec<u8>> = None;
                    let mut trust_check_counter = 0;
                    let mut is_trusted = false;

                    loop {
                        tokio::time::sleep(tokio::time::Duration::from_millis(16)).await;
                        
                        // Check trust status every ~1 second (60 iterations) to save CPU
                        if trust_check_counter == 0 {
                            is_trusted = {
                                let state = STATE.lock().unwrap();
                                state.devices.values().any(|d| d.ip == device_ip_f && d.status == "Trusted")
                            };
                            trust_check_counter = 60;
                        }
                        trust_check_counter -= 1;
                        
                        if !is_trusted { continue; }

                        if let Some(frame) = screen_streamer_f.get_latest_frame() {
                            let is_new = match &last_frame_data {
                                Some(last) => {
                                    // Check if size changed or if start/mid/end bytes changed
                                    last.len() != frame.len() || 
                                    last[..last.len().min(64)] != frame[..frame.len().min(64)] ||
                                    last[last.len()/2..last.len()/2+64.min(last.len()/2)] != frame[frame.len()/2..frame.len()/2+64.min(frame.len()/2)]
                                },
                                None => true,
                            };
                            
                            if is_new {
                                let frame_pkt = crate::protocol::BinaryPacket::Frame { b: frame.clone() };
                                if let Ok(bin) = rmp_serde::encode::to_vec_named(&frame_pkt) {
                                    let mut msg = (bin.len() as u32).to_be_bytes().to_vec();
                                    msg.extend_from_slice(&bin);
                                    
                                    // Use try_send to avoid blocking the loop if network is slow
                                    // Slow network should result in dropped frames, not lag.
                                    match tx_f.try_send(msg) {
                                        Ok(_) => {
                                            if last_frame_data.is_none() {
                                                info!("🖼️ [SIGNAL] First frame successfully transmitted to client at {}! (Size: {} bytes)", device_ip_f, frame.len());
                                            }
                                            last_frame_data = Some(frame);
                                        }
                                        Err(tokio::sync::mpsc::error::TrySendError::Full(_)) => {
                                            debug!("⚠️ [SIGNAL] Frame dropped for {}: channel full", device_ip_f);
                                        }
                                        Err(tokio::sync::mpsc::error::TrySendError::Closed(_)) => {
                                            error!("❌ [SIGNAL] Transmission channel closed for {}", device_ip_f);
                                            break;
                                        }
                                    }
                                }
                            }
                        }
                    }
                });

                // Reader Loop
                let mut len_buf = [0u8; 4];
                loop {
                    match reader.read_exact(&mut len_buf).await {
                        Ok(_) => {
                            let len = u32::from_be_bytes(len_buf) as usize;
                            if len > 10 * 1024 * 1024 { break; }
                            let mut payload = vec![0u8; len];
                            if reader.read_exact(&mut payload).await.is_ok() {
                                if let Ok(event) = rmp_serde::from_slice::<InputEvent>(&payload) {
                                     if handler.handle_event(event, &device_ip, &device_addr, &tx).await { break; }
                                }
                            } else { break; }
                        }
                        Err(_) => break,
                    }
                }

                let mut state = STATE.lock().unwrap();
                state.devices.retain(|_, d| !(d.ip == device_ip && d.status == "Pending"));
                state.save();
                registry.remove(&device_addr);
                screen_streamer.stop();
            });
        }
    }
}

fn get_server_host_name() -> String {
    std::process::Command::new("hostname").output()
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .ok()
        .or_else(|| std::env::var("HOSTNAME").ok())
        .unwrap_or_else(|| "WaylandConnect PC".to_string())
}
