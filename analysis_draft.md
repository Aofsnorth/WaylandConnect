# Architectural Analysis & Design (Draft)

## 1. Screen Sharing Instability (Issue #1)

### Current Architecture (`wc_capture/src/wayland.rs`)
- Uses `ashpd` to request ScreenCast session.
- Uses `pipewire` crate (rust bindings) to connect to the remote node.
- Uses a dedicated thread `run_pipewire_loop` to process the PW MainLoop.
- **Data Flow**: `stream.dequeue_buffer()` -> `Buffer` -> `Bytes::copy_from_slice()` -> `mpsc::Sender`.

### Root Cause Analysis (Potential)
1.  **Buffer Starvation**: If the `mpsc` channel fills up (backpressure) or the main loop is too slow, we might drop frames, but crucially, if we hold onto `Buffer` references too long (we don't, we copy immediately), we normally simulate "good" behavior. However, `pipewire-rs` bindings and the raw C API require explicit recycling of buffers (`pw_stream_queue_buffer`). The Rust binding *usually* handles this on `Drop` of the buffer guard, but complex threading can race.
2.  **Format Negotiation**: We hardcoded `BGRx`. Some compositors (e.g., wlroots based) might prefer `derived` or `RGBx`. A mismatch leads to black screens or crashes.
3.  **Memory Copy**: `Bytes::copy_from_slice` allocates a new heap vector for every 1080p/4K frame. This is a massive GC/Allocator churn.
    -   *Fix*: Use a pre-allocated pool of `BytesMut` or shared memory if transport allows (Packet zero-copy).
4.  **Signal/Sync**: The user mentioned "waiting for signal". This implies the `init` sequence (`ashpd` -> `pw connect`) might behave non-deterministically if not properly awaited or if the Portal dialog is dismissed/slow.

### Professional Redesign
-   **Explicit State Machine**: `Idle` -> `RequestingPortal` -> `NegotiatingPipeWire` -> `Streaming`.
-   **Buffer Pool**: Re-use memory for frame copies to avoid allocator thrashing.
-   **Traceability**: Add strict `tracing` spans for every state transition to diagnose "infinite loading".

## 2. Wayland Magnifier (Issue #2)

### Requirement
Zoom a specific screen region centered on the pointer (or specific point).

### Design Strategy
-   **Sub-Region Capture**: PipeWire 0.3 supports `Crop` metadata, but many compositors ignore it for ScreenCast.
-   **Client-Side Crop**: The robust way is to capture the *full* screen (which we already do) and perform the crop/scale in the `wc_processing` stage before encoding.
    -   *Pros*: Compositor agnostic.
    -   *Cons*: Wasted bandwidth capturing full screen if we only need a defined region? No, usually we want full screen *plus* a magnifier on the client? Or just the magnifier?
        -   *Assumption*: The user likely wants a "Magnifier Mode" where the *phone* shows the zoomed region, or an overlay.
        -   *Prompt says*: "Zoom a specific screen region ... Used in Pointer / Rongga Mode".
-   **Implementation**:
    -   Create `wc_processing::Magnifier`.
    -   Input: `Full Frame`, `Pointer(x, y)`, `ZoomLevel`.
    -   Output: `Cropped Frame`.
    -   *Performance*: This must be SIMD optimized or GPU shader based if possible. For generic Rust, direct slice manipulation is "okay" for testing but slow for 4K.

## 3. Audio Equalizer Source (Issue #3)

### Current Architecture (`wc_processing/src/audio.rs`)
-   `cpal::default_host().default_input_device()` -> Matches "Microphone" usually.

### Root Cause
-   `default_input_device` is the system default source (mic).
-   To capture *system output* (what music is playing), we need the **Monitor** of the default Sink.
-   PulseAudio/PipeWire exposes this as a source, but `cpal` doesn't always select it by default.

### Professional Redesign
-   **Enumeration**: Iterate all `cpal` input devices. Look for keywords `monitor` or `analog-stereo.monitor`.
-   **Configurable**: Allow `config.toml` to specify `audio.source_regex` or exact name.
-   **Pure PipeWire (Best)**: Since we use `pipewire` for video, use it for audio too. Connect a stream with `SPA_MEDIA_TYPE_audio` and `FL_CAPTURE | FL_MONITOR` flags to valid Node ID.
    -   *Decision*: Use `cpal` for cross-platform fallback, but verify "Monitor" selection logic. Better yet, since we are `Linux` focused (Wayland), use the `pipewire` crate to explicitly grab the system monitor.

