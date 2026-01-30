use std::sync::Arc;
use tokio::sync::mpsc::Sender;
use crate::protocol::{InputEvent, ControlResponse, DeviceInfo};
use crate::adapter::InputAdapter;
use crate::media_manager::MediaManager;
use crate::pointer_manager::PointerManager;
use crate::app_manager::AppManager;
use crate::screen_streamer::ScreenStreamer;
use crate::session_state::STATE;
use log::{info, error, debug};
use notify_rust::Notification;
use base64::Engine;

#[derive(Clone)]
pub struct EventHandler {
    pub adapter: Arc<dyn InputAdapter + Send + Sync>,
    pub media_manager: Arc<MediaManager>,
    pub pointer_manager: Arc<PointerManager>,
    pub screen_streamer: Arc<ScreenStreamer>,
    pub registry: Arc<crate::server::ConnectionRegistry>,
    pub audio_analyzer: Arc<crate::audio_analyzer::AudioAnalyzer>,
    pub fingerprint: String,
}

impl EventHandler {
    pub async fn handle_event(&self, event: InputEvent, device_ip: &str, connection_addr: &str, tx_h: &Sender<Vec<u8>>) -> bool {
        match event {
            InputEvent::PairRequest { device_name, id, version, auto_reconnect } => {
                self.handle_pair_request(device_name, id, version, auto_reconnect, device_ip, connection_addr, tx_h).await;
                false
            },
            InputEvent::GetStatus => {
                let (devices, zoom_enabled) = {
                    let state = STATE.lock().unwrap();
                    let mut devices: Vec<DeviceInfo> = state.devices.values().cloned().collect();
                    let mirroring_id = state.mirroring_device.clone();
                    for d in devices.iter_mut() {
                        d.is_mirroring = Some(d.id.clone()) == mirroring_id; 
                    }
                    (devices, state.zoom_enabled)
                };
                let response = ControlResponse::StatusResponse { devices, zoom_enabled };
                self.send_packet(&response, tx_h).await;
                false
            },
            InputEvent::ApproveDevice { id } => {
                self.handle_approve_device(id).await;
                false
            },
            InputEvent::RejectDevice { id } => {
                info!("Rejecting device: {}", id);
                let (ip, _was_active) = {
                    let mut state = STATE.lock().unwrap();
                    let dev = state.devices.get_mut(&id);
                    let ip = dev.as_ref().map(|d| d.ip.clone());
                    if let Some(d) = dev {
                        d.status = "Declined".to_string();
                        state.save();
                    }
                    (ip, true) // Assume it might be active
                };
                
                if let Some(ip) = ip {
                     self.registry.send_to(&ip, &ControlResponse::SecurityUpdate { status: "Declined".to_string() }).await;
                }
                {
                    let mut state = STATE.lock().unwrap();
                    state.mirroring_device = None;
                }
                self.screen_streamer.stop(); // Stop mirroring on rejection
                false 
            },
            InputEvent::BlockDevice { id } => {
                self.handle_block_device(id).await;
                false
            },
            InputEvent::UnblockDevice { id } => {
                info!("Unblocking device: {}", id);
                let mut state = STATE.lock().unwrap();
                state.devices.remove(&id);
                state.save();
                false
            },
            InputEvent::Discovery {} => {
                self.handle_discovery(tx_h).await;
                false
            },
            InputEvent::SetZoomEnabled { enabled } => {
                let mut state = STATE.lock().unwrap();
                state.zoom_enabled = enabled;
                state.save();
                self.pointer_manager.set_zoom_enabled(device_ip, enabled);
                false
            },
            InputEvent::SetAutoConnect { enabled } => {
                let mut state = STATE.lock().unwrap();
                state.auto_connect = enabled;
                state.save();
                false
            },
            InputEvent::SetDeviceAutoReconnect { id, enabled } => {
                let mut state = STATE.lock().unwrap();
                if let Some(dev) = state.devices.get_mut(&id) {
                    dev.auto_reconnect = enabled;
                    state.save();
                }
                false
            },
            InputEvent::AutoReconnectResponse { id, accepted } => {
                info!("PC response for auto-reconnect device {}: {}", id, accepted);
                let mut state = STATE.lock().unwrap();
                if let Some(dev) = state.devices.get_mut(&id) {
                    dev.auto_reconnect = accepted;
                    state.save();
                }
                false
            },
            InputEvent::PCStopMirroring { id } => {
                info!("🛑 PC requested stop mirroring for device: {}", id);
                let ip = {
                    let state = STATE.lock().unwrap();
                    state.devices.get(&id).map(|d| d.ip.clone())
                };
                if let Some(ip) = ip {
                    self.registry.send_to(&ip, &ControlResponse::StopMirroring).await;
                }
                {
                    let mut state = STATE.lock().unwrap();
                    state.mirroring_device = None;
                }
                self.screen_streamer.stop();
                false
            },
            InputEvent::RequestAutoReconnect { id } => {
                info!("Device {} requested auto-reconnect", id);
                let (device_id, device_name) = {
                    let state = STATE.lock().unwrap();
                    let dev = state.devices.get(&id);
                    (id.clone(), dev.map(|d| d.name.clone()).unwrap_or_else(|| "Unknown Device".to_string()))
                };

                // Broadcast to dashboards instead of just a system notification
                let req = ControlResponse::AutoReconnectRequest { 
                    device_id, 
                    device_name: device_name.clone() 
                };
                self.registry.broadcast_to_dashboard(&req).await;

                // Also keep notification for redundancy/utility
                let _ = Notification::new()
                    .appname("Wayland Connect")
                    .summary("Auto-Reconnect Request")
                    .body(&format!("'{}' wants to enable auto-reconnect.", device_name))
                    .icon("wayland-connect")
                    .show();
                
                false
            },
            InputEvent::MirrorResponse { device_id, accepted } => {
                self.handle_mirror_response(device_id, accepted).await;
                false
            },
            InputEvent::RegisterDashboard => {
                info!("📡 Received RegisterDashboard from {}", connection_addr);
                self.registry.mark_as_dashboard(connection_addr);
                self.send_packet(&ControlResponse::RegisterResponse { success: true }, tx_h).await;
                false
            },
            _ => {
                let is_trusted = {
                    let state = STATE.lock().unwrap();
                    state.devices.values().any(|d| d.ip == device_ip && d.status == "Trusted")
                };

                if is_trusted {
                    self.handle_trusted_event(event, tx_h, device_ip).await;
                }
                false
            }
        }
    }

