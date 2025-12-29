package gb_cpu

// LR35902 instruction execution
// Opcodes are organized into blocks for easier implementation

// Main opcode execution - returns cycles consumed
execute :: proc(cpu: ^CPU, opcode: u8) -> u8 {
    // CB-prefixed instructions
    if opcode == 0xCB {
        cb_opcode := fetch8(cpu)
        return execute_cb(cpu, cb_opcode)
    }

    // Decode by opcode block
    switch opcode {
    // ============ 0x00-0x3F: Misc, loads, inc/dec, rotates ============

    case 0x00: // NOP
        return 4

    case 0x01: // LD BC, nn
        set_bc(cpu, fetch16(cpu))
        return 12

    case 0x02: // LD (BC), A
        write8(cpu, get_bc(cpu), cpu.a)
        return 8

    case 0x03: // INC BC
        set_bc(cpu, get_bc(cpu) + 1)
        return 8

    case 0x04: // INC B
        cpu.b = inc8(cpu, cpu.b)
        return 4

    case 0x05: // DEC B
        cpu.b = dec8(cpu, cpu.b)
        return 4

    case 0x06: // LD B, n
        cpu.b = fetch8(cpu)
        return 8

    case 0x07: // RLCA
        carry := (cpu.a & 0x80) != 0
        cpu.a = (cpu.a << 1) | (cpu.a >> 7)
        set_flags(cpu, false, false, false, carry)
        return 4

    case 0x08: // LD (nn), SP
        write16(cpu, fetch16(cpu), cpu.sp)
        return 20

    case 0x09: // ADD HL, BC
        add_hl(cpu, get_bc(cpu))
        return 8

    case 0x0A: // LD A, (BC)
        cpu.a = read8(cpu, get_bc(cpu))
        return 8

    case 0x0B: // DEC BC
        set_bc(cpu, get_bc(cpu) - 1)
        return 8

    case 0x0C: // INC C
        cpu.c = inc8(cpu, cpu.c)
        return 4

    case 0x0D: // DEC C
        cpu.c = dec8(cpu, cpu.c)
        return 4

    case 0x0E: // LD C, n
        cpu.c = fetch8(cpu)
        return 8

    case 0x0F: // RRCA
        carry := (cpu.a & 0x01) != 0
        cpu.a = (cpu.a >> 1) | (cpu.a << 7)
        set_flags(cpu, false, false, false, carry)
        return 4

    case 0x10: // STOP
        fetch8(cpu)  // STOP is 2 bytes
        cpu.stopped = true
        return 4

    case 0x11: // LD DE, nn
        set_de(cpu, fetch16(cpu))
        return 12

    case 0x12: // LD (DE), A
        write8(cpu, get_de(cpu), cpu.a)
        return 8

    case 0x13: // INC DE
        set_de(cpu, get_de(cpu) + 1)
        return 8

    case 0x14: // INC D
        cpu.d = inc8(cpu, cpu.d)
        return 4

    case 0x15: // DEC D
        cpu.d = dec8(cpu, cpu.d)
        return 4

    case 0x16: // LD D, n
        cpu.d = fetch8(cpu)
        return 8

    case 0x17: // RLA
        carry := get_flag_c(cpu)
        new_carry := (cpu.a & 0x80) != 0
        cpu.a = (cpu.a << 1) | (carry ? 1 : 0)
        set_flags(cpu, false, false, false, new_carry)
        return 4

    case 0x18: // JR n
        offset := i8(fetch8(cpu))
        cpu.pc = u16(i32(cpu.pc) + i32(offset))
        return 12

    case 0x19: // ADD HL, DE
        add_hl(cpu, get_de(cpu))
        return 8

    case 0x1A: // LD A, (DE)
        cpu.a = read8(cpu, get_de(cpu))
        return 8

    case 0x1B: // DEC DE
        set_de(cpu, get_de(cpu) - 1)
        return 8

    case 0x1C: // INC E
        cpu.e = inc8(cpu, cpu.e)
        return 4

    case 0x1D: // DEC E
        cpu.e = dec8(cpu, cpu.e)
        return 4

    case 0x1E: // LD E, n
        cpu.e = fetch8(cpu)
        return 8

    case 0x1F: // RRA
        carry := get_flag_c(cpu)
        new_carry := (cpu.a & 0x01) != 0
        cpu.a = (cpu.a >> 1) | (carry ? 0x80 : 0)
        set_flags(cpu, false, false, false, new_carry)
        return 4

    case 0x20: // JR NZ, n
        offset := i8(fetch8(cpu))
        if !get_flag_z(cpu) {
            cpu.pc = u16(i32(cpu.pc) + i32(offset))
            return 12
        }
        return 8

    case 0x21: // LD HL, nn
        set_hl(cpu, fetch16(cpu))
        return 12

    case 0x22: // LD (HL+), A
        write8(cpu, get_hl(cpu), cpu.a)
        set_hl(cpu, get_hl(cpu) + 1)
        return 8

    case 0x23: // INC HL
        set_hl(cpu, get_hl(cpu) + 1)
        return 8

    case 0x24: // INC H
        cpu.h = inc8(cpu, cpu.h)
        return 4

    case 0x25: // DEC H
        cpu.h = dec8(cpu, cpu.h)
        return 4

    case 0x26: // LD H, n
        cpu.h = fetch8(cpu)
        return 8

    case 0x27: // DAA
        daa(cpu)
        return 4

    case 0x28: // JR Z, n
        offset := i8(fetch8(cpu))
        if get_flag_z(cpu) {
            cpu.pc = u16(i32(cpu.pc) + i32(offset))
            return 12
        }
        return 8

    case 0x29: // ADD HL, HL
        add_hl(cpu, get_hl(cpu))
        return 8

    case 0x2A: // LD A, (HL+)
        cpu.a = read8(cpu, get_hl(cpu))
        set_hl(cpu, get_hl(cpu) + 1)
        return 8

    case 0x2B: // DEC HL
        set_hl(cpu, get_hl(cpu) - 1)
        return 8

    case 0x2C: // INC L
        cpu.l = inc8(cpu, cpu.l)
        return 4

    case 0x2D: // DEC L
        cpu.l = dec8(cpu, cpu.l)
        return 4

    case 0x2E: // LD L, n
        cpu.l = fetch8(cpu)
        return 8

    case 0x2F: // CPL
        cpu.a = ~cpu.a
        set_flag_n(cpu, true)
        set_flag_h(cpu, true)
        return 4

    case 0x30: // JR NC, n
        offset := i8(fetch8(cpu))
        if !get_flag_c(cpu) {
            cpu.pc = u16(i32(cpu.pc) + i32(offset))
            return 12
        }
        return 8

    case 0x31: // LD SP, nn
        cpu.sp = fetch16(cpu)
        return 12

    case 0x32: // LD (HL-), A
        write8(cpu, get_hl(cpu), cpu.a)
        set_hl(cpu, get_hl(cpu) - 1)
        return 8

    case 0x33: // INC SP
        cpu.sp += 1
        return 8

    case 0x34: // INC (HL)
        addr := get_hl(cpu)
        write8(cpu, addr, inc8(cpu, read8(cpu, addr)))
        return 12

    case 0x35: // DEC (HL)
        addr := get_hl(cpu)
        write8(cpu, addr, dec8(cpu, read8(cpu, addr)))
        return 12

    case 0x36: // LD (HL), n
        write8(cpu, get_hl(cpu), fetch8(cpu))
        return 12

    case 0x37: // SCF
        set_flag_n(cpu, false)
        set_flag_h(cpu, false)
        set_flag_c(cpu, true)
        return 4

    case 0x38: // JR C, n
        offset := i8(fetch8(cpu))
        if get_flag_c(cpu) {
            cpu.pc = u16(i32(cpu.pc) + i32(offset))
            return 12
        }
        return 8

    case 0x39: // ADD HL, SP
        add_hl(cpu, cpu.sp)
        return 8

    case 0x3A: // LD A, (HL-)
        cpu.a = read8(cpu, get_hl(cpu))
        set_hl(cpu, get_hl(cpu) - 1)
        return 8

    case 0x3B: // DEC SP
        cpu.sp -= 1
        return 8

    case 0x3C: // INC A
        cpu.a = inc8(cpu, cpu.a)
        return 4

    case 0x3D: // DEC A
        cpu.a = dec8(cpu, cpu.a)
        return 4

    case 0x3E: // LD A, n
        cpu.a = fetch8(cpu)
        return 8

    case 0x3F: // CCF
        set_flag_n(cpu, false)
        set_flag_h(cpu, false)
        set_flag_c(cpu, !get_flag_c(cpu))
        return 4

    // ============ 0x40-0x7F: LD r, r' (and HALT) ============

    case 0x40: cpu.b = cpu.b; return 4  // LD B, B
    case 0x41: cpu.b = cpu.c; return 4  // LD B, C
    case 0x42: cpu.b = cpu.d; return 4  // LD B, D
    case 0x43: cpu.b = cpu.e; return 4  // LD B, E
    case 0x44: cpu.b = cpu.h; return 4  // LD B, H
    case 0x45: cpu.b = cpu.l; return 4  // LD B, L
    case 0x46: cpu.b = read8(cpu, get_hl(cpu)); return 8  // LD B, (HL)
    case 0x47: cpu.b = cpu.a; return 4  // LD B, A

    case 0x48: cpu.c = cpu.b; return 4  // LD C, B
    case 0x49: cpu.c = cpu.c; return 4  // LD C, C
    case 0x4A: cpu.c = cpu.d; return 4  // LD C, D
    case 0x4B: cpu.c = cpu.e; return 4  // LD C, E
    case 0x4C: cpu.c = cpu.h; return 4  // LD C, H
    case 0x4D: cpu.c = cpu.l; return 4  // LD C, L
    case 0x4E: cpu.c = read8(cpu, get_hl(cpu)); return 8  // LD C, (HL)
    case 0x4F: cpu.c = cpu.a; return 4  // LD C, A

    case 0x50: cpu.d = cpu.b; return 4  // LD D, B
    case 0x51: cpu.d = cpu.c; return 4  // LD D, C
    case 0x52: cpu.d = cpu.d; return 4  // LD D, D
    case 0x53: cpu.d = cpu.e; return 4  // LD D, E
    case 0x54: cpu.d = cpu.h; return 4  // LD D, H
    case 0x55: cpu.d = cpu.l; return 4  // LD D, L
    case 0x56: cpu.d = read8(cpu, get_hl(cpu)); return 8  // LD D, (HL)
    case 0x57: cpu.d = cpu.a; return 4  // LD D, A

    case 0x58: cpu.e = cpu.b; return 4  // LD E, B
    case 0x59: cpu.e = cpu.c; return 4  // LD E, C
    case 0x5A: cpu.e = cpu.d; return 4  // LD E, D
    case 0x5B: cpu.e = cpu.e; return 4  // LD E, E
    case 0x5C: cpu.e = cpu.h; return 4  // LD E, H
    case 0x5D: cpu.e = cpu.l; return 4  // LD E, L
    case 0x5E: cpu.e = read8(cpu, get_hl(cpu)); return 8  // LD E, (HL)
    case 0x5F: cpu.e = cpu.a; return 4  // LD E, A

    case 0x60: cpu.h = cpu.b; return 4  // LD H, B
    case 0x61: cpu.h = cpu.c; return 4  // LD H, C
    case 0x62: cpu.h = cpu.d; return 4  // LD H, D
    case 0x63: cpu.h = cpu.e; return 4  // LD H, E
    case 0x64: cpu.h = cpu.h; return 4  // LD H, H
    case 0x65: cpu.h = cpu.l; return 4  // LD H, L
    case 0x66: cpu.h = read8(cpu, get_hl(cpu)); return 8  // LD H, (HL)
    case 0x67: cpu.h = cpu.a; return 4  // LD H, A

    case 0x68: cpu.l = cpu.b; return 4  // LD L, B
    case 0x69: cpu.l = cpu.c; return 4  // LD L, C
    case 0x6A: cpu.l = cpu.d; return 4  // LD L, D
    case 0x6B: cpu.l = cpu.e; return 4  // LD L, E
    case 0x6C: cpu.l = cpu.h; return 4  // LD L, H
    case 0x6D: cpu.l = cpu.l; return 4  // LD L, L
    case 0x6E: cpu.l = read8(cpu, get_hl(cpu)); return 8  // LD L, (HL)
    case 0x6F: cpu.l = cpu.a; return 4  // LD L, A

    case 0x70: write8(cpu, get_hl(cpu), cpu.b); return 8  // LD (HL), B
    case 0x71: write8(cpu, get_hl(cpu), cpu.c); return 8  // LD (HL), C
    case 0x72: write8(cpu, get_hl(cpu), cpu.d); return 8  // LD (HL), D
    case 0x73: write8(cpu, get_hl(cpu), cpu.e); return 8  // LD (HL), E
    case 0x74: write8(cpu, get_hl(cpu), cpu.h); return 8  // LD (HL), H
    case 0x75: write8(cpu, get_hl(cpu), cpu.l); return 8  // LD (HL), L

    case 0x76: // HALT
        cpu.halted = true
        return 4

    case 0x77: write8(cpu, get_hl(cpu), cpu.a); return 8  // LD (HL), A

    case 0x78: cpu.a = cpu.b; return 4  // LD A, B
    case 0x79: cpu.a = cpu.c; return 4  // LD A, C
    case 0x7A: cpu.a = cpu.d; return 4  // LD A, D
    case 0x7B: cpu.a = cpu.e; return 4  // LD A, E
    case 0x7C: cpu.a = cpu.h; return 4  // LD A, H
    case 0x7D: cpu.a = cpu.l; return 4  // LD A, L
    case 0x7E: cpu.a = read8(cpu, get_hl(cpu)); return 8  // LD A, (HL)
    case 0x7F: cpu.a = cpu.a; return 4  // LD A, A

    // ============ 0x80-0xBF: ALU operations ============

    case 0x80: add_a(cpu, cpu.b, false); return 4  // ADD A, B
    case 0x81: add_a(cpu, cpu.c, false); return 4  // ADD A, C
    case 0x82: add_a(cpu, cpu.d, false); return 4  // ADD A, D
    case 0x83: add_a(cpu, cpu.e, false); return 4  // ADD A, E
    case 0x84: add_a(cpu, cpu.h, false); return 4  // ADD A, H
    case 0x85: add_a(cpu, cpu.l, false); return 4  // ADD A, L
    case 0x86: add_a(cpu, read8(cpu, get_hl(cpu)), false); return 8  // ADD A, (HL)
    case 0x87: add_a(cpu, cpu.a, false); return 4  // ADD A, A

    case 0x88: add_a(cpu, cpu.b, true); return 4  // ADC A, B
    case 0x89: add_a(cpu, cpu.c, true); return 4  // ADC A, C
    case 0x8A: add_a(cpu, cpu.d, true); return 4  // ADC A, D
    case 0x8B: add_a(cpu, cpu.e, true); return 4  // ADC A, E
    case 0x8C: add_a(cpu, cpu.h, true); return 4  // ADC A, H
    case 0x8D: add_a(cpu, cpu.l, true); return 4  // ADC A, L
    case 0x8E: add_a(cpu, read8(cpu, get_hl(cpu)), true); return 8  // ADC A, (HL)
    case 0x8F: add_a(cpu, cpu.a, true); return 4  // ADC A, A

    case 0x90: sub_a(cpu, cpu.b, false); return 4  // SUB B
    case 0x91: sub_a(cpu, cpu.c, false); return 4  // SUB C
    case 0x92: sub_a(cpu, cpu.d, false); return 4  // SUB D
    case 0x93: sub_a(cpu, cpu.e, false); return 4  // SUB E
    case 0x94: sub_a(cpu, cpu.h, false); return 4  // SUB H
    case 0x95: sub_a(cpu, cpu.l, false); return 4  // SUB L
    case 0x96: sub_a(cpu, read8(cpu, get_hl(cpu)), false); return 8  // SUB (HL)
    case 0x97: sub_a(cpu, cpu.a, false); return 4  // SUB A

    case 0x98: sub_a(cpu, cpu.b, true); return 4  // SBC A, B
    case 0x99: sub_a(cpu, cpu.c, true); return 4  // SBC A, C
    case 0x9A: sub_a(cpu, cpu.d, true); return 4  // SBC A, D
    case 0x9B: sub_a(cpu, cpu.e, true); return 4  // SBC A, E
    case 0x9C: sub_a(cpu, cpu.h, true); return 4  // SBC A, H
    case 0x9D: sub_a(cpu, cpu.l, true); return 4  // SBC A, L
    case 0x9E: sub_a(cpu, read8(cpu, get_hl(cpu)), true); return 8  // SBC A, (HL)
    case 0x9F: sub_a(cpu, cpu.a, true); return 4  // SBC A, A

    case 0xA0: and_a(cpu, cpu.b); return 4  // AND B
    case 0xA1: and_a(cpu, cpu.c); return 4  // AND C
    case 0xA2: and_a(cpu, cpu.d); return 4  // AND D
    case 0xA3: and_a(cpu, cpu.e); return 4  // AND E
    case 0xA4: and_a(cpu, cpu.h); return 4  // AND H
    case 0xA5: and_a(cpu, cpu.l); return 4  // AND L
    case 0xA6: and_a(cpu, read8(cpu, get_hl(cpu))); return 8  // AND (HL)
    case 0xA7: and_a(cpu, cpu.a); return 4  // AND A

    case 0xA8: xor_a(cpu, cpu.b); return 4  // XOR B
    case 0xA9: xor_a(cpu, cpu.c); return 4  // XOR C
    case 0xAA: xor_a(cpu, cpu.d); return 4  // XOR D
    case 0xAB: xor_a(cpu, cpu.e); return 4  // XOR E
    case 0xAC: xor_a(cpu, cpu.h); return 4  // XOR H
    case 0xAD: xor_a(cpu, cpu.l); return 4  // XOR L
    case 0xAE: xor_a(cpu, read8(cpu, get_hl(cpu))); return 8  // XOR (HL)
    case 0xAF: xor_a(cpu, cpu.a); return 4  // XOR A

    case 0xB0: or_a(cpu, cpu.b); return 4  // OR B
    case 0xB1: or_a(cpu, cpu.c); return 4  // OR C
    case 0xB2: or_a(cpu, cpu.d); return 4  // OR D
    case 0xB3: or_a(cpu, cpu.e); return 4  // OR E
    case 0xB4: or_a(cpu, cpu.h); return 4  // OR H
    case 0xB5: or_a(cpu, cpu.l); return 4  // OR L
    case 0xB6: or_a(cpu, read8(cpu, get_hl(cpu))); return 8  // OR (HL)
    case 0xB7: or_a(cpu, cpu.a); return 4  // OR A

    case 0xB8: cp_a(cpu, cpu.b); return 4  // CP B
    case 0xB9: cp_a(cpu, cpu.c); return 4  // CP C
    case 0xBA: cp_a(cpu, cpu.d); return 4  // CP D
    case 0xBB: cp_a(cpu, cpu.e); return 4  // CP E
    case 0xBC: cp_a(cpu, cpu.h); return 4  // CP H
    case 0xBD: cp_a(cpu, cpu.l); return 4  // CP L
    case 0xBE: cp_a(cpu, read8(cpu, get_hl(cpu))); return 8  // CP (HL)
    case 0xBF: cp_a(cpu, cpu.a); return 4  // CP A

    // ============ 0xC0-0xFF: Control flow, stack, misc ============

    case 0xC0: // RET NZ
        if !get_flag_z(cpu) {
            cpu.pc = pop16(cpu)
            return 20
        }
        return 8

    case 0xC1: // POP BC
        set_bc(cpu, pop16(cpu))
        return 12

    case 0xC2: // JP NZ, nn
        addr := fetch16(cpu)
        if !get_flag_z(cpu) {
            cpu.pc = addr
            return 16
        }
        return 12

    case 0xC3: // JP nn
        cpu.pc = fetch16(cpu)
        return 16

    case 0xC4: // CALL NZ, nn
        addr := fetch16(cpu)
        if !get_flag_z(cpu) {
            push16(cpu, cpu.pc)
            cpu.pc = addr
            return 24
        }
        return 12

    case 0xC5: // PUSH BC
        push16(cpu, get_bc(cpu))
        return 16

    case 0xC6: // ADD A, n
        add_a(cpu, fetch8(cpu), false)
        return 8

    case 0xC7: // RST 00
        push16(cpu, cpu.pc)
        cpu.pc = 0x0000
        return 16

    case 0xC8: // RET Z
        if get_flag_z(cpu) {
            cpu.pc = pop16(cpu)
            return 20
        }
        return 8

    case 0xC9: // RET
        cpu.pc = pop16(cpu)
        return 16

    case 0xCA: // JP Z, nn
        addr := fetch16(cpu)
        if get_flag_z(cpu) {
            cpu.pc = addr
            return 16
        }
        return 12

    // 0xCB is handled at the top

    case 0xCC: // CALL Z, nn
        addr := fetch16(cpu)
        if get_flag_z(cpu) {
            push16(cpu, cpu.pc)
            cpu.pc = addr
            return 24
        }
        return 12

    case 0xCD: // CALL nn
        addr := fetch16(cpu)
        push16(cpu, cpu.pc)
        cpu.pc = addr
        return 24

    case 0xCE: // ADC A, n
        add_a(cpu, fetch8(cpu), true)
        return 8

    case 0xCF: // RST 08
        push16(cpu, cpu.pc)
        cpu.pc = 0x0008
        return 16

    case 0xD0: // RET NC
        if !get_flag_c(cpu) {
            cpu.pc = pop16(cpu)
            return 20
        }
        return 8

    case 0xD1: // POP DE
        set_de(cpu, pop16(cpu))
        return 12

    case 0xD2: // JP NC, nn
        addr := fetch16(cpu)
        if !get_flag_c(cpu) {
            cpu.pc = addr
            return 16
        }
        return 12

    // 0xD3 is illegal

    case 0xD4: // CALL NC, nn
        addr := fetch16(cpu)
        if !get_flag_c(cpu) {
            push16(cpu, cpu.pc)
            cpu.pc = addr
            return 24
        }
        return 12

    case 0xD5: // PUSH DE
        push16(cpu, get_de(cpu))
        return 16

    case 0xD6: // SUB n
        sub_a(cpu, fetch8(cpu), false)
        return 8

    case 0xD7: // RST 10
        push16(cpu, cpu.pc)
        cpu.pc = 0x0010
        return 16

    case 0xD8: // RET C
        if get_flag_c(cpu) {
            cpu.pc = pop16(cpu)
            return 20
        }
        return 8

    case 0xD9: // RETI
        cpu.pc = pop16(cpu)
        cpu.ime = true
        return 16

    case 0xDA: // JP C, nn
        addr := fetch16(cpu)
        if get_flag_c(cpu) {
            cpu.pc = addr
            return 16
        }
        return 12

    // 0xDB is illegal

    case 0xDC: // CALL C, nn
        addr := fetch16(cpu)
        if get_flag_c(cpu) {
            push16(cpu, cpu.pc)
            cpu.pc = addr
            return 24
        }
        return 12

    // 0xDD is illegal

    case 0xDE: // SBC A, n
        sub_a(cpu, fetch8(cpu), true)
        return 8

    case 0xDF: // RST 18
        push16(cpu, cpu.pc)
        cpu.pc = 0x0018
        return 16

    case 0xE0: // LD (FF00+n), A
        write8(cpu, 0xFF00 + u16(fetch8(cpu)), cpu.a)
        return 12

    case 0xE1: // POP HL
        set_hl(cpu, pop16(cpu))
        return 12

    case 0xE2: // LD (FF00+C), A
        write8(cpu, 0xFF00 + u16(cpu.c), cpu.a)
        return 8

    // 0xE3, 0xE4 are illegal

    case 0xE5: // PUSH HL
        push16(cpu, get_hl(cpu))
        return 16

    case 0xE6: // AND n
        and_a(cpu, fetch8(cpu))
        return 8

    case 0xE7: // RST 20
        push16(cpu, cpu.pc)
        cpu.pc = 0x0020
        return 16

    case 0xE8: // ADD SP, n
        offset := i8(fetch8(cpu))
        result := u16(i32(cpu.sp) + i32(offset))
        // Flags are set based on low byte addition
        set_flag_z(cpu, false)
        set_flag_n(cpu, false)
        set_flag_h(cpu, ((cpu.sp & 0x0F) + (u16(u8(offset)) & 0x0F)) > 0x0F)
        set_flag_c(cpu, ((cpu.sp & 0xFF) + u16(u8(offset))) > 0xFF)
        cpu.sp = result
        return 16

    case 0xE9: // JP HL
        cpu.pc = get_hl(cpu)
        return 4

    case 0xEA: // LD (nn), A
        write8(cpu, fetch16(cpu), cpu.a)
        return 16

    // 0xEB, 0xEC, 0xED are illegal

    case 0xEE: // XOR n
        xor_a(cpu, fetch8(cpu))
        return 8

    case 0xEF: // RST 28
        push16(cpu, cpu.pc)
        cpu.pc = 0x0028
        return 16

    case 0xF0: // LD A, (FF00+n)
        cpu.a = read8(cpu, 0xFF00 + u16(fetch8(cpu)))
        return 12

    case 0xF1: // POP AF
        set_af(cpu, pop16(cpu))
        return 12

    case 0xF2: // LD A, (FF00+C)
        cpu.a = read8(cpu, 0xFF00 + u16(cpu.c))
        return 8

    case 0xF3: // DI
        cpu.ime = false
        return 4

    // 0xF4 is illegal

    case 0xF5: // PUSH AF
        push16(cpu, get_af(cpu))
        return 16

    case 0xF6: // OR n
        or_a(cpu, fetch8(cpu))
        return 8

    case 0xF7: // RST 30
        push16(cpu, cpu.pc)
        cpu.pc = 0x0030
        return 16

    case 0xF8: // LD HL, SP+n
        offset := i8(fetch8(cpu))
        result := u16(i32(cpu.sp) + i32(offset))
        set_flag_z(cpu, false)
        set_flag_n(cpu, false)
        set_flag_h(cpu, ((cpu.sp & 0x0F) + (u16(u8(offset)) & 0x0F)) > 0x0F)
        set_flag_c(cpu, ((cpu.sp & 0xFF) + u16(u8(offset))) > 0xFF)
        set_hl(cpu, result)
        return 12

    case 0xF9: // LD SP, HL
        cpu.sp = get_hl(cpu)
        return 8

    case 0xFA: // LD A, (nn)
        cpu.a = read8(cpu, fetch16(cpu))
        return 16

    case 0xFB: // EI
        cpu.ime_scheduled = true
        return 4

    // 0xFC, 0xFD are illegal

    case 0xFE: // CP n
        cp_a(cpu, fetch8(cpu))
        return 8

    case 0xFF: // RST 38
        push16(cpu, cpu.pc)
        cpu.pc = 0x0038
        return 16

    case:
        // Illegal opcode - treat as NOP
        return 4
    }
}

