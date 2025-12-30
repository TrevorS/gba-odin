package cpu

import "core:fmt"
import "core:strings"

// =============================================================================
// ARM (32-bit) Opcode Metadata and Disassembly
// =============================================================================
//
// ARM instruction encoding (32-bit):
//   [31:28] Condition code
//   [27:25] Instruction category
//   [24:20] Opcode / flags
//   [19:16] First operand register (Rn)
//   [15:12] Destination register (Rd)
//   [11:0]  Operand 2 (immediate or register with shift)
//
// Future use cases:
// - Disassembly and debugging
// - Instruction tracing with readable output
// - Test coverage analysis
// - Documentation generation
//

// =============================================================================
// Condition Codes (bits [31:28])
// =============================================================================

Condition :: enum u8 {
    EQ = 0x0,   // Equal (Z set)
    NE = 0x1,   // Not equal (Z clear)
    CS = 0x2,   // Carry set / unsigned higher or same (C set)
    CC = 0x3,   // Carry clear / unsigned lower (C clear)
    MI = 0x4,   // Minus / negative (N set)
    PL = 0x5,   // Plus / positive or zero (N clear)
    VS = 0x6,   // Overflow (V set)
    VC = 0x7,   // No overflow (V clear)
    HI = 0x8,   // Unsigned higher (C set and Z clear)
    LS = 0x9,   // Unsigned lower or same (C clear or Z set)
    GE = 0xA,   // Signed greater or equal (N == V)
    LT = 0xB,   // Signed less than (N != V)
    GT = 0xC,   // Signed greater than (Z clear and N == V)
    LE = 0xD,   // Signed less or equal (Z set or N != V)
    AL = 0xE,   // Always (unconditional)
    NV = 0xF,   // Never (reserved, do not use)
}

CONDITION_NAMES := [16]string{
    "EQ", "NE", "CS", "CC", "MI", "PL", "VS", "VC",
    "HI", "LS", "GE", "LT", "GT", "LE", "",   "NV",
}

// =============================================================================
// ARM Instruction Formats (derived from bits [27:25] and sub-fields)
// =============================================================================

ARM_Format :: enum u8 {
    Data_Processing,     // AND, EOR, SUB, RSB, ADD, ADC, SBC, RSC, TST, TEQ, CMP, CMN, ORR, MOV, BIC, MVN
    Multiply,            // MUL, MLA
    Multiply_Long,       // UMULL, UMLAL, SMULL, SMLAL
    Swap,                // SWP, SWPB
    Branch_Exchange,     // BX
    Halfword_Transfer,   // LDRH, STRH, LDRSB, LDRSH
    Single_Transfer,     // LDR, STR, LDRB, STRB
    Block_Transfer,      // LDM, STM
    Branch,              // B, BL
    Coprocessor,         // CDP, LDC, STC, MRC, MCR (unused on GBA)
    Software_Interrupt,  // SWI
    PSR_Transfer,        // MRS, MSR
    Undefined,           // Undefined instruction
}

// =============================================================================
// Data Processing Opcodes (bits [24:21])
// =============================================================================

ALU_Op :: enum u8 {
    AND = 0x0,  // Rd = Rn AND Op2
    EOR = 0x1,  // Rd = Rn XOR Op2
    SUB = 0x2,  // Rd = Rn - Op2
    RSB = 0x3,  // Rd = Op2 - Rn
    ADD = 0x4,  // Rd = Rn + Op2
    ADC = 0x5,  // Rd = Rn + Op2 + C
    SBC = 0x6,  // Rd = Rn - Op2 + C - 1
    RSC = 0x7,  // Rd = Op2 - Rn + C - 1
    TST = 0x8,  // Test (Rn AND Op2, flags only)
    TEQ = 0x9,  // Test equal (Rn XOR Op2, flags only)
    CMP = 0xA,  // Compare (Rn - Op2, flags only)
    CMN = 0xB,  // Compare negative (Rn + Op2, flags only)
    ORR = 0xC,  // Rd = Rn OR Op2
    MOV = 0xD,  // Rd = Op2
    BIC = 0xE,  // Rd = Rn AND NOT Op2
    MVN = 0xF,  // Rd = NOT Op2
}

