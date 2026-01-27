use crate::protocol::InputEvent as ProtocolEvent;
use async_trait::async_trait;
use input_linux::{UInputHandle, EventKind, RelativeAxis, Key, InputId, EventTime};
use std::fs::File;
use std::os::unix::io::AsRawFd;

// Trait to decouple the application from the specific desktop environment mechanism
#[async_trait]
pub trait InputAdapter {
    async fn send_event(&self, event: ProtocolEvent) -> anyhow::Result<()>;
}

pub struct UInputAdapter {
    handle: UInputHandle<File>,
}

impl UInputAdapter {
    pub fn new() -> anyhow::Result<Self> {
        let file = File::options().write(true).open("/dev/uinput")?;
        let handle = UInputHandle::new(file);

        // Setup mouse device
        handle.set_evbit(EventKind::Relative)?;
        handle.set_relbit(RelativeAxis::X)?;
        handle.set_relbit(RelativeAxis::Y)?;
        handle.set_relbit(RelativeAxis::Wheel)?; // Enable scroll wheel

        // Enable Mouse Buttons (Key Events)
        handle.set_evbit(EventKind::Key)?;
        // Enable Keyboard bits for a-z, 0-9, and common keys
        for key_code in 1..=120 {
            if let Ok(k) = Key::from_code(key_code) {
                handle.set_keybit(k).ok(); 
            }
        }
        // Specifically ensure Mouse buttons are enabled (they are > 120 usually)
        handle.set_keybit(Key::ButtonLeft)?;
        handle.set_keybit(Key::ButtonRight)?;
        handle.set_keybit(Key::ButtonMiddle)?;
        
        let id = InputId {
            bustype: 0x03, // BUS_USB
            vendor: 0x1234,
            product: 0x5678,
            version: 0,
        };
        
        handle.create(&id, b"WaylandConnect Virtual Mouse", 0, &[])?;
        
        Ok(Self { handle })
    }
    
    // Helper to send raw event
    fn write_raw(&self, type_: u16, code: u16, value: i32) -> anyhow::Result<()> {
        #[repr(C)]
        struct input_event {
            tv_sec: i64,
            tv_usec: i64,
            type_: u16,
            code: u16,
            value: i32,
        }
        
        let event = input_event {
            tv_sec: 0,
            tv_usec: 0,
            type_,
            code,
            value,
        };
        
        // Write event + SYN_REPORT
        let syn = input_event {
            tv_sec: 0,
            tv_usec: 0,
            type_: 0, // EV_SYN
            code: 0,  // SYN_REPORT
            value: 0,
        };
        
        let events = [event, syn];
        
        let fd = self.handle.as_inner().as_raw_fd();
        let bytes_to_write = std::mem::size_of_val(&events);
        let ptr = events.as_ptr() as *const libc::c_void;
        
        unsafe {
            let written = libc::write(fd, ptr, bytes_to_write);
            if written < 0 {
                return Err(anyhow::anyhow!("Failed to write to uinput"));
            }
        }
        Ok(())
    }
}

#[async_trait]
impl InputAdapter for UInputAdapter {
    async fn send_event(&self, event: ProtocolEvent) -> anyhow::Result<()> {
        match event {
            ProtocolEvent::Move { dx, dy } => {
                let multi = 1.6; // Slightly more sensitive
                let final_dx = (dx * multi) as i32;
                let final_dy = (dy * multi) as i32;
                if final_dx == 0 && final_dy == 0 { return Ok(()); }
                
                 #[repr(C)]
                struct input_event {
                    tv_sec: i64, tv_usec: i64,
                    type_: u16, code: u16, value: i32,
                }
                
                let ev_x = input_event { tv_sec: 0, tv_usec: 0, type_: 2, code: 0, value: final_dx };
                let ev_y = input_event { tv_sec: 0, tv_usec: 0, type_: 2, code: 1, value: final_dy };
                let ev_syn = input_event { tv_sec: 0, tv_usec: 0, type_: 0, code: 0, value: 0 };
                
                let events = [ev_x, ev_y, ev_syn];
                 let fd = self.handle.as_inner().as_raw_fd();
                unsafe {
                     libc::write(fd, events.as_ptr() as *const _, std::mem::size_of_val(&events));
                }
            }
            ProtocolEvent::Click { button } => {
                let code = match button.as_str() {
                    "left" => 0x110, // BTN_LEFT
                    "right" => 0x111, // BTN_RIGHT
                    "middle" => 0x112, // BTN_MIDDLE
                    _ => return Ok(()),
                };
                self.write_raw(1, code, 1)?; // Press
                self.write_raw(1, code, 0)?; // Release
            }
            ProtocolEvent::Scroll { dy } => {
                // EV_REL (2), REL_WHEEL (8)
                // Remove inversion and hard multiplier to let frontend decide speed/direction
                let amount = dy as i32;
                self.write_raw(2, 8, amount)?;
            }
            ProtocolEvent::KeyPress { key } => {
                let code = match key.as_str() {
                    "Enter" => Some(28),
                    "Escape" => Some(1),
                    "Backspace" => Some(14),
                    "Tab" => Some(15),
                    " " => Some(57), // Space
                    s if s.len() == 1 => {
                        let c = s.chars().next().unwrap();
                        let lower = c.to_ascii_lowercase();
                        match lower {
                            'a'..='z' => {
                                match lower {
                                    'a' => Some(30), 'b' => Some(48), 'c' => Some(46), 'd' => Some(32),
                                    'e' => Some(18), 'f' => Some(33), 'g' => Some(34), 'h' => Some(35),
                                    'i' => Some(23), 'j' => Some(36), 'k' => Some(37), 'l' => Some(38),
                                    'm' => Some(50), 'n' => Some(49), 'o' => Some(24), 'p' => Some(25),
                                    'q' => Some(16), 'r' => Some(19), 's' => Some(31), 't' => Some(20),
                                    'u' => Some(22), 'v' => Some(47), 'w' => Some(17), 'x' => Some(45),
                                    'y' => Some(21), 'z' => Some(44),
                                    _ => None,
                                }
                            }
                            '1'..='9' | '0' => {
                                match lower {
                                    '1' => Some(2), '2' => Some(3), '3' => Some(4), '4' => Some(5),
                                    '5' => Some(6), '6' => Some(7), '7' => Some(8), '8' => Some(9),
                                    '9' => Some(10), '0' => Some(11),
                                    _ => None,
                                }
                            }
                            ',' => Some(51), '.' => Some(52), '/' => Some(53), ';' => Some(39),
                            '\'' => Some(40), '[' => Some(26), ']' => Some(27), '-' => Some(12),
                            '=' => Some(13), '\\' => Some(43), '`' => Some(41),
                            _ => None,
                        }
                    }
                    _ => None,
                };

                if let Some(c) = code {
                    self.write_raw(1, c as u16, 1)?; // Press
                    self.write_raw(1, c as u16, 0)?; // Release
                }
            }
            _ => {}
        }
        Ok(())
    }
}
