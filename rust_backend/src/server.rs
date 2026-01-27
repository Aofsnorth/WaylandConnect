use tokio::net::TcpListener;
use tokio::io::{AsyncBufReadExt, BufReader, AsyncWriteExt};
use crate::protocol::{InputEvent, DeviceInfo, StatusResponse, MediaResponse};
use crate::adapter::InputAdapter;
use crate::media_manager::MediaManager;
use crate::pointer_manager::PointerManager;
use std::sync::Arc;
use log::{info, error, warn};
use notify_rust::Notification;
use std::collections::HashMap;
use std::sync::Mutex;
use lazy_static::lazy_static;

use std::fs::File;
use std::io::{Read, Write};

// State management for devices
#[derive(serde::Serialize, serde::Deserialize)]
struct AppState {
    // Map ID -> DeviceInfo
    devices: HashMap<String, DeviceInfo>,
}

impl AppState {
    fn load() -> Self {
        if let Ok(mut file) = File::open("devices.json") {
            let mut content = String::new();
            if file.read_to_string(&mut content).is_ok() {
                if let Ok(state) = serde_json::from_str::<AppState>(&content) {
                    return state;
                }
            }
        }
        AppState { devices: HashMap::new() }
    }

    fn save(&self) {
        if let Ok(json) = serde_json::to_string_pretty(self) {
            if let Ok(mut file) = File::create("devices.json") {
                let _ = file.write_all(json.as_bytes());
            }
        }
    }
}

lazy_static! {
    static ref STATE: Mutex<AppState> = Mutex::new(AppState::load());
}

pub struct InputServer {
    adapter: Arc<dyn InputAdapter + Send + Sync>,
    media_manager: Arc<MediaManager>,
    pointer_manager: Arc<PointerManager>,
}

impl InputServer {
    pub fn new(adapter: Arc<dyn InputAdapter + Send + Sync>) -> Self {
        Self { 
            adapter,
            media_manager: Arc::new(MediaManager::new()),
            pointer_manager: Arc::new(PointerManager::new()),
        }
    }

