package cpu

import "../bus"
import "core:fmt"

// Debug flag for tracing load/store operations (enable for debugging)
thumb_debug_ldst := false

// Thumb instruction handler type
Thumb_Handler :: #type proc(cpu: ^CPU, mem_bus: ^bus.Bus, opcode: u16)

// Thumb instruction lookup table (256 entries, indexed by upper 8 bits)
thumb_lut: [256]Thumb_Handler

// Initialize Thumb lookup table
@(init)
init_thumb_lut :: proc "contextless" () {
    for i in 0 ..< 256 {
        thumb_lut[i] = decode_thumb_instruction(u8(i))
    }
}

// Decode Thumb instruction based on upper 8 bits
@(private)
decode_thumb_instruction :: proc "contextless" (upper: u8) -> Thumb_Handler {
    // Format 1: Move shifted register (LSL/LSR/ASR)
    if (upper & 0xE0) == 0x00 {
        op := (upper >> 3) & 0x3
        switch op {
        case 0:
            return thumb_lsl_imm
        case 1:
            return thumb_lsr_imm
        case 2:
            return thumb_asr_imm
        }
    }

    // Format 2: Add/subtract
    if (upper & 0xF8) == 0x18 {
        return thumb_add_sub
    }

    // Format 3: Move/compare/add/subtract immediate
    if (upper & 0xE0) == 0x20 {
        op := (upper >> 3) & 0x3
        switch op {
        case 0:
            return thumb_mov_imm
        case 1:
            return thumb_cmp_imm
        case 2:
            return thumb_add_imm8
        case 3:
            return thumb_sub_imm8
        }
    }

    // Format 4: ALU operations
    if (upper & 0xFC) == 0x40 {
        return thumb_alu
    }

    // Format 5: Hi register operations / branch exchange
    if (upper & 0xFC) == 0x44 {
        return thumb_hi_reg
    }

    // Format 6: PC-relative load
    if (upper & 0xF8) == 0x48 {
        return thumb_ldr_pc
    }

    // Format 7: Load/store with register offset
    if (upper & 0xF0) == 0x50 {
        return thumb_ldr_str_reg
    }

    // Format 8: Load/store sign-extended byte/halfword
    if (upper & 0xF0) == 0x50 {
        // Already handled by format 7/8 combined
        return thumb_ldr_str_reg
    }

    // Format 9: Load/store with immediate offset
    if (upper & 0xE0) == 0x60 {
        return thumb_ldr_str_imm
    }

    // Format 10: Load/store halfword
    if (upper & 0xF0) == 0x80 {
        return thumb_ldrh_strh_imm
    }

    // Format 11: SP-relative load/store
    if (upper & 0xF0) == 0x90 {
        return thumb_ldr_str_sp
    }

    // Format 12: Load address
    if (upper & 0xF0) == 0xA0 {
        return thumb_load_addr
    }

    // Format 13: Add offset to stack pointer
    if upper == 0xB0 {
        return thumb_add_sp
    }

    // Format 14: Push/pop registers
    if (upper & 0xF6) == 0xB4 {
        return thumb_push_pop
    }

    // Format 15: Multiple load/store
    if (upper & 0xF0) == 0xC0 {
        return thumb_ldm_stm
    }

    // Format 16: Conditional branch
    if (upper & 0xF0) == 0xD0 {
        cond := upper & 0xF
        if cond == 0xE {
            return thumb_undefined // Undefined
        }
        if cond == 0xF {
            return thumb_swi
        }
        return thumb_branch_cond
    }

    // Format 17: Software interrupt (handled above)

    // Format 18: Unconditional branch
    if (upper & 0xF8) == 0xE0 {
        return thumb_branch
    }

    // Format 19: Long branch with link
    if (upper & 0xF0) == 0xF0 {
        if (upper & 0x08) == 0 {
            return thumb_bl_prefix
        } else {
            return thumb_bl_suffix
        }
    }

    return thumb_undefined
}

// Execute Thumb instruction
execute_thumb :: proc(cpu: ^CPU, mem_bus: ^bus.Bus, opcode: u16) {
    index := opcode >> 8
    handler := thumb_lut[index]
    handler(cpu, mem_bus, opcode)

    // Advance PC if not modified by instruction
    if cpu.pipeline_valid {
        cpu.regs[15] += 2
    }
    cpu.pipeline_valid = true
}

