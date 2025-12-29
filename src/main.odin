package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import "cpu"
import "ppu"

// Headless mode flag - set via build define
HEADLESS_ONLY :: #config(HEADLESS_ONLY, true)

// Display scaling
DISPLAY_SCALE :: 2
WINDOW_WIDTH :: ppu.SCREEN_WIDTH * DISPLAY_SCALE
WINDOW_HEIGHT :: ppu.SCREEN_HEIGHT * DISPLAY_SCALE

// Command line options
Options :: struct {
    rom_path:      string,
    bios_path:     string,
    log_level:     Log_Level,
    trace_path:    string,
    breakpoint:    Maybe(u32),
    headless:      bool,
    max_frames:    int, // 0 = unlimited
    screenshot:    string, // Path to save screenshot
    skip_bios:     bool, // Skip BIOS and start at ROM
    trace_cpu:     bool, // Print CPU trace to console
}

print_usage :: proc() {
    fmt.println("gba-odin - Game Boy Advance Emulator")
    fmt.println()
    fmt.println("Usage: gba-odin <rom_path> --bios <bios_path> [options]")
    fmt.println()
    fmt.println("Required:")
    fmt.println("  <rom_path>          Path to ROM file (.gba)")
    fmt.println("  --bios <path>       Path to GBA BIOS file (16KB)")
    fmt.println()
    fmt.println("Options:")
    fmt.println("  --log-level <level> Set log level (none, error, warn, info, debug, trace)")
    fmt.println("  --trace <path>      Write instruction trace to file")
    fmt.println("  --break <address>   Set breakpoint at address (hex)")
    fmt.println("  --headless          Run without display (for testing)")
    fmt.println("  --frames <n>        Run for n frames then exit (for testing)")
    fmt.println("  --screenshot <path> Save screenshot (PNG if .png, otherwise PPM)")
    fmt.println("  --skip-bios         Skip BIOS and start directly at ROM")
    fmt.println("  --trace-cpu         Print first 50 instructions to console")
    fmt.println("  --help              Show this help message")
}

parse_args :: proc() -> (options: Options, ok: bool) {
    args := os.args[1:]

    if len(args) == 0 {
        print_usage()
        return {}, false
    }

    options.log_level = .Warn
    options.max_frames = 0
    options.headless = false

    i := 0
    for i < len(args) {
        arg := args[i]

        if arg == "--help" || arg == "-h" {
            print_usage()
            return {}, false
        } else if arg == "--bios" {
            i += 1
            if i >= len(args) {
                fmt.eprintln("Error: --bios requires a path argument")
                return {}, false
            }
            options.bios_path = args[i]
        } else if arg == "--log-level" {
            i += 1
            if i >= len(args) {
                fmt.eprintln("Error: --log-level requires a level argument")
                return {}, false
            }
            level := args[i]
            switch level {
            case "none":
                options.log_level = .None
            case "error":
                options.log_level = .Error
            case "warn":
                options.log_level = .Warn
            case "info":
                options.log_level = .Info
            case "debug":
                options.log_level = .Debug
            case "trace":
                options.log_level = .Trace
            case:
                fmt.eprintln("Error: Unknown log level:", level)
                return {}, false
            }
        } else if arg == "--trace" {
            i += 1
            if i >= len(args) {
                fmt.eprintln("Error: --trace requires a path argument")
                return {}, false
            }
            options.trace_path = args[i]
        } else if arg == "--break" {
            i += 1
            if i >= len(args) {
                fmt.eprintln("Error: --break requires an address argument")
                return {}, false
            }
            // Parse hex address
            addr_str := args[i]
            if strings.has_prefix(addr_str, "0x") {
                addr_str = addr_str[2:]
            }
            addr: u32 = 0
            for c in addr_str {
                addr <<= 4
                if c >= '0' && c <= '9' {
                    addr |= u32(c - '0')
                } else if c >= 'a' && c <= 'f' {
                    addr |= u32(c - 'a' + 10)
                } else if c >= 'A' && c <= 'F' {
                    addr |= u32(c - 'A' + 10)
                } else {
                    fmt.eprintln("Error: Invalid hex address:", args[i])
                    return {}, false
                }
            }
            options.breakpoint = addr
        } else if arg == "--headless" {
            options.headless = true
        } else if arg == "--frames" {
            i += 1
            if i >= len(args) {
                fmt.eprintln("Error: --frames requires a number argument")
                return {}, false
            }
            frames: int = 0
            for c in args[i] {
                if c >= '0' && c <= '9' {
                    frames = frames * 10 + int(c - '0')
                } else {
                    fmt.eprintln("Error: Invalid frame count:", args[i])
                    return {}, false
                }
            }
            options.max_frames = frames
        } else if arg == "--screenshot" {
            i += 1
            if i >= len(args) {
                fmt.eprintln("Error: --screenshot requires a path argument")
                return {}, false
            }
            options.screenshot = args[i]
        } else if arg == "--skip-bios" {
            options.skip_bios = true
        } else if arg == "--trace-cpu" {
            options.trace_cpu = true
        } else if !strings.has_prefix(arg, "-") {
            if options.rom_path == "" {
                options.rom_path = arg
            } else {
                fmt.eprintln("Error: Unexpected argument:", arg)
                return {}, false
            }
        } else {
            fmt.eprintln("Error: Unknown option:", arg)
            return {}, false
        }

        i += 1
    }

    // Validate required arguments
    if options.rom_path == "" {
        fmt.eprintln("Error: ROM path is required")
        print_usage()
        return {}, false
    }

    if options.bios_path == "" {
        fmt.eprintln("Error: BIOS path is required (use --bios)")
        print_usage()
        return {}, false
    }

    ok = true
    return
}

