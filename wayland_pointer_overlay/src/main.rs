#![deny(warnings)]
use gtk4::prelude::*;
use gtk4::{Application, ApplicationWindow, DrawingArea, CssProvider};
use gtk4::gdk::Display;
use gtk4_layer_shell::{Layer, LayerShell, Edge, KeyboardMode};
use cairo::Context;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use std::net::UdpSocket;
use std::thread;
mod capture;
use capture::ScreenCapture;

const MAX_TRAIL_POINTS: usize = 45;

#[derive(Clone)]
struct SinglePointerAnimState {
    x: f64,
    y: f64,
    mode: i32,
    opacity: f64,
    width: f64,
    height: f64,
    radius: f64,
    stroke_width: f64,
    fill_alpha: f64,
    trail: Vec<(f64, f64)>,
    glow_intensity: f64,
    color: (f64, f64, f64, f64),
    particle: i32,
    stretch: f64,
    zoom: f64,
}

struct SinglePointerState {
    target_x: f32,
    target_y: f32,
    target_size: f32,
    target_color: String,
    target_zoom: f32,
    target_particle: i32,
    target_stretch: f32,
    active: bool,
    mode: i32,
    monitor_index: i32,
    anim: SinglePointerAnimState,
    test_mode: bool,
}

struct MultiPointerState {
    pointers: std::collections::HashMap<String, SinglePointerState>,
    last_update: Instant,
    custom_image: SendImageSurface,
    capture: Arc<ScreenCapture>,
}

struct SendImageSurface(Option<cairo::ImageSurface>);

unsafe impl Send for SendImageSurface {}
unsafe impl Sync for SendImageSurface {}

fn draw_rounded_rect(ctx: &Context, x: f64, y: f64, w: f64, h: f64, r: f64) {
    let degrees = std::f64::consts::PI / 180.0;
    let r = r.min(w / 2.0).min(h / 2.0);
    ctx.new_sub_path();
    ctx.arc(x + w/2.0 - r, y - h/2.0 + r, r, -90.0 * degrees, 0.0 * degrees);
    ctx.arc(x + w/2.0 - r, y + h/2.0 - r, r, 0.0 * degrees, 90.0 * degrees);
    ctx.arc(x - w/2.0 + r, y + h/2.0 - r, r, 90.0 * degrees, 180.0 * degrees);
    ctx.arc(x - w/2.0 + r, y - h/2.0 + r, r, 180.0 * degrees, 270.0 * degrees);
    ctx.close_path();
}

fn draw_star(ctx: &Context, cx: f64, cy: f64, points: i32, r1: f64, r2: f64) {
    let angle = std::f64::consts::PI / points as f64;
    ctx.new_sub_path();
    for i in 0..(2 * points) {
        let r = if i % 2 == 0 { r2 } else { r1 };
        let a = i as f64 * angle - std::f64::consts::PI / 2.0;
        let x = cx + a.cos() * r;
        let y = cy + a.sin() * r;
        if i == 0 { ctx.move_to(x, y); } else { ctx.line_to(x, y); }
    }
    ctx.close_path();
}

fn draw_polygon(ctx: &Context, cx: f64, cy: f64, sides: i32, radius: f64) {
    let angle = 2.0 * std::f64::consts::PI / sides as f64;
    ctx.new_sub_path();
    for i in 0..sides {
        let a = i as f64 * angle - std::f64::consts::PI / 2.0;
        let x = cx + a.cos() * radius;
        let y = cy + a.sin() * radius;
        if i == 0 { ctx.move_to(x, y); } else { ctx.line_to(x, y); }
    }
    ctx.close_path();
}