// Undefined instruction
thumb_undefined :: proc(cpu: ^CPU, mem_bus: ^bus.Bus, opcode: u16) {
    undefined(cpu)
}

// Software interrupt
thumb_swi :: proc(cpu: ^CPU, mem_bus: ^bus.Bus, opcode: u16) {
    // SWI number is in bits 0-7
    swi_num := u8(opcode & 0xFF)

    // Try HLE first
    if swi_hle(cpu, mem_bus, swi_num) {
        cpu.cycles = 3
        return
    }

    // Fall back to BIOS
    swi(cpu)
    cpu.cycles = 3
}

// ============================================================================
// Format 1: Move shifted register
// ============================================================================

thumb_lsl_imm :: proc(cpu: ^CPU, mem_bus: ^bus.Bus, opcode: u16) {
    rd := u4(opcode & 0x7)
    rs := u4((opcode >> 3) & 0x7)
    offset := (opcode >> 6) & 0x1F

    value := get_reg(cpu, rs)
    carry := get_flag_c(cpu)

    if offset == 0 {
        // LSL #0 = no change
    } else {
        carry = (value & (1 << (32 - offset))) != 0
        value <<= offset
    }

    set_reg(cpu, rd, value)
    set_nz_flags(cpu, value)
    set_flag_c(cpu, carry)

    cpu.cycles = 1
}

thumb_lsr_imm :: proc(cpu: ^CPU, mem_bus: ^bus.Bus, opcode: u16) {
    rd := u4(opcode & 0x7)
    rs := u4((opcode >> 3) & 0x7)
    offset := (opcode >> 6) & 0x1F

    value := get_reg(cpu, rs)
    carry: bool

    if offset == 0 {
        // LSR #0 means LSR #32
        carry = (value & 0x80000000) != 0
        value = 0
    } else {
        carry = (value & (1 << (offset - 1))) != 0
        value >>= offset
    }

    set_reg(cpu, rd, value)
    set_nz_flags(cpu, value)
    set_flag_c(cpu, carry)

    cpu.cycles = 1
}

thumb_asr_imm :: proc(cpu: ^CPU, mem_bus: ^bus.Bus, opcode: u16) {
    rd := u4(opcode & 0x7)
    rs := u4((opcode >> 3) & 0x7)
    offset := (opcode >> 6) & 0x1F

    value := get_reg(cpu, rs)
    carry: bool

    if offset == 0 {
        // ASR #0 means ASR #32
        if (value & 0x80000000) != 0 {
            value = 0xFFFFFFFF
            carry = true
        } else {
            value = 0
            carry = false
        }
    } else {
        carry = (value & (1 << (offset - 1))) != 0
        value = u32(i32(value) >> offset)
    }

    set_reg(cpu, rd, value)
    set_nz_flags(cpu, value)
    set_flag_c(cpu, carry)

    cpu.cycles = 1
}

// ============================================================================
// Format 2: Add/subtract
// ============================================================================

thumb_add_sub :: proc(cpu: ^CPU, mem_bus: ^bus.Bus, opcode: u16) {
    rd := u4(opcode & 0x7)
    rs := u4((opcode >> 3) & 0x7)
    rn_imm := (opcode >> 6) & 0x7
    is_imm := (opcode & (1 << 10)) != 0
    is_sub := (opcode & (1 << 9)) != 0

    rs_val := get_reg(cpu, rs)
    operand: u32 = is_imm ? u32(rn_imm) : get_reg(cpu, u4(rn_imm))

    result: u32
    carry, overflow: bool
    if is_sub {
        result, carry, overflow = sub_with_flags(rs_val, operand)
    } else {
        result, carry, overflow = add_with_flags(rs_val, operand)
    }

    set_reg(cpu, rd, result)
    set_nz_flags(cpu, result)
    set_flag_c(cpu, carry)
    set_flag_v(cpu, overflow)

    cpu.cycles = 1
}

// ============================================================================
// Format 3: Move/compare/add/subtract immediate
// ============================================================================

thumb_mov_imm :: proc(cpu: ^CPU, mem_bus: ^bus.Bus, opcode: u16) {
    rd := u4((opcode >> 8) & 0x7)
    imm := u32(opcode & 0xFF)

    set_reg(cpu, rd, imm)
    set_nz_flags(cpu, imm)

    cpu.cycles = 1
}

