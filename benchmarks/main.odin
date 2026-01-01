package benchmarks

import "core:fmt"
import "core:time"
import "base:runtime"
import "../src/cpu"
import gb_cpu "../src/gb/cpu"

// =============================================================================
// Emulator Benchmarks
// =============================================================================
// Run with: make bench
//
// Measures performance of critical hot paths in the emulator.
// All output is text-based for easy reading and analysis.

BENCH_ITERATIONS :: 100_000

main :: proc() {
    fmt.println("╔════════════════════════════════════════╗")
    fmt.println("║     GBA-Odin Emulator Benchmarks       ║")
    fmt.println("╚════════════════════════════════════════╝")
    fmt.println("")

    run_cpu_benchmarks()
    run_gb_cpu_benchmarks()

    fmt.println("┌────────────────────────────────────────┐")
    fmt.println("│ Profiling Example                      │")
    fmt.println("└────────────────────────────────────────┘")
    run_profiling_example()
}

// =============================================================================
// Simple Text Profiler
// =============================================================================
// Outputs hierarchical timing in a format easy to read and analyze.
// Use this instead of Spall when you need text output.

Profile_Entry :: struct {
    name:     string,
    duration: time.Duration,
    depth:    int,
}

Profile_Context :: struct {
    entries: [dynamic]Profile_Entry,
    depth:   int,
}

// Scoped profiler - automatically records when scope exits
@(deferred_out=_profile_scope_end)
PROFILE_SCOPE :: proc(ctx: ^Profile_Context, name: string) -> (^Profile_Context, string, time.Tick, int) {
    depth := ctx.depth
    ctx.depth += 1
    return ctx, name, time.tick_now(), depth
}

@(private)
_profile_scope_end :: proc(ctx: ^Profile_Context, name: string, start: time.Tick, depth: int) {
    elapsed := time.tick_since(start)
    ctx.depth -= 1
    append(&ctx.entries, Profile_Entry{
        name = name,
        duration = elapsed,
        depth = depth,
    })
}

profile_print :: proc(ctx: ^Profile_Context) {
    for entry in ctx.entries {
        // Indent based on depth
        for _ in 0 ..< entry.depth {
            fmt.print("  ")
        }
        fmt.printf("%s: %v\n", entry.name, entry.duration)
    }
}

// Example showing profiler usage
run_profiling_example :: proc() {
    ctx: Profile_Context

    // Simulate profiling some operations
    {
        PROFILE_SCOPE(&ctx, "Total CPU simulation")

        // Simulate some work
        {
            PROFILE_SCOPE(&ctx, "Fetch instruction")
            time.sleep(100 * time.Microsecond)
        }

        {
            PROFILE_SCOPE(&ctx, "Decode instruction")
            time.sleep(50 * time.Microsecond)
        }

        {
            PROFILE_SCOPE(&ctx, "Execute instruction")
            time.sleep(200 * time.Microsecond)
        }
    }

    profile_print(&ctx)
    fmt.println("")

    delete(ctx.entries)
}

// =============================================================================
// CPU Benchmarks
// =============================================================================

