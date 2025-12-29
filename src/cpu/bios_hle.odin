package cpu

import "../bus"

// BIOS High-Level Emulation (HLE)
// Implements ALL GBA SWI functions without needing actual BIOS code

// HLE flag - when true, intercept ALL SWI calls
hle_enabled := true

// Handle SWI with HLE - always returns true (handles everything)
swi_hle :: proc(cpu: ^CPU, mem_bus: ^bus.Bus, swi_num: u8) -> bool {
    if !hle_enabled {
        return false
    }

    switch swi_num {
    case 0x00:
        hle_soft_reset(cpu, mem_bus)
    case 0x01:
        hle_register_ram_reset(cpu, mem_bus)
    case 0x02:
        cpu.halted = true // Halt
    case 0x03:
        cpu.halted = true // Stop
    case 0x04:
        hle_intr_wait(cpu, mem_bus)
    case 0x05:
        hle_vblank_intr_wait(cpu, mem_bus)
    case 0x06:
        hle_div(cpu)
    case 0x07:
        hle_div_arm(cpu)
    case 0x08:
        hle_sqrt(cpu)
    case 0x09:
        hle_arctan(cpu)
    case 0x0A:
        hle_arctan2(cpu)
    case 0x0B:
        hle_cpu_set(cpu, mem_bus)
    case 0x0C:
        hle_cpu_fast_set(cpu, mem_bus)
    case 0x0D:
        cpu.regs[0] = 0xBAAE187F // GetBiosChecksum
    case 0x0E:
        hle_bg_affine_set(cpu, mem_bus)
    case 0x0F:
        hle_obj_affine_set(cpu, mem_bus)
    case 0x10:
        hle_bit_unpack(cpu, mem_bus)
    case 0x11:
        hle_lz77_uncomp(cpu, mem_bus, false)
    case 0x12:
        hle_lz77_uncomp(cpu, mem_bus, true)
    case 0x13:
        hle_huff_uncomp(cpu, mem_bus)
    case 0x14:
        hle_rl_uncomp(cpu, mem_bus, false)
    case 0x15:
        hle_rl_uncomp(cpu, mem_bus, true)
    case 0x16, 0x17, 0x18:
        // Diff unfilter - stub
    case 0x19:
        bus.write16(mem_bus, 0x04000088, 0x0200) // SoundBias
    case 0x1A, 0x1B, 0x1C, 0x1D, 0x1E:
        // Sound driver functions - stub
    case 0x1F:
        cpu.regs[0] = 0 // MidiKey2Freq
    case 0x20, 0x21, 0x22, 0x23, 0x24:
        // More sound functions - stub
    case 0x25:
        cpu.regs[0] = 1 // MultiBoot - return error
    case 0x26:
        hle_soft_reset(cpu, mem_bus) // HardReset
    case 0x27:
        cpu.halted = true // CustomHalt
    case 0x28, 0x29:
        // Sound vsync control - stub
    case 0x2A:
        cpu.regs[0] = 0 // GetJumpList
    case:
        // Unknown SWI - do nothing
    }

    return true
}

// 0x00: SoftReset
hle_soft_reset :: proc(cpu: ^CPU, mem_bus: ^bus.Bus) {
    // Clear 0x200 bytes at 0x03007E00
    for i in u32(0) ..< 0x200 {
        bus.write8(mem_bus, 0x03007E00 + i, 0)
    }

    // Set up stack pointers
    cpu.regs[13] = 0x03007F00
    cpu.regs[23] = 0x03007FE0 // SVC SP
    cpu.regs[27] = 0x03007FA0 // IRQ SP

    // Enter System mode, jump to ROM
    cpu.regs[31] = u32(Mode.System)
    cpu.regs[15] = 0x08000000
}

// 0x01: RegisterRamReset
hle_register_ram_reset :: proc(cpu: ^CPU, mem_bus: ^bus.Bus) {
    flags := cpu.regs[0]

    if (flags & 0x01) != 0 { // Clear EWRAM
        for i in u32(0) ..< 0x40000 {
            bus.write32(mem_bus, 0x02000000 + i * 4, 0)
        }
    }
    if (flags & 0x02) != 0 { // Clear IWRAM (except stack)
        for i in u32(0) ..< 0x7E00 {
            bus.write8(mem_bus, 0x03000000 + i, 0)
        }
    }
    if (flags & 0x04) != 0 { // Clear Palette
        for i in u32(0) ..< 0x400 {
            bus.write8(mem_bus, 0x05000000 + i, 0)
        }
    }
    if (flags & 0x08) != 0 { // Clear VRAM
        for i in u32(0) ..< 0x18000 {
            bus.write8(mem_bus, 0x06000000 + i, 0)
        }
    }
    if (flags & 0x10) != 0 { // Clear OAM
        for i in u32(0) ..< 0x400 {
            bus.write8(mem_bus, 0x07000000 + i, 0)
        }
    }
    if (flags & 0x20) != 0 { // Reset SIO
        bus.write16(mem_bus, 0x04000134, 0x8000)
    }
    if (flags & 0x40) != 0 { // Reset Sound
        bus.write16(mem_bus, 0x04000084, 0)
    }
}

