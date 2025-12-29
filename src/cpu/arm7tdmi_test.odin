package cpu

import "core:testing"

// =============================================================================
// Constants Tests
// =============================================================================

@(test)
test_num_registers :: proc(t: ^testing.T) {
    testing.expect_value(t, NUM_REGISTERS, 37)
}

@(test)
test_cpsr_bit_positions :: proc(t: ^testing.T) {
    testing.expect_value(t, CPSR_N, 31)
    testing.expect_value(t, CPSR_Z, 30)
    testing.expect_value(t, CPSR_C, 29)
    testing.expect_value(t, CPSR_V, 28)
    testing.expect_value(t, CPSR_I, 7)
    testing.expect_value(t, CPSR_F, 6)
    testing.expect_value(t, CPSR_T, 5)
    testing.expect_value(t, CPSR_MODE_MASK, 0x1F)
}

@(test)
test_exception_vectors :: proc(t: ^testing.T) {
    testing.expect(t, VECTOR_RESET == 0x00000000, "VECTOR_RESET should be 0")
    testing.expect(t, VECTOR_UNDEFINED == 0x00000004, "VECTOR_UNDEFINED should be 0x04")
    testing.expect(t, VECTOR_SWI == 0x00000008, "VECTOR_SWI should be 0x08")
    testing.expect(t, VECTOR_PREFETCH_ABORT == 0x0000000C, "VECTOR_PREFETCH_ABORT should be 0x0C")
    testing.expect(t, VECTOR_DATA_ABORT == 0x00000010, "VECTOR_DATA_ABORT should be 0x10")
    testing.expect(t, VECTOR_IRQ == 0x00000018, "VECTOR_IRQ should be 0x18")
    testing.expect(t, VECTOR_FIQ == 0x0000001C, "VECTOR_FIQ should be 0x1C")
}

@(test)
test_mode_values :: proc(t: ^testing.T) {
    testing.expect_value(t, u8(Mode.User), u8(0b10000))
    testing.expect_value(t, u8(Mode.FIQ), u8(0b10001))
    testing.expect_value(t, u8(Mode.IRQ), u8(0b10010))
    testing.expect_value(t, u8(Mode.Supervisor), u8(0b10011))
    testing.expect_value(t, u8(Mode.Abort), u8(0b10111))
    testing.expect_value(t, u8(Mode.Undefined), u8(0b11011))
    testing.expect_value(t, u8(Mode.System), u8(0b11111))
}

// =============================================================================
// CPU Initialization Tests
// =============================================================================

@(test)
test_cpu_init :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init(&cpu)

    // Starts in Supervisor mode with IRQ/FIQ disabled
    mode := get_mode(&cpu)
    testing.expect_value(t, mode, Mode.Supervisor)
    testing.expect(t, !irq_enabled(&cpu), "IRQ should be disabled at reset")
    testing.expect(t, !fiq_enabled(&cpu), "FIQ should be disabled at reset")
    testing.expect(t, !is_thumb(&cpu), "Should start in ARM state")

    // PC starts at reset vector
    testing.expect_value(t, get_pc(&cpu), u32(0))

    // Pipeline should be invalid
    testing.expect(t, !cpu.pipeline_valid, "Pipeline should be invalid at reset")
    testing.expect(t, !cpu.halted, "CPU should not be halted at reset")
}

@(test)
test_cpu_skip_bios :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_skip_bios(&cpu)

    // Should be in System mode
    mode := get_mode(&cpu)
    testing.expect_value(t, mode, Mode.System)

    // IRQ/FIQ should be enabled
    testing.expect(t, irq_enabled(&cpu), "IRQ should be enabled after BIOS skip")
    testing.expect(t, fiq_enabled(&cpu), "FIQ should be enabled after BIOS skip")

    // ARM state
    testing.expect(t, !is_thumb(&cpu), "Should be in ARM state")

    // PC at ROM entry
    testing.expect_value(t, get_pc(&cpu), u32(0x08000000))

    // Stack pointers should be set
    // IRQ mode SP at index 27
    testing.expect_value(t, cpu.regs[27], u32(0x03007FA0))
    // Supervisor mode SP at index 23
    testing.expect_value(t, cpu.regs[23], u32(0x03007FE0))
    // User/System mode SP at index 13
    testing.expect_value(t, cpu.regs[13], u32(0x03007F00))
}

