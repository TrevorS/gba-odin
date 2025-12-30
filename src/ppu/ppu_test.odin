package ppu

import "core:testing"

// =============================================================================
// Constants Tests
// =============================================================================

@(test)
test_screen_dimensions :: proc(t: ^testing.T) {
    testing.expect_value(t, SCREEN_WIDTH, int(240))
    testing.expect_value(t, SCREEN_HEIGHT, int(160))
}

@(test)
test_timing_constants :: proc(t: ^testing.T) {
    testing.expect_value(t, CYCLES_PER_DOT, int(4))
    testing.expect_value(t, VISIBLE_DOTS, int(240))
    testing.expect_value(t, HBLANK_DOTS, int(68))
    testing.expect_value(t, TOTAL_DOTS, int(308))

    testing.expect_value(t, VISIBLE_LINES, int(160))
    testing.expect_value(t, VBLANK_LINES, int(68))
    testing.expect_value(t, TOTAL_LINES, int(228))

    testing.expect_value(t, CYCLES_PER_SCANLINE, int(1232))
    testing.expect_value(t, CYCLES_PER_FRAME, int(280896))
}

// =============================================================================
// Video Mode Tests
// =============================================================================

@(test)
test_video_modes :: proc(t: ^testing.T) {
    testing.expect_value(t, u8(Video_Mode.Mode_0), u8(0))
    testing.expect_value(t, u8(Video_Mode.Mode_1), u8(1))
    testing.expect_value(t, u8(Video_Mode.Mode_2), u8(2))
    testing.expect_value(t, u8(Video_Mode.Mode_3), u8(3))
    testing.expect_value(t, u8(Video_Mode.Mode_4), u8(4))
    testing.expect_value(t, u8(Video_Mode.Mode_5), u8(5))
}

// =============================================================================
// PPU Initialization Tests
// =============================================================================

@(test)
test_ppu_init :: proc(t: ^testing.T) {
    p: PPU
    ppu_init(&p)

    testing.expect_value(t, p.vcount, u16(0))
    testing.expect_value(t, p.dispcnt.mode, Video_Mode.Mode_0)
    testing.expect(t, !p.dispcnt.forced_blank, "Forced blank should be off")

    // Affine params should be identity
    testing.expect_value(t, p.bg2pa, i16(0x100))
    testing.expect_value(t, p.bg2pd, i16(0x100))
    testing.expect_value(t, p.bg3pa, i16(0x100))
    testing.expect_value(t, p.bg3pd, i16(0x100))
}

@(test)
test_ppu_init_framebuffer :: proc(t: ^testing.T) {
    p: PPU
    ppu_init(&p)

    // Framebuffer should be initialized to magenta (debug color)
    testing.expect_value(t, p.framebuffer[0][0], u16(0x7C1F))
    testing.expect_value(t, p.framebuffer[79][119], u16(0x7C1F))
    testing.expect_value(t, p.framebuffer[159][239], u16(0x7C1F))
}

// =============================================================================
// DISPCNT Register Tests
// =============================================================================

@(test)
test_read_dispcnt :: proc(t: ^testing.T) {
    p: PPU
    ppu_init(&p)

    p.dispcnt.mode = .Mode_3
    p.dispcnt.bg2_enable = true
    p.dispcnt.obj_enable = true

    value := read_dispcnt(&p)

    testing.expect_value(t, value & 0x07, u16(3))  // Mode 3
    testing.expect(t, (value & (1 << 10)) != 0, "BG2 should be enabled")
    testing.expect(t, (value & (1 << 12)) != 0, "OBJ should be enabled")
}

@(test)
test_write_dispcnt :: proc(t: ^testing.T) {
    p: PPU
    ppu_init(&p)

    // Set Mode 4, BG2 enabled, OBJ enabled, 1D mapping
    write_dispcnt(&p, 0x1444)

    testing.expect_value(t, p.dispcnt.mode, Video_Mode.Mode_4)
    testing.expect(t, p.dispcnt.bg2_enable, "BG2 should be enabled")
    testing.expect(t, p.dispcnt.obj_enable, "OBJ should be enabled")
    testing.expect(t, p.dispcnt.obj_mapping, "1D mapping should be set")
}

