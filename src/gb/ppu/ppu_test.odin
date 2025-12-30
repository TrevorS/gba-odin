package gb_ppu

import "core:testing"

// =============================================================================
// Constants Tests
// =============================================================================

@(test)
test_screen_dimensions :: proc(t: ^testing.T) {
    testing.expect_value(t, SCREEN_WIDTH, int(160))
    testing.expect_value(t, SCREEN_HEIGHT, int(144))
}

@(test)
test_lcdc_flags :: proc(t: ^testing.T) {
    testing.expect(t, LCDC_ENABLE == 0x80, "LCDC_ENABLE should be 0x80")
    testing.expect(t, LCDC_WIN_MAP == 0x40, "LCDC_WIN_MAP should be 0x40")
    testing.expect(t, LCDC_WIN_EN == 0x20, "LCDC_WIN_EN should be 0x20")
    testing.expect(t, LCDC_TILE_DATA == 0x10, "LCDC_TILE_DATA should be 0x10")
    testing.expect(t, LCDC_BG_MAP == 0x08, "LCDC_BG_MAP should be 0x08")
    testing.expect(t, LCDC_OBJ_SIZE == 0x04, "LCDC_OBJ_SIZE should be 0x04")
    testing.expect(t, LCDC_OBJ_EN == 0x02, "LCDC_OBJ_EN should be 0x02")
    testing.expect(t, LCDC_BG_EN == 0x01, "LCDC_BG_EN should be 0x01")
}

@(test)
test_stat_flags :: proc(t: ^testing.T) {
    testing.expect(t, STAT_LYC_INT == 0x40, "STAT_LYC_INT should be 0x40")
    testing.expect(t, STAT_OAM_INT == 0x20, "STAT_OAM_INT should be 0x20")
    testing.expect(t, STAT_VBLANK_INT == 0x10, "STAT_VBLANK_INT should be 0x10")
    testing.expect(t, STAT_HBLANK_INT == 0x08, "STAT_HBLANK_INT should be 0x08")
    testing.expect(t, STAT_LYC_FLAG == 0x04, "STAT_LYC_FLAG should be 0x04")
    testing.expect(t, STAT_MODE == 0x03, "STAT_MODE should be 0x03")
}

// =============================================================================
// PPU Initialization Tests
// =============================================================================

@(test)
test_ppu_init :: proc(t: ^testing.T) {
    p: PPU
    ppu_init(&p)

    testing.expect_value(t, p.lcdc, u8(0x91))  // LCD on, BG on
    testing.expect_value(t, p.stat, u8(0x00))
    testing.expect_value(t, p.scy, u8(0x00))
    testing.expect_value(t, p.scx, u8(0x00))
    testing.expect_value(t, p.ly, u8(0x00))
    testing.expect_value(t, p.lyc, u8(0x00))
    testing.expect_value(t, p.bgp, u8(0xFC))
    testing.expect_value(t, p.wy, u8(0x00))
    testing.expect_value(t, p.wx, u8(0x00))
    testing.expect_value(t, p.mode, Mode.OAM)
    testing.expect_value(t, p.cycle, u16(0))
}

// =============================================================================
// STAT Register Tests
// =============================================================================

@(test)
test_get_stat_mode :: proc(t: ^testing.T) {
    p: PPU
    ppu_init(&p)

    // Mode is embedded in lower 2 bits
    p.mode = .HBlank
    stat := get_stat(&p)
    testing.expect_value(t, stat & 0x03, u8(0x00))

    p.mode = .VBlank
    stat = get_stat(&p)
    testing.expect_value(t, stat & 0x03, u8(0x01))

    p.mode = .OAM
    stat = get_stat(&p)
    testing.expect_value(t, stat & 0x03, u8(0x02))

    p.mode = .Draw
    stat = get_stat(&p)
    testing.expect_value(t, stat & 0x03, u8(0x03))
}

@(test)
test_get_stat_lyc_flag :: proc(t: ^testing.T) {
    p: PPU
    ppu_init(&p)

    // LYC flag set when LY == LYC
    p.ly = 0x50
    p.lyc = 0x50
    stat := get_stat(&p)
    testing.expect(t, (stat & STAT_LYC_FLAG) != 0, "LYC flag should be set")

    p.lyc = 0x51
    stat = get_stat(&p)
    testing.expect(t, (stat & STAT_LYC_FLAG) == 0, "LYC flag should be clear")
}

@(test)
test_set_stat :: proc(t: ^testing.T) {
    p: PPU
    ppu_init(&p)

    // Only bits 3-6 are writable
    set_stat(&p, 0xFF)

    stat := get_stat(&p)
    testing.expect(t, (stat & STAT_VBLANK_INT) != 0, "VBlank INT should be set")
    testing.expect(t, (stat & STAT_HBLANK_INT) != 0, "HBlank INT should be set")
    testing.expect(t, (stat & STAT_OAM_INT) != 0, "OAM INT should be set")
    testing.expect(t, (stat & STAT_LYC_INT) != 0, "LYC INT should be set")
}

// =============================================================================
// Palette Tests
// =============================================================================