    #[allow(clippy::too_many_arguments)]
    async fn handle_pair_request(&self, device_name: String, id: String, version: String, auto_reconnect_req: Option<bool>, device_ip: &str, _connection_addr: &str, tx_h: &Sender<Vec<u8>>) {
        info!("Pair request from: {} ({}) [v{}]", device_name, id, version);
        let server_version = env!("CARGO_PKG_VERSION");
        
        // Simple version check (major.minor)
        if !version.starts_with(server_version.split('.').next().unwrap_or("1")) && !version.is_empty() {
             info!("⚠️ Version mismatch: Client v{}, Server v{}", version, server_version);
             // We can construct a map or a custom struct for pair_response error, 
             // but protocol.rs InputEvent doesn't have a generic "Response" enum for everything.
             // We will stick to the loosely typed "Map" logic via serde_json Value serialized to msgpack 
             // OR define proper response types. 
             // For simplicity in this refactor, let's use a temporary struct or dynamic value.
             // But rmp_serde works best with structs.
             // Let's rely on loose typing for responses if the client supports it, or define structs.
             // Defined `InputEvent` has no `PairResponse`. Protocol definition is needed.
             // Client expects: {"type": "pair_response", "data": ...}
              let resp = ControlResponse::PairResponse {
                 status: "VersionMismatch".to_string(),
                 server_version: server_version.to_string(),
                 server_name: format!("Update required! Server is v{}.", server_version),
                 fingerprint: Some(self.fingerprint.clone()),
              };
             self.send_packet(&resp, tx_h).await;
             return; 
        }

        let (status, should_notify) = {
            let mut state = STATE.lock().unwrap();
            let ip_blocked_or_declined = state.devices.values()
                .find(|d| d.ip == device_ip && (d.status == "Blocked" || d.status == "Declined"))
                .map(|d| d.status.clone());

            if let Some(blocked_status) = ip_blocked_or_declined {
                (blocked_status, false)
            } else if let Some(existing) = state.devices.get_mut(&id) {
                let status;
                let should_notify;
                
                {
                    if let Some(req) = auto_reconnect_req {
                        existing.auto_reconnect = req;
                    }

                    if existing.status == "Trusted" && !existing.auto_reconnect {
                        info!("Auto-reconnect disabled for {}: Requiring re-approval", id);
                        status = "Pending".to_string();
                        should_notify = true;
                    } else {
                        status = existing.status.clone();
                        should_notify = false;
                    }
                }

                if auto_reconnect_req.is_some() {
                    state.save();
                }
                (status, should_notify)
            } else {
                state.devices.insert(id.clone(), DeviceInfo {
                    id: id.clone(),
                    name: device_name.clone(),
                    status: "Pending".to_string(),
                    ip: device_ip.to_string(),
                    auto_reconnect: auto_reconnect_req.unwrap_or(false),
                    is_mirroring: false,
                });
                ("Pending".to_string(), true)
            }
        };

        if should_notify {
            let device_name_c = device_name.clone();
            let id_c = id.clone();
            std::thread::spawn(move || {
                let notification = Notification::new()
                    .appname("Wayland Connect")
                    .summary("New Connection Request")
                    .body(&format!("'{}' wants to connect.", device_name_c))
                    .icon("network-wireless")
                    .action("approve", "Approve")
                    .action("decline", "Decline")
                    .show();
                    
                if let Ok(handle) = notification {
                    handle.wait_for_action(move |action| {
                         let mut state = STATE.lock().unwrap();
                         if let Some(dev) = state.devices.get_mut(&id_c) {
                            match action {
                                "approve" => dev.status = "Trusted".to_string(),
                                "decline" => dev.status = "Declined".to_string(),
                                _ => {}
                            }
                            state.save();
                         }
                    });
                }
            });
        }

        let response = ControlResponse::PairResponse {
            status,
            server_version: server_version.to_string(),
            server_name: get_server_name(),
            fingerprint: Some(self.fingerprint.clone()),
        };
        self.send_packet(&response, tx_h).await;
    }

