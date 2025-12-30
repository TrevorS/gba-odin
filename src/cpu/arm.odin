package cpu

import "../bus"
import "core:fmt"

// Debug flag for ARM load/store (enable for debugging)
arm_debug_ldst := false

// ARM instruction handler type
ARM_Handler :: #type proc(cpu: ^CPU, mem_bus: ^bus.Bus, opcode: u32)

// ARM instruction lookup table (4096 entries)
// Index: ((opcode >> 16) & 0xFF0) | ((opcode >> 4) & 0x00F)
arm_lut: [4096]ARM_Handler

// Initialize ARM lookup table
@(init)
init_arm_lut :: proc "contextless" () {
    // Fill with undefined instruction handler
    for i in 0 ..< 4096 {
        arm_lut[i] = arm_undefined
    }

    // Populate lookup table based on instruction encoding
    for i in 0 ..< 4096 {
        // Decode bits [27:20] from upper 8 bits, [7:4] from lower 4 bits
        bits_27_20 := u32(i >> 4)
        bits_7_4 := u32(i & 0xF)

        handler := decode_arm_instruction(bits_27_20, bits_7_4)
        arm_lut[i] = handler
    }
}

// Decode ARM instruction based on encoding bits
@(private)
decode_arm_instruction :: proc "contextless" (bits_27_20: u32, bits_7_4: u32) -> ARM_Handler {
    bits_27_25 := (bits_27_20 >> 5) & 0x7
    bits_24_20 := bits_27_20 & 0x1F

    switch bits_27_25 {
    case 0b000:
        // Data processing / Multiply / Halfword transfer
        if bits_7_4 == 0b1001 {
            // Multiply or swap
            // MUL/MLA: bits 27-24 = 0000 (bits_24_20 & 0x10 == 0, bit 23 can be 0 or 1)
            // UMULL/UMLAL/SMULL/SMLAL: bits 27-24 = 0000, bit 23 = 1
            // Swap: bits 27-24 = 0001 (bits_24_20 & 0x10 != 0)
            if (bits_24_20 & 0x10) == 0 {
                // bits 24 = 0, includes MUL, MLA, and long multiply
                return arm_multiply
            } else if (bits_24_20 & 0x1B) == 0x10 {
                return arm_swap
            }
            return arm_undefined
        } else if (bits_7_4 & 0x9) == 0x9 {
            // Halfword/signed byte transfer
            return arm_halfword_transfer
        } else if bits_27_20 == 0x12 && bits_7_4 == 0x1 {
            // BX instruction (special encoding that looks like PSR transfer)
            return arm_bx
        } else if (bits_24_20 & 0x19) == 0x10 && bits_7_4 == 0 {
            // PSR transfer: bits [24:23]=10, bit [20]=0, bits [7:4]=0
            // MRS: bit 21 = 0, MSR: bit 21 = 1
            if (bits_24_20 & 0x2) == 0 {
                return arm_mrs
            } else {
                return arm_msr_reg
            }
        } else {
            // Data processing (register)
            return arm_data_processing
        }
    case 0b001:
        // Data processing (immediate) or PSR transfer (immediate)
        if (bits_24_20 & 0x19) == 0x10 {
            // MSR immediate
            return arm_msr_imm
        }
        return arm_data_processing
    case 0b010:
        // Load/store word/byte (immediate offset)
        return arm_single_transfer
    case 0b011:
        if (bits_7_4 & 0x1) == 0 {
            // Load/store word/byte (register offset)
            return arm_single_transfer
        } else {
            // Undefined (media instructions)
            return arm_undefined
        }
    case 0b100:
        // Load/store multiple
        return arm_block_transfer
    case 0b101:
        // Branch / Branch with link
        return arm_branch
    case 0b110:
        // Coprocessor data transfer (unused on GBA)
        return arm_undefined
    case 0b111:
        if (bits_24_20 & 0x10) == 0 {
            // Coprocessor data operation (unused on GBA)
            return arm_undefined
        } else if (bits_27_20 & 0xF0) == 0xF0 {
            // Software interrupt
            return arm_swi
        } else {
            // Coprocessor register transfer (unused on GBA)
            return arm_undefined
        }
    }

    return arm_undefined
}

