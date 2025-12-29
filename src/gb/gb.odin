package gb

import "core:fmt"
import "cpu"
import "bus"
import "ppu"

// Main Game Boy system structure
GameBoy :: struct {
    cpu:  cpu.CPU,
    bus:  bus.Bus,
    ppu:  ppu.PPU,

    // External RAM allocation
    eram: []u8,

    // System type (DMG or CGB)
    is_cgb: bool,

    // Frame counter
    frame: u64,

    // Cycles per frame (70224 for DMG)
    cycles_per_frame: u32,
    frame_cycles: u32,
}

// Resolution constants
SCREEN_WIDTH :: ppu.SCREEN_WIDTH
SCREEN_HEIGHT :: ppu.SCREEN_HEIGHT

// Initialize Game Boy with ROM data
gb_init :: proc(gb: ^GameBoy, rom: []u8, is_cgb: bool) -> bool {
    gb.is_cgb = is_cgb

    // Detect external RAM size from cartridge header
    eram_size := get_eram_size(rom)
    if eram_size > 0 {
        gb.eram = make([]u8, eram_size)
    }

    // Initialize bus with ROM
    bus.bus_init(&gb.bus, rom, gb.eram)

    // Initialize PPU
    ppu.ppu_init(&gb.ppu)
    gb.ppu.vram = &gb.bus.vram
    gb.ppu.oam = &gb.bus.oam
    gb.bus.ppu = &gb.ppu

    // Initialize CPU
    if is_cgb {
        cpu.cpu_init_cgb(&gb.cpu)
    } else {
        cpu.cpu_init_dmg(&gb.cpu)
    }

    gb.cycles_per_frame = 70224  // 154 scanlines * 456 cycles
    gb.frame_cycles = 0
    gb.frame = 0

    return true
}

// Get external RAM size from cartridge header
get_eram_size :: proc(rom: []u8) -> int {
    if len(rom) < 0x14A {
        return 0
    }

    switch rom[0x149] {
    case 0x00: return 0
    case 0x01: return 2048      // 2KB (listed but unused)
    case 0x02: return 8192      // 8KB
    case 0x03: return 32768     // 32KB (4 banks)
    case 0x04: return 131072    // 128KB (16 banks)
    case 0x05: return 65536     // 64KB (8 banks)
    case:      return 0
    }
}

// Run one frame
run_frame :: proc(gb: ^GameBoy) -> bool {
    target_cycles := gb.cycles_per_frame

    for gb.frame_cycles < target_cycles {
        cycles := step(gb)
        gb.frame_cycles += u32(cycles)
    }

    gb.frame_cycles -= target_cycles
    gb.frame += 1
    return true
}

// Step the system by one CPU instruction
step :: proc(gb: ^GameBoy) -> u8 {
    c := &gb.cpu
    b := &gb.bus

    // Handle scheduled IME enable
    if c.ime_scheduled {
        c.ime_scheduled = false
        c.ime = true
    }

    // If halted, just tick 4 cycles
    cycles: u8 = 4
    if !c.halted {
        // Fetch opcode
        opcode := bus.read(b, c.pc)
        c.pc += 1

        // Execute instruction
        cycles = execute_instruction(gb, opcode)
    }

    // Handle interrupts
    serviced, new_if := cpu.handle_interrupts(c, b.ie, b.if_)
    if serviced {
        b.if_ = new_if
        cycles += 20
    }

    // Step PPU
    _, stat_int := ppu.step(&gb.ppu, cycles)
    if stat_int {
        b.if_ |= 0x02  // LCD STAT interrupt
    }

    // Step timer
    bus.tick_timer(b, cycles)

    return cycles
}

