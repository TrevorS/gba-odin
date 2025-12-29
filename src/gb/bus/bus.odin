package gb_bus

import "core:fmt"
import "../ppu"

// Game Boy Memory Map:
// 0000-3FFF: ROM Bank 0 (16KB)
// 4000-7FFF: ROM Bank 1-N (switchable, 16KB)
// 8000-9FFF: Video RAM (8KB, 16KB on CGB)
// A000-BFFF: External RAM (cartridge, 8KB)
// C000-CFFF: Work RAM Bank 0 (4KB)
// D000-DFFF: Work RAM Bank 1-7 (4KB, switchable on CGB)
// E000-FDFF: Echo RAM (mirror of C000-DDFF)
// FE00-FE9F: OAM (Sprite Attribute Table)
// FEA0-FEFF: Unusable
// FF00-FF7F: I/O Registers
// FF80-FFFE: High RAM (HRAM)
// FFFF: Interrupt Enable register

VRAM_SIZE :: 8192    // 8KB (16KB on CGB with banking)
WRAM_SIZE :: 8192    // 8KB (32KB on CGB with banking)
OAM_SIZE :: 160      // 160 bytes
HRAM_SIZE :: 127     // 127 bytes
IO_SIZE :: 128       // I/O registers

Bus :: struct {
    // Memory regions
    rom:      []u8,         // Cartridge ROM (up to 8MB)
    vram:     [VRAM_SIZE]u8,
    eram:     []u8,         // External RAM (cartridge, up to 128KB)
    wram:     [WRAM_SIZE]u8,
    oam:      [OAM_SIZE]u8,
    hram:     [HRAM_SIZE]u8,
    io:       [IO_SIZE]u8,

    // Interrupt registers
    ie:       u8,           // 0xFFFF - Interrupt Enable
    if_:      u8,           // 0xFF0F - Interrupt Flags

    // Memory bank controllers
    mbc_type: MBC_Type,
    rom_bank: u16,          // Current ROM bank (1-511)
    ram_bank: u8,           // Current RAM bank (0-15)
    ram_enabled: bool,      // RAM enable flag

    // MBC1 specific
    mbc1_mode: bool,        // false = ROM mode, true = RAM mode

    // PPU reference for VRAM/OAM access timing
    ppu: ^ppu.PPU,

    // Joypad state
    joypad_select: u8,      // P1 register bits 4-5
    joypad_buttons: u8,     // Buttons state (active low)
    joypad_dpad: u8,        // D-pad state (active low)

    // Timer registers (directly accessible)
    div:  u8,               // 0xFF04 - Divider
    tima: u8,               // 0xFF05 - Timer counter
    tma:  u8,               // 0xFF06 - Timer modulo
    tac:  u8,               // 0xFF07 - Timer control

    // Internal timer counter
    div_counter: u16,
    timer_counter: u16,

    // CGB mode flag
    cgb_mode: bool,
}

MBC_Type :: enum {
    None,       // No MBC (32KB ROM only)
    MBC1,
    MBC2,
    MBC3,
    MBC5,
}

// Initialize bus
bus_init :: proc(bus: ^Bus, rom: []u8, eram: []u8) {
    bus.rom = rom
    bus.eram = eram

    // Detect MBC type from cartridge header
    if len(rom) > 0x147 {
        bus.mbc_type = detect_mbc(rom[0x147])
    }

    // Initialize banks
    bus.rom_bank = 1
    bus.ram_bank = 0
    bus.ram_enabled = false
    bus.mbc1_mode = false

    // Initialize joypad (all released = 0xFF)
    bus.joypad_buttons = 0x0F
    bus.joypad_dpad = 0x0F
    bus.joypad_select = 0x30

    // Initialize timer
    bus.div = 0
    bus.tima = 0
    bus.tma = 0
    bus.tac = 0
    bus.div_counter = 0
    bus.timer_counter = 0
}

// Detect MBC type from cartridge type byte
detect_mbc :: proc(cart_type: u8) -> MBC_Type {
    switch cart_type {
    case 0x00, 0x08, 0x09:
        return .None
    case 0x01, 0x02, 0x03:
        return .MBC1
    case 0x05, 0x06:
        return .MBC2
    case 0x0F, 0x10, 0x11, 0x12, 0x13:
        return .MBC3
    case 0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E:
        return .MBC5
    case:
        return .None
    }
}