run_cpu_benchmarks :: proc() {
    fmt.println("┌────────────────────────────────────────┐")
    fmt.println("│ CPU Benchmarks                         │")
    fmt.println("└────────────────────────────────────────┘")

    // Condition evaluation
    {
        opts := time.Benchmark_Options{
            bench = proc(opts: ^time.Benchmark_Options, _: runtime.Allocator) -> time.Benchmark_Error {
                c: cpu.CPU
                cpu.cpu_init(&c)

                for _ in 0 ..< opts.rounds {
                    for cond in 0 ..< 14 {
                        _ = cpu.check_condition(&c, cpu.u4(cond))
                    }
                    opts.count += 14
                }
                return .Okay
            },
            rounds = BENCH_ITERATIONS,
        }
        time.benchmark(&opts)
        fmt.printf("  Condition eval:   %8.2f M ops/sec  (%v)\n",
            opts.rounds_per_second / 1_000_000, opts.duration)
    }

    // ARM instruction decode (LUT lookup)
    {
        opts := time.Benchmark_Options{
            bench = proc(opts: ^time.Benchmark_Options, _: runtime.Allocator) -> time.Benchmark_Error {
                opcodes := [?]u32{
                    0xE3A00001, // MOV r0, #1
                    0xE0810002, // ADD r0, r1, r2
                    0xE5910000, // LDR r0, [r1]
                    0xE92D4010, // PUSH {r4, lr}
                    0xEA000010, // B +0x40
                }

                for _ in 0 ..< opts.rounds {
                    for opcode in opcodes {
                        // ARM LUT is indexed by bits 27:20 (high 4) and bits 7:4 (low 4)
                        bits_27_20 := (opcode >> 20) & 0xFF
                        bits_7_4 := (opcode >> 4) & 0xF
                        idx := (bits_27_20 << 4) | bits_7_4
                        _ = cpu.arm_lut[idx]
                    }
                    opts.count += len(opcodes)
                }
                return .Okay
            },
            rounds = BENCH_ITERATIONS,
        }
        time.benchmark(&opts)
        fmt.printf("  ARM decode:       %8.2f M ops/sec  (%v)\n",
            opts.rounds_per_second / 1_000_000, opts.duration)
    }

    // THUMB instruction decode
    {
        opts := time.Benchmark_Options{
            bench = proc(opts: ^time.Benchmark_Options, _: runtime.Allocator) -> time.Benchmark_Error {
                opcodes := [?]u16{
                    0x2001, // MOVS r0, #1
                    0x1840, // ADDS r0, r0, r1
                    0x6800, // LDR r0, [r0]
                    0xB500, // PUSH {lr}
                    0xE000, // B +0
                }

                for _ in 0 ..< opts.rounds {
                    for opcode in opcodes {
                        upper := u8(opcode >> 8)
                        _ = cpu.thumb_lut[upper]
                    }
                    opts.count += len(opcodes)
                }
                return .Okay
            },
            rounds = BENCH_ITERATIONS,
        }
        time.benchmark(&opts)
        fmt.printf("  THUMB decode:     %8.2f M ops/sec  (%v)\n",
            opts.rounds_per_second / 1_000_000, opts.duration)
    }

    // Register access
    {
        opts := time.Benchmark_Options{
            bench = proc(opts: ^time.Benchmark_Options, _: runtime.Allocator) -> time.Benchmark_Error {
                c: cpu.CPU
                cpu.cpu_init(&c)

                for _ in 0 ..< opts.rounds {
                    for i in 0 ..< 15 {
                        cpu.set_reg(&c, cpu.u4(i), u32(i * 100))
                    }
                    for i in 0 ..< 15 {
                        _ = cpu.get_reg(&c, cpu.u4(i))
                    }
                    opts.count += 30
                }
                return .Okay
            },
            rounds = BENCH_ITERATIONS,
        }
        time.benchmark(&opts)
        fmt.printf("  Register access:  %8.2f M ops/sec  (%v)\n",
            opts.rounds_per_second / 1_000_000, opts.duration)
    }

    // Mode switching
    {
        opts := time.Benchmark_Options{
            bench = proc(opts: ^time.Benchmark_Options, _: runtime.Allocator) -> time.Benchmark_Error {
                c: cpu.CPU
                cpu.cpu_init(&c)

                modes := [?]cpu.Mode{.User, .FIQ, .IRQ, .Supervisor, .Abort, .Undefined, .System}

                for _ in 0 ..< opts.rounds {
                    for mode in modes {
                        cpu.set_mode(&c, mode)
                    }
                    opts.count += len(modes)
                }
                return .Okay
            },
            rounds = BENCH_ITERATIONS / 10,
        }
        time.benchmark(&opts)
        fmt.printf("  Mode switch:      %8.2f M ops/sec  (%v)\n",
            opts.rounds_per_second / 1_000_000, opts.duration)
    }

    fmt.println("")
}

// =============================================================================
// GB/GBC CPU Benchmarks
// =============================================================================

