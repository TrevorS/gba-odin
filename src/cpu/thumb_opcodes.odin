package cpu

import "core:fmt"
import "core:strings"

// =============================================================================
// THUMB (16-bit) Opcode Metadata and Disassembly
// =============================================================================
//
// THUMB is a compressed instruction set where most instructions are 16-bit.
// This reduces code size at the cost of some flexibility.
//
// THUMB instruction formats (19 total):
//   Format 1:  Move shifted register
//   Format 2:  Add/subtract
//   Format 3:  Move/compare/add/subtract immediate
//   Format 4:  ALU operations
//   Format 5:  Hi register operations / branch exchange
//   Format 6:  PC-relative load
//   Format 7:  Load/store with register offset
//   Format 8:  Load/store sign-extended byte/halfword
//   Format 9:  Load/store with immediate offset
//   Format 10: Load/store halfword
//   Format 11: SP-relative load/store
//   Format 12: Load address
//   Format 13: Add offset to stack pointer
//   Format 14: Push/pop registers
//   Format 15: Multiple load/store
//   Format 16: Conditional branch
//   Format 17: Software interrupt
//   Format 18: Unconditional branch
//   Format 19: Long branch with link
//
// Future use cases:
// - Disassembly and debugging
// - Instruction tracing with readable output
// - Test coverage analysis
// - Documentation generation
//

// =============================================================================
// THUMB Instruction Formats
// =============================================================================

THUMB_Format :: enum u8 {
    Move_Shifted_Register,   // Format 1: LSL, LSR, ASR with immediate
    Add_Subtract,            // Format 2: ADD, SUB (3-operand)
    Move_Compare_Add_Sub,    // Format 3: MOV, CMP, ADD, SUB with 8-bit immediate
    ALU_Operations,          // Format 4: AND, EOR, LSL, LSR, etc.
    Hi_Register_Ops,         // Format 5: ADD, CMP, MOV with high registers, BX
    PC_Relative_Load,        // Format 6: LDR Rd, [PC, #imm]
    Load_Store_Register,     // Format 7/8: LDR/STR with register offset
    Load_Store_Immediate,    // Format 9: LDR/STR with immediate offset
    Load_Store_Halfword,     // Format 10: LDRH/STRH with immediate offset
    SP_Relative_Load_Store,  // Format 11: LDR/STR relative to SP
    Load_Address,            // Format 12: ADD Rd, PC/SP, #imm
    Add_Offset_SP,           // Format 13: ADD SP, #imm
    Push_Pop,                // Format 14: PUSH/POP
    Multiple_Load_Store,     // Format 15: LDMIA/STMIA
    Conditional_Branch,      // Format 16: B<cond>
    Software_Interrupt,      // Format 17: SWI
    Unconditional_Branch,    // Format 18: B
    Long_Branch_Link,        // Format 19: BL (two instructions)
    Undefined,               // Unknown/undefined
}

// =============================================================================
// THUMB ALU Operations (Format 4, bits [9:6])
// =============================================================================

THUMB_ALU_Op :: enum u8 {
    AND = 0x0,   // Rd = Rd AND Rs
    EOR = 0x1,   // Rd = Rd XOR Rs
    LSL = 0x2,   // Rd = Rd << Rs
    LSR = 0x3,   // Rd = Rd >> Rs (logical)
    ASR = 0x4,   // Rd = Rd >> Rs (arithmetic)
    ADC = 0x5,   // Rd = Rd + Rs + C
    SBC = 0x6,   // Rd = Rd - Rs - !C
    ROR = 0x7,   // Rd = Rd ROR Rs
    TST = 0x8,   // Rd AND Rs (flags only)
    NEG = 0x9,   // Rd = 0 - Rs
    CMP = 0xA,   // Rd - Rs (flags only)
    CMN = 0xB,   // Rd + Rs (flags only)
    ORR = 0xC,   // Rd = Rd OR Rs
    MUL = 0xD,   // Rd = Rd * Rs
    BIC = 0xE,   // Rd = Rd AND NOT Rs
    MVN = 0xF,   // Rd = NOT Rs
}

THUMB_ALU_NAMES := [16]string{
    "AND", "EOR", "LSL", "LSR", "ASR", "ADC", "SBC", "ROR",
    "TST", "NEG", "CMP", "CMN", "ORR", "MUL", "BIC", "MVN",
}

