package cpu

import "core:fmt"

// 4-bit register index type
u4 :: distinct u8

// Register file indices (37 total registers)
// Index 0-7:    r0-r7 (unbanked, shared)
// Index 8-12:   r8-r12 (User/System)
// Index 13-14:  r13-r14 (User/System)
// Index 15:     r15/PC (unbanked)
// Index 16-20:  r8_fiq - r12_fiq
// Index 21-22:  r13_fiq, r14_fiq
// Index 23-24:  r13_svc, r14_svc
// Index 25-26:  r13_abt, r14_abt
// Index 27-28:  r13_irq, r14_irq
// Index 29-30:  r13_und, r14_und
// Index 31:     CPSR
// Index 32-36:  SPSR_fiq, SPSR_svc, SPSR_abt, SPSR_irq, SPSR_und

NUM_REGISTERS :: 37

// Mode values
Mode :: enum u8 {
    User       = 0b10000,
    FIQ        = 0b10001,
    IRQ        = 0b10010,
    Supervisor = 0b10011,
    Abort      = 0b10111,
    Undefined  = 0b11011,
    System     = 0b11111,
}

// CPSR bit positions
CPSR_N :: 31
CPSR_Z :: 30
CPSR_C :: 29
CPSR_V :: 28
CPSR_I :: 7
CPSR_F :: 6
CPSR_T :: 5
CPSR_MODE_MASK :: 0x1F

// Exception vectors
VECTOR_RESET :: 0x00000000
VECTOR_UNDEFINED :: 0x00000004
VECTOR_SWI :: 0x00000008
VECTOR_PREFETCH_ABORT :: 0x0000000C
VECTOR_DATA_ABORT :: 0x00000010
VECTOR_IRQ :: 0x00000018
VECTOR_FIQ :: 0x0000001C

CPU :: struct {
    // Register file
    regs: [NUM_REGISTERS]u32,

    // Pipeline simulation
    pipeline: [2]u32, // [0] = fetch, [1] = decode
    pipeline_valid: bool,

    // Halt state
    halted: bool,

    // For open bus emulation
    last_fetched_opcode: u32,

    // Cycle tracking for current instruction
    cycles: u32,
}

// Register bank mapping for each mode
// Returns the physical index offset for banked registers
@(private)
mode_to_bank_offset :: proc(mode: Mode) -> int {
    #partial switch mode {
    case .FIQ:
        return 16 - 8 // r8-r12 at indices 16-20, r13-r14 at 21-22
    case .Supervisor:
        return 23 - 13 // r13-r14 at indices 23-24
    case .Abort:
        return 25 - 13 // r13-r14 at indices 25-26
    case .IRQ:
        return 27 - 13 // r13-r14 at indices 27-28
    case .Undefined:
        return 29 - 13 // r13-r14 at indices 29-30
    case:
        return 0 // User/System use base registers
    }
}

// Get physical register index from logical register number
@(private)
get_physical_reg_index :: proc(cpu: ^CPU, n: u4) -> int {
    mode := get_mode(cpu)

    // r0-r7 and r15 are never banked
    if n <= 7 || n == 15 {
        return int(n)
    }

    // r8-r12 are only banked in FIQ mode
    if n >= 8 && n <= 12 {
        if mode == .FIQ {
            return int(n) + 8 // 16-20
        }
        return int(n)
    }

    // r13-r14 are banked per mode
    #partial switch mode {
    case .FIQ:
        return int(n) + 8 // 21-22
    case .Supervisor:
        return int(n) + 10 // 23-24
    case .Abort:
        return int(n) + 12 // 25-26
    case .IRQ:
        return int(n) + 14 // 27-28
    case .Undefined:
        return int(n) + 16 // 29-30
    case:
        return int(n) // User/System
    }
}

// SPSR index for each exception mode
@(private)
get_spsr_index :: proc(mode: Mode) -> int {
    #partial switch mode {
    case .FIQ:
        return 32
    case .Supervisor:
        return 33
    case .Abort:
        return 34
    case .IRQ:
        return 35
    case .Undefined:
        return 36
    case:
        return -1 // User/System have no SPSR
    }
}

