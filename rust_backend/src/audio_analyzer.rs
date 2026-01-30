use rustfft::{FftPlanner, num_complex::Complex};
use std::sync::{Arc, Mutex};
use log::{info, error};
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use std::process::Command;
use std::f32::consts::PI;

pub struct AudioAnalyzer {
    bands: Arc<Mutex<Vec<f32>>>,
    target_app: Arc<Mutex<Option<String>>>,
    sensitivity: Arc<Mutex<f32>>,
}

impl AudioAnalyzer {
    pub fn new() -> Self {
        Self {
            bands: Arc::new(Mutex::new(vec![0.0; 7])),
            target_app: Arc::new(Mutex::new(None)),
            sensitivity: Arc::new(Mutex::new(1.0)),
        }
    }

    pub fn set_sensitivity(&self, val: f32) {
        if let Ok(mut s) = self.sensitivity.lock() {
            *s = val.clamp(0.01, 5.0);
            info!("🎚️ Audio Sensitivity set to: {:.2}", *s);
        }
    }

    pub fn set_target_app(&self, app: Option<String>) {
        if let Ok(mut t) = self.target_app.lock() {
            *t = app;
        }
    }

    fn get_default_sink() -> Option<String> {
        let output = Command::new("pactl")
            .arg("get-default-sink")
            .output()
            .ok()?;
        if output.status.success() {
            let sink = String::from_utf8_lossy(&output.stdout).trim().to_string();
            if !sink.is_empty() {
                return Some(sink);
            }
        }
        None
    }

    pub fn start(&self) {
        let bands_c = self.bands.clone();
        let target_app_c = self.target_app.clone();
        let sensitivity_c = self.sensitivity.clone();

        std::thread::spawn(move || {
            info!("🎵 Initializing Ultra-Consistent CPAL Audio Capture...");

            let host = cpal::default_host();
            loop {
                let device = match host.default_input_device() {
                    Some(d) => d,
                    None => {
                        std::thread::sleep(std::time::Duration::from_secs(3));
                        continue;
                    }
                };

                let config = match device.default_input_config() {
                    Ok(c) => c,
                    Err(_) => {
                        std::thread::sleep(std::time::Duration::from_secs(3));
                        continue;
                    }
                };

                let planner = FftPlanner::new();
                let fft = Arc::new(Mutex::new(planner));
                let samples_buf = Arc::new(Mutex::new(Vec::with_capacity(2048)));
                
                let bands_p = bands_c.clone();
                let sens_p = sensitivity_c.clone();

                let err_fn = |err| error!("❌ Stream error: {}", err);

                let stream_result = match config.sample_format() {
                    cpal::SampleFormat::F32 => device.build_input_stream(
                        &config.into(),
                        move |data: &[f32], _| write_input_data(data, &samples_buf, &fft, &bands_p, &sens_p),
                        err_fn,
                        None 
                    ),
                    cpal::SampleFormat::I16 => device.build_input_stream(
                        &config.into(),
                        move |data: &[i16], _| write_input_data_i16(data, &samples_buf, &fft, &bands_p, &sens_p),
                        err_fn,
                        None
                    ),
                    _ => {
                        std::thread::sleep(std::time::Duration::from_secs(3));
                        continue;
                    }
                };

                if let Ok(stream) = stream_result {
                    if let Err(e) = stream.play() {
                        error!("❌ Failed to play stream: {}", e);
                    } else {
                        info!("✅ Beat-Optimized Audio Capture Started (7 Bands)!");
                        
                        // Keep a reference to the stream to ensure it's not dropped
                        let _stream_ref = stream;
                        
                        loop {
                            let target = match target_app_c.lock() {
                                Ok(t) => t.clone(),
                                Err(_) => break, // Mutex poisoned, break to restart
                            };

                            if let Some(our_node) = find_our_node() {
                                let mut app_linked = false;
                                let our_fl = format!("{}:input_FL", our_node);
                                let our_fr = format!("{}:input_FR", our_node);

                                if let Some(app_name) = &target {
                                    if let Some((fl, fr)) = find_app_ports(app_name) {
                                        if let Some(sink_name) = Self::get_default_sink() {
                                            let _ = Command::new("pw-link").arg("-d").arg(format!("{}:monitor_FL", sink_name)).arg(&our_fl).output();
                                            let _ = Command::new("pw-link").arg("-d").arg(format!("{}:monitor_FR", sink_name)).arg(&our_fr).output();
                                        }

                                        let _ = Command::new("pw-link").arg(&fl).arg(&our_fl).output();
                                        let _ = Command::new("pw-link").arg(&fr).arg(&our_fr).output();
                                        app_linked = true;
                                    }
                                }

                                if !app_linked {
                                    if let Some(sink_name) = Self::get_default_sink() {
                                        let monitor_fl = format!("{}:monitor_FL", sink_name);
                                        let monitor_fr = format!("{}:monitor_FR", sink_name);
                                        let _ = Command::new("pw-link").arg(&monitor_fl).arg(&our_fl).output();
                                        let _ = Command::new("pw-link").arg(&monitor_fr).arg(&our_fr).output();
                                        let _ = Command::new("pactl").arg("set-source-mute").arg(format!("{}.monitor", sink_name)).arg("0").output();
                                    }
                                }
                            }
                            std::thread::sleep(std::time::Duration::from_secs(4));
                        }
                    }
                } else {
                    std::thread::sleep(std::time::Duration::from_secs(3));
                }
            }
        });
    }