// =============================================================================
// Low Register Names (R0-R7, used in most THUMB instructions)
// =============================================================================

LO_REGISTER_NAMES := [8]string{
    "R0", "R1", "R2", "R3", "R4", "R5", "R6", "R7",
}

// =============================================================================
// THUMB Disassembly Functions
// =============================================================================

// Disassemble a THUMB instruction to a human-readable string
disassemble_thumb :: proc(opcode: u16, allocator := context.allocator) -> string {
    context.allocator = allocator

    upper := u8(opcode >> 8)

    // Format 1: Move shifted register (LSL/LSR/ASR)
    if (upper & 0xE0) == 0x00 {
        return disasm_thumb_shift(opcode)
    }

    // Format 2: Add/subtract
    if (upper & 0xF8) == 0x18 {
        return disasm_thumb_add_sub(opcode)
    }

    // Format 3: Move/compare/add/subtract immediate
    if (upper & 0xE0) == 0x20 {
        return disasm_thumb_mov_cmp_add_sub(opcode)
    }

    // Format 4: ALU operations
    if (upper & 0xFC) == 0x40 {
        return disasm_thumb_alu(opcode)
    }

    // Format 5: Hi register operations / branch exchange
    if (upper & 0xFC) == 0x44 {
        return disasm_thumb_hi_reg(opcode)
    }

    // Format 6: PC-relative load
    if (upper & 0xF8) == 0x48 {
        return disasm_thumb_ldr_pc(opcode)
    }

    // Format 7/8: Load/store with register offset
    if (upper & 0xF0) == 0x50 {
        return disasm_thumb_ldr_str_reg(opcode)
    }

    // Format 9: Load/store with immediate offset
    if (upper & 0xE0) == 0x60 {
        return disasm_thumb_ldr_str_imm(opcode)
    }

    // Format 10: Load/store halfword
    if (upper & 0xF0) == 0x80 {
        return disasm_thumb_ldrh_strh(opcode)
    }

    // Format 11: SP-relative load/store
    if (upper & 0xF0) == 0x90 {
        return disasm_thumb_ldr_str_sp(opcode)
    }

    // Format 12: Load address
    if (upper & 0xF0) == 0xA0 {
        return disasm_thumb_load_addr(opcode)
    }

    // Format 13: Add offset to stack pointer
    if upper == 0xB0 {
        return disasm_thumb_add_sp(opcode)
    }

    // Format 14: Push/pop registers
    if (upper & 0xF6) == 0xB4 {
        return disasm_thumb_push_pop(opcode)
    }

    // Format 15: Multiple load/store
    if (upper & 0xF0) == 0xC0 {
        return disasm_thumb_ldm_stm(opcode)
    }

    // Format 16: Conditional branch
    if (upper & 0xF0) == 0xD0 {
        cond := (opcode >> 8) & 0xF
        if cond == 0xF {
            // Format 17: SWI
            return disasm_thumb_swi(opcode)
        }
        if cond < 0xE {
            return disasm_thumb_branch_cond(opcode)
        }
    }

    // Format 18: Unconditional branch
    if (upper & 0xF8) == 0xE0 {
        return disasm_thumb_branch(opcode)
    }

    // Format 19: Long branch with link
    if (upper & 0xF0) == 0xF0 {
        return disasm_thumb_bl(opcode)
    }

    return fmt.aprintf("??? (0x%04X)", opcode)
}

// Format 1: Move shifted register
@(private)
disasm_thumb_shift :: proc(opcode: u16) -> string {
    op := (opcode >> 11) & 0x3
    offset := (opcode >> 6) & 0x1F
    rs := (opcode >> 3) & 0x7
    rd := opcode & 0x7

    op_names := [3]string{"LSL", "LSR", "ASR"}
    return fmt.aprintf("%s %s, %s, #%d", op_names[op],
        LO_REGISTER_NAMES[rd], LO_REGISTER_NAMES[rs], offset)
}

