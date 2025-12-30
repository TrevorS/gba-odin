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

// Register pair helpers
@(private)
get_hl :: #force_inline proc(c: ^cpu.CPU) -> u16 {
    return (u16(c.h) << 8) | u16(c.l)
}

@(private)
set_hl :: #force_inline proc(c: ^cpu.CPU, val: u16) {
    c.h = u8(val >> 8)
    c.l = u8(val)
}

@(private)
get_bc :: #force_inline proc(c: ^cpu.CPU) -> u16 {
    return (u16(c.b) << 8) | u16(c.c)
}

@(private)
set_bc :: #force_inline proc(c: ^cpu.CPU, val: u16) {
    c.b = u8(val >> 8)
    c.c = u8(val)
}

@(private)
get_de :: #force_inline proc(c: ^cpu.CPU) -> u16 {
    return (u16(c.d) << 8) | u16(c.e)
}

@(private)
set_de :: #force_inline proc(c: ^cpu.CPU, val: u16) {
    c.d = u8(val >> 8)
    c.e = u8(val)
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

// Handle interrupts directly using bus (avoids callback issues)
@(private)
handle_interrupts_direct :: proc(gb: ^GameBoy) -> bool {
    c := &gb.cpu
    b := &gb.bus

    if !c.ime {
        // Even with IME=0, interrupts can wake from HALT
        if c.halted && (b.ie & b.if_) != 0 {
            c.halted = false
        }
        return false
    }

    pending := b.ie & b.if_
    if pending == 0 {
        return false
    }

    // Service highest priority interrupt
    interrupt_bit: u8
    vector: u16

    if (pending & 0x01) != 0 {
        interrupt_bit = 0x01
        vector = 0x0040  // VBlank
    } else if (pending & 0x02) != 0 {
        interrupt_bit = 0x02
        vector = 0x0048  // LCD STAT
    } else if (pending & 0x04) != 0 {
        interrupt_bit = 0x04
        vector = 0x0050  // Timer
    } else if (pending & 0x08) != 0 {
        interrupt_bit = 0x08
        vector = 0x0058  // Serial
    } else if (pending & 0x10) != 0 {
        interrupt_bit = 0x10
        vector = 0x0060  // Joypad
    } else {
        return false
    }

    // Disable interrupts and jump to vector
    c.ime = false
    c.halted = false
    push16(gb, c.pc)
    c.pc = vector

    // Clear interrupt flag
    b.if_ &= ~interrupt_bit
    return true
}

// ALU helpers
@(private)
inc8 :: proc(c: ^cpu.CPU, val: u8) -> u8 {
    result := val + 1
    c.f = (c.f & 0x10)  // Keep C
    if result == 0 { c.f |= 0x80 }  // Z
    if (val & 0x0F) == 0x0F { c.f |= 0x20 }  // H
    return result
}

@(private)
dec8 :: proc(c: ^cpu.CPU, val: u8) -> u8 {
    result := val - 1
    c.f = (c.f & 0x10) | 0x40  // Keep C, set N
    if result == 0 { c.f |= 0x80 }  // Z
    if (val & 0x0F) == 0 { c.f |= 0x20 }  // H
    return result
}

@(private)
add_a :: proc(c: ^cpu.CPU, val: u8, with_carry: bool) {
    carry: u8 = 0
    if with_carry && (c.f & 0x10) != 0 { carry = 1 }

    result := u16(c.a) + u16(val) + u16(carry)
    half := (c.a & 0x0F) + (val & 0x0F) + carry

    c.f = 0
    if u8(result) == 0 { c.f |= 0x80 }  // Z
    if half > 0x0F { c.f |= 0x20 }  // H
    if result > 0xFF { c.f |= 0x10 }  // C

    c.a = u8(result)
}

@(private)
sub_a :: proc(c: ^cpu.CPU, val: u8, with_carry: bool) {
    carry: u8 = 0
    if with_carry && (c.f & 0x10) != 0 { carry = 1 }

    result := i16(c.a) - i16(val) - i16(carry)
    half := i16(c.a & 0x0F) - i16(val & 0x0F) - i16(carry)

    c.f = 0x40  // N
    if u8(result) == 0 { c.f |= 0x80 }  // Z
    if half < 0 { c.f |= 0x20 }  // H
    if result < 0 { c.f |= 0x10 }  // C

    c.a = u8(result)
}

