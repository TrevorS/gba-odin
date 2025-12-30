package cpu

import "core:testing"
import "../bus"

// =============================================================================
// Test Helpers
// =============================================================================

// Shared test memory - using package-level storage for tests
@(thread_local)
test_iwram: [32768]u8

setup_test_cpu_and_bus :: proc() -> (CPU, bus.Bus) {
    // Clear memory
    for i in 0..<32768 {
        test_iwram[i] = 0
    }

    test_bus: bus.Bus
    test_bus.iwram = test_iwram[:]

    cpu: CPU
    cpu_init(&cpu)
    set_mode(&cpu, .System)
    set_thumb(&cpu, true)

    return cpu, test_bus
}

// =============================================================================
// Format 10: LDRH Misaligned Access Tests
// =============================================================================

@(test)
test_thumb_ldrh_aligned :: proc(t: ^testing.T) {
    cpu, test_bus := setup_test_cpu_and_bus()

    // Write test value to IWRAM at aligned address
    // IWRAM is at 0x03000000, so address 0x03000100 -> offset 0x100
    test_iwram[0x100] = 0x34
    test_iwram[0x101] = 0x12

    // Set base register (r0) to point to IWRAM
    set_reg(&cpu, 0, 0x03000100)

    // Execute LDRH r1, [r0, #0] - Format 10, immediate offset 0
    // Encoding: 1000 1 00000 000 001 = 0x8801
    opcode := u16(0x8801)
    thumb_ldrh_strh_imm(&cpu, &test_bus, opcode)

    // r1 should contain 0x1234 (little-endian halfword)
    testing.expect_value(t, get_reg(&cpu, 1), u32(0x1234))
}

@(test)
test_thumb_ldrh_misaligned :: proc(t: ^testing.T) {
    cpu, test_bus := setup_test_cpu_and_bus()

    // Write test value at offset 0x100 and 0x101
    test_iwram[0x100] = 0xAB
    test_iwram[0x101] = 0xCD

    // Read from odd address 0x03000101
    set_reg(&cpu, 0, 0x03000101)

    // Execute LDRH r1, [r0, #0]
    opcode := u16(0x8801)
    thumb_ldrh_strh_imm(&cpu, &test_bus, opcode)

    // Misaligned LDRH reads from aligned address (0x100) and rotates
    // Read halfword at 0x100: low=0xAB, high=0xCD -> 0xCDAB
    // Rotate right 8: (0xCDAB >> 8) | (0xCDAB << 24) = 0xCD | 0xAB000000 = 0xAB0000CD
    testing.expect_value(t, get_reg(&cpu, 1), u32(0xAB0000CD))
}

// =============================================================================
// Format 14: POP {PC} Mode Switching Tests (ARMv4T)
// =============================================================================

@(test)
test_thumb_pop_pc_stays_thumb :: proc(t: ^testing.T) {
    cpu, test_bus := setup_test_cpu_and_bus()

    // Set SP to point to IWRAM
    set_reg(&cpu, 13, 0x03000100)

    // Write a return address with bit 0 = 0 to stack (ARM-style address)
    // On ARMv5+, this would switch to ARM mode, but on ARMv4T it should NOT
    test_iwram[0x100] = 0x00
    test_iwram[0x101] = 0x10
    test_iwram[0x102] = 0x00
    test_iwram[0x103] = 0x08  // 0x08001000 - bit 0 is 0

    // Execute POP {PC} - Format 14
    // Encoding: 1011 1 10 1 00000000 = 0xBD00
    opcode := u16(0xBD00)
    thumb_push_pop(&cpu, &test_bus, opcode)

    // On ARMv4T, POP {PC} does NOT switch modes
    // CPU should still be in THUMB mode
    testing.expect(t, is_thumb(&cpu), "POP {PC} should NOT switch to ARM mode on ARMv4T")

    // PC should be 0x08001000 (bit 0 cleared)
    testing.expect_value(t, get_pc(&cpu), u32(0x08001000))
}

