package main

// GBA System Constants
CLOCK_FREQUENCY :: 16_777_216 // 2^24 Hz

// Memory region sizes
BIOS_SIZE :: 16_384       // 16 KB
EWRAM_SIZE :: 262_144     // 256 KB
IWRAM_SIZE :: 32_768      // 32 KB
PALETTE_SIZE :: 1_024     // 1 KB
VRAM_SIZE :: 98_304       // 96 KB
OAM_SIZE :: 1_024         // 1 KB
IO_SIZE :: 1_024          // 1 KB
TOTAL_ARENA_SIZE :: BIOS_SIZE + EWRAM_SIZE + IWRAM_SIZE + PALETTE_SIZE + VRAM_SIZE + OAM_SIZE + IO_SIZE // 411,648 bytes

// ROM constraints
ROM_MIN_SIZE :: 192
ROM_MAX_SIZE :: 33_554_432 // 32 MB
SRAM_SIZE :: 131_072       // 128 KB

// Display constants
SCREEN_WIDTH :: 240
SCREEN_HEIGHT :: 160
CYCLES_PER_SCANLINE :: 1232
VISIBLE_SCANLINES :: 160
VBLANK_SCANLINES :: 68
TOTAL_SCANLINES :: VISIBLE_SCANLINES + VBLANK_SCANLINES // 228
CYCLES_PER_FRAME :: CYCLES_PER_SCANLINE * TOTAL_SCANLINES // 280,896
HBLANK_START_CYCLE :: 960

// CPU Mode values
Mode :: enum u8 {
    User       = 0b10000,
    FIQ        = 0b10001,
    IRQ        = 0b10010,
    Supervisor = 0b10011,
    Abort      = 0b10111,
    Undefined  = 0b11011,
    System     = 0b11111,
}

// Exception vectors
VECTOR_RESET :: 0x00000000
VECTOR_UNDEFINED :: 0x00000004
VECTOR_SWI :: 0x00000008
VECTOR_PREFETCH_ABORT :: 0x0000000C
VECTOR_DATA_ABORT :: 0x00000010
VECTOR_IRQ :: 0x00000018
VECTOR_FIQ :: 0x0000001C

// CPSR bit positions
CPSR_N :: 31
CPSR_Z :: 30
CPSR_C :: 29
CPSR_V :: 28
CPSR_I :: 7
CPSR_F :: 6
CPSR_T :: 5
CPSR_MODE_MASK :: 0x1F

// Log levels
Log_Level :: enum {
    None,
    Error,
    Warn,
    Info,
    Debug,
    Trace,
}
