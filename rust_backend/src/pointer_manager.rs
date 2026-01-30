use std::net::UdpSocket;
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;
use std::time::Instant;

#[derive(Clone)]
struct SinglePointerData {
    active: bool,
    mode: i32,
    size: f32, 
    current_x: f32,
    current_y: f32,
    target_x: f32,
    target_y: f32,
    color: String,
    zoom: f32,
    particle: i32,
    stretch: f32,
    has_image: bool,
    zoom_enabled: bool,
    pulse_speed: f32,
    pulse_intensity: f32,
}

struct PointerManagerState {
    pointers: std::collections::HashMap<String, SinglePointerData>,
}

pub struct PointerManager {
    state: Arc<Mutex<PointerManagerState>>,
    input_socket: UdpSocket, 
}

impl PointerManager {
    pub fn new() -> Self {
        // Bind to an ephemeral port
        let socket = UdpSocket::bind("127.0.0.1:0").expect("Failed to bind UDP socket");
        socket.set_nonblocking(true).expect("Failed to set nonblocking");
        
        // Clone socket for the emission thread
        let send_socket = socket.try_clone().expect("Failed to clone socket");

        let state = Arc::new(Mutex::new(PointerManagerState {
            pointers: std::collections::HashMap::new(),
        }));

        let state_clone = state.clone();

        // Spawn 120Hz Interpolation & Emission Thread
        thread::spawn(move || {
            let mut last_loop = Instant::now();
            loop {
                let now = Instant::now();
                let dt = now.duration_since(last_loop).as_secs_f32();
                last_loop = now;

                // Scope for lock
                {
                    let mut s = state_clone.lock().unwrap();
                    
                    for (id, d) in s.pointers.iter_mut() {
                        if d.active {
                            // Interpolation (Smoothness)
                            let dist_sq = (d.target_x - d.current_x).powi(2) + (d.target_y - d.current_y).powi(2);
                            let smoothing_factor = if dist_sq > 0.001 { 120.0 } else { 75.0 };
                            let smoothing = smoothing_factor * dt; 
                            let t = smoothing.clamp(0.0, 1.0);
                            
                            d.current_x = d.current_x + (d.target_x - d.current_x) * t;
                            d.current_y = d.current_y + (d.target_y - d.current_y) * t;
                            
                            // Use raw values if very close target to avoid micro-drifting
                            if (d.target_x - d.current_x).abs() < 0.0001 { d.current_x = d.target_x; }
                            if (d.target_y - d.current_y).abs() < 0.0001 { d.current_y = d.target_y; }

                            // Send Packet
                            // Format: "DEVICE_ID|x,y,mode,size,color,zoom,particle,has_image,stretch,pulse_speed,pulse_intensity"
                            let msg = format!("{}|{:.4},{:.4},{},{:.2},{},{:.2},{},{},{:.2},{:.2},{:.2}", 
                                id, d.current_x, d.current_y, d.mode, d.size, d.color, d.zoom, d.particle, if d.has_image { 1 } else { 0 }, d.stretch, d.pulse_speed, d.pulse_intensity);
                            
                            let _ = send_socket.send_to(msg.as_bytes(), wc_core::constants::POINTER_OVERLAY_ADDR);
                        }
                    }
                }

                // Sleep to maintain ~250Hz (4ms)
                thread::sleep(Duration::from_millis(4));
            }
        });

        Self {
            state,
            input_socket: socket, 
        }
    }

    #[allow(clippy::too_many_arguments)]
    pub fn update(&self, device_id: &str, active: bool, mode: i32, pitch: f32, roll: f32, size: f32, color: String, zoom: f32, particle: i32, stretch: f32, has_image: bool, pulse_speed: f32, pulse_intensity: f32) {
        let mut state = match self.state.lock() {
            Ok(s) => s,
            Err(_) => return,
        };
        
        let data = state.pointers.entry(device_id.to_string()).or_insert_with(|| SinglePointerData {
            active: false,
            mode: 0,
            size: 1.0,
            current_x: roll,
            current_y: pitch,
            target_x: roll,
            target_y: pitch,
            color: color.clone(),
            zoom: 1.0,
            particle: 0,
            stretch: 1.0,
            has_image: false,
            zoom_enabled: false,
            pulse_speed: 1.0,
            pulse_intensity: 0.0,
        });

        let mode_changed = data.mode != mode;
        let size_changed = (data.size - size).abs() > 0.01;
        let was_active = data.active;
        
        // Update State
        data.active = active;
        data.mode = mode;
        data.size = size;
        data.color = color;
        data.zoom = zoom;
        data.particle = particle;
        data.stretch = stretch;
        data.has_image = has_image;
        data.pulse_speed = pulse_speed;
        data.pulse_intensity = pulse_intensity;
        
        // Update Targets (Input Feed)
        if active {
            data.target_x = roll;
            data.target_y = pitch;
            
            if !was_active {
                data.current_x = roll;
                data.current_y = pitch;
            }
        }

        // Handle Control Signals immediately
        if !was_active && active {
             log::info!("🎯 Starting pointer overlay for device {}", device_id);
             let msg = format!("{}|START", device_id);
             let _ = self.input_socket.send_to(msg.as_bytes(), wc_core::constants::POINTER_OVERLAY_ADDR);
        } else if was_active && !active {
             log::info!("🎯 Stopping pointer overlay for device {}", device_id);
             let msg = format!("{}|STOP", device_id);
             let _ = self.input_socket.send_to(msg.as_bytes(), wc_core::constants::POINTER_OVERLAY_ADDR);
        }

        if !active {
            if mode_changed {
                let msg = format!("{}|MODE:{}", device_id, mode);
                let _ = self.input_socket.send_to(msg.as_bytes(), wc_core::constants::POINTER_OVERLAY_ADDR);
            }
            if size_changed {
                let msg = format!("{}|SIZE:{:.2}", device_id, size);
                let _ = self.input_socket.send_to(msg.as_bytes(), wc_core::constants::POINTER_OVERLAY_ADDR);
            }
        }
    }

    pub fn get_zoom_and_coords(&self, device_id: &str) -> (f32, f32, f32) {
        let state = self.state.lock().unwrap();
        if let Some(data) = state.pointers.get(device_id) {
            (data.zoom, data.current_x, data.current_y)
        } else {
            (1.0, 0.5, 0.5)
        }
    }

    pub fn set_monitor(&self, device_id: &str, monitor: i32) {
        let msg = format!("{}|MONITOR:{}", device_id, monitor);
        let _ = self.input_socket.send_to(msg.as_bytes(), wc_core::constants::POINTER_OVERLAY_ADDR);
    }

    pub fn run_test_sequence(&self, device_id: &str) {
         let msg = format!("{}|TEST_SEQUENCE", device_id);
         let _ = self.input_socket.send_to(msg.as_bytes(), wc_core::constants::POINTER_OVERLAY_ADDR);
    }

    pub fn set_zoom_enabled(&self, device_id: &str, enabled: bool) {
        let mut state = self.state.lock().unwrap();
        if let Some(data) = state.pointers.get_mut(device_id) {
            data.zoom_enabled = enabled;
            if enabled {
                 let msg = format!("{}|START_CAPTURE", device_id);
                 let _ = self.input_socket.send_to(msg.as_bytes(), wc_core::constants::POINTER_OVERLAY_ADDR);
            }
        }
    }
}
