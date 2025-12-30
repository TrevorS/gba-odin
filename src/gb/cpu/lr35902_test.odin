package gb_cpu

import "core:testing"

// =============================================================================
// Register Pair Tests
// =============================================================================

@(test)
test_get_set_af :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init_dmg(&cpu)

    // Test AF (low 4 bits of F are always 0)
    set_af(&cpu, 0x1234)
    testing.expect_value(t, get_af(&cpu), u16(0x1230))  // Low nibble cleared

    set_af(&cpu, 0xFFFF)
    testing.expect_value(t, get_af(&cpu), u16(0xFFF0))

    set_af(&cpu, 0x0000)
    testing.expect_value(t, get_af(&cpu), u16(0x0000))
}

@(test)
test_get_set_bc :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init_dmg(&cpu)

    set_bc(&cpu, 0x1234)
    testing.expect_value(t, get_bc(&cpu), u16(0x1234))
    testing.expect_value(t, cpu.b, u8(0x12))
    testing.expect_value(t, cpu.c, u8(0x34))

    set_bc(&cpu, 0xFFFF)
    testing.expect_value(t, get_bc(&cpu), u16(0xFFFF))
}

@(test)
test_get_set_de :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init_dmg(&cpu)

    set_de(&cpu, 0xABCD)
    testing.expect_value(t, get_de(&cpu), u16(0xABCD))
    testing.expect_value(t, cpu.d, u8(0xAB))
    testing.expect_value(t, cpu.e, u8(0xCD))
}

@(test)
test_get_set_hl :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init_dmg(&cpu)

    set_hl(&cpu, 0x5678)
    testing.expect_value(t, get_hl(&cpu), u16(0x5678))
    testing.expect_value(t, cpu.h, u8(0x56))
    testing.expect_value(t, cpu.l, u8(0x78))
}

// =============================================================================
// Flag Tests
// =============================================================================

@(test)
test_flag_z :: proc(t: ^testing.T) {
    cpu: CPU
    cpu.f = 0x00

    set_flag_z(&cpu, true)
    testing.expect(t, get_flag_z(&cpu), "Z flag should be set")
    testing.expect_value(t, cpu.f & 0x80, u8(0x80))

    set_flag_z(&cpu, false)
    testing.expect(t, !get_flag_z(&cpu), "Z flag should be clear")
    testing.expect_value(t, cpu.f & 0x80, u8(0x00))
}

@(test)
test_flag_n :: proc(t: ^testing.T) {
    cpu: CPU
    cpu.f = 0x00

    set_flag_n(&cpu, true)
    testing.expect(t, get_flag_n(&cpu), "N flag should be set")
    testing.expect_value(t, cpu.f & 0x40, u8(0x40))

    set_flag_n(&cpu, false)
    testing.expect(t, !get_flag_n(&cpu), "N flag should be clear")
}

@(test)
test_flag_h :: proc(t: ^testing.T) {
    cpu: CPU
    cpu.f = 0x00

    set_flag_h(&cpu, true)
    testing.expect(t, get_flag_h(&cpu), "H flag should be set")
    testing.expect_value(t, cpu.f & 0x20, u8(0x20))

    set_flag_h(&cpu, false)
    testing.expect(t, !get_flag_h(&cpu), "H flag should be clear")
}

@(test)
test_flag_c :: proc(t: ^testing.T) {
    cpu: CPU
    cpu.f = 0x00

    set_flag_c(&cpu, true)
    testing.expect(t, get_flag_c(&cpu), "C flag should be set")
    testing.expect_value(t, cpu.f & 0x10, u8(0x10))

    set_flag_c(&cpu, false)
    testing.expect(t, !get_flag_c(&cpu), "C flag should be clear")
}

@(test)
test_flags_combined :: proc(t: ^testing.T) {
    cpu: CPU
    cpu.f = 0x00

    // Set all flags
    set_flag_z(&cpu, true)
    set_flag_n(&cpu, true)
    set_flag_h(&cpu, true)
    set_flag_c(&cpu, true)

    testing.expect_value(t, cpu.f, u8(0xF0))
    testing.expect(t, get_flag_z(&cpu), "Z should be set")
    testing.expect(t, get_flag_n(&cpu), "N should be set")
    testing.expect(t, get_flag_h(&cpu), "H should be set")
    testing.expect(t, get_flag_c(&cpu), "C should be set")

    // Clear N and H, keep Z and C
    set_flag_n(&cpu, false)
    set_flag_h(&cpu, false)
    testing.expect_value(t, cpu.f, u8(0x90))
}

