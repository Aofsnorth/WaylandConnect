use serde::Deserialize;

#[derive(Debug, Deserialize, Clone)]
pub struct AppConfig {
    pub video: VideoConfig,
    pub audio: AudioConfig,
    pub network: NetworkConfig,
    pub input: InputConfig,
    pub visualizer: VisualizerConfig,
}

#[derive(Debug, Deserialize, Clone)]
pub struct VideoConfig {
    pub codec: String, // "h264", "vp8", "vp9", "av1"
    pub width: u32,
    pub height: u32,
    pub fps: u32,
    pub bitrate_kbps: u32,
    pub hardware: bool,
    pub magnifier_enabled: bool,
    pub magnifier_scale: f32,
}

#[derive(Debug, Deserialize, Clone)]
pub struct AudioConfig {
    pub enabled: bool,
    pub codec: String, // "opus", "pcm"
    pub bitrate_kbps: u32,
    pub sample_rate: u32,
    pub source_regex: Option<String>,
}

#[derive(Debug, Deserialize, Clone)]
pub struct NetworkConfig {
    pub port: u16,
    pub protocol: String, // "udp", "tcp", "quic"
    pub bind_address: String,
}

#[derive(Debug, Deserialize, Clone)]
pub struct InputConfig {
    pub enabled: bool,
    pub sensitivity: f64,
    pub scroll_speed: f64,
    pub smooth_scroll: bool,
}

#[derive(Debug, Deserialize, Clone)]
pub struct VisualizerConfig {
    pub fps: u32,
    pub particle_count: u32,
    pub fft_size: usize,
}

impl Default for AppConfig {
    fn default() -> Self {
        Self {
            video: VideoConfig {
                codec: "h264".to_string(),
                width: 1280,
                height: 720,
                fps: 30,
                bitrate_kbps: 5000,
                hardware: true,
                magnifier_enabled: false,
                magnifier_scale: 2.0,
            },
            audio: AudioConfig {
                enabled: true,
                codec: "opus".to_string(),
                bitrate_kbps: 128,
                sample_rate: 48000,
                source_regex: None,
            },
            network: NetworkConfig {
                port: 7000,
                protocol: "quic".to_string(),
                bind_address: "0.0.0.0".to_string(),
            },
            input: InputConfig {
                enabled: true,
                sensitivity: 1.0,
                scroll_speed: 1.0,
                smooth_scroll: true,
            },
            visualizer: VisualizerConfig {
                fps: 60,
                particle_count: 100,
                fft_size: 1024,
            },
        }
    }
}
