---
name: odin-install
description: |
  Install and configure the Odin programming language. Use when:
  - Setting up Odin on a new machine
  - Updating Odin to latest version
  - Configuring Odin language server (ols)
---

# Odin Installation

## Quick Install (Linux)

```bash
# Download latest release
curl -L "https://github.com/odin-lang/Odin/releases/latest/download/odin-linux-amd64-$(curl -sL https://api.github.com/repos/odin-lang/Odin/releases/latest | grep tag_name | cut -d'"' -f4).tar.gz" -o /tmp/odin.tar.gz

# Or find latest directly:
LATEST=$(curl -sL https://api.github.com/repos/odin-lang/Odin/releases/latest | grep -o '"browser_download_url": "[^"]*linux[^"]*amd64[^"]*"' | head -1 | cut -d'"' -f4)
curl -L "$LATEST" -o /tmp/odin.tar.gz

# Extract to /opt
sudo tar -xzf /tmp/odin.tar.gz -C /opt/

# Link to PATH
sudo ln -sf /opt/odin-*/odin /usr/local/bin/odin

# Verify
odin version
```

## Prerequisites

### Linux (Debian/Ubuntu)

```bash
# Odin uses libatomic from GCC
clang++ -v  # Check "Selected GCC installation" version
sudo apt install libstdc++-12-dev  # or version 14

# For SDL2 (vendor library)
sudo apt install libsdl2-dev
```

### macOS

```bash
# Using Homebrew
brew install odin
brew install sdl2  # For SDL2 projects
```

## From Source

```bash
# Install LLVM (14, 17, 18, 19, 20, or 21)
sudo apt install llvm-17 clang-17 lld-17

# Clone and build
git clone https://github.com/odin-lang/Odin
cd Odin
make release-native

# Add to PATH
export PATH="$PWD:$PATH"
```

## Language Server (OLS)

```bash
# Download OLS
git clone https://github.com/DanielGaworworski/ols
cd ols
odin build . -out:ols

# Install
sudo mv ols /usr/local/bin/

# Configure (ols.json in project root)
{
    "$schema": "https://raw.githubusercontent.com/DanielGaworski/ols/master/misc/ols.schema.json",
    "collections": [
        { "name": "core", "path": "/opt/odin-*/core" },
        { "name": "vendor", "path": "/opt/odin-*/vendor" }
    ],
    "enable_semantic_tokens": true,
    "enable_hover": true,
    "enable_snippets": true
}
```

## Project Setup

```bash
# Create new project
mkdir my-project && cd my-project
mkdir -p src build

# Create main file
cat > src/main.odin << 'EOF'
package main

import "core:fmt"

main :: proc() {
    fmt.println("Hello, Odin!")
}
EOF

# Create ols.json for language server
cat > ols.json << 'EOF'
{
    "$schema": "https://raw.githubusercontent.com/DanielGaworski/ols/master/misc/ols.schema.json",
    "collections": [
        { "name": "core", "path": "ODIN_ROOT/core" },
        { "name": "vendor", "path": "ODIN_ROOT/vendor" }
    ]
}
EOF

# Create Makefile
cat > Makefile << 'EOF'
.PHONY: build run clean debug test

build:
	odin build src -out:build/app

run: build
	./build/app

debug:
	odin build src -out:build/app -debug

clean:
	rm -rf build/

test:
	odin test src -out:build/test
EOF

# Create .gitignore
cat >> .gitignore << 'EOF'
build/
*.o
*.obj
EOF

# Build and run
make run
```

## Verify Installation

```bash
# Check version
odin version

# Check LLVM backend
odin report

# Run hello world
odin run -file:src/main.odin
```

## Update Odin

```bash
# Remove old version
sudo rm -rf /opt/odin-*

# Download and install latest (repeat install steps)
LATEST=$(curl -sL https://api.github.com/repos/odin-lang/Odin/releases/latest | grep -o '"browser_download_url": "[^"]*linux[^"]*amd64[^"]*"' | head -1 | cut -d'"' -f4)
curl -L "$LATEST" -o /tmp/odin.tar.gz
sudo tar -xzf /tmp/odin.tar.gz -C /opt/
sudo ln -sf /opt/odin-*/odin /usr/local/bin/odin

odin version
```

## Troubleshooting

### "atomic.h not found"
```bash
sudo apt install libstdc++-12-dev
# or libstdc++-14-dev depending on clang version
```

### LLVM version mismatch
```bash
# Check supported versions
odin report

# Set explicit LLVM
LLVM_CONFIG=/usr/bin/llvm-config-17 make release-native
```

### SDL2 not found
```bash
sudo apt install libsdl2-dev
# Or on macOS: brew install sdl2
```