// Read byte from memory
read :: proc(bus: ^Bus, addr: u16) -> u8 {
    switch {
    case addr < 0x4000:
        // ROM Bank 0
        if int(addr) < len(bus.rom) {
            return bus.rom[addr]
        }
        return 0xFF

    case addr < 0x8000:
        // ROM Bank N
        bank_addr := u32(bus.rom_bank) * 0x4000 + u32(addr - 0x4000)
        if int(bank_addr) < len(bus.rom) {
            return bus.rom[bank_addr]
        }
        return 0xFF

    case addr < 0xA000:
        // VRAM
        return bus.vram[addr - 0x8000]

    case addr < 0xC000:
        // External RAM
        if bus.ram_enabled && len(bus.eram) > 0 {
            ram_addr := u32(bus.ram_bank) * 0x2000 + u32(addr - 0xA000)
            if int(ram_addr) < len(bus.eram) {
                return bus.eram[ram_addr]
            }
        }
        return 0xFF

    case addr < 0xD000:
        // WRAM Bank 0
        return bus.wram[addr - 0xC000]

    case addr < 0xE000:
        // WRAM Bank 1 (CGB: banks 1-7)
        return bus.wram[addr - 0xC000]

    case addr < 0xFE00:
        // Echo RAM (mirror of C000-DDFF)
        return bus.wram[addr - 0xE000]

    case addr < 0xFEA0:
        // OAM
        return bus.oam[addr - 0xFE00]

    case addr < 0xFF00:
        // Unusable
        return 0xFF

    case addr < 0xFF80:
        // I/O Registers
        return read_io(bus, addr)

    case addr < 0xFFFF:
        // HRAM
        return bus.hram[addr - 0xFF80]

    case addr == 0xFFFF:
        // Interrupt Enable
        return bus.ie
    }

    return 0xFF
}

// Write byte to memory
write :: proc(bus: ^Bus, addr: u16, value: u8) {
    switch {
    case addr < 0x2000:
        // RAM Enable (MBC)
        if bus.mbc_type != .None {
            bus.ram_enabled = (value & 0x0F) == 0x0A
        }

    case addr < 0x4000:
        // ROM Bank Number (lower bits)
        switch bus.mbc_type {
        case .MBC1:
            bank := u16(value & 0x1F)
            if bank == 0 { bank = 1 }
            bus.rom_bank = (bus.rom_bank & 0x60) | bank
        case .MBC3:
            bank := u16(value & 0x7F)
            if bank == 0 { bank = 1 }
            bus.rom_bank = bank
        case .MBC5:
            bus.rom_bank = (bus.rom_bank & 0x100) | u16(value)
        case .None, .MBC2:
            // No action or handled differently
        }

    case addr < 0x6000:
        // RAM Bank Number / Upper ROM Bank bits
        switch bus.mbc_type {
        case .MBC1:
            if bus.mbc1_mode {
                bus.ram_bank = value & 0x03
            } else {
                bus.rom_bank = (bus.rom_bank & 0x1F) | (u16(value & 0x03) << 5)
            }
        case .MBC3, .MBC5:
            bus.ram_bank = value & 0x0F
        case .None, .MBC2:
            // No action
        }

    case addr < 0x8000:
        // Banking Mode Select (MBC1)
        if bus.mbc_type == .MBC1 {
            bus.mbc1_mode = (value & 0x01) != 0
        }

    case addr < 0xA000:
        // VRAM
        bus.vram[addr - 0x8000] = value

    case addr < 0xC000:
        // External RAM
        if bus.ram_enabled && len(bus.eram) > 0 {
            ram_addr := u32(bus.ram_bank) * 0x2000 + u32(addr - 0xA000)
            if int(ram_addr) < len(bus.eram) {
                bus.eram[ram_addr] = value
            }
        }

    case addr < 0xE000:
        // WRAM
        bus.wram[addr - 0xC000] = value

    case addr < 0xFE00:
        // Echo RAM
        bus.wram[addr - 0xE000] = value

    case addr < 0xFEA0:
        // OAM
        bus.oam[addr - 0xFE00] = value

    case addr < 0xFF00:
        // Unusable - ignore

    case addr < 0xFF80:
        // I/O Registers
        write_io(bus, addr, value)

    case addr < 0xFFFF:
        // HRAM
        bus.hram[addr - 0xFF80] = value

    case addr == 0xFFFF:
        // Interrupt Enable
        bus.ie = value
    }
}