// Execute ARM instruction
execute_arm :: proc(cpu: ^CPU, mem_bus: ^bus.Bus, opcode: u32) {
    // Check condition
    condition := get_condition_code(opcode)
    if !check_condition(cpu, condition) {
        // Condition failed, just advance PC
        cpu.regs[15] += 4
        cpu.cycles = 1
        return
    }

    // Get handler from LUT
    index := ((opcode >> 16) & 0xFF0) | ((opcode >> 4) & 0x00F)
    handler := arm_lut[index]

    // Execute instruction
    handler(cpu, mem_bus, opcode)

    // Advance PC if not modified by instruction
    if cpu.pipeline_valid {
        cpu.regs[15] += 4
    }
    cpu.pipeline_valid = true
}

// Undefined instruction handler
arm_undefined :: proc(cpu: ^CPU, mem_bus: ^bus.Bus, opcode: u32) {
    undefined(cpu)
}

// Software interrupt
arm_swi :: proc(cpu: ^CPU, mem_bus: ^bus.Bus, opcode: u32) {
    // SWI number is in bits 0-23, but GBA uses bits 16-23
    swi_num := u8((opcode >> 16) & 0xFF)

    // Try HLE first
    if swi_hle(cpu, mem_bus, swi_num) {
        cpu.cycles = 3
        return
    }

    // Fall back to BIOS
    swi(cpu)
    cpu.cycles = 3
}

// Branch / Branch with Link
arm_branch :: proc(cpu: ^CPU, mem_bus: ^bus.Bus, opcode: u32) {
    link := (opcode & (1 << 24)) != 0

    // Get signed 24-bit offset
    offset := opcode & 0x00FFFFFF
    // Sign extend
    if (offset & 0x00800000) != 0 {
        offset |= 0xFF000000
    }
    // Multiply by 4 and cast to signed for addition
    offset_signed := i32(offset) << 2

    pc := cpu.regs[15]

    if link {
        // Save return address (current instruction + 4)
        set_reg(cpu, 14, pc + 4)
    }

    // Calculate new PC: PC + 8 + offset (pipeline)
    new_pc := u32(i32(pc + 8) + offset_signed)
    set_pc(cpu, new_pc)

    cpu.cycles = 3
}

// Branch and Exchange
arm_bx :: proc(cpu: ^CPU, mem_bus: ^bus.Bus, opcode: u32) {
    rm := u4(opcode & 0xF)
    addr := get_reg(cpu, rm)

    // Set Thumb state from bit 0
    set_thumb(cpu, (addr & 1) != 0)

    // Clear bit 0 for actual address
    set_pc(cpu, addr & ~u32(1))

    cpu.cycles = 3
}

// ============================================================================
// Data Processing Instructions
// ============================================================================

// Barrel shifter for operand2
barrel_shift :: proc(cpu: ^CPU, value: u32, shift_type: u32, amount: u32, carry_in: bool, update_carry: bool) -> (result: u32, carry_out: bool) {
    carry_out = carry_in

    if amount == 0 {
        // Special cases for shift amount of 0
        switch shift_type {
        case 0: // LSL #0 = no shift
            result = value
        case 1: // LSR #0 means LSR #32
            result = 0
            if update_carry {
                carry_out = (value & 0x80000000) != 0
            }
        case 2: // ASR #0 means ASR #32
            if (value & 0x80000000) != 0 {
                result = 0xFFFFFFFF
                if update_carry {
                    carry_out = true
                }
            } else {
                result = 0
                if update_carry {
                    carry_out = false
                }
            }
        case 3: // ROR #0 means RRX (rotate right through carry)
            result = (value >> 1) | (carry_in ? 0x80000000 : 0)
            if update_carry {
                carry_out = (value & 1) != 0
            }
        }
        return
    }

    switch shift_type {
    case 0: // LSL
        if amount < 32 {
            result = value << amount
            if update_carry {
                carry_out = (value & (1 << (32 - amount))) != 0
            }
        } else if amount == 32 {
            result = 0
            if update_carry {
                carry_out = (value & 1) != 0
            }
        } else {
            result = 0
            if update_carry {
                carry_out = false
            }
        }
    case 1: // LSR
        if amount < 32 {
            result = value >> amount
            if update_carry {
                carry_out = (value & (1 << (amount - 1))) != 0
            }
        } else if amount == 32 {
            result = 0
            if update_carry {
                carry_out = (value & 0x80000000) != 0
            }
        } else {
            result = 0
            if update_carry {
                carry_out = false
            }
        }
    case 2: // ASR
        if amount < 32 {
            result = u32(i32(value) >> amount)
            if update_carry {
                carry_out = (value & (1 << (amount - 1))) != 0
            }
        } else {
            if (value & 0x80000000) != 0 {
                result = 0xFFFFFFFF
                if update_carry {
                    carry_out = true
                }
            } else {
                result = 0
                if update_carry {
                    carry_out = false
                }
            }
        }
    case 3: // ROR
        effective_amount := amount & 31
        if effective_amount == 0 {
            result = value
            if update_carry {
                carry_out = (value & 0x80000000) != 0
            }
        } else {
            result = (value >> effective_amount) | (value << (32 - effective_amount))
            if update_carry {
                carry_out = (value & (1 << (effective_amount - 1))) != 0
            }
        }
    }

    return
}

