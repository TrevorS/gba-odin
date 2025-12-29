package bus

// I/O Register addresses
IO_DISPCNT :: 0x000
IO_GREENSWP :: 0x002
IO_DISPSTAT :: 0x004
IO_VCOUNT :: 0x006
IO_BG0CNT :: 0x008
IO_BG1CNT :: 0x00A
IO_BG2CNT :: 0x00C
IO_BG3CNT :: 0x00E
IO_BG0HOFS :: 0x010
IO_BG0VOFS :: 0x012
IO_BG1HOFS :: 0x014
IO_BG1VOFS :: 0x016
IO_BG2HOFS :: 0x018
IO_BG2VOFS :: 0x01A
IO_BG3HOFS :: 0x01C
IO_BG3VOFS :: 0x01E
IO_BG2PA :: 0x020
IO_BG2PB :: 0x022
IO_BG2PC :: 0x024
IO_BG2PD :: 0x026
IO_BG2X :: 0x028
IO_BG2Y :: 0x02C
IO_BG3PA :: 0x030
IO_BG3PB :: 0x032
IO_BG3PC :: 0x034
IO_BG3PD :: 0x036
IO_BG3X :: 0x038
IO_BG3Y :: 0x03C
IO_WIN0H :: 0x040
IO_WIN1H :: 0x042
IO_WIN0V :: 0x044
IO_WIN1V :: 0x046
IO_WININ :: 0x048
IO_WINOUT :: 0x04A
IO_MOSAIC :: 0x04C
IO_BLDCNT :: 0x050
IO_BLDALPHA :: 0x052
IO_BLDY :: 0x054

IO_SOUND1CNT_L :: 0x060
IO_SOUND1CNT_H :: 0x062
IO_SOUND1CNT_X :: 0x064
IO_SOUND2CNT_L :: 0x068
IO_SOUND2CNT_H :: 0x06C
IO_SOUND3CNT_L :: 0x070
IO_SOUND3CNT_H :: 0x072
IO_SOUND3CNT_X :: 0x074
IO_SOUND4CNT_L :: 0x078
IO_SOUND4CNT_H :: 0x07C
IO_SOUNDCNT_L :: 0x080
IO_SOUNDCNT_H :: 0x082
IO_SOUNDCNT_X :: 0x084
IO_SOUNDBIAS :: 0x088
IO_WAVE_RAM :: 0x090 // 0x090-0x09F

IO_FIFO_A :: 0x0A0
IO_FIFO_B :: 0x0A4

IO_DMA0SAD :: 0x0B0
IO_DMA0DAD :: 0x0B4
IO_DMA0CNT_L :: 0x0B8
IO_DMA0CNT_H :: 0x0BA
IO_DMA1SAD :: 0x0BC
IO_DMA1DAD :: 0x0C0
IO_DMA1CNT_L :: 0x0C4
IO_DMA1CNT_H :: 0x0C6
IO_DMA2SAD :: 0x0C8
IO_DMA2DAD :: 0x0CC
IO_DMA2CNT_L :: 0x0D0
IO_DMA2CNT_H :: 0x0D2
IO_DMA3SAD :: 0x0D4
IO_DMA3DAD :: 0x0D8
IO_DMA3CNT_L :: 0x0DC
IO_DMA3CNT_H :: 0x0DE

IO_TM0CNT_L :: 0x100
IO_TM0CNT_H :: 0x102
IO_TM1CNT_L :: 0x104
IO_TM1CNT_H :: 0x106
IO_TM2CNT_L :: 0x108
IO_TM2CNT_H :: 0x10A
IO_TM3CNT_L :: 0x10C
IO_TM3CNT_H :: 0x10E

IO_SIODATA32 :: 0x120
IO_SIOMULTI0 :: 0x120
IO_SIOMULTI1 :: 0x122
IO_SIOMULTI2 :: 0x124
IO_SIOMULTI3 :: 0x126
IO_SIOCNT :: 0x128
IO_SIOMLT_SEND :: 0x12A
IO_SIODATA8 :: 0x12A

IO_KEYINPUT :: 0x130
IO_KEYCNT :: 0x132

IO_RCNT :: 0x134
IO_JOYCNT :: 0x140
IO_JOY_RECV :: 0x150
IO_JOY_TRANS :: 0x154
IO_JOYSTAT :: 0x158

IO_IE :: 0x200
IO_IF :: 0x202
IO_WAITCNT :: 0x204
IO_IME :: 0x208
IO_POSTFLG :: 0x300
IO_HALTCNT :: 0x301

// Read 8-bit I/O register
read_io8 :: proc(bus: ^Bus, addr: u32) -> (value: u8, cycles: u8) {
    offset := addr & 0x3FF

    switch offset {
    case IO_IE:
        value = u8(bus.ie)
    case IO_IE + 1:
        value = u8(bus.ie >> 8)
    case IO_IF:
        value = u8(bus.if_)
    case IO_IF + 1:
        value = u8(bus.if_ >> 8)
    case IO_WAITCNT:
        value = u8(bus.waitcnt)
    case IO_WAITCNT + 1:
        value = u8(bus.waitcnt >> 8)
    case IO_IME:
        value = u8(bus.ime)
    case IO_IME + 1:
        value = u8(bus.ime >> 8)
    case IO_POSTFLG:
        value = bus.postflg
    case IO_KEYINPUT, IO_KEYINPUT + 1:
        // Return all buttons released (0x3FF)
        if offset == IO_KEYINPUT {
            value = 0xFF
        } else {
            value = 0x03
        }
    case:
        // Unimplemented register
        value = 0
    }

    cycles = 1
    return
}

