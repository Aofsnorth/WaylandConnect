use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize, Debug)]
#[serde(tag = "type", content = "data")]
pub enum InputEvent {
    #[serde(rename = "move")]
    Move { dx: f64, dy: f64 },
    #[serde(rename = "click")]
    Click { button: String },
    #[serde(rename = "scroll")]
    Scroll { dy: f64 },
    #[serde(rename = "keypress")]
    KeyPress { key: String },
    #[serde(rename = "pair_request")]
    PairRequest { device_name: String, id: String },
    
    // Management Commands
    #[serde(rename = "get_status")]
    GetStatus,
    #[serde(rename = "approve_device")]
    ApproveDevice { id: String },
    #[serde(rename = "reject_device")] // Clean up pending
    RejectDevice { id: String },
    #[serde(rename = "block_device")]
    BlockDevice { id: String },
    #[serde(rename = "unblock_device")] // Alias for approve or remove from block list
    UnblockDevice { id: String },

    // Media Controls
    #[serde(rename = "media_control")]
    MediaControl { action: String }, // "play", "pause", "play_pause", "next", "previous"
    
    #[serde(rename = "media_get_status")]
    MediaGetStatus,

    // Presentation Pointer
    #[serde(rename = "pointer_data")]
    PointerData { active: bool, mode: i32, pitch: f32, roll: f32 },
    
    // Presentation Slide Control
    #[serde(rename = "presentation_control")]
    PresentationControl { action: String }, // "prev" or "next"

    #[serde(rename = "set_pointer_monitor")]
    SetPointerMonitor { monitor: i32 },
}


#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct MediaMetadata {
    pub title: String,
    pub artist: String,
    pub album: String,
    pub art_url: String,
    pub duration: i64, // Usecs
    pub position: i64, // Usecs
    pub status: String, // "Playing", "Paused", "Stopped"
    pub player_name: String,
    pub shuffle: bool,
    pub repeat: String, // "None", "Track", "Playlist"
    pub volume: f64,    // 0.0 to 1.0
    pub track_id: String,
}

#[derive(Serialize, Deserialize, Debug)]
pub struct MediaResponse {
    pub metadata: Option<MediaMetadata>,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct DeviceInfo {
    pub id: String,
    pub name: String,
    pub status: String, // "Trusted", "Pending", "Connected"
    pub ip: String,
}

#[derive(Serialize, Deserialize, Debug)]
pub struct StatusResponse {
    pub devices: Vec<DeviceInfo>,
}

#[derive(Serialize, Deserialize, Debug)]
pub struct PairResponse {
    pub status: String,
}
