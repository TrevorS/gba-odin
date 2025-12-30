# GBA Emulator Technical Requirements Specification

## Document Overview

This specification defines the technical requirements for Phase 1 of a Game Boy Advance emulator implemented in Odin. Phase 1 covers CPU execution, memory subsystem, bus architecture, event scheduling, and supporting infrastructure. PPU, APU, DMA, and timers are out of scope for Phase 1 but their integration points are defined.

---

## 1. System Architecture

### 1.1 Top-Level Structure

**REQ-SYS-001**: The emulator shall be organized as a single `GBA` struct that owns all subsystem state.

**REQ-SYS-002**: The `GBA` struct shall contain:
- `cpu`: ARM7TDMI processor state
- `bus`: Memory bus and I/O registers
- `scheduler`: Event-driven timing coordinator
- `ppu`: Picture processing unit state (stub in Phase 1)
- `apu`: Audio processing unit state (stub in Phase 1)
- `dma`: DMA controller state (stub in Phase 1)
- `timers`: Timer 0-3 state (stub in Phase 1)
- `keypad`: Input state
- `cartridge`: ROM and save memory

**REQ-SYS-003**: The main loop shall follow this execution model:
```
1. Peek next scheduled event timestamp
2. Execute CPU instructions until cycle count reaches event timestamp
3. Pop and handle the event
4. If event was frame-complete, present frame and poll input
5. Repeat
```

**REQ-SYS-004**: The emulator shall track time using a 64-bit unsigned cycle counter. This counter shall never be reset during emulation (wrap-around occurs after ~34,000 years at 16.78 MHz).

**REQ-SYS-005**: The emulator shall target a master clock of 16,777,216 Hz (2^24 Hz) for cycle timing calculations.

---

## 2. Memory Subsystem

### 2.1 Allocator Requirements

**REQ-MEM-001**: The emulator shall use a custom arena allocator for all emulated memory regions.

**REQ-MEM-002**: The arena allocator shall support the following operations:
- `arena_init(size: uint) -> ^Arena`: Allocate backing memory
- `arena_alloc(arena: ^Arena, size: uint, align: uint) -> []u8`: Sub-allocate from arena
- `arena_reset(arena: ^Arena)`: Reset allocation pointer (for save state restore)
- `arena_destroy(arena: ^Arena)`: Free backing memory

**REQ-MEM-003**: The arena shall perform a single OS allocation at initialization. All subsequent allocations shall be pointer bumps with no system calls.

**REQ-MEM-004**: Arena allocations shall support alignment requirements up to 4096 bytes.

**REQ-MEM-005**: The arena shall track high-water mark for debugging/profiling purposes.

### 2.2 Memory Region Definitions

**REQ-MEM-010**: The emulator shall define the following memory regions with exact sizes:

| Region ID | Name                  | Size (bytes) | Alignment |
|-----------|-----------------------|--------------|-----------|
| BIOS      | System ROM            | 16,384       | 4         |
| EWRAM     | External Work RAM     | 262,144      | 4         |
| IWRAM     | Internal Work RAM     | 32,768       | 4         |
| PALETTE   | Palette RAM           | 1,024        | 4         |
| VRAM      | Video RAM             | 98,304       | 4         |
| OAM       | Object Attribute Mem  | 1,024        | 4         |
| IO        | I/O Registers         | 1,024        | 4         |

**REQ-MEM-011**: ROM and save memory shall be allocated separately from the main arena, with sizes determined at cartridge load time.

**REQ-MEM-012**: The total fixed arena size shall be exactly 411,648 bytes (sum of regions in REQ-MEM-010).

**REQ-MEM-013**: Each memory region shall be represented as a slice (`[]u8`) pointing into the arena.

### 2.3 Memory Initialization

**REQ-MEM-020**: BIOS memory shall be initialized by loading from an external file.

**REQ-MEM-021**: EWRAM shall be initialized to zero on power-on.

**REQ-MEM-022**: IWRAM shall be initialized to zero on power-on.

**REQ-MEM-023**: Palette RAM shall be initialized to zero on power-on.

**REQ-MEM-024**: VRAM shall be initialized to zero on power-on.

**REQ-MEM-025**: OAM shall be initialized to zero on power-on.

**REQ-MEM-026**: I/O register region shall be initialized with hardware default values as specified in section 4.3.

---

## 3. CPU (ARM7TDMI)

### 3.1 Register File

**REQ-CPU-001**: The CPU shall implement the full ARM7TDMI register file:
- 16 general-purpose registers visible at any time (r0-r15)
- r13 (SP), r14 (LR) banked per mode (6 copies each)
- r8-r12 banked for FIQ mode (2 copies each)
- Current Program Status Register (CPSR)
- 5 Saved Program Status Registers (SPSR), one per exception mode

**REQ-CPU-002**: The register file shall be stored as a flat array with the following layout:
```
Index 0-7:    r0-r7 (unbanked, shared)
Index 8-12:   r8-r12 (User/System)
Index 13-14:  r13-r14 (User/System)
Index 15:     r15/PC (unbanked)
Index 16-20:  r8_fiq - r12_fiq
Index 21-22:  r13_fiq, r14_fiq
Index 23-24:  r13_svc, r14_svc
Index 25-26:  r13_abt, r14_abt
Index 27-28:  r13_irq, r14_irq
Index 29-30:  r13_und, r14_und
Index 31:     CPSR
Index 32-36:  SPSR_fiq, SPSR_svc, SPSR_abt, SPSR_irq, SPSR_und
```

**REQ-CPU-003**: Register access functions shall map logical register numbers (0-15) to physical indices based on current CPU mode.

**REQ-CPU-004**: The following accessor functions shall be implemented:
- `get_reg(cpu: ^CPU, n: u4) -> u32`: Read register with banking
- `set_reg(cpu: ^CPU, n: u4, value: u32)`: Write register with banking
- `get_cpsr(cpu: ^CPU) -> u32`: Read CPSR
- `set_cpsr(cpu: ^CPU, value: u32)`: Write CPSR (may trigger mode switch)
- `get_spsr(cpu: ^CPU) -> u32`: Read current mode's SPSR
- `set_spsr(cpu: ^CPU, value: u32)`: Write current mode's SPSR

**REQ-CPU-005**: All register accessors shall be marked `#force_inline`.

### 3.2 CPSR/SPSR Format

**REQ-CPU-010**: The CPSR/SPSR shall use the following bit layout:

| Bits  | Name     | Description           |
|-------|----------|-----------------------|
| 31    | N        | Negative/Less than    |
| 30    | Z        | Zero                  |
| 29    | C        | Carry/Borrow/Extend   |
| 28    | V        | Overflow              |
| 27-8  | Reserved | Read as zero          |
| 7     | I        | IRQ disable           |
| 6     | F        | FIQ disable           |
| 5     | T        | Thumb state           |
| 4-0   | Mode     | Processor mode        |

**REQ-CPU-011**: The following mode values shall be recognized:

| Value    | Mode       | Description         |
|----------|------------|---------------------|
| 0b10000  | User       | Normal execution    |
| 0b10001  | FIQ        | Fast interrupt      |
| 0b10010  | IRQ        | Normal interrupt    |
| 0b10011  | Supervisor | SWI                 |
| 0b10111  | Abort      | Prefetch/data abort |
| 0b11011  | Undefined  | Undefined instr     |
| 0b11111  | System     | Privileged User     |

**REQ-CPU-012**: Writing to CPSR mode bits shall trigger register bank switching. The previous mode's banked registers shall remain in their physical locations; only the mapping changes.

**REQ-CPU-013**: Writing to CPSR.T shall switch between ARM and Thumb execution state.

### 3.3 Condition Evaluation

**REQ-CPU-020**: The CPU shall implement a 256-byte lookup table for condition evaluation: `condition_lut[cond][flags] -> bool` where:
- `cond`: 4-bit condition code (bits 31-28 of ARM instruction)
- `flags`: 4-bit flag state (N, Z, C, V packed as `N<<3 | Z<<2 | C<<1 | V`)

**REQ-CPU-021**: The condition lookup table shall be initialized at program startup using `@(init)`.

**REQ-CPU-022**: The following conditions shall be implemented:

| Code | Mnemonic | Condition            |
|------|----------|----------------------|
| 0x0  | EQ       | Z == 1               |
| 0x1  | NE       | Z == 0               |
| 0x2  | CS/HS    | C == 1               |
| 0x3  | CC/LO    | C == 0               |
| 0x4  | MI       | N == 1               |
| 0x5  | PL       | N == 0               |
| 0x6  | VS       | V == 1               |
| 0x7  | VC       | V == 0               |
| 0x8  | HI       | C == 1 AND Z == 0    |
| 0x9  | LS       | C == 0 OR Z == 1     |
| 0xA  | GE       | N == V               |
| 0xB  | LT       | N != V               |
| 0xC  | GT       | Z == 0 AND N == V    |
| 0xD  | LE       | Z == 1 OR N != V     |
| 0xE  | AL       | Always               |
| 0xF  | NV       | Never (unconditional)|

**REQ-CPU-023**: Condition code 0xF shall be treated as unconditional for ARMv4T compatibility.

### 3.4 Pipeline Emulation

**REQ-CPU-030**: The emulator shall NOT model the three-stage pipeline explicitly.

**REQ-CPU-031**: When an instruction reads the PC (r15), it shall receive the address of the current instruction plus:
- 8 bytes in ARM state
- 4 bytes in Thumb state

**REQ-CPU-032**: When an instruction writes to the PC, execution shall continue at the written address. No pipeline flush modeling is required.

**REQ-CPU-033**: For STR with Rd=PC, the stored value shall be the current instruction address plus 12 in ARM state.

### 3.5 ARM Instruction Decoding

**REQ-CPU-040**: ARM instructions shall be decoded using a 4096-entry lookup table.

**REQ-CPU-041**: The table index shall be computed as: `((opcode >> 16) & 0xFF0) | ((opcode >> 4) & 0x00F)`

This extracts bits [27:20] into the upper 8 bits and bits [7:4] into the lower 4 bits.

**REQ-CPU-042**: Each table entry shall be a procedure pointer of type: `proc(cpu: ^CPU, bus: ^Bus, opcode: u32)`

**REQ-CPU-043**: The table shall be populated at program startup using `@(init)`.

**REQ-CPU-044**: The decoder shall categorize instructions into the following groups:

| Bits [27:25] | Bits [24:20] | Bits [7:4] | Category                        |
|--------------|--------------|------------|---------------------------------|
| 000          | xxxx         | 0xx0       | Data Processing (register)      |
| 000          | xxxx         | 0xx1       | Data Processing (reg-shifted)   |
| 000          | xxxx         | 1001       | Multiply                        |
| 000          | xxxx         | 1011       | Load/Store halfword (reg)       |
| 000          | xxxx         | 11x1       | Load/Store halfword (reg)       |
| 001          | xxxx         | xxxx       | Data Processing (immediate)     |
| 010          | xxxx         | xxxx       | Load/Store word/byte (imm)      |
| 011          | xxxx         | xxx0       | Load/Store word/byte (reg)      |
| 011          | xxxx         | xxx1       | Media instructions (undefined)  |
| 100          | xxxx         | xxxx       | Load/Store multiple             |
| 101          | xxxx         | xxxx       | Branch / Branch with link       |
| 110          | xxxx         | xxxx       | Coprocessor (unused)            |
| 111          | 0xxx         | xxxx       | Coprocessor (unused)            |
| 111          | 10xx         | xxxx       | Coprocessor (unused)            |
| 111          | 11xx         | xxxx       | Software interrupt              |

### 3.6 ARM Instructions (Phase 1)

**REQ-CPU-050**: The following ARM instruction categories shall be implemented in Phase 1:

#### Data Processing

**REQ-CPU-051**: All 16 data processing operations shall be implemented:

| Opcode | Mnemonic | Operation                    |
|--------|----------|------------------------------|
| 0000   | AND      | Rd := Rn AND operand2        |
| 0001   | EOR      | Rd := Rn XOR operand2        |
| 0010   | SUB      | Rd := Rn - operand2          |
| 0011   | RSB      | Rd := operand2 - Rn          |
| 0100   | ADD      | Rd := Rn + operand2          |
| 0101   | ADC      | Rd := Rn + operand2 + C      |
| 0110   | SBC      | Rd := Rn - operand2 - NOT(C) |
| 0111   | RSC      | Rd := operand2 - Rn - NOT(C) |
| 1000   | TST      | Set flags on Rn AND operand2 |
| 1001   | TEQ      | Set flags on Rn XOR operand2 |
| 1010   | CMP      | Set flags on Rn - operand2   |
| 1011   | CMN      | Set flags on Rn + operand2   |
| 1100   | ORR      | Rd := Rn OR operand2         |
| 1101   | MOV      | Rd := operand2               |
| 1110   | BIC      | Rd := Rn AND NOT(operand2)   |
| 1111   | MVN      | Rd := NOT(operand2)          |