thumb_cmp_imm :: proc(cpu: ^CPU, mem_bus: ^bus.Bus, opcode: u16) {
    rd := u4((opcode >> 8) & 0x7)
    imm := u32(opcode & 0xFF)

    rd_val := get_reg(cpu, rd)
    result, carry, overflow := sub_with_flags(rd_val, imm)

    set_nz_flags(cpu, result)
    set_flag_c(cpu, carry)
    set_flag_v(cpu, overflow)

    cpu.cycles = 1
}

thumb_add_imm8 :: proc(cpu: ^CPU, mem_bus: ^bus.Bus, opcode: u16) {
    rd := u4((opcode >> 8) & 0x7)
    imm := u32(opcode & 0xFF)

    rd_val := get_reg(cpu, rd)
    result, carry, overflow := add_with_flags(rd_val, imm)

    set_reg(cpu, rd, result)
    set_nz_flags(cpu, result)
    set_flag_c(cpu, carry)
    set_flag_v(cpu, overflow)

    cpu.cycles = 1
}

thumb_sub_imm8 :: proc(cpu: ^CPU, mem_bus: ^bus.Bus, opcode: u16) {
    rd := u4((opcode >> 8) & 0x7)
    imm := u32(opcode & 0xFF)

    rd_val := get_reg(cpu, rd)
    result, carry, overflow := sub_with_flags(rd_val, imm)

    set_reg(cpu, rd, result)
    set_nz_flags(cpu, result)
    set_flag_c(cpu, carry)
    set_flag_v(cpu, overflow)

    cpu.cycles = 1
}

// ============================================================================
// Format 4: ALU operations
// ============================================================================

thumb_alu :: proc(cpu: ^CPU, mem_bus: ^bus.Bus, opcode: u16) {
    rd := u4(opcode & 0x7)
    rs := u4((opcode >> 3) & 0x7)
    op := (opcode >> 6) & 0xF

    rd_val := get_reg(cpu, rd)
    rs_val := get_reg(cpu, rs)

    result: u32
    carry := get_flag_c(cpu)
    overflow := get_flag_v(cpu)
    write := true

    switch op {
    case 0x0: // AND
        result = rd_val & rs_val
    case 0x1: // EOR
        result = rd_val ~ rs_val
    case 0x2: // LSL
        shift := rs_val & 0xFF
        if shift == 0 {
            result = rd_val
        } else if shift < 32 {
            carry = (rd_val & (1 << (32 - shift))) != 0
            result = rd_val << shift
        } else if shift == 32 {
            carry = (rd_val & 1) != 0
            result = 0
        } else {
            carry = false
            result = 0
        }
    case 0x3: // LSR
        shift := rs_val & 0xFF
        if shift == 0 {
            result = rd_val
        } else if shift < 32 {
            carry = (rd_val & (1 << (shift - 1))) != 0
            result = rd_val >> shift
        } else if shift == 32 {
            carry = (rd_val & 0x80000000) != 0
            result = 0
        } else {
            carry = false
            result = 0
        }
    case 0x4: // ASR
        shift := rs_val & 0xFF
        if shift == 0 {
            result = rd_val
        } else if shift < 32 {
            carry = (rd_val & (1 << (shift - 1))) != 0
            result = u32(i32(rd_val) >> shift)
        } else {
            if (rd_val & 0x80000000) != 0 {
                carry = true
                result = 0xFFFFFFFF
            } else {
                carry = false
                result = 0
            }
        }
    case 0x5: // ADC
        c: u32 = carry ? 1 : 0
        result, carry, overflow = adc_with_flags(rd_val, rs_val, c)
    case 0x6: // SBC
        c: u32 = carry ? 1 : 0
        result, carry, overflow = sbc_with_flags(rd_val, rs_val, c)
    case 0x7: // ROR
        shift := rs_val & 0xFF
        if shift == 0 {
            result = rd_val
        } else {
            effective := shift & 0x1F
            if effective == 0 {
                carry = (rd_val & 0x80000000) != 0
                result = rd_val
            } else {
                carry = (rd_val & (1 << (effective - 1))) != 0
                result = (rd_val >> effective) | (rd_val << (32 - effective))
            }
        }
    case 0x8: // TST
        result = rd_val & rs_val
        write = false
    case 0x9: // NEG
        result, carry, overflow = sub_with_flags(0, rs_val)
    case 0xA: // CMP
        result, carry, overflow = sub_with_flags(rd_val, rs_val)
        write = false
    case 0xB: // CMN
        result, carry, overflow = add_with_flags(rd_val, rs_val)
        write = false
    case 0xC: // ORR
        result = rd_val | rs_val
    case 0xD: // MUL
        result = rd_val * rs_val
    case 0xE: // BIC
        result = rd_val & ~rs_val
    case 0xF: // MVN
        result = ~rs_val
    }

    if write {
        set_reg(cpu, rd, result)
    }

    set_nz_flags(cpu, result)
    set_flag_c(cpu, carry)
    if op == 0x5 || op == 0x6 || op == 0x9 || op == 0xA || op == 0xB {
        set_flag_v(cpu, overflow)
    }

    cpu.cycles = 1
    if op == 0xD {
        cpu.cycles = 2 // MUL takes extra cycles
    }
}