fn draw_manifestation(ctx: &Context, mode: i32, particle: i32, cx: f64, cy: f64, w: f64, h: f64, r: f64, scale: f64, custom_image: &Option<cairo::ImageSurface>) {
    if mode == 6 {
        if let Some(img) = custom_image {
             let img_w = img.width() as f64;
             let img_h = img.height() as f64;
             let s_x = (w * scale) / img_w;
             let s_y = (h * scale) / img_h;
             
             ctx.save().unwrap();
             ctx.translate(cx - (w * scale)/2.0, cy - (h * scale)/2.0);
             ctx.scale(s_x, s_y);
             ctx.set_source_surface(img, 0.0, 0.0).unwrap();
             ctx.paint().unwrap();
             ctx.restore().unwrap();
             return;
        }

        match particle {
            1 => draw_star(ctx, cx, cy, 5, w * 0.4 * scale, w * 1.0 * scale), // Celestial
            2 => draw_polygon(ctx, cx, cy, 3, w * 1.0 * scale),           // Plasma
            3 => draw_polygon(ctx, cx, cy, 4, w * 1.0 * scale),           // Kinetic
            _ => draw_rounded_rect(ctx, cx, cy, w * scale, h * scale, r * scale),
        }
    } else {
        draw_rounded_rect(ctx, cx, cy, w * scale, h * scale, r * scale);
    }
}