ALU_OP_NAMES := [16]string{
    "AND", "EOR", "SUB", "RSB", "ADD", "ADC", "SBC", "RSC",
    "TST", "TEQ", "CMP", "CMN", "ORR", "MOV", "BIC", "MVN",
}

// =============================================================================
// Shift Types (bits [6:5] in register operand)
// =============================================================================

Shift_Type :: enum u8 {
    LSL = 0,  // Logical shift left
    LSR = 1,  // Logical shift right
    ASR = 2,  // Arithmetic shift right
    ROR = 3,  // Rotate right (RRX when shift amount is 0)
}

SHIFT_NAMES := [4]string{"LSL", "LSR", "ASR", "ROR"}

// =============================================================================
// Register Names
// =============================================================================

REGISTER_NAMES := [16]string{
    "R0", "R1", "R2", "R3", "R4", "R5", "R6", "R7",
    "R8", "R9", "R10", "R11", "R12", "SP", "LR", "PC",
}

// =============================================================================
// ARM Disassembly Functions
// =============================================================================

// Disassemble an ARM instruction to a human-readable string
// Returns a string like "ADDS R0, R1, #0x10" or "LDREQ R0, [R1, #4]"
disassemble_arm :: proc(opcode: u32, allocator := context.allocator) -> string {
    context.allocator = allocator

    cond := (opcode >> 28) & 0xF
    cond_str := cond == 0xE ? "" : CONDITION_NAMES[cond]

    // Decode instruction format from bits [27:25]
    bits_27_25 := (opcode >> 25) & 0x7

    switch bits_27_25 {
    case 0b000, 0b001:
        return disasm_data_processing(opcode, cond_str)
    case 0b010, 0b011:
        return disasm_single_transfer(opcode, cond_str)
    case 0b100:
        return disasm_block_transfer(opcode, cond_str)
    case 0b101:
        return disasm_branch(opcode, cond_str)
    case 0b110:
        return fmt.aprintf("CDP%s <coprocessor>", cond_str)
    case 0b111:
        if (opcode & 0x0F000000) == 0x0F000000 {
            return disasm_swi(opcode, cond_str)
        }
        return fmt.aprintf("MRC/MCR%s <coprocessor>", cond_str)
    }

    return "???"
}

// Disassemble data processing / multiply / PSR transfer
@(private)
disasm_data_processing :: proc(opcode: u32, cond_str: string) -> string {
    bits_27_20 := (opcode >> 20) & 0xFF
    bits_7_4 := (opcode >> 4) & 0xF

    // Check for special instructions
    if bits_7_4 == 0b1001 {
        // Multiply or swap
        if (bits_27_20 & 0xF0) == 0x00 {
            return disasm_multiply(opcode, cond_str)
        } else if (bits_27_20 & 0xFB) == 0x10 {
            return disasm_swap(opcode, cond_str)
        }
    }

    if (bits_7_4 & 0x9) == 0x9 && (bits_27_20 & 0xE0) == 0x00 {
        return disasm_halfword_transfer(opcode, cond_str)
    }

    if bits_27_20 == 0x12 && bits_7_4 == 0x1 {
        return disasm_bx(opcode, cond_str)
    }

    if (bits_27_20 & 0xF9) == 0x10 && bits_7_4 == 0 {
        return disasm_psr_transfer(opcode, cond_str)
    }

    // Regular data processing
    alu_op := ALU_Op((opcode >> 21) & 0xF)
    s_bit := ((opcode >> 20) & 1) != 0
    rd := (opcode >> 12) & 0xF
    rn := (opcode >> 16) & 0xF

    op_name := ALU_OP_NAMES[u8(alu_op)]
    s_str := s_bit ? "S" : ""

    // Get operand 2
    op2_str := disasm_operand2(opcode)

    // Format based on instruction type
    #partial switch alu_op {
    case .MOV, .MVN:
        // Rd, Op2
        return fmt.aprintf("%s%s%s %s, %s", op_name, cond_str, s_str,
            REGISTER_NAMES[rd], op2_str)
    case .TST, .TEQ, .CMP, .CMN:
        // Rn, Op2 (no Rd, always sets flags)
        return fmt.aprintf("%s%s %s, %s", op_name, cond_str,
            REGISTER_NAMES[rn], op2_str)
    case:
        // Rd, Rn, Op2
        return fmt.aprintf("%s%s%s %s, %s, %s", op_name, cond_str, s_str,
            REGISTER_NAMES[rd], REGISTER_NAMES[rn], op2_str)
    }
}