// Barrel shifter for register-specified shift amounts (non-zero)
// Different from immediate shifts: no special case for 0, different handling of >= 32
barrel_shift_reg :: proc(cpu: ^CPU, value: u32, shift_type: u32, amount: u32, carry_in: bool, update_carry: bool) -> (result: u32, carry_out: bool) {
    carry_out = carry_in

    switch shift_type {
    case 0: // LSL
        if amount < 32 {
            result = value << amount
            if update_carry {
                carry_out = (value & (1 << (32 - amount))) != 0
            }
        } else if amount == 32 {
            result = 0
            if update_carry {
                carry_out = (value & 1) != 0
            }
        } else { // > 32
            result = 0
            if update_carry {
                carry_out = false
            }
        }
    case 1: // LSR
        if amount < 32 {
            result = value >> amount
            if update_carry {
                carry_out = (value & (1 << (amount - 1))) != 0
            }
        } else if amount == 32 {
            result = 0
            if update_carry {
                carry_out = (value & 0x80000000) != 0
            }
        } else { // > 32
            result = 0
            if update_carry {
                carry_out = false
            }
        }
    case 2: // ASR
        if amount < 32 {
            result = u32(i32(value) >> amount)
            if update_carry {
                carry_out = (value & (1 << (amount - 1))) != 0
            }
        } else { // >= 32
            if (value & 0x80000000) != 0 {
                result = 0xFFFFFFFF
                if update_carry {
                    carry_out = true
                }
            } else {
                result = 0
                if update_carry {
                    carry_out = false
                }
            }
        }
    case 3: // ROR
        if amount == 0 {
            // ROR by 0 from register = no rotation
            result = value
        } else {
            effective_amount := amount & 31
            if effective_amount == 0 {
                result = value
                if update_carry {
                    carry_out = (value & 0x80000000) != 0
                }
            } else {
                result = (value >> effective_amount) | (value << (32 - effective_amount))
                if update_carry {
                    carry_out = (value & (1 << (effective_amount - 1))) != 0
                }
            }
        }
    }

    return
}

// Get operand2 for data processing instructions
get_operand2 :: proc(cpu: ^CPU, opcode: u32, update_carry: bool) -> (value: u32, carry: bool) {
    carry = get_flag_c(cpu)

    if (opcode & (1 << 25)) != 0 {
        // Immediate operand
        imm := opcode & 0xFF
        rotate := (opcode >> 8) & 0xF
        rotate_amount := rotate * 2

        if rotate_amount != 0 {
            value = (imm >> rotate_amount) | (imm << (32 - rotate_amount))
            if update_carry {
                carry = (value & 0x80000000) != 0
            }
        } else {
            value = imm
        }
    } else {
        // Register operand with shift
        rm := u4(opcode & 0xF)
        rm_value := get_reg(cpu, rm)

        shift_type := (opcode >> 5) & 0x3

        if (opcode & (1 << 4)) != 0 {
            // Shift by register
            rs := u4((opcode >> 8) & 0xF)
            shift_amount := get_reg(cpu, rs) & 0xFF

            // When Rm is PC in a register shift, PC reads as PC+12 (extra 4 bytes)
            if rm == 15 {
                rm_value += 4
            }

            // Register shift by 0: no shift, carry unchanged
            if shift_amount == 0 {
                value = rm_value
                // carry already set to current C flag
            } else {
                value, carry = barrel_shift_reg(cpu, rm_value, shift_type, shift_amount, carry, update_carry)
            }
        } else {
            // Shift by immediate (amount 0 has special meanings)
            shift_amount := (opcode >> 7) & 0x1F
            value, carry = barrel_shift(cpu, rm_value, shift_type, shift_amount, carry, update_carry)
        }
    }

    return
}

