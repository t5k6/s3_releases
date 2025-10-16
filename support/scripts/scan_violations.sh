#!/bin/bash

# scan_violations.sh - Outputs all function names that violate naming standards
# Used to generate the rename_map.csv

set -e

directory="${1:-.}"

# Source the naming standards
shdir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -f "$shdir/functions/_naming_standards.sh" ]; then
  . "$shdir/functions/_naming_standards.sh"
fi

# Regex patterns for function names (PREFIX_ACTION_OBJECT format)
public_func_pattern='^(repo_|sys_|net_|file_|ui_|build_|cfg_|log_|err_)'
private_func_pattern='^_[a-z][a-z0-9_]*$'
valid_func_pattern="($public_func_pattern|$private_func_pattern)"

# Find all shell scripts and extract function names
  # Get list of shell script files
  find "$directory" -name "*.sh" -type f -exec file {} \; | grep "shell script" | cut -d: -f1 | grep -v -E "(migrate_names|lint_conventions|scan_violations|_naming_standards|_main_integration)" | while IFS= read -r file; do
    # Find function definitions and extract names
    grep -n '^[a-zA-Z_][a-zA-Z0-9_]*() {' "$file" | while IFS=: read -r lineno line; do
    # Extract function name
    if [[ "$line" =~ ^function\s+ ]]; then
      funcname=$(echo "$line" | sed 's/^function //' | cut -d'(' -f1 | xargs)
    else
      funcname=$(echo "$line" | cut -d'(' -f1 | xargs)
    fi

    if [ -n "$funcname" ]; then
      # Check against valid patterns
      if ! [[ "$funcname" =~ $valid_func_pattern ]]; then
        # Output in CSV format: old_name,new_name,function
        echo "$funcname,,function"
      fi
    fi
  done
