use std::sync::{Arc, Mutex};
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use rustfft::{FftPlanner, num_complex::Complex, num_traits::Zero};
use tracing::{info, error};
use anyhow::Result;

pub struct AudioAnalyzer {
    // Current magnitudes (frequency bins) for visualization
    pub magnitudes: Arc<Mutex<Vec<f32>>>,
    // Stream holder to keep it alive
    _stream: Option<cpal::Stream>,
}

impl Default for AudioAnalyzer {
    fn default() -> Self {
        Self::new()
    }
}

impl AudioAnalyzer {
    pub fn new() -> Self {
        Self {
            magnitudes: Arc::new(Mutex::new(Vec::new())),
            _stream: None,
        }
    }

    pub fn start(&mut self) -> Result<()> {
        let host = cpal::default_host();
        
        let mut target_device = None;

        // 1. Try to find a monitor source
        if let Ok(devices) = host.input_devices() {
            for dev in devices {
                if let Ok(name) = dev.name() {
                    if name.to_lowercase().contains("monitor") {
                        info!("✅ Found Monitor Source: {}", name);
                        target_device = Some(dev);
                        break;
                    }
                }
            }
        }

        // 2. Fallback to default
        let device = match target_device {
            Some(d) => d,
            None => {
                 info!("⚠️  No Monitor source found, falling back to default input (Microphone).");
                 host.default_input_device()
                    .ok_or_else(|| anyhow::anyhow!("No input device available"))?
            }
        };

        info!("🎤 Using audio input device: {}", device.name().unwrap_or("Unknown".into()));

        let config = device.default_input_config()?;
        let _sample_rate = config.sample_rate().0;
        let channels = config.channels() as usize;

        // Shared state for the callback
        let magnitudes_clone = self.magnitudes.clone();
        
        let err_fn = |err| error!("Audio Stream Error: {}", err);
        
        // FFT Planner
        let mut planner = FftPlanner::new();
        let fft = planner.plan_fft_forward(512); // Window size
        let fft_len = fft.len();
        
        // Use a ring buffer or channel in real world to decouple sensitive audio callback.
        // For simplicity here, we process chunks directly or simpler aggregation.
        // A simple approach: Accumulate samples until we have 512, then FFT.
        
        // Actually, inside the callback we want to be fast.
        // Let's implement a simple mostly-lock-free visualizer logic:
        // We update the mutex only when we have a new FFT result.

        let mut sample_buf = Vec::with_capacity(fft_len);
        let scratch_len = fft.get_inplace_scratch_len();
        let mut scratch = vec![Complex::zero(); scratch_len];

        let stream = device.build_input_stream(
            &config.into(),
            move |data: &[f32], _: &cpal::InputCallbackInfo| {
                // Mix down to mono
                for frame in data.chunks(channels) {
                    let mono = frame.iter().sum::<f32>() / channels as f32;
                    sample_buf.push(Complex { re: mono, im: 0.0 });

                    if sample_buf.len() >= fft_len {
                        // Apply Window Function (Hanning) to reduce leakage
                        // Skipping for performance/brevity here, or apply simple pre-calc window

                         fft.process_with_scratch(&mut sample_buf, &mut scratch);
                         
                         // Calculate magnitudes
                         // Take first half (Nyquist)
                         let output: Vec<f32> = sample_buf.iter()
                             .take(fft_len / 2)
                             .map(|c| c.norm()) // sqrt(re^2 + im^2)
                             .collect();

                         // Update shared state
                         if let Ok(mut lock) = magnitudes_clone.lock() {
                             *lock = output;
                         }

                         sample_buf.clear();
                    }
                }
            },
            err_fn,
            None // Timeout
        )?;

        stream.play()?;
        self._stream = Some(stream);
        
        info!("Audio analysis started.");
        Ok(())
    }
}