// ============================================================================
// Format 5: Hi register operations / branch exchange
// ============================================================================

thumb_hi_reg :: proc(cpu: ^CPU, mem_bus: ^bus.Bus, opcode: u16) {
    op := (opcode >> 8) & 0x3
    h1 := (opcode & (1 << 7)) != 0
    h2 := (opcode & (1 << 6)) != 0

    rd := u4((opcode & 0x7) | (h1 ? 0x8 : 0))
    rs := u4(((opcode >> 3) & 0x7) | (h2 ? 0x8 : 0))

    rd_val := get_reg(cpu, rd)
    rs_val := get_reg(cpu, rs)

    switch op {
    case 0: // ADD
        // Per ARM7TDMI: when PC is used as operand, bit 0 is cleared
        add_rd := rd == 15 ? (rd_val & ~u32(1)) : rd_val
        add_rs := rs == 15 ? (rs_val & ~u32(1)) : rs_val
        result := add_rd + add_rs
        if rd == 15 {
            // ADD Rd=PC: bits [1:0] of result forced to 0 (word-aligned)
            result &= ~u32(3)
            cpu.cycles = 3
        } else {
            cpu.cycles = 1
        }
        set_reg(cpu, rd, result)
    case 1: // CMP
        // Per ARM7TDMI: when PC is used as operand, bit 0 is cleared
        cmp_rd := rd == 15 ? (rd_val & ~u32(1)) : rd_val
        cmp_rs := rs == 15 ? (rs_val & ~u32(1)) : rs_val
        result, carry, overflow := sub_with_flags(cmp_rd, cmp_rs)
        set_nz_flags(cpu, result)
        set_flag_c(cpu, carry)
        set_flag_v(cpu, overflow)
        cpu.cycles = 1
    case 2: // MOV
        // MOV Rd=PC: value written directly, bit 0 ignored for address (stays in THUMB)
        // Note: In ARMv4T, MOV PC does NOT change state - only BX does
        if rd == 15 {
            set_pc(cpu, rs_val & ~u32(1))
            cpu.cycles = 3
        } else {
            set_reg(cpu, rd, rs_val)
            cpu.cycles = 1
        }
    case 3: // BX / BLX
        // BX does NOT apply alignment - bit 0 determines ARM/Thumb state
        // Check for BLX (H1 bit set on ARMv5+, but on ARMv4 it's just BX)
        if h1 {
            // BLX - store return address
            set_reg(cpu, 14, (get_pc(cpu) - 2) | 1)
        }
        set_thumb(cpu, (rs_val & 1) != 0)
        set_pc(cpu, rs_val & ~u32(1))
        cpu.cycles = 3
    }
}

// ============================================================================
// Format 6: PC-relative load
// ============================================================================

thumb_ldr_pc :: proc(cpu: ^CPU, mem_bus: ^bus.Bus, opcode: u16) {
    rd := u4((opcode >> 8) & 0x7)
    offset := u32(opcode & 0xFF) << 2

    // PC is word-aligned for this calculation
    pc := (cpu.regs[15] + 4) & ~u32(2)
    addr := pc + offset

    value, cycles := bus.read32(mem_bus, addr)
    set_reg(cpu, rd, value)

    cpu.cycles = u32(cycles) + 1
}

// ============================================================================
// Format 7/8: Load/store with register offset
// ============================================================================

