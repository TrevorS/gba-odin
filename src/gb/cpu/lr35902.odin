package gb_cpu

// LR35902 CPU - Sharp SM83 core used in Game Boy
// Similar to Z80 but with differences:
// - No IX, IY registers
// - No alternate register set
// - Simplified instruction set
// - Different flag behavior in some cases

CPU :: struct {
    // Main registers (directly accessible as 8-bit or 16-bit pairs)
    a: u8,           // Accumulator
    f: u8,           // Flags (ZNHC----)
    b: u8,
    c: u8,
    d: u8,
    e: u8,
    h: u8,
    l: u8,

    // 16-bit registers
    sp: u16,         // Stack pointer
    pc: u16,         // Program counter

    // CPU state
    halted:          bool,
    stopped:         bool,
    ime:             bool,  // Interrupt Master Enable
    ime_scheduled:   bool,  // EI schedules IME for next instruction

    // Cycle counting
    cycles:          u64,
}

// Flag bit positions in F register
FLAG_Z :: 7  // Zero
FLAG_N :: 6  // Subtract
FLAG_H :: 5  // Half-carry
FLAG_C :: 4  // Carry

// Initialize CPU to post-boot state (DMG)
cpu_init_dmg :: proc(cpu: ^CPU) {
    cpu.a = 0x01
    cpu.f = 0xB0  // Z=1, N=0, H=1, C=1
    cpu.b = 0x00
    cpu.c = 0x13
    cpu.d = 0x00
    cpu.e = 0xD8
    cpu.h = 0x01
    cpu.l = 0x4D
    cpu.sp = 0xFFFE
    cpu.pc = 0x0100  // Entry point after boot ROM

    cpu.halted = false
    cpu.stopped = false
    cpu.ime = false
    cpu.ime_scheduled = false
    cpu.cycles = 0
}

// Initialize CPU to post-boot state (CGB)
cpu_init_cgb :: proc(cpu: ^CPU) {
    cpu.a = 0x11  // Different from DMG
    cpu.f = 0x80  // Z=1, N=0, H=0, C=0
    cpu.b = 0x00
    cpu.c = 0x00
    cpu.d = 0xFF
    cpu.e = 0x56
    cpu.h = 0x00
    cpu.l = 0x0D
    cpu.sp = 0xFFFE
    cpu.pc = 0x0100

    cpu.halted = false
    cpu.stopped = false
    cpu.ime = false
    cpu.ime_scheduled = false
    cpu.cycles = 0
}

// Register pair accessors
get_af :: #force_inline proc(cpu: ^CPU) -> u16 {
    return (u16(cpu.a) << 8) | u16(cpu.f & 0xF0)  // Low 4 bits of F are always 0
}

set_af :: #force_inline proc(cpu: ^CPU, value: u16) {
    cpu.a = u8(value >> 8)
    cpu.f = u8(value) & 0xF0  // Low 4 bits always 0
}

get_bc :: #force_inline proc(cpu: ^CPU) -> u16 {
    return (u16(cpu.b) << 8) | u16(cpu.c)
}

set_bc :: #force_inline proc(cpu: ^CPU, value: u16) {
    cpu.b = u8(value >> 8)
    cpu.c = u8(value)
}

get_de :: #force_inline proc(cpu: ^CPU) -> u16 {
    return (u16(cpu.d) << 8) | u16(cpu.e)
}

set_de :: #force_inline proc(cpu: ^CPU, value: u16) {
    cpu.d = u8(value >> 8)
    cpu.e = u8(value)
}

get_hl :: #force_inline proc(cpu: ^CPU) -> u16 {
    return (u16(cpu.h) << 8) | u16(cpu.l)
}

set_hl :: #force_inline proc(cpu: ^CPU, value: u16) {
    cpu.h = u8(value >> 8)
    cpu.l = u8(value)
}

// Flag accessors
get_flag_z :: #force_inline proc(cpu: ^CPU) -> bool {
    return (cpu.f & (1 << FLAG_Z)) != 0
}

get_flag_n :: #force_inline proc(cpu: ^CPU) -> bool {
    return (cpu.f & (1 << FLAG_N)) != 0
}

get_flag_h :: #force_inline proc(cpu: ^CPU) -> bool {
    return (cpu.f & (1 << FLAG_H)) != 0
}

get_flag_c :: #force_inline proc(cpu: ^CPU) -> bool {
    return (cpu.f & (1 << FLAG_C)) != 0
}

set_flag_z :: #force_inline proc(cpu: ^CPU, value: bool) {
    if value {
        cpu.f |= (1 << FLAG_Z)
    } else {
        cpu.f &= ~u8(1 << FLAG_Z)
    }
}

set_flag_n :: #force_inline proc(cpu: ^CPU, value: bool) {
    if value {
        cpu.f |= (1 << FLAG_N)
    } else {
        cpu.f &= ~u8(1 << FLAG_N)
    }
}

set_flag_h :: #force_inline proc(cpu: ^CPU, value: bool) {
    if value {
        cpu.f |= (1 << FLAG_H)
    } else {
        cpu.f &= ~u8(1 << FLAG_H)
    }
}

set_flag_c :: #force_inline proc(cpu: ^CPU, value: bool) {
    if value {
        cpu.f |= (1 << FLAG_C)
    } else {
        cpu.f &= ~u8(1 << FLAG_C)
    }
}

// Set multiple flags at once
set_flags :: #force_inline proc(cpu: ^CPU, z, n, h, c: bool) {
    cpu.f = 0
    if z { cpu.f |= (1 << FLAG_Z) }
    if n { cpu.f |= (1 << FLAG_N) }
    if h { cpu.f |= (1 << FLAG_H) }
    if c { cpu.f |= (1 << FLAG_C) }
}

// =============================================================================
// ALU Helper Functions
// =============================================================================

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

// =============================================================================
// Interrupt Handling
// =============================================================================

// Check for pending interrupts, returns info for caller to act on
// Caller must handle: push PC to stack, set PC to vector, clear IF bit
check_interrupts :: proc(cpu: ^CPU, ie: u8, if_: u8) -> (pending: bool, vector: u16, interrupt_bit: u8) {
    // Even with IME=0, interrupts can wake from HALT
    if cpu.halted && (ie & if_) != 0 {
        cpu.halted = false
    }

    if !cpu.ime {
        return false, 0, 0
    }

    enabled_pending := ie & if_
    if enabled_pending == 0 {
        return false, 0, 0
    }

    // Return highest priority interrupt
    // Priority: VBlank > LCD STAT > Timer > Serial > Joypad
    if (enabled_pending & 0x01) != 0 {
        return true, 0x0040, 0x01  // VBlank
    } else if (enabled_pending & 0x02) != 0 {
        return true, 0x0048, 0x02  // LCD STAT
    } else if (enabled_pending & 0x04) != 0 {
        return true, 0x0050, 0x04  // Timer
    } else if (enabled_pending & 0x08) != 0 {
        return true, 0x0058, 0x08  // Serial
    } else if (enabled_pending & 0x10) != 0 {
        return true, 0x0060, 0x10  // Joypad
    }

    return false, 0, 0
}