// ALU helper functions

inc8 :: proc(cpu: ^CPU, value: u8) -> u8 {
    result := value + 1
    set_flag_z(cpu, result == 0)
    set_flag_n(cpu, false)
    set_flag_h(cpu, (value & 0x0F) == 0x0F)
    return result
}

dec8 :: proc(cpu: ^CPU, value: u8) -> u8 {
    result := value - 1
    set_flag_z(cpu, result == 0)
    set_flag_n(cpu, true)
    set_flag_h(cpu, (value & 0x0F) == 0)
    return result
}

add_a :: proc(cpu: ^CPU, value: u8, with_carry: bool) {
    carry: u8 = 0
    if with_carry && get_flag_c(cpu) {
        carry = 1
    }

    result := u16(cpu.a) + u16(value) + u16(carry)
    half := (cpu.a & 0x0F) + (value & 0x0F) + carry

    set_flag_z(cpu, u8(result) == 0)
    set_flag_n(cpu, false)
    set_flag_h(cpu, half > 0x0F)
    set_flag_c(cpu, result > 0xFF)

    cpu.a = u8(result)
}

sub_a :: proc(cpu: ^CPU, value: u8, with_carry: bool) {
    carry: u8 = 0
    if with_carry && get_flag_c(cpu) {
        carry = 1
    }

    result := i16(cpu.a) - i16(value) - i16(carry)
    half := i16(cpu.a & 0x0F) - i16(value & 0x0F) - i16(carry)

    set_flag_z(cpu, u8(result) == 0)
    set_flag_n(cpu, true)
    set_flag_h(cpu, half < 0)
    set_flag_c(cpu, result < 0)

    cpu.a = u8(result)
}