// Disassemble operand 2 (immediate or register with shift)
@(private)
disasm_operand2 :: proc(opcode: u32) -> string {
    if ((opcode >> 25) & 1) != 0 {
        // Immediate
        imm := opcode & 0xFF
        rotate := ((opcode >> 8) & 0xF) * 2
        value := (imm >> rotate) | (imm << (32 - rotate))
        return fmt.aprintf("#0x%X", value)
    } else {
        // Register with shift
        rm := opcode & 0xF
        shift_type := Shift_Type((opcode >> 5) & 0x3)

        if ((opcode >> 4) & 1) != 0 {
            // Shift by register
            rs := (opcode >> 8) & 0xF
            if shift_type == .LSL && rs == 0 {
                return fmt.aprintf("%s", REGISTER_NAMES[rm])
            }
            return fmt.aprintf("%s, %s %s", REGISTER_NAMES[rm],
                SHIFT_NAMES[u8(shift_type)], REGISTER_NAMES[rs])
        } else {
            // Shift by immediate
            shift_amt := (opcode >> 7) & 0x1F
            if shift_amt == 0 && shift_type == .LSL {
                return fmt.aprintf("%s", REGISTER_NAMES[rm])
            }
            if shift_amt == 0 && shift_type == .ROR {
                return fmt.aprintf("%s, RRX", REGISTER_NAMES[rm])
            }
            return fmt.aprintf("%s, %s #%d", REGISTER_NAMES[rm],
                SHIFT_NAMES[u8(shift_type)], shift_amt)
        }
    }
}

// Disassemble multiply instructions
@(private)
disasm_multiply :: proc(opcode: u32, cond_str: string) -> string {
    rd := (opcode >> 16) & 0xF
    rn := (opcode >> 12) & 0xF
    rs := (opcode >> 8) & 0xF
    rm := opcode & 0xF
    s_bit := ((opcode >> 20) & 1) != 0
    a_bit := ((opcode >> 21) & 1) != 0
    u_bit := ((opcode >> 22) & 1) != 0
    l_bit := ((opcode >> 23) & 1) != 0
    s_str := s_bit ? "S" : ""

    if l_bit {
        // Long multiply
        rdhi := rd
        rdlo := rn
        sign_str := u_bit ? "S" : "U"
        acc_str := a_bit ? "AL" : "LL"
        return fmt.aprintf("%sMUL%s%s%s %s, %s, %s, %s", sign_str, acc_str, cond_str, s_str,
            REGISTER_NAMES[rdlo], REGISTER_NAMES[rdhi], REGISTER_NAMES[rm], REGISTER_NAMES[rs])
    } else if a_bit {
        return fmt.aprintf("MLA%s%s %s, %s, %s, %s", cond_str, s_str,
            REGISTER_NAMES[rd], REGISTER_NAMES[rm], REGISTER_NAMES[rs], REGISTER_NAMES[rn])
    } else {
        return fmt.aprintf("MUL%s%s %s, %s, %s", cond_str, s_str,
            REGISTER_NAMES[rd], REGISTER_NAMES[rm], REGISTER_NAMES[rs])
    }
}