// Read I/O register
read_io :: proc(bus: ^Bus, addr: u16) -> u8 {
    switch addr {
    case 0xFF00: // P1/JOYP - Joypad
        result: u8 = 0xCF  // Bits 6-7 unused, always 1
        if (bus.joypad_select & 0x10) == 0 {
            // D-pad selected
            result = (result & 0xF0) | bus.joypad_dpad
        }
        if (bus.joypad_select & 0x20) == 0 {
            // Buttons selected
            result = (result & 0xF0) | bus.joypad_buttons
        }
        result |= bus.joypad_select & 0x30
        return result

    case 0xFF04: return bus.div   // DIV
    case 0xFF05: return bus.tima  // TIMA
    case 0xFF06: return bus.tma   // TMA
    case 0xFF07: return bus.tac | 0xF8  // TAC (bits 3-7 unused)
    case 0xFF0F: return bus.if_ | 0xE0  // IF (bits 5-7 unused)

    // PPU registers (delegated if PPU exists)
    case 0xFF40: return bus.ppu != nil ? bus.ppu.lcdc : 0
    case 0xFF41: return bus.ppu != nil ? ppu.get_stat(bus.ppu) : 0
    case 0xFF42: return bus.ppu != nil ? bus.ppu.scy : 0
    case 0xFF43: return bus.ppu != nil ? bus.ppu.scx : 0
    case 0xFF44: return bus.ppu != nil ? bus.ppu.ly : 0
    case 0xFF45: return bus.ppu != nil ? bus.ppu.lyc : 0
    case 0xFF47: return bus.ppu != nil ? bus.ppu.bgp : 0
    case 0xFF48: return bus.ppu != nil ? bus.ppu.obp0 : 0
    case 0xFF49: return bus.ppu != nil ? bus.ppu.obp1 : 0
    case 0xFF4A: return bus.ppu != nil ? bus.ppu.wy : 0
    case 0xFF4B: return bus.ppu != nil ? bus.ppu.wx : 0

    case:
        // Other I/O registers
        if addr >= 0xFF00 && addr < 0xFF80 {
            return bus.io[addr - 0xFF00]
        }
        return 0xFF
    }
}

// Write I/O register
write_io :: proc(bus: ^Bus, addr: u16, value: u8) {
    switch addr {
    case 0xFF00: // P1/JOYP
        bus.joypad_select = value & 0x30

    case 0xFF04: // DIV - writing any value resets to 0
        bus.div = 0
        bus.div_counter = 0

    case 0xFF05: bus.tima = value  // TIMA
    case 0xFF06: bus.tma = value   // TMA
    case 0xFF07: bus.tac = value & 0x07  // TAC
    case 0xFF0F: bus.if_ = value & 0x1F  // IF

    // PPU registers
    case 0xFF40: if bus.ppu != nil { bus.ppu.lcdc = value }
    case 0xFF41: if bus.ppu != nil { ppu.set_stat(bus.ppu, value) }
    case 0xFF42: if bus.ppu != nil { bus.ppu.scy = value }
    case 0xFF43: if bus.ppu != nil { bus.ppu.scx = value }
    case 0xFF45: if bus.ppu != nil { bus.ppu.lyc = value }
    case 0xFF46: // OAM DMA
        dma_transfer(bus, value)
    case 0xFF47: if bus.ppu != nil { bus.ppu.bgp = value }
    case 0xFF48: if bus.ppu != nil { bus.ppu.obp0 = value }
    case 0xFF49: if bus.ppu != nil { bus.ppu.obp1 = value }
    case 0xFF4A: if bus.ppu != nil { bus.ppu.wy = value }
    case 0xFF4B: if bus.ppu != nil { bus.ppu.wx = value }

    case:
        // Other I/O registers
        if addr >= 0xFF00 && addr < 0xFF80 {
            bus.io[addr - 0xFF00] = value
        }
    }
}

// OAM DMA transfer
dma_transfer :: proc(bus: ^Bus, value: u8) {
    src_addr := u16(value) << 8
    for i in u16(0) ..< 160 {
        bus.oam[i] = read(bus, src_addr + i)
    }
}

// Request interrupt
request_interrupt :: proc(bus: ^Bus, bit: u8) {
    bus.if_ |= bit
}

// Update joypad state (called from input handling)
// buttons: bit 0=A, 1=B, 2=Select, 3=Start (active low)
// dpad: bit 0=Right, 1=Left, 2=Up, 3=Down (active low)
update_joypad :: proc(bus: ^Bus, buttons: u8, dpad: u8) {
    old_p1 := bus.joypad_buttons & bus.joypad_dpad
    bus.joypad_buttons = buttons | 0xF0
    bus.joypad_dpad = dpad | 0xF0
    new_p1 := bus.joypad_buttons & bus.joypad_dpad

    // Interrupt on high-to-low transition
    if (old_p1 & ~new_p1) != 0 {
        request_interrupt(bus, 0x10)  // Joypad interrupt
    }
}

// Tick timer (call every 4 cycles / 1 M-cycle)
tick_timer :: proc(bus: ^Bus, cycles: u8) {
    // DIV increments every 256 cycles
    bus.div_counter += u16(cycles)
    if bus.div_counter >= 256 {
        bus.div_counter -= 256
        bus.div += 1
    }

    // TIMA (if enabled)
    if (bus.tac & 0x04) != 0 {
        bus.timer_counter += u16(cycles)

        // Get timer frequency
        freq: u16
        switch bus.tac & 0x03 {
        case 0: freq = 1024  // 4096 Hz
        case 1: freq = 16    // 262144 Hz
        case 2: freq = 64    // 65536 Hz
        case 3: freq = 256   // 16384 Hz
        }

        for bus.timer_counter >= freq {
            bus.timer_counter -= freq
            bus.tima += 1
            if bus.tima == 0 {
                // Overflow
                bus.tima = bus.tma
                request_interrupt(bus, 0x04)  // Timer interrupt
            }
        }
    }
}
