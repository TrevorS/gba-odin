package ppu

// GBA PPU (Picture Processing Unit)
// Renders 240x160 pixels at 59.7275 Hz

// Display dimensions
SCREEN_WIDTH :: 240
SCREEN_HEIGHT :: 160

// Timing constants
CYCLES_PER_DOT :: 4
VISIBLE_DOTS :: 240
HBLANK_DOTS :: 68
TOTAL_DOTS :: VISIBLE_DOTS + HBLANK_DOTS // 308

VISIBLE_LINES :: 160
VBLANK_LINES :: 68
TOTAL_LINES :: VISIBLE_LINES + VBLANK_LINES // 228

CYCLES_PER_SCANLINE :: 1232 // 308 dots × 4 cycles
CYCLES_PER_FRAME :: CYCLES_PER_SCANLINE * TOTAL_LINES // 280,896

// Video modes
Video_Mode :: enum u8 {
    Mode_0 = 0, // 4 tiled BG layers
    Mode_1 = 1, // 2 tiled + 1 affine
    Mode_2 = 2, // 2 affine
    Mode_3 = 3, // 240x160 16bpp bitmap
    Mode_4 = 4, // 240x160 8bpp bitmap (double buffer)
    Mode_5 = 5, // 160x128 16bpp bitmap (double buffer)
}

// DISPCNT register (0x04000000)
DISPCNT :: struct {
    mode:            Video_Mode, // bits 0-2
    cgb_mode:        bool,       // bit 3 (GBC mode, read-only)
    frame_select:    bool,       // bit 4 (for Mode 4/5)
    hblank_interval: bool,       // bit 5 (allow OAM access in HBlank)
    obj_mapping:     bool,       // bit 6 (0=2D, 1=1D)
    forced_blank:    bool,       // bit 7
    bg0_enable:      bool,       // bit 8
    bg1_enable:      bool,       // bit 9
    bg2_enable:      bool,       // bit 10
    bg3_enable:      bool,       // bit 11
    obj_enable:      bool,       // bit 12
    win0_enable:     bool,       // bit 13
    win1_enable:     bool,       // bit 14
    objwin_enable:   bool,       // bit 15
}

// DISPSTAT register (0x04000004)
DISPSTAT :: struct {
    vblank_flag:   bool, // bit 0 (read-only)
    hblank_flag:   bool, // bit 1 (read-only)
    vcount_flag:   bool, // bit 2 (read-only)
    vblank_irq:    bool, // bit 3
    hblank_irq:    bool, // bit 4
    vcount_irq:    bool, // bit 5
    // bits 6-7 unused
    vcount_target: u8,   // bits 8-15
}

// BGxCNT register
BGCNT :: struct {
    priority:      u8,   // bits 0-1
    tile_base:     u8,   // bits 2-3 (× 16KB)
    // bit 4-5 unused
    mosaic:        bool, // bit 6
    palette_mode:  bool, // bit 7 (0=4bpp, 1=8bpp)
    map_base:      u8,   // bits 8-12 (× 2KB)
    overflow_wrap: bool, // bit 13 (affine only)
    size:          u8,   // bits 14-15
}

// PPU state
PPU :: struct {
    // Registers
    dispcnt:  DISPCNT,
    dispstat: DISPSTAT,
    vcount:   u16, // Current scanline (0-227)

    // Background control
    bgcnt:  [4]BGCNT,
    bghofs: [4]u16,
    bgvofs: [4]u16,

    // Affine background parameters (BG2/BG3)
    bg2pa, bg2pb, bg2pc, bg2pd: i16,
    bg2x, bg2y:                 i32,
    bg3pa, bg3pb, bg3pc, bg3pd: i16,
    bg3x, bg3y:                 i32,

    // Internal affine reference points (latched at VBlank)
    bg2x_ref, bg2y_ref: i32,
    bg3x_ref, bg3y_ref: i32,

    // Window registers
    win0h, win1h: u16,
    win0v, win1v: u16,
    winin, winout: u16,

    // Effects
    mosaic:   u16,
    bldcnt:   u16,
    bldalpha: u16,
    bldy:     u16,

    // Framebuffer (RGB555 format)
    framebuffer: [SCREEN_HEIGHT][SCREEN_WIDTH]u16,

    // Scanline buffer for compositing
    line_buffer: [SCREEN_WIDTH]u16,

    // Priority buffer for sprite compositing
    priority_buffer: [SCREEN_WIDTH]u8,

    // Memory pointers (set by bus)
    vram:    []u8,
    palette: []u8,
    oam:     []u8,
}

