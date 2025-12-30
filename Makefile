.PHONY: build run clean debug test test-all test-gb-cpu test-gb-ppu test-gb-bus test-gba-cpu test-gba-ppu lint check check-warnings

build:
	odin build src -out:build/gba-odin

run: build
	./build/gba-odin

debug:
	odin build src -out:build/gba-odin -debug

clean:
	rm -rf build/

# Run all unit tests
test: test-all

test-all: test-gb-cpu test-gb-ppu test-gb-bus test-gba-cpu test-gba-ppu
	@echo "All tests completed successfully!"

test-gb-cpu:
	@echo "=== GB CPU Tests ==="
	@odin test src/gb/cpu -out:build/gb_cpu_test

test-gb-ppu:
	@echo "=== GB PPU Tests ==="
	@odin test src/gb/ppu -out:build/gb_ppu_test

test-gb-bus:
	@echo "=== GB Bus Tests ==="
	@odin test src/gb/bus -out:build/gb_bus_test

test-gba-cpu:
	@echo "=== GBA CPU Tests ==="
	@odin test src/cpu -out:build/gba_cpu_test

test-gba-ppu:
	@echo "=== GBA PPU Tests ==="
	@odin test src/ppu -out:build/gba_ppu_test

# Style and lint checks
lint:
	@echo "=== Style Check ==="
	@odin check src -strict-style
	@echo "Style check passed!"

check:
	@echo "=== Full Vet Check ==="
	@odin check src -vet
	@echo "Vet check passed!"

check-warnings:
	@echo "=== Warnings Check ==="
	@odin check src -vet-unused -vet-shadowing 2>&1 || true