thumb_ldr_str_reg :: proc(cpu: ^CPU, mem_bus: ^bus.Bus, opcode: u16) {
    rd := u4(opcode & 0x7)
    rb := u4((opcode >> 3) & 0x7)
    ro := u4((opcode >> 6) & 0x7)

    addr := get_reg(cpu, rb) + get_reg(cpu, ro)

    op := (opcode >> 9) & 0x7

    cycles: u8
    switch op {
    case 0b000: // STR
        cycles = bus.write32(mem_bus, addr, get_reg(cpu, rd))
    case 0b001: // STRH
        if thumb_debug_ldst {
            fmt.printf("  STRH: rd=%d rb=%d ro=%d addr=%08X val=%04X\n",
                rd, rb, ro, addr, u16(get_reg(cpu, rd)))
        }
        cycles = bus.write16(mem_bus, addr, u16(get_reg(cpu, rd)))
    case 0b010: // STRB
        if thumb_debug_ldst {
            fmt.printf("  STRB: rd=%d rb=%d ro=%d addr=%08X val=%02X\n",
                rd, rb, ro, addr, u8(get_reg(cpu, rd)))
        }
        cycles = bus.write8(mem_bus, addr, u8(get_reg(cpu, rd)))
    case 0b011: // LDRSB
        val, c := bus.read8(mem_bus, addr)
        cycles = c
        result: u32 = u32(val)
        if (val & 0x80) != 0 {
            result |= 0xFFFFFF00
        }
        if thumb_debug_ldst {
            fmt.printf("  LDRSB: rd=%d rb=%d ro=%d addr=%08X val=%02X result=%08X\n",
                rd, rb, ro, addr, val, result)
        }
        set_reg(cpu, rd, result)
    case 0b100: // LDR
        val, c := bus.read32(mem_bus, addr)
        cycles = c
        set_reg(cpu, rd, val)
    case 0b101: // LDRH
        val, c := bus.read16(mem_bus, addr)
        cycles = c
        result := u32(val)
        // Misaligned LDRH: rotate result right by 8
        if (addr & 1) != 0 {
            result = (result >> 8) | (result << 24)
        }
        set_reg(cpu, rd, result)
    case 0b110: // LDRB
        val, c := bus.read8(mem_bus, addr)
        cycles = c
        set_reg(cpu, rd, u32(val))
    case 0b111: // LDRSH
        result: u32
        if (addr & 1) != 0 {
            // Misaligned: load byte and sign-extend
            val, c := bus.read8(mem_bus, addr)
            cycles = c
            result = u32(val)
            if (val & 0x80) != 0 {
                result |= 0xFFFFFF00
            }
        } else {
            // Aligned: load halfword and sign-extend
            val, c := bus.read16(mem_bus, addr)
            cycles = c
            result = u32(val)
            if (val & 0x8000) != 0 {
                result |= 0xFFFF0000
            }
        }
        if thumb_debug_ldst {
            fmt.printf("  LDRSH: rd=%d rb=%d ro=%d addr=%08X result=%08X\n",
                rd, rb, ro, addr, result)
        }
        set_reg(cpu, rd, result)
    }

    cpu.cycles = u32(cycles) + 1
}

// ============================================================================
// Format 9: Load/store with immediate offset
// ============================================================================

thumb_ldr_str_imm :: proc(cpu: ^CPU, mem_bus: ^bus.Bus, opcode: u16) {
    rd := u4(opcode & 0x7)
    rb := u4((opcode >> 3) & 0x7)
    offset := (opcode >> 6) & 0x1F

    is_byte := (opcode & (1 << 12)) != 0
    is_load := (opcode & (1 << 11)) != 0

    base := get_reg(cpu, rb)
    addr: u32

    if is_byte {
        addr = base + u32(offset)
    } else {
        addr = base + u32(offset) * 4
    }

    cycles: u8
    if is_load {
        if is_byte {
            val, c := bus.read8(mem_bus, addr)
            cycles = c
            set_reg(cpu, rd, u32(val))
        } else {
            val, c := bus.read32(mem_bus, addr)
            cycles = c
            set_reg(cpu, rd, val)
        }
    } else {
        value := get_reg(cpu, rd)
        if is_byte {
            if thumb_debug_ldst {
                fmt.printf("  STRB(imm): rd=%d rb=%d offset=%d addr=%08X val=%02X\n",
                    rd, rb, offset, addr, u8(value))
            }
            cycles = bus.write8(mem_bus, addr, u8(value))
        } else {
            cycles = bus.write32(mem_bus, addr, value)
        }
    }

    cpu.cycles = u32(cycles) + 1
}

// ============================================================================
// Format 10: Load/store halfword
// ============================================================================