// Initialize PPU
ppu_init :: proc(ppu: ^PPU) {
    ppu.dispcnt = {}
    ppu.dispstat = {}
    ppu.vcount = 0

    for i in 0 ..< 4 {
        ppu.bgcnt[i] = {}
        ppu.bghofs[i] = 0
        ppu.bgvofs[i] = 0
    }

    ppu.bg2pa = 0x100
    ppu.bg2pb = 0
    ppu.bg2pc = 0
    ppu.bg2pd = 0x100
    ppu.bg2x = 0
    ppu.bg2y = 0

    ppu.bg3pa = 0x100
    ppu.bg3pb = 0
    ppu.bg3pc = 0
    ppu.bg3pd = 0x100
    ppu.bg3x = 0
    ppu.bg3y = 0

    ppu.bg2x_ref = 0
    ppu.bg2y_ref = 0
    ppu.bg3x_ref = 0
    ppu.bg3y_ref = 0

    // Clear framebuffer to magenta (debug color)
    for y in 0 ..< SCREEN_HEIGHT {
        for x in 0 ..< SCREEN_WIDTH {
            ppu.framebuffer[y][x] = 0x7C1F // Magenta in BGR555
        }
    }
}

// Set memory pointers
ppu_set_memory :: proc(ppu: ^PPU, vram: []u8, palette: []u8, oam: []u8) {
    ppu.vram = vram
    ppu.palette = palette
    ppu.oam = oam
}

// Read DISPCNT as u16
read_dispcnt :: proc(ppu: ^PPU) -> u16 {
    value: u16 = u16(ppu.dispcnt.mode)
    if ppu.dispcnt.cgb_mode { value |= 1 << 3 }
    if ppu.dispcnt.frame_select { value |= 1 << 4 }
    if ppu.dispcnt.hblank_interval { value |= 1 << 5 }
    if ppu.dispcnt.obj_mapping { value |= 1 << 6 }
    if ppu.dispcnt.forced_blank { value |= 1 << 7 }
    if ppu.dispcnt.bg0_enable { value |= 1 << 8 }
    if ppu.dispcnt.bg1_enable { value |= 1 << 9 }
    if ppu.dispcnt.bg2_enable { value |= 1 << 10 }
    if ppu.dispcnt.bg3_enable { value |= 1 << 11 }
    if ppu.dispcnt.obj_enable { value |= 1 << 12 }
    if ppu.dispcnt.win0_enable { value |= 1 << 13 }
    if ppu.dispcnt.win1_enable { value |= 1 << 14 }
    if ppu.dispcnt.objwin_enable { value |= 1 << 15 }
    return value
}

// Write DISPCNT from u16
write_dispcnt :: proc(ppu: ^PPU, value: u16) {
    ppu.dispcnt.mode = Video_Mode(value & 0x7)
    // cgb_mode is read-only
    ppu.dispcnt.frame_select = (value & (1 << 4)) != 0
    ppu.dispcnt.hblank_interval = (value & (1 << 5)) != 0
    ppu.dispcnt.obj_mapping = (value & (1 << 6)) != 0
    ppu.dispcnt.forced_blank = (value & (1 << 7)) != 0
    ppu.dispcnt.bg0_enable = (value & (1 << 8)) != 0
    ppu.dispcnt.bg1_enable = (value & (1 << 9)) != 0
    ppu.dispcnt.bg2_enable = (value & (1 << 10)) != 0
    ppu.dispcnt.bg3_enable = (value & (1 << 11)) != 0
    ppu.dispcnt.obj_enable = (value & (1 << 12)) != 0
    ppu.dispcnt.win0_enable = (value & (1 << 13)) != 0
    ppu.dispcnt.win1_enable = (value & (1 << 14)) != 0
    ppu.dispcnt.objwin_enable = (value & (1 << 15)) != 0
}

