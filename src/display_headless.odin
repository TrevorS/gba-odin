package main

// Stub display type for headless builds
// Only compiled when HEADLESS_ONLY is true
when HEADLESS_ONLY {

Display :: struct {}

// Initialize display (always fails in headless mode)
display_init :: proc(title: cstring, width, height: i32) -> (display: Display, ok: bool) {
    return {}, false
}

display_destroy :: proc(display: ^Display) {}

// Update display with framebuffer (no-op in headless mode)
display_update :: proc(display: ^Display, framebuffer: [^]u16, width, height: i32) {}

// Poll events - returns false to quit, true to continue
display_poll_events :: proc() -> bool {
    return true
}

display_set_title :: proc(display: ^Display, fps: f64) {}

} // when HEADLESS_ONLY