@(test)
test_dispcnt_forced_blank :: proc(t: ^testing.T) {
    p: PPU
    ppu_init(&p)

    write_dispcnt(&p, 0x0080)  // Forced blank
    testing.expect(t, p.dispcnt.forced_blank, "Forced blank should be set")
}

// =============================================================================
// DISPSTAT Register Tests
// =============================================================================

@(test)
test_read_dispstat_flags :: proc(t: ^testing.T) {
    p: PPU
    ppu_init(&p)

    p.dispstat.vblank_flag = true
    p.dispstat.hblank_flag = true
    p.dispstat.vcount_target = 100

    value := read_dispstat(&p)

    testing.expect(t, (value & 0x01) != 0, "VBlank flag should be set")
    testing.expect(t, (value & 0x02) != 0, "HBlank flag should be set")
    testing.expect_value(t, u8(value >> 8), u8(100))
}

@(test)
test_write_dispstat :: proc(t: ^testing.T) {
    p: PPU
    ppu_init(&p)

    // Enable VBlank, HBlank, VCount IRQs, set target to 50
    write_dispstat(&p, 0x3238)

    testing.expect(t, p.dispstat.vblank_irq, "VBlank IRQ should be enabled")
    testing.expect(t, p.dispstat.hblank_irq, "HBlank IRQ should be enabled")
    testing.expect(t, p.dispstat.vcount_irq, "VCount IRQ should be enabled")
    testing.expect_value(t, p.dispstat.vcount_target, u8(50))
}

// =============================================================================
// BGCNT Register Tests
// =============================================================================

@(test)
test_read_bgcnt :: proc(t: ^testing.T) {
    p: PPU
    ppu_init(&p)

    p.bgcnt[0].priority = 2
    p.bgcnt[0].tile_base = 1
    p.bgcnt[0].palette_mode = true
    p.bgcnt[0].map_base = 15
    p.bgcnt[0].size = 3

    value := read_bgcnt(&p, 0)

    testing.expect_value(t, value & 0x03, u16(2))  // Priority
    testing.expect(t, (value & 0x80) != 0, "8bpp mode should be set")
    testing.expect_value(t, (value >> 14) & 0x03, u16(3))  // Size
}

@(test)
test_write_bgcnt :: proc(t: ^testing.T) {
    p: PPU
    ppu_init(&p)

    // Priority 1, tile base 2, 8bpp, map base 5, size 2
    // 0xA589 = 1010 0101 1000 1001
    // bits 0-1: 01 = priority 1
    // bits 2-3: 10 = tile_base 2
    // bit 7: 1 = 8bpp
    // bits 8-12: 00101 = map_base 5
    // bits 14-15: 10 = size 2
    write_bgcnt(&p, 1, 0xA589)

    testing.expect_value(t, p.bgcnt[1].priority, u8(1))
    testing.expect_value(t, p.bgcnt[1].tile_base, u8(2))
    testing.expect(t, p.bgcnt[1].palette_mode, "8bpp should be set")
    testing.expect_value(t, p.bgcnt[1].map_base, u8(5))
    testing.expect_value(t, p.bgcnt[1].size, u8(2))
}

// =============================================================================
// HBlank/VBlank Tests
// =============================================================================

@(test)
test_ppu_hblank :: proc(t: ^testing.T) {
    p: PPU
    ppu_init(&p)

    p.dispstat.hblank_irq = true
    irq := ppu_hblank(&p)

    testing.expect(t, p.dispstat.hblank_flag, "HBlank flag should be set")
    testing.expect(t, irq, "HBlank IRQ should fire")
}

@(test)
test_ppu_end_hblank_normal :: proc(t: ^testing.T) {
    p: PPU
    ppu_init(&p)

    p.dispstat.hblank_flag = true
    p.vcount = 50

    vblank_irq, vcount_irq := ppu_end_hblank(&p)

    testing.expect(t, !p.dispstat.hblank_flag, "HBlank flag should be cleared")
    testing.expect_value(t, p.vcount, u16(51))
    testing.expect(t, !vblank_irq, "No VBlank yet")
}