    pub async fn run(&self, port: u16) -> anyhow::Result<()> {
        let listener = TcpListener::bind(format!("0.0.0.0:{}", port)).await?;
        info!("Wayland Connect Server listening on 0.0.0.0:{}", port);

        loop {
            let (mut socket, addr) = listener.accept().await?;
            let adapter = self.adapter.clone();
            let media_manager = self.media_manager.clone();
            let pointer_manager = self.pointer_manager.clone();
            
            tokio::spawn(async move {
                let (reader, mut writer) = socket.split();
                let mut lines = BufReader::new(reader).lines();
                let device_ip = addr.ip().to_string();

                while let Ok(Some(line)) = lines.next_line().await {
                    match serde_json::from_str::<InputEvent>(&line) {
                        Ok(event) => {
                            match event {
                                InputEvent::PairRequest { device_name, id } => {
                                    info!("Pair request from: {} ({})", device_name, id);
                                    
                                    let (status, should_notify) = {
                                        let mut state = STATE.lock().unwrap();
                                        
                                        // 1. Check if this IP is already blocked/declined (Nuclear Spam Protection)
                                        let ip_blocked_or_declined = state.devices.values()
                                            .find(|d| d.ip == device_ip && (d.status == "Blocked" || d.status == "Declined"))
                                            .map(|d| d.status.clone());

                                        if let Some(blocked_status) = ip_blocked_or_declined {
                                            info!("Rejecting request from {} due to existing {} status on IP", device_ip, blocked_status);
                                            (blocked_status, false)
                                        } else if let Some(existing) = state.devices.get(&id) {
                                            // 2. Exact ID match
                                            (existing.status.clone(), false)
                                        } else {
                                            // 3. ID match failed, check if we have a dangling entry for this IP (e.g. reinstall) to migrate
                                            let same_ip_entry = state.devices.iter()
                                                .find(|(_, dev)| dev.ip == device_ip)
                                                .map(|(k, v)| (k.clone(), v.clone()));
                                            
                                            if let Some((old_id, old_dev)) = same_ip_entry {
                                                // MIGRATING OLD IP DATA TO NEW ID
                                                state.devices.remove(&old_id);
                                                let new_status = old_dev.status; // Could be Trusted/Pending
                                                
                                                state.devices.insert(id.clone(), DeviceInfo {
                                                    id: id.clone(),
                                                    name: device_name.clone(),
                                                    status: new_status.clone(),
                                                    ip: device_ip.clone(),
                                                });
                                                
                                                info!("Migrated device IP {}: {} -> {} (Status: {})", device_ip, old_id, id, new_status);
                                                (new_status, false) 
                                            } else {
                                                // 4. Truly NEW request
                                                state.devices.insert(id.clone(), DeviceInfo {
                                                    id: id.clone(),
                                                    name: device_name.clone(),
                                                    status: "Pending".to_string(),
                                                    ip: device_ip.clone(),
                                                });
                                                ("Pending".to_string(), true)
                                            }
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
                                                    match action {
                                                        "approve" => {
                                                            info!("Notification Action: Approving {}", id_c);
                                                            let mut state = STATE.lock().unwrap();
                                                            if let Some(dev) = state.devices.get_mut(&id_c) {
                                                                dev.status = "Trusted".to_string();
                                                                state.save();
                                                            }
                                                        },
                                                        "decline" => {
                                                            info!("Notification Action: Declining {}", id_c);
                                                            let mut state = STATE.lock().unwrap();
                                                            if let Some(dev) = state.devices.get_mut(&id_c) {
                                                                dev.status = "Declined".to_string();
                                                                state.save();
                                                            }
                                                        },
                                                        _ => {}
                                                    }
                                                });
                                            }
                                        });
                                    }

                                    // Send Status Response back to Android
                                    let response = serde_json::json!({
                                        "type": "pair_response",
                                        "data": {
                                            "status": status
                                        }
                                    });
                                    
                                    if let Ok(json) = serde_json::to_string(&response) {
                                        let _ = writer.write_all(format!("{}\n", json).as_bytes()).await;
                                    }

                                    // If Declined or Blocked, close the connection immediately to stop any polling spam
                                    if status == "Declined" || status == "Blocked" {
                                        let _ = writer.flush().await;
                                        return; 
                                    }
                                },
                                InputEvent::GetStatus => {
                                    // Management App asking for list
                                    let devices = {
                                        let state = STATE.lock().unwrap();
                                        state.devices.values().cloned().collect()
                                    };
                                    let response = StatusResponse { devices };
                                    if let Ok(json) = serde_json::to_string(&response) {
                                        let _ = writer.write_all(format!("{}\n", json).as_bytes()).await;
                                    }
                                },
                                InputEvent::ApproveDevice { id } => {
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
                                        // Notify user
                                        let _ = Notification::new()
                                            .appname("Wayland Connect")
                                            .summary("Device Paired")
                                            .body(&format!("{} is now connected.", name))
                                            .icon("security-high")
                                            .show();
                                    }
                                },
                                InputEvent::RejectDevice { id } => {
                                    info!("Rejecting device: {}", id);
                                    let mut state = STATE.lock().unwrap();
                                    if let Some(dev) = state.devices.get_mut(&id) {
                                        dev.status = "Declined".to_string();
                                        state.save();
                                    }
                                },
                                InputEvent::BlockDevice { id } => {
                                    info!("Blocking device: {}", id);
                                    let mut state = STATE.lock().unwrap();
                                    if let Some(dev) = state.devices.get_mut(&id) {
                                        dev.status = "Blocked".to_string();
                                    } else {
                                         // Create a placeholder if trying to block a non-existent (or removed) ID
                                         state.devices.insert(id.clone(), DeviceInfo {
                                             id: id.clone(),
                                             name: "Blocked Device".to_string(),
                                             status: "Blocked".to_string(),
                                             ip: "Unknown".to_string(),
                                         });
                                    }
                                    state.save();
                                },
                                InputEvent::UnblockDevice { id } => {
                                    info!("Unblocking device: {}", id);
                                    let mut state = STATE.lock().unwrap();
                                    state.devices.remove(&id);
                                    state.save();
                                },
                                _ => {
                                    let is_trusted = {
                                        let state = STATE.lock().unwrap();
                                        state.devices.values().any(|d| d.ip == device_ip && d.status == "Trusted")
                                    };

                                    if is_trusted {
                                        match event {
                                            InputEvent::MediaControl { action } => {
                                                if let Err(e) = media_manager.send_command(&action).await {
                                                    error!("Media control error: {}", e);
                                                }
                                            },
                                            InputEvent::MediaGetStatus => {
                                                let metadata = media_manager.get_current_player_metadata().await;
                                                let resp = MediaResponse { metadata };
                                                if let Ok(json) = serde_json::to_string(&resp) {
                                                    let _ = writer.write_all(format!("{}\n", json).as_bytes()).await;
                                                }
                                            },
                                            InputEvent::PointerData { active, mode, pitch, roll, size } => {
                                                println!("📍 PointerData from {}: active={}, mode={}, pitch={:.2}, roll={:.2}, size={:.2}", device_ip, active, mode, pitch, roll, size);
                                                pointer_manager.update(active, mode, pitch, roll, size);
                                            },
                                            InputEvent::PresentationControl { action } => {
                                                // Send keyboard arrow keys for slide control
                                                use crate::protocol::InputEvent;
                                                let key_event = match action.as_str() {
                                                    "prev" => InputEvent::KeyPress { key: "Left".to_string() },
                                                    "next" => InputEvent::KeyPress { key: "Right".to_string() },
                                                    _ => continue,
                                                };
                                                if let Err(e) = adapter.send_event(key_event).await {
                                                    error!("Failed to send presentation control: {}", e);
                                                }
                                            },
                                            InputEvent::SetPointerMonitor { monitor } => {
                                                info!("🖥️ SetPointerMonitor: monitor={}", monitor);
                                                pointer_manager.set_monitor(monitor);
                                            },
                                            _ => {

                                                if let Err(e) = adapter.send_event(event).await {
                                                    error!("Failed to forward event: {}", e);
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        Err(e) => error!("JSON Error: {}", e),
                    }
                }

                // Disconnect handling
                let mut state = STATE.lock().unwrap();
                let mut to_remove = Vec::new();
                for (id, dev) in state.devices.iter() {
                    // Remove "Pending" devices from the list when they disconnect so they don't linger in Dashboard
                    if dev.ip == device_ip && dev.status == "Pending" {
                        to_remove.push(id.clone());
                    }
                }
                for id in to_remove {
                    state.devices.remove(&id);
                    info!("Removed disconnected pending device from activity: {}", id);
                }
                state.save();
            });
        }
    }
}
