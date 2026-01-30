use wc_core::types::Resolution;
use bytes::{Bytes, BytesMut};

pub struct Magnifier {
    pub scale_factor: f32, // e.g. 2.0
    pub output_resolution: Resolution,
}

impl Magnifier {
    pub fn new(scale_factor: f32, width: u32, height: u32) -> Self {
        Self {
            scale_factor,
            output_resolution: Resolution { width, height },
        }
    }

    /// Zooms into the frame centered at (cx, cy)
    /// Expects BGRx/RGBx (4 bytes per pixel)
    pub fn process(&self, input: &[u8], input_res: Resolution, cx: i32, cy: i32) -> Bytes {
        let in_w = input_res.width as usize;
        let in_h = input_res.height as usize;
        let out_w = self.output_resolution.width as usize;
        let out_h = self.output_resolution.height as usize;
        let scale = self.scale_factor;

        // 1. Calculate the view rectangle in input coordinates
        // Width of the region to be upscaled to fit out_w
        let view_w = (out_w as f32 / scale) as usize;
        let view_h = (out_h as f32 / scale) as usize;

        // Clamped top-left
        let half_w = view_w as i32 / 2;
        let half_h = view_h as i32 / 2;
        
        // Clamp cursor center to keep view inside bounds
        let safe_cx = cx.clamp(half_w, in_w as i32 - half_w);
        let safe_cy = cy.clamp(half_h, in_h as i32 - half_h);

        let start_x = (safe_cx - half_w) as usize;
        let start_y = (safe_cy - half_h) as usize;

        // 2. Allocate Output Buffer
        // 4 bytes per pixel
        let mut output = BytesMut::with_capacity(out_w * out_h * 4);
        
        // 3. Nearest Neighbor Scaling
        // For every pixel in output (dy, dx), find source pixel (sy, sx)
        for dy in 0..out_h {
            let sy = start_y + (dy as f32 / scale) as usize;
            // Bounds check safeguard
            let sy = sy.min(in_h - 1);
            
            let row_offset = sy * in_w * 4;
            
            for dx in 0..out_w {
                let sx = start_x + (dx as f32 / scale) as usize;
                let sx = sx.min(in_w - 1);

                let pixel_offset = row_offset + (sx * 4);
                
                // Copy 4 bytes (B G R X)
                output.extend_from_slice(&input[pixel_offset..pixel_offset+4]);
            }
        }

        output.freeze()
    }
}
