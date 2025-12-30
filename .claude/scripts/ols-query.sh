#!/bin/bash
# ols-query.sh - Direct OLS interaction for Claude Code
# Provides LSP functionality when ENABLE_LSP_TOOLS is unavailable

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Send LSP message with Content-Length header
format_message() {
    local json="$1"
    local len=${#json}
    printf "Content-Length: %d\r\n\r\n%s" "$len" "$json"
}

# Run OLS session and extract result for request ID 2
run_session() {
    local operation="$1"
    local file_path="$2"
    local line="${3:-0}"
    local char="${4:-0}"

    # Make path absolute
    if [[ ! "$file_path" = /* ]]; then
        file_path="$PROJECT_ROOT/$file_path"
    fi

    if [[ ! -f "$file_path" ]]; then
        echo "Error: File not found: $file_path" >&2
        return 1
    fi

    local root_uri="file://$PROJECT_ROOT"
    local file_uri="file://$file_path"
    local content
    content=$(cat "$file_path" | jq -Rs .)

    # Build messages
    local init_msg='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":'$$',"rootUri":"'$root_uri'","capabilities":{},"workspaceFolders":[{"uri":"'$root_uri'","name":"workspace"}]}}'
    local init_notif='{"jsonrpc":"2.0","method":"initialized","params":{}}'
    local open_msg='{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"'$file_uri'","languageId":"odin","version":1,"text":'$content'}}}'

    local request_msg
    case "$operation" in
        definition)
            request_msg='{"jsonrpc":"2.0","id":2,"method":"textDocument/definition","params":{"textDocument":{"uri":"'$file_uri'"},"position":{"line":'$line',"character":'$char'}}}'
            ;;
        references)
            request_msg='{"jsonrpc":"2.0","id":2,"method":"textDocument/references","params":{"textDocument":{"uri":"'$file_uri'"},"position":{"line":'$line',"character":'$char'},"context":{"includeDeclaration":true}}}'
            ;;
        symbols)
            request_msg='{"jsonrpc":"2.0","id":2,"method":"textDocument/documentSymbol","params":{"textDocument":{"uri":"'$file_uri'"}}}'
            ;;
        hover)
            request_msg='{"jsonrpc":"2.0","id":2,"method":"textDocument/hover","params":{"textDocument":{"uri":"'$file_uri'"},"position":{"line":'$line',"character":'$char'}}}'
            ;;
        format)
            request_msg='{"jsonrpc":"2.0","id":2,"method":"textDocument/formatting","params":{"textDocument":{"uri":"'$file_uri'"},"options":{"tabSize":4,"insertSpaces":false}}}'
            ;;
        *)
            echo "Unknown operation: $operation" >&2
            return 1
            ;;
    esac

    local shutdown_msg='{"jsonrpc":"2.0","id":3,"method":"shutdown","params":null}'

    # Run OLS with all messages
    local response
    response=$({
        format_message "$init_msg"
        format_message "$init_notif"
        format_message "$open_msg"
        sleep 0.3  # Give OLS time to process the file
        format_message "$request_msg"
        sleep 0.3
        format_message "$shutdown_msg"
    } | timeout 10 ols 2>/dev/null || true)

    # Extract the result for id:2 (our actual request)
    # The response format is: {"jsonrpc": "2.0", "id": 2, "result": ...}
    local result
    result=$(echo "$response" | grep -o '{"jsonrpc": "2.0", "id": 2, "result": \[.*\]}' | head -1 || true)

    if [[ -z "$result" ]]; then
        # Try without array (for single results or null)
        result=$(echo "$response" | grep -o '{"jsonrpc": "2.0", "id": 2, "result": [^}]*}' | head -1 || true)
    fi

    if [[ -n "$result" ]]; then
        echo "$result" | jq -r '.result' 2>/dev/null
    else
        echo "null"
    fi
}

# Format symbols output nicely
format_symbols() {
    jq -r '
        def kind_name:
            if . == 1 then "File"
            elif . == 2 then "Module"
            elif . == 5 then "Class"
            elif . == 6 then "Method"
            elif . == 10 then "Enum"
            elif . == 12 then "Function"
            elif . == 13 then "Variable"
            elif . == 14 then "Constant"
            elif . == 22 then "Struct"
            elif . == 23 then "Event"
            else "Unknown(\(.))"
            end;
        if . == null then "No symbols found"
        else
            .[] | "\(.name) (\(.kind | kind_name)) at line \(.range.start.line + 1)"
        end
    ' 2>/dev/null || cat
}

# Format location output nicely
format_location() {
    jq -r '
        if . == null then "No definition found"
        elif type == "array" then
            .[] | "\(.uri | sub("file://"; "")):\(.range.start.line + 1):\(.range.start.character + 1)"
        else
            "\(.uri | sub("file://"; "")):\(.range.start.line + 1):\(.range.start.character + 1)"
        end
    ' 2>/dev/null || cat
}

# Main
main() {
    if [[ $# -lt 2 ]]; then
        cat <<EOF
Usage: $0 <operation> <file> [line] [character]

Operations:
  symbols <file>                   - List all symbols in file
  references <file> <line> <char>  - Find all references at position
  definition <file> <line> <char>  - Go to definition at position
  hover <file> <line> <char>       - Get hover info at position
  format <file>                    - Check if formatting needed

Line and character are 0-indexed.

For diagnostics/errors, use: odin check src/
For formatting, use: odinfmt -w <file>

Examples:
  $0 symbols src/main.odin
  $0 references src/system.odin 3 0
  $0 format src/main.odin

Add --raw to get JSON output instead of formatted text.
EOF
        return 1
    fi

    local raw=false
    if [[ "$1" == "--raw" ]]; then
        raw=true
        shift
    fi

    local operation="$1"
    shift

    local result
    result=$(run_session "$operation" "$@")

    if [[ "$raw" == true ]]; then
        echo "$result"
    else
        case "$operation" in
            symbols)
                echo "$result" | format_symbols
                ;;
            definition|references)
                echo "$result" | format_location
                ;;
            hover)
                echo "$result" | jq -r '.contents.value // .contents // "No hover info"' 2>/dev/null || echo "$result"
                ;;
            format)
                # Format returns array of text edits - show what would change
                echo "$result" | jq -r 'if . == null or . == [] then "No formatting changes needed" else "Formatting changes available (use odinfmt -w to apply)" end' 2>/dev/null || echo "$result"
                ;;
            *)
                echo "$result"
                ;;
        esac
    fi
}

main "$@"