// =============================================================================
// Register Access Tests
// =============================================================================

@(test)
test_get_set_reg :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init(&cpu)
    set_mode(&cpu, .System) // Use System mode for easy testing

    // Test r0-r7 (never banked)
    set_reg(&cpu, 0, 0x12345678)
    testing.expect_value(t, get_reg(&cpu, 0), u32(0x12345678))

    set_reg(&cpu, 7, 0xDEADBEEF)
    testing.expect_value(t, get_reg(&cpu, 7), u32(0xDEADBEEF))
}

@(test)
test_pc_read_arm :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init(&cpu)
    set_mode(&cpu, .System)
    set_thumb(&cpu, false)

    // Set raw PC
    set_pc(&cpu, 0x08000100)

    // Reading r15 should return PC + 8 in ARM mode
    pc_read := get_reg(&cpu, 15)
    testing.expect_value(t, pc_read, u32(0x08000108))
}

@(test)
test_pc_read_thumb :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init(&cpu)
    set_mode(&cpu, .System)
    set_thumb(&cpu, true)

    // Set raw PC
    set_pc(&cpu, 0x08000100)

    // Reading r15 should return PC + 4 in Thumb mode
    pc_read := get_reg(&cpu, 15)
    testing.expect_value(t, pc_read, u32(0x08000104))
}

@(test)
test_pc_write_invalidates_pipeline :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init(&cpu)
    cpu.pipeline_valid = true

    set_reg(&cpu, 15, 0x08001000)

    testing.expect(t, !cpu.pipeline_valid, "Writing to PC should invalidate pipeline")
}

// =============================================================================
// Register Banking Tests
// =============================================================================

@(test)
test_register_banking_fiq :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init(&cpu)

    // Set value in System mode
    set_mode(&cpu, .System)
    set_reg(&cpu, 8, 0x11111111)
    set_reg(&cpu, 13, 0x22222222)

    // Switch to FIQ mode
    set_mode(&cpu, .FIQ)

    // r8-r12 should be banked (different physical registers)
    set_reg(&cpu, 8, 0x33333333)
    testing.expect_value(t, get_reg(&cpu, 8), u32(0x33333333))

    // r13-r14 should also be banked
    set_reg(&cpu, 13, 0x44444444)
    testing.expect_value(t, get_reg(&cpu, 13), u32(0x44444444))

    // Switch back to System mode, values should be preserved
    set_mode(&cpu, .System)
    testing.expect_value(t, get_reg(&cpu, 8), u32(0x11111111))
    testing.expect_value(t, get_reg(&cpu, 13), u32(0x22222222))
}

@(test)
test_register_banking_irq :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init(&cpu)

    // Set values in System mode
    set_mode(&cpu, .System)
    set_reg(&cpu, 8, 0x11111111)  // r8 NOT banked in IRQ
    set_reg(&cpu, 13, 0x22222222)  // r13 IS banked

    // Switch to IRQ mode
    set_mode(&cpu, .IRQ)

    // r8-r12 should NOT be banked (same as System)
    testing.expect_value(t, get_reg(&cpu, 8), u32(0x11111111))

    // r13-r14 SHOULD be banked
    set_reg(&cpu, 13, 0x44444444)

    // Switch back
    set_mode(&cpu, .System)
    testing.expect_value(t, get_reg(&cpu, 13), u32(0x22222222))
}

// =============================================================================
// CPSR/SPSR Tests
// =============================================================================

@(test)
test_cpsr_get_set :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init(&cpu)

    set_cpsr(&cpu, 0x600000D3) // SVC mode, IRQ/FIQ disabled, ARM, Z and C flags
    cpsr := get_cpsr(&cpu)
    testing.expect_value(t, cpsr, u32(0x600000D3))
}

@(test)
test_spsr_user_system :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init(&cpu)
    set_mode(&cpu, .System)

    // User/System mode have no SPSR, should return CPSR
    set_cpsr(&cpu, 0x1F) // System mode
    spsr := get_spsr(&cpu)
    testing.expect_value(t, spsr, u32(0x1F))
}