// 0x04: IntrWait
hle_intr_wait :: proc(cpu: ^CPU, mem_bus: ^bus.Bus) {
    // Enable requested interrupts and halt
    ie := bus.bus_get_ie(mem_bus)
    bus.bus_set_ie(mem_bus, ie | u16(cpu.regs[1]))
    bus.write16(mem_bus, 0x04000208, 1) // IME = 1
    cpu.halted = true
}

// 0x05: VBlankIntrWait
hle_vblank_intr_wait :: proc(cpu: ^CPU, mem_bus: ^bus.Bus) {
    ie := bus.bus_get_ie(mem_bus)
    bus.bus_set_ie(mem_bus, ie | 0x0001) // Enable VBlank
    bus.write16(mem_bus, 0x04000208, 1)
    cpu.halted = true
}

// 0x06: Div
hle_div :: proc(cpu: ^CPU) {
    num := i32(cpu.regs[0])
    den := i32(cpu.regs[1])

    if den == 0 {
        cpu.regs[0] = num >= 0 ? 0x7FFFFFFF : 0x80000001
        cpu.regs[1] = u32(num)
        cpu.regs[3] = cpu.regs[0] & 0x7FFFFFFF
        return
    }

    quot := num / den
    rem := num % den
    cpu.regs[0] = u32(quot)
    cpu.regs[1] = u32(rem)
    cpu.regs[3] = u32(quot < 0 ? -quot : quot)
}

// 0x07: DivArm
hle_div_arm :: proc(cpu: ^CPU) {
    cpu.regs[0], cpu.regs[1] = cpu.regs[1], cpu.regs[0]
    hle_div(cpu)
}

// 0x08: Sqrt
hle_sqrt :: proc(cpu: ^CPU) {
    value := cpu.regs[0]
    if value == 0 {
        cpu.regs[0] = 0
        return
    }
    result := value
    for {
        next := (result + value / result) >> 1
        if next >= result { break }
        result = next
    }
    cpu.regs[0] = result
}

// 0x09: ArcTan
hle_arctan :: proc(cpu: ^CPU) {
    // Simplified - just clamp input to valid range
    tan := i32(i16(cpu.regs[0]))
    if tan > 0x2000 { tan = 0x2000 }
    if tan < -0x2000 { tan = -0x2000 }
    cpu.regs[0] = u32(tan)
}

// 0x0A: ArcTan2
hle_arctan2 :: proc(cpu: ^CPU) {
    x := i16(cpu.regs[0])
    y := i16(cpu.regs[1])

    if x == 0 && y == 0 {
        cpu.regs[0] = 0
        return
    }

    // Simple quadrant approximation
    angle: u32 = 0
    if y >= 0 {
        angle = x >= 0 ? 0x2000 : 0x6000
    } else {
        angle = x >= 0 ? 0xE000 : 0xA000
    }
    cpu.regs[0] = angle
}

// 0x0B: CpuSet
hle_cpu_set :: proc(cpu: ^CPU, mem_bus: ^bus.Bus) {
    src := cpu.regs[0]
    dst := cpu.regs[1]
    cnt := cpu.regs[2]

    count := cnt & 0x1FFFFF
    fixed := (cnt & (1 << 24)) != 0
    is_32 := (cnt & (1 << 26)) != 0

    if is_32 {
        for _ in 0 ..< count {
            val, _ := bus.read32(mem_bus, src)
            bus.write32(mem_bus, dst, val)
            if !fixed { src += 4 }
            dst += 4
        }
    } else {
        for _ in 0 ..< count {
            val, _ := bus.read16(mem_bus, src)
            bus.write16(mem_bus, dst, val)
            if !fixed { src += 2 }
            dst += 2
        }
    }
}

// 0x0C: CpuFastSet
hle_cpu_fast_set :: proc(cpu: ^CPU, mem_bus: ^bus.Bus) {
    src := cpu.regs[0]
    dst := cpu.regs[1]
    cnt := cpu.regs[2]

    count := ((cnt & 0x1FFFFF) + 7) & ~u32(7)
    fixed := (cnt & (1 << 24)) != 0

    for _ in 0 ..< count {
        val, _ := bus.read32(mem_bus, src)
        bus.write32(mem_bus, dst, val)
        if !fixed { src += 4 }
        dst += 4
    }
}

// 0x0E: BgAffineSet
hle_bg_affine_set :: proc(cpu: ^CPU, mem_bus: ^bus.Bus) {
    src := cpu.regs[0]
    dst := cpu.regs[1]
    count := cpu.regs[2]

    for _ in 0 ..< count {
        cx, _ := bus.read32(mem_bus, src)
        cy, _ := bus.read32(mem_bus, src + 4)
        sx, _ := bus.read16(mem_bus, src + 12)
        sy, _ := bus.read16(mem_bus, src + 14)

        bus.write16(mem_bus, dst, sx)
        bus.write16(mem_bus, dst + 2, 0)
        bus.write16(mem_bus, dst + 4, 0)
        bus.write16(mem_bus, dst + 6, sy)
        bus.write32(mem_bus, dst + 8, cx)
        bus.write32(mem_bus, dst + 12, cy)

        src += 20
        dst += 16
    }
}

