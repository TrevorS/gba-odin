#!/bin/bash
# GBA Emulator Test Runner
# Downloads test ROMs and runs the emulator against them

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ROM_DIR="$PROJECT_DIR/roms/tests"
SCREENSHOT_DIR="$PROJECT_DIR/test_results"
BIOS_PATH="$PROJECT_DIR/bios/gba_bios.bin"
EMU_PATH="$PROJECT_DIR/build/gba-odin"
SKIP_BIOS=false

# Check if BIOS exists, otherwise use skip-bios mode
if [ ! -f "$BIOS_PATH" ]; then
    SKIP_BIOS=true
fi

# Test ROM sources
JSMOLKA_REPO="https://raw.githubusercontent.com/jsmolka/gba-tests/master"
MGBA_SUITE="https://github.com/mgba-emu/suite/releases/download/v0.3.0"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Create directories
mkdir -p "$ROM_DIR"
mkdir -p "$SCREENSHOT_DIR"

echo "=== GBA Emulator Test Suite ==="
echo ""

# Check prerequisites
if [ "$SKIP_BIOS" = true ]; then
    echo -e "${YELLOW}Note: BIOS not found, using --skip-bios mode${NC}"
fi

if [ ! -f "$EMU_PATH" ]; then
    echo -e "${YELLOW}Building emulator...${NC}"
    cd "$PROJECT_DIR" && make build
fi

# Download function with retry
download_file() {
    local url="$1"
    local output="$2"
    local name="$3"

    if [ -f "$output" ]; then
        echo "  [cached] $name"
        return 0
    fi

    echo "  [downloading] $name"
    if curl -sL --retry 3 --retry-delay 2 -o "$output" "$url"; then
        return 0
    else
        echo -e "${RED}  [failed] $name${NC}"
        return 1
    fi
}

# Download jsmolka's gba-tests
echo "Downloading jsmolka's gba-tests..."
JSMOLKA_TESTS=(
    "arm/arm.gba"
    "thumb/thumb.gba"
    "memory/memory.gba"
    "nes/nes.gba"
    "bios/bios.gba"
    "ppu/hello.gba"
    "ppu/stripes.gba"
    "ppu/shades.gba"
    "save/none.gba"
    "save/sram.gba"
    "save/flash64.gba"
    "save/flash128.gba"
)

for test in "${JSMOLKA_TESTS[@]}"; do
    name=$(basename "$test")
    dir=$(dirname "$test")
    mkdir -p "$ROM_DIR/jsmolka/$dir"
    download_file "$JSMOLKA_REPO/$test" "$ROM_DIR/jsmolka/$test" "jsmolka/$test" || true
done

# Download mGBA test suite
echo ""
echo "Downloading mGBA test suite..."
if [ ! -f "$ROM_DIR/mgba/suite.gba" ]; then
    mkdir -p "$ROM_DIR/mgba"
    download_file "$MGBA_SUITE/suite.gba" "$ROM_DIR/mgba/suite.gba" "mgba/suite.gba" || true
fi

# Run tests function
run_test() {
    local rom_path="$1"
    local test_name="$2"
    local frames="${3:-60}"

    local screenshot_name=$(echo "$test_name" | tr '/' '_')
    local screenshot_path="$SCREENSHOT_DIR/${screenshot_name}.png"

    if [ ! -f "$rom_path" ]; then
        echo -e "  ${YELLOW}[skip]${NC} $test_name (ROM not found)"
        return 1
    fi

    echo -n "  [running] $test_name... "

    # Build command with optional BIOS
    local cmd="$EMU_PATH $rom_path --headless --frames $frames --screenshot $screenshot_path"
    if [ "$SKIP_BIOS" = true ]; then
        cmd="$cmd --skip-bios"
    else
        cmd="$cmd --bios $BIOS_PATH"
    fi

    # Run emulator and capture output
    local output
    if output=$($cmd 2>&1); then
        echo -e "${GREEN}[done]${NC} -> $screenshot_name.png"
        return 0
    else
        echo -e "${RED}[error]${NC}"
        echo "$output" | tail -5
        return 1
    fi
}

