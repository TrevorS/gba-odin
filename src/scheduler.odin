package main

MAX_EVENTS :: 32

Event_Type :: enum u8 {
    // PPU events
    HBlank_Start,
    HBlank_End,
    VBlank_Start,
    VBlank_End,

    // Timer events
    Timer0_Overflow,
    Timer1_Overflow,
    Timer2_Overflow,
    Timer3_Overflow,

    // DMA events (Phase 4)
    DMA0,
    DMA1,
    DMA2,
    DMA3,

    // APU events (Phase 6)
    APU_Sample,
    APU_Sequencer,

    // System events
    Halt_Check,
    Frame_Complete,
}

Event :: struct {
    timestamp: u64,
    type:      Event_Type,
    param:     u32,
}

Scheduler :: struct {
    events:         [MAX_EVENTS]Event,
    event_count:    int,
    current_cycles: u64,
}

// Initialize scheduler
scheduler_init :: proc(scheduler: ^Scheduler) {
    scheduler.event_count = 0
    scheduler.current_cycles = 0
}

// Schedule event at current_time + delay
scheduler_schedule :: proc(scheduler: ^Scheduler, type: Event_Type, delay: u64, param: u32 = 0) {
    scheduler_schedule_absolute(scheduler, type, scheduler.current_cycles + delay, param)
}

// Schedule event at absolute timestamp
scheduler_schedule_absolute :: proc(scheduler: ^Scheduler, type: Event_Type, timestamp: u64, param: u32 = 0) {
    // First, remove any existing event of this type
    scheduler_deschedule(scheduler, type)

    // Ensure we have room
    if scheduler.event_count >= MAX_EVENTS {
        return // Should not happen in normal operation
    }

    // Find insertion point to maintain sorted order
    insert_pos := scheduler.event_count
    for i := 0; i < scheduler.event_count; i += 1 {
        if timestamp < scheduler.events[i].timestamp {
            insert_pos = i
            break
        }
    }

    // Shift events to make room
    for i := scheduler.event_count; i > insert_pos; i -= 1 {
        scheduler.events[i] = scheduler.events[i - 1]
    }

    // Insert new event
    scheduler.events[insert_pos] = Event{
        timestamp = timestamp,
        type      = type,
        param     = param,
    }
    scheduler.event_count += 1
}

// Remove all events of given type
scheduler_deschedule :: proc(scheduler: ^Scheduler, type: Event_Type) {
    write_idx := 0
    for i := 0; i < scheduler.event_count; i += 1 {
        if scheduler.events[i].type != type {
            if write_idx != i {
                scheduler.events[write_idx] = scheduler.events[i]
            }
            write_idx += 1
        }
    }
    scheduler.event_count = write_idx
}

// Peek at next event without removing
scheduler_peek :: proc(scheduler: ^Scheduler) -> ^Event {
    if scheduler.event_count == 0 {
        return nil
    }
    return &scheduler.events[0]
}

// Remove and return next event
scheduler_pop :: proc(scheduler: ^Scheduler) -> (event: Event, ok: bool) {
    if scheduler.event_count == 0 {
        return {}, false
    }

    event = scheduler.events[0]

    // Shift remaining events
    for i := 0; i < scheduler.event_count - 1; i += 1 {
        scheduler.events[i] = scheduler.events[i + 1]
    }
    scheduler.event_count -= 1

    return event, true
}

// Reschedule existing event with new delay from current time
scheduler_reschedule :: proc(scheduler: ^Scheduler, type: Event_Type, new_delay: u64) {
    // Find and update the event
    for i := 0; i < scheduler.event_count; i += 1 {
        if scheduler.events[i].type == type {
            param := scheduler.events[i].param
            scheduler_deschedule(scheduler, type)
            scheduler_schedule(scheduler, type, new_delay, param)
            return
        }
    }
}

// Get time until next event
scheduler_time_until_next :: proc(scheduler: ^Scheduler) -> u64 {
    if scheduler.event_count == 0 {
        return max(u64)
    }
    if scheduler.events[0].timestamp <= scheduler.current_cycles {
        return 0
    }
    return scheduler.events[0].timestamp - scheduler.current_cycles
}

// Advance scheduler time
scheduler_add_cycles :: proc(scheduler: ^Scheduler, cycles: u64) {
    scheduler.current_cycles += cycles
}

// Schedule initial events for system reset
scheduler_reset :: proc(scheduler: ^Scheduler) {
    scheduler.event_count = 0
    scheduler.current_cycles = 0

    // Schedule initial PPU events
    scheduler_schedule(scheduler, .HBlank_Start, HBLANK_START_CYCLE)
    scheduler_schedule(scheduler, .Frame_Complete, CYCLES_PER_FRAME)
}