// Data processing instruction
arm_data_processing :: proc(cpu: ^CPU, mem_bus: ^bus.Bus, opcode: u32) {
    // Note: BX is now handled directly in the LUT

    op := (opcode >> 21) & 0xF
    s := (opcode & (1 << 20)) != 0
    rn := u4((opcode >> 16) & 0xF)
    rd := u4((opcode >> 12) & 0xF)

    rn_value := get_reg(cpu, rn)

    // When using register shift (bit 25=0, bit 4=1) and Rn is PC, PC reads as PC+12
    // (extra cycle for register shift advances PC by 4)
    is_register_shift := (opcode & (1 << 25)) == 0 && (opcode & (1 << 4)) != 0
    if is_register_shift && rn == 15 {
        rn_value += 4
    }

    operand2, shifter_carry := get_operand2(cpu, opcode, s)

    result: u32
    write_result := true
    carry := get_flag_c(cpu)
    overflow := get_flag_v(cpu)

    switch op {
    case 0x0: // AND
        result = rn_value & operand2
        carry = shifter_carry
    case 0x1: // EOR
        result = rn_value ~ operand2
        carry = shifter_carry
    case 0x2: // SUB
        result, carry, overflow = sub_with_flags(rn_value, operand2)
    case 0x3: // RSB
        result, carry, overflow = sub_with_flags(operand2, rn_value)
    case 0x4: // ADD
        result, carry, overflow = add_with_flags(rn_value, operand2)
    case 0x5: // ADC
        c: u32 = get_flag_c(cpu) ? 1 : 0
        result, carry, overflow = adc_with_flags(rn_value, operand2, c)
    case 0x6: // SBC
        c: u32 = get_flag_c(cpu) ? 1 : 0
        result, carry, overflow = sbc_with_flags(rn_value, operand2, c)
    case 0x7: // RSC
        c: u32 = get_flag_c(cpu) ? 1 : 0
        result, carry, overflow = sbc_with_flags(operand2, rn_value, c)
    case 0x8: // TST
        result = rn_value & operand2
        carry = shifter_carry
        write_result = false
    case 0x9: // TEQ
        result = rn_value ~ operand2
        carry = shifter_carry
        write_result = false
    case 0xA: // CMP
        result, carry, overflow = sub_with_flags(rn_value, operand2)
        write_result = false
    case 0xB: // CMN
        result, carry, overflow = add_with_flags(rn_value, operand2)
        write_result = false
    case 0xC: // ORR
        result = rn_value | operand2
        carry = shifter_carry
    case 0xD: // MOV
        result = operand2
        carry = shifter_carry
    case 0xE: // BIC
        result = rn_value & ~operand2
        carry = shifter_carry
    case 0xF: // MVN
        result = ~operand2
        carry = shifter_carry
    }

    if write_result {
        set_reg(cpu, rd, result)
    }

    if s {
        if rd == 15 {
            // Writing to PC with S bit: restore CPSR from SPSR
            set_cpsr(cpu, get_spsr(cpu))
        } else {
            set_nz_flags(cpu, result)
            set_flag_c(cpu, carry)
            if op >= 0x2 && op <= 0x7 || op == 0xA || op == 0xB {
                set_flag_v(cpu, overflow)
            }
        }
    }

    cpu.cycles = 1
    if (opcode & (1 << 4)) != 0 && (opcode & (1 << 25)) == 0 {
        cpu.cycles += 1 // Extra cycle for register shift
    }
    if rd == 15 && write_result {
        cpu.cycles += 2 // Pipeline flush
    }
}

// Helper functions for arithmetic with flags
add_with_flags :: proc(a, b: u32) -> (result: u32, carry, overflow: bool) {
    result = a + b
    carry = result < a
    // Overflow: signs of operands same but result different
    overflow = ((a ~ result) & (b ~ result) & 0x80000000) != 0
    return
}