// Format 2: Add/subtract
@(private)
disasm_thumb_add_sub :: proc(opcode: u16) -> string {
    i_bit := ((opcode >> 10) & 1) != 0
    op_bit := ((opcode >> 9) & 1) != 0
    rn_or_imm := (opcode >> 6) & 0x7
    rs := (opcode >> 3) & 0x7
    rd := opcode & 0x7

    op_str := op_bit ? "SUB" : "ADD"

    if i_bit {
        return fmt.aprintf("%s %s, %s, #%d", op_str,
            LO_REGISTER_NAMES[rd], LO_REGISTER_NAMES[rs], rn_or_imm)
    } else {
        return fmt.aprintf("%s %s, %s, %s", op_str,
            LO_REGISTER_NAMES[rd], LO_REGISTER_NAMES[rs], LO_REGISTER_NAMES[rn_or_imm])
    }
}

// Format 3: Move/compare/add/subtract immediate
@(private)
disasm_thumb_mov_cmp_add_sub :: proc(opcode: u16) -> string {
    op := (opcode >> 11) & 0x3
    rd := (opcode >> 8) & 0x7
    imm := opcode & 0xFF

    op_names := [4]string{"MOV", "CMP", "ADD", "SUB"}
    return fmt.aprintf("%s %s, #%d", op_names[op], LO_REGISTER_NAMES[rd], imm)
}

// Format 4: ALU operations
@(private)
disasm_thumb_alu :: proc(opcode: u16) -> string {
    op := THUMB_ALU_Op((opcode >> 6) & 0xF)
    rs := (opcode >> 3) & 0x7
    rd := opcode & 0x7

    return fmt.aprintf("%s %s, %s", THUMB_ALU_NAMES[u8(op)],
        LO_REGISTER_NAMES[rd], LO_REGISTER_NAMES[rs])
}

// Format 5: Hi register operations / BX
@(private)
disasm_thumb_hi_reg :: proc(opcode: u16) -> string {
    op := (opcode >> 8) & 0x3
    h1 := ((opcode >> 7) & 1) != 0
    h2 := ((opcode >> 6) & 1) != 0
    rs := (opcode >> 3) & 0x7
    rd := opcode & 0x7

    // Add high bit to register numbers
    rs_full := h2 ? rs + 8 : rs
    rd_full := h1 ? rd + 8 : rd

    switch op {
    case 0:
        return fmt.aprintf("ADD %s, %s", REGISTER_NAMES[rd_full], REGISTER_NAMES[rs_full])
    case 1:
        return fmt.aprintf("CMP %s, %s", REGISTER_NAMES[rd_full], REGISTER_NAMES[rs_full])
    case 2:
        return fmt.aprintf("MOV %s, %s", REGISTER_NAMES[rd_full], REGISTER_NAMES[rs_full])
    case 3:
        if h1 {
            return fmt.aprintf("BLX %s", REGISTER_NAMES[rs_full])
        }
        return fmt.aprintf("BX %s", REGISTER_NAMES[rs_full])
    }

    return "???"
}

// Format 6: PC-relative load
@(private)
disasm_thumb_ldr_pc :: proc(opcode: u16) -> string {
    rd := (opcode >> 8) & 0x7
    imm := (opcode & 0xFF) * 4

    return fmt.aprintf("LDR %s, [PC, #%d]", LO_REGISTER_NAMES[rd], imm)
}

// Format 7/8: Load/store with register offset
@(private)
disasm_thumb_ldr_str_reg :: proc(opcode: u16) -> string {
    op := (opcode >> 10) & 0x3
    ro := (opcode >> 6) & 0x7
    rb := (opcode >> 3) & 0x7
    rd := opcode & 0x7

    op_names: [4]string
    if ((opcode >> 9) & 1) != 0 {
        // Format 8: sign-extended
        op_names = [4]string{"STRH", "LDSB", "LDRH", "LDSH"}
    } else {
        // Format 7: normal
        op_names = [4]string{"STR", "STRB", "LDR", "LDRB"}
    }

    return fmt.aprintf("%s %s, [%s, %s]", op_names[op],
        LO_REGISTER_NAMES[rd], LO_REGISTER_NAMES[rb], LO_REGISTER_NAMES[ro])
}

// Format 9: Load/store with immediate offset
@(private)
disasm_thumb_ldr_str_imm :: proc(opcode: u16) -> string {
    b_bit := ((opcode >> 12) & 1) != 0
    l_bit := ((opcode >> 11) & 1) != 0
    offset := (opcode >> 6) & 0x1F
    rb := (opcode >> 3) & 0x7
    rd := opcode & 0x7

    op_str: string
    if l_bit {
        op_str = b_bit ? "LDRB" : "LDR"
    } else {
        op_str = b_bit ? "STRB" : "STR"
    }

    // Word access multiplies offset by 4
    actual_offset := b_bit ? offset : offset * 4

    return fmt.aprintf("%s %s, [%s, #%d]", op_str,
        LO_REGISTER_NAMES[rd], LO_REGISTER_NAMES[rb], actual_offset)
}

