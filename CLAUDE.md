# CLAUDE.md

This file provides guidance to Claude Code when working with this emulator project.

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

## Project Structure

```
gba-odin/
├── src/
│   ├── main.odin           # Entry point, system detection, main loop
│   ├── system.odin         # System type detection (GB/GBC/GBA)
│   ├── cartridge.odin      # ROM loading, save detection (shared)
│   ├── gba.odin            # Top-level GBA struct, orchestration
│   ├── scheduler.odin      # Event-driven timing coordinator
│   ├── cpu/                # GBA CPU (ARM7TDMI)
│   │   ├── arm7tdmi.odin       # CPU state and core logic
│   │   ├── arm7tdmi_test.odin  # CPU unit tests (46 tests)
│   │   ├── arm.odin            # ARM instruction handlers
│   │   ├── thumb.odin          # THUMB instruction handlers
│   │   ├── thumb_test.odin     # THUMB instruction tests (9 tests)
│   │   ├── conditions.odin     # Condition evaluation LUT
│   │   └── bios_hle.odin       # BIOS high-level emulation
│   ├── bus/                # GBA memory bus
│   │   ├── bus.odin        # Memory bus, read/write dispatch
│   │   └── mmio.odin       # I/O register dispatch
│   ├── ppu/                # GBA Picture Processing Unit
│   │   ├── ppu.odin        # PPU rendering (Mode 0/3/4 + sprites)
│   │   └── ppu_test.odin   # PPU unit tests (27 tests)
│   └── gb/                 # Game Boy / Game Boy Color
│       ├── gb.odin         # GB system orchestration
│       ├── cpu/
│       │   ├── lr35902.odin      # GB CPU (LR35902/SM83)
│       │   └── lr35902_test.odin # GB CPU tests (34 tests)
│       ├── bus/
│       │   ├── bus.odin          # GB memory bus, MBC support
│       │   └── bus_test.odin     # GB Bus tests (30 tests)
│       └── ppu/
│           ├── ppu.odin          # GB PPU rendering
│           └── ppu_test.odin     # GB PPU tests (17 tests)
├── docs/
│   ├── TECHNICAL_REQUIREMENTS.md  # Detailed specifications
│   └── DESIGN.md                  # Design decisions and rationale
├── bios/                   # Place GBA bios.bin here (gitignored)
├── roms/                   # Test ROMs (gitignored)
│   └── tests/jsmolka/      # ARM/THUMB test ROMs
├── saves/                  # Save files (gitignored)
├── build/                  # Build output (gitignored)
├── benchmarks/             # Performance benchmarks
│   └── main.odin           # Benchmark runner
└── .claude/
    └── skills/             # Claude Code skills for this project
```

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

### Unit Tests

The project has comprehensive unit tests for all core components. Tests use Odin's built-in `testing` package with the `@(test)` attribute.

```bash
# Run all unit tests (163 tests total)
make test

# Run specific test suites
make test-gb-cpu    # GB CPU tests (34 tests)
make test-gb-ppu    # GB PPU tests (17 tests)
make test-gb-bus    # GB Bus tests (30 tests)
make test-gba-cpu   # GBA CPU tests (55 tests)
make test-gba-ppu   # GBA PPU tests (27 tests)
```

### Test Files

| Component | Test File | Tests | Coverage |
|-----------|-----------|-------|----------|
| GB CPU (LR35902) | `src/gb/cpu/lr35902_test.odin` | 34 | Registers, flags, ALU, interrupts, init |
| GB PPU | `src/gb/ppu/ppu_test.odin` | 17 | Modes, STAT/LCDC, timing, palettes |
| GB Bus | `src/gb/bus/bus_test.odin` | 30 | MBC detection, banking, I/O registers |
| GBA CPU (ARM7TDMI) | `src/cpu/arm7tdmi_test.odin` | 46 | Modes, flags, exceptions, conditions |
| GBA THUMB | `src/cpu/thumb_test.odin` | 9 | LDRH, POP PC, LDM/STM edge cases |
| GBA PPU | `src/ppu/ppu_test.odin` | 27 | Video modes, BGCNT, sprites, OAM |

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

## Style and Linting

Odin has built-in style checking:

```bash
make lint            # Enforces 1TBS brace style (-strict-style)
make check           # Full vetting (-vet): unused vars, shadowing
make check-warnings  # Show warnings without failing build
```

## Benchmarking

Odin provides built-in benchmarking via `core:time`. Run performance benchmarks with:

```bash
make bench           # Build with -o:speed and run benchmarks
```

### Benchmark Results

The benchmarks measure critical hot paths:

| Operation | Description |
|-----------|-------------|
| Condition eval | ARM condition code evaluation (14 codes) |
| ARM decode | ARM instruction LUT lookup |
| THUMB decode | THUMB instruction LUT lookup |
| Register access | Register read/write with banking |
| Mode switch | CPU mode transitions with bank swapping |

### Writing Benchmarks

Add benchmarks to `benchmarks/main.odin`:

```odin
import "core:time"
import "base:runtime"

// Define benchmark
opts := time.Benchmark_Options{
    bench = proc(opts: ^time.Benchmark_Options, _: runtime.Allocator) -> time.Benchmark_Error {
        for _ in 0 ..< opts.rounds {
            // Code to benchmark
            opts.count += 1  // Track operations
        }
        return .Okay
    },
    rounds = 100_000,
}

// Run and get results
time.benchmark(&opts)
// opts.duration, opts.rounds_per_second available
```

### Profiling with Spall

For detailed profiling, Odin integrates with [Spall](https://gravitymoth.com/spall/):

```odin
import "core:prof/spall"

// Manual instrumentation
spall.SCOPED_EVENT(&ctx, &buffer, #procedure)

// Or automatic instrumentation with @(instrumentation_enter/exit)
```

## Odin Language Server (OLS)

This project uses OLS for language server features and odinfmt for code formatting.

### Installation

If OLS is not installed, use the `odin-install` skill or run:

```bash
# Check if installed
which ols odinfmt

# If not installed, build from source:
cd /tmp && git clone --depth 1 https://github.com/DanielGavin/ols.git
cd /tmp/ols && ./build.sh && ./odinfmt.sh
sudo cp /tmp/ols/ols /tmp/ols/odinfmt /usr/local/bin/
```

### Configuration

The project includes `ols.json` at the root with proper collection paths. If Odin is updated, update the paths:

```bash
# Find current Odin install directory
ls /opt/ | grep odin

# Update ols.json collection paths to match
```

### Formatting

```bash
# Format a file (preview)
odinfmt src/main.odin

# Format and save in place
odinfmt -w src/main.odin

# Format from stdin
cat src/main.odin | odinfmt -stdin
```

### Claude Code LSP Integration

This project is configured for Claude Code's built-in LSP tools with OLS:

- **`.lsp.json`** - Configures OLS as the language server for `.odin` files
- **`.claude/settings.json`** - Enables `ENABLE_LSP_TOOLS=1` for this project

Available LSP operations (Claude Code v2.0.74+):
- **goToDefinition** - Jump to where a symbol is defined
- **findReferences** - Find all usages of a symbol
- **documentSymbol** - List all symbols in a file

To enable debug logging:
```bash
claude --enable-lsp-logging  # Logs go to ~/.claude/debug/
```

### Claude Code on the Web

This project includes a SessionStart hook (`.claude/hooks/session-start.sh`) that automatically installs Odin and OLS when running on Claude Code for the web. The hook:

1. Detects if running in remote environment (`$CLAUDE_CODE_REMOTE`)
2. Downloads and installs Odin from latest release
3. Builds and installs OLS and odinfmt from source
4. Sets `ODIN_ROOT` environment variable for the session

No manual setup needed - just open this repo in Claude Code on the web and the environment will be configured automatically.

### Manual OLS Queries

When Claude Code's built-in LSP tools aren't available, use the OLS wrapper script directly:

```bash
# List all symbols in a file
.claude/scripts/ols-query.sh symbols src/main.odin

# Find all references to a symbol (line and char are 0-indexed)
.claude/scripts/ols-query.sh references src/system.odin 3 0

# Check if file needs formatting
.claude/scripts/ols-query.sh format src/main.odin

# Get raw JSON output
.claude/scripts/ols-query.sh --raw symbols src/system.odin
```

Available operations: `symbols`, `references`, `definition`, `hover`, `format`

### Diagnostics and Formatting

OLS integrates with Odin's built-in tools for errors and formatting:

```bash
# Check for errors/warnings in the codebase
odin check src/

# Check a single file
odin check src/main.odin -file

# Format a file (preview)
odinfmt src/main.odin

# Format and save in place
odinfmt -w src/main.odin
```

The Makefile also provides:
- `make lint` - Strict style check (1TBS brace style)
- `make check` - Full vetting (unused vars, shadowing)
- `make check-warnings` - Show warnings without failing

### Automatic Hooks

The project includes automatic hooks for code quality:

| Hook | When | What |
|------|------|------|
| `SessionStart` | When Claude Code starts | Installs Odin and OLS on web environments |
| `PostToolUse:Edit` | After editing `.odin` files | Checks the modified package for errors |
| `Stop` | When Claude finishes responding | Auto-formats and runs project-wide check |

**Hook Details:**

- **SessionStart** (`.claude/hooks/session-start.sh`): Only runs on Claude Code for the web (`$CLAUDE_CODE_REMOTE=true`). Installs Odin from latest release and builds OLS from source.

- **PostToolUse:Edit** (`.claude/hooks/post-edit-check.sh`): Runs `odin check` on the package directory after each edit to an `.odin` file. Catches errors immediately while context is fresh. Skips test files.

- **Stop** (`.claude/hooks/stop-odin-check.sh`): When Claude finishes responding:
  1. Finds all `.odin` files modified in the last 5 minutes
  2. Auto-formats them with `odinfmt -w` (only if changes needed)
  3. Runs `odin check src/` for project-wide validation
  4. Reports summary of formatting and any errors

All hooks are **non-blocking** - they exit with code 1 to show warnings without interrupting the workflow. This means you'll see error summaries but can continue working.

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