// Display functions are in display_headless.odin (for headless builds)
// or would be in display_sdl.odin (for SDL2 builds)

// Save framebuffer as PPM image (simple format, no external deps)
save_screenshot :: proc(path: string, framebuffer: ^[ppu.SCREEN_HEIGHT][ppu.SCREEN_WIDTH]u16) -> bool {
    // Open file for writing
    file, err := os.open(path, os.O_WRONLY | os.O_CREATE | os.O_TRUNC, 0o644)
    if err != os.ERROR_NONE {
        fmt.eprintln("Error: Failed to create screenshot file:", path)
        return false
    }
    defer os.close(file)

    // Write PPM header (P6 binary format)
    header := fmt.tprintf("P6\n%d %d\n255\n", ppu.SCREEN_WIDTH, ppu.SCREEN_HEIGHT)
    os.write_string(file, header)

    // Convert BGR555 to RGB888 and write pixels
    pixel_data: [ppu.SCREEN_WIDTH * 3]u8
    for y in 0 ..< ppu.SCREEN_HEIGHT {
        for x in 0 ..< ppu.SCREEN_WIDTH {
            bgr555 := framebuffer[y][x]
            // Extract 5-bit components and expand to 8-bit
            b := u8((bgr555 >> 10) & 0x1F)
            g := u8((bgr555 >> 5) & 0x1F)
            r := u8(bgr555 & 0x1F)
            // Expand 5-bit to 8-bit: (val << 3) | (val >> 2)
            pixel_data[x * 3 + 0] = (r << 3) | (r >> 2)
            pixel_data[x * 3 + 1] = (g << 3) | (g >> 2)
            pixel_data[x * 3 + 2] = (b << 3) | (b >> 2)
        }
        os.write(file, pixel_data[:])
    }

    fmt.println("Screenshot saved to:", path)
    return true
}

// CRC32 for PNG - computed on demand (no @init needed)
png_crc32 :: proc(data: []u8) -> u32 {
    crc := u32(0xFFFFFFFF)
    for b in data {
        c := crc ~ u32(b)
        // Unrolled CRC calculation
        for _ in 0..<8 {
            if (c & 1) != 0 {
                c = 0xEDB88320 ~ (c >> 1)
            } else {
                c = c >> 1
            }
        }
        crc = c
    }
    return crc ~ 0xFFFFFFFF
}

// Adler32 for zlib wrapper
adler32 :: proc(data: []u8) -> u32 {
    a := u32(1)
    b := u32(0)
    for byte in data {
        a = (a + u32(byte)) % 65521
        b = (b + a) % 65521
    }
    return (b << 16) | a
}

// Write a PNG chunk
write_png_chunk :: proc(file: os.Handle, chunk_type: [4]u8, data: []u8) {
    // Length (big-endian)
    length := u32(len(data))
    length_be: [4]u8 = {u8(length >> 24), u8(length >> 16), u8(length >> 8), u8(length)}
    os.write(file, length_be[:])

    // Type - write bytes individually since we can't slice the array
    type_bytes: [4]u8 = chunk_type
    os.write(file, type_bytes[:])

    // Data
    if len(data) > 0 {
        os.write(file, data)
    }

    // CRC (over type + data)
    crc_data := make([]u8, 4 + len(data))
    defer delete(crc_data)
    crc_data[0] = chunk_type[0]
    crc_data[1] = chunk_type[1]
    crc_data[2] = chunk_type[2]
    crc_data[3] = chunk_type[3]
    for i in 0..<len(data) {
        crc_data[4+i] = data[i]
    }
    crc := png_crc32(crc_data)
    crc_be: [4]u8 = {u8(crc >> 24), u8(crc >> 16), u8(crc >> 8), u8(crc)}
    os.write(file, crc_be[:])
}

