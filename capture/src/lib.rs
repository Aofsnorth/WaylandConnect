#![deny(warnings)]
#[cfg(target_os = "linux")]
mod wayland;

#[cfg(target_os = "linux")]
pub use wayland::WaylandCapturer;

pub fn get_capturer() -> Box<dyn wc_core::traits::ScreenCapturer> {
    #[cfg(target_os = "linux")]
    return Box::new(WaylandCapturer::new());

    #[cfg(not(target_os = "linux"))]
    panic!("Unsupported OS");
}
