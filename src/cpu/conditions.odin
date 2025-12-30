package cpu

// Condition code lookup table
// Index: [condition_code (4 bits)][flags NZCV (4 bits)] = 16 * 16 = 256 entries
// Flags are packed as: N<<3 | Z<<2 | C<<1 | V

condition_lut: [16][16]bool

// Initialize the condition lookup table at program startup
@(init)
init_condition_lut :: proc "contextless" () {
    for cond in 0 ..< 16 {
        for flags in 0 ..< 16 {
            n := (flags & 0x8) != 0
            z := (flags & 0x4) != 0
            c := (flags & 0x2) != 0
            v := (flags & 0x1) != 0

            result: bool
            switch cond {
            case 0x0: // EQ - Z set
                result = z
            case 0x1: // NE - Z clear
                result = !z
            case 0x2: // CS/HS - C set
                result = c
            case 0x3: // CC/LO - C clear
                result = !c
            case 0x4: // MI - N set
                result = n
            case 0x5: // PL - N clear
                result = !n
            case 0x6: // VS - V set
                result = v
            case 0x7: // VC - V clear
                result = !v
            case 0x8: // HI - C set and Z clear
                result = c && !z
            case 0x9: // LS - C clear or Z set
                result = !c || z
            case 0xA: // GE - N equals V
                result = n == v
            case 0xB: // LT - N not equal to V
                result = n != v
            case 0xC: // GT - Z clear and N equals V
                result = !z && (n == v)
            case 0xD: // LE - Z set or N not equal to V
                result = z || (n != v)
            case 0xE: // AL - Always
                result = true
            case 0xF: // NV - Never (ARMv4T: never execute, ARMv5+: unconditional)
                // GBA uses ARMv4T, so this should never execute
                result = false
            case:
                result = false
            }

            condition_lut[cond][flags] = result
        }
    }
}

// Check if condition passes given current CPU state
check_condition :: proc(cpu: ^CPU, condition: u4) -> bool {
    // Pack flags: N<<3 | Z<<2 | C<<1 | V
    flags: u8 = 0
    if get_flag_n(cpu) {
        flags |= 0x8
    }
    if get_flag_z(cpu) {
        flags |= 0x4
    }
    if get_flag_c(cpu) {
        flags |= 0x2
    }
    if get_flag_v(cpu) {
        flags |= 0x1
    }

    return condition_lut[condition][flags]
}

// Extract condition code from ARM instruction
get_condition_code :: proc(opcode: u32) -> u4 {
    return u4((opcode >> 28) & 0xF)
}