fn draw_pointer(ctx: &Context, s: &SinglePointerAnimState, screen_w: f64, screen_h: f64, custom_image: &Option<cairo::ImageSurface>, capture: &Arc<ScreenCapture>) {
    let px = s.x * screen_w;
    let py = s.y * screen_h;
    let opacity = s.opacity;
    let glow = s.glow_intensity;
    let (r, g, b, a) = s.color;

    if opacity < 0.001 { return; }
    
    // Debug logging for zoom (Disabled for production multi-pointer or moved to per-pointer logic if needed)
    /*
    static mut LOG_COUNTER: i32 = 0;
    unsafe {
        LOG_COUNTER += 1;
        if LOG_COUNTER % 60 == 0 {
           println!("Overlay Debug: Alpha: {}, Zoom: {}, HasFrame: {}", s.fill_alpha, s.zoom, capture.get_latest_frame().is_some());
        }
    }
    */

    // ========== 0. MAGNIFIER CONTENT (New) ==========
    // Logic: If hollow mode (fill_alpha < 0.5) AND zoom > 1.05
    if s.fill_alpha < 0.5 && s.zoom > 1.05 {
        if let Some((frame_data, fw, fh)) = capture.get_latest_frame() {
             // println!("Rendering Magnifier Frame: {}x{}", fw, fh);
             ctx.save().unwrap();
             
             // Define the clipping path (the hole)
             // Mode 6: Special "Zoom Screen" behavior (Large Lens)
             let (m_w, m_h, m_r) = if s.mode == 6 {
                 (screen_w * 0.75, screen_h * 0.75, 40.0) // Very large lens
             } else {
                 (s.width, s.height, s.radius)
             };

             let punch_width = (m_w - s.stroke_width * 1.5).max(0.0);
             let punch_height = (m_h - s.stroke_width * 1.5).max(0.0);
             let punch_radius = (m_r - s.stroke_width * 0.75).max(0.0);
             draw_manifestation(ctx, s.mode, s.particle, px, py, punch_width, punch_height, punch_radius, 1.0, custom_image);
             ctx.clip();
             
             // Calculate source rectangle
             // We want the area centered at (px, py) with size (view_w, view_h)
             let scale = s.zoom;
             let view_w = (screen_w / scale).ceil() as i32;
             let view_h = (screen_h / scale).ceil() as i32;
             
             let src_x = (px - view_w as f64 / 2.0) as i32;
             let src_y = (py - view_h as f64 / 2.0) as i32;

             // Create a surface for just the view area
             let mut surf = cairo::ImageSurface::create(cairo::Format::Rgb24, view_w, view_h).unwrap();
             
             // Copy pixels from frame_data to surf
             // frame_data is BGRx (which maps to Format::Rgb24 on Little Endian usually)
             // We need to handle bounds checking
             
             // Copy pixels using .data() which returns a mutable guard
             if let Ok(mut data_guard) = surf.data() {
                 let dest = &mut *data_guard;
                 let src_stride = (fw * 4) as usize;
                 let dest_stride = (view_w * 4) as usize;
                 
                 for dy in 0..view_h {
                     let sy = src_y + dy;
                     if sy < 0 || sy >= fh as i32 { continue; } // Out of bounds vertical
                     
                     let row_src_start = (sy as usize * src_stride) as usize;
                     let row_dest_start = (dy as usize * dest_stride) as usize;
                     
                     for dx in 0..view_w {
                         let sx = src_x + dx;
                         if sx < 0 || sx >= fw as i32 { continue; } // Out of bounds horizontal
                         
                         let offset_src = row_src_start + (sx as usize * 4);
                         let offset_dest = row_dest_start + (dx as usize * 4);
                         
                         // Copy 4 bytes (Pixel)
                         // Safety: We checked bounds
                         if offset_src + 4 <= frame_data.len() && offset_dest + 4 <= dest.len() {
                            dest[offset_dest..offset_dest+4].copy_from_slice(&frame_data[offset_src..offset_src+4]);
                         }
                     }
                 }
             }

             // Draw the surface
             // We translate so that (src_x, src_y) maps to (0,0) of the surface?
             // No, we are drawing 'surf' which represents the view rectangle.
             // We want this surface to fill the screen space corresponding to the view rectangle... 
             // actually, we want it to fill the HOLE which is at (px, py).
             // But we applied a clip.
             // The clip is the hole.
             // We want to draw the magnified content such that the center of 'surf' is at (px, py).
             // 'surf' has size (view_w, view_h).
             // Can we just scale it up by 'scale'?
             // If we scale 'surf' by 'scale', it becomes size (screen_w, screen_h).
             // And we draw it centered at (px, py)?
             // Wait, 'view_w' = screen_w / scale.
             // So 'view_w * scale' = screen_w.
             // Yes. So if we just draw 'surf' scaled up, it covers the whole screen.
             // And since 'surf' contains the pixels from the center of the screen (src_x, src_y), 
             // effectively we are doing a "zoom center".
             // We need to position 'surf' such that its content aligns correctly.
             // The top-left of 'surf' corresponds to (src_x, src_y) in "world" space.
             // So if we draw it at (src_x, src_y)? No, we want it magnified.
             // We want the pixel at (cx, cy) of surf to be at (px, py) of screen.
             // And it should be drawn with scale 'scale'.
             
             // Let's reset transform to identity first? No, context is identity (0..screen_w, 0..screen_h).
             // We want to draw 'surf'.
             // We scale it: ctx.scale(scale, scale). 
             // Now drawing at (0,0) draws a huge image.
             // We want the result to be that the center of the image is at (px, py).
             // The center of surf is (view_w/2, view_h/2).
             // Scaled center is (view_w*scale/2, view_h*scale/2) = (screen_w/2, screen_h/2).
             // So if we just scale and draw at (0,0), it covers the screen perfectly IF px/py is center.
             // But px/py might NOT be center of screen (e.g. pointer moves).
             // src_x/src_y follows px/py.
             // logic:
             // 1. We captured a crop at (src_x, src_y).
             // 2. We want to display this crop... where?
             //    If we display it as a magnifier, we want "what is under the pointer" (src_x,src_y) to appear "under the pointer" (px,py) but bigger.
             //    But if we magnify, the pixel at px,py stays at px,py.
             //    The pixels AROUND it move away. 
             //    So yes, zooming centered at px,py.
             
             // Step 1: Translate to pivot (px, py)
             ctx.translate(px, py);
             // Step 2: Scale
             ctx.scale(scale, scale);
             // Step 3: Translate back by half the size of the surface
             // The surface represents the area centered at px, py (roughly).
             // width is view_w. 
             ctx.translate(-view_w as f64 / 2.0, -view_h as f64 / 2.0);
                          // Draw surface
              // Use paint_with_alpha so it fades out with the pointer
              ctx.set_source_surface(&surf, 0.0, 0.0).unwrap();
              ctx.paint_with_alpha(opacity).unwrap();
              
              ctx.restore().unwrap();
        } else {
             // NO FRAME: Keep it hollow (do nothing)
        }
    }

    // ========== 1. DRAW TAIL (Mode 6 Only) - High Quality Trail ==========
    if s.mode == 6 && s.trail.len() > 1 {
        ctx.set_line_cap(cairo::LineCap::Round);
        ctx.set_line_join(cairo::LineJoin::Round);
        
        let count = s.trail.len();
        for i in 0..count-1 {
            let (x1, y1) = s.trail[i];
            let (x2, y2) = s.trail[i+1];
            
            // Fade out the trail
            let alpha = (1.0 - (i as f64 / count as f64)) * 0.6 * opacity * a;
            // Taper the width
            let width = s.width * 0.4 * (1.0 - (i as f64 / count as f64) * 0.8);
            
            ctx.set_source_rgba(r, g, b, alpha);
            ctx.set_line_width(width.max(1.0));
            
            ctx.move_to(x1 * screen_w, y1 * screen_h);
            ctx.line_to(x2 * screen_w, y2 * screen_h);
            ctx.stroke().unwrap();
        }
    }

    ctx.save().unwrap();
    
    // ========== INVERSE CLIP (For surgical transparency in hollow modes) ==========
    if s.fill_alpha < 0.5 {
        // Create an inverse clip path: Giant rect minus the inner shape
        ctx.set_fill_rule(cairo::FillRule::EvenOdd);
        ctx.rectangle(0.0, 0.0, screen_w, screen_h);
        
        // The inner shape is where we want transparency
        // We punch a hole slightly smaller than the outer path to show the stroke properly
        let punch_width = (s.width - s.stroke_width * 1.5).max(0.0);
        let punch_height = (s.height - s.stroke_width * 1.5).max(0.0);
        let punch_radius = (s.radius - s.stroke_width * 0.75).max(0.0);
        draw_manifestation(ctx, s.mode, s.particle, px, py, punch_width, punch_height, punch_radius, 1.0, custom_image);
        
        ctx.clip();
        ctx.set_fill_rule(cairo::FillRule::Winding);
    }

    // ========== 2. OUTER GLOW (Monochrome Volumetric) ==========
    if s.fill_alpha < 0.5 {
        // Hollow: Volumetric Shadow & Glow (Outside Only)
        // Layer 1: Soft White Glow
        ctx.set_source_rgba(1.0, 1.0, 1.0, 0.15 * opacity * glow * a);
        ctx.set_line_width(s.stroke_width + 12.0);
        draw_manifestation(ctx, s.mode, s.particle, px, py, s.width, s.height, s.radius, 1.0, custom_image);
        ctx.stroke().unwrap();
        
        // Layer 2: Deep Black Shadow
        ctx.set_source_rgba(0.0, 0.0, 0.0, 0.25 * opacity * glow * a);
        ctx.set_line_width(s.stroke_width + 30.0);
        draw_manifestation(ctx, s.mode, s.particle, px, py, s.width, s.height, s.radius, 1.0, custom_image);
        ctx.stroke().unwrap();

        // Layer 3: Far Atmospheric Shadow
        ctx.set_source_rgba(0.0, 0.0, 0.0, 0.08 * opacity * glow * a);
        ctx.set_line_width(s.stroke_width + 60.0);
        draw_manifestation(ctx, s.mode, s.particle, px, py, s.width, s.height, s.radius, 1.0, custom_image);
        ctx.stroke().unwrap();
    } else {
        // Solid: Multi-Layered Shadows
        ctx.set_source_rgba(0.0, 0.0, 0.0, 0.25 * opacity * glow * a);
        draw_manifestation(ctx, s.mode, s.particle, px, py, s.width, s.height, s.radius, 1.4, custom_image);
        ctx.fill().unwrap();

        ctx.set_source_rgba(1.0, 1.0, 1.0, 0.1 * opacity * glow * a);
        draw_manifestation(ctx, s.mode, s.particle, px, py, s.width, s.height, s.radius, 1.1, custom_image);
        ctx.fill().unwrap();
    }

    // ========== 3. MAIN SHAPE (High Contrast) ==========
    ctx.set_source_rgba(0.2, 0.2, 0.2, 0.9 * opacity); // Softened from pure black
    if s.fill_alpha > 0.5 {
        draw_manifestation(ctx, s.mode, s.particle, px, py, s.width, s.height, s.radius, 1.15, custom_image);
        ctx.fill().unwrap();
    } else {
        ctx.set_line_width(s.stroke_width + 4.5);
        draw_manifestation(ctx, s.mode, s.particle, px, py, s.width, s.height, s.radius, 1.0, custom_image);
        ctx.stroke().unwrap();
    }

    // Pure Thematic Color Shape
    ctx.set_source_rgba(r, g, b, opacity * a);
    draw_manifestation(ctx, s.mode, s.particle, px, py, s.width, s.height, s.radius, 1.0, custom_image);

    if s.fill_alpha > 0.5 {
        ctx.fill().unwrap();
    } else {
        ctx.set_line_width(s.stroke_width);
        ctx.stroke().unwrap();
    }

    ctx.restore().unwrap();
}

