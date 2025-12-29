package gb_cpu

import "core:fmt"

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

    // Memory bus (set by emulator)
    read_byte:       proc(addr: u16) -> u8,
    write_byte:      proc(addr: u16, value: u8),
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

// Memory access helpers
read8 :: #force_inline proc(cpu: ^CPU, addr: u16) -> u8 {
    return cpu.read_byte(addr)
}

write8 :: #force_inline proc(cpu: ^CPU, addr: u16, value: u8) {
    cpu.write_byte(addr, value)
}

read16 :: #force_inline proc(cpu: ^CPU, addr: u16) -> u16 {
    lo := u16(cpu.read_byte(addr))
    hi := u16(cpu.read_byte(addr + 1))
    return (hi << 8) | lo
}

write16 :: #force_inline proc(cpu: ^CPU, addr: u16, value: u16) {
    cpu.write_byte(addr, u8(value))
    cpu.write_byte(addr + 1, u8(value >> 8))
}

// Fetch byte at PC and increment
fetch8 :: #force_inline proc(cpu: ^CPU) -> u8 {
    value := cpu.read_byte(cpu.pc)
    cpu.pc += 1
    return value
}

// Fetch 16-bit value at PC and increment
fetch16 :: #force_inline proc(cpu: ^CPU) -> u16 {
    lo := u16(cpu.read_byte(cpu.pc))
    cpu.pc += 1
    hi := u16(cpu.read_byte(cpu.pc))
    cpu.pc += 1
    return (hi << 8) | lo
}

// Push 16-bit value to stack
push16 :: #force_inline proc(cpu: ^CPU, value: u16) {
    cpu.sp -= 1
    cpu.write_byte(cpu.sp, u8(value >> 8))
    cpu.sp -= 1
    cpu.write_byte(cpu.sp, u8(value))
}

// Pop 16-bit value from stack
pop16 :: #force_inline proc(cpu: ^CPU) -> u16 {
    lo := u16(cpu.read_byte(cpu.sp))
    cpu.sp += 1
    hi := u16(cpu.read_byte(cpu.sp))
    cpu.sp += 1
    return (hi << 8) | lo
}

// Execute one instruction, returns cycles consumed
step :: proc(cpu: ^CPU) -> u8 {
    // Handle scheduled IME enable
    if cpu.ime_scheduled {
        cpu.ime_scheduled = false
        cpu.ime = true
    }

    // If halted, just return 4 cycles
    if cpu.halted {
        return 4
    }

    // Fetch and execute opcode
    opcode := fetch8(cpu)
    cycles := execute(cpu, opcode)

    cpu.cycles += u64(cycles)
    return cycles
}

// Handle interrupts, returns true if interrupt was serviced
handle_interrupts :: proc(cpu: ^CPU, ie: u8, if_: u8) -> (serviced: bool, new_if: u8) {
    if !cpu.ime {
        // Even with IME=0, interrupts can wake from HALT
        if cpu.halted && (ie & if_) != 0 {
            cpu.halted = false
        }
        return false, if_
    }

    pending := ie & if_
    if pending == 0 {
        return false, if_
    }

    // Service highest priority interrupt
    // Priority: VBlank > LCD STAT > Timer > Serial > Joypad
    interrupt_bit: u8
    vector: u16

    if (pending & 0x01) != 0 {
        interrupt_bit = 0x01
        vector = 0x0040  // VBlank
    } else if (pending & 0x02) != 0 {
        interrupt_bit = 0x02
        vector = 0x0048  // LCD STAT
    } else if (pending & 0x04) != 0 {
        interrupt_bit = 0x04
        vector = 0x0050  // Timer
    } else if (pending & 0x08) != 0 {
        interrupt_bit = 0x08
        vector = 0x0058  // Serial
    } else if (pending & 0x10) != 0 {
        interrupt_bit = 0x10
        vector = 0x0060  // Joypad
    } else {
        return false, if_
    }

    // Disable interrupts and jump to vector
    cpu.ime = false
    cpu.halted = false
    push16(cpu, cpu.pc)
    cpu.pc = vector

    // Clear interrupt flag
    return true, if_ & ~interrupt_bit
}