@(test)
test_ppu_end_hblank_enter_vblank :: proc(t: ^testing.T) {
    p: PPU
    ppu_init(&p)

    p.vcount = 159  // Last visible line
    p.dispstat.vblank_irq = true

    vblank_irq, _ := ppu_end_hblank(&p)

    testing.expect_value(t, p.vcount, u16(160))
    testing.expect(t, p.dispstat.vblank_flag, "VBlank flag should be set")
    testing.expect(t, vblank_irq, "VBlank IRQ should fire")
}

@(test)
test_ppu_end_hblank_wrap :: proc(t: ^testing.T) {
    p: PPU
    ppu_init(&p)

    p.vcount = 227  // Last line
    p.dispstat.vblank_flag = true

    ppu_end_hblank(&p)

    testing.expect_value(t, p.vcount, u16(0))
    testing.expect(t, !p.dispstat.vblank_flag, "VBlank flag should be cleared")
}

@(test)
test_ppu_vcount_match :: proc(t: ^testing.T) {
    p: PPU
    ppu_init(&p)

    p.vcount = 99
    p.dispstat.vcount_target = 100
    p.dispstat.vcount_irq = true

    _, vcount_irq := ppu_end_hblank(&p)

    testing.expect_value(t, p.vcount, u16(100))
    testing.expect(t, p.dispstat.vcount_flag, "VCount flag should be set")
    testing.expect(t, vcount_irq, "VCount IRQ should fire")
}

// =============================================================================
// Palette Tests
// =============================================================================

@(test)
test_read_palette16 :: proc(t: ^testing.T) {
    p: PPU
    ppu_init(&p)

    palette := make([]u8, 512)
    defer delete(palette)

    palette[0] = 0x1F  // Blue
    palette[1] = 0x00
    palette[2] = 0xE0  // Green (low byte)
    palette[3] = 0x03  // Green (high byte)

    ppu_set_memory(&p, nil, palette, nil)

    testing.expect_value(t, read_palette16(&p, 0), u16(0x001F))
    testing.expect_value(t, read_palette16(&p, 1), u16(0x03E0))
}

// =============================================================================
// Sprite Size Tests
// =============================================================================

@(test)
test_sprite_sizes_square :: proc(t: ^testing.T) {
    // Shape 0 = Square
    testing.expect_value(t, SPRITE_SIZES[0][0][0], u8(8))   // 8x8
    testing.expect_value(t, SPRITE_SIZES[0][0][1], u8(8))
    testing.expect_value(t, SPRITE_SIZES[0][1][0], u8(16))  // 16x16
    testing.expect_value(t, SPRITE_SIZES[0][1][1], u8(16))
    testing.expect_value(t, SPRITE_SIZES[0][2][0], u8(32))  // 32x32
    testing.expect_value(t, SPRITE_SIZES[0][2][1], u8(32))
    testing.expect_value(t, SPRITE_SIZES[0][3][0], u8(64))  // 64x64
    testing.expect_value(t, SPRITE_SIZES[0][3][1], u8(64))
}

@(test)
test_sprite_sizes_horizontal :: proc(t: ^testing.T) {
    // Shape 1 = Horizontal
    testing.expect_value(t, SPRITE_SIZES[1][0][0], u8(16))  // 16x8
    testing.expect_value(t, SPRITE_SIZES[1][0][1], u8(8))
    testing.expect_value(t, SPRITE_SIZES[1][1][0], u8(32))  // 32x8
    testing.expect_value(t, SPRITE_SIZES[1][1][1], u8(8))
    testing.expect_value(t, SPRITE_SIZES[1][2][0], u8(32))  // 32x16
    testing.expect_value(t, SPRITE_SIZES[1][2][1], u8(16))
    testing.expect_value(t, SPRITE_SIZES[1][3][0], u8(64))  // 64x32
    testing.expect_value(t, SPRITE_SIZES[1][3][1], u8(32))
}

