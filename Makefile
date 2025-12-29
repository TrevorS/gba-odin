.PHONY: build run clean debug test

build:
	odin build src -out:build/gba-odin

run: build
	./build/gba-odin

debug:
	odin build src -out:build/gba-odin -debug

clean:
	rm -rf build/

test:
	odin test src -out:build/gba-odin-test