sub_with_flags :: proc(a, b: u32) -> (result: u32, carry, overflow: bool) {
    result = a - b
    carry = a >= b
    // Overflow: signs of operands different and result has sign of b
    overflow = ((a ~ b) & (a ~ result) & 0x80000000) != 0
    return
}

adc_with_flags :: proc(a, b, c: u32) -> (result: u32, carry, overflow: bool) {
    temp := u64(a) + u64(b) + u64(c)
    result = u32(temp)
    carry = temp > 0xFFFFFFFF
    overflow = ((a ~ result) & (b ~ result) & 0x80000000) != 0
    return
}

sbc_with_flags :: proc(a, b, c: u32) -> (result: u32, carry, overflow: bool) {
    // SBC: a - b - !c = a - b - 1 + c
    borrow: u32 = c != 0 ? 0 : 1
    result = a - b - borrow
    carry = u64(a) >= u64(b) + u64(borrow)
    overflow = ((a ~ b) & (a ~ result) & 0x80000000) != 0
    return
}

// ============================================================================
// MRS/MSR Instructions
// ============================================================================

arm_mrs :: proc(cpu: ^CPU, mem_bus: ^bus.Bus, opcode: u32) {
    rd := u4((opcode >> 12) & 0xF)
    use_spsr := (opcode & (1 << 22)) != 0

    if use_spsr {
        set_reg(cpu, rd, get_spsr(cpu))
    } else {
        set_reg(cpu, rd, get_cpsr(cpu))
    }

    cpu.cycles = 1
}

arm_msr_reg :: proc(cpu: ^CPU, mem_bus: ^bus.Bus, opcode: u32) {
    use_spsr := (opcode & (1 << 22)) != 0
    rm := u4(opcode & 0xF)
    value := get_reg(cpu, rm)

    msr_write(cpu, opcode, value, use_spsr)
    cpu.cycles = 1
}

arm_msr_imm :: proc(cpu: ^CPU, mem_bus: ^bus.Bus, opcode: u32) {
    use_spsr := (opcode & (1 << 22)) != 0

    imm := opcode & 0xFF
    rotate := (opcode >> 8) & 0xF
    rotate_amount := rotate * 2

    value: u32
    if rotate_amount != 0 {
        value = (imm >> rotate_amount) | (imm << (32 - rotate_amount))
    } else {
        value = imm
    }

    msr_write(cpu, opcode, value, use_spsr)
    cpu.cycles = 1
}

msr_write :: proc(cpu: ^CPU, opcode: u32, value: u32, use_spsr: bool) {
    // Field mask
    mask: u32 = 0
    if (opcode & (1 << 19)) != 0 {
        mask |= 0xFF000000
    } // f - flags
    if (opcode & (1 << 18)) != 0 {
        mask |= 0x00FF0000
    } // s - status
    if (opcode & (1 << 17)) != 0 {
        mask |= 0x0000FF00
    } // x - extension
    if (opcode & (1 << 16)) != 0 {
        mask |= 0x000000FF
    } // c - control

    // In User mode, only flags can be modified
    mode := get_mode(cpu)
    if mode == .User {
        mask &= 0xFF000000
    }

    if use_spsr {
        old := get_spsr(cpu)
        set_spsr(cpu, (old & ~mask) | (value & mask))
    } else {
        old := get_cpsr(cpu)
        set_cpsr(cpu, (old & ~mask) | (value & mask))
    }
}

// ============================================================================
// Multiply Instructions
// ============================================================================

