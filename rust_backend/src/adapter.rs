use crate::protocol::InputEvent as ProtocolEvent;
use async_trait::async_trait;
use input_linux::{UInputHandle, EventKind, RelativeAxis, AbsoluteAxis, AbsoluteInfo, AbsoluteInfoSetup, Key, InputId};
use std::fs::File;

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
        let file = File::options().write(true).open(wc_core::constants::UINPUT_PATH)?;
        let handle = UInputHandle::new(file);

        // Setup mouse device
        handle.set_evbit(EventKind::Relative)?;
        handle.set_relbit(RelativeAxis::X)?;
        handle.set_relbit(RelativeAxis::Y)?;
        handle.set_relbit(RelativeAxis::Wheel)?; // Enable scroll wheel

        // Setup Absolute Axis (for mirroring/touchscreen)
        handle.set_evbit(EventKind::Absolute)?;
        handle.set_absbit(AbsoluteAxis::X)?;
        handle.set_absbit(AbsoluteAxis::Y)?;
        let abs_info = AbsoluteInfo {
            value: 0,
            minimum: 0,
            maximum: 32767, // Standard 16-bit range
            fuzz: 0,
            flat: 0,
            resolution: 0,
        };
        
        let abs_setup = [
            AbsoluteInfoSetup {
                axis: AbsoluteAxis::X,
                info: abs_info,
            },
            AbsoluteInfoSetup {
                axis: AbsoluteAxis::Y,
                info: abs_info,
            },
        ];

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
        
        handle.create(&id, b"WaylandConnect Virtual Mouse", 0, &abs_setup)?;
        
        Ok(Self { handle })
    }
    
    // Helper to send raw event safely
    fn write_raw(&self, type_: u16, code: u16, value: i32) -> anyhow::Result<()> {
        let event = input_linux::sys::input_event {
            time: input_linux::sys::timeval { tv_sec: 0, tv_usec: 0 },
            type_,
            code,
            value,
        };
        
        // Write event + SYN_REPORT
        let syn = input_linux::sys::input_event {
            time: input_linux::sys::timeval { tv_sec: 0, tv_usec: 0 },
            type_: 0, // EV_SYN
            code: 0,  // SYN_REPORT
            value: 0,
        };
        
        let events = [event, syn];
        self.handle.write(&events).map_err(|e| anyhow::anyhow!("Failed to write to uinput: {}", e))?;
        Ok(())
    }
}

#[async_trait]
impl InputAdapter for UInputAdapter {
    async fn send_event(&self, event: ProtocolEvent) -> anyhow::Result<()> {
        match event {
            ProtocolEvent::Move { dx, dy } => {
                let multi = wc_core::constants::MOUSE_SENSITIVITY;
                let final_dx = (dx * multi) as i32;
                let final_dy = (dy * multi) as i32;
                if final_dx == 0 && final_dy == 0 { return Ok(()); }
                
                let ev_x = input_linux::sys::input_event { 
                    time: input_linux::sys::timeval { tv_sec: 0, tv_usec: 0 },
                    type_: 2, code: 0, value: final_dx 
                };
                let ev_y = input_linux::sys::input_event { 
                    time: input_linux::sys::timeval { tv_sec: 0, tv_usec: 0 },
                    type_: 2, code: 1, value: final_dy 
                };
                let ev_syn = input_linux::sys::input_event { 
                    time: input_linux::sys::timeval { tv_sec: 0, tv_usec: 0 },
                    type_: 0, code: 0, value: 0 
                };
                
                let events = [ev_x, ev_y, ev_syn];
                self.handle.write(&events).map_err(|e| anyhow::anyhow!("Failed to write to uinput: {}", e))?;
            }
            ProtocolEvent::MoveAbsolute { x, y } => {
                // Map normalized 0.0-1.0 to 0-32767
                let abs_x = (x.clamp(0.0, 1.0) * 32767.0) as i32;
                let abs_y = (y.clamp(0.0, 1.0) * 32767.0) as i32;

                self.write_raw(3, 0, abs_x)?; // EV_ABS (3), ABS_X (0)
                self.write_raw(3, 1, abs_y)?; // EV_ABS (3), ABS_Y (1)
                self.write_raw(0, 0, 0)?;     // SYN_REPORT
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
            ProtocolEvent::MouseClick { button, state } => {
                let code = match button.as_str() {
                    "left" => 0x110,
                    "right" => 0x111,
                    "middle" => 0x112,
                    _ => return Ok(()),
                };
                let value = match state.as_str() {
                    "down" => 1,  // Press
                    "up" => 0,    // Release
                    _ => return Ok(()),
                };
                self.write_raw(1, code, value)?;
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
                        if let Some(c) = s.chars().next() {
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
                    } else {
                        None
                    }
                }
                    "Left" => Some(105),
                    "Right" => Some(106),
                    "Up" => Some(103),
                    "Down" => Some(108),
                    "Prior" | "PageUp" => Some(104),
                    "Next" | "PageDown" => Some(109),
                    "Home" => Some(102),
                    "End" => Some(107),
                    "Insert" => Some(110),
                    "Delete" => Some(111),
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