@(private)
and_a :: proc(c: ^cpu.CPU, val: u8) {
    c.a &= val
    c.f = 0x20  // H
    if c.a == 0 { c.f |= 0x80 }  // Z
}

@(private)
xor_a :: proc(c: ^cpu.CPU, val: u8) {
    c.a ~= val
    c.f = 0
    if c.a == 0 { c.f |= 0x80 }  // Z
}

@(private)
or_a :: proc(c: ^cpu.CPU, val: u8) {
    c.a |= val
    c.f = 0
    if c.a == 0 { c.f |= 0x80 }  // Z
}

@(private)
cp_a :: proc(c: ^cpu.CPU, val: u8) {
    result := i16(c.a) - i16(val)
    half := i16(c.a & 0x0F) - i16(val & 0x0F)

    c.f = 0x40  // N
    if u8(result) == 0 { c.f |= 0x80 }  // Z
    if half < 0 { c.f |= 0x20 }  // H
    if result < 0 { c.f |= 0x10 }  // C
}

@(private)
add_hl :: proc(c: ^cpu.CPU, val: u16) {
    hl := get_hl(c)
    result := u32(hl) + u32(val)

    c.f &= 0x80  // Keep Z
    if ((hl & 0x0FFF) + (val & 0x0FFF)) > 0x0FFF { c.f |= 0x20 }  // H
    if result > 0xFFFF { c.f |= 0x10 }  // C

    set_hl(c, u16(result))
}

@(private)
daa :: proc(c: ^cpu.CPU) {
    a := c.a
    correction: u8 = 0

    if (c.f & 0x20) != 0 || ((c.f & 0x40) == 0 && (a & 0x0F) > 9) {
        correction |= 0x06
    }

    if (c.f & 0x10) != 0 || ((c.f & 0x40) == 0 && a > 0x99) {
        correction |= 0x60
        c.f |= 0x10  // C
    }

    if (c.f & 0x40) != 0 {
        a -= correction
    } else {
        a += correction
    }

    c.a = a
    c.f &= 0x50  // Keep N, C
    if a == 0 { c.f |= 0x80 }  // Z
}