arm_multiply :: proc(cpu: ^CPU, mem_bus: ^bus.Bus, opcode: u32) {
    // Decode multiply variant
    accumulate := (opcode & (1 << 21)) != 0
    set_flags := (opcode & (1 << 20)) != 0
    long_mul := (opcode & (1 << 23)) != 0
    signed_mul := (opcode & (1 << 22)) != 0

    rm := u4(opcode & 0xF)
    rs := u4((opcode >> 8) & 0xF)
    rn := u4((opcode >> 12) & 0xF)
    rd := u4((opcode >> 16) & 0xF)

    rm_val := get_reg(cpu, rm)
    rs_val := get_reg(cpu, rs)

    if long_mul {
        // 64-bit multiply
        result: u64
        if signed_mul {
            result = u64(i64(i32(rm_val)) * i64(i32(rs_val)))
        } else {
            result = u64(rm_val) * u64(rs_val)
        }

        if accumulate {
            acc := (u64(get_reg(cpu, rd)) << 32) | u64(get_reg(cpu, rn))
            result += acc
        }

        // rd is RdHi, rn is RdLo
        set_reg(cpu, rn, u32(result))
        set_reg(cpu, rd, u32(result >> 32))

        if set_flags {
            set_flag_n(cpu, (result & 0x8000000000000000) != 0)
            set_flag_z(cpu, result == 0)
        }
    } else {
        // 32-bit multiply
        result := rm_val * rs_val

        if accumulate {
            result += get_reg(cpu, rn)
        }

        set_reg(cpu, rd, result)

        if set_flags {
            set_nz_flags(cpu, result)
        }
    }

    // Multiply timing depends on operand size (simplified)
    cpu.cycles = 2
}

// ============================================================================
// Swap Instructions
// ============================================================================

arm_swap :: proc(cpu: ^CPU, mem_bus: ^bus.Bus, opcode: u32) {
    byte_swap := (opcode & (1 << 22)) != 0

    rm := u4(opcode & 0xF)
    rd := u4((opcode >> 12) & 0xF)
    rn := u4((opcode >> 16) & 0xF)

    addr := get_reg(cpu, rn)
    source := get_reg(cpu, rm)

    if byte_swap {
        // SWPB
        old_val, cycles := bus.read8(mem_bus, addr)
        bus.write8(mem_bus, addr, u8(source))
        set_reg(cpu, rd, u32(old_val))
        cpu.cycles = 4 + u32(cycles)
    } else {
        // SWP
        old_val, cycles := bus.read32(mem_bus, addr)
        bus.write32(mem_bus, addr, source)
        set_reg(cpu, rd, old_val)
        cpu.cycles = 4 + u32(cycles)
    }
}

// ============================================================================
// Single Data Transfer (LDR/STR)
// ============================================================================

arm_single_transfer :: proc(cpu: ^CPU, mem_bus: ^bus.Bus, opcode: u32) {
    is_load := (opcode & (1 << 20)) != 0
    is_byte := (opcode & (1 << 22)) != 0
    writeback := (opcode & (1 << 21)) != 0
    add_offset := (opcode & (1 << 23)) != 0
    pre_indexed := (opcode & (1 << 24)) != 0
    is_reg_offset := (opcode & (1 << 25)) != 0

    rn := u4((opcode >> 16) & 0xF)
    rd := u4((opcode >> 12) & 0xF)

    base := get_reg(cpu, rn)

    // Calculate offset
    offset: u32
    if is_reg_offset {
        rm := u4(opcode & 0xF)
        rm_val := get_reg(cpu, rm)

        shift_type := (opcode >> 5) & 0x3
        shift_amount := (opcode >> 7) & 0x1F

        // Use actual carry flag for RRX (shift_type=3, shift_amount=0)
        carry := get_flag_c(cpu)
        offset, _ = barrel_shift(cpu, rm_val, shift_type, shift_amount, carry, false)
    } else {
        offset = opcode & 0xFFF
    }

    // Calculate address
    addr: u32
    if pre_indexed {
        if add_offset {
            addr = base + offset
        } else {
            addr = base - offset
        }
    } else {
        addr = base
    }

    // Perform transfer
    cycles: u8 = 0
    if is_load {
        value: u32
        if is_byte {
            val, c := bus.read8(mem_bus, addr)
            value = u32(val)
            cycles = c
        } else {
            value, cycles = bus.read32(mem_bus, addr)
        }
        set_reg(cpu, rd, value)
    } else {
        value := get_reg(cpu, rd)
        // STR Rd=PC stores PC+12
        if rd == 15 {
            value += 4
        }
        if is_byte {
            if arm_debug_ldst {
                fmt.printf("  ARM STRB: rd=%d rn=%d addr=%08X val=%02X\n",
                    rd, rn, addr, u8(value))
            }
            cycles = bus.write8(mem_bus, addr, u8(value))
        } else {
            cycles = bus.write32(mem_bus, addr, value)
        }
    }

    // Writeback
    // For loads, don't writeback if rd == rn (loaded value takes precedence)
    should_writeback := !is_load || rd != rn
    if !pre_indexed && should_writeback {
        // Post-indexed always writes back
        if add_offset {
            base += offset
        } else {
            base -= offset
        }
        set_reg(cpu, rn, base)
    } else if writeback && should_writeback {
        set_reg(cpu, rn, addr)
    }

    cpu.cycles = u32(cycles) + 1
    if is_load && rd == 15 {
        cpu.cycles += 2
    }
}

