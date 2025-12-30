package gb

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
    case 0x01: return 2048
    case 0x02: return 8192
    case 0x03: return 32768
    case 0x04: return 131072
    case 0x05: return 65536
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

// Memory access helpers
@(private)
read8 :: #force_inline proc(gb: ^GameBoy, addr: u16) -> u8 {
    return bus.read(&gb.bus, addr)
}

@(private)
write8 :: #force_inline proc(gb: ^GameBoy, addr: u16, value: u8) {
    bus.write(&gb.bus, addr, value)
}

@(private)
fetch8 :: #force_inline proc(gb: ^GameBoy) -> u8 {
    val := bus.read(&gb.bus, gb.cpu.pc)
    gb.cpu.pc += 1
    return val
}

@(private)
fetch16 :: #force_inline proc(gb: ^GameBoy) -> u16 {
    lo := u16(bus.read(&gb.bus, gb.cpu.pc))
    gb.cpu.pc += 1
    hi := u16(bus.read(&gb.bus, gb.cpu.pc))
    gb.cpu.pc += 1
    return (hi << 8) | lo
}

@(private)
push16 :: #force_inline proc(gb: ^GameBoy, value: u16) {
    gb.cpu.sp -= 1
    bus.write(&gb.bus, gb.cpu.sp, u8(value >> 8))
    gb.cpu.sp -= 1
    bus.write(&gb.bus, gb.cpu.sp, u8(value))
}

@(private)
pop16 :: #force_inline proc(gb: ^GameBoy) -> u16 {
    lo := u16(bus.read(&gb.bus, gb.cpu.sp))
    gb.cpu.sp += 1
    hi := u16(bus.read(&gb.bus, gb.cpu.sp))
    gb.cpu.sp += 1
    return (hi << 8) | lo
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
        opcode := fetch8(gb)
        cycles = execute(gb, opcode)
    }

    // Handle interrupts (directly, without using cpu callbacks)
    serviced := handle_interrupts_direct(gb)
    if serviced {
        cycles += 20
    }

    // Step PPU
    vblank, stat_int := ppu.step(&gb.ppu, cycles)
    if vblank {
        b.if_ |= 0x01  // VBlank interrupt
    }
    if stat_int {
        b.if_ |= 0x02
    }

    // Step timer
    bus.tick_timer(b, cycles)

    return cycles
}

// Handle interrupts using CPU package helper
@(private)
handle_interrupts_direct :: proc(gb: ^GameBoy) -> bool {
    c := &gb.cpu
    b := &gb.bus

    // Check for pending interrupts (also handles wake-from-halt)
    pending, vector, interrupt_bit := cpu.check_interrupts(c, b.ie, b.if_)
    if !pending {
        return false
    }

    // Service the interrupt: push PC, jump to vector, clear IF bit
    c.ime = false
    push16(gb, c.pc)
    c.pc = vector
    b.if_ &= ~interrupt_bit
    return true
}