// Read DISPSTAT as u16
read_dispstat :: proc(ppu: ^PPU) -> u16 {
    value: u16 = 0
    if ppu.dispstat.vblank_flag { value |= 1 << 0 }
    if ppu.dispstat.hblank_flag { value |= 1 << 1 }
    if ppu.dispstat.vcount_flag { value |= 1 << 2 }
    if ppu.dispstat.vblank_irq { value |= 1 << 3 }
    if ppu.dispstat.hblank_irq { value |= 1 << 4 }
    if ppu.dispstat.vcount_irq { value |= 1 << 5 }
    value |= u16(ppu.dispstat.vcount_target) << 8
    return value
}

// Write DISPSTAT from u16
write_dispstat :: proc(ppu: ^PPU, value: u16) {
    // Bits 0-2 are read-only
    ppu.dispstat.vblank_irq = (value & (1 << 3)) != 0
    ppu.dispstat.hblank_irq = (value & (1 << 4)) != 0
    ppu.dispstat.vcount_irq = (value & (1 << 5)) != 0
    ppu.dispstat.vcount_target = u8(value >> 8)
}

// Read BGxCNT as u16
read_bgcnt :: proc(ppu: ^PPU, bg: int) -> u16 {
    if bg < 0 || bg > 3 { return 0 }
    cnt := &ppu.bgcnt[bg]
    value: u16 = u16(cnt.priority)
    value |= u16(cnt.tile_base) << 2
    if cnt.mosaic { value |= 1 << 6 }
    if cnt.palette_mode { value |= 1 << 7 }
    value |= u16(cnt.map_base) << 8
    if cnt.overflow_wrap { value |= 1 << 13 }
    value |= u16(cnt.size) << 14
    return value
}

// Write BGxCNT from u16
write_bgcnt :: proc(ppu: ^PPU, bg: int, value: u16) {
    if bg < 0 || bg > 3 { return }
    cnt := &ppu.bgcnt[bg]
    cnt.priority = u8(value & 0x3)
    cnt.tile_base = u8((value >> 2) & 0x3)
    cnt.mosaic = (value & (1 << 6)) != 0
    cnt.palette_mode = (value & (1 << 7)) != 0
    cnt.map_base = u8((value >> 8) & 0x1F)
    cnt.overflow_wrap = (value & (1 << 13)) != 0
    cnt.size = u8((value >> 14) & 0x3)
}

// Begin HBlank period
ppu_hblank :: proc(ppu: ^PPU) -> (hblank_irq: bool) {
    ppu.dispstat.hblank_flag = true
    return ppu.dispstat.hblank_irq
}

// End HBlank, advance to next scanline
ppu_end_hblank :: proc(ppu: ^PPU) -> (vblank_irq: bool, vcount_irq: bool) {
    ppu.dispstat.hblank_flag = false
    ppu.vcount += 1

    if ppu.vcount >= TOTAL_LINES {
        ppu.vcount = 0
        ppu.dispstat.vblank_flag = false

        // Latch affine reference points at start of frame
        ppu.bg2x_ref = ppu.bg2x
        ppu.bg2y_ref = ppu.bg2y
        ppu.bg3x_ref = ppu.bg3x
        ppu.bg3y_ref = ppu.bg3y
    }

    // Check VCOUNT match
    ppu.dispstat.vcount_flag = ppu.vcount == u16(ppu.dispstat.vcount_target)
    if ppu.dispstat.vcount_flag && ppu.dispstat.vcount_irq {
        vcount_irq = true
    }

    // Check for VBlank start
    if ppu.vcount == VISIBLE_LINES {
        ppu.dispstat.vblank_flag = true
        if ppu.dispstat.vblank_irq {
            vblank_irq = true
        }
    }

    return
}