run_gb_cpu_benchmarks :: proc() {
    fmt.println("┌────────────────────────────────────────┐")
    fmt.println("│ GB/GBC CPU Benchmarks                  │")
    fmt.println("└────────────────────────────────────────┘")

    // Opcode table lookup
    {
        opts := time.Benchmark_Options{
            bench = proc(opts: ^time.Benchmark_Options, _: runtime.Allocator) -> time.Benchmark_Error {
                // Sample common opcodes
                opcodes := [?]u8{
                    0x00, // NOP
                    0x3E, // LD A,n
                    0xC3, // JP nn
                    0x20, // JR NZ,n
                    0x80, // ADD A,B
                    0xCB, // CB prefix
                    0xCD, // CALL nn
                    0xC9, // RET
                }

                for _ in 0 ..< opts.rounds {
                    for opcode in opcodes {
                        info := gb_cpu.get_opcode_info(opcode)
                        _ = info.cycles
                        _ = info.mnemonic
                    }
                    opts.count += len(opcodes)
                }
                return .Okay
            },
            rounds = BENCH_ITERATIONS,
        }
        time.benchmark(&opts)
        fmt.printf("  Opcode lookup:    %8.2f M ops/sec  (%v)\n",
            opts.rounds_per_second / 1_000_000, opts.duration)
    }

    // CB opcode table lookup
    {
        opts := time.Benchmark_Options{
            bench = proc(opts: ^time.Benchmark_Options, _: runtime.Allocator) -> time.Benchmark_Error {
                // Sample CB opcodes
                cb_opcodes := [?]u8{
                    0x00, // RLC B
                    0x11, // RL C
                    0x27, // SLA A
                    0x38, // SRL B
                    0x40, // BIT 0,B
                    0x80, // RES 0,B
                    0xC0, // SET 0,B
                    0x7F, // BIT 7,A
                }

                for _ in 0 ..< opts.rounds {
                    for opcode in cb_opcodes {
                        info := gb_cpu.get_cb_opcode_info(opcode)
                        _ = info.cycles
                        _ = info.mnemonic
                    }
                    opts.count += len(cb_opcodes)
                }
                return .Okay
            },
            rounds = BENCH_ITERATIONS,
        }
        time.benchmark(&opts)
        fmt.printf("  CB opcode lookup: %8.2f M ops/sec  (%v)\n",
            opts.rounds_per_second / 1_000_000, opts.duration)
    }

    // Register pair access
    {
        opts := time.Benchmark_Options{
            bench = proc(opts: ^time.Benchmark_Options, _: runtime.Allocator) -> time.Benchmark_Error {
                c: gb_cpu.CPU
                gb_cpu.cpu_init_dmg(&c)

                for _ in 0 ..< opts.rounds {
                    // Get pairs
                    _ = gb_cpu.get_af(&c)
                    _ = gb_cpu.get_bc(&c)
                    _ = gb_cpu.get_de(&c)
                    _ = gb_cpu.get_hl(&c)

                    // Set pairs
                    gb_cpu.set_af(&c, 0x1234)
                    gb_cpu.set_bc(&c, 0x5678)
                    gb_cpu.set_de(&c, 0x9ABC)
                    gb_cpu.set_hl(&c, 0xDEF0)

                    opts.count += 8
                }
                return .Okay
            },
            rounds = BENCH_ITERATIONS,
        }
        time.benchmark(&opts)
        fmt.printf("  Register pairs:   %8.2f M ops/sec  (%v)\n",
            opts.rounds_per_second / 1_000_000, opts.duration)
    }

    // ALU operations
    {
        opts := time.Benchmark_Options{
            bench = proc(opts: ^time.Benchmark_Options, _: runtime.Allocator) -> time.Benchmark_Error {
                c: gb_cpu.CPU
                gb_cpu.cpu_init_dmg(&c)

                for _ in 0 ..< opts.rounds {
                    c.a = 0x50

                    // INC/DEC
                    c.b = gb_cpu.inc8(&c, c.b)
                    c.c = gb_cpu.dec8(&c, c.c)

                    // ADD/SUB
                    gb_cpu.add_a(&c, 0x10, false)
                    gb_cpu.sub_a(&c, 0x05, false)

                    // ADC/SBC
                    gb_cpu.add_a(&c, 0x01, true)
                    gb_cpu.sub_a(&c, 0x01, true)

                    // Logic ops
                    gb_cpu.and_a(&c, 0xFF)
                    gb_cpu.or_a(&c, 0x0F)
                    gb_cpu.xor_a(&c, 0xAA)
                    gb_cpu.cp_a(&c, 0x50)

                    opts.count += 10
                }
                return .Okay
            },
            rounds = BENCH_ITERATIONS,
        }
        time.benchmark(&opts)
        fmt.printf("  ALU operations:   %8.2f M ops/sec  (%v)\n",
            opts.rounds_per_second / 1_000_000, opts.duration)
    }

    // Flag operations
    {
        opts := time.Benchmark_Options{
            bench = proc(opts: ^time.Benchmark_Options, _: runtime.Allocator) -> time.Benchmark_Error {
                c: gb_cpu.CPU
                gb_cpu.cpu_init_dmg(&c)

                for _ in 0 ..< opts.rounds {
                    // Get flags
                    _ = gb_cpu.get_flag_z(&c)
                    _ = gb_cpu.get_flag_n(&c)
                    _ = gb_cpu.get_flag_h(&c)
                    _ = gb_cpu.get_flag_c(&c)

                    // Set individual flags
                    gb_cpu.set_flag_z(&c, true)
                    gb_cpu.set_flag_n(&c, false)
                    gb_cpu.set_flag_h(&c, true)
                    gb_cpu.set_flag_c(&c, false)

                    // Set all flags at once
                    gb_cpu.set_flags(&c, true, false, true, false)

                    opts.count += 9
                }
                return .Okay
            },
            rounds = BENCH_ITERATIONS,
        }
        time.benchmark(&opts)
        fmt.printf("  Flag operations:  %8.2f M ops/sec  (%v)\n",
            opts.rounds_per_second / 1_000_000, opts.duration)
    }

    // 16-bit ADD HL
    {
        opts := time.Benchmark_Options{
            bench = proc(opts: ^time.Benchmark_Options, _: runtime.Allocator) -> time.Benchmark_Error {
                c: gb_cpu.CPU
                gb_cpu.cpu_init_dmg(&c)

                for _ in 0 ..< opts.rounds {
                    gb_cpu.set_hl(&c, 0x1000)
                    gb_cpu.add_hl(&c, gb_cpu.get_bc(&c))
                    gb_cpu.add_hl(&c, gb_cpu.get_de(&c))
                    gb_cpu.add_hl(&c, c.sp)

                    opts.count += 3
                }
                return .Okay
            },
            rounds = BENCH_ITERATIONS,
        }
        time.benchmark(&opts)
        fmt.printf("  ADD HL,rr:        %8.2f M ops/sec  (%v)\n",
            opts.rounds_per_second / 1_000_000, opts.duration)
    }

    // DAA operation
    {
        opts := time.Benchmark_Options{
            bench = proc(opts: ^time.Benchmark_Options, _: runtime.Allocator) -> time.Benchmark_Error {
                c: gb_cpu.CPU
                gb_cpu.cpu_init_dmg(&c)

                for _ in 0 ..< opts.rounds {
                    c.a = 0x99
                    gb_cpu.add_a(&c, 0x01, false)
                    gb_cpu.daa(&c)

                    c.a = 0x50
                    gb_cpu.sub_a(&c, 0x25, false)
                    gb_cpu.daa(&c)

                    opts.count += 2
                }
                return .Okay
            },
            rounds = BENCH_ITERATIONS,
        }
        time.benchmark(&opts)
        fmt.printf("  DAA operation:    %8.2f M ops/sec  (%v)\n",
            opts.rounds_per_second / 1_000_000, opts.duration)
    }

    fmt.println("")
}
