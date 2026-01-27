use std::net::UdpSocket;
use std::sync::Mutex;

struct PointerData {
    active: bool,
    mode: i32,
    x: f32,
    y: f32,
}

pub struct PointerManager {
    data: Mutex<PointerData>,
    socket: UdpSocket,
}

impl PointerManager {
    pub fn new() -> Self {
        // Bind to an ephemeral port to send from
        let socket = UdpSocket::bind("127.0.0.1:0").expect("Failed to bind UDP socket");
        socket.set_nonblocking(true).expect("Failed to set nonblocking");

        Self {
            data: Mutex::new(PointerData {
                active: false,
                mode: 2,
                x: 0.5,
                y: 0.5,
            }),
            socket,
        }
    }

    pub fn update(&self, active: bool, mode: i32, pitch: f32, roll: f32, size: f32) {
        let mut data = self.data.lock().unwrap();
        
        // If transitioning from active to inactive, send a STOP signal once
        if data.active && !active {
            let _ = self.socket.send_to(b"STOP", "127.0.0.1:7878");
        }

        data.active = active;
        data.mode = mode;

        if active {
            // Android already sends normalized 0.0-1.0 coordinates
            data.x = roll;  // roll maps to x
            data.y = pitch; // pitch maps to y
            
            // Send UDP packet: "x,y,mode,size"
            let msg = format!("{:.4},{:.4},{},{:.2}", data.x, data.y, data.mode, size);
            // TARGET: Localhost port 7878 (Overlay will listen here)
            match self.socket.send_to(msg.as_bytes(), "127.0.0.1:7878") {
                Ok(_) => {},
                Err(e) => eprintln!("❌ UDP Send Error: {}", e),
            }
        }
    }

    pub fn set_monitor(&self, monitor: i32) {
        let msg = format!("MONITOR:{}", monitor);
        match self.socket.send_to(msg.as_bytes(), "127.0.0.1:7878") {
            Ok(_) => info!("📤 UDP Sent Monitor Selection: {}", msg),
            Err(e) => eprintln!("❌ UDP Send Error (Monitor): {}", e),
        }
    }
}

