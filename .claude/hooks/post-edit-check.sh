#!/bin/bash
# post-edit-check.sh - Run odin check after editing Odin files
# Non-blocking: exits 1 for warnings (shown but doesn't stop workflow)

set -euo pipefail

# Read hook input from stdin
input=$(cat)

# Extract the file path from tool_input
# Edit tool sends: {"file_path": "...", "old_string": "...", "new_string": "..."}
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

# Skip if no file path or not an Odin file
if [[ -z "$file_path" ]] || [[ ! "$file_path" == *.odin ]]; then
    exit 0
fi

# Skip test files (they often have intentional edge cases)
if [[ "$file_path" == *_test.odin ]]; then
    exit 0
fi

# Get the package directory - for this project, use src/ as root
# This handles nested packages like src/cpu/, src/gb/ppu/, etc.
pkg_dir=$(dirname "$file_path")

# Run odin check on the package directory
check_output=$(odin check "$pkg_dir" 2>&1) || true

# Get just the filename for matching
file_basename=$(basename "$file_path")

# Check for errors mentioning our file
if echo "$check_output" | grep -q "$file_basename.*Error:\|Error:.*$file_basename"; then
    errors=$(echo "$check_output" | grep -B1 -A2 "$file_basename" | grep -A2 "Error:" | head -10)
    echo "⚠️  Odin check found issues in $file_path:" >&2
    echo "$errors" >&2
    exit 1  # Non-blocking error
fi

# Also check for any errors in the output (might be in other files due to our change)
if echo "$check_output" | grep -q "Error:"; then
    error_count=$(echo "$check_output" | grep -c "Error:" || echo "0")
    if [[ "$error_count" -gt 0 ]]; then
        echo "⚠️  Odin check found $error_count error(s) in package" >&2
        echo "$check_output" | grep -A2 "Error:" | head -6 >&2
        exit 1
    fi
fi

exit 0
