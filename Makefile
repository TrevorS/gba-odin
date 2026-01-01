# GBA-Odin Emulator Makefile
# ===========================

.PHONY: all build build-sdl run run-sdl clean debug debug-sdl test test-all \
        test-gb-cpu test-gb-ppu test-gb-bus test-gba-cpu test-gba-ppu \
        lint check check-warnings bench

# Default target
all: build

# =============================================================================
# Build targets
# =============================================================================

# Default: headless build (works everywhere, no SDL2 needed)
build:
	@mkdir -p build
	odin build src -out:build/gba-odin -define:HEADLESS_ONLY=true

# SDL2 build: requires SDL2 installed (brew install sdl2)
build-sdl:
	@mkdir -p build
	odin build src -out:build/gba-odin -define:HEADLESS_ONLY=false

run: build
	./build/gba-odin

# Run with SDL2 display
run-sdl: build-sdl
	./build/gba-odin

debug:
	@mkdir -p build
	odin build src -out:build/gba-odin -debug -define:HEADLESS_ONLY=true

debug-sdl:
	@mkdir -p build
	odin build src -out:build/gba-odin -debug -define:HEADLESS_ONLY=false

clean:
	rm -rf build/

# =============================================================================
# Test targets (163 tests total)
# =============================================================================

test: test-all

test-all: test-gb-cpu test-gb-ppu test-gb-bus test-gba-cpu test-gba-ppu
	@echo ""
	@echo "=== All 163 tests passed! ==="

# Game Boy tests (81 tests)
test-gb-cpu:
	@echo "=== GB CPU Tests (34) ==="
	@mkdir -p build
	@odin test src/gb/cpu -out:build/gb_cpu_test

test-gb-ppu:
	@echo "=== GB PPU Tests (17) ==="
	@mkdir -p build
	@odin test src/gb/ppu -out:build/gb_ppu_test

test-gb-bus:
	@echo "=== GB Bus Tests (30) ==="
	@mkdir -p build
	@odin test src/gb/bus -out:build/gb_bus_test

# GBA tests (82 tests)
test-gba-cpu:
	@echo "=== GBA CPU Tests (55) ==="
	@mkdir -p build
	@odin test src/cpu -out:build/gba_cpu_test

test-gba-ppu:
	@echo "=== GBA PPU Tests (27) ==="
	@mkdir -p build
	@odin test src/ppu -out:build/gba_ppu_test

# =============================================================================
# Style and lint checks
# =============================================================================

# Strict style check - enforces 1TBS brace style
lint:
	@echo "=== Style Check (-strict-style) ==="
	@odin check src -strict-style
	@echo "Style check passed!"

# Full vet check - unused vars, shadowing, etc.
check:
	@echo "=== Full Vet Check (-vet) ==="
	@odin check src -vet
	@echo "Vet check passed!"

# Show warnings without failing (for CI or incremental cleanup)
check-warnings:
	@echo "=== Warnings Check ==="
	@odin check src -vet-unused -vet-shadowing 2>&1 || true

# =============================================================================
# Benchmarks
# =============================================================================

# Run performance benchmarks with optimizations
bench:
	@mkdir -p build
	@echo "=== Building benchmarks with -o:speed ==="
	@odin build benchmarks -out:build/bench -o:speed
	@echo ""
	@./build/bench

# =============================================================================
# Help
# =============================================================================

help:
	@echo "GBA-Odin Emulator"
	@echo ""
	@echo "Build:"
	@echo "  make build      - Build headless (no SDL2 needed)"
	@echo "  make build-sdl  - Build with SDL2 display"
	@echo "  make run        - Build and run (headless)"
	@echo "  make run-sdl    - Build and run with display"
	@echo "  make debug      - Build with debug symbols (headless)"
	@echo "  make debug-sdl  - Build with debug symbols + SDL2"
	@echo "  make clean      - Remove build artifacts"
	@echo ""
	@echo "Test:"
	@echo "  make test     - Run all 163 unit tests"
	@echo "  make test-gb-cpu   - GB CPU tests (34)"
	@echo "  make test-gb-ppu   - GB PPU tests (17)"
	@echo "  make test-gb-bus   - GB Bus tests (30)"
	@echo "  make test-gba-cpu  - GBA CPU tests (55)"
	@echo "  make test-gba-ppu  - GBA PPU tests (27)"
	@echo ""
	@echo "Lint:"
	@echo "  make lint           - Style check (1TBS brace style)"
	@echo "  make check          - Full vet (unused vars, shadowing)"
	@echo "  make check-warnings - Show warnings without failing"
	@echo ""
	@echo "Benchmark:"
	@echo "  make bench          - Run performance benchmarks"
