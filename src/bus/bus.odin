package bus

import "core:fmt"

// Memory region size constants
BIOS_SIZE :: 16_384
EWRAM_SIZE :: 262_144
IWRAM_SIZE :: 32_768
PALETTE_SIZE :: 1_024
VRAM_SIZE :: 98_304
OAM_SIZE :: 1_024
IO_SIZE :: 1_024
ROM_MAX_SIZE :: 33_554_432
SRAM_SIZE :: 131_072

Bus :: struct {
    // Memory region pointers (set from Memory struct)
    bios:    []u8,
    ewram:   []u8,
    iwram:   []u8,
    palette: []u8,
    vram:    []u8,
    oam:     []u8,
    io:      []u8,
    rom:     []u8,
    sram:    []u8,

    // BIOS protection
    last_bios_read: u32,
    pc:             ^u32, // Pointer to CPU's PC for BIOS protection check

    // Open bus
    last_prefetch: u32,

    // Last access tracking for sequential detection
    last_addr:   u32,
    last_width:  u8,
    last_region: u8,

    // I/O registers (directly accessible for subsystems)
    // Interrupt registers
    ie:  u16, // 0x04000200 - Interrupt Enable
    if_: u16, // 0x04000202 - Interrupt Flags
    ime: u16, // 0x04000208 - Interrupt Master Enable

    // Wait control
    waitcnt: u16, // 0x04000204 - Waitstate Control

    // System control
    postflg: u8, // 0x04000300 - Post-boot flag
    haltcnt: u8, // 0x04000301 - Halt control (write-only)

    // Halt request callback
    halt_requested: bool,
}

// Initialize bus with memory regions
bus_init :: proc(bus: ^Bus, bios, ewram, iwram, palette, vram, oam, io, rom, sram: []u8) {
    bus.bios = bios
    bus.ewram = ewram
    bus.iwram = iwram
    bus.palette = palette
    bus.vram = vram
    bus.oam = oam
    bus.io = io
    bus.rom = rom
    bus.sram = sram

    // Initialize BIOS protection
    bus.last_bios_read = 0xE129F000 // Typical post-boot value

    // Initialize tracking
    bus.last_addr = 0
    bus.last_width = 0
    bus.last_region = 0xFF

    // Initialize I/O defaults
    bus.ie = 0
    bus.if_ = 0
    bus.ime = 0
    bus.waitcnt = 0
    bus.postflg = 0
    bus.haltcnt = 0
    bus.halt_requested = false
}

// Set PC pointer for BIOS protection
bus_set_pc_ptr :: proc(bus: ^Bus, pc: ^u32) {
    bus.pc = pc
}

// Region identification from address
@(private)
get_region :: proc(addr: u32) -> u8 {
    return u8((addr >> 24) & 0xFF)
}

// Check if access is sequential
@(private)
is_sequential :: proc(bus: ^Bus, addr: u32, width: u8) -> bool {
    region := get_region(addr)
    seq := (addr == bus.last_addr + u32(bus.last_width)) && (region == bus.last_region)
    bus.last_addr = addr
    bus.last_width = width
    bus.last_region = region
    return seq
}

// Read 8-bit value
read8 :: proc(bus: ^Bus, addr: u32) -> (value: u8, cycles: u8) {
    _ = is_sequential(bus, addr, 1)
    region := get_region(addr)

    switch region {
    case 0x00: // BIOS
        if bus.pc != nil && bus.pc^ < 0x4000 {
            offset := addr & 0x3FFF
            if offset < u32(len(bus.bios)) {
                value = bus.bios[offset]
                bus.last_bios_read = (bus.last_bios_read & 0xFFFFFF00) | u32(value)
            }
        } else {
            value = u8(bus.last_bios_read)
        }
        cycles = 1
    case 0x02: // EWRAM
        offset := addr & 0x3FFFF // Mirror every 256KB
        value = bus.ewram[offset]
        cycles = 3
    case 0x03: // IWRAM
        offset := addr & 0x7FFF // Mirror every 32KB
        value = bus.iwram[offset]
        cycles = 1
    case 0x04: // I/O
        value, cycles = read_io8(bus, addr)
    case 0x05: // Palette
        offset := addr & 0x3FF // Mirror every 1KB
        value = bus.palette[offset]
        cycles = 1
    case 0x06: // VRAM
        offset := addr & 0x1FFFF // 128KB mirror
        if offset >= VRAM_SIZE {
            offset -= 0x8000 // Special 96KB behavior
        }
        value = bus.vram[offset]
        cycles = 1
    case 0x07: // OAM
        offset := addr & 0x3FF // Mirror every 1KB
        value = bus.oam[offset]
        cycles = 1
    case 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D: // ROM
        offset := addr & 0x1FFFFFF // 32MB address space
        if offset < u32(len(bus.rom)) {
            value = bus.rom[offset]
        } else if len(bus.rom) > 0 {
            // Mirror ROM
            value = bus.rom[offset % u32(len(bus.rom))]
        } else {
            value = u8(offset >> 1) // Open bus for ROM
        }
        cycles = 5 // Default N-cycle
    case 0x0E, 0x0F: // SRAM
        offset := addr & 0xFFFF // 64KB address space
        if offset < u32(len(bus.sram)) {
            value = bus.sram[offset]
        }
        cycles = 5
    case:
        // Open bus
        value = u8(bus.last_prefetch)
        cycles = 1
    }

    return
}