// Format 10: Load/store halfword
@(private)
disasm_thumb_ldrh_strh :: proc(opcode: u16) -> string {
    l_bit := ((opcode >> 11) & 1) != 0
    offset := ((opcode >> 6) & 0x1F) * 2
    rb := (opcode >> 3) & 0x7
    rd := opcode & 0x7

    op_str := l_bit ? "LDRH" : "STRH"
    return fmt.aprintf("%s %s, [%s, #%d]", op_str,
        LO_REGISTER_NAMES[rd], LO_REGISTER_NAMES[rb], offset)
}

// Format 11: SP-relative load/store
@(private)
disasm_thumb_ldr_str_sp :: proc(opcode: u16) -> string {
    l_bit := ((opcode >> 11) & 1) != 0
    rd := (opcode >> 8) & 0x7
    offset := (opcode & 0xFF) * 4

    op_str := l_bit ? "LDR" : "STR"
    return fmt.aprintf("%s %s, [SP, #%d]", op_str, LO_REGISTER_NAMES[rd], offset)
}

// Format 12: Load address
@(private)
disasm_thumb_load_addr :: proc(opcode: u16) -> string {
    sp_bit := ((opcode >> 11) & 1) != 0
    rd := (opcode >> 8) & 0x7
    offset := (opcode & 0xFF) * 4

    src := sp_bit ? "SP" : "PC"
    return fmt.aprintf("ADD %s, %s, #%d", LO_REGISTER_NAMES[rd], src, offset)
}

// Format 13: Add offset to SP
@(private)
disasm_thumb_add_sp :: proc(opcode: u16) -> string {
    s_bit := ((opcode >> 7) & 1) != 0
    offset := (opcode & 0x7F) * 4

    if s_bit {
        return fmt.aprintf("ADD SP, #-%d", offset)
    }
    return fmt.aprintf("ADD SP, #%d", offset)
}

// Format 14: Push/pop
@(private)
disasm_thumb_push_pop :: proc(opcode: u16) -> string {
    l_bit := ((opcode >> 11) & 1) != 0
    r_bit := ((opcode >> 8) & 1) != 0
    reg_list := opcode & 0xFF

    // Build register list
    regs := make([dynamic]string, context.temp_allocator)
    for i in 0 ..< 8 {
        if (reg_list & (1 << u16(i))) != 0 {
            append(&regs, LO_REGISTER_NAMES[i])
        }
    }
    if r_bit {
        append(&regs, l_bit ? "PC" : "LR")
    }
    reg_str := strings.join(regs[:], ", ")

    op_str := l_bit ? "POP" : "PUSH"
    return fmt.aprintf("%s {%s}", op_str, reg_str)
}

// Format 15: Multiple load/store
@(private)
disasm_thumb_ldm_stm :: proc(opcode: u16) -> string {
    l_bit := ((opcode >> 11) & 1) != 0
    rb := (opcode >> 8) & 0x7
    reg_list := opcode & 0xFF

    // Build register list
    regs := make([dynamic]string, context.temp_allocator)
    for i in 0 ..< 8 {
        if (reg_list & (1 << u16(i))) != 0 {
            append(&regs, LO_REGISTER_NAMES[i])
        }
    }
    reg_str := strings.join(regs[:], ", ")

    op_str := l_bit ? "LDMIA" : "STMIA"
    return fmt.aprintf("%s %s!, {%s}", op_str, LO_REGISTER_NAMES[rb], reg_str)
}

// Format 16: Conditional branch
@(private)
disasm_thumb_branch_cond :: proc(opcode: u16) -> string {
    cond := (opcode >> 8) & 0xF
    offset := i32(i8(opcode & 0xFF)) * 2 + 4

    cond_str := CONDITION_NAMES[cond]

    if offset >= 0 {
        return fmt.aprintf("B%s PC+#%d", cond_str, offset)
    }
    return fmt.aprintf("B%s PC-#%d", cond_str, -offset)
}

