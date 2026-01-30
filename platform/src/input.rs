use async_trait::async_trait;
use crate::error::Result;

#[async_trait]
pub trait InputInjector: Send + Sync {
    async fn move_mouse(&mut self, dx: i32, dy: i32) -> Result<()>;
    async fn move_mouse_abs(&mut self, x: u32, y: u32, screen_width: u32, screen_height: u32) -> Result<()>;
    async fn click(&mut self, button: MouseButton) -> Result<()>;
    async fn scroll(&mut self, axis: ScrollAxis, distance: i32) -> Result<()>;
    async fn key_press(&mut self, key: KeyCode) -> Result<()>;
}

#[derive(Debug, Clone, Copy)]
pub enum MouseButton {
    Left,
    Right,
    Middle,
}

#[derive(Debug, Clone, Copy)]
pub enum ScrollAxis {
    Vertical,
    Horizontal,
}

#[derive(Debug, Clone, Copy)]
pub enum KeyCode {
    // Basic mapping, can be expanded
    Space,
    Enter,
    Backspace,
    Tab,
    Escape,
    ControlLeft,
    AltLeft,
    SuperLeft,
    VolumeUp,
    VolumeDown,
    MediaPlayPause,
    MediaNext,
    MediaPrev,
    PageUp,
    PageDown,
    Left,
    Right,
    Up,
    Down,
    Char(char),
    Unknown(u32),
}

// Linux Implementation
#[cfg(target_os = "linux")]
pub mod linux {
    use super::*;
    // use anyhow::Context as _;
    use input_linux::{uinput::UInputHandle, EventKind, Key, RelativeAxis, SynchronizeKind, AbsoluteAxis};
    use std::fs::{File, OpenOptions};
    use std::os::unix::fs::OpenOptionsExt;
    use std::path::Path;
    use crate::error::WcError;

    pub struct LinuxInputInjector {
        handle: UInputHandle<File>,
    }

    impl LinuxInputInjector {
        pub fn new() -> Result<Self> {
            let path = Path::new("/dev/uinput");
            
            // Try to open /dev/uinput. Needs permissions.
            let file = OpenOptions::new()
                .write(true)
                .custom_flags(libc::O_NONBLOCK)
                .open(path)
                .map_err(|e| WcError::Platform(format!("Failed to open /dev/uinput: {}", e)))?;

            let handle = UInputHandle::new(file);

            // Set up capabilities
            handle.set_evbit(EventKind::Key).map_err(map_err)?;
            handle.set_evbit(EventKind::Relative).map_err(map_err)?;
            handle.set_evbit(EventKind::Absolute).map_err(map_err)?;
            handle.set_evbit(EventKind::Synchronize).map_err(map_err)?;

            // Register Keys (Mouse + Keyboard)
            // Mouse
            handle.set_keybit(Key::ButtonLeft).map_err(map_err)?;
            handle.set_keybit(Key::ButtonRight).map_err(map_err)?;
            handle.set_keybit(Key::ButtonMiddle).map_err(map_err)?;

            // Multimedia
            handle.set_keybit(Key::VolumeUp).map_err(map_err)?;
            handle.set_keybit(Key::VolumeDown).map_err(map_err)?;
            handle.set_keybit(Key::PlayPause).map_err(map_err)?;
            handle.set_keybit(Key::NextSong).map_err(map_err)?;
            handle.set_keybit(Key::PreviousSong).map_err(map_err)?;

            // Navigation
            handle.set_keybit(Key::PageUp).map_err(map_err)?;
            handle.set_keybit(Key::PageDown).map_err(map_err)?;
            handle.set_keybit(Key::Up).map_err(map_err)?;
            handle.set_keybit(Key::Down).map_err(map_err)?;
            handle.set_keybit(Key::Left).map_err(map_err)?;
            handle.set_keybit(Key::Right).map_err(map_err)?;

            // Common Keyboard Keys
            handle.set_keybit(Key::Space).map_err(map_err)?;
            handle.set_keybit(Key::Enter).map_err(map_err)?;
            handle.set_keybit(Key::Backspace).map_err(map_err)?;
            handle.set_keybit(Key::Tab).map_err(map_err)?;
            handle.set_keybit(Key::Esc).map_err(map_err)?;
            handle.set_keybit(Key::LeftCtrl).map_err(map_err)?;
            handle.set_keybit(Key::LeftAlt).map_err(map_err)?;
            handle.set_keybit(Key::LeftMeta).map_err(map_err)?;
            
            // Letters
            for key_code in (Key::A as u16)..=(Key::Z as u16) {
                handle.set_keybit(unsafe { std::mem::transmute::<u16, Key>(key_code) }).map_err(map_err)?;
            }

            // Register Axes
            handle.set_relbit(RelativeAxis::X).map_err(map_err)?;
            handle.set_relbit(RelativeAxis::Y).map_err(map_err)?;
            handle.set_relbit(RelativeAxis::Wheel).map_err(map_err)?;
            
            // Absolute events for Touch/Tablet like control
            // Note: input-linux 0.7 handle doesn't expose ease way to set abs info via ioctl easily without generic access.
            // For now, enabling the bits is enough for some compositors to pick it up, or we assume relative mostly.
            // If strictly needed, we must use sys::ioctl logic.
            // handle.create_abs(AbsoluteAxis::X, abs_setup).map_err(map_err)?;
            // handle.create_abs(AbsoluteAxis::Y, abs_setup).map_err(map_err)?;


            // Create Device
            let input_id = input_linux::InputId {
                bustype: input_linux::sys::BUS_USB,
                vendor: 0x1234,
                product: 0x5678,
                version: 1,
            };
            
            handle.create(&input_id, b"WaylandConnect Virtual Device", 0, &[]).map_err(map_err)?;

            Ok(Self { handle })
        }