// Execute main opcode - uses opcode table for cycle timing
execute :: proc(gb: ^GameBoy, opcode: u8) -> u8 {
    c := &gb.cpu
    info := &cpu.OPCODES[opcode]

    // CB prefix
    if opcode == 0xCB {
        return execute_cb(gb, fetch8(gb))
    }

    // For conditional instructions, track whether condition was taken
    // alt_cycles is used when condition is NOT taken
    condition_taken := true

    switch opcode {
    // 0x00-0x0F
    case 0x00:  // NOP
    case 0x01: cpu.set_bc(c, fetch16(gb))  // LD BC,nn
    case 0x02: write8(gb, cpu.get_bc(c), c.a)  // LD (BC),A
    case 0x03: cpu.set_bc(c, cpu.get_bc(c) + 1)  // INC BC
    case 0x04: c.b = cpu.inc8(c, c.b)  // INC B
    case 0x05: c.b = cpu.dec8(c, c.b)  // DEC B
    case 0x06: c.b = fetch8(gb)  // LD B,n
    case 0x07:  // RLCA
        carry := (c.a & 0x80) != 0
        c.a = (c.a << 1) | (c.a >> 7)
        c.f = carry ? 0x10 : 0
    case 0x08:  // LD (nn),SP
        addr := fetch16(gb)
        write8(gb, addr, u8(c.sp))
        write8(gb, addr + 1, u8(c.sp >> 8))
    case 0x09: cpu.add_hl(c, cpu.get_bc(c))  // ADD HL,BC
    case 0x0A: c.a = read8(gb, cpu.get_bc(c))  // LD A,(BC)
    case 0x0B: cpu.set_bc(c, cpu.get_bc(c) - 1)  // DEC BC
    case 0x0C: c.c = cpu.inc8(c, c.c)  // INC C
    case 0x0D: c.c = cpu.dec8(c, c.c)  // DEC C
    case 0x0E: c.c = fetch8(gb)  // LD C,n
    case 0x0F:  // RRCA
        carry := (c.a & 0x01) != 0
        c.a = (c.a >> 1) | (c.a << 7)
        c.f = carry ? 0x10 : 0

    // 0x10-0x1F
    case 0x10: fetch8(gb); c.stopped = true  // STOP
    case 0x11: cpu.set_de(c, fetch16(gb))  // LD DE,nn
    case 0x12: write8(gb, cpu.get_de(c), c.a)  // LD (DE),A
    case 0x13: cpu.set_de(c, cpu.get_de(c) + 1)  // INC DE
    case 0x14: c.d = cpu.inc8(c, c.d)  // INC D
    case 0x15: c.d = cpu.dec8(c, c.d)  // DEC D
    case 0x16: c.d = fetch8(gb)  // LD D,n
    case 0x17:  // RLA
        old_carry := (c.f & 0x10) != 0
        new_carry := (c.a & 0x80) != 0
        c.a = (c.a << 1) | (old_carry ? 1 : 0)
        c.f = new_carry ? 0x10 : 0
    case 0x18:  // JR n
        offset := i8(fetch8(gb))
        c.pc = u16(i32(c.pc) + i32(offset))
    case 0x19: cpu.add_hl(c, cpu.get_de(c))  // ADD HL,DE
    case 0x1A: c.a = read8(gb, cpu.get_de(c))  // LD A,(DE)
    case 0x1B: cpu.set_de(c, cpu.get_de(c) - 1)  // DEC DE
    case 0x1C: c.e = cpu.inc8(c, c.e)  // INC E
    case 0x1D: c.e = cpu.dec8(c, c.e)  // DEC E
    case 0x1E: c.e = fetch8(gb)  // LD E,n
    case 0x1F:  // RRA
        old_carry := (c.f & 0x10) != 0
        new_carry := (c.a & 0x01) != 0
        c.a = (c.a >> 1) | (old_carry ? 0x80 : 0)
        c.f = new_carry ? 0x10 : 0

    // 0x20-0x2F
    case 0x20:  // JR NZ,n
        offset := i8(fetch8(gb))
        if (c.f & 0x80) == 0 {
            c.pc = u16(i32(c.pc) + i32(offset))
        } else {
            condition_taken = false
        }
    case 0x21: cpu.set_hl(c, fetch16(gb))  // LD HL,nn
    case 0x22: write8(gb, cpu.get_hl(c), c.a); cpu.set_hl(c, cpu.get_hl(c) + 1)  // LD (HL+),A
    case 0x23: cpu.set_hl(c, cpu.get_hl(c) + 1)  // INC HL
    case 0x24: c.h = cpu.inc8(c, c.h)  // INC H
    case 0x25: c.h = cpu.dec8(c, c.h)  // DEC H
    case 0x26: c.h = fetch8(gb)  // LD H,n
    case 0x27: cpu.daa(c)  // DAA
    case 0x28:  // JR Z,n
        offset := i8(fetch8(gb))
        if (c.f & 0x80) != 0 {
            c.pc = u16(i32(c.pc) + i32(offset))
        } else {
            condition_taken = false
        }
    case 0x29: cpu.add_hl(c, cpu.get_hl(c))  // ADD HL,HL
    case 0x2A: c.a = read8(gb, cpu.get_hl(c)); cpu.set_hl(c, cpu.get_hl(c) + 1)  // LD A,(HL+)
    case 0x2B: cpu.set_hl(c, cpu.get_hl(c) - 1)  // DEC HL
    case 0x2C: c.l = cpu.inc8(c, c.l)  // INC L
    case 0x2D: c.l = cpu.dec8(c, c.l)  // DEC L
    case 0x2E: c.l = fetch8(gb)  // LD L,n
    case 0x2F: c.a = ~c.a; c.f |= 0x60  // CPL

    // 0x30-0x3F
    case 0x30:  // JR NC,n
        offset := i8(fetch8(gb))
        if (c.f & 0x10) == 0 {
            c.pc = u16(i32(c.pc) + i32(offset))
        } else {
            condition_taken = false
        }
    case 0x31: c.sp = fetch16(gb)  // LD SP,nn
    case 0x32: write8(gb, cpu.get_hl(c), c.a); cpu.set_hl(c, cpu.get_hl(c) - 1)  // LD (HL-),A
    case 0x33: c.sp += 1  // INC SP
    case 0x34: write8(gb, cpu.get_hl(c), cpu.inc8(c, read8(gb, cpu.get_hl(c))))  // INC (HL)
    case 0x35: write8(gb, cpu.get_hl(c), cpu.dec8(c, read8(gb, cpu.get_hl(c))))  // DEC (HL)
    case 0x36: write8(gb, cpu.get_hl(c), fetch8(gb))  // LD (HL),n
    case 0x37: c.f = (c.f & 0x80) | 0x10  // SCF
    case 0x38:  // JR C,n
        offset := i8(fetch8(gb))
        if (c.f & 0x10) != 0 {
            c.pc = u16(i32(c.pc) + i32(offset))
        } else {
            condition_taken = false
        }
    case 0x39: cpu.add_hl(c, c.sp)  // ADD HL,SP
    case 0x3A: c.a = read8(gb, cpu.get_hl(c)); cpu.set_hl(c, cpu.get_hl(c) - 1)  // LD A,(HL-)
    case 0x3B: c.sp -= 1  // DEC SP
    case 0x3C: c.a = cpu.inc8(c, c.a)  // INC A
    case 0x3D: c.a = cpu.dec8(c, c.a)  // DEC A
    case 0x3E: c.a = fetch8(gb)  // LD A,n
    case 0x3F: c.f = (c.f & 0x90) ~ 0x10  // CCF - toggle C, clear N/H, keep Z

    // 0x40-0x7F: LD r,r' and HALT
    case 0x40:  // LD B,B
    case 0x41: c.b = c.c
    case 0x42: c.b = c.d
    case 0x43: c.b = c.e
    case 0x44: c.b = c.h
    case 0x45: c.b = c.l
    case 0x46: c.b = read8(gb, cpu.get_hl(c))
    case 0x47: c.b = c.a
    case 0x48: c.c = c.b
    case 0x49:  // LD C,C
    case 0x4A: c.c = c.d
    case 0x4B: c.c = c.e
    case 0x4C: c.c = c.h
    case 0x4D: c.c = c.l
    case 0x4E: c.c = read8(gb, cpu.get_hl(c))
    case 0x4F: c.c = c.a
    case 0x50: c.d = c.b
    case 0x51: c.d = c.c
    case 0x52:  // LD D,D
    case 0x53: c.d = c.e
    case 0x54: c.d = c.h
    case 0x55: c.d = c.l
    case 0x56: c.d = read8(gb, cpu.get_hl(c))
    case 0x57: c.d = c.a
    case 0x58: c.e = c.b
    case 0x59: c.e = c.c
    case 0x5A: c.e = c.d
    case 0x5B:  // LD E,E
    case 0x5C: c.e = c.h
    case 0x5D: c.e = c.l
    case 0x5E: c.e = read8(gb, cpu.get_hl(c))
    case 0x5F: c.e = c.a
    case 0x60: c.h = c.b
    case 0x61: c.h = c.c
    case 0x62: c.h = c.d
    case 0x63: c.h = c.e
    case 0x64:  // LD H,H
    case 0x65: c.h = c.l
    case 0x66: c.h = read8(gb, cpu.get_hl(c))
    case 0x67: c.h = c.a
    case 0x68: c.l = c.b
    case 0x69: c.l = c.c
    case 0x6A: c.l = c.d
    case 0x6B: c.l = c.e
    case 0x6C: c.l = c.h
    case 0x6D:  // LD L,L
    case 0x6E: c.l = read8(gb, cpu.get_hl(c))
    case 0x6F: c.l = c.a
    case 0x70: write8(gb, cpu.get_hl(c), c.b)
    case 0x71: write8(gb, cpu.get_hl(c), c.c)
    case 0x72: write8(gb, cpu.get_hl(c), c.d)
    case 0x73: write8(gb, cpu.get_hl(c), c.e)
    case 0x74: write8(gb, cpu.get_hl(c), c.h)
    case 0x75: write8(gb, cpu.get_hl(c), c.l)
    case 0x76: c.halted = true  // HALT
    case 0x77: write8(gb, cpu.get_hl(c), c.a)
    case 0x78: c.a = c.b
    case 0x79: c.a = c.c
    case 0x7A: c.a = c.d
    case 0x7B: c.a = c.e
    case 0x7C: c.a = c.h
    case 0x7D: c.a = c.l
    case 0x7E: c.a = read8(gb, cpu.get_hl(c))
    case 0x7F:  // LD A,A

    // 0x80-0xBF: ALU operations
    case 0x80: cpu.add_a(c, c.b, false)
    case 0x81: cpu.add_a(c, c.c, false)
    case 0x82: cpu.add_a(c, c.d, false)
    case 0x83: cpu.add_a(c, c.e, false)
    case 0x84: cpu.add_a(c, c.h, false)
    case 0x85: cpu.add_a(c, c.l, false)
    case 0x86: cpu.add_a(c, read8(gb, cpu.get_hl(c)), false)
    case 0x87: cpu.add_a(c, c.a, false)
    case 0x88: cpu.add_a(c, c.b, true)
    case 0x89: cpu.add_a(c, c.c, true)
    case 0x8A: cpu.add_a(c, c.d, true)
    case 0x8B: cpu.add_a(c, c.e, true)
    case 0x8C: cpu.add_a(c, c.h, true)
    case 0x8D: cpu.add_a(c, c.l, true)
    case 0x8E: cpu.add_a(c, read8(gb, cpu.get_hl(c)), true)
    case 0x8F: cpu.add_a(c, c.a, true)
    case 0x90: cpu.sub_a(c, c.b, false)
    case 0x91: cpu.sub_a(c, c.c, false)
    case 0x92: cpu.sub_a(c, c.d, false)
    case 0x93: cpu.sub_a(c, c.e, false)
    case 0x94: cpu.sub_a(c, c.h, false)
    case 0x95: cpu.sub_a(c, c.l, false)
    case 0x96: cpu.sub_a(c, read8(gb, cpu.get_hl(c)), false)
    case 0x97: cpu.sub_a(c, c.a, false)
    case 0x98: cpu.sub_a(c, c.b, true)
    case 0x99: cpu.sub_a(c, c.c, true)
    case 0x9A: cpu.sub_a(c, c.d, true)
    case 0x9B: cpu.sub_a(c, c.e, true)
    case 0x9C: cpu.sub_a(c, c.h, true)
    case 0x9D: cpu.sub_a(c, c.l, true)
    case 0x9E: cpu.sub_a(c, read8(gb, cpu.get_hl(c)), true)
    case 0x9F: cpu.sub_a(c, c.a, true)
    case 0xA0: cpu.and_a(c, c.b)
    case 0xA1: cpu.and_a(c, c.c)
    case 0xA2: cpu.and_a(c, c.d)
    case 0xA3: cpu.and_a(c, c.e)
    case 0xA4: cpu.and_a(c, c.h)
    case 0xA5: cpu.and_a(c, c.l)
    case 0xA6: cpu.and_a(c, read8(gb, cpu.get_hl(c)))
    case 0xA7: cpu.and_a(c, c.a)
    case 0xA8: cpu.xor_a(c, c.b)
    case 0xA9: cpu.xor_a(c, c.c)
    case 0xAA: cpu.xor_a(c, c.d)
    case 0xAB: cpu.xor_a(c, c.e)
    case 0xAC: cpu.xor_a(c, c.h)
    case 0xAD: cpu.xor_a(c, c.l)
    case 0xAE: cpu.xor_a(c, read8(gb, cpu.get_hl(c)))
    case 0xAF: cpu.xor_a(c, c.a)
    case 0xB0: cpu.or_a(c, c.b)
    case 0xB1: cpu.or_a(c, c.c)
    case 0xB2: cpu.or_a(c, c.d)
    case 0xB3: cpu.or_a(c, c.e)
    case 0xB4: cpu.or_a(c, c.h)
    case 0xB5: cpu.or_a(c, c.l)
    case 0xB6: cpu.or_a(c, read8(gb, cpu.get_hl(c)))
    case 0xB7: cpu.or_a(c, c.a)
    case 0xB8: cpu.cp_a(c, c.b)
    case 0xB9: cpu.cp_a(c, c.c)
    case 0xBA: cpu.cp_a(c, c.d)
    case 0xBB: cpu.cp_a(c, c.e)
    case 0xBC: cpu.cp_a(c, c.h)
    case 0xBD: cpu.cp_a(c, c.l)
    case 0xBE: cpu.cp_a(c, read8(gb, cpu.get_hl(c)))
    case 0xBF: cpu.cp_a(c, c.a)

    // 0xC0-0xFF: Control, stack, misc
    case 0xC0:  // RET NZ
        if (c.f & 0x80) == 0 {
            c.pc = pop16(gb)
        } else {
            condition_taken = false
        }
    case 0xC1: cpu.set_bc(c, pop16(gb))  // POP BC
    case 0xC2:  // JP NZ,nn
        addr := fetch16(gb)
        if (c.f & 0x80) == 0 {
            c.pc = addr
        } else {
            condition_taken = false
        }
    case 0xC3: c.pc = fetch16(gb)  // JP nn
    case 0xC4:  // CALL NZ,nn
        addr := fetch16(gb)
        if (c.f & 0x80) == 0 {
            push16(gb, c.pc)
            c.pc = addr
        } else {
            condition_taken = false
        }
    case 0xC5: push16(gb, cpu.get_bc(c))  // PUSH BC
    case 0xC6: cpu.add_a(c, fetch8(gb), false)  // ADD A,n
    case 0xC7: push16(gb, c.pc); c.pc = 0x00  // RST 00
    case 0xC8:  // RET Z
        if (c.f & 0x80) != 0 {
            c.pc = pop16(gb)
        } else {
            condition_taken = false
        }
    case 0xC9: c.pc = pop16(gb)  // RET
    case 0xCA:  // JP Z,nn
        addr := fetch16(gb)
        if (c.f & 0x80) != 0 {
            c.pc = addr
        } else {
            condition_taken = false
        }
    // 0xCB is handled at start
    case 0xCC:  // CALL Z,nn
        addr := fetch16(gb)
        if (c.f & 0x80) != 0 {
            push16(gb, c.pc)
            c.pc = addr
        } else {
            condition_taken = false
        }
    case 0xCD:  // CALL nn
        addr := fetch16(gb)
        push16(gb, c.pc)
        c.pc = addr
    case 0xCE: cpu.add_a(c, fetch8(gb), true)  // ADC A,n
    case 0xCF: push16(gb, c.pc); c.pc = 0x08  // RST 08
    case 0xD0:  // RET NC
        if (c.f & 0x10) == 0 {
            c.pc = pop16(gb)
        } else {
            condition_taken = false
        }
    case 0xD1: cpu.set_de(c, pop16(gb))  // POP DE
    case 0xD2:  // JP NC,nn
        addr := fetch16(gb)
        if (c.f & 0x10) == 0 {
            c.pc = addr
        } else {
            condition_taken = false
        }
    // 0xD3 illegal
    case 0xD4:  // CALL NC,nn
        addr := fetch16(gb)
        if (c.f & 0x10) == 0 {
            push16(gb, c.pc)
            c.pc = addr
        } else {
            condition_taken = false
        }
    case 0xD5: push16(gb, cpu.get_de(c))  // PUSH DE
    case 0xD6: cpu.sub_a(c, fetch8(gb), false)  // SUB n
    case 0xD7: push16(gb, c.pc); c.pc = 0x10  // RST 10
    case 0xD8:  // RET C
        if (c.f & 0x10) != 0 {
            c.pc = pop16(gb)
        } else {
            condition_taken = false
        }
    case 0xD9: c.pc = pop16(gb); c.ime = true  // RETI
    case 0xDA:  // JP C,nn
        addr := fetch16(gb)
        if (c.f & 0x10) != 0 {
            c.pc = addr
        } else {
            condition_taken = false
        }
    // 0xDB illegal
    case 0xDC:  // CALL C,nn
        addr := fetch16(gb)
        if (c.f & 0x10) != 0 {
            push16(gb, c.pc)
            c.pc = addr
        } else {
            condition_taken = false
        }
    // 0xDD illegal
    case 0xDE: cpu.sub_a(c, fetch8(gb), true)  // SBC A,n
    case 0xDF: push16(gb, c.pc); c.pc = 0x18  // RST 18
    case 0xE0: write8(gb, 0xFF00 + u16(fetch8(gb)), c.a)  // LD (FF00+n),A
    case 0xE1: cpu.set_hl(c, pop16(gb))  // POP HL
    case 0xE2: write8(gb, 0xFF00 + u16(c.c), c.a)  // LD (FF00+C),A
    // 0xE3, 0xE4 illegal
    case 0xE5: push16(gb, cpu.get_hl(c))  // PUSH HL
    case 0xE6: cpu.and_a(c, fetch8(gb))  // AND n
    case 0xE7: push16(gb, c.pc); c.pc = 0x20  // RST 20
    case 0xE8:  // ADD SP,n
        offset := i8(fetch8(gb))
        result := u16(i32(c.sp) + i32(offset))
        c.f = 0
        if ((c.sp & 0x0F) + (u16(u8(offset)) & 0x0F)) > 0x0F { c.f |= 0x20 }
        if ((c.sp & 0xFF) + u16(u8(offset))) > 0xFF { c.f |= 0x10 }
        c.sp = result
    case 0xE9: c.pc = cpu.get_hl(c)  // JP HL
    case 0xEA: write8(gb, fetch16(gb), c.a)  // LD (nn),A
    // 0xEB, 0xEC, 0xED illegal
    case 0xEE: cpu.xor_a(c, fetch8(gb))  // XOR n
    case 0xEF: push16(gb, c.pc); c.pc = 0x28  // RST 28
    case 0xF0: c.a = read8(gb, 0xFF00 + u16(fetch8(gb)))  // LD A,(FF00+n)
    case 0xF1:  // POP AF
        val := pop16(gb)
        c.a = u8(val >> 8)
        c.f = u8(val) & 0xF0
    case 0xF2: c.a = read8(gb, 0xFF00 + u16(c.c))  // LD A,(FF00+C)
    case 0xF3: c.ime = false  // DI
    // 0xF4 illegal
    case 0xF5: push16(gb, (u16(c.a) << 8) | u16(c.f))  // PUSH AF
    case 0xF6: cpu.or_a(c, fetch8(gb))  // OR n
    case 0xF7: push16(gb, c.pc); c.pc = 0x30  // RST 30
    case 0xF8:  // LD HL,SP+n
        offset := i8(fetch8(gb))
        result := u16(i32(c.sp) + i32(offset))
        c.f = 0
        if ((c.sp & 0x0F) + (u16(u8(offset)) & 0x0F)) > 0x0F { c.f |= 0x20 }
        if ((c.sp & 0xFF) + u16(u8(offset))) > 0xFF { c.f |= 0x10 }
        cpu.set_hl(c, result)
    case 0xF9: c.sp = cpu.get_hl(c)  // LD SP,HL
    case 0xFA: c.a = read8(gb, fetch16(gb))  // LD A,(nn)
    case 0xFB: c.ime_scheduled = true  // EI
    // 0xFC, 0xFD illegal
    case 0xFE: cpu.cp_a(c, fetch8(gb))  // CP n
    case 0xFF: push16(gb, c.pc); c.pc = 0x38  // RST 38

    case:  // Illegal - NOP
    }

    // Return cycles from opcode table
    // For conditional instructions, use alt_cycles when condition not taken
    if !condition_taken && info.alt_cycles != 0 {
        return info.alt_cycles
    }
    return info.cycles
}