@(test)
test_thumb_pop_pc_with_thumb_address :: proc(t: ^testing.T) {
    cpu, test_bus := setup_test_cpu_and_bus()

    // Set SP to point to IWRAM
    set_reg(&cpu, 13, 0x03000100)

    // Write a return address with bit 0 = 1 (THUMB-style address)
    test_iwram[0x100] = 0x01
    test_iwram[0x101] = 0x10
    test_iwram[0x102] = 0x00
    test_iwram[0x103] = 0x08  // 0x08001001

    // Execute POP {PC}
    opcode := u16(0xBD00)
    thumb_push_pop(&cpu, &test_bus, opcode)

    // CPU should still be in THUMB mode
    testing.expect(t, is_thumb(&cpu), "POP {PC} should stay in THUMB mode")

    // PC should be 0x08001000 (bit 0 cleared from address)
    testing.expect_value(t, get_pc(&cpu), u32(0x08001000))
}

// =============================================================================
// Format 15: Empty Register List Tests
// =============================================================================

@(test)
test_thumb_stm_empty_list :: proc(t: ^testing.T) {
    cpu, test_bus := setup_test_cpu_and_bus()

    // Set PC to a known value
    set_pc(&cpu, 0x08000100)

    // Set base register to point to IWRAM
    set_reg(&cpu, 0, 0x03000200)

    // Execute STM r0!, {} - empty register list
    // Encoding: 1100 0 000 00000000 = 0xC000
    opcode := u16(0xC000)
    thumb_ldm_stm(&cpu, &test_bus, opcode)

    // Empty list STM stores PC+6 in THUMB mode
    // PC = 0x08000100, so stored value should be 0x08000106
    stored := u32(test_iwram[0x200]) | (u32(test_iwram[0x201]) << 8) |
              (u32(test_iwram[0x202]) << 16) | (u32(test_iwram[0x203]) << 24)
    testing.expect_value(t, stored, u32(0x08000106))

    // Base register should be incremented by 0x40
    testing.expect_value(t, get_reg(&cpu, 0), u32(0x03000240))
}

@(test)
test_thumb_ldm_empty_list :: proc(t: ^testing.T) {
    cpu, test_bus := setup_test_cpu_and_bus()

    // Set base register to point to IWRAM
    set_reg(&cpu, 0, 0x03000200)

    // Write a PC value to memory
    test_iwram[0x200] = 0x00
    test_iwram[0x201] = 0x20
    test_iwram[0x202] = 0x00
    test_iwram[0x203] = 0x08  // 0x08002000

    // Execute LDM r0!, {} - empty register list
    // Encoding: 1100 1 000 00000000 = 0xC800
    opcode := u16(0xC800)
    thumb_ldm_stm(&cpu, &test_bus, opcode)

    // Empty list LDM loads to PC
    testing.expect_value(t, get_pc(&cpu), u32(0x08002000))

    // Base register should be incremented by 0x40
    testing.expect_value(t, get_reg(&cpu, 0), u32(0x03000240))
}

// =============================================================================
// Format 15: Base in Register List Tests
// =============================================================================

@(test)
test_thumb_stm_base_first_in_list :: proc(t: ^testing.T) {
    cpu, test_bus := setup_test_cpu_and_bus()

    // Set registers
    set_reg(&cpu, 0, 0x03000200)  // Base = r0, also in list
    set_reg(&cpu, 1, 0x11111111)
    set_reg(&cpu, 2, 0x22222222)

    // Execute STM r0!, {r0, r1, r2}
    // r0 is FIRST in list, so OLD value should be stored
    // Encoding: 1100 0 000 00000111 = 0xC007
    opcode := u16(0xC007)
    thumb_ldm_stm(&cpu, &test_bus, opcode)

    // First stored value (r0) should be OLD value (0x03000200)
    stored_r0 := u32(test_iwram[0x200]) | (u32(test_iwram[0x201]) << 8) |
                 (u32(test_iwram[0x202]) << 16) | (u32(test_iwram[0x203]) << 24)
    testing.expect_value(t, stored_r0, u32(0x03000200))

    // r1 stored at offset 4
    stored_r1 := u32(test_iwram[0x204]) | (u32(test_iwram[0x205]) << 8) |
                 (u32(test_iwram[0x206]) << 16) | (u32(test_iwram[0x207]) << 24)
    testing.expect_value(t, stored_r1, u32(0x11111111))

    // Base register should be updated (writeback)
    // 3 registers * 4 bytes = 12 bytes
    testing.expect_value(t, get_reg(&cpu, 0), u32(0x0300020C))
}