thumb_ldrh_strh_imm :: proc(cpu: ^CPU, mem_bus: ^bus.Bus, opcode: u16) {
    rd := u4(opcode & 0x7)
    rb := u4((opcode >> 3) & 0x7)
    offset := u32((opcode >> 6) & 0x1F) << 1 // Offset * 2

    is_load := (opcode & (1 << 11)) != 0

    addr := get_reg(cpu, rb) + offset

    cycles: u8
    if is_load {
        val, c := bus.read16(mem_bus, addr)
        cycles = c
        set_reg(cpu, rd, u32(val))
    } else {
        cycles = bus.write16(mem_bus, addr, u16(get_reg(cpu, rd)))
    }

    cpu.cycles = u32(cycles) + 1
}

// ============================================================================
// Format 11: SP-relative load/store
// ============================================================================

thumb_ldr_str_sp :: proc(cpu: ^CPU, mem_bus: ^bus.Bus, opcode: u16) {
    rd := u4((opcode >> 8) & 0x7)
    offset := u32(opcode & 0xFF) << 2

    is_load := (opcode & (1 << 11)) != 0

    addr := get_reg(cpu, 13) + offset // r13 = SP

    cycles: u8
    if is_load {
        val, c := bus.read32(mem_bus, addr)
        cycles = c
        set_reg(cpu, rd, val)
    } else {
        cycles = bus.write32(mem_bus, addr, get_reg(cpu, rd))
    }

    cpu.cycles = u32(cycles) + 1
}

// ============================================================================
// Format 12: Load address
// ============================================================================

thumb_load_addr :: proc(cpu: ^CPU, mem_bus: ^bus.Bus, opcode: u16) {
    rd := u4((opcode >> 8) & 0x7)
    offset := u32(opcode & 0xFF) << 2

    is_sp := (opcode & (1 << 11)) != 0

    if is_sp {
        set_reg(cpu, rd, get_reg(cpu, 13) + offset)
    } else {
        // PC is word-aligned
        pc := (cpu.regs[15] + 4) & ~u32(2)
        set_reg(cpu, rd, pc + offset)
    }

    cpu.cycles = 1
}

// ============================================================================
// Format 13: Add offset to stack pointer
// ============================================================================

thumb_add_sp :: proc(cpu: ^CPU, mem_bus: ^bus.Bus, opcode: u16) {
    offset := u32(opcode & 0x7F) << 2
    is_negative := (opcode & (1 << 7)) != 0

    sp := get_reg(cpu, 13)
    if is_negative {
        sp -= offset
    } else {
        sp += offset
    }
    set_reg(cpu, 13, sp)

    cpu.cycles = 1
}

// ============================================================================
// Format 14: Push/pop registers
// ============================================================================

thumb_push_pop :: proc(cpu: ^CPU, mem_bus: ^bus.Bus, opcode: u16) {
    is_pop := (opcode & (1 << 11)) != 0
    has_extra := (opcode & (1 << 8)) != 0 // LR for push, PC for pop
    reg_list := opcode & 0xFF

    // Count registers
    count: u32 = 0
    for i in 0 ..< 8 {
        if (reg_list & (1 << u8(i))) != 0 {
            count += 1
        }
    }
    if has_extra {
        count += 1
    }

    sp := get_reg(cpu, 13)
    cycles: u8 = 0

    if is_pop {
        // POP
        for i in 0 ..< 8 {
            if (reg_list & (1 << u8(i))) != 0 {
                val, c := bus.read32(mem_bus, sp)
                if cycles == 0 {
                    cycles = c
                }
                set_reg(cpu, u4(i), val)
                sp += 4
            }
        }
        if has_extra {
            val, c := bus.read32(mem_bus, sp)
            if cycles == 0 {
                cycles = c
            }
            // Pop to PC, check for ARM/Thumb switch
            set_thumb(cpu, (val & 1) != 0)
            set_pc(cpu, val & ~u32(1))
            sp += 4
        }
    } else {
        // PUSH - decrement first, then store
        if has_extra {
            sp -= 4
            bus.write32(mem_bus, sp, get_reg(cpu, 14)) // LR
        }
        // Push in reverse order (high to low register)
        for i := 7; i >= 0; i -= 1 {
            if (reg_list & (1 << u8(i))) != 0 {
                sp -= 4
                c := bus.write32(mem_bus, sp, get_reg(cpu, u4(i)))
                if cycles == 0 {
                    cycles = c
                }
            }
        }
    }

    set_reg(cpu, 13, sp)

    cpu.cycles = u32(count) + u32(cycles)
    if is_pop && has_extra {
        cpu.cycles += 2 // Pipeline flush for PC load
    }
}

