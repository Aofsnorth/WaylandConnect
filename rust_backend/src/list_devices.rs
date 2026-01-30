use cpal::traits::{DeviceTrait, HostTrait};

fn main() {
    let host = cpal::default_host();
    println!("Host: {}", host.id().name());
    
    if let Ok(devices) = host.input_devices() {
        for (i, d) in devices.enumerate() {
            println!("Device {}: {}", i, d.name().unwrap_or_else(|_| "Unknown".into()));
        }
    } else {
        println!("No input devices found.");
    }
    
    if let Some(d) = host.default_input_device() {
        println!("Default Input: {}", d.name().unwrap_or_else(|_| "Unknown".into()));
    }
}