// Save framebuffer as PNG image (uncompressed)
save_screenshot_png :: proc(path: string, framebuffer: ^[ppu.SCREEN_HEIGHT][ppu.SCREEN_WIDTH]u16) -> bool {
    // Open file for writing
    file, err := os.open(path, os.O_WRONLY | os.O_CREATE | os.O_TRUNC, 0o644)
    if err != os.ERROR_NONE {
        fmt.eprintln("Error: Failed to create screenshot file:", path)
        return false
    }
    defer os.close(file)

    // PNG signature
    png_sig: [8]u8 = {0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A}
    os.write(file, png_sig[:])

    // IHDR chunk
    width := u32(ppu.SCREEN_WIDTH)
    height := u32(ppu.SCREEN_HEIGHT)
    ihdr: [13]u8 = {
        u8(width >> 24), u8(width >> 16), u8(width >> 8), u8(width),     // Width
        u8(height >> 24), u8(height >> 16), u8(height >> 8), u8(height), // Height
        8,    // Bit depth
        2,    // Color type (RGB)
        0,    // Compression method
        0,    // Filter method
        0,    // Interlace method
    }
    write_png_chunk(file, {'I', 'H', 'D', 'R'}, ihdr[:])

    // Prepare raw image data with filter bytes
    row_size := 1 + ppu.SCREEN_WIDTH * 3  // 1 filter byte + RGB per row
    raw_size := ppu.SCREEN_HEIGHT * row_size
    raw_data := make([]u8, raw_size)
    defer delete(raw_data)

    idx := 0
    for y in 0..<ppu.SCREEN_HEIGHT {
        raw_data[idx] = 0  // No filter
        idx += 1
        for x in 0..<ppu.SCREEN_WIDTH {
            bgr555 := framebuffer[y][x]
            // Extract 5-bit components and expand to 8-bit
            b := u8((bgr555 >> 10) & 0x1F)
            g := u8((bgr555 >> 5) & 0x1F)
            r := u8(bgr555 & 0x1F)
            // Expand 5-bit to 8-bit
            raw_data[idx] = (r << 3) | (r >> 2)
            raw_data[idx+1] = (g << 3) | (g >> 2)
            raw_data[idx+2] = (b << 3) | (b >> 2)
            idx += 3
        }
    }

    // Create uncompressed zlib stream (stored blocks)
    // zlib header: 0x78 0x01 (no compression)
    // For each block: 1 byte header, 2 bytes len, 2 bytes ~len, then data
    // Max block size is 65535, so we may need multiple blocks

    MAX_BLOCK :: 65535
    num_blocks := (raw_size + MAX_BLOCK - 1) / MAX_BLOCK
    zlib_size := 2 + num_blocks * 5 + raw_size + 4  // header + block headers + data + adler32
    zlib_data := make([]u8, zlib_size)
    defer delete(zlib_data)

    // zlib header
    zlib_data[0] = 0x78
    zlib_data[1] = 0x01

    zidx := 2
    remaining := raw_size
    src_idx := 0
    for block := 0; block < num_blocks; block += 1 {
        block_size := min(remaining, MAX_BLOCK)
        is_final := block == num_blocks - 1

        // Block header: BFINAL=1 for last, BTYPE=00 (stored)
        zlib_data[zidx] = is_final ? 0x01 : 0x00
        zidx += 1

        // LEN and NLEN (little-endian)
        len16 := u16(block_size)
        zlib_data[zidx] = u8(len16 & 0xFF)
        zlib_data[zidx+1] = u8(len16 >> 8)
        zlib_data[zidx+2] = u8(~len16 & 0xFF)
        zlib_data[zidx+3] = u8((~len16) >> 8)
        zidx += 4

        // Copy data
        for i in 0..<block_size {
            zlib_data[zidx+i] = raw_data[src_idx+i]
        }
        zidx += block_size
        src_idx += block_size
        remaining -= block_size
    }

    // Adler32 checksum (big-endian)
    adler := adler32(raw_data)
    zlib_data[zidx] = u8(adler >> 24)
    zlib_data[zidx+1] = u8(adler >> 16)
    zlib_data[zidx+2] = u8(adler >> 8)
    zlib_data[zidx+3] = u8(adler)

    // IDAT chunk
    write_png_chunk(file, {'I', 'D', 'A', 'T'}, zlib_data[:])

    // IEND chunk
    empty: []u8
    write_png_chunk(file, {'I', 'E', 'N', 'D'}, empty)

    fmt.println("Screenshot saved to:", path)
    return true
}

