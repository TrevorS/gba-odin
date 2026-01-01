package main

// Shared input state for display to update and emulators to read
// Uses GBA KEYINPUT format (active-low, 0 = pressed)

// GBA button bits (active-low)
BUTTON_A      :: 0x0001
BUTTON_B      :: 0x0002
BUTTON_SELECT :: 0x0004
BUTTON_START  :: 0x0008
BUTTON_RIGHT  :: 0x0010
BUTTON_LEFT   :: 0x0020
BUTTON_UP     :: 0x0040
BUTTON_DOWN   :: 0x0080
BUTTON_R      :: 0x0100
BUTTON_L      :: 0x0200

Input_State :: struct {
    buttons: u16, // Active-low, GBA KEYINPUT format (0x3FF = all released)
}

// Global input state - updated by display_poll_events, read by emulators
g_input: Input_State = {buttons = 0x3FF}

// Get current button state in GBA KEYINPUT format
get_keyinput :: proc() -> u16 {
    return g_input.buttons
}

// Convert to GB button format (bits 0-3: A,B,Select,Start)
// Returns active-high: 0 = released, 1 = pressed
get_gb_buttons :: proc() -> u8 {
    result: u8 = 0x00
    if (g_input.buttons & BUTTON_A) == 0 do result |= 0x01       // A pressed
    if (g_input.buttons & BUTTON_B) == 0 do result |= 0x02       // B pressed
    if (g_input.buttons & BUTTON_SELECT) == 0 do result |= 0x04  // Select pressed
    if (g_input.buttons & BUTTON_START) == 0 do result |= 0x08   // Start pressed
    return result
}

// Convert to GB d-pad format (bits 0-3: Right,Left,Up,Down)
// Returns active-high: 0 = released, 1 = pressed
get_gb_dpad :: proc() -> u8 {
    result: u8 = 0x00
    if (g_input.buttons & BUTTON_RIGHT) == 0 do result |= 0x01  // Right pressed
    if (g_input.buttons & BUTTON_LEFT) == 0 do result |= 0x02   // Left pressed
    if (g_input.buttons & BUTTON_UP) == 0 do result |= 0x04     // Up pressed
    if (g_input.buttons & BUTTON_DOWN) == 0 do result |= 0x08   // Down pressed
    return result
}