// Read 16-bit value
read16 :: proc(bus: ^Bus, addr: u32) -> (value: u16, cycles: u8) {
    aligned_addr := addr & ~u32(1) // Force align
    _ = is_sequential(bus, aligned_addr, 2)

    region := get_region(aligned_addr)

    // Read based on region
    switch region {
    case 0x00: // BIOS
        if bus.pc != nil && bus.pc^ < 0x4000 {
            offset := aligned_addr & 0x3FFF
            if offset + 1 < u32(len(bus.bios)) {
                value = u16(bus.bios[offset]) | (u16(bus.bios[offset + 1]) << 8)
                bus.last_bios_read = u32(value) | (u32(value) << 16)
            }
        } else {
            value = u16(bus.last_bios_read)
        }
        cycles = 1
    case 0x02: // EWRAM
        offset := aligned_addr & 0x3FFFF
        value = u16(bus.ewram[offset]) | (u16(bus.ewram[offset + 1]) << 8)
        cycles = 3
    case 0x03: // IWRAM
        offset := aligned_addr & 0x7FFF
        value = u16(bus.iwram[offset]) | (u16(bus.iwram[offset + 1]) << 8)
        cycles = 1
    case 0x04: // I/O
        value, cycles = read_io16(bus, aligned_addr)
    case 0x05: // Palette
        offset := aligned_addr & 0x3FF
        value = u16(bus.palette[offset]) | (u16(bus.palette[offset + 1]) << 8)
        cycles = 1
    case 0x06: // VRAM
        offset := aligned_addr & 0x1FFFF
        if offset >= VRAM_SIZE {
            offset -= 0x8000
        }
        value = u16(bus.vram[offset]) | (u16(bus.vram[offset + 1]) << 8)
        cycles = 1
    case 0x07: // OAM
        offset := aligned_addr & 0x3FF
        value = u16(bus.oam[offset]) | (u16(bus.oam[offset + 1]) << 8)
        cycles = 1
    case 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D: // ROM
        offset := aligned_addr & 0x1FFFFFF
        if offset + 1 < u32(len(bus.rom)) {
            value = u16(bus.rom[offset]) | (u16(bus.rom[offset + 1]) << 8)
        } else if len(bus.rom) > 0 {
            mirror_offset := offset % u32(len(bus.rom))
            value = u16(bus.rom[mirror_offset])
            if mirror_offset + 1 < u32(len(bus.rom)) {
                value |= u16(bus.rom[mirror_offset + 1]) << 8
            }
        } else {
            value = u16(offset >> 1)
        }
        cycles = 5
    case 0x0E, 0x0F: // SRAM (8-bit bus, reads return byte twice)
        offset := aligned_addr & 0xFFFF
        if offset < u32(len(bus.sram)) {
            value = u16(bus.sram[offset]) | (u16(bus.sram[offset]) << 8)
        }
        cycles = 5
    case:
        value = u16(bus.last_prefetch)
        cycles = 1
    }

    // Handle misaligned rotation
    if (addr & 1) != 0 {
        value = (value >> 8) | (value << 8)
    }

    return
}