// Initialize CPU to reset state
cpu_init :: proc(cpu: ^CPU) {
    // Clear all registers
    for i in 0 ..< NUM_REGISTERS {
        cpu.regs[i] = 0
    }

    // Set initial CPSR: Supervisor mode, IRQ/FIQ disabled, ARM state
    cpu.regs[31] = u32(Mode.Supervisor) | (1 << CPSR_I) | (1 << CPSR_F)

    // PC starts at 0 (reset vector)
    cpu.regs[15] = 0

    cpu.pipeline_valid = false
    cpu.halted = false
    cpu.last_fetched_opcode = 0
    cpu.cycles = 0
}

// Get register value with banking
get_reg :: proc(cpu: ^CPU, n: u4) -> u32 {
    idx := get_physical_reg_index(cpu, n)
    value := cpu.regs[idx]

    // PC reads return current instruction + 8 (ARM) or + 4 (Thumb)
    if n == 15 {
        if is_thumb(cpu) {
            return value + 4
        } else {
            return value + 8
        }
    }
    return value
}

// Set register value with banking
set_reg :: proc(cpu: ^CPU, n: u4, value: u32) {
    idx := get_physical_reg_index(cpu, n)
    cpu.regs[idx] = value

    // Writing to PC invalidates pipeline
    if n == 15 {
        cpu.pipeline_valid = false
    }
}

// Get raw PC (without pipeline offset)
get_pc :: proc(cpu: ^CPU) -> u32 {
    return cpu.regs[15]
}

// Set PC directly
set_pc :: proc(cpu: ^CPU, value: u32) {
    cpu.regs[15] = value
    cpu.pipeline_valid = false
}

// Get CPSR
get_cpsr :: proc(cpu: ^CPU) -> u32 {
    return cpu.regs[31]
}

// Set CPSR (may trigger mode switch)
set_cpsr :: proc(cpu: ^CPU, value: u32) {
    old_mode := get_mode(cpu)
    cpu.regs[31] = value
    new_mode := get_mode(cpu)

    // Mode switch is handled by register banking automatically
    _ = old_mode
    _ = new_mode
}

// Get current mode's SPSR
get_spsr :: proc(cpu: ^CPU) -> u32 {
    mode := get_mode(cpu)
    idx := get_spsr_index(mode)
    if idx < 0 {
        // User/System mode - return CPSR
        return cpu.regs[31]
    }
    return cpu.regs[idx]
}

// Set current mode's SPSR
set_spsr :: proc(cpu: ^CPU, value: u32) {
    mode := get_mode(cpu)
    idx := get_spsr_index(mode)
    if idx >= 0 {
        cpu.regs[idx] = value
    }
}

// Get current CPU mode
get_mode :: proc(cpu: ^CPU) -> Mode {
    return Mode(cpu.regs[31] & CPSR_MODE_MASK)
}

// Set CPU mode
set_mode :: proc(cpu: ^CPU, mode: Mode) {
    cpu.regs[31] = (cpu.regs[31] & ~u32(CPSR_MODE_MASK)) | u32(mode)
}

// Check if in Thumb state
is_thumb :: proc(cpu: ^CPU) -> bool {
    return (cpu.regs[31] & (1 << CPSR_T)) != 0
}

// Set/clear Thumb state
set_thumb :: proc(cpu: ^CPU, thumb: bool) {
    if thumb {
        cpu.regs[31] |= (1 << CPSR_T)
    } else {
        cpu.regs[31] &= ~u32(1 << CPSR_T)
    }
}

// Get individual flags
get_flag_n :: proc(cpu: ^CPU) -> bool {
    return (cpu.regs[31] & (1 << CPSR_N)) != 0
}

get_flag_z :: proc(cpu: ^CPU) -> bool {
    return (cpu.regs[31] & (1 << CPSR_Z)) != 0
}