    pub fn get_levels(&self) -> Vec<f32> {
        self.bands.lock().unwrap().clone()
    }
}

fn find_our_node() -> Option<String> {
    if let Ok(out) = Command::new("wpctl").arg("status").output() {
        let stdout = String::from_utf8_lossy(&out.stdout);
        for line in stdout.lines() {
            if line.contains("wayland_connect_backend") {
                let parts: Vec<&str> = line.split('.').collect();
                if parts.len() >= 2 {
                    return Some(parts[0].trim().to_string());
                }
            }
        }
    }
    None
}

fn find_app_ports(app_name: &str) -> Option<(String, String)> {
    let search_term = app_name
        .replace("org.mpris.MediaPlayer2.", "")
        .split('.')
        .next()
        .unwrap_or(app_name)
        .to_lowercase();

    if let Ok(out) = Command::new("pw-dump").output() {
        if let Ok(val) = serde_json::from_slice::<serde_json::Value>(&out.stdout) {
            if let Some(nodes) = val.as_array() {
                for node in nodes {
                    if let Some(props) = node.get("info").and_then(|i| i.get("props")) {
                        let node_app_name = props.get("application.name").and_then(|n| n.as_str()).unwrap_or("").to_lowercase();
                        let node_name = props.get("node.name").and_then(|n| n.as_str()).unwrap_or("").to_lowercase();
                        let node_nick = props.get("node.nick").and_then(|n| n.as_str()).unwrap_or("").to_lowercase();
                        
                        if node_app_name.contains(&search_term) || 
                           node_name.contains(&search_term) ||
                           node_nick.contains(&search_term) {
                            
                            if let Some(id) = node.get("id") {
                                let node_id = id.to_string();
                                return Some((format!("{}:output_FL", node_id), format!("{}:output_FR", node_id)));
                            }
                        }
                    }
                }
            }
        }
    }
    None
}

fn write_input_data_i16(data: &[i16], buf: &Arc<Mutex<Vec<f32>>>, fft: &Arc<Mutex<FftPlanner<f32>>>, bands: &Arc<Mutex<Vec<f32>>>, sens: &Arc<Mutex<f32>>) {
    let f32_data: Vec<f32> = data.iter().map(|&x| x as f32 / i16::MAX as f32).collect();
    write_input_data(&f32_data, buf, fft, bands, sens);
}

fn write_input_data(data: &[f32], buf: &Arc<Mutex<Vec<f32>>>, fft_planner: &Arc<Mutex<FftPlanner<f32>>>, bands_p: &Arc<Mutex<Vec<f32>>>, sens: &Arc<Mutex<f32>>) {
    let mut buffer = buf.lock().unwrap();
    buffer.extend_from_slice(data);

    while buffer.len() >= 1024 {
        let mut planner = fft_planner.lock().unwrap();
        let fft = planner.plan_fft_forward(1024);
        
        let chunk = buffer.drain(0..1024).collect::<Vec<f32>>();
        let mut buffer_complex: Vec<Complex<f32>> = chunk.iter().enumerate()
            .map(|(i, &s)| {
                let window = 0.5 * (1.0 - (2.0 * PI * i as f32 / 1023.0).cos());
                Complex { re: s * window, im: 0.0 }
            })
            .collect();
        
        fft.process(&mut buffer_complex);

        let magnitudes: Vec<f32> = buffer_complex.iter()
            .take(512)
            .map(|c| (c.re.powi(2) + c.im.powi(2)).sqrt() / 4.0)
            .collect();

        let mut current_bands = vec![0.0f32; 7];
        let scalar = *sens.lock().unwrap();

        // 7-Band Distribution (Bins out of 512, ~22Hz per bin)
        // 1: Sub-Bass (0-3 bins, ~66Hz)
        // 2: Bass (3-12 bins, ~264Hz)
        // 3: Low-Mid (12-24 bins, ~528Hz)
        // 4: Mid (24-96 bins, ~2.1kHz)
        // 5: High-Mid (96-192 bins, ~4.2kHz)
        // 6: High (192-320 bins, ~7kHz)
        // 7: Brilliance (320-512 bins, >7kHz)
        
        for (j, &mag) in magnitudes.iter().enumerate() {
            if j < 3 { current_bands[0] += mag; }
            else if j < 12 { current_bands[1] += mag; }
            else if j < 24 { current_bands[2] += mag; }
            else if j < 96 { current_bands[3] += mag; }
            else if j < 192 { current_bands[4] += mag; }
            else if j < 320 { current_bands[5] += mag; }
            else { current_bands[6] += mag; }
        }

        // Apply distinct scaling for each band to normalize visual energy
        let normalizers = [3.0, 8.0, 10.0, 15.0, 20.0, 25.0, 30.0];
        
        if let Ok(mut b) = bands_p.lock() {
            for i in 0..7 {
                let target = ((current_bands[i] / normalizers[i]) * scalar).min(1.0);
                let attack = if target > b[i] { 0.85 } else { 0.35 };
                b[i] = b[i] * (1.0 - attack) + target * attack;
            }
        }
    }
}