// ============================================================================
// Halfword and Signed Data Transfer
// ============================================================================

arm_halfword_transfer :: proc(cpu: ^CPU, mem_bus: ^bus.Bus, opcode: u32) {
    is_load := (opcode & (1 << 20)) != 0
    writeback := (opcode & (1 << 21)) != 0
    imm_offset := (opcode & (1 << 22)) != 0
    add_offset := (opcode & (1 << 23)) != 0
    pre_indexed := (opcode & (1 << 24)) != 0
    sh := (opcode >> 5) & 0x3 // 01=H, 10=SB, 11=SH

    rn := u4((opcode >> 16) & 0xF)
    rd := u4((opcode >> 12) & 0xF)

    base := get_reg(cpu, rn)

    // Calculate offset
    offset: u32
    if imm_offset {
        offset = ((opcode >> 4) & 0xF0) | (opcode & 0xF)
    } else {
        rm := u4(opcode & 0xF)
        offset = get_reg(cpu, rm)
    }

    // Calculate address
    addr: u32
    if pre_indexed {
        if add_offset {
            addr = base + offset
        } else {
            addr = base - offset
        }
    } else {
        addr = base
    }

    cycles: u8 = 0
    if is_load {
        value: u32
        switch sh {
        case 0b01: // LDRH
            val, c := bus.read16(mem_bus, addr)
            value = u32(val)
            // For misaligned LDRH, rotate the 32-bit result right by 8
            if (addr & 1) != 0 {
                value = (value >> 8) | (value << 24)
            }
            cycles = c
            if arm_debug_ldst {
                fmt.printf("  ARM LDRH: rd=%d rn=%d addr=%08X val=%04X result=%08X\n",
                    rd, rn, addr, val, value)
            }
        case 0b10: // LDRSB
            val, c := bus.read8(mem_bus, addr)
            // Sign extend
            if (val & 0x80) != 0 {
                value = u32(val) | 0xFFFFFF00
            } else {
                value = u32(val)
            }
            cycles = c
            if arm_debug_ldst {
                fmt.printf("  ARM LDRSB: rd=%d rn=%d addr=%08X val=%02X result=%08X\n",
                    rd, rn, addr, val, value)
            }
        case 0b11: // LDRSH
            // For misaligned LDRSH, act like LDRSB (sign-extend byte)
            if (addr & 1) != 0 {
                val, c := bus.read8(mem_bus, addr)
                if (val & 0x80) != 0 {
                    value = u32(val) | 0xFFFFFF00
                } else {
                    value = u32(val)
                }
                cycles = c
                if arm_debug_ldst {
                    fmt.printf("  ARM LDRSH (misaligned->LDRSB): rd=%d rn=%d addr=%08X val=%02X result=%08X\n",
                        rd, rn, addr, val, value)
                }
            } else {
                val, c := bus.read16(mem_bus, addr)
                // Sign extend
                if (val & 0x8000) != 0 {
                    value = u32(val) | 0xFFFF0000
                } else {
                    value = u32(val)
                }
                cycles = c
                if arm_debug_ldst {
                    fmt.printf("  ARM LDRSH: rd=%d rn=%d addr=%08X val=%04X result=%08X\n",
                        rd, rn, addr, val, value)
                }
            }
        }
        set_reg(cpu, rd, value)
    } else {
        // Store halfword
        value := get_reg(cpu, rd)
        if arm_debug_ldst {
            fmt.printf("  ARM STRH: rd=%d rn=%d addr=%08X val=%04X\n",
                rd, rn, addr, u16(value))
        }
        cycles = bus.write16(mem_bus, addr, u16(value))
    }

    // Writeback
    // For loads, don't writeback if rd == rn (loaded value takes precedence)
    should_writeback := !is_load || rd != rn
    if !pre_indexed && should_writeback {
        if add_offset {
            base += offset
        } else {
            base -= offset
        }
        set_reg(cpu, rn, base)
    } else if writeback && should_writeback {
        set_reg(cpu, rn, addr)
    }

    cpu.cycles = u32(cycles) + 1
    if is_load && rd == 15 {
        cpu.cycles += 2
    }
}

