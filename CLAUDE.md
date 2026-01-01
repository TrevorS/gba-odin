# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **Game Boy / Game Boy Advance emulator** written in Odin. The project supports:
- **Game Boy (DMG)** - Original Game Boy
- **Game Boy Color (GBC)** - Color-enhanced Game Boy
- **Game Boy Advance (GBA)** - 32-bit handheld

The goal is to create a clean, well-documented, reasonably accurate emulator that can play commercial games on all three platforms.

## Development Commands

```bash
# Build the emulator
make build

# Build and run
make run

# Build with debug symbols
make debug

# Run all unit tests (163 tests)
make test

# Run specific test suites
make test-gb-cpu     # GB CPU tests (34 tests)
make test-gb-ppu     # GB PPU tests (17 tests)
make test-gb-bus     # GB Bus tests (30 tests)
make test-gba-cpu    # GBA CPU tests (55 tests)
make test-gba-ppu    # GBA PPU tests (27 tests)

# Style and lint checks
make lint            # Strict style check (1TBS brace style)
make check           # Full vet check (unused vars, shadowing)
make check-warnings  # Show warnings without failing

# Clean build artifacts
make clean
```

## Architecture Overview

The emulator supports both GB/GBC and GBA with shared infrastructure:

```
main.odin → detects system type → runs gb.GameBoy or GBA struct

GBA:                           GB/GBC:
┌─────────────────────┐        ┌─────────────────────┐
│ gba.odin (GBA)      │        │ gb/gb.odin (GameBoy)│
│ - Orchestrates all  │        │ - 70224 cycles/frame│
│ - Scheduler-driven  │        │ - Timer-based sync  │
├─────────────────────┤        ├─────────────────────┤
│ cpu/arm7tdmi.odin   │        │ gb/cpu/lr35902.odin │
│ - ARM/THUMB decode  │        │ - 8-bit CPU         │
│ - 4096-entry LUT    │        │ - 256-entry LUT     │
├─────────────────────┤        ├─────────────────────┤
│ bus/bus.odin        │        │ gb/bus/bus.odin     │
│ - Memory map        │        │ - MBC1/3/5 support  │
│ - Waitstate timing  │        │ - I/O registers     │
├─────────────────────┤        ├─────────────────────┤
│ ppu/ppu.odin        │        │ gb/ppu/ppu.odin     │
│ - Mode 0/3/4        │        │ - Scanline renderer │
│ - Sprites           │        │ - BG/Window/Sprites │
└─────────────────────┘        └─────────────────────┘
```

**Key patterns:**
- Lookup tables for instruction dispatch (`@(init)` populated at startup)
- Event-driven scheduler for GBA timing (not cycle-counting)
- Scanline-based rendering for both PPU implementations
- Arena allocator for all emulated memory regions

## Key Technical Decisions

1. **BIOS**: GBA can run with original BIOS or `--skip-bios` for testing
2. **Allocator**: Custom arena allocator for all emulated memory
3. **Scheduler**: Event-driven timing (not cycle-counting) for GBA
4. **Auto-detection**: ROM file extension and header used to detect system type

## Implementation Status

### Shared Components

| Component | Status | Notes |
|-----------|--------|-------|
| ROM Loading | ✅ Done | Auto-detection, header parsing |
| Input/Controller | ✅ Done | SDL2 keyboard/gamepad mapping |
| Framebuffer | ✅ Done | PNG export, headless mode |
| Audio (APU) | ❌ Not started | Different implementations, shared output |
| Save States | ❌ Not started | Serialize/deserialize emulator state |
| Battery Saves | ❌ Not started | SRAM/Flash persistence |

### Game Boy (GB/GBC)

| Phase | Status | Components |
|-------|--------|------------|
| **Phase 1** | ✅ Done | CPU (LR35902), Memory Bus, MBC1/3/5 |
| **Phase 2** | ✅ Done | PPU (BG, Window, Sprites), Interrupts, Timer, Input |
| **Phase 3** | ❌ Pending | Audio (APU) - 4 channels |
| **Phase 4** | ❌ Pending | Polish (save states, serial link stub) |

**Current:** Playable - Tetris and other games run correctly