fn parse_hex_color(hex: &str) -> (f64, f64, f64, f64) {
    let hex = hex.trim_start_matches('#');
    if hex.len() == 8 {
        // Android Color.toRadixString(16) outputs AARRGGBB
        let a = u8::from_str_radix(&hex[0..2], 16).unwrap_or(255) as f64 / 255.0;
        let r = u8::from_str_radix(&hex[2..4], 16).unwrap_or(255) as f64 / 255.0;
        let g = u8::from_str_radix(&hex[4..6], 16).unwrap_or(255) as f64 / 255.0;
        let b = u8::from_str_radix(&hex[6..8], 16).unwrap_or(255) as f64 / 255.0;
        (r, g, b, a)
    } else if hex.len() == 6 {
        let r = u8::from_str_radix(&hex[0..2], 16).unwrap_or(255) as f64 / 255.0;
        let g = u8::from_str_radix(&hex[2..4], 16).unwrap_or(255) as f64 / 255.0;
        let b = u8::from_str_radix(&hex[4..6], 16).unwrap_or(255) as f64 / 255.0;
        (r, g, b, 1.0)
    } else {
        (1.0, 1.0, 1.0, 1.0) // White Default
    }
}

fn damp(current: f64, target: f64, smoothing: f64, dt: f64) -> f64 {
    let factor = 1.0 - (-smoothing * dt).exp();
    current + (target - current) * factor
}

