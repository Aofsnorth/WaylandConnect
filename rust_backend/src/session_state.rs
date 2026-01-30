use std::collections::HashMap;
use std::fs::File;
use std::io::{Read, Write};
use std::path::PathBuf;
use std::sync::Mutex;
use lazy_static::lazy_static;
use crate::protocol::DeviceInfo;

#[derive(Debug, Clone)]
pub struct PendingMirror {
    pub _device_id: String,
    pub width: u32,
    pub height: u32,
    pub fps: u32,
    pub monitor: i32,
}

#[derive(serde::Serialize, serde::Deserialize)]
pub struct AppState {
    pub devices: HashMap<String, DeviceInfo>,
    #[serde(default)]
    pub media_playing: bool,
    #[serde(default)]
    pub zoom_enabled: bool,
    #[serde(default = "default_true")]
    pub auto_connect: bool,
    #[serde(skip)]
    pub pending_mirror: Option<PendingMirror>,
}

fn default_true() -> bool { true }

impl AppState {
    pub fn load() -> Self {
        let config_dir = get_config_dir();
        let file_path = config_dir.join("devices.json");
        
        if let Ok(mut file) = File::open(file_path) {
            let mut content = String::new();
            if file.read_to_string(&mut content).is_ok() {
                if let Ok(state) = serde_json::from_str::<AppState>(&content) {
                    return state;
                }
            }
        }
        AppState { devices: HashMap::new(), media_playing: false, zoom_enabled: false, auto_connect: true, pending_mirror: None }
    }

    pub fn save(&self) {
        let config_dir = get_config_dir();
        let file_path = config_dir.join("devices.json");
        
        if let Ok(json) = serde_json::to_string_pretty(self) {
            if let Ok(mut file) = File::create(file_path) {
                let _ = file.write_all(json.as_bytes());
            }
        }
    }
}

pub fn get_config_dir() -> PathBuf {
    let mut path = dirs::config_dir().unwrap_or_else(|| PathBuf::from("."));
    path.push(wc_core::constants::CONFIG_DIR_NAME);
    if !path.exists() {
        let _ = std::fs::create_dir_all(&path);
    }
    path
}

lazy_static! {
    pub static ref STATE: Mutex<AppState> = Mutex::new(AppState::load());
}
