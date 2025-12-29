package main

import "core:fmt"
import "cpu"
import "bus"

// Top-level GBA system structure
GBA :: struct {
    // Core components
    cpu:       cpu.CPU,
    bus:       bus.Bus,
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

// Handle scheduler event
handle_event :: proc(gba: ^GBA, event: Event) {
    #partial switch event.type {
    case .HBlank_Start:
        // TODO: Trigger HBlank processing in PPU
        // Request HBlank interrupt if enabled
        // bus.bus_request_interrupt(&gba.bus, 0x0002) // HBlank interrupt

        // Schedule end of HBlank
        scheduler_schedule(&gba.scheduler, .HBlank_End, CYCLES_PER_SCANLINE - HBLANK_START_CYCLE)

    case .HBlank_End:
        // Schedule next HBlank start
        scheduler_schedule(&gba.scheduler, .HBlank_Start, HBLANK_START_CYCLE)

    case .Frame_Complete:
        gba.frame_complete = true
        // Schedule next frame
        scheduler_schedule(&gba.scheduler, .Frame_Complete, CYCLES_PER_FRAME)

        // TODO: Request VBlank interrupt
        // bus.bus_request_interrupt(&gba.bus, 0x0001) // VBlank interrupt

    case:
        // Other events not implemented in Phase 1
    }
}

// Shutdown GBA
gba_destroy :: proc(gba: ^GBA) {
    cartridge_destroy(&gba.cartridge)
    memory_destroy(&gba.memory)
}