// Render current scanline
ppu_render_scanline :: proc(ppu: ^PPU) {
    if ppu.vcount >= VISIBLE_LINES {
        return // VBlank, nothing to render
    }

    scanline := int(ppu.vcount)

    // Forced blank - render white
    if ppu.dispcnt.forced_blank {
        for x in 0 ..< SCREEN_WIDTH {
            ppu.framebuffer[scanline][x] = 0x7FFF // White
        }
        return
    }

    // Clear line buffer to backdrop color
    backdrop := read_palette16(ppu, 0)
    for x in 0 ..< SCREEN_WIDTH {
        ppu.line_buffer[x] = backdrop
        ppu.priority_buffer[x] = 4 // Lowest priority
    }

    // Render based on video mode
    #partial switch ppu.dispcnt.mode {
    case .Mode_0:
        render_mode0(ppu, scanline)
    case .Mode_3:
        render_mode3(ppu, scanline)
    case .Mode_4:
        render_mode4(ppu, scanline)
    case:
        // Other modes render backdrop only for now
    }

    // Render sprites if enabled
    if ppu.dispcnt.obj_enable {
        render_sprites(ppu, scanline)
    }

    // Copy line buffer to framebuffer
    for x in 0 ..< SCREEN_WIDTH {
        ppu.framebuffer[scanline][x] = ppu.line_buffer[x]
    }
}

// Read 16-bit color from palette RAM
read_palette16 :: proc(ppu: ^PPU, index: int) -> u16 {
    if ppu.palette == nil || index * 2 + 1 >= len(ppu.palette) {
        return 0
    }
    offset := index * 2
    return u16(ppu.palette[offset]) | (u16(ppu.palette[offset + 1]) << 8)
}

// Mode 3: 240x160 16bpp bitmap
render_mode3 :: proc(ppu: ^PPU, scanline: int) {
    if !ppu.dispcnt.bg2_enable || ppu.vram == nil {
        return
    }

    // Each pixel is 2 bytes (BGR555)
    base_offset := scanline * SCREEN_WIDTH * 2

    for x in 0 ..< SCREEN_WIDTH {
        offset := base_offset + x * 2
        if offset + 1 < len(ppu.vram) {
            color := u16(ppu.vram[offset]) | (u16(ppu.vram[offset + 1]) << 8)
            ppu.line_buffer[x] = color
        }
    }
}

// Mode 4: 240x160 8bpp bitmap with palette
render_mode4 :: proc(ppu: ^PPU, scanline: int) {
    if !ppu.dispcnt.bg2_enable || ppu.vram == nil {
        return
    }

    // Frame buffer base: 0x0000 or 0xA000 based on frame_select
    frame_base := ppu.dispcnt.frame_select ? 0xA000 : 0x0000
    base_offset := frame_base + scanline * SCREEN_WIDTH

    for x in 0 ..< SCREEN_WIDTH {
        offset := base_offset + x
        if offset < len(ppu.vram) {
            palette_index := int(ppu.vram[offset])
            color := read_palette16(ppu, palette_index)
            ppu.line_buffer[x] = color
        }
    }
}

// Mode 0: 4 tiled background layers
render_mode0 :: proc(ppu: ^PPU, scanline: int) {
    // Render backgrounds in priority order (3 = lowest, 0 = highest)
    // We render from lowest to highest so higher priority overwrites

    for priority := 3; priority >= 0; priority -= 1 {
        if ppu.dispcnt.bg3_enable && ppu.bgcnt[3].priority == u8(priority) {
            render_text_bg(ppu, 3, scanline)
        }
        if ppu.dispcnt.bg2_enable && ppu.bgcnt[2].priority == u8(priority) {
            render_text_bg(ppu, 2, scanline)
        }
        if ppu.dispcnt.bg1_enable && ppu.bgcnt[1].priority == u8(priority) {
            render_text_bg(ppu, 1, scanline)
        }
        if ppu.dispcnt.bg0_enable && ppu.bgcnt[0].priority == u8(priority) {
            render_text_bg(ppu, 0, scanline)
        }
    }
}