// CB-prefix helpers
@(private)
rlc :: proc(c: ^cpu.CPU, val: u8) -> u8 {
    carry := (val & 0x80) != 0
    result := (val << 1) | (val >> 7)
    c.f = 0
    if result == 0 { c.f |= 0x80 }
    if carry { c.f |= 0x10 }
    return result
}

@(private)
rrc :: proc(c: ^cpu.CPU, val: u8) -> u8 {
    carry := (val & 0x01) != 0
    result := (val >> 1) | (val << 7)
    c.f = 0
    if result == 0 { c.f |= 0x80 }
    if carry { c.f |= 0x10 }
    return result
}

@(private)
rl :: proc(c: ^cpu.CPU, val: u8) -> u8 {
    old_carry := (c.f & 0x10) != 0
    new_carry := (val & 0x80) != 0
    result := (val << 1) | (old_carry ? 1 : 0)
    c.f = 0
    if result == 0 { c.f |= 0x80 }
    if new_carry { c.f |= 0x10 }
    return result
}

@(private)
rr :: proc(c: ^cpu.CPU, val: u8) -> u8 {
    old_carry := (c.f & 0x10) != 0
    new_carry := (val & 0x01) != 0
    result := (val >> 1) | (old_carry ? 0x80 : 0)
    c.f = 0
    if result == 0 { c.f |= 0x80 }
    if new_carry { c.f |= 0x10 }
    return result
}