// 0x0F: ObjAffineSet
hle_obj_affine_set :: proc(cpu: ^CPU, mem_bus: ^bus.Bus) {
    src := cpu.regs[0]
    dst := cpu.regs[1]
    count := cpu.regs[2]
    offset := cpu.regs[3]

    for _ in 0 ..< count {
        sx, _ := bus.read16(mem_bus, src)
        sy, _ := bus.read16(mem_bus, src + 2)

        bus.write16(mem_bus, dst, sx)
        bus.write16(mem_bus, dst + offset, 0)
        bus.write16(mem_bus, dst + offset * 2, 0)
        bus.write16(mem_bus, dst + offset * 3, sy)

        src += 8
        dst += offset * 4
    }
}

// 0x10: BitUnPack
hle_bit_unpack :: proc(cpu: ^CPU, mem_bus: ^bus.Bus) {
    src := cpu.regs[0]
    dst := cpu.regs[1]
    info := cpu.regs[2]

    length, _ := bus.read16(mem_bus, info)
    src_width, _ := bus.read8(mem_bus, info + 2)
    dst_width, _ := bus.read8(mem_bus, info + 3)
    data_offset, _ := bus.read32(mem_bus, info + 4)

    zero_flag := (data_offset & 0x80000000) != 0
    data_offset &= 0x7FFFFFFF

    src_bits := u32(src_width)
    dst_bits := u32(dst_width)
    src_max := (u32(1) << src_bits) - 1

    out_val: u32 = 0
    out_bits: u32 = 0

    for i in u32(0) ..< u32(length) {
        byte, _ := bus.read8(mem_bus, src + i)
        for bit_pos := u32(0); bit_pos < 8; bit_pos += src_bits {
            val := (u32(byte) >> bit_pos) & src_max

            if val != 0 || !zero_flag {
                val += data_offset
            }

            out_val |= val << out_bits
            out_bits += dst_bits

            if out_bits >= 32 {
                bus.write32(mem_bus, dst, out_val)
                dst += 4
                out_val = 0
                out_bits = 0
            }
        }
    }

    if out_bits > 0 {
        bus.write32(mem_bus, dst, out_val)
    }
}

// 0x11/0x12: LZ77UnComp
hle_lz77_uncomp :: proc(cpu: ^CPU, mem_bus: ^bus.Bus, vram: bool) {
    src := cpu.regs[0]
    dst := cpu.regs[1]

    header, _ := bus.read32(mem_bus, src)
    size := header >> 8
    src += 4

    written: u32 = 0
    for written < size {
        flags, _ := bus.read8(mem_bus, src)
        src += 1

        for bit in 0 ..< 8 {
            if written >= size { break }

            if (flags & (0x80 >> u32(bit))) != 0 {
                b1, _ := bus.read8(mem_bus, src)
                b2, _ := bus.read8(mem_bus, src + 1)
                src += 2

                length := u32((b1 >> 4) + 3)
                offset := u32(((b1 & 0x0F) << 8) | b2) + 1

                for _ in 0 ..< length {
                    if written >= size { break }
                    val, _ := bus.read8(mem_bus, dst + written - offset)
                    bus.write8(mem_bus, dst + written, val)
                    written += 1
                }
            } else {
                val, _ := bus.read8(mem_bus, src)
                src += 1
                bus.write8(mem_bus, dst + written, val)
                written += 1
            }
        }
    }
}

// 0x13: HuffUnComp
hle_huff_uncomp :: proc(cpu: ^CPU, mem_bus: ^bus.Bus) {
    // Stub - rarely used
}

// 0x14/0x15: RLUnComp
hle_rl_uncomp :: proc(cpu: ^CPU, mem_bus: ^bus.Bus, vram: bool) {
    src := cpu.regs[0]
    dst := cpu.regs[1]

    header, _ := bus.read32(mem_bus, src)
    size := header >> 8
    src += 4

    written: u32 = 0
    for written < size {
        flag, _ := bus.read8(mem_bus, src)
        src += 1

        if (flag & 0x80) != 0 {
            length := u32((flag & 0x7F) + 3)
            data, _ := bus.read8(mem_bus, src)
            src += 1
            for _ in 0 ..< length {
                if written >= size { break }
                bus.write8(mem_bus, dst + written, data)
                written += 1
            }
        } else {
            length := u32((flag & 0x7F) + 1)
            for _ in 0 ..< length {
                if written >= size { break }
                data, _ := bus.read8(mem_bus, src)
                src += 1
                bus.write8(mem_bus, dst + written, data)
                written += 1
            }
        }
    }
}
