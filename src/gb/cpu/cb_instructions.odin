package gb_cpu

// CB-prefixed instructions (bit operations, rotates, shifts)
// These are all 2-byte opcodes: CB xx

execute_cb :: proc(cpu: ^CPU, opcode: u8) -> u8 {
    // Get register operand (bottom 3 bits)
    reg := opcode & 0x07

    // Get value from register
    value := get_reg8(cpu, reg)
    is_memory := reg == 6  // (HL) access

    // Get operation (top 2 bits) and bit number (bits 3-5)
    op := opcode >> 6
    bit := (opcode >> 3) & 0x07

    result: u8
    cycles: u8 = is_memory ? 16 : 8

    switch op {
    case 0b00: // Rotates and shifts
        switch bit {
        case 0: result = rlc(cpu, value)   // RLC
        case 1: result = rrc(cpu, value)   // RRC
        case 2: result = rl(cpu, value)    // RL
        case 3: result = rr(cpu, value)    // RR
        case 4: result = sla(cpu, value)   // SLA
        case 5: result = sra(cpu, value)   // SRA
        case 6: result = swap(cpu, value)  // SWAP
        case 7: result = srl(cpu, value)   // SRL
        }
        set_reg8(cpu, reg, result)

    case 0b01: // BIT (test bit)
        bit_test(cpu, value, bit)
        return is_memory ? 12 : 8  // BIT doesn't write back

    case 0b10: // RES (reset bit)
        result = value & ~(1 << bit)
        set_reg8(cpu, reg, result)

    case 0b11: // SET (set bit)
        result = value | (1 << bit)
        set_reg8(cpu, reg, result)
    }

    return cycles
}

// Get 8-bit register by index
get_reg8 :: proc(cpu: ^CPU, reg: u8) -> u8 {
    switch reg {
    case 0: return cpu.b
    case 1: return cpu.c
    case 2: return cpu.d
    case 3: return cpu.e
    case 4: return cpu.h
    case 5: return cpu.l
    case 6: return read8(cpu, get_hl(cpu))  // (HL)
    case 7: return cpu.a
    }
    return 0
}

// Set 8-bit register by index
set_reg8 :: proc(cpu: ^CPU, reg: u8, value: u8) {
    switch reg {
    case 0: cpu.b = value
    case 1: cpu.c = value
    case 2: cpu.d = value
    case 3: cpu.e = value
    case 4: cpu.h = value
    case 5: cpu.l = value
    case 6: write8(cpu, get_hl(cpu), value)  // (HL)
    case 7: cpu.a = value
    }
}

// Rotate left circular
rlc :: proc(cpu: ^CPU, value: u8) -> u8 {
    carry := (value & 0x80) != 0
    result := (value << 1) | (value >> 7)
    set_flags(cpu, result == 0, false, false, carry)
    return result
}

// Rotate right circular
rrc :: proc(cpu: ^CPU, value: u8) -> u8 {
    carry := (value & 0x01) != 0
    result := (value >> 1) | (value << 7)
    set_flags(cpu, result == 0, false, false, carry)
    return result
}

// Rotate left through carry
rl :: proc(cpu: ^CPU, value: u8) -> u8 {
    old_carry := get_flag_c(cpu)
    new_carry := (value & 0x80) != 0
    result := (value << 1) | (old_carry ? 1 : 0)
    set_flags(cpu, result == 0, false, false, new_carry)
    return result
}

// Rotate right through carry
rr :: proc(cpu: ^CPU, value: u8) -> u8 {
    old_carry := get_flag_c(cpu)
    new_carry := (value & 0x01) != 0
    result := (value >> 1) | (old_carry ? 0x80 : 0)
    set_flags(cpu, result == 0, false, false, new_carry)
    return result
}

// Shift left arithmetic (same as logical for left)
sla :: proc(cpu: ^CPU, value: u8) -> u8 {
    carry := (value & 0x80) != 0
    result := value << 1
    set_flags(cpu, result == 0, false, false, carry)
    return result
}

// Shift right arithmetic (preserves sign bit)
sra :: proc(cpu: ^CPU, value: u8) -> u8 {
    carry := (value & 0x01) != 0
    result := (value >> 1) | (value & 0x80)  // Keep bit 7
    set_flags(cpu, result == 0, false, false, carry)
    return result
}

// Shift right logical
srl :: proc(cpu: ^CPU, value: u8) -> u8 {
    carry := (value & 0x01) != 0
    result := value >> 1
    set_flags(cpu, result == 0, false, false, carry)
    return result
}

// Swap nibbles
swap :: proc(cpu: ^CPU, value: u8) -> u8 {
    result := ((value & 0x0F) << 4) | ((value & 0xF0) >> 4)
    set_flags(cpu, result == 0, false, false, false)
    return result
}

// Test bit
bit_test :: proc(cpu: ^CPU, value: u8, bit: u8) {
    set_flag_z(cpu, (value & (1 << bit)) == 0)
    set_flag_n(cpu, false)
    set_flag_h(cpu, true)
    // Carry is not affected
}
