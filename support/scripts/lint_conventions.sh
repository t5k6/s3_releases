#!/bin/bash

# lint_conventions.sh - Enforces Simplebuild3 naming standards
# Scans codebase for violations and reports them

set -e

directory="${1:-support/functions}"

if [ ! -d "$directory" ]; then
  echo "Error: Directory $directory does not exist"
  exit 1
fi

echo "Linting naming conventions in $directory"

# Source the naming standards
shdir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -f "$shdir/functions/_naming_standards.sh" ]; then
  . "$shdir/functions/_naming_standards.sh"
fi

declare -a violations=()

# Regex patterns for function names (PREFIX_ACTION_OBJECT format)
# Allow prefixes: repo_, sys_, net_, file_, ui_, build_, cfg_, log_, err_, _
public_func_pattern='^(repo_|sys_|net_|file_|ui_|build_|cfg_|log_|err_)'
private_func_pattern='^_[a-z][a-z0-9_]*$'
valid_func_pattern="($public_func_pattern|$private_func_pattern)"

# Find all shell scripts
while IFS= read -r -d '' file; do
  echo "Checking $file"

  # Find function definitions
  grep -n -E '^(function\s+)?[a-zA-Z_][a-zA-Z0-9_]*\s*\(\)\s*\{' "$file" | while IFS=: read -r lineno line; do
    # Extract function name
    if [[ "$line" =~ ^function\s+ ]]; then
      funcname=$(echo "$line" | sed 's/^function //' | cut -d'(' -f1 | xargs)
    else
      funcname=$(echo "$line" | cut -d'(' -f1 | xargs)
    fi

    if [ -n "$funcname" ]; then
      # Check against valid patterns
      if ! [[ "$funcname" =~ $valid_func_pattern ]]; then
        violations+=("$file:$lineno: Function '$funcname' does not conform to naming standard")
      fi
    fi
  done

  # Check for variables declared without 'local' (should be flagged as potential issues)
  grep -n -E '^[[:space:]]*[a-z][a-zA-Z0-9_]*=' "$file" | while IFS=: read -r lineno line; do
    # Skip if line contains 'local', 'export', 'readonly', or is part of a command
    if ! [[ "$line" =~ (local|export|readonly|=|\$|\(|\)) ]] && [[ "$line" =~ ^[[:space:]]*([a-z][a-zA-Z0-9_]*)= ]]; then
      var="${BASH_REMATCH[1]}"
      # Skip common constants or if it looks like a global
      if [[ "$var" =~ ^[A-Z_]+$ ]]; then
        continue
      fi
      violations+=("$file:$lineno: Variable '$var' may need 'local' declaration")
    fi
  done

done < <(find "$directory" -name "*.sh" -type f -print0)

# Report violations
if [ ${#violations[@]} -gt 0 ]; then
  echo ""
  echo "=== NAMING STANDARD VIOLATIONS FOUND ==="
  printf '%s\n' "${violations[@]}"
  echo ""
  echo "Total violations: ${#violations[@]}"
  exit 1
else
  echo "✅ All functions conform to naming standards"
  exit 0
fi