// ============================================================================
// Format 15: Multiple load/store
// ============================================================================

thumb_ldm_stm :: proc(cpu: ^CPU, mem_bus: ^bus.Bus, opcode: u16) {
    rb := u4((opcode >> 8) & 0x7)
    reg_list := opcode & 0xFF
    is_load := (opcode & (1 << 11)) != 0

    addr := get_reg(cpu, rb)
    cycles: u8 = 0
    first := true

    // Count registers
    count: u32 = 0
    for i in 0 ..< 8 {
        if (reg_list & (1 << u8(i))) != 0 {
            count += 1
        }
    }

    // Empty list: weird behavior (store/load r15, add 0x40)
    if count == 0 {
        if is_load {
            val, c := bus.read32(mem_bus, addr)
            set_pc(cpu, val)
            cycles = c
        } else {
            bus.write32(mem_bus, addr, cpu.regs[15] + 4)
        }
        set_reg(cpu, rb, addr + 0x40)
        cpu.cycles = 3
        return
    }

    for i in 0 ..< 8 {
        if (reg_list & (1 << u8(i))) != 0 {
            if is_load {
                val, c := bus.read32(mem_bus, addr)
                if first {
                    cycles = c
                    first = false
                }
                set_reg(cpu, u4(i), val)
            } else {
                c := bus.write32(mem_bus, addr, get_reg(cpu, u4(i)))
                if first {
                    cycles = c
                    first = false
                }
            }
            addr += 4
        }
    }

    // Writeback (but not if rb was in the list for LDMIA)
    if !is_load || (reg_list & (1 << u8(rb))) == 0 {
        set_reg(cpu, rb, addr)
    }

    cpu.cycles = u32(count) + u32(cycles)
}

// ============================================================================
// Format 16: Conditional branch
// ============================================================================

thumb_branch_cond :: proc(cpu: ^CPU, mem_bus: ^bus.Bus, opcode: u16) {
    cond := u4((opcode >> 8) & 0xF)

    if !check_condition(cpu, cond) {
        cpu.cycles = 1
        return
    }

    // Sign-extend 8-bit offset
    offset := i32(i8(opcode & 0xFF)) << 1

    pc := cpu.regs[15] + 4
    new_pc := u32(i32(pc) + offset)
    set_pc(cpu, new_pc)

    cpu.cycles = 3
}

// ============================================================================
// Format 18: Unconditional branch
// ============================================================================

thumb_branch :: proc(cpu: ^CPU, mem_bus: ^bus.Bus, opcode: u16) {
    // Sign-extend 11-bit offset
    offset := u32(opcode & 0x7FF)
    signed_offset: i32
    if (offset & 0x400) != 0 {
        signed_offset = i32(offset | 0xFFFFF800)
    } else {
        signed_offset = i32(offset)
    }
    signed_offset <<= 1

    pc := cpu.regs[15] + 4
    new_pc := u32(i32(pc) + signed_offset)
    set_pc(cpu, new_pc)

    cpu.cycles = 3
}

// ============================================================================
// Format 19: Long branch with link
// ============================================================================

thumb_bl_prefix :: proc(cpu: ^CPU, mem_bus: ^bus.Bus, opcode: u16) {
    // First instruction: LR = PC + (offset << 12)
    offset := u32(opcode & 0x7FF)
    signed_offset: i32
    if (offset & 0x400) != 0 {
        signed_offset = i32(offset | 0xFFFFF800)
    } else {
        signed_offset = i32(offset)
    }

    pc := cpu.regs[15] + 4
    set_reg(cpu, 14, u32(i32(pc) + (signed_offset << 12)))

    cpu.cycles = 1
}

thumb_bl_suffix :: proc(cpu: ^CPU, mem_bus: ^bus.Bus, opcode: u16) {
    // Second instruction: temp = next instr; PC = LR + (offset << 1); LR = temp | 1
    offset := u32(opcode & 0x7FF) << 1

    lr := get_reg(cpu, 14)
    next_instr := cpu.regs[15] + 2

    new_pc := lr + offset
    set_pc(cpu, new_pc)
    set_reg(cpu, 14, next_instr | 1)

    cpu.cycles = 3
}