and_a :: proc(cpu: ^CPU, value: u8) {
    cpu.a &= value
    set_flags(cpu, cpu.a == 0, false, true, false)
}

xor_a :: proc(cpu: ^CPU, value: u8) {
    cpu.a ~= value
    set_flags(cpu, cpu.a == 0, false, false, false)
}

or_a :: proc(cpu: ^CPU, value: u8) {
    cpu.a |= value
    set_flags(cpu, cpu.a == 0, false, false, false)
}

cp_a :: proc(cpu: ^CPU, value: u8) {
    result := i16(cpu.a) - i16(value)
    half := i16(cpu.a & 0x0F) - i16(value & 0x0F)

    set_flag_z(cpu, u8(result) == 0)
    set_flag_n(cpu, true)
    set_flag_h(cpu, half < 0)
    set_flag_c(cpu, result < 0)
}

add_hl :: proc(cpu: ^CPU, value: u16) {
    hl := get_hl(cpu)
    result := u32(hl) + u32(value)

    set_flag_n(cpu, false)
    set_flag_h(cpu, ((hl & 0x0FFF) + (value & 0x0FFF)) > 0x0FFF)
    set_flag_c(cpu, result > 0xFFFF)

    set_hl(cpu, u16(result))
}

daa :: proc(cpu: ^CPU) {
    // Decimal Adjust Accumulator
    a := cpu.a
    correction: u8 = 0

    if get_flag_h(cpu) || (!get_flag_n(cpu) && (a & 0x0F) > 9) {
        correction |= 0x06
    }

    if get_flag_c(cpu) || (!get_flag_n(cpu) && a > 0x99) {
        correction |= 0x60
        set_flag_c(cpu, true)
    }

    if get_flag_n(cpu) {
        a -= correction
    } else {
        a += correction
    }

    cpu.a = a
    set_flag_z(cpu, a == 0)
    set_flag_h(cpu, false)
}