# Run all tests
echo ""
echo "=== Running Tests ==="
echo ""

PASSED=0
FAILED=0
SKIPPED=0

# jsmolka tests
echo "jsmolka's gba-tests:"
for test in "${JSMOLKA_TESTS[@]}"; do
    rom_path="$ROM_DIR/jsmolka/$test"
    test_name="jsmolka/$(basename "$test" .gba)"

    # Use more frames for complex tests
    frames=60
    case "$test" in
        *memory*|*bios*) frames=120 ;;
        *ppu*) frames=30 ;;
    esac

    if run_test "$rom_path" "$test_name" "$frames"; then
        ((PASSED++))
    elif [ -f "$rom_path" ]; then
        ((FAILED++))
    else
        ((SKIPPED++))
    fi
done

# mGBA suite
echo ""
echo "mGBA test suite:"
if run_test "$ROM_DIR/mgba/suite.gba" "mgba/suite" 300; then
    ((PASSED++))
elif [ -f "$ROM_DIR/mgba/suite.gba" ]; then
    ((FAILED++))
else
    ((SKIPPED++))
fi

# Also run the original test ROMs if present
echo ""
echo "Original test ROMs:"
if [ -f "$PROJECT_DIR/roms/arm.gba" ]; then
    if run_test "$PROJECT_DIR/roms/arm.gba" "original/arm" 30; then
        ((PASSED++))
    else
        ((FAILED++))
    fi
fi

if [ -f "$PROJECT_DIR/roms/thumb.gba" ]; then
    if run_test "$PROJECT_DIR/roms/thumb.gba" "original/thumb" 30; then
        ((PASSED++))
    else
        ((FAILED++))
    fi
fi

# Summary
echo ""
echo "=== Test Summary ==="
echo -e "  ${GREEN}Passed:${NC}  $PASSED"
echo -e "  ${RED}Failed:${NC}  $FAILED"
echo -e "  ${YELLOW}Skipped:${NC} $SKIPPED"
echo ""
echo "Screenshots saved to: $SCREENSHOT_DIR"
echo ""

# List screenshots
echo "=== Screenshots ==="
ls -la "$SCREENSHOT_DIR"/*.png 2>/dev/null | awk '{print "  " $NF}' || echo "  (none)"
echo ""

# Generate HTML report
REPORT_PATH="$SCREENSHOT_DIR/report.html"
cat > "$REPORT_PATH" << 'HTMLEOF'
<!DOCTYPE html>
<html>
<head>
    <title>GBA Emulator Test Results</title>
    <style>
        body { font-family: sans-serif; margin: 20px; background: #1a1a2e; color: #eee; }
        h1 { color: #00d4ff; }
        .test-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 20px; }
        .test-card { background: #16213e; border-radius: 8px; padding: 15px; }
        .test-card h3 { margin: 0 0 10px 0; color: #00d4ff; font-size: 14px; }
        .test-card img { width: 100%; image-rendering: pixelated; border-radius: 4px; }
        .timestamp { color: #666; font-size: 12px; margin-top: 20px; }
    </style>
</head>
<body>
    <h1>GBA Emulator Test Results</h1>
    <div class="test-grid">
HTMLEOF

# Add each screenshot to the report
for png in "$SCREENSHOT_DIR"/*.png; do
    if [ -f "$png" ]; then
        name=$(basename "$png" .png)
        echo "        <div class=\"test-card\">" >> "$REPORT_PATH"
        echo "            <h3>$name</h3>" >> "$REPORT_PATH"
        echo "            <img src=\"$(basename "$png")\" alt=\"$name\">" >> "$REPORT_PATH"
        echo "        </div>" >> "$REPORT_PATH"
    fi
done

cat >> "$REPORT_PATH" << 'HTMLEOF'
    </div>
    <p class="timestamp">Generated: TIMESTAMP</p>
</body>
</html>
HTMLEOF

# Replace timestamp
sed -i "s/TIMESTAMP/$(date)/" "$REPORT_PATH"

echo "HTML report: $REPORT_PATH"
