package main

import "core:fmt"
import sdl "vendor:sdl2"

// SDL2 display implementation
// Only compiled when HEADLESS_ONLY is false
when !HEADLESS_ONLY {

Display :: struct {
    window:   ^sdl.Window,
    renderer: ^sdl.Renderer,
    texture:  ^sdl.Texture,
    width:    i32,
    height:   i32,
}

// Initialize SDL2 display
display_init :: proc(title: cstring, width, height: i32) -> (display: Display, ok: bool) {
    if sdl.Init({.VIDEO}) != 0 {
        fmt.eprintln("SDL_Init failed:", sdl.GetError())
        return {}, false
    }

    scaled_w := width * DISPLAY_SCALE
    scaled_h := height * DISPLAY_SCALE

    window := sdl.CreateWindow(
        title,
        sdl.WINDOWPOS_CENTERED,
        sdl.WINDOWPOS_CENTERED,
        scaled_w,
        scaled_h,
        {.SHOWN},
    )
    if window == nil {
        fmt.eprintln("SDL_CreateWindow failed:", sdl.GetError())
        sdl.Quit()
        return {}, false
    }

    // macOS: Process events to make window appear
    sdl.PumpEvents()
    sdl.RaiseWindow(window)

    renderer := sdl.CreateRenderer(window, -1, {.ACCELERATED, .PRESENTVSYNC})
    if renderer == nil {
        fmt.eprintln("SDL_CreateRenderer failed:", sdl.GetError())
        sdl.DestroyWindow(window)
        sdl.Quit()
        return {}, false
    }

    // Create texture for framebuffer
    texture := sdl.CreateTexture(
        renderer,
        .ARGB8888,
        .STREAMING,
        width,
        height,
    )
    if texture == nil {
        fmt.eprintln("SDL_CreateTexture failed:", sdl.GetError())
        sdl.DestroyRenderer(renderer)
        sdl.DestroyWindow(window)
        sdl.Quit()
        return {}, false
    }

    return Display{
        window   = window,
        renderer = renderer,
        texture  = texture,
        width    = width,
        height   = height,
    }, true
}

// Clean up SDL2 resources
display_destroy :: proc(display: ^Display) {
    if display.texture != nil do sdl.DestroyTexture(display.texture)
    if display.renderer != nil do sdl.DestroyRenderer(display.renderer)
    if display.window != nil do sdl.DestroyWindow(display.window)
    sdl.Quit()
}

// Temp buffer for format conversion
@(thread_local)
convert_buffer: [256 * 256]u32

// Update display with framebuffer
display_update :: proc(display: ^Display, framebuffer: [^]u16, width, height: i32) {
    // Convert RGB555 to ARGB8888
    pixel_count := width * height
    for i in 0..<pixel_count {
        rgb555 := framebuffer[i]
        // GB/GBA format: 0BBBBBGGGGGRRRRR (BGR555)
        r5 := (rgb555 >> 0) & 0x1F
        g5 := (rgb555 >> 5) & 0x1F
        b5 := (rgb555 >> 10) & 0x1F

        // Expand 5-bit to 8-bit (multiply by 8 and add high bits for accuracy)
        r8 := (r5 << 3) | (r5 >> 2)
        g8 := (g5 << 3) | (g5 >> 2)
        b8 := (b5 << 3) | (b5 >> 2)

        // ARGB8888 format
        convert_buffer[i] = 0xFF000000 | (u32(r8) << 16) | (u32(g8) << 8) | u32(b8)
    }

    // Update texture with converted pixels
    sdl.UpdateTexture(
        display.texture,
        nil,
        &convert_buffer[0],
        width * size_of(u32),
    )

    // Clear and render
    sdl.RenderClear(display.renderer)
    sdl.RenderCopy(display.renderer, display.texture, nil, nil)
    sdl.RenderPresent(display.renderer)
}

// Poll SDL events - returns false to quit
display_poll_events :: proc() -> bool {
    event: sdl.Event
    for sdl.PollEvent(&event) {
        #partial switch event.type {
        case .QUIT:
            return false
        case .KEYDOWN, .KEYUP:
            handle_key_event(&event.key)
        }
    }
    return true
}

// Handle keyboard input
handle_key_event :: proc(event: ^sdl.KeyboardEvent) {
    pressed := event.type == .KEYDOWN

    #partial switch event.keysym.scancode {
    case .UP:
        set_button(BUTTON_UP, pressed)
    case .DOWN:
        set_button(BUTTON_DOWN, pressed)
    case .LEFT:
        set_button(BUTTON_LEFT, pressed)
    case .RIGHT:
        set_button(BUTTON_RIGHT, pressed)
    case .Z:
        set_button(BUTTON_A, pressed)
    case .X:
        set_button(BUTTON_B, pressed)
    case .RETURN:
        set_button(BUTTON_START, pressed)
    case .RSHIFT:
        set_button(BUTTON_SELECT, pressed)
    case .A:
        set_button(BUTTON_L, pressed)
    case .S:
        set_button(BUTTON_R, pressed)
    case .ESCAPE:
        // Could add quit on escape
    }
}

// Set button state (active-low: 0 = pressed)
set_button :: proc(button: u16, pressed: bool) {
    if pressed {
        g_input.buttons &= ~button // Clear bit = pressed
    } else {
        g_input.buttons |= button  // Set bit = released
    }
}

// Update window title with FPS
display_set_title :: proc(display: ^Display, fps: f64) {
    title := fmt.ctprintf("gba-odin - %.1f FPS", fps)
    sdl.SetWindowTitle(display.window, title)
}

} // when !HEADLESS_ONLY