@(private)
sla :: proc(c: ^cpu.CPU, val: u8) -> u8 {
    carry := (val & 0x80) != 0
    result := val << 1
    c.f = 0
    if result == 0 { c.f |= 0x80 }
    if carry { c.f |= 0x10 }
    return result
}

@(private)
sra :: proc(c: ^cpu.CPU, val: u8) -> u8 {
    carry := (val & 0x01) != 0
    result := (val >> 1) | (val & 0x80)
    c.f = 0
    if result == 0 { c.f |= 0x80 }
    if carry { c.f |= 0x10 }
    return result
}

@(private)
swap_op :: proc(c: ^cpu.CPU, val: u8) -> u8 {
    result := ((val & 0x0F) << 4) | ((val & 0xF0) >> 4)
    c.f = 0
    if result == 0 { c.f |= 0x80 }
    return result
}

@(private)
srl :: proc(c: ^cpu.CPU, val: u8) -> u8 {
    carry := (val & 0x01) != 0
    result := val >> 1
    c.f = 0
    if result == 0 { c.f |= 0x80 }
    if carry { c.f |= 0x10 }
    return result
}

@(private)
bit_op :: proc(c: ^cpu.CPU, val: u8, bit: u8) {
    c.f = (c.f & 0x10) | 0x20  // Keep C, set H
    if (val & (1 << bit)) == 0 { c.f |= 0x80 }  // Z
}

