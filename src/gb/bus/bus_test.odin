package gb_bus

import "core:testing"

// =============================================================================
// Memory Size Constants Tests
// =============================================================================

@(test)
test_memory_sizes :: proc(t: ^testing.T) {
    testing.expect_value(t, VRAM_SIZE, int(8192))
    testing.expect_value(t, WRAM_SIZE, int(8192))
    testing.expect_value(t, OAM_SIZE, int(160))
    testing.expect_value(t, HRAM_SIZE, int(127))
    testing.expect_value(t, IO_SIZE, int(128))
}

// =============================================================================
// MBC Detection Tests
// =============================================================================

@(test)
test_detect_mbc_none :: proc(t: ^testing.T) {
    // Cart type 0x00 = ROM only
    mbc := detect_mbc(0x00)
    testing.expect_value(t, mbc, MBC_Type.None)

    // Cart type 0x08 = ROM+RAM
    mbc = detect_mbc(0x08)
    testing.expect_value(t, mbc, MBC_Type.None)

    // Cart type 0x09 = ROM+RAM+Battery
    mbc = detect_mbc(0x09)
    testing.expect_value(t, mbc, MBC_Type.None)
}

@(test)
test_detect_mbc1 :: proc(t: ^testing.T) {
    // Cart types 0x01-0x03 = MBC1
    testing.expect_value(t, detect_mbc(0x01), MBC_Type.MBC1)
    testing.expect_value(t, detect_mbc(0x02), MBC_Type.MBC1)
    testing.expect_value(t, detect_mbc(0x03), MBC_Type.MBC1)
}

@(test)
test_detect_mbc2 :: proc(t: ^testing.T) {
    testing.expect_value(t, detect_mbc(0x05), MBC_Type.MBC2)
    testing.expect_value(t, detect_mbc(0x06), MBC_Type.MBC2)
}

@(test)
test_detect_mbc3 :: proc(t: ^testing.T) {
    testing.expect_value(t, detect_mbc(0x0F), MBC_Type.MBC3)
    testing.expect_value(t, detect_mbc(0x10), MBC_Type.MBC3)
    testing.expect_value(t, detect_mbc(0x11), MBC_Type.MBC3)
    testing.expect_value(t, detect_mbc(0x12), MBC_Type.MBC3)
    testing.expect_value(t, detect_mbc(0x13), MBC_Type.MBC3)
}

@(test)
test_detect_mbc5 :: proc(t: ^testing.T) {
    testing.expect_value(t, detect_mbc(0x19), MBC_Type.MBC5)
    testing.expect_value(t, detect_mbc(0x1A), MBC_Type.MBC5)
    testing.expect_value(t, detect_mbc(0x1B), MBC_Type.MBC5)
    testing.expect_value(t, detect_mbc(0x1C), MBC_Type.MBC5)
    testing.expect_value(t, detect_mbc(0x1D), MBC_Type.MBC5)
    testing.expect_value(t, detect_mbc(0x1E), MBC_Type.MBC5)
}

// =============================================================================
// Bus Initialization Tests
// =============================================================================

@(test)
test_bus_init :: proc(t: ^testing.T) {
    bus: Bus
    rom := make([]u8, 0x8000)  // 32KB ROM
    defer delete(rom)

    rom[0x147] = 0x00  // No MBC

    eram := make([]u8, 0x2000)  // 8KB ERAM
    defer delete(eram)

    bus_init(&bus, rom, eram)

    testing.expect_value(t, bus.mbc_type, MBC_Type.None)
    testing.expect_value(t, bus.rom_bank, u16(1))
    testing.expect_value(t, bus.ram_bank, u8(0))
    testing.expect(t, !bus.ram_enabled, "RAM should be disabled by default")
    testing.expect_value(t, bus.joypad_buttons, u8(0x0F))
    testing.expect_value(t, bus.joypad_dpad, u8(0x0F))
}

// =============================================================================
// Memory Read Tests
// =============================================================================

@(test)
test_read_rom_bank0 :: proc(t: ^testing.T) {
    bus: Bus
    rom := make([]u8, 0x8000)
    defer delete(rom)

    rom[0x0000] = 0x12
    rom[0x3FFF] = 0x34

    bus_init(&bus, rom, nil)

    testing.expect_value(t, read(&bus, 0x0000), u8(0x12))
    testing.expect_value(t, read(&bus, 0x3FFF), u8(0x34))
}

@(test)
test_read_rom_bank1 :: proc(t: ^testing.T) {
    bus: Bus
    rom := make([]u8, 0x8000)
    defer delete(rom)

    rom[0x4000] = 0x56
    rom[0x7FFF] = 0x78

    bus_init(&bus, rom, nil)

    testing.expect_value(t, read(&bus, 0x4000), u8(0x56))
    testing.expect_value(t, read(&bus, 0x7FFF), u8(0x78))
}

