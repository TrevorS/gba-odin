#!/bin/bash
set -euo pipefail

# Only run on Claude Code web (remote environment)
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

# Configure git identity for commits made on Claude Code web
git config --global user.name "TrevorS"
git config --global user.email "trevor@strieber.org"

echo "Installing Odin and OLS for Claude Code on the web..."

# Track the Odin directory for later use
ODIN_DIR=""

# Check if Odin is already installed
if command -v odin &> /dev/null; then
  echo "Odin already installed: $(odin version)"
  ODIN_DIR=$(ls /opt/ | grep odin | head -1)
else
  echo "Installing Odin..."

  # Get latest release URL
  ODIN_URL=$(curl -sL https://api.github.com/repos/odin-lang/Odin/releases/latest | grep -o '"browser_download_url": "[^"]*linux[^"]*amd64[^"]*"' | head -1 | cut -d'"' -f4)

  # Download and extract
  curl -L "$ODIN_URL" -o /tmp/odin.tar.gz
  sudo tar -xzf /tmp/odin.tar.gz -C /opt/

  # Find extracted directory and create symlink
  ODIN_DIR=$(ls /opt/ | grep odin | head -1)
  sudo ln -sf "/opt/$ODIN_DIR/odin" /usr/local/bin/odin

  echo "Odin installed: $(odin version)"
fi

# Check if OLS is already installed
if command -v ols &> /dev/null; then
  echo "OLS already installed"
else
  echo "Installing OLS..."

  # Clone and build OLS
  cd /tmp
  git clone --depth 1 https://github.com/DanielGavin/ols.git
  cd /tmp/ols
  ./build.sh
  ./odinfmt.sh

  # Install binaries
  sudo cp /tmp/ols/ols /usr/local/bin/
  sudo cp /tmp/ols/odinfmt /usr/local/bin/

  echo "OLS and odinfmt installed"
fi

# Export ODIN_ROOT for the session (if CLAUDE_ENV_FILE is available)
if [ -n "${CLAUDE_ENV_FILE:-}" ] && [ -n "$ODIN_DIR" ]; then
  echo "export ODIN_ROOT=/opt/$ODIN_DIR" >> "$CLAUDE_ENV_FILE"
fi

echo "Odin development environment ready!"