// Render a text/tiled background layer
render_text_bg :: proc(ppu: ^PPU, bg: int, scanline: int) {
    if ppu.vram == nil || ppu.palette == nil {
        return
    }

    cnt := &ppu.bgcnt[bg]

    // Get scroll offsets
    scroll_x := int(ppu.bghofs[bg])
    scroll_y := int(ppu.bgvofs[bg])

    // Calculate base addresses
    map_base := int(cnt.map_base) * 0x800    // × 2KB
    tile_base := int(cnt.tile_base) * 0x4000 // × 16KB

    // Get background dimensions based on size
    bg_width, bg_height: int
    switch cnt.size {
    case 0:
        bg_width, bg_height = 256, 256
    case 1:
        bg_width, bg_height = 512, 256
    case 2:
        bg_width, bg_height = 256, 512
    case 3:
        bg_width, bg_height = 512, 512
    }

    is_8bpp := cnt.palette_mode

    // Render each pixel in the scanline
    for screen_x in 0 ..< SCREEN_WIDTH {
        // Calculate the background coordinates
        bg_x := (screen_x + scroll_x) % bg_width
        bg_y := (scanline + scroll_y) % bg_height

        // Find which tile this pixel is in
        tile_x := bg_x / 8
        tile_y := bg_y / 8
        pixel_x := bg_x % 8
        pixel_y := bg_y % 8

        // Calculate screen block offset for large backgrounds
        screen_block := 0
        tiles_per_row := bg_width / 8
        if bg_width == 512 && tile_x >= 32 {
            screen_block += 1
            tile_x -= 32
        }
        if bg_height == 512 && tile_y >= 32 {
            screen_block += bg_width == 512 ? 2 : 1
            tile_y -= 32
        }

        // Read map entry (2 bytes per entry)
        map_offset := map_base + screen_block * 0x800 + (tile_y * 32 + tile_x) * 2
        if map_offset + 1 >= len(ppu.vram) {
            continue
        }

        map_entry := u16(ppu.vram[map_offset]) | (u16(ppu.vram[map_offset + 1]) << 8)

        tile_num := int(map_entry & 0x3FF)
        h_flip := (map_entry & (1 << 10)) != 0
        v_flip := (map_entry & (1 << 11)) != 0
        palette_bank := int((map_entry >> 12) & 0xF)

        // Apply flipping
        if h_flip { pixel_x = 7 - pixel_x }
        if v_flip { pixel_y = 7 - pixel_y }

        // Read pixel from tile data
        color_index: int

        if is_8bpp {
            // 8bpp: 64 bytes per tile
            tile_offset := tile_base + tile_num * 64 + pixel_y * 8 + pixel_x
            if tile_offset >= len(ppu.vram) {
                continue
            }
            color_index = int(ppu.vram[tile_offset])
        } else {
            // 4bpp: 32 bytes per tile
            tile_offset := tile_base + tile_num * 32 + pixel_y * 4 + pixel_x / 2
            if tile_offset >= len(ppu.vram) {
                continue
            }
            byte := ppu.vram[tile_offset]
            if pixel_x & 1 == 0 {
                color_index = int(byte & 0xF)
            } else {
                color_index = int(byte >> 4)
            }
            // Add palette bank offset for 4bpp
            if color_index != 0 {
                color_index += palette_bank * 16
            }
        }

        // Skip transparent pixels (index 0)
        if color_index == 0 {
            continue
        }

        // Read color from palette
        color := read_palette16(ppu, color_index)
        ppu.line_buffer[screen_x] = color
    }
}

// OAM Attribute structure (8 bytes per sprite, 128 sprites max)
OAM_Attr :: struct {
    // Attribute 0
    y:          u8,      // Y coordinate (0-255, wraps)
    rot_scale:  bool,    // Rotation/Scaling flag
    double_size: bool,   // Double size (rot/scale) or disable (normal)
    mode:       u8,      // 0=Normal, 1=Semi-transparent, 2=OBJ Window, 3=Forbidden
    mosaic:     bool,
    palette_mode: bool,  // 0=4bpp, 1=8bpp
    shape:      u8,      // 0=Square, 1=Horizontal, 2=Vertical

    // Attribute 1
    x:          u16,     // X coordinate (9 bits, signed)
    rot_param:  u8,      // Rotation/scaling parameter group (if rot_scale)
    h_flip:     bool,    // Horizontal flip (if !rot_scale)
    v_flip:     bool,    // Vertical flip (if !rot_scale)
    size:       u8,      // Size selector (0-3)

    // Attribute 2
    tile_num:   u16,     // Base tile number (10 bits)
    priority:   u8,      // Priority (0-3)
    palette:    u8,      // Palette bank (4bpp only)
}