@(test)
test_spsr_exception_modes :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init(&cpu)

    // Test SPSR in IRQ mode
    set_mode(&cpu, .IRQ)
    set_spsr(&cpu, 0x12345678)
    testing.expect_value(t, get_spsr(&cpu), u32(0x12345678))

    // Switch to Supervisor, should have different SPSR
    set_mode(&cpu, .Supervisor)
    set_spsr(&cpu, 0xDEADBEEF)
    testing.expect_value(t, get_spsr(&cpu), u32(0xDEADBEEF))

    // Verify IRQ SPSR unchanged
    set_mode(&cpu, .IRQ)
    testing.expect_value(t, get_spsr(&cpu), u32(0x12345678))
}

// =============================================================================
// Flag Tests
// =============================================================================

@(test)
test_individual_flags :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init(&cpu)

    // Test N flag
    set_flag_n(&cpu, true)
    testing.expect(t, get_flag_n(&cpu), "N flag should be set")
    set_flag_n(&cpu, false)
    testing.expect(t, !get_flag_n(&cpu), "N flag should be clear")

    // Test Z flag
    set_flag_z(&cpu, true)
    testing.expect(t, get_flag_z(&cpu), "Z flag should be set")
    set_flag_z(&cpu, false)
    testing.expect(t, !get_flag_z(&cpu), "Z flag should be clear")

    // Test C flag
    set_flag_c(&cpu, true)
    testing.expect(t, get_flag_c(&cpu), "C flag should be set")
    set_flag_c(&cpu, false)
    testing.expect(t, !get_flag_c(&cpu), "C flag should be clear")

    // Test V flag
    set_flag_v(&cpu, true)
    testing.expect(t, get_flag_v(&cpu), "V flag should be set")
    set_flag_v(&cpu, false)
    testing.expect(t, !get_flag_v(&cpu), "V flag should be clear")
}

@(test)
test_set_nz_flags_zero :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init(&cpu)

    set_nz_flags(&cpu, 0)
    testing.expect(t, !get_flag_n(&cpu), "N should be clear for zero")
    testing.expect(t, get_flag_z(&cpu), "Z should be set for zero")
}

@(test)
test_set_nz_flags_negative :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init(&cpu)

    set_nz_flags(&cpu, 0x80000000) // Negative value
    testing.expect(t, get_flag_n(&cpu), "N should be set for negative")
    testing.expect(t, !get_flag_z(&cpu), "Z should be clear for non-zero")
}

@(test)
test_set_nz_flags_positive :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init(&cpu)

    set_nz_flags(&cpu, 0x12345678) // Positive non-zero
    testing.expect(t, !get_flag_n(&cpu), "N should be clear for positive")
    testing.expect(t, !get_flag_z(&cpu), "Z should be clear for non-zero")
}

// =============================================================================
// Mode Tests
// =============================================================================

@(test)
test_get_set_mode :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init(&cpu)

    set_mode(&cpu, .User)
    testing.expect_value(t, get_mode(&cpu), Mode.User)

    set_mode(&cpu, .FIQ)
    testing.expect_value(t, get_mode(&cpu), Mode.FIQ)

    set_mode(&cpu, .IRQ)
    testing.expect_value(t, get_mode(&cpu), Mode.IRQ)

    set_mode(&cpu, .Supervisor)
    testing.expect_value(t, get_mode(&cpu), Mode.Supervisor)

    set_mode(&cpu, .Abort)
    testing.expect_value(t, get_mode(&cpu), Mode.Abort)

    set_mode(&cpu, .Undefined)
    testing.expect_value(t, get_mode(&cpu), Mode.Undefined)

    set_mode(&cpu, .System)
    testing.expect_value(t, get_mode(&cpu), Mode.System)
}

@(test)
test_thumb_state :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init(&cpu)

    testing.expect(t, !is_thumb(&cpu), "Should start in ARM state")

    set_thumb(&cpu, true)
    testing.expect(t, is_thumb(&cpu), "Should be in Thumb state")

    set_thumb(&cpu, false)
    testing.expect(t, !is_thumb(&cpu), "Should be back in ARM state")
}