// ============================================================================
// Block Data Transfer (LDM/STM)
// ============================================================================

arm_block_transfer :: proc(cpu: ^CPU, mem_bus: ^bus.Bus, opcode: u32) {
    is_load := (opcode & (1 << 20)) != 0
    writeback := (opcode & (1 << 21)) != 0
    user_mode := (opcode & (1 << 22)) != 0
    add_offset := (opcode & (1 << 23)) != 0
    pre_indexed := (opcode & (1 << 24)) != 0

    rn := u4((opcode >> 16) & 0xF)
    reg_list := u16(opcode & 0xFFFF)

    // Get original base for writeback calculation
    original_base := get_reg(cpu, rn)
    // LDM/STM force word alignment for actual transfers (ignore lower 2 bits)
    base := original_base & ~u32(3)

    // Count registers
    count: u32 = 0
    for i in 0 ..< 16 {
        if (reg_list & (1 << u16(i))) != 0 {
            count += 1
        }
    }

    // Empty list behavior: transfer PC and adjust base by 0x40
    empty_list := count == 0
    if empty_list {
        count = 16 // Base adjustment is 0x40 (16 * 4)
    }

    // Calculate start address based on mode
    addr: u32
    if add_offset {
        if pre_indexed {
            addr = base + 4 // IB
        } else {
            addr = base // IA
        }
    } else {
        if pre_indexed {
            addr = base - count * 4 // DB
        } else {
            addr = base - count * 4 + 4 // DA
        }
    }

    // Calculate final base for writeback (uses original unaligned base)
    final_base: u32
    if add_offset {
        final_base = original_base + count * 4
    } else {
        final_base = original_base - count * 4
    }

    // Handle user mode transfer
    old_mode := get_mode(cpu)
    if user_mode && (!is_load || (reg_list & 0x8000) == 0) {
        set_mode(cpu, .User)
    }

    // Transfer registers
    cycles: u8 = 0
    if empty_list {
        // Empty register list: load/store only PC
        if is_load {
            value, c := bus.read32(mem_bus, addr)
            set_reg(cpu, 15, value)
            cycles = c
        } else {
            value := get_reg(cpu, 15) + 4 // Store PC+12
            cycles = bus.write32(mem_bus, addr, value)
        }
    } else {
        // Find lowest register in list (for base-in-rlist handling)
        lowest_reg := -1
        for i in 0 ..< 16 {
            if (reg_list & (1 << u16(i))) != 0 {
                lowest_reg = i
                break
            }
        }

        first := true
        for i in 0 ..< 16 {
            if (reg_list & (1 << u16(i))) != 0 {
                if is_load {
                    value, c := bus.read32(mem_bus, addr)
                    set_reg(cpu, u4(i), value)
                    if first {
                        cycles = c
                        first = false
                    }
                } else {
                    value := get_reg(cpu, u4(i))
                    // STM with PC stores PC+12 (get_reg returns PC+8, add 4 more)
                    if i == 15 {
                        value += 4
                    }
                    // STM with base in rlist: if base is NOT lowest, store final base value
                    if writeback && u4(i) == rn && i != lowest_reg {
                        value = final_base
                    }
                    c := bus.write32(mem_bus, addr, value)
                    if first {
                        cycles = c
                        first = false
                    }
                }
                addr += 4
            }
        }
    }

    // Restore mode if changed
    if user_mode && (!is_load || (reg_list & 0x8000) == 0) {
        set_mode(cpu, old_mode)
    }

    // Writeback (not if base is in register list for LDM)
    if writeback {
        if !is_load || (reg_list & (1 << u16(rn))) == 0 {
            set_reg(cpu, rn, final_base)
        }
    }

    // If loading PC with S bit, restore CPSR from SPSR
    if is_load && (reg_list & 0x8000) != 0 && user_mode {
        set_cpsr(cpu, get_spsr(cpu))
    }

    cpu.cycles = u32(count) + u32(cycles)
    if is_load && (reg_list & 0x8000) != 0 {
        cpu.cycles += 2
    }
}
