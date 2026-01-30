use std::net::UdpSocket;
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;
use std::time::Instant;

struct PointerData {
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
}

pub struct PointerManager {
    data: Arc<Mutex<PointerData>>,
    input_socket: UdpSocket, // Only for sending control commands internally if needed
}

impl PointerManager {
    pub fn new() -> Self {
        // Bind to an ephemeral port
        let socket = UdpSocket::bind("127.0.0.1:0").expect("Failed to bind UDP socket");
        socket.set_nonblocking(true).expect("Failed to set nonblocking");
        
        // Clone socket for the emission thread
        let send_socket = socket.try_clone().expect("Failed to clone socket");

        let data = Arc::new(Mutex::new(PointerData {
            active: false,
            mode: 0,
            size: 1.0,
            current_x: 0.5,
            current_y: 0.5,
            target_x: 0.5,
            target_y: 0.5,
            color: "#ffffffff".to_string(),
            zoom: 1.0,
            particle: 0,
            stretch: 1.0,
            has_image: false,
            zoom_enabled: false,
        }));

        let data_clone = data.clone();

        // Spawn 120Hz Interpolation & Emission Thread
        thread::spawn(move || {
            let mut last_loop = Instant::now();
            loop {
                let now = Instant::now();
                let dt = now.duration_since(last_loop).as_secs_f32();
                last_loop = now;

                // Scope for lock
                {
                    let mut d = data_clone.lock().unwrap();
                    
                    if d.active {
                        // Interpolation (Smoothness)
                        // Adjust smoothing factor: 0.1 = very smooth/slow, 0.5 = responsive, 1.0 = instant
                        // Using variable lerp based on dt for framerate independence
                        // Target about 20-30% movement per frame at 120Hz
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
                        // Format: "x,y,mode,size,color,zoom,particle,has_image,stretch"
                        let msg = format!("{:.4},{:.4},{},{:.2},{},{:.2},{},{},{:.2}", 
                            d.current_x, d.current_y, d.mode, d.size, d.color, d.zoom, d.particle, if d.has_image { 1 } else { 0 }, d.stretch);
                        
                        // Error ignored to prevent panic on shutdown
                        let _ = send_socket.send_to(msg.as_bytes(), wc_core::constants::POINTER_OVERLAY_ADDR);
                    }
                }

                // Sleep to maintain ~250Hz (4ms)
                thread::sleep(Duration::from_millis(4));
            }
        });

        Self {
            data,
            input_socket: socket, // Kept to match struct, but mostly unused for data now
        }
    }

    pub fn update(&self, active: bool, mode: i32, pitch: f32, roll: f32, size: f32, color: String, zoom: f32, particle: i32, stretch: f32, has_image: bool) {
        let mut data = match self.data.lock() {
            Ok(d) => d,
            Err(_) => return,
        };
        
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
        
        // Update Targets (Input Feed)
        if active {
            data.target_x = roll;
            data.target_y = pitch;
            // Note: We do NOT set current_x/y here to allow interpolation to work
            
            // If just activated, snap to target to prevent flying in from (0,0)
            if !was_active {
                data.current_x = roll;
                data.current_y = pitch;
            }
        }

        // Handle Control Signals immediately
        if !was_active && active {
             log::info!("🎯 Starting pointer overlay");
             let _ = self.input_socket.send_to(b"START", wc_core::constants::POINTER_OVERLAY_ADDR);
        } else if was_active && !active {
             log::info!("🎯 Stopping pointer overlay");
             let _ = self.input_socket.send_to(b"STOP", wc_core::constants::POINTER_OVERLAY_ADDR);
        }

        if !active {
            if mode_changed {
                let msg = format!("MODE:{}", mode);
                let _ = self.input_socket.send_to(msg.as_bytes(), wc_core::constants::POINTER_OVERLAY_ADDR);
            }
            if size_changed {
                let msg = format!("SIZE:{:.2}", size);
                let _ = self.input_socket.send_to(msg.as_bytes(), wc_core::constants::POINTER_OVERLAY_ADDR);
            }
        }
    }

    pub fn get_zoom_and_coords(&self) -> (f32, f32, f32) {
        let data = self.data.lock().unwrap();
        (data.zoom, data.current_x, data.current_y)
    }

    pub fn set_monitor(&self, monitor: i32) {
        let msg = format!("MONITOR:{}", monitor);
                 let _ = self.input_socket.send_to(msg.as_bytes(), wc_core::constants::POINTER_OVERLAY_ADDR);
    }

    pub fn run_test_sequence(&self) {
         let _ = self.input_socket.send_to(b"TEST_SEQUENCE", wc_core::constants::POINTER_OVERLAY_ADDR);
    }

    pub fn set_zoom_enabled(&self, enabled: bool) {
        let mut data = self.data.lock().unwrap();
        data.zoom_enabled = enabled;
        if enabled {
             let _ = self.input_socket.send_to(b"START_CAPTURE", wc_core::constants::POINTER_OVERLAY_ADDR);
        }
    }
}