// Read 32-bit value
read32 :: proc(bus: ^Bus, addr: u32) -> (value: u32, cycles: u8) {
    aligned_addr := addr & ~u32(3) // Force align
    _ = is_sequential(bus, aligned_addr, 4)

    region := get_region(aligned_addr)

    switch region {
    case 0x00: // BIOS
        if bus.pc != nil && bus.pc^ < 0x4000 {
            offset := aligned_addr & 0x3FFF
            if offset + 3 < u32(len(bus.bios)) {
                value = u32(bus.bios[offset]) |
                    (u32(bus.bios[offset + 1]) << 8) |
                    (u32(bus.bios[offset + 2]) << 16) |
                    (u32(bus.bios[offset + 3]) << 24)
                bus.last_bios_read = value
            }
        } else {
            value = bus.last_bios_read
        }
        cycles = 1
    case 0x02: // EWRAM (16-bit bus, 2 accesses)
        offset := aligned_addr & 0x3FFFF
        value = u32(bus.ewram[offset]) |
            (u32(bus.ewram[offset + 1]) << 8) |
            (u32(bus.ewram[offset + 2]) << 16) |
            (u32(bus.ewram[offset + 3]) << 24)
        cycles = 6 // Two 16-bit accesses
    case 0x03: // IWRAM
        offset := aligned_addr & 0x7FFF
        value = u32(bus.iwram[offset]) |
            (u32(bus.iwram[offset + 1]) << 8) |
            (u32(bus.iwram[offset + 2]) << 16) |
            (u32(bus.iwram[offset + 3]) << 24)
        cycles = 1
    case 0x04: // I/O
        value, cycles = read_io32(bus, aligned_addr)
    case 0x05: // Palette (16-bit bus)
        offset := aligned_addr & 0x3FF
        value = u32(bus.palette[offset]) |
            (u32(bus.palette[offset + 1]) << 8) |
            (u32(bus.palette[(offset + 2) & 0x3FF]) << 16) |
            (u32(bus.palette[(offset + 3) & 0x3FF]) << 24)
        cycles = 2
    case 0x06: // VRAM (16-bit bus)
        offset := aligned_addr & 0x1FFFF
        if offset >= VRAM_SIZE {
            offset -= 0x8000
        }
        value = u32(bus.vram[offset]) |
            (u32(bus.vram[offset + 1]) << 8) |
            (u32(bus.vram[(offset + 2) % VRAM_SIZE]) << 16) |
            (u32(bus.vram[(offset + 3) % VRAM_SIZE]) << 24)
        cycles = 2
    case 0x07: // OAM
        offset := aligned_addr & 0x3FF
        value = u32(bus.oam[offset]) |
            (u32(bus.oam[offset + 1]) << 8) |
            (u32(bus.oam[(offset + 2) & 0x3FF]) << 16) |
            (u32(bus.oam[(offset + 3) & 0x3FF]) << 24)
        cycles = 1
    case 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D: // ROM
        offset := aligned_addr & 0x1FFFFFF
        if offset + 3 < u32(len(bus.rom)) {
            value = u32(bus.rom[offset]) |
                (u32(bus.rom[offset + 1]) << 8) |
                (u32(bus.rom[offset + 2]) << 16) |
                (u32(bus.rom[offset + 3]) << 24)
        } else if len(bus.rom) > 0 {
            // Handle mirroring and partial reads
            for i in u32(0) ..< 4 {
                byte_offset := (offset + i) % u32(len(bus.rom))
                value |= u32(bus.rom[byte_offset]) << (i * 8)
            }
        } else {
            value = (offset >> 1) | ((offset >> 1) << 16)
        }
        cycles = 8 // Two 16-bit accesses
    case 0x0E, 0x0F: // SRAM (8-bit bus)
        offset := aligned_addr & 0xFFFF
        if offset < u32(len(bus.sram)) {
            b := bus.sram[offset]
            value = u32(b) | (u32(b) << 8) | (u32(b) << 16) | (u32(b) << 24)
        }
        cycles = 5
    case:
        value = bus.last_prefetch
        cycles = 1
    }

    // Handle misaligned rotation
    rotation := (addr & 3) * 8
    if rotation != 0 {
        value = (value >> rotation) | (value << (32 - rotation))
    }

    return
}

// Write 8-bit value
write8 :: proc(bus: ^Bus, addr: u32, value: u8) -> (cycles: u8) {
    _ = is_sequential(bus, addr, 1)
    region := get_region(addr)

    switch region {
    case 0x00: // BIOS - read only
        cycles = 1
    case 0x02: // EWRAM
        offset := addr & 0x3FFFF
        bus.ewram[offset] = value
        cycles = 3
    case 0x03: // IWRAM
        offset := addr & 0x7FFF
        bus.iwram[offset] = value
        cycles = 1
    case 0x04: // I/O
        cycles = write_io8(bus, addr, value)
    case 0x05: // Palette - 8-bit writes are weird (write to both bytes)
        offset := addr & 0x3FE // Force halfword align
        bus.palette[offset] = value
        bus.palette[offset + 1] = value
        cycles = 1
    case 0x06: // VRAM - 8-bit writes are weird
        offset := addr & 0x1FFFF
        if offset >= VRAM_SIZE {
            offset -= 0x8000
        }
        // In bitmap modes (3/4/5), 8-bit writes work to bg area
        // In tile modes, 8-bit writes to bg are ignored
        // For now, implement bitmap mode behavior
        aligned_offset := offset & ~u32(1)
        bus.vram[aligned_offset] = value
        bus.vram[aligned_offset + 1] = value
        cycles = 1
    case 0x07: // OAM - 8-bit writes are ignored
        cycles = 1
    case 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D: // ROM - read only
        cycles = 5
    case 0x0E, 0x0F: // SRAM
        offset := addr & 0xFFFF
        if offset < u32(len(bus.sram)) {
            bus.sram[offset] = value
        }
        cycles = 5
    case:
        cycles = 1
    }

    return
}

