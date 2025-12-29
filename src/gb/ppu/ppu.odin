package gb_ppu

// Game Boy PPU (Picture Processing Unit)
// Resolution: 160x144
// 4 shades of gray (or colors on CGB)
// Tile-based rendering with sprites

SCREEN_WIDTH :: 160
SCREEN_HEIGHT :: 144

// PPU modes
Mode :: enum u8 {
    HBlank = 0,    // Mode 0: H-Blank (204 cycles)
    VBlank = 1,    // Mode 1: V-Blank (4560 cycles total)
    OAM    = 2,    // Mode 2: OAM Search (80 cycles)
    Draw   = 3,    // Mode 3: Drawing (172-289 cycles)
}

// LCDC register bits
LCDC_ENABLE     :: 0x80  // Bit 7: LCD Enable
LCDC_WIN_MAP    :: 0x40  // Bit 6: Window Tile Map (0=9800, 1=9C00)
LCDC_WIN_EN     :: 0x20  // Bit 5: Window Enable
LCDC_TILE_DATA  :: 0x10  // Bit 4: BG & Window Tile Data (0=8800, 1=8000)
LCDC_BG_MAP     :: 0x08  // Bit 3: BG Tile Map (0=9800, 1=9C00)
LCDC_OBJ_SIZE   :: 0x04  // Bit 2: OBJ Size (0=8x8, 1=8x16)
LCDC_OBJ_EN     :: 0x02  // Bit 1: OBJ Enable
LCDC_BG_EN      :: 0x01  // Bit 0: BG Enable (different on CGB)

// STAT register bits
STAT_LYC_INT    :: 0x40  // Bit 6: LYC=LY Interrupt
STAT_OAM_INT    :: 0x20  // Bit 5: Mode 2 OAM Interrupt
STAT_VBLANK_INT :: 0x10  // Bit 4: Mode 1 VBlank Interrupt
STAT_HBLANK_INT :: 0x08  // Bit 3: Mode 0 HBlank Interrupt
STAT_LYC_FLAG   :: 0x04  // Bit 2: LYC=LY Flag (read-only)
STAT_MODE       :: 0x03  // Bits 0-1: Mode Flag (read-only)

PPU :: struct {
    // Registers
    lcdc: u8,   // 0xFF40 - LCD Control
    stat: u8,   // 0xFF41 - LCD Status
    scy:  u8,   // 0xFF42 - Scroll Y
    scx:  u8,   // 0xFF43 - Scroll X
    ly:   u8,   // 0xFF44 - LY (current scanline)
    lyc:  u8,   // 0xFF45 - LY Compare
    bgp:  u8,   // 0xFF47 - BG Palette
    obp0: u8,   // 0xFF48 - OBJ Palette 0
    obp1: u8,   // 0xFF49 - OBJ Palette 1
    wy:   u8,   // 0xFF4A - Window Y
    wx:   u8,   // 0xFF4B - Window X

    // Internal state
    mode:        Mode,
    cycle:       u16,        // Cycle within current scanline
    window_line: u8,         // Internal window line counter

    // Memory references (set by emulator)
    vram: ^[8192]u8,
    oam:  ^[160]u8,

    // Framebuffer (RGB values, 2 bytes per pixel: RGB555)
    framebuffer: [SCREEN_HEIGHT][SCREEN_WIDTH]u16,

    // Interrupt callback
    request_interrupt: proc(bit: u8),
}

// Initialize PPU
ppu_init :: proc(p: ^PPU) {
    p.lcdc = 0x91  // LCD on, BG on
    p.stat = 0
    p.scy = 0
    p.scx = 0
    p.ly = 0
    p.lyc = 0
    p.bgp = 0xFC
    p.obp0 = 0xFF
    p.obp1 = 0xFF
    p.wy = 0
    p.wx = 0

    p.mode = .OAM
    p.cycle = 0
    p.window_line = 0
}

// Get STAT register (with mode and LYC flag)
get_stat :: proc(p: ^PPU) -> u8 {
    result := p.stat & 0x78  // Keep interrupt enable bits
    result |= u8(p.mode)     // Mode flag

    if p.ly == p.lyc {
        result |= STAT_LYC_FLAG
    }

    return result | 0x80  // Bit 7 always reads as 1
}

// Set STAT register (only interrupt enable bits are writable)
set_stat :: proc(p: ^PPU, value: u8) {
    p.stat = (p.stat & 0x07) | (value & 0x78)
}

// DMG color palette (RGB555)
DMG_COLORS := [4]u16{
    0x7FFF,  // White
    0x5294,  // Light gray
    0x294A,  // Dark gray
    0x0000,  // Black
}

