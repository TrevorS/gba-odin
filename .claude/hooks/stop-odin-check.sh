#!/bin/bash
# stop-odin-check.sh - Run project-wide odin check and format when Claude finishes
# Only runs if Odin files were modified during the session
# Non-blocking: exits 1 to show summary without stopping

set -euo pipefail

# Get project directory
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# Check if we're in the gba-odin project
if [[ ! -f "$PROJECT_DIR/src/main.odin" ]]; then
    exit 0
fi

# Find Odin files modified recently (last 5 minutes)
# This avoids running checks when no code was changed
# Note: Using while loop instead of mapfile for bash 3.x compatibility (macOS)
recent_files=()
while IFS= read -r -d '' file; do
    recent_files+=("$file")
done < <(find "$PROJECT_DIR/src" -name "*.odin" -mmin -5 -print0 2>/dev/null)

if [[ ${#recent_files[@]} -eq 0 ]]; then
    exit 0
fi

had_issues=false

# Auto-format modified files
if command -v odinfmt &> /dev/null; then
    format_count=0
    for file in "${recent_files[@]}"; do
        # Check if file needs formatting (compare before/after)
        original=$(cat "$file")
        formatted=$(odinfmt "$file" 2>/dev/null) || continue

        if [[ "$original" != "$formatted" ]]; then
            odinfmt -w "$file" 2>/dev/null || true
            ((format_count++)) || true
        fi
    done

    if [[ "$format_count" -gt 0 ]]; then
        echo "" >&2
        echo "✨ Auto-formatted $format_count file(s)" >&2
    fi
fi

# Run odin check on the whole project
check_output=$(odin check "$PROJECT_DIR/src" 2>&1) || true

# Count errors (handle grep returning empty)
error_count=0
if echo "$check_output" | grep -q "Error:"; then
    error_count=$(echo "$check_output" | grep -c "Error:") || error_count=0
fi

if [[ "$error_count" -gt 0 ]]; then
    echo "" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "⚠️  Odin check found $error_count error(s)" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    # Show first few errors
    echo "$check_output" | grep -A2 "Error:" | head -15 >&2
    echo "" >&2
    echo "Run 'odin check src/' for full details" >&2
    had_issues=true
fi

# Report success if no issues
if [[ "$had_issues" == false ]]; then
    echo "" >&2
    echo "✅ Odin check passed (${#recent_files[@]} file(s) checked)" >&2
fi

# Exit 1 if there were issues (non-blocking warning)
if [[ "$had_issues" == true ]]; then
    exit 1
fi

exit 0
