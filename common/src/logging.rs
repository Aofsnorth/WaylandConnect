use tracing_subscriber::FmtSubscriber;
use tracing::Level;
use std::env;

pub fn init_logger() {
    let env_filter = env::var("RUST_LOG").unwrap_or_else(|_| "info".to_string());
    
    // Parse level from env or default to INFO
    let level = match env_filter.to_lowercase().as_str() {
        "error" => Level::ERROR,
        "warn" => Level::WARN,
        "debug" => Level::DEBUG,
        "trace" => Level::TRACE,
        _ => Level::INFO,
    };

    let subscriber = FmtSubscriber::builder()
        .with_max_level(level)
        .with_target(false) // Cleaner output without module paths in simple mode
        .with_thread_ids(true)
        .finish();

    tracing::subscriber::set_global_default(subscriber)
        .expect("setting default subscriber failed");
}