// Disassemble swap instructions
@(private)
disasm_swap :: proc(opcode: u32, cond_str: string) -> string {
    rd := (opcode >> 12) & 0xF
    rn := (opcode >> 16) & 0xF
    rm := opcode & 0xF
    b_bit := ((opcode >> 22) & 1) != 0
    b_str := b_bit ? "B" : ""

    return fmt.aprintf("SWP%s%s %s, %s, [%s]", b_str, cond_str,
        REGISTER_NAMES[rd], REGISTER_NAMES[rm], REGISTER_NAMES[rn])
}

// Disassemble BX instruction
@(private)
disasm_bx :: proc(opcode: u32, cond_str: string) -> string {
    rm := opcode & 0xF
    return fmt.aprintf("BX%s %s", cond_str, REGISTER_NAMES[rm])
}

// Disassemble PSR transfer (MRS/MSR)
@(private)
disasm_psr_transfer :: proc(opcode: u32, cond_str: string) -> string {
    if ((opcode >> 21) & 1) == 0 {
        // MRS
        rd := (opcode >> 12) & 0xF
        psr := ((opcode >> 22) & 1) != 0 ? "SPSR" : "CPSR"
        return fmt.aprintf("MRS%s %s, %s", cond_str, REGISTER_NAMES[rd], psr)
    } else {
        // MSR
        psr := ((opcode >> 22) & 1) != 0 ? "SPSR" : "CPSR"
        fields := ""
        if ((opcode >> 16) & 1) != 0 { fields = strings.concatenate({fields, "c"}) }
        if ((opcode >> 17) & 1) != 0 { fields = strings.concatenate({fields, "x"}) }
        if ((opcode >> 18) & 1) != 0 { fields = strings.concatenate({fields, "s"}) }
        if ((opcode >> 19) & 1) != 0 { fields = strings.concatenate({fields, "f"}) }

        if ((opcode >> 25) & 1) != 0 {
            // Immediate
            imm := opcode & 0xFF
            rotate := ((opcode >> 8) & 0xF) * 2
            value := (imm >> rotate) | (imm << (32 - rotate))
            return fmt.aprintf("MSR%s %s_%s, #0x%X", cond_str, psr, fields, value)
        } else {
            rm := opcode & 0xF
            return fmt.aprintf("MSR%s %s_%s, %s", cond_str, psr, fields, REGISTER_NAMES[rm])
        }
    }
}

// Disassemble halfword/signed byte transfer
@(private)
disasm_halfword_transfer :: proc(opcode: u32, cond_str: string) -> string {
    rd := (opcode >> 12) & 0xF
    rn := (opcode >> 16) & 0xF
    l_bit := ((opcode >> 20) & 1) != 0
    w_bit := ((opcode >> 21) & 1) != 0
    imm_bit := ((opcode >> 22) & 1) != 0
    u_bit := ((opcode >> 23) & 1) != 0
    p_bit := ((opcode >> 24) & 1) != 0
    sh := (opcode >> 5) & 0x3

    // Determine operation
    op_str: string
    switch sh {
    case 0b01: op_str = l_bit ? "LDRH" : "STRH"
    case 0b10: op_str = "LDRSB"
    case 0b11: op_str = "LDRSH"
    case: op_str = "???"
    }

    // Get offset
    offset_str: string
    sign := u_bit ? "" : "-"
    if imm_bit {
        offset := ((opcode >> 4) & 0xF0) | (opcode & 0xF)
        offset_str = fmt.aprintf("#%s%d", sign, offset)
    } else {
        rm := opcode & 0xF
        offset_str = fmt.aprintf("%s%s", sign, REGISTER_NAMES[rm])
    }

    // Format addressing mode
    w_str := w_bit ? "!" : ""
    if p_bit {
        return fmt.aprintf("%s%s %s, [%s, %s]%s", op_str, cond_str,
            REGISTER_NAMES[rd], REGISTER_NAMES[rn], offset_str, w_str)
    } else {
        return fmt.aprintf("%s%s %s, [%s], %s", op_str, cond_str,
            REGISTER_NAMES[rd], REGISTER_NAMES[rn], offset_str)
    }
}