    async fn handle_approve_device(&self, id: String) {
        info!("Approving device: {}", id);
        let device_name = {
            let mut state = STATE.lock().unwrap();
            if let Some(dev) = state.devices.get_mut(&id) {
                dev.status = "Trusted".to_string();
                let name = dev.name.clone();
                state.save();
                Some(name)
            } else {
                None
            }
        };

        if let Some(name) = device_name {
            let _ = Notification::new()
                .appname("Wayland Connect")
                .summary("Device Paired")
                .body(&format!("{} is now connected.", name))
                .icon("security-high")
                .show();

            // Notify the device itself
            let ip = {
                let state = STATE.lock().unwrap();
                state.devices.get(&id).map(|d| d.ip.clone())
            };
            if let Some(ip) = ip {
                self.registry.send_to(&ip, &ControlResponse::SecurityUpdate { status: "Trusted".to_string() }).await;
            }
        }
    }

    async fn handle_block_device(&self, id: String) {
        info!("Blocking device: {}", id);
        let ip = {
            let mut state = STATE.lock().unwrap();
            if let Some(dev) = state.devices.get_mut(&id) {
                dev.status = "Blocked".to_string();
                let ip = dev.ip.clone();
                state.save();
                Some(ip)
            } else {
                None
            }
        };

        if let Some(ip) = ip {
            // Proactively notify the device so it can show the blocked UI immediately
            self.registry.send_to(&ip, &ControlResponse::SecurityUpdate { status: "Blocked".to_string() }).await;
        }
        {
            let mut state = STATE.lock().unwrap();
            state.mirroring_device = None;
        }
        self.screen_streamer.stop();
    }

    async fn handle_discovery(&self, tx_h: &Sender<Vec<u8>>) {
        let response = ControlResponse::DiscoveryResponse {
            server_name: get_server_name(),
            fingerprint: Some(self.fingerprint.clone()),
        };
        self.send_packet(&response, tx_h).await;
    }