main :: proc() {
    fmt.println("gba-odin - Game Boy Advance Emulator")
    fmt.println()

    // Parse command line arguments
    options, ok := parse_args()
    if !ok {
        os.exit(1)
    }

    // Initialize GBA
    gba: GBA
    if !gba_init(&gba) {
        fmt.eprintln("Error: Failed to initialize GBA")
        os.exit(1)
    }
    defer gba_destroy(&gba)

    gba.log_level = options.log_level

    // Load BIOS
    fmt.println("Loading BIOS:", options.bios_path)
    if !gba_load_bios(&gba, options.bios_path) {
        os.exit(1)
    }
    fmt.println("BIOS loaded successfully")

    // Load ROM
    fmt.println()
    fmt.println("Loading ROM:", options.rom_path)
    if !gba_load_rom(&gba, options.rom_path) {
        os.exit(1)
    }
    fmt.println("ROM loaded successfully")

    // Skip BIOS if requested
    if options.skip_bios {
        cpu.cpu_skip_bios(&gba.cpu)
        fmt.println("BIOS skipped - starting at ROM entry point")
    }

    // Enable CPU trace if requested
    if options.trace_cpu {
        gba.trace_enabled = true
        gba.trace_count = 0
        fmt.println("CPU trace enabled (first 50 instructions)")
    }
    fmt.println()

    // Initialize display if not headless
    display: Display
    if !options.headless && !HEADLESS_ONLY {
        display, ok = display_init("gba-odin")
        if !ok {
            fmt.eprintln("Warning: Failed to initialize display, running headless")
            options.headless = true
        } else {
            defer display_destroy(&display)
        }
    } else {
        // Force headless mode when built without SDL2
        options.headless = true
    }

    // Run emulation
    fmt.println("Starting emulation...")
    if options.headless {
        fmt.println("Running in headless mode")
    }

    frame_count := 0
    start_time := time.now()
    last_fps_time := start_time
    fps_frame_count := 0

    for gba.running {
        // Poll events if not headless
        if !options.headless {
            if !display_poll_events() {
                break
            }
        }

        // Run one frame
        gba_run_frame(&gba)
        frame_count += 1
        fps_frame_count += 1

        // Update display if not headless
        if !options.headless {
            framebuffer := gba_get_framebuffer(&gba)
            display_update(&display, framebuffer)
        }

        // Check breakpoint
        if bp, has_bp := options.breakpoint.?; has_bp {
            if gba.cpu.regs[15] == bp {
                fmt.printf("\nBreakpoint hit at 0x%08X\n", bp)
                dump_cpu_state(&gba.cpu)
                break
            }
        }

        // Check frame limit
        if options.max_frames > 0 && frame_count >= options.max_frames {
            fmt.printf("\nReached frame limit (%d frames)\n", frame_count)
            gba_debug_dump(&gba)
            break
        }

        // Update FPS display periodically
        now := time.now()
        fps_elapsed := time.duration_seconds(time.diff(last_fps_time, now))
        if fps_elapsed >= 1.0 {
            fps := f64(fps_frame_count) / fps_elapsed
            if !options.headless {
                display_set_title(&display, fps)
            }
            if options.headless && frame_count % 60 == 0 {
                fmt.printf("\rFrame %d (%.1f FPS)", frame_count, fps)
            }
            last_fps_time = now
            fps_frame_count = 0
        }
    }

    // Save screenshot if requested
    if options.screenshot != "" {
        framebuffer := gba_get_framebuffer(&gba)
        // Use PNG for .png extension, otherwise PPM
        if strings.has_suffix(options.screenshot, ".png") {
            save_screenshot_png(options.screenshot, framebuffer)
        } else {
            save_screenshot(options.screenshot, framebuffer)
        }
    }

    // Final stats
    elapsed := time.duration_seconds(time.since(start_time))
    fps := f64(frame_count) / elapsed
    fmt.printf("\n\nEmulation complete: %d frames in %.2f seconds (%.1f FPS)\n",
        frame_count, elapsed, fps)
}

// Dump CPU state for debugging
dump_cpu_state :: proc(c: ^cpu.CPU) {
    fmt.println("\nCPU State:")
    for i in 0 ..< 16 {
        fmt.printf("  r%-2d = 0x%08X", i, c.regs[i])
        if i % 4 == 3 {
            fmt.println()
        }
    }
    fmt.printf("  CPSR = 0x%08X [%s%s%s%s %s %s]\n",
        c.regs[31],
        cpu.get_flag_n(c) ? "N" : "-",
        cpu.get_flag_z(c) ? "Z" : "-",
        cpu.get_flag_c(c) ? "C" : "-",
        cpu.get_flag_v(c) ? "V" : "-",
        cpu.is_thumb(c) ? "T" : "A",
        mode_name(cpu.get_mode(c)))
}

mode_name :: proc(mode: cpu.Mode) -> string {
    switch mode {
    case .User:
        return "USR"
    case .FIQ:
        return "FIQ"
    case .IRQ:
        return "IRQ"
    case .Supervisor:
        return "SVC"
    case .Abort:
        return "ABT"
    case .Undefined:
        return "UND"
    case .System:
        return "SYS"
    case:
        return "???"
    }
}
