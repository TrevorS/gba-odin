# CLAUDE.md

This file provides guidance to Claude Code when working with this GBA emulator project.

## Project Overview

This is a Game Boy Advance emulator written in Odin. The goal is to create a clean, well-documented, reasonably accurate emulator that can play commercial games.

## Development Commands

```bash
# Build the emulator
make build

# Build and run
make run

# Build with debug symbols
make debug

# Run tests
make test

# Clean build artifacts
make clean
```

## Project Structure

```
gba-odin/
├── src/
│   ├── main.odin           # Entry point, main loop
│   ├── gba.odin            # Top-level GBA struct, orchestration
│   ├── scheduler.odin      # Event-driven timing coordinator
│   ├── cpu/
│   │   ├── arm7tdmi.odin   # CPU state and core logic
│   │   ├── arm.odin        # ARM instruction handlers
│   │   ├── thumb.odin      # THUMB instruction handlers
│   │   ├── conditions.odin # Condition evaluation LUT
│   │   └── disasm.odin     # Disassembler
│   ├── bus/
│   │   ├── bus.odin        # Memory bus, read/write dispatch
│   │   ├── mmio.odin       # I/O register dispatch
│   │   └── waitstates.odin # Timing tables
│   ├── ppu/                # Picture Processing Unit
│   ├── apu/                # Audio Processing Unit
│   ├── dma.odin            # DMA controller
│   ├── timer.odin          # Timer 0-3
│   ├── keypad.odin         # Input handling
│   └── cartridge.odin      # ROM loading, save detection
├── docs/
│   ├── TECHNICAL_REQUIREMENTS.md  # Detailed specifications
│   └── DESIGN.md                  # Design decisions and rationale
├── bios/                   # Place bios.bin here (gitignored)
├── roms/                   # Test ROMs (gitignored)
├── saves/                  # Save files (gitignored)
├── build/                  # Build output (gitignored)
└── .claude/
    └── skills/             # Claude Code skills for this project
```

## Key Technical Decisions

1. **BIOS**: Requires original GBA BIOS (bios.bin, 16KB)
2. **Allocator**: Custom arena allocator for all emulated memory
3. **Scheduler**: Event-driven timing (not cycle-counting)
4. **Target Game**: Tetris (GBA) as first milestone

## Implementation Phases

- **Phase 1**: CPU (ARM7TDMI) + Memory Bus + Scheduler
- **Phase 2**: PPU fundamentals (Mode 0/3/4)
- **Phase 3**: Interrupts + Timers
- **Phase 4**: DMA
- **Phase 5**: Complete PPU
- **Phase 6**: Audio
- **Phase 7**: Polish (saves, edge cases)

## Documentation

- `docs/TECHNICAL_REQUIREMENTS.md` - Detailed technical specifications
- `docs/DESIGN.md` - Design rationale and GBA hardware overview
- GBATEK: https://problemkaputt.de/gbatek.htm (primary reference)

## Testing

```bash
# CPU instruction tests
# Place jsmolka's arm.gba and thumb.gba in roms/

make test    # Run Odin tests
make run     # Run with a ROM
```

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

### Version Control
- Use jj if available (`jj root` to check)
- Otherwise use standard git workflow
- Commit messages: conventional commits format