// =============================================================================
// Initialization Tests
// =============================================================================

@(test)
test_cpu_init_dmg :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init_dmg(&cpu)

    // DMG post-boot values
    testing.expect_value(t, cpu.a, u8(0x01))
    testing.expect_value(t, cpu.f, u8(0xB0))  // Z=1, N=0, H=1, C=1
    testing.expect_value(t, cpu.b, u8(0x00))
    testing.expect_value(t, cpu.c, u8(0x13))
    testing.expect_value(t, cpu.d, u8(0x00))
    testing.expect_value(t, cpu.e, u8(0xD8))
    testing.expect_value(t, cpu.h, u8(0x01))
    testing.expect_value(t, cpu.l, u8(0x4D))
    testing.expect_value(t, cpu.sp, u16(0xFFFE))
    testing.expect_value(t, cpu.pc, u16(0x0100))

    testing.expect(t, !cpu.halted, "CPU should not be halted")
    testing.expect(t, !cpu.ime, "IME should be disabled")
}

@(test)
test_cpu_init_cgb :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init_cgb(&cpu)

    // CGB post-boot values differ from DMG
    testing.expect_value(t, cpu.a, u8(0x11))  // Different!
    testing.expect_value(t, cpu.f, u8(0x80))  // Different!
    testing.expect_value(t, cpu.pc, u16(0x0100))
}

// =============================================================================
// ALU Tests - ADD
// =============================================================================

@(test)
test_add_a_zero :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init_dmg(&cpu)
    cpu.f = 0x00

    // 0 + 0 = 0, Z flag set
    cpu.a = 0x00
    add_a(&cpu, 0x00, false)
    testing.expect_value(t, cpu.a, u8(0x00))
    testing.expect(t, get_flag_z(&cpu), "Zero flag should be set")
    testing.expect(t, !get_flag_n(&cpu), "N flag should be clear for ADD")
}

@(test)
test_add_a_half_carry :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init_dmg(&cpu)
    cpu.f = 0x00

    // 0x0F + 0x01 = 0x10, H flag set
    cpu.a = 0x0F
    add_a(&cpu, 0x01, false)
    testing.expect_value(t, cpu.a, u8(0x10))
    testing.expect(t, get_flag_h(&cpu), "Half-carry should be set")
    testing.expect(t, !get_flag_c(&cpu), "Carry should be clear")
}

@(test)
test_add_a_carry :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init_dmg(&cpu)
    cpu.f = 0x00

    // 0xFF + 0x01 = 0x00 with carry
    cpu.a = 0xFF
    add_a(&cpu, 0x01, false)
    testing.expect_value(t, cpu.a, u8(0x00))
    testing.expect(t, get_flag_c(&cpu), "Carry should be set")
    testing.expect(t, get_flag_z(&cpu), "Zero should be set")
}

@(test)
test_adc_with_carry :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init_dmg(&cpu)

    // ADC with carry flag set: 0x10 + 0x10 + 1 = 0x21
    cpu.f = 0x00
    set_flag_c(&cpu, true)
    cpu.a = 0x10
    add_a(&cpu, 0x10, true)
    testing.expect_value(t, cpu.a, u8(0x21))
}

// =============================================================================
// ALU Tests - SUB
// =============================================================================

@(test)
test_sub_a_zero_result :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init_dmg(&cpu)
    cpu.f = 0x00

    cpu.a = 0x10
    sub_a(&cpu, 0x10, false)
    testing.expect_value(t, cpu.a, u8(0x00))
    testing.expect(t, get_flag_z(&cpu), "Zero flag should be set")
    testing.expect(t, get_flag_n(&cpu), "N flag should be set for SUB")
}

