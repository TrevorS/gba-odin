package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import "cpu"

// Command line options
Options :: struct {
    rom_path:   string,
    bios_path:  string,
    log_level:  Log_Level,
    trace_path: string,
    breakpoint: Maybe(u32),
    headless:   bool,
    max_frames: int, // 0 = unlimited
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
    fmt.println()

    // Run emulation
    fmt.println("Starting emulation...")
    if options.headless {
        fmt.println("Running in headless mode")
    }

    frame_count := 0
    start_time := time.now()

    for gba.running {
        // Run one frame
        gba_run_frame(&gba)
        frame_count += 1

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
            break
        }

        // Print status periodically
        if frame_count % 60 == 0 {
            elapsed := time.duration_seconds(time.since(start_time))
            fps := f64(frame_count) / elapsed
            fmt.printf("\rFrame %d (%.1f FPS)", frame_count, fps)
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
