package main

import "core:fmt"
import "cpu"
import "bus"
import "ppu"

// Top-level GBA system structure
GBA :: struct {
    // Core components
    cpu:       cpu.CPU,
    bus:       bus.Bus,
    ppu:       ppu.PPU,
    scheduler: Scheduler,
    memory:    Memory,

    // Cartridge info
    cartridge: Cartridge,

    // State
    running:        bool,
    frame_complete: bool,

    // Debug
    log_level: Log_Level,
}

// Initialize GBA system
gba_init :: proc(gba: ^GBA) -> bool {
    // Initialize memory
    memory, ok := memory_init()
    if !ok {
        fmt.eprintln("Error: Failed to initialize memory")
        return false
    }
    gba.memory = memory

    // Initialize CPU
    cpu.cpu_init(&gba.cpu)

    // Initialize PPU
    ppu.ppu_init(&gba.ppu)
    ppu.ppu_set_memory(&gba.ppu, gba.memory.vram, gba.memory.palette, gba.memory.oam)

    // Initialize bus with memory regions
    bus.bus_init(
        &gba.bus,
        gba.memory.bios,
        gba.memory.ewram,
        gba.memory.iwram,
        gba.memory.palette,
        gba.memory.vram,
        gba.memory.oam,
        gba.memory.io,
        gba.memory.rom,
        gba.memory.sram,
    )

    // Link bus to CPU's PC for BIOS protection
    bus.bus_set_pc_ptr(&gba.bus, &gba.cpu.regs[15])

    // Link bus to PPU for register access
    bus.bus_set_ppu(&gba.bus, &gba.ppu)

    // Initialize scheduler
    scheduler_init(&gba.scheduler)
    scheduler_reset(&gba.scheduler)

    gba.running = true
    gba.frame_complete = false
    gba.log_level = .Warn

    return true
}

// Load BIOS into GBA
gba_load_bios :: proc(gba: ^GBA, path: string) -> bool {
    data, ok := load_bios(path)
    if !ok {
        return false
    }
    defer delete(data)

    if !memory_load_bios(&gba.memory, data) {
        fmt.eprintln("Error: Failed to load BIOS into memory")
        return false
    }

    // Refresh bus pointer (in case memory was reallocated)
    gba.bus.bios = gba.memory.bios

    return true
}

// Load ROM into GBA
gba_load_rom :: proc(gba: ^GBA, path: string) -> bool {
    data, ok := load_rom(path)
    if !ok {
        return false
    }
    defer delete(data)

    // Parse header first
    cart, parse_ok := parse_rom_header(data)
    if !parse_ok {
        fmt.eprintln("Warning: Failed to parse ROM header")
    }
    gba.cartridge = cart
    print_cartridge_info(&gba.cartridge)

    if !memory_load_rom(&gba.memory, data) {
        fmt.eprintln("Error: Failed to load ROM into memory")
        return false
    }

    // Update bus ROM pointer
    gba.bus.rom = gba.memory.rom

    return true
}

// Reset GBA to initial state
gba_reset :: proc(gba: ^GBA) {
    // Reset CPU
    cpu.cpu_init(&gba.cpu)

    // Reset PPU
    ppu.ppu_init(&gba.ppu)
    ppu.ppu_set_memory(&gba.ppu, gba.memory.vram, gba.memory.palette, gba.memory.oam)

    // Reset memory (but keep BIOS and ROM)
    memory_reset(&gba.memory)

    // Reset scheduler
    scheduler_reset(&gba.scheduler)

    // Reset bus state
    gba.bus.last_bios_read = 0xE129F000
    gba.bus.ie = 0
    gba.bus.if_ = 0
    gba.bus.ime = 0
    gba.bus.halt_requested = false

    gba.running = true
    gba.frame_complete = false
}