// =============================================================================
// Interrupt Enable Tests
// =============================================================================

@(test)
test_irq_enable_disable :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init(&cpu)

    // IRQ disabled at reset
    testing.expect(t, !irq_enabled(&cpu), "IRQ disabled at reset")

    // Enable IRQ by clearing I bit
    cpsr := get_cpsr(&cpu)
    set_cpsr(&cpu, cpsr & ~u32(1 << CPSR_I))
    testing.expect(t, irq_enabled(&cpu), "IRQ should be enabled")

    // Disable IRQ by setting I bit
    set_cpsr(&cpu, cpsr | (1 << CPSR_I))
    testing.expect(t, !irq_enabled(&cpu), "IRQ should be disabled")
}

@(test)
test_fiq_enable_disable :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init(&cpu)

    // FIQ disabled at reset
    testing.expect(t, !fiq_enabled(&cpu), "FIQ disabled at reset")

    // Enable FIQ by clearing F bit
    cpsr := get_cpsr(&cpu)
    set_cpsr(&cpu, cpsr & ~u32(1 << CPSR_F))
    testing.expect(t, fiq_enabled(&cpu), "FIQ should be enabled")

    // Disable FIQ by setting F bit
    set_cpsr(&cpu, cpsr | (1 << CPSR_F))
    testing.expect(t, !fiq_enabled(&cpu), "FIQ should be disabled")
}

// =============================================================================
// Exception Tests
// =============================================================================

@(test)
test_swi_exception :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init(&cpu)

    // Setup in System mode
    set_mode(&cpu, .System)
    set_cpsr(&cpu, u32(Mode.System)) // Interrupts enabled
    set_pc(&cpu, 0x08001000)

    // Execute SWI
    swi(&cpu)

    // Should be in Supervisor mode
    testing.expect_value(t, get_mode(&cpu), Mode.Supervisor)

    // PC should be at SWI vector
    testing.expect_value(t, get_pc(&cpu), u32(VECTOR_SWI))

    // IRQ should be disabled
    testing.expect(t, !irq_enabled(&cpu), "IRQ should be disabled after SWI")

    // Should be in ARM state
    testing.expect(t, !is_thumb(&cpu), "Should be in ARM state after SWI")

    // SPSR should contain old CPSR
    testing.expect_value(t, get_spsr(&cpu), u32(Mode.System))
}

@(test)
test_irq_exception :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init(&cpu)

    // Setup
    set_mode(&cpu, .System)
    set_cpsr(&cpu, u32(Mode.System))
    set_pc(&cpu, 0x08001000)

    // Execute IRQ
    irq(&cpu)

    // Should be in IRQ mode
    testing.expect_value(t, get_mode(&cpu), Mode.IRQ)

    // PC should be at IRQ vector
    testing.expect_value(t, get_pc(&cpu), u32(VECTOR_IRQ))

    // LR should contain return address (PC + 4 for IRQ)
    // IRQ passes return_offset=4, so LR = old_pc + 4
    lr := get_reg(&cpu, 14)
    testing.expect_value(t, lr, u32(0x08001004))
}

@(test)
test_fiq_exception :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init(&cpu)

    set_mode(&cpu, .System)
    set_cpsr(&cpu, u32(Mode.System))
    set_pc(&cpu, 0x08001000)

    fiq(&cpu)

    // Should be in FIQ mode
    testing.expect_value(t, get_mode(&cpu), Mode.FIQ)

    // PC at FIQ vector
    testing.expect_value(t, get_pc(&cpu), u32(VECTOR_FIQ))

    // Both IRQ and FIQ should be disabled
    testing.expect(t, !irq_enabled(&cpu), "IRQ should be disabled after FIQ")
    testing.expect(t, !fiq_enabled(&cpu), "FIQ should be disabled after FIQ")
}

@(test)
test_undefined_exception :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init(&cpu)

    set_mode(&cpu, .System)
    set_pc(&cpu, 0x08001000)

    undefined(&cpu)

    testing.expect_value(t, get_mode(&cpu), Mode.Undefined)
    testing.expect_value(t, get_pc(&cpu), u32(VECTOR_UNDEFINED))
}