    async fn handle_trusted_event(&self, event: InputEvent, tx_h: &Sender<Vec<u8>>, device_ip: &str) {
        match event {
            InputEvent::MediaControl { action } => {
                let _ = self.media_manager.send_command(&action).await;
            },
            InputEvent::MediaGetStatus => {
                let metadata = self.media_manager.get_current_player_metadata().await;
                let response = ControlResponse::MediaStatus {
                    metadata,
                };
                self.send_packet(&response, tx_h).await;
            },
            InputEvent::PointerData { active, mode, pitch, roll, size, color, zoom_scale, particle_type, stretch_factor, has_image, pulse_speed, pulse_intensity } => {
                debug!("🖱️ Received PointerData: active={}, mode={}, pitch={}, roll={}, speed={}", active, mode, pitch, roll, pulse_speed);
                self.pointer_manager.update(device_ip, active, mode, pitch, roll, size, color, zoom_scale, particle_type, stretch_factor, has_image, pulse_speed, pulse_intensity);
            },
            InputEvent::TestOverlaySequence => {
                self.pointer_manager.run_test_sequence(device_ip);
            },
            InputEvent::PresentationControl { action } => {
                let key = match action.as_str() {
                    "prev" => "PageUp",
                    "next" => "PageDown",
                    _ => return,
                };
                let _ = self.adapter.send_event(InputEvent::KeyPress { key: key.to_string() }).await;
            },
            InputEvent::SetPointerMonitor { monitor } => {
                self.pointer_manager.set_monitor(device_ip, monitor);
            },
            InputEvent::LaunchApp { command } => {
                let apps = AppManager::get_installed_apps();
                if apps.iter().any(|a| a.exec == command) {
                    info!("🚀 Launching verified app: {}", command);
                    let _ = std::process::Command::new("sh").arg("-c").arg(&command).spawn();
                } else {
                    error!("⚠️ Blocked attempt to launch unverified command: {}", command);
                }
            },
            InputEvent::GetApps => {
                let apps = AppManager::get_installed_apps();
                let response = ControlResponse::AppsList { apps };
                self.send_packet(&response, tx_h).await;
            },
            InputEvent::GetMonitors => {
                let monitors = self.fetch_monitors();
                let response = ControlResponse::MonitorsList { monitors };
                self.send_packet(&response, tx_h).await;
            },
            InputEvent::StartMirroring { width, height, fps, monitor } => {
                info!("🖥️ Start Mirroring requested (awaiting approval): {}x{} @ {}fps on monitor {}", width, height, fps, monitor);
                
                let (id, name) = {
                    let mut state = STATE.lock().unwrap();
                    let device = state.devices.values()
                        .find(|d| d.ip == device_ip)
                        .map(|d| (d.id.clone(), d.name.clone()))
                        .unwrap_or_else(|| ("unknown".to_string(), "Unknown Device".to_string()));
                    
                    // Store request for later execution after approval
                    state.pending_mirror = Some(crate::session_state::PendingMirror {
                       _device_id: device.0.clone(),
                       width, height, fps, monitor
                    });
                    device
                };

                let req = ControlResponse::MirrorRequest { device_id: id.clone(), device_name: name.clone() };
                println!("📡 Broadcasting MirrorRequest for {} to dashboards...", name);
                self.registry.broadcast_to_dashboard(&req).await;

                // Show System Notification
                let handler = self.clone();
                let device_id_c = id.clone();
                let device_name_c = name.clone();
                
                std::thread::spawn(move || {
                    let notification = Notification::new()
                        .appname("Wayland Connect")
                        .summary("Screen Share Request")
                        .body(&format!("'{}' wants to mirror their screen.", device_name_c))
                        .icon("video-display")
                        .action("approve", "Approve")
                        .action("decline", "Decline")
                        .show();

                     if let Ok(handle) = notification {
                        handle.wait_for_action(move |action| {
                             let accepted = match action {
                                 "approve" => true,
                                 "decline" => false,
                                 _ => return, 
                             };
                             
                             // Bridge to async using a cloned handler and tokio::spawn
                             let handler_clone = handler.clone();
                             tokio::spawn(async move {
                                 handler_clone.handle_mirror_response(device_id_c.clone(), accepted).await;
                             });
                        });
                     }
                });
            },
            InputEvent::StopMirroring => {
                {
                    let mut state = STATE.lock().unwrap();
                    state.mirroring_device = None;
                }
                self.screen_streamer.stop();
            },
            InputEvent::PointerImage { data } => {
                self.handle_pointer_image(data).await;
            },
            InputEvent::Discovery {} => {
                self.handle_discovery(tx_h).await;
            },
            InputEvent::SetZoomEnabled { enabled } => {
                let mut state = STATE.lock().unwrap();
                state.zoom_enabled = enabled;
                state.save();
                self.pointer_manager.set_zoom_enabled(device_ip, enabled);
            },
            InputEvent::SetAudioSensitivity { value } => {
                self.audio_analyzer.set_sensitivity(value);
            },
            _ => {
                let _ = self.adapter.send_event(event).await;
            }
        }
    }