// Read 16-bit I/O register
read_io16 :: proc(bus: ^Bus, addr: u32) -> (value: u16, cycles: u8) {
    offset := addr & 0x3FE // Force halfword align

    switch offset {
    case IO_IE:
        value = bus.ie
    case IO_IF:
        value = bus.if_
    case IO_WAITCNT:
        value = bus.waitcnt
    case IO_IME:
        value = bus.ime
    case IO_KEYINPUT:
        // Return all buttons released (active low)
        value = 0x03FF
    case IO_KEYCNT:
        value = 0 // Keypad IRQ control (stub)
    case IO_DISPSTAT:
        value = 0 // Display status (stub for Phase 1)
    case IO_VCOUNT:
        value = 0 // Current scanline (stub for Phase 1)
    case:
        value = 0
    }

    cycles = 1
    return
}

// Read 32-bit I/O register
read_io32 :: proc(bus: ^Bus, addr: u32) -> (value: u32, cycles: u8) {
    offset := addr & 0x3FC

    switch offset {
    case IO_IE:
        value = u32(bus.ie) | (u32(bus.if_) << 16)
    case IO_WAITCNT:
        value = u32(bus.waitcnt)
    case IO_IME:
        value = u32(bus.ime)
    case IO_KEYINPUT:
        value = 0x03FF // All buttons released
    case:
        // Read as two 16-bit accesses
        lo, _ := read_io16(bus, addr)
        hi, _ := read_io16(bus, addr + 2)
        value = u32(lo) | (u32(hi) << 16)
    }

    cycles = 1
    return
}

// Write 8-bit I/O register
write_io8 :: proc(bus: ^Bus, addr: u32, value: u8) -> (cycles: u8) {
    offset := addr & 0x3FF

    switch offset {
    case IO_IE:
        bus.ie = (bus.ie & 0xFF00) | u16(value)
    case IO_IE + 1:
        bus.ie = (bus.ie & 0x00FF) | (u16(value) << 8)
    case IO_IF:
        // Write 1 to clear
        bus.if_ &= ~u16(value)
    case IO_IF + 1:
        bus.if_ &= ~(u16(value) << 8)
    case IO_WAITCNT:
        bus.waitcnt = (bus.waitcnt & 0xFF00) | u16(value)
    case IO_WAITCNT + 1:
        bus.waitcnt = (bus.waitcnt & 0x00FF) | (u16(value) << 8)
    case IO_IME:
        bus.ime = (bus.ime & 0xFF00) | u16(value)
    case IO_IME + 1:
        bus.ime = (bus.ime & 0x00FF) | (u16(value) << 8)
    case IO_POSTFLG:
        bus.postflg = value
    case IO_HALTCNT:
        // Writing any value halts the CPU
        bus.halt_requested = true
    }

    cycles = 1
    return
}

// Write 16-bit I/O register
write_io16 :: proc(bus: ^Bus, addr: u32, value: u16) -> (cycles: u8) {
    offset := addr & 0x3FE

    switch offset {
    case IO_IE:
        bus.ie = value
    case IO_IF:
        // Write 1 to clear
        bus.if_ &= ~value
    case IO_WAITCNT:
        bus.waitcnt = value
    case IO_IME:
        bus.ime = value & 1
    case IO_HALTCNT:
        bus.halt_requested = true
    case:
        // Stub for PPU/APU/DMA/Timer registers
        // Just store in I/O memory for now
        if offset < 0x400 && bus.io != nil {
            bus.io[offset] = u8(value)
            bus.io[offset + 1] = u8(value >> 8)
        }
    }

    cycles = 1
    return
}

// Write 32-bit I/O register
write_io32 :: proc(bus: ^Bus, addr: u32, value: u32) -> (cycles: u8) {
    offset := addr & 0x3FC

    switch offset {
    case IO_IE:
        bus.ie = u16(value)
        // IF is at +2, write 1 to clear
        bus.if_ &= ~u16(value >> 16)
    case IO_WAITCNT:
        bus.waitcnt = u16(value)
    case IO_IME:
        bus.ime = u16(value) & 1
    case:
        // Write as two 16-bit accesses
        write_io16(bus, addr, u16(value))
        write_io16(bus, addr + 2, u16(value >> 16))
    }

    cycles = 1
    return
}

// Request interrupt
bus_request_interrupt :: proc(bus: ^Bus, interrupt: u16) {
    bus.if_ |= interrupt
}

// Check if interrupt is pending
bus_interrupt_pending :: proc(bus: ^Bus) -> bool {
    return (bus.ime & 1) != 0 && (bus.ie & bus.if_) != 0
}