// Get color from palette
get_palette_color :: proc(palette: u8, color_idx: u8) -> u16 {
    shade := (palette >> (color_idx * 2)) & 0x03
    return DMG_COLORS[shade]
}

// Step PPU by given number of cycles
step :: proc(p: ^PPU, cycles: u8) -> (vblank: bool, stat_int: bool) {
    if (p.lcdc & LCDC_ENABLE) == 0 {
        // LCD disabled
        return false, false
    }

    vblank = false
    stat_int = false

    p.cycle += u16(cycles)

    switch p.mode {
    case .OAM:  // Mode 2: 80 cycles
        if p.cycle >= 80 {
            p.cycle -= 80
            p.mode = .Draw
        }

    case .Draw:  // Mode 3: ~172 cycles (variable)
        if p.cycle >= 172 {
            p.cycle -= 172
            p.mode = .HBlank

            // Render scanline at end of Draw
            render_scanline(p)

            // HBlank interrupt
            if (p.stat & STAT_HBLANK_INT) != 0 {
                stat_int = true
            }
        }

    case .HBlank:  // Mode 0: 204 cycles
        if p.cycle >= 204 {
            p.cycle -= 204
            p.ly += 1

            if p.ly == 144 {
                // Enter VBlank
                p.mode = .VBlank
                vblank = true
                if p.request_interrupt != nil {
                    p.request_interrupt(0x01)  // VBlank interrupt
                }
                if (p.stat & STAT_VBLANK_INT) != 0 {
                    stat_int = true
                }
            } else {
                p.mode = .OAM
                if (p.stat & STAT_OAM_INT) != 0 {
                    stat_int = true
                }
            }

            // LYC compare
            check_lyc(p, &stat_int)
        }

    case .VBlank:  // Mode 1: 10 lines * 456 cycles
        if p.cycle >= 456 {
            p.cycle -= 456
            p.ly += 1

            if p.ly > 153 {
                // Return to top
                p.ly = 0
                p.window_line = 0
                p.mode = .OAM
                if (p.stat & STAT_OAM_INT) != 0 {
                    stat_int = true
                }
            }

            check_lyc(p, &stat_int)
        }
    }

    return
}

// Check LYC coincidence
check_lyc :: proc(p: ^PPU, stat_int: ^bool) {
    if p.ly == p.lyc {
        if (p.stat & STAT_LYC_INT) != 0 {
            stat_int^ = true
        }
    }
}

// Render a single scanline
render_scanline :: proc(p: ^PPU) {
    if p.vram == nil {
        return
    }

    ly := p.ly
    if ly >= SCREEN_HEIGHT {
        return
    }

    // Clear scanline
    for x in 0 ..< SCREEN_WIDTH {
        p.framebuffer[ly][x] = DMG_COLORS[0]
    }

    // Render background
    if (p.lcdc & LCDC_BG_EN) != 0 {
        render_bg_line(p, ly)
    }

    // Render window
    if (p.lcdc & LCDC_WIN_EN) != 0 && ly >= p.wy {
        render_window_line(p, ly)
    }

    // Render sprites
    if (p.lcdc & LCDC_OBJ_EN) != 0 {
        render_sprites_line(p, ly)
    }
}

// Render background for current scanline
render_bg_line :: proc(p: ^PPU, ly: u8) {
    // Get tile map base
    map_base: u16 = (p.lcdc & LCDC_BG_MAP) != 0 ? 0x1C00 : 0x1800

    // Get tile data base and addressing mode
    tile_base: u16 = (p.lcdc & LCDC_TILE_DATA) != 0 ? 0x0000 : 0x0800
    signed_addressing := (p.lcdc & LCDC_TILE_DATA) == 0

    y := u16(ly) + u16(p.scy)

    for x in u8(0) ..< SCREEN_WIDTH {
        px := u16(x) + u16(p.scx)

        // Get tile index
        tile_x := (px / 8) & 31
        tile_y := (y / 8) & 31
        tile_idx := p.vram[map_base + tile_y * 32 + tile_x]

        // Get tile address
        tile_addr: u16
        if signed_addressing {
            // Signed addressing: 0x9000 base
            tile_addr = u16(0x1000 + i16(i8(tile_idx)) * 16)
        } else {
            tile_addr = tile_base + u16(tile_idx) * 16
        }

        // Get pixel within tile
        tile_px := px & 7
        tile_py := y & 7

        // Get tile row data (2 bytes per row)
        row_addr := tile_addr + tile_py * 2
        lo := p.vram[row_addr]
        hi := p.vram[row_addr + 1]

        // Get pixel color (bit 7 = leftmost)
        bit := 7 - (tile_px & 7)
        color_idx := ((hi >> bit) & 1) << 1 | ((lo >> bit) & 1)

        p.framebuffer[ly][x] = get_palette_color(p.bgp, color_idx)
    }
}