@(test)
test_data_abort_exception :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init(&cpu)

    set_mode(&cpu, .System)
    set_pc(&cpu, 0x08001000)

    data_abort(&cpu)

    testing.expect_value(t, get_mode(&cpu), Mode.Abort)
    testing.expect_value(t, get_pc(&cpu), u32(VECTOR_DATA_ABORT))

    // Data abort has return_offset=8
    lr := get_reg(&cpu, 14)
    testing.expect_value(t, lr, u32(0x08001008))
}

// =============================================================================
// Halt Tests
// =============================================================================

@(test)
test_halt_unhalt :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init(&cpu)

    testing.expect(t, !cpu.halted, "Should not be halted initially")

    halt(&cpu)
    testing.expect(t, cpu.halted, "Should be halted")

    unhalt(&cpu)
    testing.expect(t, !cpu.halted, "Should be unhalted")
}

// =============================================================================
// Condition Code Tests
// =============================================================================

@(test)
test_condition_eq :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init(&cpu)

    // EQ: Z set
    set_flag_z(&cpu, true)
    testing.expect(t, check_condition(&cpu, 0x0), "EQ should pass when Z set")

    set_flag_z(&cpu, false)
    testing.expect(t, !check_condition(&cpu, 0x0), "EQ should fail when Z clear")
}

@(test)
test_condition_ne :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init(&cpu)

    // NE: Z clear
    set_flag_z(&cpu, false)
    testing.expect(t, check_condition(&cpu, 0x1), "NE should pass when Z clear")

    set_flag_z(&cpu, true)
    testing.expect(t, !check_condition(&cpu, 0x1), "NE should fail when Z set")
}

@(test)
test_condition_cs :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init(&cpu)

    // CS: C set
    set_flag_c(&cpu, true)
    testing.expect(t, check_condition(&cpu, 0x2), "CS should pass when C set")

    set_flag_c(&cpu, false)
    testing.expect(t, !check_condition(&cpu, 0x2), "CS should fail when C clear")
}

@(test)
test_condition_cc :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init(&cpu)

    // CC: C clear
    set_flag_c(&cpu, false)
    testing.expect(t, check_condition(&cpu, 0x3), "CC should pass when C clear")

    set_flag_c(&cpu, true)
    testing.expect(t, !check_condition(&cpu, 0x3), "CC should fail when C set")
}

@(test)
test_condition_mi :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init(&cpu)

    // MI: N set
    set_flag_n(&cpu, true)
    testing.expect(t, check_condition(&cpu, 0x4), "MI should pass when N set")

    set_flag_n(&cpu, false)
    testing.expect(t, !check_condition(&cpu, 0x4), "MI should fail when N clear")
}

@(test)
test_condition_pl :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init(&cpu)

    // PL: N clear
    set_flag_n(&cpu, false)
    testing.expect(t, check_condition(&cpu, 0x5), "PL should pass when N clear")

    set_flag_n(&cpu, true)
    testing.expect(t, !check_condition(&cpu, 0x5), "PL should fail when N set")
}

@(test)
test_condition_vs :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init(&cpu)

    // VS: V set
    set_flag_v(&cpu, true)
    testing.expect(t, check_condition(&cpu, 0x6), "VS should pass when V set")

    set_flag_v(&cpu, false)
    testing.expect(t, !check_condition(&cpu, 0x6), "VS should fail when V clear")
}

@(test)
test_condition_vc :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init(&cpu)

    // VC: V clear
    set_flag_v(&cpu, false)
    testing.expect(t, check_condition(&cpu, 0x7), "VC should pass when V clear")

    set_flag_v(&cpu, true)
    testing.expect(t, !check_condition(&cpu, 0x7), "VC should fail when V set")
}

@(test)
test_condition_hi :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init(&cpu)

    // HI: C set AND Z clear
    set_flag_c(&cpu, true)
    set_flag_z(&cpu, false)
    testing.expect(t, check_condition(&cpu, 0x8), "HI should pass when C set and Z clear")

    set_flag_z(&cpu, true)
    testing.expect(t, !check_condition(&cpu, 0x8), "HI should fail when Z set")

    set_flag_c(&cpu, false)
    set_flag_z(&cpu, false)
    testing.expect(t, !check_condition(&cpu, 0x8), "HI should fail when C clear")
}

