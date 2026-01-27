use gtk4::prelude::*;
use gtk4::{Application, ApplicationWindow, DrawingArea, CssProvider};
use gtk4::gdk::Display;
use gtk4_layer_shell::{Layer, LayerShell, Edge, KeyboardMode};
use cairo::Context;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use std::net::UdpSocket;
use std::thread;

const MAX_TRAIL_POINTS: usize = 30;

#[derive(Clone)]
struct AnimState {
    x: f64,
    y: f64,
    active: bool,
    mode: i32,
    opacity: f64,
    // Morphing Properties
    width: f64,
    height: f64,
    radius: f64,
    stroke_width: f64,
    fill_alpha: f64,
    trail: Vec<(f64, f64)>,  // (x, y) - 0..1 range
    glow_intensity: f64,
}

struct PointerState {
    target_x: f32,
    target_y: f32,
    active: bool,
    mode: i32,
    monitor_index: i32,
    anim: AnimState,
    last_update: Instant,
}

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

fn draw_pointer(ctx: &Context, s: &AnimState, screen_w: f64, screen_h: f64) {
    let px = s.x * screen_w;
    let py = s.y * screen_h;
    let opacity = s.opacity;
    let glow = s.glow_intensity;

    if opacity < 0.001 { return; }

    // ========== 1. DRAW TAIL (Mode 4) - Pure White Comet ==========
    if s.mode == 4 && s.trail.len() > 1 {
        ctx.set_line_cap(cairo::LineCap::Round);
        ctx.set_line_join(cairo::LineJoin::Round);
        ctx.set_source_rgba(1.0, 1.0, 1.0, 0.5 * opacity);
        ctx.set_line_width(s.width * 0.4);
        
        if let Some((first_x, first_y)) = s.trail.first() {
            ctx.move_to(first_x * screen_w, first_y * screen_h);
            for (tx, ty) in s.trail.iter().skip(1) {
                ctx.line_to(tx * screen_w, ty * screen_h);
            }
            ctx.stroke().unwrap();
        }
    }

    // ========== 2. OUTER GLOW (Neutral White) ==========
    ctx.set_source_rgba(1.0, 1.0, 1.0, 0.15 * opacity * glow);
    if s.mode == 3 {
        // High visibility Ring glow
        ctx.set_line_width(s.stroke_width + 12.0);
        draw_rounded_rect(ctx, px, py, s.width, s.height, s.radius);
        ctx.stroke().unwrap();
    } else {
        draw_rounded_rect(ctx, px, py, s.width * 1.5, s.height * 1.5, s.radius * 1.5);
        ctx.fill().unwrap();
    }

    // ========== 3. MAIN SHAPE (High Contrast B&W) ==========
    // Strong Black outline for contrast on white/bright screens
    ctx.set_source_rgba(0.0, 0.0, 0.0, 0.9 * opacity);
    draw_rounded_rect(ctx, px, py, s.width + 3.0, s.height + 3.0, s.radius + 1.5);
    if s.fill_alpha > 0.5 {
        ctx.fill().unwrap();
    } else {
        ctx.set_line_width(s.stroke_width + 3.0);
        ctx.stroke().unwrap();
    }

    // Pure White Shape
    // For Ring (3), we skip Difference operator to keep it clean white
    if s.mode != 3 {
        ctx.set_operator(cairo::Operator::Difference);
    }
    
    ctx.set_source_rgba(1.0, 1.0, 1.0, opacity);
    draw_rounded_rect(ctx, px, py, s.width, s.height, s.radius);
    if s.fill_alpha > 0.5 {
        ctx.fill().unwrap();
    } else {
        ctx.set_line_width(s.stroke_width);
        ctx.stroke().unwrap();
    }
    
    ctx.set_operator(cairo::Operator::Over);

    // ========== 4. PERSISTENT CORE DOT (Mode 2/4) ==========
    if s.mode == 2 || s.mode == 4 {
        ctx.set_source_rgba(1.0, 1.0, 1.0, 1.0 * opacity);
        ctx.arc(px, py, (s.width * 0.2).max(2.5), 0.0, 2.0 * std::f64::consts::PI);
        ctx.fill().unwrap();
    }
}

fn damp(current: f64, target: f64, smoothing: f64, dt: f64) -> f64 {
    let factor = 1.0 - (-smoothing * dt).exp();
    current + (target - current) * factor
}