// Execute one CPU step
gba_step :: proc(gba: ^GBA) -> u32 {
    // Check for halt
    if gba.cpu.halted {
        // Skip to next event
        if evt := scheduler_peek(&gba.scheduler); evt != nil {
            if evt.timestamp > gba.scheduler.current_cycles {
                gba.scheduler.current_cycles = evt.timestamp
            }
        }
        return 0
    }

    // Check for pending interrupts
    if cpu.irq_enabled(&gba.cpu) && bus.bus_interrupt_pending(&gba.bus) {
        cpu.unhalt(&gba.cpu)
        cpu.irq(&gba.cpu)
    }

    // Fetch and execute instruction
    pc := gba.cpu.regs[15]
    cycles: u32

    if cpu.is_thumb(&gba.cpu) {
        opcode, c := bus.read16(&gba.bus, pc)
        bus.bus_update_prefetch(&gba.bus, u32(opcode) | (u32(opcode) << 16))
        cpu.execute_thumb(&gba.cpu, &gba.bus, opcode)
        cycles = gba.cpu.cycles + u32(c)
    } else {
        opcode, c := bus.read32(&gba.bus, pc)
        bus.bus_update_prefetch(&gba.bus, opcode)
        cpu.execute_arm(&gba.cpu, &gba.bus, opcode)
        cycles = gba.cpu.cycles + u32(c)
    }

    // Check for halt request from I/O
    if gba.bus.halt_requested {
        cpu.halt(&gba.cpu)
        gba.bus.halt_requested = false
    }

    return cycles
}

// Run until frame complete
gba_run_frame :: proc(gba: ^GBA) {
    gba.frame_complete = false

    for gba.running && !gba.frame_complete {
        // Check for pending events
        for {
            evt := scheduler_peek(&gba.scheduler)
            if evt == nil || evt.timestamp > gba.scheduler.current_cycles {
                break
            }

            // Pop and handle event
            event, ok := scheduler_pop(&gba.scheduler)
            if !ok {
                break
            }

            handle_event(gba, event)
        }

        // Execute CPU
        cycles := gba_step(gba)
        scheduler_add_cycles(&gba.scheduler, u64(cycles))
    }
}

// Interrupt bit constants
IRQ_VBLANK :: 0x0001
IRQ_HBLANK :: 0x0002
IRQ_VCOUNT :: 0x0004

// Handle scheduler event
handle_event :: proc(gba: ^GBA, event: Event) {
    #partial switch event.type {
    case .HBlank_Start:
        // Render the current scanline before HBlank
        ppu.ppu_render_scanline(&gba.ppu)

        // Set HBlank flag
        hblank_irq := ppu.ppu_hblank(&gba.ppu)
        if hblank_irq {
            bus.bus_request_interrupt(&gba.bus, IRQ_HBLANK)
        }

        // Schedule end of HBlank (end of scanline)
        scheduler_schedule(&gba.scheduler, .HBlank_End, CYCLES_PER_SCANLINE - HBLANK_START_CYCLE)

    case .HBlank_End:
        // End of HBlank, advance to next scanline
        vblank_irq, vcount_irq := ppu.ppu_end_hblank(&gba.ppu)

        if vblank_irq {
            bus.bus_request_interrupt(&gba.bus, IRQ_VBLANK)
        }
        if vcount_irq {
            bus.bus_request_interrupt(&gba.bus, IRQ_VCOUNT)
        }

        // Check if frame is complete
        if ppu.ppu_frame_complete(&gba.ppu) {
            // We're now in VBlank, schedule frame complete at end of VBlank
            scheduler_schedule(&gba.scheduler, .Frame_Complete, CYCLES_PER_SCANLINE * VBLANK_SCANLINES)
        }

        // Schedule next HBlank
        scheduler_schedule(&gba.scheduler, .HBlank_Start, HBLANK_START_CYCLE)

    case .Frame_Complete:
        gba.frame_complete = true
        // Frame complete event is one-shot per frame, next one scheduled at VBlank

    case:
        // Other events not implemented yet
    }
}

// Get framebuffer for display
gba_get_framebuffer :: proc(gba: ^GBA) -> ^[ppu.SCREEN_HEIGHT][ppu.SCREEN_WIDTH]u16 {
    return ppu.ppu_get_framebuffer(&gba.ppu)
}

// Shutdown GBA
gba_destroy :: proc(gba: ^GBA) {
    cartridge_destroy(&gba.cartridge)
    memory_destroy(&gba.memory)
}
