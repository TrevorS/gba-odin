# GBA Emulator in Odin: Research & Design Document

You are helping me design and implement a Game Boy Advance emulator in Odin. This is a learning project with the goal of creating a clean, well-documented, reasonably accurate emulator that can play commercial games.

---

## Project Goals

**Primary goals:**

- Learn GBA hardware architecture deeply
- Write clean, idiomatic Odin code
- Achieve compatibility with popular commercial games (Pokemon, Zelda, Metroid, etc.)
- Maintain readable code over maximum performance (but don't be wasteful)

**Non-goals (for now):**

- Cycle-accurate timing (scanline accuracy is fine)
- Link cable / multiplayer
- Debug UI (maybe later)
- Mobile/web ports

---

## Technical Context: GBA Hardware

### CPU: ARM7TDMI

- 32-bit ARM core running at 16.78 MHz
- Two instruction sets:
  - **ARM**: 32-bit instructions, bits [27:20] and [7:4] determine opcode
  - **THUMB**: 16-bit compressed instructions, more common in GBA games
- 16 general-purpose registers (r0-r15), r15 is PC, r14 is LR, r13 is SP
- CPSR (status register) with condition flags (N, Z, C, V) and mode bits
- 6 operating modes with banked registers (User, FIQ, IRQ, Supervisor, Abort, Undefined)
- 3-stage pipeline (fetch, decode, execute) — PC is 8 bytes ahead in ARM, 4 in THUMB

### Memory Map

```
0x00000000-0x00003FFF  BIOS (16KB, protected after boot)
0x02000000-0x0203FFFF  EWRAM (256KB, 16-bit bus, 2 wait states)
0x03000000-0x03007FFF  IWRAM (32KB, 32-bit bus, fast)
0x04000000-0x040003FF  I/O Registers
0x05000000-0x050003FF  Palette RAM (1KB)
0x06000000-0x06017FFF  VRAM (96KB)
0x07000000-0x070003FF  OAM (1KB)
0x08000000-0x09FFFFFF  ROM (up to 32MB, directly addressable)
0x0E000000-0x0E00FFFF  SRAM/Flash (up to 64KB)
```

### PPU (Picture Processing Unit)

- 240x160 pixels, 15-bit color (BGR555)
- 60 fps (59.7275 Hz precisely)
- 4 background layers + 1 sprite layer
- 6 video modes:
  - **Mode 0**: Four text/tile BGs
  - **Mode 1**: Two text BGs + one affine BG
  - **Mode 2**: Two affine BGs
  - **Mode 3**: Single 240x160 16-bit bitmap
  - **Mode 4**: Double-buffered 240x160 8-bit bitmap
  - **Mode 5**: Double-buffered 160x128 16-bit bitmap
- 128 sprites (OBJs), 8x8 to 64x64 pixels
- Priority system: Lower priority number = drawn on top
- Alpha blending and brightness effects

### Timing (per frame)

```
Scanline:  1232 cycles (960 visible + 272 HBlank)
VDraw:     160 scanlines
VBlank:    68 scanlines
Frame:     280896 cycles total
```

### APU (Audio Processing Unit)

- 4 channels:
  - Channel 1: Square wave with sweep
  - Channel 2: Square wave
  - Channel 3: Programmable wave
  - Channel 4: Noise
- 2 DMA channels (Direct Sound A and B) for PCM audio
- Output at 32768 Hz

### DMA (Direct Memory Access)

- 4 DMA channels (0-3)
- Triggered by: Immediate, VBlank, HBlank, or special (audio FIFO, video capture)
- Channel priority: 0 > 1 > 2 > 3

### Interrupts

- Sources: VBlank, HBlank, VCount, Timer 0-3, Serial, DMA 0-3, Keypad, Cartridge
- IE (0x4000200): Interrupt enable
- IF (0x4000202): Interrupt flags (write 1 to acknowledge)
- IME (0x4000208): Master enable

### Cartridge Types

- ROM sizes: 1MB to 32MB
- Save types: SRAM (32KB), Flash (64KB/128KB), EEPROM (512B/8KB)
- Detection often requires heuristics or database

---

## Odin-Specific Guidance

### Project Structure

```
gba/
├── src/
│   ├── main.odin           # Entry point, main loop
│   ├── gba.odin            # Top-level GBA struct, orchestration
│   ├── cpu/
│   │   ├── arm7tdmi.odin   # CPU state and core logic
│   │   ├── arm.odin        # ARM instruction handlers
│   │   ├── thumb.odin      # THUMB instruction handlers
│   │   └── disasm.odin     # Disassembler (for debugging)
│   ├── ppu/
│   │   ├── ppu.odin        # PPU state and scanline renderer
│   │   ├── background.odin # BG layer rendering
│   │   ├── sprite.odin     # OBJ/sprite rendering
│   │   └── effects.odin    # Blending, mosaic, windows
│   ├── apu/
│   │   ├── apu.odin        # Audio state and mixing
│   │   ├── channels.odin   # PSG channels 1-4
│   │   └── fifo.odin       # DMA sound FIFOs
│   ├── bus.odin            # Memory bus, read/write dispatch
│   ├── dma.odin            # DMA controller
│   ├── timer.odin          # Timer 0-3
│   ├── keypad.odin         # Input handling
│   ├── cartridge.odin      # ROM loading, save type detection
│   └── scheduler.odin      # Event scheduler (optional but recommended)
├── vendor/                 # Any external deps
├── roms/                   # Test ROMs (gitignored)
├── build.sh
└── README.md
```

### Odin Idioms to Use

**Bit manipulation:**

```odin
// Use bit_set for flags
Cpu_Flags :: bit_set[enum { N, Z, C, V }; u8]

// Use bit_field for packed registers when it helps readability
Bg_Control :: bit_field u16 {
    priority:      u8  | 2,
    tile_base:     u8  | 2,
    _:             u8  | 2,
    mosaic:        bool | 1,
    palette_mode:  bool | 1,  // 0 = 4bpp, 1 = 8bpp
    map_base:      u8  | 5,
    overflow_wrap: bool | 1,  // For affine BGs
    size:          u8  | 2,
}
```

**Error handling:**

```odin
load_rom :: proc(path: string) -> ([]u8, bool) {
    data, ok := os.read_entire_file(path)
    return data, ok
}

// Or with explicit errors:
Load_Error :: enum { File_Not_Found, Invalid_Header, Too_Large }

load_rom_v2 :: proc(path: string) -> ([]u8, Maybe(Load_Error)) {
    // ...
}
```

**Tables for dispatch:**

```odin
// ARM instruction handlers
Arm_Handler :: #type proc(cpu: ^Cpu, opcode: u32)

@(private="file")
arm_table: [4096]Arm_Handler

@(init)
init_arm_table :: proc() {
    for i in 0..<4096 {
        arm_table[i] = decode_arm(u16(i))
    }
}

execute_arm :: #force_inline proc(cpu: ^Cpu, opcode: u32) {
    index := ((opcode >> 16) & 0xFF0) | ((opcode >> 4) & 0xF)
    arm_table[index](cpu, opcode)
}
```

**Using vendor:sdl2:**

```odin
import "vendor:sdl2"

// Enums work naturally
if sdl2.Init({.VIDEO, .AUDIO}) != 0 { /* error */ }

// Pixel format matches GBA native
texture := sdl2.CreateTexture(renderer, .BGR555, .STREAMING, 240, 160)
```

### Things Odin Does Well

- `#force_inline` for hot paths
- `bit_field` for hardware registers
- `#partial switch` for handling only relevant cases
- `Maybe(T)` instead of null pointers where appropriate
- Named return values for clarity
- `defer` for cleanup
- `@(init)` for table initialization

### Things to Watch For

- No comptime like Zig — tables are runtime-initialized (but `@(init)` makes this clean)
- No generics (use `$T` for polymorphic procedures)
- Slices vs pointers: be explicit about what you need
- `context` system: useful for allocators, logging

---

## Implementation Phases

### Phase 1: CPU + Basic Memory

**Goal:** Execute ARM/THUMB instructions, pass simple test ROMs

- [ ] Implement ARM7TDMI register file with mode switching
- [ ] Implement CPSR/SPSR handling
- [ ] Memory bus with basic regions (no I/O side effects yet)
- [ ] ARM instruction decoder and handlers (data processing, load/store, branch)
- [ ] THUMB instruction decoder and handlers
- [ ] Condition evaluation
- [ ] Test with armwrestler and gba-tests CPU tests

**Key files:** `cpu/`, `bus.odin`

### Phase 2: PPU Fundamentals

**Goal:** Render Mode 0/3/4, see something on screen

- [ ] Scanline-based renderer structure
- [ ] VRAM, Palette RAM, OAM access
- [ ] Mode 3 (bitmap) — easiest to test
- [ ] Mode 0 (tiled) with one BG layer
- [ ] Basic sprite rendering
- [ ] VBlank/HBlank flag timing
- [ ] SDL2 integration for display

**Key files:** `ppu/`, display code

### Phase 3: Interrupts + Timers

**Goal:** Games that rely on timing start working

- [ ] Interrupt controller (IE, IF, IME)
- [ ] VBlank/HBlank interrupts
- [ ] Timer implementation (cascade mode, overflow IRQ)
- [ ] Timer-driven frame limiting

**Key files:** `timer.odin`, interrupt handling in `gba.odin`

### Phase 4: DMA

**Goal:** Fast memory copies, audio DMA

- [ ] All 4 DMA channels
- [ ] Trigger conditions (immediate, VBlank, HBlank, special)
- [ ] Priority handling
- [ ] Sound FIFO DMA (channels A/B)

**Key files:** `dma.odin`

### Phase 5: Complete PPU

**Goal:** Most games render correctly

- [ ] All video modes (0-5)
- [ ] All 4 BG layers with priorities
- [ ] Affine backgrounds (Mode 1/2)
- [ ] Affine sprites
- [ ] Windowing (WIN0, WIN1, OBJWIN)
- [ ] Alpha blending
- [ ] Mosaic effect

**Key files:** `ppu/`

### Phase 6: Audio

**Goal:** Games have sound

- [ ] PSG channels 1-4
- [ ] Direct Sound channels A/B with FIFO
- [ ] Mixing and output via SDL2
- [ ] Proper timing sync

**Key files:** `apu/`

### Phase 7: Polish

**Goal:** Play commercial games reliably

- [ ] Save game support (SRAM, Flash, EEPROM detection)
- [ ] Prefetch buffer emulation (for speed-sensitive games)
- [ ] Open bus behavior
- [ ] Edge cases from game-specific testing

---

## Testing Strategy

### Test ROMs (run these regularly)

- **armwrestler** — CPU instruction tests
- **gba-tests** — CPU, memory timing
- **tonc demos** — PPU modes, effects
- **mGBA test suite** — Comprehensive
- **AGS (Ages) Aging Cartridge** — Nintendo's internal test

### Commercial Games (milestone targets)

- **Pokemon Emerald** — Heavy on everything, good stress test
- **The Legend of Zelda: Minish Cap** — Tests Mode 1, affine
- **Metroid Fusion** — Good PPU/audio test
- **Advance Wars** — UI-heavy, good for text rendering
- **Mario Kart: Super Circuit** — Mode 7-style affine

### Debugging Techniques

- Log PC + opcode for instruction traces
- Compare against known-good emulator (mGBA, NanoBoyAdvance)
- Implement a simple disassembler early
- Frame-by-frame stepping
- VRAM/OAM viewer (later)

---

## Key Resources

### Documentation

- **GBATEK** (Martin Korth): https://problemkaputt.de/gbatek.htm
  The definitive reference. Dense but comprehensive.
- **Tonc**: https://www.coranac.com/tonc/text/
  GBA programming tutorial, great for understanding hardware from dev perspective
- **ARM7TDMI Technical Reference Manual**
  Official ARM documentation for the CPU

### Open Source References

- **mGBA** (C): Most accurate GBA emulator, great reference
- **NanoBoyAdvance** (C++): Clean codebase, cycle-accurate
- **RustBoyAdvance-ng** (Rust): Good Rust reference
- **emudev Discord**: Active community for emulator developers

### Odin Resources

- **Odin Overview**: https://odin-lang.org/docs/overview/
- **vendor:sdl2 source**: Check Odin's GitHub for examples

---

## Specific Questions to Explore

When implementing, consider asking about:

- **Scheduler architecture**: Event-driven vs cycle-counting? (Event-driven is cleaner)
- **ARM/THUMB decoder**: Table-based vs switch? (Table for ARM, switch for THUMB is common)
- **Pipeline emulation**: Accurate vs simplified? (Simplified is fine for most games)
- **PPU renderer**: Scanline vs pixel? Per-layer vs merged? (Scanline, per-layer with compositing)
- **Audio sync**: Separate thread vs main loop? (Main loop with ring buffer is simpler)
- **Save detection**: Database vs heuristics? (Heuristics first, database for edge cases)

---

## Session Workflow

When working on this project:

1. **Start sessions with context**: "We're working on the GBA emulator in Odin. Currently implementing [X]. Last session we [Y]."
2. **Ask for explanations**: "Explain how GBA affine backgrounds work and how to implement them."
3. **Request code**: "Write the THUMB decoder with handlers for ALU operations."
4. **Debug together**: "This test ROM expects r0=0x1234 after BL but I get 0x1230. Here's my BL implementation…"
5. **Review approach**: "Here's my PPU structure. Does this make sense for scanline rendering?"

---

## Initial Implementation Request

Let's start with Phase 1. Please provide:

1. **cpu/arm7tdmi.odin**: CPU struct with registers, CPSR, mode handling
2. **bus.odin**: Memory bus with read8/16/32 and write8/16/32
3. **cpu/arm.odin**: ARM decoder skeleton + a few key instructions (MOV, ADD, B, LDR)
4. **main.odin**: Basic loop that loads a ROM and runs instructions

Focus on clean structure over completeness. We'll iterate.

---

## Plan Refinements

### Scheduler: Promote from "Optional"

For GBA emulation, an event-driven scheduler should be core infrastructure, not optional. Without it, you end up with ugly polling code everywhere:

```odin
// Without scheduler (messy)
for cycles < frame_cycles {
    step_cpu()
    if cycles >= next_timer0_event { handle_timer0() }
    if cycles >= next_hblank { handle_hblank() }
    if cycles >= next_dma_trigger { handle_dma() }
    // ... grows unwieldy
}

// With scheduler (clean)
for !scheduler_empty() {
    event := pop_next_event()
    cpu.cycles = event.timestamp
    event.handler()
}
```

I'd add `scheduler.odin` to Phase 1 alongside CPU/bus. It's ~80 lines of code and makes everything else cleaner.

### BIOS Strategy

Options:

1. Require original BIOS — legally gray, but most accurate
2. Use Normmatt's open-source BIOS — works for most games
3. HLE (high-level emulation) — trap SWI calls, implement in Odin

**Recommendation:** Support loading original BIOS if present, fall back to HLE for common SWI calls (especially 0x0B CpuSet, 0x0C CpuFastSet, 0x06 Halt). Many games only use a handful of BIOS functions.

**Current Decision:** Require original BIOS for Phase 1.

### Memory Bus: Waitstates

Consider adding waitstate tracking from the start, even if you hardcode defaults initially:

```odin
Access_Type :: enum { Sequential, Non_Sequential }

// Returns cycles consumed by this access
read32 :: proc(bus: ^Bus, addr: u32, access: Access_Type) -> (u32, u8)
```

This signature change is painful to retrofit later. Games like Golden Sun are timing-sensitive enough to notice.

### ARM Decoder: The 4096-Entry Table

The table is indexed by bits [27:20] concatenated with [7:4], but some instructions don't use all those bits for decoding. You'll end up with multiple table entries pointing to the same handler. That's fine—it's a classic time/space tradeoff.

For THUMB, I'd actually suggest a 256-entry table indexed by the top 8 bits, with sub-decoding in handlers where needed. THUMB is regular enough that this hits a sweet spot.

### Pipeline Simplification

Don't actually model fetch/decode/execute stages. Just:

```odin
// When reading PC during execution:
read_pc :: #force_inline proc(cpu: ^Cpu) -> u32 {
    return cpu.r[15] + (cpu.thumb_mode ? 4 : 8)
}
```

The only subtlety is that some instructions (like STR with Rd=PC) behave differently, but you handle those case-by-case.

### Phase 1 Addition: Condition Evaluation

This is a hot path—every ARM instruction checks conditions. A 16-entry lookup table is perfect:

```odin
// Index by top 4 bits of opcode (condition code)
// Returns true if condition passes given current CPSR flags
condition_table: [16]proc(flags: u32) -> bool
```

Actually, even better—since you only have 4 flag bits (N, Z, C, V), you can precompute a `[16][16]bool` table: `condition_lut[condition_code][flags]`.

---

## Decision Summary

| Decision | Choice | Implication |
|----------|--------|-------------|
| BIOS | Require original | Must handle BIOS protection, simpler implementation |
| Allocator | Custom | Design memory subsystem around arena/pool allocators |
| Error handling | Tiered | Balance debugging ease with accurate emulation |
| Target game | Tetris (GBA) | Relatively simple requirements, good first milestone |

---

## Tetris-Specific Considerations

GBA Tetris (assuming Tetris Worlds or Classic NES Series: Tetris) is a good first target because:

### What It Uses

- Mode 0 or Mode 4 (simple)
- Basic sprites for pieces
- VBlank for frame sync
- Timers for drop speed
- Simple audio (PSG channels)
- SRAM save (probably)
- Keypad input

### What It Doesn't Use (Probably)

- Affine transformations
- Complex blending effects
- DMA for raster effects
- HBlank interrupts
- Direct Sound (maybe)

### Milestone: "Tetris Boots"

Defined as:

1. Nintendo logo animation plays (from BIOS)
2. THQ/developer logos appear
3. Title screen renders correctly
4. Menu is navigable
5. Gameplay screen shows falling pieces

This exercises: CPU (all basic ops), Bus (ROM/RAM), PPU (Mode 0/4, sprites), Timer (piece drop), Keypad (navigation).