// Render window for current scanline
render_window_line :: proc(p: ^PPU, ly: u8) {
    if p.wx > 166 {
        return
    }

    win_x := i16(p.wx) - 7
    if win_x < 0 { win_x = 0 }

    map_base: u16 = (p.lcdc & LCDC_WIN_MAP) != 0 ? 0x1C00 : 0x1800
    tile_base: u16 = (p.lcdc & LCDC_TILE_DATA) != 0 ? 0x0000 : 0x0800
    signed_addressing := (p.lcdc & LCDC_TILE_DATA) == 0

    win_y := u16(p.window_line)

    for x in u8(win_x) ..< SCREEN_WIDTH {
        px := u16(x) - u16(win_x)

        tile_x := px / 8
        tile_y := win_y / 8
        tile_idx := p.vram[map_base + tile_y * 32 + tile_x]

        tile_addr: u16
        if signed_addressing {
            tile_addr = u16(0x1000 + i16(i8(tile_idx)) * 16)
        } else {
            tile_addr = tile_base + u16(tile_idx) * 16
        }

        tile_px := px & 7
        tile_py := win_y & 7

        row_addr := tile_addr + tile_py * 2
        lo := p.vram[row_addr]
        hi := p.vram[row_addr + 1]

        bit := 7 - (tile_px & 7)
        color_idx := ((hi >> bit) & 1) << 1 | ((lo >> bit) & 1)

        p.framebuffer[ly][x] = get_palette_color(p.bgp, color_idx)
    }

    p.window_line += 1
}

// Render sprites for current scanline
render_sprites_line :: proc(p: ^PPU, ly: u8) {
    if p.oam == nil {
        return
    }

    sprite_height: u8 = (p.lcdc & LCDC_OBJ_SIZE) != 0 ? 16 : 8

    // Find sprites on this line (max 10)
    sprites_on_line: [10]u8
    sprite_count := 0

    for i in u8(0) ..< 40 {
        oam_addr := i * 4
        sprite_y := i16(p.oam[oam_addr]) - 16

        if i16(ly) >= sprite_y && i16(ly) < sprite_y + i16(sprite_height) {
            if sprite_count < 10 {
                sprites_on_line[sprite_count] = i
                sprite_count += 1
            }
        }
    }

    // Render sprites (in reverse order for proper priority)
    for i := sprite_count - 1; i >= 0; i -= 1 {
        sprite_idx := sprites_on_line[i]
        oam_addr := u16(sprite_idx) * 4

        sprite_y := i16(p.oam[oam_addr]) - 16
        sprite_x := i16(p.oam[oam_addr + 1]) - 8
        tile_idx := p.oam[oam_addr + 2]
        attrs := p.oam[oam_addr + 3]

        // 8x16 sprites: bit 0 of tile index is ignored
        if sprite_height == 16 {
            tile_idx &= 0xFE
        }

        flip_y := (attrs & 0x40) != 0
        flip_x := (attrs & 0x20) != 0
        priority := (attrs & 0x80) != 0
        palette := (attrs & 0x10) != 0 ? p.obp1 : p.obp0

        // Calculate which row of the sprite we're drawing
        row := u8(i16(ly) - sprite_y)
        if flip_y {
            row = sprite_height - 1 - row
        }

        // Get tile row data
        tile_addr := u16(tile_idx) * 16 + u16(row) * 2
        lo := p.vram[tile_addr]
        hi := p.vram[tile_addr + 1]

        // Draw sprite pixels
        for px in u8(0) ..< 8 {
            screen_x := sprite_x + i16(px)
            if screen_x < 0 || screen_x >= SCREEN_WIDTH {
                continue
            }

            bit := flip_x ? px : (7 - px)
            color_idx := ((hi >> bit) & 1) << 1 | ((lo >> bit) & 1)

            // Color 0 is transparent
            if color_idx == 0 {
                continue
            }

            // BG priority: if set and BG color != 0, don't draw
            if priority {
                // Check if BG pixel is non-zero
                // For simplicity, always draw (proper implementation would check)
            }

            p.framebuffer[ly][screen_x] = get_palette_color(palette, color_idx)
        }
    }
}