@(test)
test_sprite_sizes_vertical :: proc(t: ^testing.T) {
    // Shape 2 = Vertical
    testing.expect_value(t, SPRITE_SIZES[2][0][0], u8(8))   // 8x16
    testing.expect_value(t, SPRITE_SIZES[2][0][1], u8(16))
    testing.expect_value(t, SPRITE_SIZES[2][1][0], u8(8))   // 8x32
    testing.expect_value(t, SPRITE_SIZES[2][1][1], u8(32))
    testing.expect_value(t, SPRITE_SIZES[2][2][0], u8(16))  // 16x32
    testing.expect_value(t, SPRITE_SIZES[2][2][1], u8(32))
    testing.expect_value(t, SPRITE_SIZES[2][3][0], u8(32))  // 32x64
    testing.expect_value(t, SPRITE_SIZES[2][3][1], u8(64))
}

// =============================================================================
// OAM Parsing Tests
// =============================================================================

@(test)
test_parse_oam_entry_basic :: proc(t: ^testing.T) {
    oam := make([]u8, 1024)
    defer delete(oam)

    // Sprite 0: Y=50, X=100, tile=0x100, no special flags
    oam[0] = 50      // Y
    oam[1] = 0x00    // attr0 high (no rot, normal mode, 4bpp, shape 0)
    oam[2] = 100     // X low
    oam[3] = 0x00    // X high, size 0
    oam[4] = 0x00    // tile low
    oam[5] = 0x01    // tile high (tile 0x100), priority 0
    oam[6] = 0x00    // padding
    oam[7] = 0x00    // padding

    attr := parse_oam_entry(oam, 0)

    testing.expect_value(t, attr.y, u8(50))
    testing.expect_value(t, attr.x, u16(100))
    testing.expect(t, !attr.rot_scale, "Should not be rotated")
    testing.expect(t, !attr.double_size, "Should not be double size")
    testing.expect_value(t, attr.shape, u8(0))
    testing.expect_value(t, attr.size, u8(0))
    testing.expect_value(t, attr.tile_num, u16(0x100))
}

@(test)
test_parse_oam_entry_with_flip :: proc(t: ^testing.T) {
    oam := make([]u8, 1024)
    defer delete(oam)

    // Sprite with H-flip and V-flip
    oam[0] = 0       // Y
    oam[1] = 0x00    // no rot
    oam[2] = 0       // X low
    oam[3] = 0x30    // H-flip (bit 12) and V-flip (bit 13)
    oam[4] = 0x00
    oam[5] = 0x00

    attr := parse_oam_entry(oam, 0)

    testing.expect(t, attr.h_flip, "H-flip should be set")
    testing.expect(t, attr.v_flip, "V-flip should be set")
}

@(test)
test_parse_oam_entry_disabled :: proc(t: ^testing.T) {
    oam := make([]u8, 1024)
    defer delete(oam)

    // Disabled sprite (rot_scale=0, double_size=1)
    oam[0] = 0
    oam[1] = 0x02    // double_size set, rot_scale clear

    attr := parse_oam_entry(oam, 0)

    testing.expect(t, !attr.rot_scale, "rot_scale should be clear")
    testing.expect(t, attr.double_size, "double_size should be set (disabled)")
}

@(test)
test_parse_oam_entry_8bpp :: proc(t: ^testing.T) {
    oam := make([]u8, 1024)
    defer delete(oam)

    // 8bpp sprite
    oam[0] = 0
    oam[1] = 0x20    // palette_mode = 1 (8bpp)

    attr := parse_oam_entry(oam, 0)

    testing.expect(t, attr.palette_mode, "Should be 8bpp mode")
}

@(test)
test_parse_oam_entry_palette :: proc(t: ^testing.T) {
    oam := make([]u8, 1024)
    defer delete(oam)

    // Sprite with palette bank 5
    oam[4] = 0x00
    oam[5] = 0x50    // palette = 5 (bits 12-15)

    attr := parse_oam_entry(oam, 0)

    testing.expect_value(t, attr.palette, u8(5))
}

// =============================================================================
// Frame Complete Test
// =============================================================================

@(test)
test_ppu_frame_complete :: proc(t: ^testing.T) {
    p: PPU
    ppu_init(&p)

    p.vcount = 159
    testing.expect(t, !ppu_frame_complete(&p), "Frame not complete at line 159")

    p.vcount = 160
    testing.expect(t, ppu_frame_complete(&p), "Frame complete at line 160")

    p.vcount = 161
    testing.expect(t, !ppu_frame_complete(&p), "Frame not complete at line 161")
}