@(test)
test_sub_a_half_borrow :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init_dmg(&cpu)
    cpu.f = 0x00

    // 0x10 - 0x01 = 0x0F, H flag set (borrow from bit 4)
    cpu.a = 0x10
    sub_a(&cpu, 0x01, false)
    testing.expect_value(t, cpu.a, u8(0x0F))
    testing.expect(t, get_flag_h(&cpu), "Half-carry (borrow) should be set")
}

@(test)
test_sub_a_borrow :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init_dmg(&cpu)
    cpu.f = 0x00

    // 0x00 - 0x01 = 0xFF with borrow
    cpu.a = 0x00
    sub_a(&cpu, 0x01, false)
    testing.expect_value(t, cpu.a, u8(0xFF))
    testing.expect(t, get_flag_c(&cpu), "Carry (borrow) should be set")
}

// =============================================================================
// ALU Tests - Logic
// =============================================================================

@(test)
test_and_a :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init_dmg(&cpu)
    cpu.f = 0x00

    cpu.a = 0xF0
    and_a(&cpu, 0x0F)
    testing.expect_value(t, cpu.a, u8(0x00))
    testing.expect(t, get_flag_z(&cpu), "Zero flag for AND result 0")
    testing.expect(t, get_flag_h(&cpu), "H flag always set for AND")
    testing.expect(t, !get_flag_n(&cpu), "N flag clear for AND")
    testing.expect(t, !get_flag_c(&cpu), "C flag clear for AND")
}

@(test)
test_or_a :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init_dmg(&cpu)
    cpu.f = 0x00

    cpu.a = 0xF0
    or_a(&cpu, 0x0F)
    testing.expect_value(t, cpu.a, u8(0xFF))
    testing.expect(t, !get_flag_z(&cpu), "Zero flag should be clear")
}

@(test)
test_xor_a :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init_dmg(&cpu)
    cpu.f = 0x00

    cpu.a = 0xFF
    xor_a(&cpu, 0xFF)
    testing.expect_value(t, cpu.a, u8(0x00))
    testing.expect(t, get_flag_z(&cpu), "Zero flag for XOR result 0")
}

// =============================================================================
// ALU Tests - INC/DEC
// =============================================================================

@(test)
test_inc8_overflow :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init_dmg(&cpu)
    cpu.f = 0x00

    result := inc8(&cpu, 0xFF)
    testing.expect_value(t, result, u8(0x00))
    testing.expect(t, get_flag_z(&cpu), "Zero flag for overflow to 0")
    testing.expect(t, get_flag_h(&cpu), "Half-carry for 0xFF + 1")
    testing.expect(t, !get_flag_n(&cpu), "N flag clear for INC")
}

@(test)
test_inc8_half_carry :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init_dmg(&cpu)
    cpu.f = 0x00

    result := inc8(&cpu, 0x0F)
    testing.expect_value(t, result, u8(0x10))
    testing.expect(t, get_flag_h(&cpu), "Half-carry for 0x0F + 1")
}

@(test)
test_dec8_to_zero :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init_dmg(&cpu)
    cpu.f = 0x00

    result := dec8(&cpu, 0x01)
    testing.expect_value(t, result, u8(0x00))
    testing.expect(t, get_flag_z(&cpu), "Zero flag for decrement to 0")
    testing.expect(t, get_flag_n(&cpu), "N flag set for DEC")
}

@(test)
test_dec8_half_borrow :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init_dmg(&cpu)
    cpu.f = 0x00

    result := dec8(&cpu, 0x10)
    testing.expect_value(t, result, u8(0x0F))
    testing.expect(t, get_flag_h(&cpu), "Half-carry (borrow) for 0x10 - 1")
}

// =============================================================================
// 16-bit ALU Tests
// =============================================================================

@(test)
test_add_hl_carry :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init_dmg(&cpu)
    cpu.f = 0x00

    set_hl(&cpu, 0x8000)
    add_hl(&cpu, 0x8000)
    testing.expect_value(t, get_hl(&cpu), u16(0x0000))
    testing.expect(t, get_flag_c(&cpu), "Carry for 16-bit overflow")
}

@(test)
test_add_hl_half_carry :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init_dmg(&cpu)
    cpu.f = 0x00

    set_hl(&cpu, 0x0FFF)
    add_hl(&cpu, 0x0001)
    testing.expect_value(t, get_hl(&cpu), u16(0x1000))
    testing.expect(t, get_flag_h(&cpu), "Half-carry for bits 11->12")
}