@(test)
test_read_vram :: proc(t: ^testing.T) {
    bus: Bus
    bus_init(&bus, nil, nil)

    bus.vram[0x0000] = 0xAA
    bus.vram[0x1FFF] = 0xBB

    testing.expect_value(t, read(&bus, 0x8000), u8(0xAA))
    testing.expect_value(t, read(&bus, 0x9FFF), u8(0xBB))
}

@(test)
test_read_wram :: proc(t: ^testing.T) {
    bus: Bus
    bus_init(&bus, nil, nil)

    bus.wram[0x0000] = 0xCC
    bus.wram[0x1FFF] = 0xDD

    testing.expect_value(t, read(&bus, 0xC000), u8(0xCC))
    testing.expect_value(t, read(&bus, 0xDFFF), u8(0xDD))
}

@(test)
test_read_echo_ram :: proc(t: ^testing.T) {
    bus: Bus
    bus_init(&bus, nil, nil)

    bus.wram[0x0000] = 0xEE

    // Echo RAM mirrors WRAM
    testing.expect_value(t, read(&bus, 0xE000), u8(0xEE))
}

@(test)
test_read_oam :: proc(t: ^testing.T) {
    bus: Bus
    bus_init(&bus, nil, nil)

    bus.oam[0] = 0x11
    bus.oam[159] = 0x22

    testing.expect_value(t, read(&bus, 0xFE00), u8(0x11))
    testing.expect_value(t, read(&bus, 0xFE9F), u8(0x22))
}

@(test)
test_read_hram :: proc(t: ^testing.T) {
    bus: Bus
    bus_init(&bus, nil, nil)

    bus.hram[0] = 0x33
    bus.hram[126] = 0x44

    testing.expect_value(t, read(&bus, 0xFF80), u8(0x33))
    testing.expect_value(t, read(&bus, 0xFFFE), u8(0x44))
}

@(test)
test_read_ie :: proc(t: ^testing.T) {
    bus: Bus
    bus_init(&bus, nil, nil)

    bus.ie = 0x1F

    testing.expect_value(t, read(&bus, 0xFFFF), u8(0x1F))
}

// =============================================================================
// Memory Write Tests
// =============================================================================

@(test)
test_write_vram :: proc(t: ^testing.T) {
    bus: Bus
    bus_init(&bus, nil, nil)

    write(&bus, 0x8000, 0x55)
    write(&bus, 0x9FFF, 0x66)

    testing.expect_value(t, bus.vram[0x0000], u8(0x55))
    testing.expect_value(t, bus.vram[0x1FFF], u8(0x66))
}

@(test)
test_write_wram :: proc(t: ^testing.T) {
    bus: Bus
    bus_init(&bus, nil, nil)

    write(&bus, 0xC000, 0x77)
    write(&bus, 0xDFFF, 0x88)

    testing.expect_value(t, bus.wram[0x0000], u8(0x77))
    testing.expect_value(t, bus.wram[0x1FFF], u8(0x88))
}

@(test)
test_write_oam :: proc(t: ^testing.T) {
    bus: Bus
    bus_init(&bus, nil, nil)

    write(&bus, 0xFE00, 0x99)
    testing.expect_value(t, bus.oam[0], u8(0x99))
}

@(test)
test_write_hram :: proc(t: ^testing.T) {
    bus: Bus
    bus_init(&bus, nil, nil)

    write(&bus, 0xFF80, 0xAA)
    testing.expect_value(t, bus.hram[0], u8(0xAA))
}

@(test)
test_write_ie :: proc(t: ^testing.T) {
    bus: Bus
    bus_init(&bus, nil, nil)

    write(&bus, 0xFFFF, 0x1F)
    testing.expect_value(t, bus.ie, u8(0x1F))
}

// =============================================================================
// MBC Banking Tests
// =============================================================================

@(test)
test_mbc1_rom_bank_switch :: proc(t: ^testing.T) {
    bus: Bus
    rom := make([]u8, 0x80000)  // 512KB ROM (32 banks)
    defer delete(rom)

    rom[0x147] = 0x01  // MBC1

    // Write different values at each bank
    for bank in 1 ..< 32 {
        base := bank * 0x4000
        rom[base] = u8(bank)
    }

    bus_init(&bus, rom, nil)

    // Switch to bank 5
    write(&bus, 0x2000, 0x05)
    testing.expect_value(t, bus.rom_bank, u16(5))
    testing.expect_value(t, read(&bus, 0x4000), u8(5))

    // Switch to bank 10
    write(&bus, 0x2000, 0x0A)
    testing.expect_value(t, bus.rom_bank, u16(10))
    testing.expect_value(t, read(&bus, 0x4000), u8(10))
}