// Disassemble single data transfer (LDR/STR)
@(private)
disasm_single_transfer :: proc(opcode: u32, cond_str: string) -> string {
    rd := (opcode >> 12) & 0xF
    rn := (opcode >> 16) & 0xF
    l_bit := ((opcode >> 20) & 1) != 0
    w_bit := ((opcode >> 21) & 1) != 0
    b_bit := ((opcode >> 22) & 1) != 0
    u_bit := ((opcode >> 23) & 1) != 0
    p_bit := ((opcode >> 24) & 1) != 0
    imm_bit := ((opcode >> 25) & 1) == 0

    op_str := l_bit ? "LDR" : "STR"
    b_str := b_bit ? "B" : ""

    // Get offset
    offset_str: string
    sign := u_bit ? "" : "-"
    if imm_bit {
        offset := opcode & 0xFFF
        if offset == 0 {
            offset_str = ""
        } else {
            offset_str = fmt.aprintf(", #%s%d", sign, offset)
        }
    } else {
        rm := opcode & 0xF
        shift_type := Shift_Type((opcode >> 5) & 0x3)
        shift_amt := (opcode >> 7) & 0x1F

        if shift_amt == 0 && shift_type == .LSL {
            offset_str = fmt.aprintf(", %s%s", sign, REGISTER_NAMES[rm])
        } else {
            offset_str = fmt.aprintf(", %s%s, %s #%d", sign, REGISTER_NAMES[rm],
                SHIFT_NAMES[u8(shift_type)], shift_amt)
        }
    }

    // Format addressing mode
    w_str := w_bit ? "!" : ""
    if p_bit {
        return fmt.aprintf("%s%s%s %s, [%s%s]%s", op_str, cond_str, b_str,
            REGISTER_NAMES[rd], REGISTER_NAMES[rn], offset_str, w_str)
    } else {
        return fmt.aprintf("%s%s%sT %s, [%s]%s", op_str, cond_str, b_str,
            REGISTER_NAMES[rd], REGISTER_NAMES[rn], offset_str)
    }
}

// Disassemble block data transfer (LDM/STM)
@(private)
disasm_block_transfer :: proc(opcode: u32, cond_str: string) -> string {
    rn := (opcode >> 16) & 0xF
    l_bit := ((opcode >> 20) & 1) != 0
    w_bit := ((opcode >> 21) & 1) != 0
    s_bit := ((opcode >> 22) & 1) != 0
    u_bit := ((opcode >> 23) & 1) != 0
    p_bit := ((opcode >> 24) & 1) != 0
    reg_list := opcode & 0xFFFF

    // Determine addressing mode suffix
    mode_str: string
    if l_bit {
        switch {
        case p_bit && u_bit:  mode_str = "ED"   // LDMED = LDMIB
        case !p_bit && u_bit: mode_str = "FD"   // LDMFD = LDMIA
        case p_bit && !u_bit: mode_str = "EA"   // LDMEA = LDMDB
        case:                 mode_str = "FA"   // LDMFA = LDMDA
        }
    } else {
        switch {
        case p_bit && u_bit:  mode_str = "FA"   // STMFA = STMIB
        case !p_bit && u_bit: mode_str = "EA"   // STMEA = STMIA
        case p_bit && !u_bit: mode_str = "FD"   // STMFD = STMDB
        case:                 mode_str = "ED"   // STMED = STMDA
        }
    }

    op_str := l_bit ? "LDM" : "STM"
    w_str := w_bit ? "!" : ""
    s_str := s_bit ? "^" : ""

    // Build register list
    regs := make([dynamic]string, context.temp_allocator)
    for i in 0 ..< 16 {
        if (reg_list & (1 << u32(i))) != 0 {
            append(&regs, REGISTER_NAMES[i])
        }
    }
    reg_str := strings.join(regs[:], ", ")

    return fmt.aprintf("%s%s%s %s%s, {%s}%s", op_str, cond_str, mode_str,
        REGISTER_NAMES[rn], w_str, reg_str, s_str)
}