**REQ-CPU-052**: Operand2 shall support:
- Immediate: 8-bit value rotated right by 2 × rotate field
- Register: Rm optionally shifted by immediate or register amount
- Shift types: LSL, LSR, ASR, ROR (and RRX as ROR #0)

**REQ-CPU-053**: When S bit is set and Rd is not PC, flags shall be updated:
- N: Set to bit 31 of result
- Z: Set if result is zero
- C: Set to carry output of barrel shifter (for logical ops) or arithmetic carry
- V: Set to overflow (for arithmetic ops only)

**REQ-CPU-054**: When S bit is set and Rd is PC, CPSR shall be restored from current mode's SPSR.

#### Branch

**REQ-CPU-055**: Branch (B) shall add signed 24-bit offset × 4 to PC.

**REQ-CPU-056**: Branch with Link (BL) shall:
1. Store return address (current instruction + 4) in LR
2. Add signed 24-bit offset × 4 to PC

**REQ-CPU-057**: Branch and Exchange (BX) shall:
1. Copy Rm[0] to CPSR.T (switch to Thumb if bit 0 set)
2. Set PC to Rm with bit 0 cleared

#### Load/Store

**REQ-CPU-058**: LDR (Load Register) shall:
1. Calculate address from base register and offset
2. Read 32-bit value from memory
3. If address is not word-aligned, rotate result right by `(address & 3) × 8` bits
4. Store in destination register

**REQ-CPU-059**: STR (Store Register) shall:
1. Calculate address from base register and offset
2. Force-align address to word boundary
3. Write 32-bit value to memory

**REQ-CPU-060**: LDRB (Load Register Byte) shall:
1. Calculate address from base register and offset
2. Read 8-bit value from memory
3. Zero-extend to 32 bits
4. Store in destination register

**REQ-CPU-061**: STRB (Store Register Byte) shall:
1. Calculate address from base register and offset
2. Write lower 8 bits to memory

**REQ-CPU-062**: Addressing modes shall support:
- Pre-indexed: address = base + offset, optionally write back
- Post-indexed: address = base, then base = base + offset
- Offset: register or 12-bit immediate
- Offset direction: add or subtract

#### Load/Store Halfword

**REQ-CPU-063**: LDRH (Load Register Halfword) shall:
1. Calculate address from base register and offset
2. If address is halfword-aligned, read 16-bit value
3. If address is not halfword-aligned, behavior is undefined
4. Zero-extend to 32 bits

**REQ-CPU-064**: STRH (Store Register Halfword) shall:
1. Calculate address from base register and offset
2. Force-align address to halfword boundary
3. Write lower 16 bits to memory

**REQ-CPU-065**: LDRSH (Load Register Signed Halfword) shall:
1. Load halfword as LDRH
2. Sign-extend bit 15 to bits 31-16

**REQ-CPU-066**: LDRSB (Load Register Signed Byte) shall:
1. Load byte
2. Sign-extend bit 7 to bits 31-8

#### Load/Store Multiple

**REQ-CPU-067**: LDM (Load Multiple) shall:
1. Calculate base address
2. For each bit set in register list (low to high), load word to that register
3. Address increments by 4 for each register
4. If W bit set, write back final address to base register
5. If PC is in register list and S bit set, restore CPSR from SPSR

**REQ-CPU-068**: STM (Store Multiple) shall:
1. Calculate base address
2. For each bit set in register list (low to high), store that register
3. Address increments by 4 for each register
4. If W bit set, write back final address to base register

**REQ-CPU-069**: Addressing modes shall include:
- IA (Increment After): start at base
- IB (Increment Before): start at base + 4
- DA (Decrement After): start at base - 4 × count + 4
- DB (Decrement Before): start at base - 4 × count

#### Multiply

**REQ-CPU-070**: MUL (Multiply) shall compute `Rd := (Rm × Rs)[31:0]`.

**REQ-CPU-071**: MLA (Multiply Accumulate) shall compute `Rd := (Rm × Rs + Rn)[31:0]`.

**REQ-CPU-072**: UMULL (Unsigned Multiply Long) shall compute `RdHi:RdLo := Rm × Rs` (64-bit unsigned).

**REQ-CPU-073**: UMLAL (Unsigned Multiply Accumulate Long) shall compute `RdHi:RdLo := Rm × Rs + RdHi:RdLo` (64-bit unsigned).

**REQ-CPU-074**: SMULL (Signed Multiply Long) shall compute `RdHi:RdLo := Rm × Rs` (64-bit signed).

**REQ-CPU-075**: SMLAL (Signed Multiply Accumulate Long) shall compute `RdHi:RdLo := Rm × Rs + RdHi:RdLo` (64-bit signed).

#### Miscellaneous

**REQ-CPU-076**: SWP (Swap) shall atomically:
1. Read word at [Rn]
2. Write Rm to [Rn]
3. Store read value in Rd

**REQ-CPU-077**: SWPB (Swap Byte) shall perform SWP with byte-sized access.

**REQ-CPU-078**: MRS (Move PSR to Register) shall copy CPSR or SPSR to Rd.

**REQ-CPU-079**: MSR (Move Register to PSR) shall copy Rm or immediate to CPSR or SPSR. In User mode, only condition flags (bits 31-28) may be modified.

**REQ-CPU-080**: SWI (Software Interrupt) shall:
1. Save CPSR to SPSR_svc
2. Set CPSR mode to Supervisor
3. Set CPSR.I (disable IRQ)
4. Set CPSR.T = 0 (ARM state)
5. Save return address (current + 4) to LR_svc
6. Set PC to 0x00000008

**REQ-CPU-081**: Undefined instructions shall trigger the undefined instruction exception:
1. Save CPSR to SPSR_und
2. Set CPSR mode to Undefined
3. Set CPSR.I (disable IRQ)
4. Set CPSR.T = 0 (ARM state)
5. Save return address to LR_und
6. Set PC to 0x00000004

### 3.7 Thumb Instruction Decoding

**REQ-CPU-090**: Thumb instructions shall be decoded using a 256-entry lookup table.

**REQ-CPU-091**: The table index shall be computed as: `opcode >> 8` (upper 8 bits).

**REQ-CPU-092**: Each table entry shall be a procedure pointer of type: `proc(cpu: ^CPU, bus: ^Bus, opcode: u16)`

**REQ-CPU-093**: Some table entries shall perform additional decoding of lower bits within the handler.

### 3.8 Thumb Instructions (Phase 1)

**REQ-CPU-100**: The following Thumb instruction formats shall be implemented:

#### Format 1: Move Shifted Register

**REQ-CPU-101**: LSL Rd, Rs, #Offset (opcode `000xxxxxxxxxxxx`) shall:
1. Shift Rs left by 5-bit offset
2. Store in Rd
3. Update N, Z flags; C = last bit shifted out (if offset > 0)

**REQ-CPU-102**: LSR Rd, Rs, #Offset (opcode `001xxxxxxxxxxxx`) shall:
1. Shift Rs right logically by 5-bit offset (0 means 32)
2. Store in Rd
3. Update N, Z, C flags

**REQ-CPU-103**: ASR Rd, Rs, #Offset (opcode `010xxxxxxxxxxxx`) shall:
1. Shift Rs right arithmetically by 5-bit offset (0 means 32)
2. Store in Rd
3. Update N, Z, C flags

#### Format 2: Add/Subtract

**REQ-CPU-104**: ADD Rd, Rs, Rn (opcode `0001100xxxxxxxx`) shall add Rs + Rn, store in Rd, update flags.

**REQ-CPU-105**: SUB Rd, Rs, Rn (opcode `0001101xxxxxxxx`) shall subtract Rs - Rn, store in Rd, update flags.

**REQ-CPU-106**: ADD Rd, Rs, #nn (opcode `0001110xxxxxxxx`) shall add Rs + 3-bit immediate, store in Rd, update flags.

**REQ-CPU-107**: SUB Rd, Rs, #nn (opcode `0001111xxxxxxxx`) shall subtract Rs - 3-bit immediate, store in Rd, update flags.

#### Format 3: Move/Compare/Add/Subtract Immediate

**REQ-CPU-108**: MOV Rd, #nn (opcode `00100xxxxxxxxxxx`) shall move 8-bit immediate to Rd, update N, Z.

**REQ-CPU-109**: CMP Rd, #nn (opcode `00101xxxxxxxxxxx`) shall compare Rd - immediate, update all flags.

**REQ-CPU-110**: ADD Rd, #nn (opcode `00110xxxxxxxxxxx`) shall add Rd + immediate, update all flags.

**REQ-CPU-111**: SUB Rd, #nn (opcode `00111xxxxxxxxxxx`) shall subtract Rd - immediate, update all flags.

#### Format 4: ALU Operations

**REQ-CPU-112**: Format 4 (opcode `010000xxxx`) shall implement all 16 ALU operations on low registers:

| Op   | Mnemonic | Operation                  |
|------|----------|----------------------------|
| 0000 | AND      | Rd := Rd AND Rs            |
| 0001 | EOR      | Rd := Rd XOR Rs            |
| 0010 | LSL      | Rd := Rd << Rs[7:0]        |
| 0011 | LSR      | Rd := Rd >> Rs[7:0] (log)  |
| 0100 | ASR      | Rd := Rd >> Rs[7:0] (arith)|
| 0101 | ADC      | Rd := Rd + Rs + C          |
| 0110 | SBC      | Rd := Rd - Rs - NOT(C)     |
| 0111 | ROR      | Rd := Rd rotated by Rs[7:0]|
| 1000 | TST      | Update flags for Rd AND Rs |
| 1001 | NEG      | Rd := 0 - Rs               |
| 1010 | CMP      | Update flags for Rd - Rs   |
| 1011 | CMN      | Update flags for Rd + Rs   |
| 1100 | ORR      | Rd := Rd OR Rs             |
| 1101 | MUL      | Rd := Rd × Rs              |
| 1110 | BIC      | Rd := Rd AND NOT(Rs)       |
| 1111 | MVN      | Rd := NOT(Rs)              |

#### Format 5: Hi Register Operations / Branch Exchange

**REQ-CPU-113**: ADD Rd, Rs (opcode `01000100xxxxxxxx`) shall add with one or both high registers.

**REQ-CPU-114**: CMP Rd, Rs (opcode `01000101xxxxxxxx`) shall compare with one or both high registers.

**REQ-CPU-115**: MOV Rd, Rs (opcode `01000110xxxxxxxx`) shall move with one or both high registers.

**REQ-CPU-116**: BX Rs (opcode `010001110xxxx000`) shall branch and exchange:
1. Copy Rs[0] to CPSR.T
2. Set PC to Rs with bit 0 cleared

**REQ-CPU-117**: BLX Rs (opcode `010001111xxxx000`) shall:
1. Store return address in LR
2. Perform BX Rs

#### Format 6: PC-Relative Load

**REQ-CPU-118**: LDR Rd, [PC, #nn] (opcode `01001xxxxxxxxxxx`) shall:
1. Calculate address: `(PC & ~2) + (8-bit offset × 4)`
2. Load word from address
3. Store in Rd

#### Format 7: Load/Store with Register Offset

**REQ-CPU-119**: STR Rd, [Rb, Ro] (opcode `0101000xxxxxxxxx`) shall store word.

**REQ-CPU-120**: STRB Rd, [Rb, Ro] (opcode `0101010xxxxxxxxx`) shall store byte.

**REQ-CPU-121**: LDR Rd, [Rb, Ro] (opcode `0101100xxxxxxxxx`) shall load word.

**REQ-CPU-122**: LDRB Rd, [Rb, Ro] (opcode `0101110xxxxxxxxx`) shall load byte.

#### Format 8: Load/Store Sign-Extended Byte/Halfword

**REQ-CPU-123**: STRH Rd, [Rb, Ro] (opcode `0101001xxxxxxxxx`) shall store halfword.

**REQ-CPU-124**: LDSB Rd, [Rb, Ro] (opcode `0101011xxxxxxxxx`) shall load sign-extended byte.

**REQ-CPU-125**: LDRH Rd, [Rb, Ro] (opcode `0101101xxxxxxxxx`) shall load halfword.

**REQ-CPU-126**: LDSH Rd, [Rb, Ro] (opcode `0101111xxxxxxxxx`) shall load sign-extended halfword.

#### Format 9: Load/Store with Immediate Offset

**REQ-CPU-127**: STR Rd, [Rb, #nn] (opcode `01100xxxxxxxxxxx`) shall store word at Rb + offset×4.

**REQ-CPU-128**: LDR Rd, [Rb, #nn] (opcode `01101xxxxxxxxxxx`) shall load word from Rb + offset×4.

**REQ-CPU-129**: STRB Rd, [Rb, #nn] (opcode `01110xxxxxxxxxxx`) shall store byte at Rb + offset.

**REQ-CPU-130**: LDRB Rd, [Rb, #nn] (opcode `01111xxxxxxxxxxx`) shall load byte from Rb + offset.

#### Format 10: Load/Store Halfword

**REQ-CPU-131**: STRH Rd, [Rb, #nn] (opcode `10000xxxxxxxxxxx`) shall store halfword at Rb + offset×2.

**REQ-CPU-132**: LDRH Rd, [Rb, #nn] (opcode `10001xxxxxxxxxxx`) shall load halfword from Rb + offset×2.

#### Format 11: SP-Relative Load/Store

**REQ-CPU-133**: STR Rd, [SP, #nn] (opcode `10010xxxxxxxxxxx`) shall store word at SP + offset×4.

**REQ-CPU-134**: LDR Rd, [SP, #nn] (opcode `10011xxxxxxxxxxx`) shall load word from SP + offset×4.

#### Format 12: Load Address

**REQ-CPU-135**: ADD Rd, PC, #nn (opcode `10100xxxxxxxxxxx`) shall compute `Rd := (PC & ~2) + offset×4`.

**REQ-CPU-136**: ADD Rd, SP, #nn (opcode `10101xxxxxxxxxxx`) shall compute `Rd := SP + offset×4`.

#### Format 13: Add Offset to Stack Pointer

**REQ-CPU-137**: ADD SP, #nn (opcode `10110000xxxxxxxx`) shall add signed 7-bit offset×4 to SP.

#### Format 14: Push/Pop Registers

**REQ-CPU-138**: PUSH {Rlist} (opcode `1011010xxxxxxxxx`) shall:
1. For each register in list (high to low), decrement SP by 4 and store register
2. If R bit set, also push LR

**REQ-CPU-139**: POP {Rlist} (opcode `1011110xxxxxxxxx`) shall:
1. For each register in list (low to high), load register and increment SP by 4
2. If R bit set, also pop to PC (and potentially switch to ARM via bit 0)

#### Format 15: Multiple Load/Store

**REQ-CPU-140**: STMIA Rb!, {Rlist} (opcode `11000xxxxxxxxxxx`) shall store multiple, increment after, writeback.

**REQ-CPU-141**: LDMIA Rb!, {Rlist} (opcode `11001xxxxxxxxxxx`) shall load multiple, increment after, writeback.

#### Format 16: Conditional Branch

**REQ-CPU-142**: B{cond} label (opcode `1101xxxxxxxxxxxx`) shall branch if condition met:
1. Sign-extend 8-bit offset
2. If condition true, `PC := PC + offset×2`

#### Format 17: Software Interrupt

**REQ-CPU-143**: SWI nn (opcode `11011111xxxxxxxx`) shall trigger SWI exception with 8-bit comment field.

#### Format 18: Unconditional Branch

**REQ-CPU-144**: B label (opcode `11100xxxxxxxxxxx`) shall:
1. Sign-extend 11-bit offset
2. `PC := PC + offset×2`

#### Format 19: Long Branch with Link

**REQ-CPU-145**: BL label (two instructions) shall:
1. First instruction (opcode `11110xxxxxxxxxxx`): `LR := PC + (offset_high << 12)`
2. Second instruction (opcode `11111xxxxxxxxxxx`): `temp := next instruction address; PC := LR + (offset_low << 1); LR := temp | 1`

### 3.9 Exception Handling

**REQ-CPU-150**: The CPU shall support the following exceptions in priority order:

| Priority | Exception             | Vector Address |
|----------|-----------------------|----------------|
| 1        | Reset                 | 0x00000000     |
| 2        | Data Abort            | 0x00000010     |
| 3        | FIQ                   | 0x0000001C     |
| 4        | IRQ                   | 0x00000018     |
| 5        | Prefetch Abort        | 0x0000000C     |
| 6        | Undefined Instruction | 0x00000004     |
| 6        | SWI                   | 0x00000008     |

**REQ-CPU-151**: Exception entry shall:
1. Save CPSR to SPSR of target mode
2. Set CPSR to target mode with I bit set (F bit set for FIQ/Reset)
3. Set CPSR.T = 0 (enter ARM state)
4. Save return address to LR of target mode
5. Set PC to vector address

**REQ-CPU-152**: IRQ exception shall only be taken if CPSR.I = 0 and IME = 1 and (IE & IF) != 0.

**REQ-CPU-153**: FIQ exception shall only be taken if CPSR.F = 0 (but GBA does not use FIQ).

### 3.10 Halt State

**REQ-CPU-160**: The CPU shall support a halted state entered via BIOS halt functions or HALTCNT register.

**REQ-CPU-161**: While halted, the CPU shall not execute instructions.

**REQ-CPU-162**: The CPU shall exit halt when an enabled interrupt becomes pending.

**REQ-CPU-163**: The scheduler shall skip CPU execution and advance directly to the next event when halted.

---

## 4. Memory Bus

### 4.1 Address Decoding

**REQ-BUS-001**: The bus shall decode addresses into regions based on bits [27:24]:

| Address Range           | Bits [27:24] | Region             |
|-------------------------|--------------|-------------------|
| 0x00000000-0x00003FFF   | 0x0          | BIOS              |
| 0x02000000-0x0203FFFF   | 0x2          | EWRAM             |
| 0x03000000-0x03007FFF   | 0x3          | IWRAM             |
| 0x04000000-0x040003FF   | 0x4          | I/O Registers     |
| 0x05000000-0x050003FF   | 0x5          | Palette RAM       |
| 0x06000000-0x06017FFF   | 0x6          | VRAM              |
| 0x07000000-0x070003FF   | 0x7          | OAM               |
| 0x08000000-0x09FFFFFF   | 0x8-0x9      | ROM (Wait State 0)|
| 0x0A000000-0x0BFFFFFF   | 0xA-0xB      | ROM (Wait State 1)|
| 0x0C000000-0x0DFFFFFF   | 0xC-0xD      | ROM (Wait State 2)|
| 0x0E000000-0x0E00FFFF   | 0xE          | SRAM              |

**REQ-BUS-002**: Addresses outside defined ranges shall return open bus values.

**REQ-BUS-003**: Each region shall handle mirroring:
- EWRAM: Mirrors every 256 KB
- IWRAM: Mirrors every 32 KB
- Palette: Mirrors every 1 KB
- VRAM: Mirrors in 128 KB blocks (with special 96 KB behavior)
- OAM: Mirrors every 1 KB
- ROM: Mirrors if ROM is smaller than 32 MB

### 4.2 Access Width

**REQ-BUS-010**: The bus shall provide the following access functions:
- `read8(addr: u32) -> (u8, cycles: u8)`
- `read16(addr: u32) -> (u16, cycles: u8)`
- `read32(addr: u32) -> (u32, cycles: u8)`
- `write8(addr: u32, value: u8) -> cycles: u8`
- `write16(addr: u32, value: u16) -> cycles: u8`
- `write32(addr: u32, value: u32) -> cycles: u8`

**REQ-BUS-011**: Misaligned 16-bit reads shall force-align to halfword boundary and return rotated data.

**REQ-BUS-012**: Misaligned 32-bit reads shall force-align to word boundary and return rotated data.

**REQ-BUS-013**: Misaligned 16-bit writes shall force-align to halfword boundary.

**REQ-BUS-014**: Misaligned 32-bit writes shall force-align to word boundary.

**REQ-BUS-015**: 32-bit access to 16-bit bus regions (EWRAM, Palette, VRAM) shall perform two 16-bit accesses.

### 4.3 Waitstates

**REQ-BUS-020**: The bus shall track access timing and return cycle counts.

**REQ-BUS-021**: Default waitstates (before WAITCNT modification):

| Region   | N cycles (8/16/32) | S cycles (8/16/32) |
|----------|--------------------|--------------------|
| BIOS     | 1/1/1              | 1/1/1              |
| EWRAM    | 3/3/6              | 3/3/6              |
| IWRAM    | 1/1/1              | 1/1/1              |
| I/O      | 1/1/1              | 1/1/1              |
| Palette  | 1/1/2              | 1/1/2              |
| VRAM     | 1/1/2              | 1/1/2              |
| OAM      | 1/1/1              | 1/1/1              |
| ROM WS0  | 5/5/8              | 3/3/6              |
| ROM WS1  | 5/5/8              | 5/5/10             |
| ROM WS2  | 5/5/8              | 9/9/18             |
| SRAM     | 5/5/5              | 5/5/5              |

**REQ-BUS-022**: The bus shall track sequential vs non-sequential access:
- Sequential: Address == previous_address + previous_width AND same region
- Non-sequential: All other accesses

**REQ-BUS-023**: ROM waitstates shall be configurable via WAITCNT register (0x04000204).

### 4.4 BIOS Protection

**REQ-BUS-030**: The bus shall track BIOS protection state.

**REQ-BUS-031**: While PC < 0x4000, BIOS reads shall succeed and update `last_bios_read`.

**REQ-BUS-032**: While PC >= 0x4000, BIOS reads shall return `last_bios_read` instead of actual BIOS contents.

**REQ-BUS-033**: `last_bios_read` shall be initialized to 0xE129F000 (typical post-boot value).

### 4.5 Open Bus

**REQ-BUS-040**: Reads from unmapped addresses shall return the last prefetched opcode value.

**REQ-BUS-041**: The bus shall track `last_prefetch: u32` updated on each instruction fetch.

**REQ-BUS-042**: Open bus reads during CPU execution shall return:
- In ARM state: `last_prefetch`
- In Thumb state: `last_prefetch` duplicated in both halfwords

### 4.6 I/O Registers

**REQ-BUS-050**: I/O register reads and writes shall dispatch to appropriate subsystem handlers.

**REQ-BUS-051**: The following I/O registers shall be implemented in Phase 1:

| Address    | Name    | R/W | Description                    |
|------------|---------|-----|--------------------------------|
| 0x04000200 | IE      | R/W | Interrupt Enable               |
| 0x04000202 | IF      | R/W | Interrupt Flags (write 1 clr)  |
| 0x04000204 | WAITCNT | R/W | Waitstate Control              |
| 0x04000208 | IME     | R/W | Interrupt Master Enable        |
| 0x04000300 | POSTFLG | R/W | Post-boot flag                 |
| 0x04000301 | HALTCNT | W   | Halt/Stop control              |

**REQ-BUS-052**: Unimplemented I/O registers shall:
- Reads: Return 0 or open bus (implementation defined)
- Writes: Log address and value for debugging, otherwise ignore

**REQ-BUS-053**: I/O register access shall respect read/write permissions. Writing to read-only bits shall be ignored.

---

## 5. Scheduler

### 5.1 Event Types

**REQ-SCH-001**: The scheduler shall support the following event types:

```odin
Event_Type :: enum {
    // PPU events
    HBlank_Start,
    HBlank_End,
    VBlank_Start,
    VBlank_End,

    // Timer events
    Timer0_Overflow,
    Timer1_Overflow,
    Timer2_Overflow,
    Timer3_Overflow,

    // DMA events (Phase 4)
    DMA0, DMA1, DMA2, DMA3,

    // APU events (Phase 6)
    APU_Sample,
    APU_Sequencer,

    // System events
    Halt_Check,
    Frame_Complete,
}
```

### 5.2 Event Structure

**REQ-SCH-010**: Each event shall contain:
- `timestamp: u64`: Absolute cycle count when event fires
- `type: Event_Type`: Event identifier
- `param: u32`: Optional parameter (e.g., timer ID)

**REQ-SCH-011**: Events shall be stored in a fixed-size array with maximum capacity of 32 events.

**REQ-SCH-012**: Events shall be maintained in sorted order by timestamp (earliest first).

### 5.3 Scheduler Operations

**REQ-SCH-020**: The scheduler shall provide:
- `schedule(type: Event_Type, delay: u64, param: u32 = 0)`: Add event at current_time + delay
- `schedule_absolute(type: Event_Type, timestamp: u64, param: u32 = 0)`: Add event at absolute time
- `deschedule(type: Event_Type)`: Remove all events of given type
- `peek() -> ^Event`: Return next event without removing
- `pop() -> Event`: Remove and return next event
- `reschedule(type: Event_Type, new_delay: u64)`: Update existing event's timestamp

**REQ-SCH-021**: `schedule` and `schedule_absolute` shall maintain sorted order via insertion sort.

**REQ-SCH-022**: Scheduling an event of a type that already exists shall replace the existing event.

**REQ-SCH-023**: The scheduler shall track current cycle count: `current_cycles: u64`.

### 5.4 Initial Events

**REQ-SCH-030**: On system reset, the following events shall be scheduled:
- `HBlank_Start` at cycle 960 (first scanline HBlank)
- `Frame_Complete` at cycle 280896 (first frame boundary)

---

## 6. Cartridge

### 6.1 ROM Loading

**REQ-CART-001**: The emulator shall load ROM files with extensions: `.gba`, `.GBA`, `.bin`.

**REQ-CART-002**: ROM size shall be validated: minimum 192 bytes (header), maximum 33,554,432 bytes (32 MB).

**REQ-CART-003**: ROM data shall be allocated separately from the main memory arena.

**REQ-CART-004**: ROM smaller than 32 MB shall be mirrored to fill the 32 MB address space.

### 6.2 Header Validation

**REQ-CART-010**: The emulator shall parse the ROM header at offset 0x00:

| Offset | Size | Field                       |
|--------|------|-----------------------------|
| 0x00   | 4    | Entry point (ARM branch)    |
| 0x04   | 156  | Nintendo logo               |
| 0xA0   | 12   | Game title                  |
| 0xAC   | 4    | Game code                   |
| 0xB0   | 2    | Maker code                  |
| 0xB2   | 1    | Fixed value (0x96)          |
| 0xB3   | 1    | Main unit code              |
| 0xB4   | 1    | Device type                 |
| 0xBD   | 1    | Header checksum             |

**REQ-CART-011**: The emulator shall verify header checksum:
```
checksum = 0
for i in 0xA0..0xBC:
    checksum = checksum - rom[i]
checksum = (checksum - 0x19) & 0xFF
```

**REQ-CART-012**: Header validation failure shall produce a warning but not prevent loading.

### 6.3 Save Type Detection (Phase 7)

**REQ-CART-020**: Save type detection shall be deferred to Phase 7.

**REQ-CART-021**: Phase 1 shall allocate a 128 KB buffer for save memory, initialized to 0xFF.

**REQ-CART-022**: All save memory accesses shall be logged for later analysis.

---

## 7. BIOS

### 7.1 Loading

**REQ-BIOS-001**: The emulator shall load BIOS from file path specified by command line or configuration.

**REQ-BIOS-002**: BIOS file size shall be exactly 16,384 bytes.

**REQ-BIOS-003**: BIOS file checksum (CRC32) should be validated against known good value: `0xBAAE187F`.

**REQ-BIOS-004**: Checksum mismatch shall produce a warning but not prevent loading.

---

## 8. Input

### 8.1 Keypad State

**REQ-INPUT-001**: The emulator shall track the state of 10 GBA buttons:
- A, B, Select, Start, Right, Left, Up, Down, R, L

**REQ-INPUT-002**: Keypad state shall be exposed via KEYINPUT register (0x04000130):
- Bit 0: A (0 = pressed)
- Bit 1: B
- Bit 2: Select
- Bit 3: Start
- Bit 4: Right
- Bit 5: Left
- Bit 6: Up
- Bit 7: Down
- Bit 8: R
- Bit 9: L

**REQ-INPUT-003**: KEYINPUT bits are active-low (0 = pressed, 1 = released).

**REQ-INPUT-004**: KEYCNT register (0x04000132) shall be implemented for keypad interrupt control (Phase 3).

### 8.2 SDL2 Mapping

**REQ-INPUT-010**: The emulator shall map keyboard keys to GBA buttons:

| Keyboard    | GBA Button |
|-------------|------------|
| Z           | A          |
| X           | B          |
| Backspace   | Select     |
| Enter       | Start      |
| Arrow Right | Right      |
| Arrow Left  | Left       |
| Arrow Up    | Up         |
| Arrow Down  | Down       |
| A           | L          |
| S           | R          |

**REQ-INPUT-011**: Key mappings shall be configurable (Phase 7).

---

## 9. Logging and Debug

### 9.1 Log Levels

**REQ-LOG-001**: The emulator shall support the following log levels:
- `None`: No logging
- `Error`: Unrecoverable errors only
- `Warn`: Unusual conditions (unmapped access, misalignment)
- `Info`: State changes (mode switches, interrupts)
- `Debug`: Detailed information (register changes)
- `Trace`: Every instruction executed

**REQ-LOG-002**: Log level shall be configurable at compile time and runtime.

### 9.2 Instruction Trace

**REQ-LOG-010**: Trace output format shall match mGBA for diffing:
```
{ARM|THM} {PC:08X}: {opcode:08X}  {mnemonic:16s}  {register_changes}
```

**REQ-LOG-011**: Trace output shall be written to file, not stdout.

**REQ-LOG-012**: Trace logging shall be buffered (minimum 64 KB buffer) to minimize I/O overhead.

**REQ-LOG-013**: Trace buffer shall flush on frame boundaries and program exit.

### 9.3 Debug Features

**REQ-LOG-020**: The emulator shall support a breakpoint at a specific PC address (single breakpoint sufficient for Phase 1).

**REQ-LOG-021**: When breakpoint is hit, the emulator shall pause and dump CPU state to stdout.

---

## 10. Display (Stub for Phase 1)

### 10.1 SDL2 Window

**REQ-DISP-001**: The emulator shall create an SDL2 window of size 480x320 (2× native resolution).

**REQ-DISP-002**: The window title shall include: emulator name, ROM name, and FPS counter.

**REQ-DISP-003**: The window shall be resizable.

### 10.2 Framebuffer

**REQ-DISP-010**: A framebuffer of 240×160 pixels in BGR555 format shall be allocated.

**REQ-DISP-011**: For Phase 1, the framebuffer shall be cleared to a solid color (e.g., magenta 0x7C1F) each frame.

**REQ-DISP-012**: The framebuffer shall be uploaded to an SDL2 texture and rendered each frame.

### 10.3 Frame Timing

**REQ-DISP-020**: The emulator shall target 59.7275 Hz refresh rate.

**REQ-DISP-021**: Frame timing shall be managed via SDL2 VSync or manual delay.

**REQ-DISP-022**: The emulator shall track and display frames per second.

---

## 11. Application Entry Point

### 11.1 Command Line Arguments

**REQ-APP-001**: The emulator shall accept the following command line arguments:
- `<rom_path>`: Path to ROM file (required)
- `--bios <path>`: Path to BIOS file (required)
- `--log-level <level>`: Set log level
- `--trace <path>`: Enable instruction trace to file
- `--break <address>`: Set breakpoint at address

**REQ-APP-002**: Missing required arguments shall print usage and exit.

### 11.2 Initialization Sequence

**REQ-APP-010**: Initialization shall proceed in this order:
1. Parse command line arguments
2. Initialize memory arena
3. Load BIOS
4. Load ROM
5. Initialize SDL2 (video, audio, input)
6. Initialize CPU to reset state
7. Initialize scheduler with initial events
8. Initialize bus
9. Enter main loop

### 11.3 Main Loop

**REQ-APP-020**: The main loop shall:
1. Poll SDL2 events (input, window close)
2. Run emulation until Frame_Complete event
3. Upload framebuffer to display
4. Update window title with FPS
5. Repeat until quit requested

### 11.4 Shutdown Sequence

**REQ-APP-030**: Shutdown shall:
1. Flush trace log buffer
2. Save game if dirty (Phase 7)
3. Destroy SDL2 resources
4. Free memory arena
5. Exit with code 0

---

## 12. Testing Requirements

### 12.1 Test ROM Compatibility

**REQ-TEST-001**: Phase 1 shall pass jsmolka's `arm.gba` test ROM (all ARM instruction tests).

**REQ-TEST-002**: Phase 1 shall pass jsmolka's `thumb.gba` test ROM (all Thumb instruction tests).

**REQ-TEST-003**: Phase 1 shall complete BIOS boot sequence and reach ROM entry point (0x08000000).

### 12.2 Unit Tests

**REQ-TEST-004**: All core components shall have unit tests using Odin's built-in testing framework.

**REQ-TEST-005**: Unit tests shall use the `@(test)` attribute and `core:testing` package.

**REQ-TEST-006**: The following minimum test coverage shall be maintained:

| Component | Minimum Tests | Coverage Areas |
|-----------|---------------|----------------|
| GBA CPU (ARM7TDMI) | 55 | Mode switching, flags, conditions, ALU, exceptions |
| GBA PPU | 27 | Video modes, BGCNT, sprites, OAM |
| GB CPU (LR35902) | 34 | Registers, flags, interrupts, instruction set |
| GB PPU | 17 | Modes, timing, STAT/LCDC, palettes |
| GB Bus | 30 | MBC detection, banking, I/O registers |

**REQ-TEST-007**: Unit tests shall be runnable via `make test` or individual targets:
- `make test-gba-cpu` - GBA CPU tests
- `make test-gba-ppu` - GBA PPU tests
- `make test-gb-cpu` - GB CPU tests
- `make test-gb-ppu` - GB PPU tests
- `make test-gb-bus` - GB Bus tests

**REQ-TEST-008**: Test helper functions shall use thread-local storage for test memory to avoid interference between tests.

**REQ-TEST-009**: All tests shall pass before merging changes.

### 12.3 Instruction Trace Comparison

**REQ-TEST-010**: The emulator shall be capable of producing an instruction trace that can be diff'd against mGBA output.

**REQ-TEST-011**: Trace comparison shall be documented as a testing procedure.

---

## Appendix A: Bit Field Definitions

### A.1 CPSR Format

```odin
CPSR :: bit_field u32 {
    mode:     u5  | 5,    // bits 0-4
    thumb:    bool | 1,   // bit 5
    fiq_dis:  bool | 1,   // bit 6
    irq_dis:  bool | 1,   // bit 7
    _reserved: u20 | 20,  // bits 8-27
    v:        bool | 1,   // bit 28
    c:        bool | 1,   // bit 29
    z:        bool | 1,   // bit 30
    n:        bool | 1,   // bit 31
}
```

### A.2 WAITCNT Format

```odin
WAITCNT :: bit_field u16 {
    sram_wait:     u2  | 2,  // bits 0-1
    ws0_first:     u2  | 2,  // bits 2-3
    ws0_second:    bool | 1, // bit 4
    ws1_first:     u2  | 2,  // bits 5-6
    ws1_second:    bool | 1, // bit 7
    ws2_first:     u2  | 2,  // bits 8-9
    ws2_second:    bool | 1, // bit 10
    phi_out:       u2  | 2,  // bits 11-12
    _unused:       bool | 1, // bit 13
    prefetch:      bool | 1, // bit 14
    game_pak_type: bool | 1, // bit 15
}
```

### A.3 IE/IF Format

```odin
Interrupt_Flags :: bit_field u16 {
    vblank:   bool | 1,  // bit 0
    hblank:   bool | 1,  // bit 1
    vcount:   bool | 1,  // bit 2
    timer0:   bool | 1,  // bit 3
    timer1:   bool | 1,  // bit 4
    timer2:   bool | 1,  // bit 5
    timer3:   bool | 1,  // bit 6
    serial:   bool | 1,  // bit 7
    dma0:     bool | 1,  // bit 8
    dma1:     bool | 1,  // bit 9
    dma2:     bool | 1,  // bit 10
    dma3:     bool | 1,  // bit 11
    keypad:   bool | 1,  // bit 12
    game_pak: bool | 1,  // bit 13
    _unused:  u2   | 2,  // bits 14-15
}
```

---

## Appendix B: File Format Reference

### B.1 ROM Header

| Offset | Bytes | Description                              |
|--------|-------|------------------------------------------|
| 0x000  | 4     | Entry point (32-bit ARM branch)          |
| 0x004  | 156   | Nintendo logo (compressed bitmap)        |
| 0x0A0  | 12    | Game title (uppercase ASCII)             |
| 0x0AC  | 4     | Game code (uppercase ASCII)              |
| 0x0B0  | 2     | Maker code (uppercase ASCII)             |
| 0x0B2  | 1     | Fixed value (must be 0x96)               |
| 0x0B3  | 1     | Main unit code (0x00 for GBA)            |
| 0x0B4  | 1     | Device type (usually 0x00)               |
| 0x0B5  | 7     | Reserved (zero filled)                   |
| 0x0BC  | 1     | Software version                         |
| 0x0BD  | 1     | Header checksum                          |
| 0x0BE  | 2     | Reserved (zero filled)                   |

### B.2 Checksum Algorithm

```
sum = 0
for byte in rom[0xA0..0xBC]:
    sum = sum - byte
result = (sum - 0x19) & 0xFF
```

---

## Appendix C: Cycle Timing Reference

### C.1 Instruction Cycles (Approximate)

| Instruction Class     | Base Cycles | Notes                           |
|-----------------------|-------------|---------------------------------|
| Data Processing (reg) | 1S          | +1I if shift by register        |
| Data Processing (imm) | 1S          |                                 |
| Multiply              | 1S + mI     | m = multiplier cycles (1-4)     |
| Multiply Long         | 1S + (m+1)I |                                 |
| Branch                | 2S + 1N     |                                 |
| Branch Exchange       | 2S + 1N     |                                 |
| LDR                   | 1S + 1N + 1I| +1S +1N if PC destination       |
| STR                   | 2N          |                                 |
| LDM (n regs)          | nS + 1N + 1I| +1S +1N if PC in list           |
| STM (n regs)          | (n-1)S + 2N |                                 |
| SWP                   | 1S + 2N + 1I|                                 |
| SWI                   | 2S + 1N     |                                 |

S = Sequential, N = Non-sequential, I = Internal

### C.2 PPU Timing

| Event          | Cycle                    |
|----------------|--------------------------|
| Scanline start | 0                        |
| HBlank start   | 960                      |
| Scanline end   | 1232                     |
| VBlank start   | 160 × 1232 = 197,120     |
| VBlank end     | 228 × 1232 = 280,896     |
| Frame complete | 280,896                  |

---

*End of Technical Requirements Specification*
