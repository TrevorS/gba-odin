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

# Run tests
make test

# Clean build artifacts
make clean
```

## Project Structure

```
gba-odin/
├── src/
│   ├── main.odin           # Entry point, system detection, main loop
│   ├── system.odin         # System type detection (GB/GBC/GBA)
│   ├── gba.odin            # Top-level GBA struct, orchestration
│   ├── scheduler.odin      # Event-driven timing coordinator
│   ├── cpu/                # GBA CPU (ARM7TDMI)
│   │   ├── arm7tdmi.odin   # CPU state and core logic
│   │   ├── arm.odin        # ARM instruction handlers
│   │   ├── thumb.odin      # THUMB instruction handlers
│   │   ├── conditions.odin # Condition evaluation LUT
│   │   └── bios_hle.odin   # BIOS high-level emulation
│   ├── bus/                # GBA memory bus
│   │   ├── bus.odin        # Memory bus, read/write dispatch
│   │   └── mmio.odin       # I/O register dispatch
│   ├── ppu/                # GBA Picture Processing Unit
│   │   └── ppu.odin        # PPU rendering (Mode 0/3/4)
│   ├── gb/                 # Game Boy / Game Boy Color
│   │   ├── gb.odin         # GB system orchestration
│   │   ├── cpu/
│   │   │   └── lr35902.odin    # GB CPU (LR35902/SM83)
│   │   ├── bus/
│   │   │   └── bus.odin        # GB memory bus, MBC support
│   │   └── ppu/
│   │       └── ppu.odin        # GB PPU rendering
│   └── cartridge.odin      # ROM loading, save detection
├── docs/
│   ├── TECHNICAL_REQUIREMENTS.md  # Detailed specifications
│   └── DESIGN.md                  # Design decisions and rationale
├── bios/                   # Place GBA bios.bin here (gitignored)
├── roms/                   # Test ROMs (gitignored)
├── saves/                  # Save files (gitignored)
├── build/                  # Build output (gitignored)
└── .claude/
    └── skills/             # Claude Code skills for this project
```

## Key Technical Decisions

1. **BIOS**: GBA requires original BIOS (bios.bin, 16KB); GB runs without BIOS
2. **Allocator**: Custom arena allocator for all emulated memory
3. **Scheduler**: Event-driven timing (not cycle-counting) for GBA
4. **Auto-detection**: ROM file extension and header used to detect system type

## Implementation Status

### Game Boy (GB/GBC) - Playable ✅
- [x] CPU (LR35902) - Full instruction set
- [x] PPU - Background, window, sprites
- [x] Memory Bus - MBC1/MBC3/MBC5 support
- [x] Interrupts - VBlank, STAT, Timer, Joypad
- [x] Timer
- [x] Input
- [ ] Audio (APU)
- [ ] Save states

### Game Boy Advance (GBA) - In Progress
- **Phase 1** ✅: CPU (ARM7TDMI) + Memory Bus + Scheduler
- **Phase 2** 🔄: PPU fundamentals (Mode 0/3/4 + Sprites)
- **Phase 3**: Interrupts + Timers
- **Phase 4**: DMA
- **Phase 5**: Complete PPU (all modes, windows, effects)
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