// Write 16-bit value
write16 :: proc(bus: ^Bus, addr: u32, value: u16) -> (cycles: u8) {
    aligned_addr := addr & ~u32(1)
    _ = is_sequential(bus, aligned_addr, 2)
    region := get_region(aligned_addr)

    switch region {
    case 0x00: // BIOS - read only
        cycles = 1
    case 0x02: // EWRAM
        offset := aligned_addr & 0x3FFFF
        bus.ewram[offset] = u8(value)
        bus.ewram[offset + 1] = u8(value >> 8)
        cycles = 3
    case 0x03: // IWRAM
        offset := aligned_addr & 0x7FFF
        bus.iwram[offset] = u8(value)
        bus.iwram[offset + 1] = u8(value >> 8)
        cycles = 1
    case 0x04: // I/O
        cycles = write_io16(bus, aligned_addr, value)
    case 0x05: // Palette
        offset := aligned_addr & 0x3FF
        bus.palette[offset] = u8(value)
        bus.palette[offset + 1] = u8(value >> 8)
        cycles = 1
    case 0x06: // VRAM
        offset := aligned_addr & 0x1FFFF
        if offset >= VRAM_SIZE {
            offset -= 0x8000
        }
        bus.vram[offset] = u8(value)
        bus.vram[offset + 1] = u8(value >> 8)
        cycles = 1
    case 0x07: // OAM
        offset := aligned_addr & 0x3FF
        bus.oam[offset] = u8(value)
        bus.oam[offset + 1] = u8(value >> 8)
        cycles = 1
    case 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D: // ROM - read only
        cycles = 5
    case 0x0E, 0x0F: // SRAM (8-bit bus)
        offset := aligned_addr & 0xFFFF
        if offset < u32(len(bus.sram)) {
            bus.sram[offset] = u8(value)
        }
        cycles = 5
    case:
        cycles = 1
    }

    return
}

// Write 32-bit value
write32 :: proc(bus: ^Bus, addr: u32, value: u32) -> (cycles: u8) {
    aligned_addr := addr & ~u32(3)
    _ = is_sequential(bus, aligned_addr, 4)
    region := get_region(aligned_addr)

    switch region {
    case 0x00: // BIOS - read only
        cycles = 1
    case 0x02: // EWRAM
        offset := aligned_addr & 0x3FFFF
        bus.ewram[offset] = u8(value)
        bus.ewram[offset + 1] = u8(value >> 8)
        bus.ewram[offset + 2] = u8(value >> 16)
        bus.ewram[offset + 3] = u8(value >> 24)
        cycles = 6
    case 0x03: // IWRAM
        offset := aligned_addr & 0x7FFF
        bus.iwram[offset] = u8(value)
        bus.iwram[offset + 1] = u8(value >> 8)
        bus.iwram[offset + 2] = u8(value >> 16)
        bus.iwram[offset + 3] = u8(value >> 24)
        cycles = 1
    case 0x04: // I/O
        cycles = write_io32(bus, aligned_addr, value)
    case 0x05: // Palette
        offset := aligned_addr & 0x3FF
        bus.palette[offset] = u8(value)
        bus.palette[offset + 1] = u8(value >> 8)
        bus.palette[(offset + 2) & 0x3FF] = u8(value >> 16)
        bus.palette[(offset + 3) & 0x3FF] = u8(value >> 24)
        cycles = 2
    case 0x06: // VRAM
        offset := aligned_addr & 0x1FFFF
        if offset >= VRAM_SIZE {
            offset -= 0x8000
        }
        bus.vram[offset] = u8(value)
        bus.vram[offset + 1] = u8(value >> 8)
        bus.vram[(offset + 2) % VRAM_SIZE] = u8(value >> 16)
        bus.vram[(offset + 3) % VRAM_SIZE] = u8(value >> 24)
        cycles = 2
    case 0x07: // OAM
        offset := aligned_addr & 0x3FF
        bus.oam[offset] = u8(value)
        bus.oam[offset + 1] = u8(value >> 8)
        bus.oam[(offset + 2) & 0x3FF] = u8(value >> 16)
        bus.oam[(offset + 3) & 0x3FF] = u8(value >> 24)
        cycles = 1
    case 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D: // ROM - read only
        cycles = 8
    case 0x0E, 0x0F: // SRAM (8-bit bus)
        offset := aligned_addr & 0xFFFF
        if offset < u32(len(bus.sram)) {
            bus.sram[offset] = u8(value)
        }
        cycles = 5
    case:
        cycles = 1
    }

    return
}

// Update prefetch value (called after instruction fetch)
bus_update_prefetch :: proc(bus: ^Bus, value: u32) {
    bus.last_prefetch = value
}
