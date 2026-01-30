use serde::{Serialize, Deserialize};

#[derive(Debug, Serialize, Deserialize, Clone)]
#[serde(tag = "type")]
pub enum Packet {
    // Media & Viz
    VideoFrame {
        timestamp: u64,
        keyframe: bool,
        data: Vec<u8>
    },
    Spectrum {
        low: f32,
        mid: f32,
        high: f32,
    },
    MediaMetadata {
        metadata: serde_json::Value,
    },
    
    // Remote Control (Incoming from Client)
    MouseMove {
        dx: f32,
        dy: f32,
    },
    MouseScroll {
        axis: u8, // 0: vertical, 1: horizontal
        amount: f32,
    },
    MouseClick {
        button: String,
        state: bool,
    },
    KeyPress {
        key: String,
    },

    // System & Handshake
    ControlRequest {
        action: String,
        params: Option<serde_json::Value>,
    },
    ControlResponse {
        status: String,
        message: String,
        data: Option<serde_json::Value>,
    },

    Handshake {
        version: String,
        device_name: String,
    },
    KeepAlive,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub enum InputType {
    Key,
    MouseMotion,
    MouseWheel,
    MouseButton,
}
