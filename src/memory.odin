package main

import "core:mem"

// Memory regions - slices into the arena
Memory :: struct {
    // Backing storage
    arena: []u8,

    // Memory region slices (point into arena)
    bios:    []u8,
    ewram:   []u8,
    iwram:   []u8,
    palette: []u8,
    vram:    []u8,
    oam:     []u8,
    io:      []u8,

    // ROM and SRAM (separately allocated)
    rom:  []u8,
    sram: []u8,

    // Tracking
    high_water_mark: uint,
}

// Initialize memory arena and carve out regions
memory_init :: proc() -> (memory: Memory, ok: bool) {
    // Allocate the arena
    arena, err := make([]u8, TOTAL_ARENA_SIZE)
    if err != nil {
        return {}, false
    }
    memory.arena = arena

    // Zero initialize (Odin's make already does this, but be explicit)
    mem.zero_slice(memory.arena)

    // Carve out regions
    offset: uint = 0

    memory.bios = memory.arena[offset:][:BIOS_SIZE]
    offset += BIOS_SIZE

    memory.ewram = memory.arena[offset:][:EWRAM_SIZE]
    offset += EWRAM_SIZE

    memory.iwram = memory.arena[offset:][:IWRAM_SIZE]
    offset += IWRAM_SIZE

    memory.palette = memory.arena[offset:][:PALETTE_SIZE]
    offset += PALETTE_SIZE

    memory.vram = memory.arena[offset:][:VRAM_SIZE]
    offset += VRAM_SIZE

    memory.oam = memory.arena[offset:][:OAM_SIZE]
    offset += OAM_SIZE

    memory.io = memory.arena[offset:][:IO_SIZE]
    offset += IO_SIZE

    memory.high_water_mark = offset

    // Allocate SRAM (initialized to 0xFF per spec)
    sram, sram_err := make([]u8, SRAM_SIZE)
    if sram_err != nil {
        delete(memory.arena)
        return {}, false
    }
    memory.sram = sram
    mem.set(raw_data(memory.sram), 0xFF, SRAM_SIZE)

    ok = true
    return
}

// Load ROM data
memory_load_rom :: proc(memory: ^Memory, data: []u8) -> bool {
    if len(data) < ROM_MIN_SIZE || len(data) > ROM_MAX_SIZE {
        return false
    }

    // Allocate ROM
    rom, err := make([]u8, len(data))
    if err != nil {
        return false
    }
    memory.rom = rom
    copy(memory.rom, data)

    return true
}

// Load BIOS data
memory_load_bios :: proc(memory: ^Memory, data: []u8) -> bool {
    if len(data) != BIOS_SIZE {
        return false
    }

    copy(memory.bios, data)
    return true
}

// Free all memory
memory_destroy :: proc(memory: ^Memory) {
    if memory.arena != nil {
        delete(memory.arena)
        memory.arena = nil
    }
    if memory.rom != nil {
        delete(memory.rom)
        memory.rom = nil
    }
    if memory.sram != nil {
        delete(memory.sram)
        memory.sram = nil
    }
}

// Reset allocation pointer (for save state restore)
memory_reset :: proc(memory: ^Memory) {
    // Zero EWRAM, IWRAM, Palette, VRAM, OAM
    mem.zero_slice(memory.ewram)
    mem.zero_slice(memory.iwram)
    mem.zero_slice(memory.palette)
    mem.zero_slice(memory.vram)
    mem.zero_slice(memory.oam)
    // I/O initialized with defaults in bus_init
}
