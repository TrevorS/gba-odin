package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:hash"

// ROM header offsets
ROM_ENTRY_POINT :: 0x00
ROM_LOGO :: 0x04
ROM_TITLE :: 0xA0
ROM_GAME_CODE :: 0xAC
ROM_MAKER_CODE :: 0xB0
ROM_FIXED_VALUE :: 0xB2
ROM_MAIN_UNIT :: 0xB3
ROM_DEVICE_TYPE :: 0xB4
ROM_VERSION :: 0xBC
ROM_CHECKSUM :: 0xBD

// Expected BIOS CRC32
BIOS_CRC32 :: 0xBAAE187F

Cartridge :: struct {
    // ROM info
    title:      string,
    game_code:  string,
    maker_code: string,
    version:    u8,
    checksum:   u8,

    // ROM data (stored in Memory struct)
    rom_size: int,
}

// Load ROM file
load_rom :: proc(path: string) -> (data: []u8, ok: bool) {
    data, ok = os.read_entire_file(path)
    if !ok {
        fmt.eprintln("Error: Failed to read ROM file:", path)
        return nil, false
    }

    if len(data) < ROM_MIN_SIZE {
        fmt.eprintln("Error: ROM file too small (minimum 192 bytes)")
        delete(data)
        return nil, false
    }

    if len(data) > ROM_MAX_SIZE {
        fmt.eprintln("Error: ROM file too large (maximum 32 MB)")
        delete(data)
        return nil, false
    }

    return data, true
}

// Load BIOS file
load_bios :: proc(path: string) -> (data: []u8, ok: bool) {
    data, ok = os.read_entire_file(path)
    if !ok {
        fmt.eprintln("Error: Failed to read BIOS file:", path)
        return nil, false
    }

    if len(data) != BIOS_SIZE {
        fmt.eprintf("Error: BIOS file must be exactly %d bytes (got %d)\n", BIOS_SIZE, len(data))
        delete(data)
        return nil, false
    }

    // Verify CRC32 (warning only)
    crc := hash.crc32(data)
    if crc != BIOS_CRC32 {
        fmt.eprintf("Warning: BIOS CRC32 mismatch (expected 0x%08X, got 0x%08X)\n", BIOS_CRC32, crc)
    }

    return data, true
}

// Parse ROM header and create cartridge info
parse_rom_header :: proc(rom: []u8) -> (cart: Cartridge, ok: bool) {
    if len(rom) < 0xC0 {
        return {}, false
    }

    // Read title (12 bytes, null-terminated ASCII)
    title_bytes := rom[ROM_TITLE:][:12]
    title_end := 0
    for i in 0 ..< 12 {
        if title_bytes[i] == 0 {
            break
        }
        title_end = i + 1
    }
    cart.title = strings.clone_from_bytes(title_bytes[:title_end])

    // Read game code (4 bytes)
    cart.game_code = strings.clone_from_bytes(rom[ROM_GAME_CODE:][:4])

    // Read maker code (2 bytes)
    cart.maker_code = strings.clone_from_bytes(rom[ROM_MAKER_CODE:][:2])

    // Check fixed value
    if rom[ROM_FIXED_VALUE] != 0x96 {
        fmt.eprintln("Warning: ROM fixed value is not 0x96")
    }

    cart.version = rom[ROM_VERSION]
    cart.checksum = rom[ROM_CHECKSUM]
    cart.rom_size = len(rom)

    // Verify header checksum
    checksum: u8 = 0
    for i in 0xA0 ..< 0xBD {
        checksum -= rom[i]
    }
    checksum -= 0x19

    if checksum != cart.checksum {
        fmt.eprintf("Warning: Header checksum mismatch (expected 0x%02X, calculated 0x%02X)\n",
            cart.checksum, checksum)
    }

    ok = true
    return
}

// Print cartridge info
print_cartridge_info :: proc(cart: ^Cartridge) {
    fmt.println("ROM Information:")
    fmt.println("  Title:     ", cart.title)
    fmt.println("  Game Code: ", cart.game_code)
    fmt.println("  Maker:     ", cart.maker_code)
    fmt.println("  Version:   ", cart.version)
    fmt.printf("  Size:       %d KB\n", cart.rom_size / 1024)
}

// Free cartridge resources
cartridge_destroy :: proc(cart: ^Cartridge) {
    if cart.title != "" {
        delete(cart.title)
    }
    if cart.game_code != "" {
        delete(cart.game_code)
    }
    if cart.maker_code != "" {
        delete(cart.maker_code)
    }
}