// =============================================================================
// DAA Tests
// =============================================================================

@(test)
test_daa_after_add :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init_dmg(&cpu)

    // BCD: 0x09 + 0x01 should give 0x10 after DAA
    cpu.a = 0x0A  // Result of 9+1 in binary
    cpu.f = 0x00  // N=0 (was addition)
    daa(&cpu)
    testing.expect_value(t, cpu.a, u8(0x10))
}

@(test)
test_daa_carry :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init_dmg(&cpu)

    // BCD overflow
    cpu.a = 0xA0
    cpu.f = 0x00
    daa(&cpu)
    testing.expect_value(t, cpu.a, u8(0x00))
    testing.expect(t, get_flag_c(&cpu), "Carry set for BCD overflow")
}

// =============================================================================
// CP Tests
// =============================================================================

@(test)
test_cp_equal :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init_dmg(&cpu)
    cpu.f = 0x00

    cpu.a = 0x42
    cp_a(&cpu, 0x42)
    testing.expect(t, get_flag_z(&cpu), "Z set when A == value")
    testing.expect(t, get_flag_n(&cpu), "N set for CP")
    testing.expect_value(t, cpu.a, u8(0x42))  // A unchanged
}

@(test)
test_cp_less_than :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init_dmg(&cpu)
    cpu.f = 0x00

    cpu.a = 0x10
    cp_a(&cpu, 0x20)
    testing.expect(t, !get_flag_z(&cpu), "Z clear when A != value")
    testing.expect(t, get_flag_c(&cpu), "C set when A < value")
}

// =============================================================================
// Interrupt Tests
// =============================================================================

// Mock memory for interrupt tests
@(private)
test_memory: [0x10000]u8

@(private)
test_read_byte :: proc(addr: u16) -> u8 {
    return test_memory[addr]
}

@(private)
test_write_byte :: proc(addr: u16, value: u8) {
    test_memory[addr] = value
}

@(test)
test_interrupt_service :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init_dmg(&cpu)
    cpu.read_byte = test_read_byte
    cpu.write_byte = test_write_byte

    cpu.ime = true
    cpu.pc = 0x1234

    // VBlank interrupt (bit 0)
    ie: u8 = 0x01  // VBlank enabled
    if_: u8 = 0x01  // VBlank requested

    serviced, new_if := handle_interrupts(&cpu, ie, if_)

    testing.expect(t, serviced, "Interrupt should be serviced")
    testing.expect_value(t, new_if, u8(0x00))  // IF bit cleared
    testing.expect_value(t, cpu.pc, u16(0x0040))  // VBlank vector
    testing.expect(t, !cpu.ime, "IME should be disabled")
}

@(test)
test_interrupt_disabled :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init_dmg(&cpu)
    cpu.read_byte = test_read_byte
    cpu.write_byte = test_write_byte

    cpu.ime = false  // Interrupts disabled
    cpu.pc = 0x1234

    ie: u8 = 0x01
    if_: u8 = 0x01

    serviced, new_if := handle_interrupts(&cpu, ie, if_)

    testing.expect(t, !serviced, "Interrupt should not be serviced when IME=0")
    testing.expect_value(t, cpu.pc, u16(0x1234))  // PC unchanged
}

@(test)
test_interrupt_priority :: proc(t: ^testing.T) {
    cpu: CPU
    cpu_init_dmg(&cpu)
    cpu.read_byte = test_read_byte
    cpu.write_byte = test_write_byte

    cpu.ime = true
    cpu.pc = 0x1234

    // Multiple interrupts pending, VBlank has highest priority
    ie: u8 = 0xFF  // All enabled
    if_: u8 = 0x1F  // All requested

    serviced, new_if := handle_interrupts(&cpu, ie, if_)

    testing.expect(t, serviced, "Interrupt should be serviced")
    testing.expect_value(t, new_if, u8(0x1E))  // Only VBlank (bit 0) cleared
    testing.expect_value(t, cpu.pc, u16(0x0040))  // VBlank vector (highest priority)
}
