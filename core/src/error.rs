use thiserror::Error;

#[derive(Error, Debug)]
pub enum WcError {
    #[error("Capture error: {0}")]
    Capture(String),
    #[error("Encoding error: {0}")]
    Encoding(String),
    #[error("Transport error: {0}")]
    Transport(String),
    #[error("Configuration error: {0}")]
    Config(String),
    #[error("Platform error: {0}")]
    Platform(String),
    #[error("Unknown error: {0}")]
    Unknown(#[from] anyhow::Error),
}

pub type Result<T> = std::result::Result<T, WcError>;