fn main() {
    println!("🚀 OVERLAY STARTING - DEBUG MODE ACTIVE");
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

        let state = Arc::new(Mutex::new(PointerState {
            target_x: 0.5,
            target_y: 0.5,
            active: false,
            mode: 2,
            monitor_index: 0,
            last_update: Instant::now(),
            anim: AnimState {
                x: 0.5,
                y: 0.5,
                active: false,
                mode: 2,
                width: 28.0,
                height: 28.0,
                radius: 14.0,
                stroke_width: 0.0,
                fill_alpha: 1.0,
                opacity: 0.0,
                trail: Vec::new(),
                glow_intensity: 1.0,
            },
        }));

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
            if s.anim.opacity > 0.001 {
                draw_pointer(ctx, &s.anim, w as f64, h as f64);
            }
        });

        let state_tick = state.clone();
        let da_tick = drawing_area.clone();
        let win_tick = window.clone();
        
        glib::timeout_add_local(Duration::from_millis(10), move || {
            let now = Instant::now();
            let mut s = state_tick.lock().unwrap();
            let dt = now.duration_since(s.last_update).as_secs_f64().min(0.1);
            s.last_update = now;
            
            // Movement Smoothing
            s.anim.x = damp(s.anim.x, s.target_x as f64, 20.0, dt);
            s.anim.y = damp(s.anim.y, s.target_y as f64, 20.0, dt);
            
            // Opacity
            let target_op = if s.active { 1.0 } else { 0.0 };
            s.anim.opacity = damp(s.anim.opacity, target_op, if s.active { 25.0 } else { 10.0 }, dt);
            
            // Sync visibility and monitor
            if !win_tick.is_visible() { win_tick.set_visible(true); }
            
            // Monitor update logic
            static mut LAST_MONITOR: i32 = -1;
            unsafe {
                if LAST_MONITOR != s.monitor_index {
                    let display = Display::default().expect("No display");
                    let monitors = display.monitors();
                    if s.monitor_index >= 0 && (s.monitor_index as u32) < monitors.n_items() {
                        if let Some(m) = monitors.item(s.monitor_index as u32).and_then(|i| i.downcast::<gtk4::gdk::Monitor>().ok()) {
                            println!("🖥️ Overlay switching to monitor {}", s.monitor_index);
                            win_tick.set_monitor(&m);
                        }
                    }
                    LAST_MONITOR = s.monitor_index;
                }
            }
            
            // Morphing
            let (t_w, t_h, t_r, t_sw, t_fa) = match s.mode {
                0 => (200.0, 4.0, 2.0, 0.0, 1.0),   // H-Bar
                1 => (4.0, 200.0, 2.0, 0.0, 1.0),   // V-Bar
                2 => (30.0, 30.0, 15.0, 0.0, 1.0),  // Dot
                3 => (80.0, 80.0, 40.0, 5.0, 0.0),  // Ring
                4 => (20.0, 20.0, 10.0, 0.0, 1.0),  // Tail
                _ => (30.0, 30.0, 15.0, 0.0, 1.0),
            };
            
            s.anim.width = damp(s.anim.width, t_w, 15.0, dt);
            s.anim.height = damp(s.anim.height, t_h, 15.0, dt);
            s.anim.radius = damp(s.anim.radius, t_r, 15.0, dt);
            s.anim.stroke_width = damp(s.anim.stroke_width, t_sw, 15.0, dt);
            s.anim.fill_alpha = damp(s.anim.fill_alpha, t_fa, 15.0, dt);
            s.anim.mode = s.mode;
            
            if s.mode == 4 && s.active {
                let current_pos = (s.anim.x, s.anim.y);
                s.anim.trail.insert(0, current_pos);
                if s.anim.trail.len() > MAX_TRAIL_POINTS { s.anim.trail.pop(); }
            } else if !s.anim.trail.is_empty() {
                s.anim.trail.pop();
            }

            s.anim.glow_intensity = 0.8 + 0.2 * (now.elapsed().as_secs_f64() * 5.0).sin().abs();
            
            da_tick.queue_draw();
            glib::ControlFlow::Continue
        });

        // UDP Listener
        let state_udp = state.clone();
        thread::spawn(move || {
            let socket = loop {
                if let Ok(s) = UdpSocket::bind("127.0.0.1:7878") { break s; }
                thread::sleep(Duration::from_millis(500));
            };
            let mut buf = [0u8; 512];
            loop {
                if let Ok((amt, _)) = socket.recv_from(&mut buf) {
                    let msg = String::from_utf8_lossy(&buf[..amt]);
                    let msg = msg.trim();
                    let mut s = state_udp.lock().unwrap();
                    if msg == "STOP" {
                        s.active = false;
                    } else if msg.starts_with("MONITOR:") {
                        if let Ok(idx) = msg[8..].parse::<i32>() { s.monitor_index = idx; }
                    } else {
                        let parts: Vec<&str> = msg.split(',').collect();
                        if parts.len() >= 2 {
                            if let (Ok(x), Ok(y)) = (parts[0].parse::<f32>(), parts[1].parse::<f32>()) {
                                s.target_x = x; 
                                s.target_y = y; 
                                s.active = true;
                                if parts.len() >= 3 { s.mode = parts[2].parse().unwrap_or(2); }
                            }
                        }
                    }
                }
            }
        });
    });
    app.run();
}
