use config::{Config, ConfigError, File, Environment};
use crate::schema::AppConfig;
use std::env;

pub fn load_config() -> Result<AppConfig, ConfigError> {
    let run_mode = env::var("RUN_MODE").unwrap_or_else(|_| "development".into());

    let s = Config::builder()
        // Start with default values via implicit structural defaults handled here manually or strictly via file
        // Ideally we start with "default" structure values.
        // For config-rs, we usually set defaults via set_default.
        .set_default("video.codec", "h264")?
        .set_default("video.width", 1280)?
        .set_default("video.height", 720)?
        .set_default("video.fps", 30)?
        .set_default("video.bitrate_kbps", 5000)?
        .set_default("video.hardware", true)?
        .set_default("video.magnifier_enabled", false)?
        .set_default("video.magnifier_scale", 2.0)?
        
        .set_default("audio.enabled", true)?
        .set_default("audio.codec", "opus")?
        .set_default("audio.bitrate_kbps", 128)?
        .set_default("audio.sample_rate", 48000)?
        .set_default("audio.source_regex", Option::<String>::None)?
        
        .set_default("network.port", 7000)?
        .set_default("network.protocol", "quic")?
        .set_default("network.bind_address", "0.0.0.0")?

        .set_default("input.enabled", true)?
        .set_default("input.sensitivity", 1.0)?
        .set_default("input.scroll_speed", 1.0)?
        .set_default("input.smooth_scroll", true)?

        .set_default("visualizer.fps", 60)?
        .set_default("visualizer.particle_count", 100)?
        .set_default("visualizer.fft_size", 1024)?

        // Start merging
        .add_source(File::with_name("config/default").required(false))
        .add_source(File::with_name(&format!("config/{}", run_mode)).required(false))
        .add_source(File::with_name("config").required(false)) // Local config.toml
        
        // Add Environment variables check
        // e.g. WC_VIDEO_FPS=60
        .add_source(Environment::with_prefix("WC").separator("_"))
        
        .build()?;

    // You can deserialize (and thus freeze) the entire configuration as
    s.try_deserialize()
}