@(test)
test_mbc1_bank_zero_becomes_one :: proc(t: ^testing.T) {
    bus: Bus
    rom := make([]u8, 0x8000)
    defer delete(rom)

    rom[0x147] = 0x01  // MBC1

    bus_init(&bus, rom, nil)

    // Writing 0 should select bank 1, not bank 0
    write(&bus, 0x2000, 0x00)
    testing.expect_value(t, bus.rom_bank, u16(1))
}

@(test)
test_mbc_ram_enable :: proc(t: ^testing.T) {
    bus: Bus
    rom := make([]u8, 0x8000)
    defer delete(rom)

    rom[0x147] = 0x03  // MBC1+RAM+Battery

    eram := make([]u8, 0x2000)
    defer delete(eram)

    bus_init(&bus, rom, eram)

    // RAM disabled by default
    testing.expect(t, !bus.ram_enabled, "RAM should be disabled initially")

    // Enable RAM by writing 0x0A to 0x0000-0x1FFF
    write(&bus, 0x0000, 0x0A)
    testing.expect(t, bus.ram_enabled, "RAM should be enabled")

    // Disable RAM by writing any other value
    write(&bus, 0x0000, 0x00)
    testing.expect(t, !bus.ram_enabled, "RAM should be disabled")
}

// =============================================================================
// Joypad Tests
// =============================================================================

@(test)
test_joypad_init :: proc(t: ^testing.T) {
    bus: Bus
    bus_init(&bus, nil, nil)

    // All buttons/dpad released (active low, so 0x0F = all released)
    testing.expect_value(t, bus.joypad_buttons, u8(0x0F))
    testing.expect_value(t, bus.joypad_dpad, u8(0x0F))
}

@(test)
test_update_joypad :: proc(t: ^testing.T) {
    bus: Bus
    bus_init(&bus, nil, nil)

    // Press A button (bit 0 = 0 means pressed, active low input)
    update_joypad(&bus, 0x0E, 0x0F)  // A pressed, dpad released

    // Select buttons (P14 = 0)
    bus.joypad_select = 0x10  // Select buttons

    joypad := read_io(&bus, 0xFF00)
    // Should show A pressed (bit 0 = 0)
    testing.expect_value(t, joypad & 0x01, u8(0x00))
}

// =============================================================================
// Timer Tests
// =============================================================================

@(test)
test_div_register :: proc(t: ^testing.T) {
    bus: Bus
    bus_init(&bus, nil, nil)

    bus.div = 0x50

    // Reading DIV
    testing.expect_value(t, read_io(&bus, 0xFF04), u8(0x50))

    // Writing any value resets DIV to 0
    write_io(&bus, 0xFF04, 0xFF)
    testing.expect_value(t, bus.div, u8(0x00))
    testing.expect_value(t, bus.div_counter, u16(0))
}

@(test)
test_timer_registers :: proc(t: ^testing.T) {
    bus: Bus
    bus_init(&bus, nil, nil)

    // TIMA
    write_io(&bus, 0xFF05, 0x42)
    testing.expect_value(t, bus.tima, u8(0x42))
    testing.expect_value(t, read_io(&bus, 0xFF05), u8(0x42))

    // TMA
    write_io(&bus, 0xFF06, 0x80)
    testing.expect_value(t, bus.tma, u8(0x80))
    testing.expect_value(t, read_io(&bus, 0xFF06), u8(0x80))

    // TAC (only bits 0-2 used)
    write_io(&bus, 0xFF07, 0xFF)
    testing.expect_value(t, bus.tac, u8(0x07))
}

@(test)
test_timer_tick :: proc(t: ^testing.T) {
    bus: Bus
    bus_init(&bus, nil, nil)

    // Enable timer at fastest speed (262144 Hz, increment every 16 cycles)
    bus.tac = 0x05  // Enabled, clock select 01

    bus.tima = 0xFE

    // Tick enough to cause overflow
    tick_timer(&bus, 16)
    testing.expect_value(t, bus.tima, u8(0xFF))

    tick_timer(&bus, 16)
    // Should overflow and reload from TMA
    testing.expect_value(t, bus.tima, bus.tma)
}

// =============================================================================
// Interrupt Tests
// =============================================================================

@(test)
test_request_interrupt :: proc(t: ^testing.T) {
    bus: Bus
    bus_init(&bus, nil, nil)

    bus.if_ = 0x00

    // Request VBlank interrupt
    request_interrupt(&bus, 0x01)
    testing.expect_value(t, bus.if_, u8(0x01))

    // Request Timer interrupt
    request_interrupt(&bus, 0x04)
    testing.expect_value(t, bus.if_, u8(0x05))  // Both set
}

@(test)
test_if_register :: proc(t: ^testing.T) {
    bus: Bus
    bus_init(&bus, nil, nil)

    write_io(&bus, 0xFF0F, 0x1F)
    testing.expect_value(t, bus.if_, u8(0x1F))

    // Read should have upper bits set
    val := read_io(&bus, 0xFF0F)
    testing.expect_value(t, val & 0x1F, u8(0x1F))
}