// Format 17: SWI
@(private)
disasm_thumb_swi :: proc(opcode: u16) -> string {
    comment := opcode & 0xFF
    return fmt.aprintf("SWI #0x%X", comment)
}

// Format 18: Unconditional branch
@(private)
disasm_thumb_branch :: proc(opcode: u16) -> string {
    offset := opcode & 0x7FF
    // Sign extend 11-bit offset
    if (offset & 0x400) != 0 {
        offset |= 0xF800
    }
    offset_val := i32(i16(offset)) * 2 + 4

    if offset_val >= 0 {
        return fmt.aprintf("B PC+#%d", offset_val)
    }
    return fmt.aprintf("B PC-#%d", -offset_val)
}

// Format 19: Long branch with link
@(private)
disasm_thumb_bl :: proc(opcode: u16) -> string {
    h_bit := ((opcode >> 11) & 1) != 0
    offset := opcode & 0x7FF

    if h_bit {
        return fmt.aprintf("BL (suffix: #0x%X)", offset * 2)
    }
    return fmt.aprintf("BL (prefix: #0x%X)", offset)
}

// =============================================================================
// Instruction Classification Helpers
// =============================================================================

// Get the format/category of a THUMB instruction
get_thumb_format :: proc(opcode: u16) -> THUMB_Format {
    upper := u8(opcode >> 8)

    if (upper & 0xE0) == 0x00 {
        return .Move_Shifted_Register
    }
    if (upper & 0xF8) == 0x18 {
        return .Add_Subtract
    }
    if (upper & 0xE0) == 0x20 {
        return .Move_Compare_Add_Sub
    }
    if (upper & 0xFC) == 0x40 {
        return .ALU_Operations
    }
    if (upper & 0xFC) == 0x44 {
        return .Hi_Register_Ops
    }
    if (upper & 0xF8) == 0x48 {
        return .PC_Relative_Load
    }
    if (upper & 0xF0) == 0x50 {
        return .Load_Store_Register
    }
    if (upper & 0xE0) == 0x60 {
        return .Load_Store_Immediate
    }
    if (upper & 0xF0) == 0x80 {
        return .Load_Store_Halfword
    }
    if (upper & 0xF0) == 0x90 {
        return .SP_Relative_Load_Store
    }
    if (upper & 0xF0) == 0xA0 {
        return .Load_Address
    }
    if upper == 0xB0 {
        return .Add_Offset_SP
    }
    if (upper & 0xF6) == 0xB4 {
        return .Push_Pop
    }
    if (upper & 0xF0) == 0xC0 {
        return .Multiple_Load_Store
    }
    if (upper & 0xF0) == 0xD0 {
        cond := (opcode >> 8) & 0xF
        if cond == 0xF {
            return .Software_Interrupt
        }
        if cond < 0xE {
            return .Conditional_Branch
        }
    }
    if (upper & 0xF8) == 0xE0 {
        return .Unconditional_Branch
    }
    if (upper & 0xF0) == 0xF0 {
        return .Long_Branch_Link
    }

    return .Undefined
}

// Check if THUMB instruction affects flags
thumb_affects_flags :: proc(opcode: u16) -> bool {
    format := get_thumb_format(opcode)

    #partial switch format {
    case .Move_Shifted_Register:
        return true  // Always affects N, Z, C
    case .Add_Subtract:
        return true  // Always affects N, Z, C, V
    case .Move_Compare_Add_Sub:
        return true  // Always affects flags
    case .ALU_Operations:
        return true  // All ALU ops affect flags
    case .Hi_Register_Ops:
        op := (opcode >> 8) & 0x3
        return op == 1  // Only CMP affects flags
    case:
        return false
    }
}

// Check if THUMB instruction is a branch
thumb_is_branch :: proc(opcode: u16) -> bool {
    format := get_thumb_format(opcode)
    #partial switch format {
    case .Hi_Register_Ops:
        op := (opcode >> 8) & 0x3
        return op == 3  // BX/BLX
    case .Conditional_Branch, .Unconditional_Branch, .Long_Branch_Link:
        return true
    case:
        return false
    }
}

// Get the ALU operation for Format 4 instructions
get_thumb_alu_op :: proc(opcode: u16) -> Maybe(THUMB_ALU_Op) {
    format := get_thumb_format(opcode)
    if format != .ALU_Operations {
        return nil
    }
    return THUMB_ALU_Op((opcode >> 6) & 0xF)
}