        fn write_events(&mut self, events: &[input_linux::sys::input_event]) -> Result<()> {
            self.handle.write(events).map_err(map_err)?;
            Ok(())
        }
    }

    fn map_err(e: std::io::Error) -> WcError {
        WcError::Platform(format!("uinput error: {}", e))
    }
    
    fn make_event(kind: EventKind, code: u16, value: i32) -> input_linux::sys::input_event {
        input_linux::sys::input_event {
            time: input_linux::sys::timeval { tv_sec: 0, tv_usec: 0 },
            type_: kind as u16,
            code,
            value,
        }
    }

    #[async_trait]
    impl InputInjector for LinuxInputInjector {
        async fn move_mouse(&mut self, dx: i32, dy: i32) -> Result<()> {
            self.write_events(&[
                make_event(EventKind::Relative, RelativeAxis::X as u16, dx),
                make_event(EventKind::Relative, RelativeAxis::Y as u16, dy),
                make_event(EventKind::Synchronize, SynchronizeKind::Report as u16, 0),
            ])
        }

        async fn move_mouse_abs(&mut self, x: u32, y: u32, screen_width: u32, screen_height: u32) -> Result<()> {
             let abs_x = ((x as u64 * 65535) / screen_width as u64) as i32;
             let abs_y = ((y as u64 * 65535) / screen_height as u64) as i32;

             self.write_events(&[
                make_event(EventKind::Absolute, AbsoluteAxis::X as u16, abs_x),
                make_event(EventKind::Absolute, AbsoluteAxis::Y as u16, abs_y),
                make_event(EventKind::Synchronize, SynchronizeKind::Report as u16, 0),
             ])
        }

        async fn click(&mut self, button: MouseButton) -> Result<()> {
            let key = match button {
                MouseButton::Left => Key::ButtonLeft,
                MouseButton::Right => Key::ButtonRight,
                MouseButton::Middle => Key::ButtonMiddle,
            };
            self.write_events(&[
                make_event(EventKind::Key, key as u16, 1),
                make_event(EventKind::Synchronize, SynchronizeKind::Report as u16, 0),
                make_event(EventKind::Key, key as u16, 0),
                make_event(EventKind::Synchronize, SynchronizeKind::Report as u16, 0),
            ])
        }

        async fn scroll(&mut self, axis: ScrollAxis, distance: i32) -> Result<()> {
             let axis_code = match axis {
                 ScrollAxis::Vertical => RelativeAxis::Wheel,
                 ScrollAxis::Horizontal => RelativeAxis::Wheel, 
             };
             
             self.write_events(&[
                 make_event(EventKind::Relative, axis_code as u16, distance),
                 make_event(EventKind::Synchronize, SynchronizeKind::Report as u16, 0),
             ])
        }

        async fn key_press(&mut self, key: KeyCode) -> Result<()> {
            let u_key = match key {
                KeyCode::Space => Key::Space,
                KeyCode::Enter => Key::Enter,
                KeyCode::Backspace => Key::Backspace,
                KeyCode::Tab => Key::Tab,
                KeyCode::Escape => Key::Esc,
                KeyCode::ControlLeft => Key::LeftCtrl,
                KeyCode::AltLeft => Key::LeftAlt,
                KeyCode::SuperLeft => Key::LeftMeta,
                KeyCode::PageUp => Key::PageUp,
                KeyCode::PageDown => Key::PageDown,
                KeyCode::Left => Key::Left,
                KeyCode::Right => Key::Right,
                KeyCode::Up => Key::Up,
                KeyCode::Down => Key::Down,
                KeyCode::VolumeUp => Key::VolumeUp,
                KeyCode::VolumeDown => Key::VolumeDown,
                KeyCode::MediaPlayPause => Key::PlayPause,
                KeyCode::MediaNext => Key::NextSong,
                KeyCode::MediaPrev => Key::PreviousSong,
                KeyCode::Char(c) => {
                    match c.to_ascii_lowercase() {
                        'a' => Key::A, 'b' => Key::B, 'c' => Key::C, 'd' => Key::D, 
                        'e' => Key::E, 'f' => Key::F, 'g' => Key::G, 'h' => Key::H,
                        'i' => Key::I, 'j' => Key::J, 'k' => Key::K, 'l' => Key::L,
                        'm' => Key::M, 'n' => Key::N, 'o' => Key::O, 'p' => Key::P,
                        'q' => Key::Q, 'r' => Key::R, 's' => Key::S, 't' => Key::T,
                        'u' => Key::U, 'v' => Key::V, 'w' => Key::W, 'x' => Key::X,
                        'y' => Key::Y, 'z' => Key::Z,
                        ' ' => Key::Space,
                        _ => return Ok(()),
                    }
                }
                KeyCode::Unknown(_) => return Ok(()),
            };
            
            self.write_events(&[
                make_event(EventKind::Key, u_key as u16, 1),
                make_event(EventKind::Synchronize, SynchronizeKind::Report as u16, 0),
                make_event(EventKind::Key, u_key as u16, 0),
                make_event(EventKind::Synchronize, SynchronizeKind::Report as u16, 0),
            ])
        }
    }
}