@(test)
test_thumb_stm_base_not_first_in_list :: proc(t: ^testing.T) {
    cpu, test_bus := setup_test_cpu_and_bus()

    // Set registers
    set_reg(&cpu, 0, 0xAAAAAAAA)
    set_reg(&cpu, 1, 0x03000200)  // Base = r1, NOT first in list
    set_reg(&cpu, 2, 0x22222222)
    set_reg(&cpu, 3, 0x33333333)

    // Execute STM r1!, {r0, r1, r2, r3}
    // r1 is NOT first in list (r0 is), so NEW (writeback) value should be stored
    // Encoding: 1100 0 001 00001111 = 0xC10F
    opcode := u16(0xC10F)
    thumb_ldm_stm(&cpu, &test_bus, opcode)

    // r0 stored at offset 0
    stored_r0 := u32(test_iwram[0x200]) | (u32(test_iwram[0x201]) << 8) |
                 (u32(test_iwram[0x202]) << 16) | (u32(test_iwram[0x203]) << 24)
    testing.expect_value(t, stored_r0, u32(0xAAAAAAAA))

    // r1 stored at offset 4 - should be WRITEBACK value (base + 16)
    // Final address = 0x03000200 + (4 * 4) = 0x03000210
    stored_r1 := u32(test_iwram[0x204]) | (u32(test_iwram[0x205]) << 8) |
                 (u32(test_iwram[0x206]) << 16) | (u32(test_iwram[0x207]) << 24)
    testing.expect_value(t, stored_r1, u32(0x03000210))

    // r2 stored at offset 8
    stored_r2 := u32(test_iwram[0x208]) | (u32(test_iwram[0x209]) << 8) |
                 (u32(test_iwram[0x20A]) << 16) | (u32(test_iwram[0x20B]) << 24)
    testing.expect_value(t, stored_r2, u32(0x22222222))

    // Base register (r1) final value
    testing.expect_value(t, get_reg(&cpu, 1), u32(0x03000210))
}

@(test)
test_thumb_ldm_base_in_list_no_writeback :: proc(t: ^testing.T) {
    cpu, test_bus := setup_test_cpu_and_bus()

    // Set base register
    set_reg(&cpu, 0, 0x03000200)

    // Write values to memory
    test_iwram[0x200] = 0x78; test_iwram[0x201] = 0x56; test_iwram[0x202] = 0x34; test_iwram[0x203] = 0x12  // 0x12345678
    test_iwram[0x204] = 0xEF; test_iwram[0x205] = 0xBE; test_iwram[0x206] = 0xAD; test_iwram[0x207] = 0xDE  // 0xDEADBEEF

    // Execute LDM r0!, {r0, r1}
    // r0 is in list, so NO writeback should occur (loaded value takes precedence)
    // Encoding: 1100 1 000 00000011 = 0xC803
    opcode := u16(0xC803)
    thumb_ldm_stm(&cpu, &test_bus, opcode)

    // r0 should have loaded value, NOT writeback address
    testing.expect_value(t, get_reg(&cpu, 0), u32(0x12345678))

    // r1 should have second loaded value
    testing.expect_value(t, get_reg(&cpu, 1), u32(0xDEADBEEF))
}