@(test)
test_condition_ls :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init(&cpu)

    // LS: C clear OR Z set
    set_flag_c(&cpu, false)
    set_flag_z(&cpu, false)
    testing.expect(t, check_condition(&cpu, 0x9), "LS should pass when C clear")

    set_flag_c(&cpu, true)
    set_flag_z(&cpu, true)
    testing.expect(t, check_condition(&cpu, 0x9), "LS should pass when Z set")

    set_flag_c(&cpu, true)
    set_flag_z(&cpu, false)
    testing.expect(t, !check_condition(&cpu, 0x9), "LS should fail when C set and Z clear")
}

@(test)
test_condition_ge :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init(&cpu)

    // GE: N equals V
    set_flag_n(&cpu, false)
    set_flag_v(&cpu, false)
    testing.expect(t, check_condition(&cpu, 0xA), "GE should pass when N=V=0")

    set_flag_n(&cpu, true)
    set_flag_v(&cpu, true)
    testing.expect(t, check_condition(&cpu, 0xA), "GE should pass when N=V=1")

    set_flag_n(&cpu, true)
    set_flag_v(&cpu, false)
    testing.expect(t, !check_condition(&cpu, 0xA), "GE should fail when N!=V")
}

@(test)
test_condition_lt :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init(&cpu)

    // LT: N not equal to V
    set_flag_n(&cpu, true)
    set_flag_v(&cpu, false)
    testing.expect(t, check_condition(&cpu, 0xB), "LT should pass when N!=V")

    set_flag_n(&cpu, true)
    set_flag_v(&cpu, true)
    testing.expect(t, !check_condition(&cpu, 0xB), "LT should fail when N=V")
}

@(test)
test_condition_gt :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init(&cpu)

    // GT: Z clear AND N equals V
    set_flag_z(&cpu, false)
    set_flag_n(&cpu, false)
    set_flag_v(&cpu, false)
    testing.expect(t, check_condition(&cpu, 0xC), "GT should pass when Z=0 and N=V")

    set_flag_z(&cpu, true)
    testing.expect(t, !check_condition(&cpu, 0xC), "GT should fail when Z set")

    set_flag_z(&cpu, false)
    set_flag_n(&cpu, true)
    set_flag_v(&cpu, false)
    testing.expect(t, !check_condition(&cpu, 0xC), "GT should fail when N!=V")
}

@(test)
test_condition_le :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init(&cpu)

    // LE: Z set OR N not equal to V
    set_flag_z(&cpu, true)
    testing.expect(t, check_condition(&cpu, 0xD), "LE should pass when Z set")

    set_flag_z(&cpu, false)
    set_flag_n(&cpu, true)
    set_flag_v(&cpu, false)
    testing.expect(t, check_condition(&cpu, 0xD), "LE should pass when N!=V")

    set_flag_z(&cpu, false)
    set_flag_n(&cpu, false)
    set_flag_v(&cpu, false)
    testing.expect(t, !check_condition(&cpu, 0xD), "LE should fail when Z=0 and N=V")
}

@(test)
test_condition_al :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init(&cpu)

    // AL: Always
    testing.expect(t, check_condition(&cpu, 0xE), "AL should always pass")

    set_flag_n(&cpu, true)
    set_flag_z(&cpu, true)
    set_flag_c(&cpu, true)
    set_flag_v(&cpu, true)
    testing.expect(t, check_condition(&cpu, 0xE), "AL should pass regardless of flags")
}

@(test)
test_get_condition_code :: proc(t: ^testing.T) {
    // Condition is in bits 28-31
    opcode := u32(0xE0000000) // AL (0xE)
    testing.expect_value(t, get_condition_code(opcode), u4(0xE))

    opcode = 0x00000000 // EQ (0x0)
    testing.expect_value(t, get_condition_code(opcode), u4(0x0))

    opcode = 0xF0000000 // NV (0xF)
    testing.expect_value(t, get_condition_code(opcode), u4(0xF))
}
