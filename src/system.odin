package main

// System types supported by the emulator
System_Type :: enum {
    Unknown,
    GB,      // Original Game Boy (DMG)
    GBC,     // Game Boy Color
    GBA,     // Game Boy Advance
}

// Detect system type from ROM header
detect_system :: proc(rom_data: []u8) -> System_Type {
    if len(rom_data) < 0x150 {
        return .Unknown
    }

    // Check for GBA ROM (starts at 0x08000000, has Nintendo logo at 0x04)
    // GBA ROMs have a specific header format with entry point at 0x00-0x03
    // and Nintendo logo at 0x04-0x9F

    // GBA cartridge header check: entry point is typically a branch instruction
    // ARM branch: 0xEA (top byte) for B instruction
    if len(rom_data) >= 0xC0 {
        // Check for GBA Nintendo logo (first few bytes)
        // GBA logo starts at offset 0x04: 0x24, 0xFF, 0xAE, 0x51...
        if rom_data[0x04] == 0x24 && rom_data[0x05] == 0xFF &&
           rom_data[0x06] == 0xAE && rom_data[0x07] == 0x51 {
            return .GBA
        }
    }

    // Check for GB/GBC ROM
    // Nintendo logo at 0x104-0x133
    // 0xCE 0xED 0x66 0x66 are the first 4 bytes of the Nintendo logo
    if rom_data[0x104] == 0xCE && rom_data[0x105] == 0xED &&
       rom_data[0x106] == 0x66 && rom_data[0x107] == 0x66 {
        // Check CGB flag at 0x143
        cgb_flag := rom_data[0x143]

        if cgb_flag == 0xC0 {
            // CGB only
            return .GBC
        } else if cgb_flag == 0x80 {
            // CGB compatible (can run on both)
            return .GBC
        } else {
            // DMG only
            return .GB
        }
    }

    return .Unknown
}

// Get system name for display
system_name :: proc(sys: System_Type) -> string {
    switch sys {
    case .GB:      return "Game Boy"
    case .GBC:     return "Game Boy Color"
    case .GBA:     return "Game Boy Advance"
    case .Unknown: return "Unknown"
    }
    return "Unknown"
}

// Get native resolution for system
system_resolution :: proc(sys: System_Type) -> (width: int, height: int) {
    switch sys {
    case .GB, .GBC:
        return 160, 144
    case .GBA:
        return 240, 160
    case .Unknown:
        return 240, 160  // Default to GBA
    }
    return 240, 160
}