### Game Boy Advance (GBA)

| Phase | Status | Components |
|-------|--------|------------|
| **Phase 1** | ✅ Done | CPU (ARM7TDMI), Memory Bus, Scheduler |
| **Phase 2** | ✅ Done | PPU (Mode 0/3/4, Sprites, OAM) |
| **Phase 3** | ❌ Pending | Interrupts (IE/IF/IME), Timers (TM0-TM3) |
| **Phase 4** | ❌ Pending | DMA (channels 0-3) |
| **Phase 5** | ❌ Pending | Complete PPU (Mode 1/2/5, windows, blending, mosaic) |
| **Phase 6** | ❌ Pending | Audio (APU) - 4 legacy + 2 direct sound |
| **Phase 7** | ❌ Pending | Polish (saves, RTC, edge cases) |

**Current:** CPU passes all ARM and THUMB instruction tests (jsmolka test suite)

## Documentation

- `docs/TECHNICAL_REQUIREMENTS.md` - Detailed technical specifications
- `docs/DESIGN.md` - Design rationale and GBA hardware overview
- GBATEK: https://problemkaputt.de/gbatek.htm (primary reference)

## Testing

Tests use Odin's `testing` package with `@(test)`. Test files are co-located with source (e.g., `arm7tdmi_test.odin`).

### Writing Tests

```odin
package my_package

import "core:testing"

@(test)
test_example :: proc(t: ^testing.T) {
    // Use testing.expect for boolean conditions
    testing.expect(t, actual == expected, "description")

    // Use testing.expect_value for value comparisons
    testing.expect_value(t, actual, expected)
}
```

### Integration Testing

```bash
# Run with a ROM to test full integration
make run ARGS="roms/test.gb"

# Headless mode for automated testing (GBA)
./build/gba-odin --headless --skip-bios --frames 300 --screenshot output.png roms/test.gba

# Headless mode (GB)
./build/gba-odin --headless --frames 300 --screenshot output.png roms/test.gb
```

### ROM Tests

For GBA CPU validation, place jsmolka's test ROMs in `roms/tests/jsmolka/`:
- `arm.gba` - ARM instruction tests (all pass ✅)
- `thumb.gba` - THUMB instruction tests (all pass ✅)

## Benchmarking

```bash
make bench           # Build with -o:speed and run benchmarks
```

Benchmarks measure critical hot paths (condition eval, decode, register access, mode switch). Add new benchmarks to `benchmarks/main.odin` using `core:time.Benchmark_Options`.

## Language Server (OLS)

This project uses OLS for LSP features. Configuration is in `ols.json` and `.lsp.json`.

**Installation:** Use the `odin-install` skill or build from source:
```bash
cd /tmp && git clone --depth 1 https://github.com/DanielGavin/ols.git
cd /tmp/ols && ./build.sh && ./odinfmt.sh
sudo cp /tmp/ols/ols /tmp/ols/odinfmt /usr/local/bin/
```

**Claude Code on the web:** The SessionStart hook (`.claude/hooks/session-start.sh`) auto-installs Odin and OLS when `$CLAUDE_CODE_REMOTE=true`.

## Automatic Hooks

| Hook | Trigger | Action |
|------|---------|--------|
| `SessionStart` | Claude Code starts | Installs Odin/OLS on web environments |
| `PostToolUse:Edit` | After editing `.odin` | Runs `odin check` on modified package |
| `Stop` | Claude finishes responding | Auto-formats and runs project-wide check |

All hooks are non-blocking (exit code 1 shows warnings without interrupting).

## Guidelines

### Odin Idioms
- Use `bit_field` for hardware registers
- Use `#force_inline` for hot paths
- Use `@(init)` for table initialization
- Use `Maybe(T)` for optional values
- Use `#partial switch` for subset handling

### Code Style
- Prioritize readability over maximum performance
- Document hardware behavior being emulated
- Use tables for instruction dispatch (not giant switches)
- Keep functions small and focused
- Follow 1TBS brace style (enforced by `make lint`)

### Version Control
- Use jj if available (`jj root` to check)
- Otherwise use standard git workflow
- Commit messages: conventional commits format