// Sprite size lookup table [shape][size] -> (width, height)
SPRITE_SIZES := [3][4][2]u8{
    // Square
    {{8, 8}, {16, 16}, {32, 32}, {64, 64}},
    // Horizontal
    {{16, 8}, {32, 8}, {32, 16}, {64, 32}},
    // Vertical
    {{8, 16}, {8, 32}, {16, 32}, {32, 64}},
}

// Parse OAM entry from raw bytes
parse_oam_entry :: proc(oam: []u8, index: int) -> OAM_Attr {
    if oam == nil || index * 8 + 7 >= len(oam) {
        return {}
    }

    base := index * 8
    attr0 := u16(oam[base]) | (u16(oam[base + 1]) << 8)
    attr1 := u16(oam[base + 2]) | (u16(oam[base + 3]) << 8)
    attr2 := u16(oam[base + 4]) | (u16(oam[base + 5]) << 8)

    attr: OAM_Attr
    attr.y = u8(attr0 & 0xFF)
    attr.rot_scale = (attr0 & (1 << 8)) != 0
    attr.double_size = (attr0 & (1 << 9)) != 0
    attr.mode = u8((attr0 >> 10) & 0x3)
    attr.mosaic = (attr0 & (1 << 12)) != 0
    attr.palette_mode = (attr0 & (1 << 13)) != 0
    attr.shape = u8((attr0 >> 14) & 0x3)

    attr.x = attr1 & 0x1FF
    if attr.rot_scale {
        attr.rot_param = u8((attr1 >> 9) & 0x1F)
    } else {
        attr.h_flip = (attr1 & (1 << 12)) != 0
        attr.v_flip = (attr1 & (1 << 13)) != 0
    }
    attr.size = u8((attr1 >> 14) & 0x3)

    attr.tile_num = attr2 & 0x3FF
    attr.priority = u8((attr2 >> 10) & 0x3)
    attr.palette = u8((attr2 >> 12) & 0xF)

    return attr
}

