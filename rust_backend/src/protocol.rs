use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize, Debug)]
#[serde(tag = "type", content = "data")]
pub enum InputEvent {
    #[serde(rename = "move")]
    Move { dx: f64, dy: f64 },
    #[serde(rename = "move_absolute")]
    MoveAbsolute { x: f64, y: f64 },
    #[serde(rename = "click")]
    Click { button: String },
    #[serde(rename = "mouse_click")]
    MouseClick { button: String, state: String }, // state: "down" or "up"
    #[serde(rename = "scroll")]
    Scroll { dy: f64 },
    #[serde(rename = "keypress")]
    KeyPress { key: String },
    #[serde(rename = "pair_request")]
    PairRequest { device_name: String, id: String, #[serde(default)] version: String, #[serde(default)] auto_reconnect: Option<bool> },
    
    // Management Commands
    #[serde(rename = "get_status")]
    GetStatus,
    #[serde(rename = "approve_device")]
    ApproveDevice { id: String },
    #[serde(rename = "reject_device")] // Clean up pending
    RejectDevice { id: String },
    #[serde(rename = "block_device")]
    BlockDevice { id: String },
    #[serde(rename = "test_overlay_sequence")]
    TestOverlaySequence,
    #[serde(rename = "unblock_device")] // Alias for approve or remove from block list
    UnblockDevice { id: String },

    // Media Controls
    #[serde(rename = "media_control")]
    MediaControl { action: String }, // "play", "pause", "play_pause", "next", "previous"
    
    #[serde(rename = "media_get_status")]
    MediaGetStatus,

    // Presentation Pointer
    #[serde(rename = "pointer_data")]
    PointerData { 
        active: bool, 
        mode: i32, 
        pitch: f32, 
        roll: f32,
        #[serde(default = "default_size")] 
        size: f32,
        #[serde(default = "default_color")]
        color: String,
        #[serde(default = "default_zoom")]
        zoom_scale: f32,
        #[serde(default = "default_particle")]
        particle_type: i32,
        #[serde(default = "default_stretch")]
        stretch_factor: f32,
        #[serde(default)]
        has_image: bool,
    },
    
    // Presentation Slide Control
    #[serde(rename = "presentation_control")]
    PresentationControl { action: String }, // "prev" or "next"

    #[serde(rename = "set_pointer_monitor")]
    SetPointerMonitor { monitor: i32 },

    #[serde(rename = "launch_app")]
    LaunchApp { command: String },

    #[serde(rename = "get_apps")]
    GetApps,

    #[serde(rename = "start_mirroring")]
    StartMirroring { 
        #[serde(default = "default_width")] width: u32, 
        #[serde(default = "default_height")] height: u32,
        #[serde(default = "default_fps")] fps: u32,
        #[serde(default)] monitor: i32
    },

    #[serde(rename = "stop_mirroring")]
    StopMirroring,

    #[serde(rename = "discovery")]
    Discovery {},

    #[serde(rename = "pointer_image")]
    PointerImage { data: String },

    #[serde(rename = "set_zoom_enabled")]
    SetZoomEnabled { enabled: bool },

    #[serde(rename = "mirror_response")]
    MirrorResponse { device_id: String, accepted: bool },

    #[serde(rename = "set_audio_sensitivity")]
    SetAudioSensitivity { value: f32 },

    #[serde(rename = "get_monitors")]
    GetMonitors,

    #[serde(rename = "set_auto_connect")]
    SetAutoConnect { enabled: bool },
    #[serde(rename = "set_device_auto_reconnect")]
    SetDeviceAutoReconnect { id: String, enabled: bool },
    #[serde(rename = "request_auto_reconnect")]
    RequestAutoReconnect { id: String },
    #[serde(rename = "auto_reconnect_response")]
    AutoReconnectResponse { id: String, accepted: bool },
    #[serde(rename = "pc_stop_mirroring")]
    PCStopMirroring { id: String },

    #[serde(rename = "register_dashboard")]
    RegisterDashboard,
}

fn default_size() -> f32 { 1.0 }
fn default_color() -> String { "#ffffffff".to_string() }
fn default_zoom() -> f32 { 1.0 }
fn default_particle() -> i32 { 0 }
fn default_stretch() -> f32 { 1.0 }
fn default_width() -> u32 { 854 }
fn default_height() -> u32 { 480 }
fn default_fps() -> u32 { 15 }

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct MonitorInfo {
    pub id: i32,
    pub name: String,
    pub width: i32,
    pub height: i32,
    pub x: i32,
    pub y: i32,
    pub focused: bool,
}


#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct AppInfo {
    pub name: String,
    pub exec: String,
    pub icon: String, // Can be name or path
    pub icon_base64: Option<String>,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct DeviceInfo {
    pub id: String,
    pub name: String,
    pub status: String, // "Trusted", "Pending", "Connected"
    pub ip: String,
    #[serde(default)]
    pub auto_reconnect: bool,
    #[serde(default)]
    pub is_mirroring: bool,
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
#[serde(tag = "type", content = "data")]
pub enum ControlResponse {
    #[serde(rename = "discovery_response")]
    DiscoveryResponse { 
        server_name: String, 
        #[serde(default)]
        fingerprint: Option<String> 
    },
    #[serde(rename = "media_status")]
    MediaStatus { metadata: Option<MediaMetadata> },
    #[serde(rename = "status_response")]
    StatusResponse { 
        devices: Vec<DeviceInfo>,
        #[serde(default)]
        zoom_enabled: bool,
    },
    #[serde(rename = "pair_response")]
    PairResponse { 
        status: String, 
        server_version: String, 
        server_name: String,
        #[serde(default)]
        fingerprint: Option<String>
    },
    #[serde(rename = "apps_list")]
    AppsList { apps: Vec<AppInfo> },
    #[serde(rename = "mirror_request")]
    MirrorRequest { device_id: String, device_name: String },
    #[serde(rename = "mirror_status")]
    MirrorStatus { allowed: bool, message: String },
    #[serde(rename = "auto_reconnect_request")]
    AutoReconnectRequest { device_id: String, device_name: String },
    #[serde(rename = "stop_mirroring")]
    StopMirroring,
    #[serde(rename = "monitors_list")]
    MonitorsList { monitors: Vec<MonitorInfo> },
    #[serde(rename = "security_update")]
    SecurityUpdate { status: String },
    #[serde(rename = "register_response")]
    RegisterResponse { success: bool },
}

#[derive(Serialize, Deserialize, Debug)]
#[serde(tag = "t", content = "d")]
pub enum BinaryPacket {
    #[serde(rename = "s")]
    Spectrum { bands: Vec<f32> },
    #[serde(rename = "f")]
    Frame { b: Vec<u8> },
}