// Disassemble branch instructions
@(private)
disasm_branch :: proc(opcode: u32, cond_str: string) -> string {
    l_bit := ((opcode >> 24) & 1) != 0
    offset := opcode & 0x00FFFFFF

    // Sign extend 24-bit offset
    if (offset & 0x00800000) != 0 {
        offset |= 0xFF000000
    }

    // Calculate target (PC + 8 + offset * 4)
    // Note: We don't have PC here, so show relative offset
    offset_val := i32(offset) * 4 + 8

    op_str := l_bit ? "BL" : "B"

    if offset_val >= 0 {
        return fmt.aprintf("%s%s PC+#0x%X", op_str, cond_str, offset_val)
    } else {
        return fmt.aprintf("%s%s PC-#0x%X", op_str, cond_str, -offset_val)
    }
}

// Disassemble software interrupt
@(private)
disasm_swi :: proc(opcode: u32, cond_str: string) -> string {
    comment := opcode & 0x00FFFFFF
    return fmt.aprintf("SWI%s #0x%X", cond_str, comment)
}

// =============================================================================
// Instruction Classification Helpers
// =============================================================================

// Get the format/category of an ARM instruction
get_arm_format :: proc(opcode: u32) -> ARM_Format {
    bits_27_25 := (opcode >> 25) & 0x7
    bits_27_20 := (opcode >> 20) & 0xFF
    bits_7_4 := (opcode >> 4) & 0xF

    switch bits_27_25 {
    case 0b000:
        if bits_7_4 == 0b1001 {
            if (bits_27_20 & 0xF0) == 0x00 {
                if (bits_27_20 & 0x08) != 0 {
                    return .Multiply_Long
                }
                return .Multiply
            } else if (bits_27_20 & 0xFB) == 0x10 {
                return .Swap
            }
        }
        if (bits_7_4 & 0x9) == 0x9 && (bits_27_20 & 0xE0) == 0x00 {
            return .Halfword_Transfer
        }
        if bits_27_20 == 0x12 && bits_7_4 == 0x1 {
            return .Branch_Exchange
        }
        if (bits_27_20 & 0xF9) == 0x10 && bits_7_4 == 0 {
            return .PSR_Transfer
        }
        return .Data_Processing
    case 0b001:
        if (bits_27_20 & 0xF9) == 0x10 {
            return .PSR_Transfer
        }
        return .Data_Processing
    case 0b010, 0b011:
        if bits_27_25 == 0b011 && (bits_7_4 & 0x1) != 0 {
            return .Undefined
        }
        return .Single_Transfer
    case 0b100:
        return .Block_Transfer
    case 0b101:
        return .Branch
    case 0b110:
        return .Coprocessor
    case 0b111:
        if (opcode & 0x0F000000) == 0x0F000000 {
            return .Software_Interrupt
        }
        return .Coprocessor
    }

    return .Undefined
}

// Check if instruction affects flags (has S bit or is comparison)
arm_affects_flags :: proc(opcode: u32) -> bool {
    format := get_arm_format(opcode)

    #partial switch format {
    case .Data_Processing:
        alu_op := ALU_Op((opcode >> 21) & 0xF)
        // TST, TEQ, CMP, CMN always affect flags
        if alu_op >= .TST && alu_op <= .CMN {
            return true
        }
        // Other ops only if S bit is set
        return ((opcode >> 20) & 1) != 0
    case .Multiply, .Multiply_Long:
        return ((opcode >> 20) & 1) != 0
    case:
        return false
    }
}

// Get the ALU operation for data processing instructions
get_alu_op :: proc(opcode: u32) -> Maybe(ALU_Op) {
    format := get_arm_format(opcode)
    if format != .Data_Processing {
        return nil
    }
    return ALU_Op((opcode >> 21) & 0xF)
}