// Render sprites for current scanline
render_sprites :: proc(ppu: ^PPU, scanline: int) {
    if ppu.oam == nil || ppu.vram == nil || ppu.palette == nil {
        return
    }

    is_1d_mapping := ppu.dispcnt.obj_mapping

    // Process all 128 sprites (in reverse order for correct priority)
    for i := 127; i >= 0; i -= 1 {
        attr := parse_oam_entry(ppu.oam, i)

        // Skip disabled sprites (rot_scale=0 and double_size=1 means disabled)
        if !attr.rot_scale && attr.double_size {
            continue
        }

        // Skip forbidden mode
        if attr.mode == 3 {
            continue
        }

        // Get sprite dimensions
        if attr.shape > 2 || attr.size > 3 {
            continue
        }
        sprite_width := int(SPRITE_SIZES[attr.shape][attr.size][0])
        sprite_height := int(SPRITE_SIZES[attr.shape][attr.size][1])

        // Handle double size for rotation/scaling
        render_width := sprite_width
        render_height := sprite_height
        if attr.rot_scale && attr.double_size {
            render_width *= 2
            render_height *= 2
        }

        // Calculate sprite Y position (handle wrap-around)
        sprite_y := int(attr.y)
        if sprite_y >= 160 {
            sprite_y -= 256
        }

        // Check if sprite is on this scanline
        if scanline < sprite_y || scanline >= sprite_y + render_height {
            continue
        }

        // Calculate which row of the sprite we're rendering
        sprite_row := scanline - sprite_y

        // Handle vertical flip (non-rotated sprites only)
        if !attr.rot_scale && attr.v_flip {
            sprite_row = render_height - 1 - sprite_row
        }

        // For double-size rotation sprites, adjust to actual sprite coordinates
        if attr.rot_scale && attr.double_size {
            // TODO: Proper rotation/scaling support
            // For now, just render without rotation
            sprite_row = sprite_row / 2
            if sprite_row >= sprite_height {
                continue
            }
        }

        // Calculate sprite X position (9-bit signed)
        sprite_x := int(attr.x)
        if sprite_x >= 256 {
            sprite_x -= 512
        }

        // Tile base for sprites is at 0x10000 in VRAM
        tile_base := 0x10000

        // Render each pixel of the sprite row
        for px in 0 ..< render_width {
            screen_x := sprite_x + px
            if screen_x < 0 || screen_x >= SCREEN_WIDTH {
                continue
            }

            // Handle horizontal flip
            pixel_x := px
            if !attr.rot_scale && attr.h_flip {
                pixel_x = render_width - 1 - px
            }

            // For double-size rotation, adjust pixel coordinate
            if attr.rot_scale && attr.double_size {
                pixel_x = pixel_x / 2
            }

            // Calculate tile coordinates
            tile_x := pixel_x / 8
            tile_y := sprite_row / 8
            pixel_in_tile_x := pixel_x % 8
            pixel_in_tile_y := sprite_row % 8

            // Calculate tile number based on mapping mode
            tile_num: int
            if is_1d_mapping {
                // 1D mapping: tiles are sequential
                tiles_per_row := sprite_width / 8
                if attr.palette_mode {
                    // 8bpp: tiles take 2x space
                    tile_num = int(attr.tile_num) + tile_y * tiles_per_row * 2 + tile_x * 2
                } else {
                    // 4bpp
                    tile_num = int(attr.tile_num) + tile_y * tiles_per_row + tile_x
                }
            } else {
                // 2D mapping: 32 tiles per row in VRAM
                if attr.palette_mode {
                    tile_num = int(attr.tile_num) + tile_y * 32 + tile_x * 2
                } else {
                    tile_num = int(attr.tile_num) + tile_y * 32 + tile_x
                }
            }

            // Read pixel from tile
            color_index: int
            if attr.palette_mode {
                // 8bpp: 64 bytes per tile
                tile_offset := tile_base + tile_num * 32 + pixel_in_tile_y * 8 + pixel_in_tile_x
                if tile_offset >= len(ppu.vram) {
                    continue
                }
                color_index = int(ppu.vram[tile_offset])
            } else {
                // 4bpp: 32 bytes per tile
                tile_offset := tile_base + tile_num * 32 + pixel_in_tile_y * 4 + pixel_in_tile_x / 2
                if tile_offset >= len(ppu.vram) {
                    continue
                }
                byte := ppu.vram[tile_offset]
                if pixel_in_tile_x & 1 == 0 {
                    color_index = int(byte & 0xF)
                } else {
                    color_index = int(byte >> 4)
                }
            }

            // Skip transparent pixels
            if color_index == 0 {
                continue
            }

            // Check priority against existing pixel
            if attr.priority >= ppu.priority_buffer[screen_x] {
                continue
            }

            // Get color from sprite palette (starts at offset 256 in palette RAM)
            palette_offset: int
            if attr.palette_mode {
                // 8bpp: single 256-color palette
                palette_offset = 256 + color_index
            } else {
                // 4bpp: 16 palettes of 16 colors each
                palette_offset = 256 + int(attr.palette) * 16 + color_index
            }

            color := read_palette16(ppu, palette_offset)
            ppu.line_buffer[screen_x] = color
            ppu.priority_buffer[screen_x] = attr.priority
        }
    }
}

// Check if frame is complete (at start of line 160)
ppu_frame_complete :: proc(ppu: ^PPU) -> bool {
    return ppu.vcount == VISIBLE_LINES
}

// Get pointer to framebuffer for display
ppu_get_framebuffer :: proc(ppu: ^PPU) -> ^[SCREEN_HEIGHT][SCREEN_WIDTH]u16 {
    return &ppu.framebuffer
}