// Get register by index for CB ops
@(private)
get_reg :: proc(gb: ^GameBoy, idx: u8) -> u8 {
    c := &gb.cpu
    switch idx {
    case 0: return c.b
    case 1: return c.c
    case 2: return c.d
    case 3: return c.e
    case 4: return c.h
    case 5: return c.l
    case 6: return read8(gb, cpu.get_hl(c))
    case 7: return c.a
    }
    return 0
}

// Set register by index for CB ops
@(private)
set_reg :: proc(gb: ^GameBoy, idx: u8, val: u8) {
    c := &gb.cpu
    switch idx {
    case 0: c.b = val
    case 1: c.c = val
    case 2: c.d = val
    case 3: c.e = val
    case 4: c.h = val
    case 5: c.l = val
    case 6: write8(gb, cpu.get_hl(c), val)
    case 7: c.a = val
    }
}

// Execute CB-prefixed opcode - uses CB opcode table for cycle timing
execute_cb :: proc(gb: ^GameBoy, opcode: u8) -> u8 {
    c := &gb.cpu
    info := &cpu.CB_OPCODES[opcode]
    reg_idx := opcode & 0x07

    val := get_reg(gb, reg_idx)

    switch opcode >> 3 {
    case 0x00: val = rlc(c, val)  // RLC
    case 0x01: val = rrc(c, val)  // RRC
    case 0x02: val = rl(c, val)   // RL
    case 0x03: val = rr(c, val)   // RR
    case 0x04: val = sla(c, val)  // SLA
    case 0x05: val = sra(c, val)  // SRA
    case 0x06: val = swap_op(c, val)  // SWAP
    case 0x07: val = srl(c, val)  // SRL
    case 0x08..=0x0F:  // BIT 0-7
        bit_op(c, val, (opcode >> 3) & 0x07)
        return info.cycles  // BIT doesn't write back
    case 0x10..=0x17:  // RES 0-7
        val &= ~(1 << ((opcode >> 3) & 0x07))
    case 0x18..=0x1F:  // SET 0-7
        val |= (1 << ((opcode >> 3) & 0x07))
    }

    set_reg(gb, reg_idx, val)
    return info.cycles
}

// Get framebuffer pointer
get_framebuffer :: proc(gb: ^GameBoy) -> ^[SCREEN_HEIGHT][SCREEN_WIDTH]u16 {
    return &gb.ppu.framebuffer
}

// Update joypad input
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

    title_bytes: [16]u8
    for i in 0 ..< 16 {
        if rom[0x134 + i] == 0 {
            break
        }
        title_bytes[i] = rom[0x134 + i]
    }

    return string(title_bytes[:])
}