// Execute a single instruction - simplified implementation
// For a full implementation, this would need to implement all LR35902 opcodes
execute_instruction :: proc(gb: ^GameBoy, opcode: u8) -> u8 {
    c := &gb.cpu
    b := &gb.bus

    // Fetch helpers
    fetch8 :: proc(gb: ^GameBoy) -> u8 {
        val := bus.read(&gb.bus, gb.cpu.pc)
        gb.cpu.pc += 1
        return val
    }

    fetch16 :: proc(gb: ^GameBoy) -> u16 {
        lo := u16(bus.read(&gb.bus, gb.cpu.pc))
        gb.cpu.pc += 1
        hi := u16(bus.read(&gb.bus, gb.cpu.pc))
        gb.cpu.pc += 1
        return (hi << 8) | lo
    }

    // Common instructions needed for basic operation
    switch opcode {
    case 0x00: // NOP
        return 4

    case 0x01: // LD BC, nn
        nn := fetch16(gb)
        c.b = u8(nn >> 8)
        c.c = u8(nn)
        return 12

    case 0x11: // LD DE, nn
        nn := fetch16(gb)
        c.d = u8(nn >> 8)
        c.e = u8(nn)
        return 12

    case 0x21: // LD HL, nn
        nn := fetch16(gb)
        c.h = u8(nn >> 8)
        c.l = u8(nn)
        return 12

    case 0x31: // LD SP, nn
        c.sp = fetch16(gb)
        return 12

    case 0x3E: // LD A, n
        c.a = fetch8(gb)
        return 8

    case 0x76: // HALT
        c.halted = true
        return 4

    case 0xAF: // XOR A
        c.a = 0
        c.f = 0x80  // Z=1, N=0, H=0, C=0
        return 4

    case 0xC3: // JP nn
        c.pc = fetch16(gb)
        return 16

    case 0xCD: // CALL nn
        addr := fetch16(gb)
        c.sp -= 1
        bus.write(b, c.sp, u8(c.pc >> 8))
        c.sp -= 1
        bus.write(b, c.sp, u8(c.pc))
        c.pc = addr
        return 24

    case 0xC9: // RET
        lo := u16(bus.read(b, c.sp))
        c.sp += 1
        hi := u16(bus.read(b, c.sp))
        c.sp += 1
        c.pc = (hi << 8) | lo
        return 16

    case 0xE0: // LD (FF00+n), A
        n := fetch8(gb)
        bus.write(b, 0xFF00 + u16(n), c.a)
        return 12

    case 0xF0: // LD A, (FF00+n)
        n := fetch8(gb)
        c.a = bus.read(b, 0xFF00 + u16(n))
        return 12

    case 0xF3: // DI
        c.ime = false
        return 4

    case 0xFB: // EI
        c.ime_scheduled = true
        return 4

    case 0xFE: // CP n
        n := fetch8(gb)
        result := i16(c.a) - i16(n)
        c.f = 0x40  // N=1
        if u8(result) == 0 { c.f |= 0x80 }  // Z
        if (c.a & 0x0F) < (n & 0x0F) { c.f |= 0x20 }  // H
        if result < 0 { c.f |= 0x10 }  // C
        return 8

    case 0x18: // JR n
        offset := i8(fetch8(gb))
        c.pc = u16(i32(c.pc) + i32(offset))
        return 12

    case 0x20: // JR NZ, n
        offset := i8(fetch8(gb))
        if (c.f & 0x80) == 0 {
            c.pc = u16(i32(c.pc) + i32(offset))
            return 12
        }
        return 8

    case 0x28: // JR Z, n
        offset := i8(fetch8(gb))
        if (c.f & 0x80) != 0 {
            c.pc = u16(i32(c.pc) + i32(offset))
            return 12
        }
        return 8

    case:
        // Unknown opcode - treat as NOP for now
        // A full implementation would handle all 256 opcodes
        return 4
    }
}

// Get framebuffer pointer
get_framebuffer :: proc(gb: ^GameBoy) -> ^[SCREEN_HEIGHT][SCREEN_WIDTH]u16 {
    return &gb.ppu.framebuffer
}

// Update joypad input
// buttons: bit 0=A, 1=B, 2=Select, 3=Start
// dpad: bit 0=Right, 1=Left, 2=Up, 3=Down
update_input :: proc(gb: ^GameBoy, buttons: u8, dpad: u8) {
    bus.update_joypad(&gb.bus, ~buttons & 0x0F, ~dpad & 0x0F)
}

// Cleanup
gb_destroy :: proc(gb: ^GameBoy) {
    if gb.eram != nil {
        delete(gb.eram)
        gb.eram = nil
    }
}

// Get title from ROM header
get_rom_title :: proc(rom: []u8) -> string {
    if len(rom) < 0x144 {
        return "Unknown"
    }

    // Title is at 0x134-0x143 (16 bytes, older games)
    // or 0x134-0x13E (11 bytes, newer CGB games)
    title_bytes: [16]u8
    for i in 0 ..< 16 {
        if rom[0x134 + i] == 0 {
            break
        }
        title_bytes[i] = rom[0x134 + i]
    }

    return string(title_bytes[:])
}