    async fn handle_pointer_image(&self, data: String) {
        if data.is_empty() {
            let _ = std::fs::remove_file(wc_core::constants::POINTER_IMAGE_PATH);
            if let Ok(socket) = std::net::UdpSocket::bind("127.0.0.1:0") {
                let _ = socket.send_to(b"CLEAR_IMAGE", wc_core::constants::POINTER_OVERLAY_ADDR);
            }
        } else if let Ok(bytes) = base64::engine::general_purpose::STANDARD.decode(data) {
            // Limit pointer image size to 1MB to prevent resource exhaustion
            if bytes.len() > 1024 * 1024 {
                error!("⚠️ Pointer image too large: {} bytes", bytes.len());
                return;
            }
            if let Ok(mut file) = std::fs::File::create(wc_core::constants::POINTER_IMAGE_PATH) {
                let _ = std::io::Write::write_all(&mut file, &bytes);
                if let Ok(socket) = std::net::UdpSocket::bind("127.0.0.1:0") {
                    let _ = socket.send_to(b"RELOAD_IMAGE", wc_core::constants::POINTER_OVERLAY_ADDR);
                }
            }
        }
    }

    async fn send_packet<T: serde::Serialize>(&self, val: &T, tx: &Sender<Vec<u8>>) {
        if let Ok(bin) = rmp_serde::encode::to_vec_named(val) {
            let mut msg = (bin.len() as u32).to_be_bytes().to_vec();
            msg.extend_from_slice(&bin);
            let _ = tx.send(msg).await;
        } else {
            error!("Failed to serialize packet");
        }
    }

    fn fetch_monitors(&self) -> Vec<crate::protocol::MonitorInfo> {
        let output = std::process::Command::new("hyprctl")
            .arg("monitors")
            .arg("-j")
            .output();

        if let Ok(out) = output {
            if let Ok(val) = serde_json::from_slice::<serde_json::Value>(&out.stdout) {
                if let Some(arr) = val.as_array() {
                    return arr.iter().map(|m| {
                        crate::protocol::MonitorInfo {
                            id: m.get("id").and_then(|v| v.as_i64()).unwrap_or(0) as i32,
                            name: m.get("name").and_then(|v| v.as_str()).unwrap_or("Unknown").to_string(),
                            width: m.get("width").and_then(|v| v.as_i64()).unwrap_or(1920) as i32,
                            height: m.get("height").and_then(|v| v.as_i64()).unwrap_or(1080) as i32,
                            x: m.get("x").and_then(|v| v.as_i64()).unwrap_or(0) as i32,
                            y: m.get("y").and_then(|v| v.as_i64()).unwrap_or(0) as i32,
                            focused: m.get("focused").and_then(|v| v.as_bool()).unwrap_or(false),
                        }
                    }).collect();
                }
            }
        }
        vec![]
    }

    async fn handle_mirror_response(&self, device_id: String, accepted: bool) {
        info!("Mirror response for {}: {}", device_id, if accepted { "Accepted" } else { "Declined" });
        
        let device_ip = {
            let state = STATE.lock().unwrap();
            state.devices.get(&device_id).map(|d| d.ip.clone())
        };

        if let Some(ip) = device_ip {
            if accepted {
                // Retrieve pending request params
                let pending = {
                    let mut state = STATE.lock().unwrap();
                    state.pending_mirror.take()
                };

                if let Some(p) = pending {
                    // Notify Android it's allowed
                    let status = ControlResponse::MirrorStatus { 
                        allowed: true, 
                        message: "Access granted by PC".to_string() 
                    };
                    self.registry.send_to(&ip, &status).await;
                    
                    // Start the actual stream with requested params
                    info!("🚀 Starting portal for {}x{} (Monitor {})", p.width, p.height, p.monitor);
                    {
                        let mut state = STATE.lock().unwrap();
                        state.mirroring_device = Some(device_id);
                    }
                    self.pointer_manager.set_monitor(&ip, p.monitor);
                    self.screen_streamer.start(p.width, p.height, p.fps, p.monitor);
                }
            } else {
                // Explicitly clear pending on rejection
                {
                    let mut state = STATE.lock().unwrap();
                    state.pending_mirror = None;
                }
                
                let status = ControlResponse::MirrorStatus { 
                    allowed: false, 
                    message: "Mirroring request declined by PC".to_string() 
                };
                self.registry.send_to(&ip, &status).await;
            }
        }
    }
}

fn get_server_name() -> String {
    std::process::Command::new("hostname").output()
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .ok()
        .or_else(|| std::env::var("HOSTNAME").ok())
        .unwrap_or_else(|| "Linux PC".to_string())
}