fn main() {
    println!("🚀 OVERLAY STARTING");
    let app = Application::builder()
        .application_id("com.wayland.connect.pointer")
        .build();

    app.connect_activate(|app| {
        println!("🚀 OVERLAY ACTIVATE TRIGGERED");
        let provider = CssProvider::new();
        // Transparent again
        provider.load_from_data("window, drawingarea { background-color: rgba(0, 0, 0, 0); }");
        gtk4::style_context_add_provider_for_display(
            &Display::default().expect("No display"),
            &provider,
            gtk4::STYLE_PROVIDER_PRIORITY_APPLICATION,
        );

        let state = Arc::new(Mutex::new(MultiPointerState {
            pointers: std::collections::HashMap::new(),
            last_update: Instant::now(),
            custom_image: SendImageSurface(None),
            capture: Arc::new(ScreenCapture::new()),
        }));
        
        // REMOVED: capture.start() - Now started lazily via UDP command

        let window = ApplicationWindow::builder()
            .application(app)
            .title("Wayland Connect Pointer Overlay")
            .build();

        window.init_layer_shell();
        window.set_layer(Layer::Overlay);
        window.set_namespace("wayland_connect_overlay");
        window.set_exclusive_zone(-1);
        window.set_keyboard_mode(KeyboardMode::None);
        
        // Full screen anchors
        window.set_anchor(Edge::Top, true);
        window.set_anchor(Edge::Left, true);
        window.set_anchor(Edge::Right, true);
        window.set_anchor(Edge::Bottom, true);
        
        window.set_namespace("pointer_overlay");

        let drawing_area = DrawingArea::new();
        window.set_child(Some(&drawing_area));
        
        // Make it click-through
        window.connect_map(|win| {
            if let Some(surface) = win.surface() {
                let region = cairo::Region::create();
                surface.set_input_region(&region);
            }
        });

        let state_draw = state.clone();
        drawing_area.set_draw_func(move |_, ctx, w, h| {
            let s = state_draw.lock().unwrap();
            for pointer in s.pointers.values() {
                draw_pointer(ctx, &pointer.anim, w as f64, h as f64, &s.custom_image.0, &s.capture);
            }
        });

        let state_tick = state.clone();
        let da_tick = drawing_area.clone();
        let win_tick = window.clone();
        
        window.present();
        println!("🚀 OVERLAY WINDOW PRESENTED - Ready for production signals");

        drawing_area.add_tick_callback(move |_, _clock| {
            let now = Instant::now();
            let mut s = state_tick.lock().unwrap();
            
            static mut TICK_COUNT: u64 = 0;
            let active_count = s.pointers.values().filter(|p| p.active).count();
            unsafe {
                TICK_COUNT += 1;
                if TICK_COUNT % 120 == 0 {
                    println!("💓 HEARTBEAT: active_pointers={}", active_count);
                }
            }

            let dt = now.duration_since(s.last_update).as_secs_f64().min(0.1);
            s.last_update = now;
            
            let mut has_zoom = None;
            for (_id, pointer) in s.pointers.iter_mut() {
                // Movement Smoothing
                pointer.anim.x = damp(pointer.anim.x, pointer.target_x as f64, 120.0, dt);
                pointer.anim.y = damp(pointer.anim.y, pointer.target_y as f64, 120.0, dt);
                
                // Opacity
                let target_op = if pointer.active || pointer.test_mode { 1.0 } else { 0.0 };
                let op_smoothing = if pointer.active || pointer.test_mode { 30.0 } else { 45.0 };
                pointer.anim.opacity = damp(pointer.anim.opacity, target_op, op_smoothing, dt);
                
                if pointer.anim.opacity > 0.01 && !win_tick.is_visible() { 
                    win_tick.set_visible(true); 
                }
                
                // Monitor update logic (simplified for multi-pointer: using the last one updated)
                // In practice, usually all devices target the same monitor or have independent monitors.
                // For now, let's keep it simple.
                let display = Display::default().expect("No display");
                let monitors = display.monitors();
                if pointer.monitor_index >= 0 && (pointer.monitor_index as u32) < monitors.n_items() {
                    if let Some(m) = monitors.item(pointer.monitor_index as u32).and_then(|i| i.downcast::<gtk4::gdk::Monitor>().ok()) {
                        win_tick.set_monitor(&m);
                    }
                }
                
                // Morphing
                let (t_w, t_h, t_r, t_sw, t_fa) = match pointer.mode {
                    0 => (40.0, 40.0, 20.0, 2.0, 1.0),    
                    1 => (90.0, 90.0, 45.0, 4.0, 0.0),    
                    2 => (8.0, 450.0, 4.0, 2.0, 1.0),     
                    3 => (450.0, 8.0, 4.0, 2.0, 1.0),     
                    4 => (400.0, 20.0, 10.0, 4.0, 0.0),   
                    5 => (20.0, 400.0, 10.0, 4.0, 0.0),   
                    6 => (30.0, 30.0, 15.0, 2.0, 0.0),    
                    _ => (40.0, 40.0, 20.0, 2.0, 1.0),    
                };
                
                let scale = pointer.target_size as f64;
                let zoom = pointer.target_zoom as f64;
                
                let (mut t_w, mut t_h, t_r, t_sw) = match pointer.mode {
                    3 | 4 => ((t_w * scale).min(1200.0), t_h, t_r, t_sw), 
                    2 | 5 => (t_w, (t_h * scale).min(1200.0), t_r, t_sw), 
                    6 => (t_w * scale, t_h * scale, t_r * scale, t_sw * scale),
                    _ => (t_w * scale, t_h * scale, t_r * scale, t_sw * scale),
                };

                if pointer.mode == 4 { t_w *= pointer.anim.stretch; }
                if pointer.mode == 5 { t_h *= pointer.anim.stretch; }
                
                let morph_speed = 35.0;
                pointer.anim.width = damp(pointer.anim.width, t_w, morph_speed, dt);
                pointer.anim.height = damp(pointer.anim.height, t_h, morph_speed, dt);
                pointer.anim.radius = damp(pointer.anim.radius, t_r, morph_speed, dt);
                pointer.anim.stroke_width = damp(pointer.anim.stroke_width, t_sw, 10.0, dt);
                pointer.anim.fill_alpha = damp(pointer.anim.fill_alpha, t_fa, 10.0, dt);
                
                let target_z = if pointer.active && (pointer.mode == 1 || pointer.mode == 4 || pointer.mode == 5 || pointer.mode == 6) && zoom != 1.0 { 
                    zoom 
                } else { 
                    1.0 
                };
                let zoom_smoothing = if target_z < 1.01 && pointer.anim.zoom > 1.01 { 120.0 } else { 75.0 };
                pointer.anim.zoom = damp(pointer.anim.zoom, target_z, zoom_smoothing, dt);
                
                // Set Exclusion Rect (Simplified: uses the last zooming pointer)
                if pointer.anim.zoom > 1.05 && pointer.anim.fill_alpha < 0.5 {
                     let w_l = win_tick.width() as f64;
                     let h_l = win_tick.height() as f64;
                     let (m_w, m_h) = if pointer.mode == 6 { (w_l * 0.75, h_l * 0.75) } else { (pointer.anim.width, pointer.anim.height) };
                     let b_w = m_w * 1.25;
                     let b_h = m_h * 1.25;
                     let nw = b_w / w_l.max(1.0);
                     let nh = b_h / h_l.max(1.0);
                     let nx = pointer.anim.x - nw / 2.0;
                     let ny = pointer.anim.y - nh / 2.0;
                     has_zoom = Some((nx, ny, nw, nh));
                }

                pointer.anim.color = {
                    let (cr, cg, cb, ca) = parse_hex_color(&pointer.target_color);
                    (
                        damp(pointer.anim.color.0, cr, 60.0, dt),
                        damp(pointer.anim.color.1, cg, 60.0, dt),
                        damp(pointer.anim.color.2, cb, 60.0, dt),
                        damp(pointer.anim.color.3, ca, 60.0, dt),
                    )
                };
                pointer.anim.particle = pointer.target_particle;
                pointer.anim.mode = pointer.mode;
                
                if pointer.mode == 6 && pointer.active { 
                    let current_pos = (pointer.anim.x, pointer.anim.y);
                    pointer.anim.trail.insert(0, current_pos);
                    if pointer.anim.trail.len() > MAX_TRAIL_POINTS { pointer.anim.trail.pop(); }
                } else if !pointer.anim.trail.is_empty() {
                    pointer.anim.trail.pop();
                }

                pointer.anim.glow_intensity = 0.8 + 0.2 * (now.elapsed().as_secs_f64() * 5.0).sin().abs();
            } // This is the closing brace for the `for` loop.
            
            s.capture.set_exclusion_rect(has_zoom);
            da_tick.queue_draw();
            glib::ControlFlow::Continue
        });

        // UDP Listener
        let state_udp = state.clone();
        thread::spawn(move || {
            let socket = loop {
                if let Ok(s) = UdpSocket::bind(wc_core::constants::POINTER_OVERLAY_ADDR) { break s; }
                thread::sleep(Duration::from_millis(500));
            };
            let mut buf = [0u8; 512];
            loop {
                if let Ok((amt, _)) = socket.recv_from(&mut buf) {
                    let msg = String::from_utf8_lossy(&buf[..amt]);
                    let msg = msg.trim();
                    
                    let (device_id, payload) = if let Some(idx) = msg.find('|') {
                        (&msg[..idx], &msg[idx+1..])
                    } else {
                        ("default", msg)
                    };

                    println!("📬 OVERLAY RECEIVED for {}: {}", device_id, payload);
                    let mut s = state_udp.lock().unwrap();
                    let mut clear_img = false;
                    {
                        let pointer = s.pointers.entry(device_id.to_string()).or_insert_with(|| SinglePointerState {
                            target_x: 0.5,
                            target_y: 0.5,
                            active: false,
                            mode: 0,
                            target_size: 1.0,
                            target_color: "#ffffffff".to_string(),
                            target_zoom: 1.0,
                            target_particle: 0,
                            target_stretch: 1.0,
                            monitor_index: 0,
                            anim: SinglePointerAnimState {
                                x: 0.5, y: 0.5, mode: 0, width: 40.0, height: 40.0, radius: 20.0,
                                stroke_width: 2.0, fill_alpha: 1.0, opacity: 0.0, trail: Vec::new(),
                                glow_intensity: 1.0, color: (1.0, 1.0, 1.0, 1.0), particle: 0, stretch: 1.0, zoom: 1.0,
                            },
                            test_mode: false,
                        });

                        if payload == "STOP" {
                            pointer.active = false;
                            println!("🛑 OVERLAY {}: STOP", device_id);
                        } else if payload == "START" {
                            pointer.active = true;
                            println!("🟢 OVERLAY {}: START", device_id);
                        } else if payload == "TEST_SEQUENCE" {
                            println!("🧪 OVERLAY {}: RUNNING TEST SEQUENCE (Cycling All Modes)", device_id);
                            let state_test = state_udp.clone();
                            let d_id = device_id.to_string();
                            thread::spawn(move || {
                                {
                                    let mut s = state_test.lock().unwrap();
                                    if let Some(p) = s.pointers.get_mut(&d_id) {
                                        p.test_mode = true;
                                        p.target_x = 0.5;
                                        p.target_y = 0.5;
                                        println!("🧪 TEST {}: FORCING TEST_MODE=TRUE", d_id);
                                    }
                                }
                                for mode in 0..=6 {
                                    {
                                        let mut s = state_test.lock().unwrap();
                                        if let Some(p) = s.pointers.get_mut(&d_id) { 
                                            p.mode = mode; 
                                            println!("🧪 TEST {}: Switching to Mode {}", d_id, mode);
                                        }
                                    }
                                    thread::sleep(Duration::from_millis(2000));
                                }
                                {
                                    let mut s = state_test.lock().unwrap();
                                    if let Some(p) = s.pointers.get_mut(&d_id) {
                                        p.test_mode = false;
                                        p.active = false;
                                        println!("🧪 TEST {}: Sequence Complete (test_mode=false)", d_id);
                                    }
                                }
                            });
                        } else if payload == "START_CAPTURE" {
                            s.capture.start();
                            println!("📸 OVERLAY: Started screen capture");
                        } else if payload == "RELOAD_IMAGE" {
                            if let Ok(mut f) = std::fs::File::open(wc_core::constants::POINTER_IMAGE_PATH) {
                                if let Ok(surf) = cairo::ImageSurface::create_from_png(&mut f) {
                                    s.custom_image.0 = Some(surf);
                                    println!("✅ OVERLAY reloaded custom image");
                                }
                            }
                        } else if payload == "CLEAR_IMAGE" {
                            clear_img = true;
                        } else if payload.starts_with("MONITOR:") {
                            if let Ok(idx) = payload[8..].trim().parse::<i32>() { 
                                pointer.monitor_index = idx; 
                                println!("🖥️ OVERLAY {}: Set monitor to {}", device_id, idx);
                            }
                        } else if payload.starts_with("SIZE:") {
                            if let Ok(sz) = payload[5..].trim().parse::<f32>() {
                                println!("🎯 OVERLAY {}: received standalone SIZE: {}", device_id, sz);
                                pointer.target_size = sz;
                            }
                        } else if payload.starts_with("MODE:") {
                            if let Ok(m) = payload[5..].trim().parse::<i32>() { 
                                println!("🎯 OVERLAY {}: received standalone MODE: {}", device_id, m);
                                pointer.mode = m; 
                            }
                        } else {
                            let parts: Vec<&str> = payload.split(',').collect();
                            if parts.len() >= 3 {
                                if let (Ok(x), Ok(y)) = (parts[0].trim().parse::<f32>(), parts[1].trim().parse::<f32>()) {
                                    pointer.target_x = x; 
                                    pointer.target_y = y; 
                                    pointer.active = true;
                                    if let Ok(m) = parts[2].trim().parse::<i32>() {
                                        if pointer.mode != m {
                                            println!("🎯 OVERLAY {}: mode changed to: {}", device_id, m);
                                            pointer.mode = m;
                                        }
                                    }
                                    if parts.len() >= 4 { 
                                        pointer.target_size = parts[3].trim().parse().unwrap_or(1.0); 
                                    }
                                    if parts.len() >= 5 {
                                        pointer.target_color = parts[4].to_string();
                                    }
                                    if parts.len() >= 6 {
                                        pointer.target_zoom = parts[5].parse().unwrap_or(1.0);
                                    }
                                    if parts.len() >= 7 {
                                        pointer.target_particle = parts[6].parse().unwrap_or(0);
                                    }
                                    if parts.len() >= 8 {
                                        let has_img = parts[7].trim().parse::<i32>().unwrap_or(0) == 1;
                                        if !has_img {
                                            clear_img = true;
                                        }
                                    }
                                    if parts.len() >= 9 {
                                        pointer.target_stretch = parts[8].trim().parse().unwrap_or(1.0);
                                    }
                                }
                            }
                        }
                    }
                    if clear_img {
                        s.custom_image.0 = None;
                        println!("🗑️ OVERLAY cleared custom image");
                    }
                }
            }
        });
    });
    app.run();
}
