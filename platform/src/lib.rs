#![deny(warnings)]
mod input;
mod error {
    pub use wc_core::error::{WcError, Result};
}

pub use input::{InputInjector, MouseButton, ScrollAxis, KeyCode};

#[cfg(target_os = "linux")]
pub use input::linux::LinuxInputInjector;
