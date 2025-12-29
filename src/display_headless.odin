package main

import "ppu"

// Stub display type for headless builds
Display :: struct {}

// Stub display functions for headless builds
display_init :: proc(title: cstring) -> (display: Display, ok: bool) {
    return {}, false
}

display_destroy :: proc(display: ^Display) {}

display_update :: proc(display: ^Display, framebuffer: ^[ppu.SCREEN_HEIGHT][ppu.SCREEN_WIDTH]u16) {}

display_poll_events :: proc() -> bool {
    return true
}

display_set_title :: proc(display: ^Display, fps: f64) {}