// Execute main opcode
execute :: proc(gb: ^GameBoy, opcode: u8) -> u8 {
    c := &gb.cpu

    // CB prefix
    if opcode == 0xCB {
        return execute_cb(gb, fetch8(gb))
    }

    switch opcode {
    // 0x00-0x0F
    case 0x00: return 4  // NOP
    case 0x01: set_bc(c, fetch16(gb)); return 12  // LD BC,nn
    case 0x02: write8(gb, get_bc(c), c.a); return 8  // LD (BC),A
    case 0x03: set_bc(c, get_bc(c) + 1); return 8  // INC BC
    case 0x04: c.b = inc8(c, c.b); return 4  // INC B
    case 0x05: c.b = dec8(c, c.b); return 4  // DEC B
    case 0x06: c.b = fetch8(gb); return 8  // LD B,n
    case 0x07:  // RLCA
        carry := (c.a & 0x80) != 0
        c.a = (c.a << 1) | (c.a >> 7)
        c.f = carry ? 0x10 : 0
        return 4
    case 0x08:  // LD (nn),SP
        addr := fetch16(gb)
        write8(gb, addr, u8(c.sp))
        write8(gb, addr + 1, u8(c.sp >> 8))
        return 20
    case 0x09: add_hl(c, get_bc(c)); return 8  // ADD HL,BC
    case 0x0A: c.a = read8(gb, get_bc(c)); return 8  // LD A,(BC)
    case 0x0B: set_bc(c, get_bc(c) - 1); return 8  // DEC BC
    case 0x0C: c.c = inc8(c, c.c); return 4  // INC C
    case 0x0D: c.c = dec8(c, c.c); return 4  // DEC C
    case 0x0E: c.c = fetch8(gb); return 8  // LD C,n
    case 0x0F:  // RRCA
        carry := (c.a & 0x01) != 0
        c.a = (c.a >> 1) | (c.a << 7)
        c.f = carry ? 0x10 : 0
        return 4

    // 0x10-0x1F
    case 0x10: fetch8(gb); c.stopped = true; return 4  // STOP
    case 0x11: set_de(c, fetch16(gb)); return 12  // LD DE,nn
    case 0x12: write8(gb, get_de(c), c.a); return 8  // LD (DE),A
    case 0x13: set_de(c, get_de(c) + 1); return 8  // INC DE
    case 0x14: c.d = inc8(c, c.d); return 4  // INC D
    case 0x15: c.d = dec8(c, c.d); return 4  // DEC D
    case 0x16: c.d = fetch8(gb); return 8  // LD D,n
    case 0x17:  // RLA
        old_carry := (c.f & 0x10) != 0
        new_carry := (c.a & 0x80) != 0
        c.a = (c.a << 1) | (old_carry ? 1 : 0)
        c.f = new_carry ? 0x10 : 0
        return 4
    case 0x18:  // JR n
        offset := i8(fetch8(gb))
        c.pc = u16(i32(c.pc) + i32(offset))
        return 12
    case 0x19: add_hl(c, get_de(c)); return 8  // ADD HL,DE
    case 0x1A: c.a = read8(gb, get_de(c)); return 8  // LD A,(DE)
    case 0x1B: set_de(c, get_de(c) - 1); return 8  // DEC DE
    case 0x1C: c.e = inc8(c, c.e); return 4  // INC E
    case 0x1D: c.e = dec8(c, c.e); return 4  // DEC E
    case 0x1E: c.e = fetch8(gb); return 8  // LD E,n
    case 0x1F:  // RRA
        old_carry := (c.f & 0x10) != 0
        new_carry := (c.a & 0x01) != 0
        c.a = (c.a >> 1) | (old_carry ? 0x80 : 0)
        c.f = new_carry ? 0x10 : 0
        return 4

    // 0x20-0x2F
    case 0x20:  // JR NZ,n
        offset := i8(fetch8(gb))
        if (c.f & 0x80) == 0 {
            c.pc = u16(i32(c.pc) + i32(offset))
            return 12
        }
        return 8
    case 0x21: set_hl(c, fetch16(gb)); return 12  // LD HL,nn
    case 0x22: write8(gb, get_hl(c), c.a); set_hl(c, get_hl(c) + 1); return 8  // LD (HL+),A
    case 0x23: set_hl(c, get_hl(c) + 1); return 8  // INC HL
    case 0x24: c.h = inc8(c, c.h); return 4  // INC H
    case 0x25: c.h = dec8(c, c.h); return 4  // DEC H
    case 0x26: c.h = fetch8(gb); return 8  // LD H,n
    case 0x27: daa(c); return 4  // DAA
    case 0x28:  // JR Z,n
        offset := i8(fetch8(gb))
        if (c.f & 0x80) != 0 {
            c.pc = u16(i32(c.pc) + i32(offset))
            return 12
        }
        return 8
    case 0x29: add_hl(c, get_hl(c)); return 8  // ADD HL,HL
    case 0x2A: c.a = read8(gb, get_hl(c)); set_hl(c, get_hl(c) + 1); return 8  // LD A,(HL+)
    case 0x2B: set_hl(c, get_hl(c) - 1); return 8  // DEC HL
    case 0x2C: c.l = inc8(c, c.l); return 4  // INC L
    case 0x2D: c.l = dec8(c, c.l); return 4  // DEC L
    case 0x2E: c.l = fetch8(gb); return 8  // LD L,n
    case 0x2F: c.a = ~c.a; c.f |= 0x60; return 4  // CPL

    // 0x30-0x3F
    case 0x30:  // JR NC,n
        offset := i8(fetch8(gb))
        if (c.f & 0x10) == 0 {
            c.pc = u16(i32(c.pc) + i32(offset))
            return 12
        }
        return 8
    case 0x31: c.sp = fetch16(gb); return 12  // LD SP,nn
    case 0x32: write8(gb, get_hl(c), c.a); set_hl(c, get_hl(c) - 1); return 8  // LD (HL-),A
    case 0x33: c.sp += 1; return 8  // INC SP
    case 0x34: write8(gb, get_hl(c), inc8(c, read8(gb, get_hl(c)))); return 12  // INC (HL)
    case 0x35: write8(gb, get_hl(c), dec8(c, read8(gb, get_hl(c)))); return 12  // DEC (HL)
    case 0x36: write8(gb, get_hl(c), fetch8(gb)); return 12  // LD (HL),n
    case 0x37: c.f = (c.f & 0x80) | 0x10; return 4  // SCF
    case 0x38:  // JR C,n
        offset := i8(fetch8(gb))
        if (c.f & 0x10) != 0 {
            c.pc = u16(i32(c.pc) + i32(offset))
            return 12
        }
        return 8
    case 0x39: add_hl(c, c.sp); return 8  // ADD HL,SP
    case 0x3A: c.a = read8(gb, get_hl(c)); set_hl(c, get_hl(c) - 1); return 8  // LD A,(HL-)
    case 0x3B: c.sp -= 1; return 8  // DEC SP
    case 0x3C: c.a = inc8(c, c.a); return 4  // INC A
    case 0x3D: c.a = dec8(c, c.a); return 4  // DEC A
    case 0x3E: c.a = fetch8(gb); return 8  // LD A,n
    case 0x3F: c.f = (c.f & 0x90) ~ 0x10; return 4  // CCF - toggle C, clear N/H, keep Z

    // 0x40-0x7F: LD r,r' and HALT
    case 0x40: return 4  // LD B,B
    case 0x41: c.b = c.c; return 4
    case 0x42: c.b = c.d; return 4
    case 0x43: c.b = c.e; return 4
    case 0x44: c.b = c.h; return 4
    case 0x45: c.b = c.l; return 4
    case 0x46: c.b = read8(gb, get_hl(c)); return 8
    case 0x47: c.b = c.a; return 4
    case 0x48: c.c = c.b; return 4
    case 0x49: return 4  // LD C,C
    case 0x4A: c.c = c.d; return 4
    case 0x4B: c.c = c.e; return 4
    case 0x4C: c.c = c.h; return 4
    case 0x4D: c.c = c.l; return 4
    case 0x4E: c.c = read8(gb, get_hl(c)); return 8
    case 0x4F: c.c = c.a; return 4
    case 0x50: c.d = c.b; return 4
    case 0x51: c.d = c.c; return 4
    case 0x52: return 4  // LD D,D
    case 0x53: c.d = c.e; return 4
    case 0x54: c.d = c.h; return 4
    case 0x55: c.d = c.l; return 4
    case 0x56: c.d = read8(gb, get_hl(c)); return 8
    case 0x57: c.d = c.a; return 4
    case 0x58: c.e = c.b; return 4
    case 0x59: c.e = c.c; return 4
    case 0x5A: c.e = c.d; return 4
    case 0x5B: return 4  // LD E,E
    case 0x5C: c.e = c.h; return 4
    case 0x5D: c.e = c.l; return 4
    case 0x5E: c.e = read8(gb, get_hl(c)); return 8
    case 0x5F: c.e = c.a; return 4
    case 0x60: c.h = c.b; return 4
    case 0x61: c.h = c.c; return 4
    case 0x62: c.h = c.d; return 4
    case 0x63: c.h = c.e; return 4
    case 0x64: return 4  // LD H,H
    case 0x65: c.h = c.l; return 4
    case 0x66: c.h = read8(gb, get_hl(c)); return 8
    case 0x67: c.h = c.a; return 4
    case 0x68: c.l = c.b; return 4
    case 0x69: c.l = c.c; return 4
    case 0x6A: c.l = c.d; return 4
    case 0x6B: c.l = c.e; return 4
    case 0x6C: c.l = c.h; return 4
    case 0x6D: return 4  // LD L,L
    case 0x6E: c.l = read8(gb, get_hl(c)); return 8
    case 0x6F: c.l = c.a; return 4
    case 0x70: write8(gb, get_hl(c), c.b); return 8
    case 0x71: write8(gb, get_hl(c), c.c); return 8
    case 0x72: write8(gb, get_hl(c), c.d); return 8
    case 0x73: write8(gb, get_hl(c), c.e); return 8
    case 0x74: write8(gb, get_hl(c), c.h); return 8
    case 0x75: write8(gb, get_hl(c), c.l); return 8
    case 0x76: c.halted = true; return 4  // HALT
    case 0x77: write8(gb, get_hl(c), c.a); return 8
    case 0x78: c.a = c.b; return 4
    case 0x79: c.a = c.c; return 4
    case 0x7A: c.a = c.d; return 4
    case 0x7B: c.a = c.e; return 4
    case 0x7C: c.a = c.h; return 4
    case 0x7D: c.a = c.l; return 4
    case 0x7E: c.a = read8(gb, get_hl(c)); return 8
    case 0x7F: return 4  // LD A,A

    // 0x80-0xBF: ALU operations
    case 0x80: add_a(c, c.b, false); return 4
    case 0x81: add_a(c, c.c, false); return 4
    case 0x82: add_a(c, c.d, false); return 4
    case 0x83: add_a(c, c.e, false); return 4
    case 0x84: add_a(c, c.h, false); return 4
    case 0x85: add_a(c, c.l, false); return 4
    case 0x86: add_a(c, read8(gb, get_hl(c)), false); return 8
    case 0x87: add_a(c, c.a, false); return 4
    case 0x88: add_a(c, c.b, true); return 4
    case 0x89: add_a(c, c.c, true); return 4
    case 0x8A: add_a(c, c.d, true); return 4
    case 0x8B: add_a(c, c.e, true); return 4
    case 0x8C: add_a(c, c.h, true); return 4
    case 0x8D: add_a(c, c.l, true); return 4
    case 0x8E: add_a(c, read8(gb, get_hl(c)), true); return 8
    case 0x8F: add_a(c, c.a, true); return 4
    case 0x90: sub_a(c, c.b, false); return 4
    case 0x91: sub_a(c, c.c, false); return 4
    case 0x92: sub_a(c, c.d, false); return 4
    case 0x93: sub_a(c, c.e, false); return 4
    case 0x94: sub_a(c, c.h, false); return 4
    case 0x95: sub_a(c, c.l, false); return 4
    case 0x96: sub_a(c, read8(gb, get_hl(c)), false); return 8
    case 0x97: sub_a(c, c.a, false); return 4
    case 0x98: sub_a(c, c.b, true); return 4
    case 0x99: sub_a(c, c.c, true); return 4
    case 0x9A: sub_a(c, c.d, true); return 4
    case 0x9B: sub_a(c, c.e, true); return 4
    case 0x9C: sub_a(c, c.h, true); return 4
    case 0x9D: sub_a(c, c.l, true); return 4
    case 0x9E: sub_a(c, read8(gb, get_hl(c)), true); return 8
    case 0x9F: sub_a(c, c.a, true); return 4
    case 0xA0: and_a(c, c.b); return 4
    case 0xA1: and_a(c, c.c); return 4
    case 0xA2: and_a(c, c.d); return 4
    case 0xA3: and_a(c, c.e); return 4
    case 0xA4: and_a(c, c.h); return 4
    case 0xA5: and_a(c, c.l); return 4
    case 0xA6: and_a(c, read8(gb, get_hl(c))); return 8
    case 0xA7: and_a(c, c.a); return 4
    case 0xA8: xor_a(c, c.b); return 4
    case 0xA9: xor_a(c, c.c); return 4
    case 0xAA: xor_a(c, c.d); return 4
    case 0xAB: xor_a(c, c.e); return 4
    case 0xAC: xor_a(c, c.h); return 4
    case 0xAD: xor_a(c, c.l); return 4
    case 0xAE: xor_a(c, read8(gb, get_hl(c))); return 8
    case 0xAF: xor_a(c, c.a); return 4
    case 0xB0: or_a(c, c.b); return 4
    case 0xB1: or_a(c, c.c); return 4
    case 0xB2: or_a(c, c.d); return 4
    case 0xB3: or_a(c, c.e); return 4
    case 0xB4: or_a(c, c.h); return 4
    case 0xB5: or_a(c, c.l); return 4
    case 0xB6: or_a(c, read8(gb, get_hl(c))); return 8
    case 0xB7: or_a(c, c.a); return 4
    case 0xB8: cp_a(c, c.b); return 4
    case 0xB9: cp_a(c, c.c); return 4
    case 0xBA: cp_a(c, c.d); return 4
    case 0xBB: cp_a(c, c.e); return 4
    case 0xBC: cp_a(c, c.h); return 4
    case 0xBD: cp_a(c, c.l); return 4
    case 0xBE: cp_a(c, read8(gb, get_hl(c))); return 8
    case 0xBF: cp_a(c, c.a); return 4

    // 0xC0-0xFF: Control, stack, misc
    case 0xC0:  // RET NZ
        if (c.f & 0x80) == 0 { c.pc = pop16(gb); return 20 }
        return 8
    case 0xC1: set_bc(c, pop16(gb)); return 12  // POP BC
    case 0xC2:  // JP NZ,nn
        addr := fetch16(gb)
        if (c.f & 0x80) == 0 { c.pc = addr; return 16 }
        return 12
    case 0xC3: c.pc = fetch16(gb); return 16  // JP nn
    case 0xC4:  // CALL NZ,nn
        addr := fetch16(gb)
        if (c.f & 0x80) == 0 { push16(gb, c.pc); c.pc = addr; return 24 }
        return 12
    case 0xC5: push16(gb, get_bc(c)); return 16  // PUSH BC
    case 0xC6: add_a(c, fetch8(gb), false); return 8  // ADD A,n
    case 0xC7: push16(gb, c.pc); c.pc = 0x00; return 16  // RST 00
    case 0xC8:  // RET Z
        if (c.f & 0x80) != 0 { c.pc = pop16(gb); return 20 }
        return 8
    case 0xC9: c.pc = pop16(gb); return 16  // RET
    case 0xCA:  // JP Z,nn
        addr := fetch16(gb)
        if (c.f & 0x80) != 0 { c.pc = addr; return 16 }
        return 12
    // 0xCB is handled at start
    case 0xCC:  // CALL Z,nn
        addr := fetch16(gb)
        if (c.f & 0x80) != 0 { push16(gb, c.pc); c.pc = addr; return 24 }
        return 12
    case 0xCD:  // CALL nn
        addr := fetch16(gb)
        push16(gb, c.pc)
        c.pc = addr
        return 24
    case 0xCE: add_a(c, fetch8(gb), true); return 8  // ADC A,n
    case 0xCF: push16(gb, c.pc); c.pc = 0x08; return 16  // RST 08
    case 0xD0:  // RET NC
        if (c.f & 0x10) == 0 { c.pc = pop16(gb); return 20 }
        return 8
    case 0xD1: set_de(c, pop16(gb)); return 12  // POP DE
    case 0xD2:  // JP NC,nn
        addr := fetch16(gb)
        if (c.f & 0x10) == 0 { c.pc = addr; return 16 }
        return 12
    // 0xD3 illegal
    case 0xD4:  // CALL NC,nn
        addr := fetch16(gb)
        if (c.f & 0x10) == 0 { push16(gb, c.pc); c.pc = addr; return 24 }
        return 12
    case 0xD5: push16(gb, get_de(c)); return 16  // PUSH DE
    case 0xD6: sub_a(c, fetch8(gb), false); return 8  // SUB n
    case 0xD7: push16(gb, c.pc); c.pc = 0x10; return 16  // RST 10
    case 0xD8:  // RET C
        if (c.f & 0x10) != 0 { c.pc = pop16(gb); return 20 }
        return 8
    case 0xD9: c.pc = pop16(gb); c.ime = true; return 16  // RETI
    case 0xDA:  // JP C,nn
        addr := fetch16(gb)
        if (c.f & 0x10) != 0 { c.pc = addr; return 16 }
        return 12
    // 0xDB illegal
    case 0xDC:  // CALL C,nn
        addr := fetch16(gb)
        if (c.f & 0x10) != 0 { push16(gb, c.pc); c.pc = addr; return 24 }
        return 12
    // 0xDD illegal
    case 0xDE: sub_a(c, fetch8(gb), true); return 8  // SBC A,n
    case 0xDF: push16(gb, c.pc); c.pc = 0x18; return 16  // RST 18
    case 0xE0: write8(gb, 0xFF00 + u16(fetch8(gb)), c.a); return 12  // LD (FF00+n),A
    case 0xE1: set_hl(c, pop16(gb)); return 12  // POP HL
    case 0xE2: write8(gb, 0xFF00 + u16(c.c), c.a); return 8  // LD (FF00+C),A
    // 0xE3, 0xE4 illegal
    case 0xE5: push16(gb, get_hl(c)); return 16  // PUSH HL
    case 0xE6: and_a(c, fetch8(gb)); return 8  // AND n
    case 0xE7: push16(gb, c.pc); c.pc = 0x20; return 16  // RST 20
    case 0xE8:  // ADD SP,n
        offset := i8(fetch8(gb))
        result := u16(i32(c.sp) + i32(offset))
        c.f = 0
        if ((c.sp & 0x0F) + (u16(u8(offset)) & 0x0F)) > 0x0F { c.f |= 0x20 }
        if ((c.sp & 0xFF) + u16(u8(offset))) > 0xFF { c.f |= 0x10 }
        c.sp = result
        return 16
    case 0xE9: c.pc = get_hl(c); return 4  // JP HL
    case 0xEA: write8(gb, fetch16(gb), c.a); return 16  // LD (nn),A
    // 0xEB, 0xEC, 0xED illegal
    case 0xEE: xor_a(c, fetch8(gb)); return 8  // XOR n
    case 0xEF: push16(gb, c.pc); c.pc = 0x28; return 16  // RST 28
    case 0xF0: c.a = read8(gb, 0xFF00 + u16(fetch8(gb))); return 12  // LD A,(FF00+n)
    case 0xF1:  // POP AF
        val := pop16(gb)
        c.a = u8(val >> 8)
        c.f = u8(val) & 0xF0
        return 12
    case 0xF2: c.a = read8(gb, 0xFF00 + u16(c.c)); return 8  // LD A,(FF00+C)
    case 0xF3: c.ime = false; return 4  // DI
    // 0xF4 illegal
    case 0xF5: push16(gb, (u16(c.a) << 8) | u16(c.f)); return 16  // PUSH AF
    case 0xF6: or_a(c, fetch8(gb)); return 8  // OR n
    case 0xF7: push16(gb, c.pc); c.pc = 0x30; return 16  // RST 30
    case 0xF8:  // LD HL,SP+n
        offset := i8(fetch8(gb))
        result := u16(i32(c.sp) + i32(offset))
        c.f = 0
        if ((c.sp & 0x0F) + (u16(u8(offset)) & 0x0F)) > 0x0F { c.f |= 0x20 }
        if ((c.sp & 0xFF) + u16(u8(offset))) > 0xFF { c.f |= 0x10 }
        set_hl(c, result)
        return 12
    case 0xF9: c.sp = get_hl(c); return 8  // LD SP,HL
    case 0xFA: c.a = read8(gb, fetch16(gb)); return 16  // LD A,(nn)
    case 0xFB: c.ime_scheduled = true; return 4  // EI
    // 0xFC, 0xFD illegal
    case 0xFE: cp_a(c, fetch8(gb)); return 8  // CP n
    case 0xFF: push16(gb, c.pc); c.pc = 0x38; return 16  // RST 38

    case: return 4  // Illegal - NOP
    }
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
    case 6: return read8(gb, get_hl(c))
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
    case 6: write8(gb, get_hl(c), val)
    case 7: c.a = val
    }
}

// Execute CB-prefixed opcode
execute_cb :: proc(gb: ^GameBoy, opcode: u8) -> u8 {
    c := &gb.cpu
    reg_idx := opcode & 0x07
    is_hl := reg_idx == 6
    cycles: u8 = is_hl ? 16 : 8

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
        return is_hl ? 12 : 8  // BIT doesn't write back
    case 0x10..=0x17:  // RES 0-7
        val &= ~(1 << ((opcode >> 3) & 0x07))
    case 0x18..=0x1F:  // SET 0-7
        val |= (1 << ((opcode >> 3) & 0x07))
    }

    set_reg(gb, reg_idx, val)
    return cycles
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