@(test)
test_get_palette_color :: proc(t: ^testing.T) {
    // DMG palette: 0=white, 1=light gray, 2=dark gray, 3=black
    // Palette value 0xE4 = 11 10 01 00 = colors 3,2,1,0 for indices 3,2,1,0

    // Color index 0 with palette 0xE4 -> shade 0 (white)
    color := get_palette_color(0xE4, 0)
    testing.expect_value(t, color, DMG_COLORS[0])

    // Color index 1 with palette 0xE4 -> shade 1 (light gray)
    color = get_palette_color(0xE4, 1)
    testing.expect_value(t, color, DMG_COLORS[1])

    // Color index 2 with palette 0xE4 -> shade 2 (dark gray)
    color = get_palette_color(0xE4, 2)
    testing.expect_value(t, color, DMG_COLORS[2])

    // Color index 3 with palette 0xE4 -> shade 3 (black)
    color = get_palette_color(0xE4, 3)
    testing.expect_value(t, color, DMG_COLORS[3])
}

@(test)
test_dmg_colors :: proc(t: ^testing.T) {
    // Verify DMG color palette (RGB555)
    testing.expect_value(t, DMG_COLORS[0], u16(0x7FFF))  // White
    testing.expect_value(t, DMG_COLORS[3], u16(0x0000))  // Black
}

// =============================================================================
// PPU Step/Timing Tests
// =============================================================================

@(test)
test_ppu_step_lcd_disabled :: proc(t: ^testing.T) {
    p: PPU
    ppu_init(&p)

    // Disable LCD
    p.lcdc = 0x00

    vblank, stat_int := step(&p, 100)
    testing.expect(t, !vblank, "No VBlank when LCD disabled")
    testing.expect(t, !stat_int, "No STAT interrupt when LCD disabled")
}

@(test)
test_ppu_step_oam_to_draw :: proc(t: ^testing.T) {
    p: PPU
    ppu_init(&p)

    p.lcdc = LCDC_ENABLE
    p.mode = .OAM
    p.cycle = 0

    // OAM mode is 80 cycles
    step(&p, 40)
    testing.expect_value(t, p.mode, Mode.OAM)

    step(&p, 40)  // Total 80 cycles
    testing.expect_value(t, p.mode, Mode.Draw)
}

@(test)
test_ppu_step_draw_to_hblank :: proc(t: ^testing.T) {
    p: PPU
    ppu_init(&p)

    p.lcdc = LCDC_ENABLE
    p.mode = .Draw
    p.cycle = 0

    // Draw mode is ~172 cycles
    step(&p, 172)
    testing.expect_value(t, p.mode, Mode.HBlank)
}

@(test)
test_ppu_step_hblank_to_next_line :: proc(t: ^testing.T) {
    p: PPU
    ppu_init(&p)

    p.lcdc = LCDC_ENABLE
    p.mode = .HBlank
    p.ly = 0
    p.cycle = 0

    // HBlank is 204 cycles
    step(&p, 204)
    testing.expect_value(t, p.ly, u8(1))
    testing.expect_value(t, p.mode, Mode.OAM)
}

@(test)
test_ppu_step_enter_vblank :: proc(t: ^testing.T) {
    p: PPU
    ppu_init(&p)

    p.lcdc = LCDC_ENABLE
    p.mode = .HBlank
    p.ly = 143  // Last visible line
    p.cycle = 0

    vblank, _ := step(&p, 204)
    testing.expect(t, vblank, "Should signal VBlank")
    testing.expect_value(t, p.ly, u8(144))
    testing.expect_value(t, p.mode, Mode.VBlank)
}

@(test)
test_ppu_step_vblank_wrap :: proc(t: ^testing.T) {
    p: PPU
    ppu_init(&p)

    p.lcdc = LCDC_ENABLE
    p.mode = .VBlank
    p.ly = 153  // Last VBlank line
    p.cycle = 0

    // VBlank line is 456 cycles
    step(&p, 255)
    step(&p, 201)  // Total 456 cycles

    testing.expect_value(t, p.ly, u8(0))
    testing.expect_value(t, p.mode, Mode.OAM)
}

@(test)
test_ppu_lyc_interrupt :: proc(t: ^testing.T) {
    p: PPU
    ppu_init(&p)

    p.lcdc = LCDC_ENABLE
    p.mode = .HBlank
    p.ly = 49
    p.lyc = 50
    p.stat = STAT_LYC_INT  // Enable LYC interrupt
    p.cycle = 0

    _, stat_int := step(&p, 204)  // Advance to line 50

    testing.expect_value(t, p.ly, u8(50))
    testing.expect(t, stat_int, "LYC STAT interrupt should fire")
}

// =============================================================================
// Mode Enumeration Tests
// =============================================================================

@(test)
test_mode_values :: proc(t: ^testing.T) {
    testing.expect_value(t, u8(Mode.HBlank), u8(0))
    testing.expect_value(t, u8(Mode.VBlank), u8(1))
    testing.expect_value(t, u8(Mode.OAM), u8(2))
    testing.expect_value(t, u8(Mode.Draw), u8(3))
}