get_flag_c :: proc(cpu: ^CPU) -> bool {
    return (cpu.regs[31] & (1 << CPSR_C)) != 0
}

get_flag_v :: proc(cpu: ^CPU) -> bool {
    return (cpu.regs[31] & (1 << CPSR_V)) != 0
}

// Set flags
set_flag_n :: proc(cpu: ^CPU, value: bool) {
    if value {
        cpu.regs[31] |= (1 << CPSR_N)
    } else {
        cpu.regs[31] &= ~u32(1 << CPSR_N)
    }
}

set_flag_z :: proc(cpu: ^CPU, value: bool) {
    if value {
        cpu.regs[31] |= (1 << CPSR_Z)
    } else {
        cpu.regs[31] &= ~u32(1 << CPSR_Z)
    }
}

set_flag_c :: proc(cpu: ^CPU, value: bool) {
    if value {
        cpu.regs[31] |= (1 << CPSR_C)
    } else {
        cpu.regs[31] &= ~u32(1 << CPSR_C)
    }
}

set_flag_v :: proc(cpu: ^CPU, value: bool) {
    if value {
        cpu.regs[31] |= (1 << CPSR_V)
    } else {
        cpu.regs[31] &= ~u32(1 << CPSR_V)
    }
}

// Set N and Z flags based on result
set_nz_flags :: proc(cpu: ^CPU, result: u32) {
    set_flag_n(cpu, (result & 0x80000000) != 0)
    set_flag_z(cpu, result == 0)
}

// Check IRQ enabled
irq_enabled :: proc(cpu: ^CPU) -> bool {
    return (cpu.regs[31] & (1 << CPSR_I)) == 0
}

// Check FIQ enabled
fiq_enabled :: proc(cpu: ^CPU) -> bool {
    return (cpu.regs[31] & (1 << CPSR_F)) == 0
}

// Enter exception mode
exception_enter :: proc(cpu: ^CPU, mode: Mode, vector: u32, return_offset: u32) {
    // Save current CPSR to new mode's SPSR
    old_cpsr := get_cpsr(cpu)

    // Switch to new mode
    new_cpsr := (old_cpsr & ~u32(CPSR_MODE_MASK)) | u32(mode)
    new_cpsr |= (1 << CPSR_I) // Disable IRQ

    if mode == .FIQ {
        new_cpsr |= (1 << CPSR_F) // Disable FIQ for FIQ/Reset
    }

    new_cpsr &= ~u32(1 << CPSR_T) // Enter ARM state

    set_cpsr(cpu, new_cpsr)

    // Save old CPSR to new mode's SPSR
    set_spsr(cpu, old_cpsr)

    // Save return address to LR
    // The return address calculation depends on the instruction
    set_reg(cpu, 14, get_pc(cpu) + return_offset)

    // Jump to vector
    set_pc(cpu, vector)
}

// Software interrupt
swi :: proc(cpu: ^CPU) {
    exception_enter(cpu, .Supervisor, VECTOR_SWI, 0)
}

// Undefined instruction
undefined :: proc(cpu: ^CPU) {
    exception_enter(cpu, .Undefined, VECTOR_UNDEFINED, 0)
}

// IRQ
irq :: proc(cpu: ^CPU) {
    exception_enter(cpu, .IRQ, VECTOR_IRQ, 4)
}

// FIQ
fiq :: proc(cpu: ^CPU) {
    exception_enter(cpu, .FIQ, VECTOR_FIQ, 4)
}

// Prefetch abort
prefetch_abort :: proc(cpu: ^CPU) {
    exception_enter(cpu, .Abort, VECTOR_PREFETCH_ABORT, 4)
}

// Data abort
data_abort :: proc(cpu: ^CPU) {
    exception_enter(cpu, .Abort, VECTOR_DATA_ABORT, 8)
}

// Halt the CPU
halt :: proc(cpu: ^CPU) {
    cpu.halted = true
}

// Unhalt the CPU (on interrupt)
unhalt :: proc(cpu: ^CPU) {
    cpu.halted = false
}
