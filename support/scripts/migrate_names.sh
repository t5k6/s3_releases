#!/bin/bash

# migrate_names.sh - Basic naming convention enforcer for Simplebuild3
# Enforces lowercase function names and underscores for variables where possible

#!/bin/bash

# migrate_names.sh - Automatic function name migration using CSV mapping
# Renames functions according to the standardized naming convention

set -e

csv_file="${1:-support/scripts/rename_map.csv}"
mode="${2:---dry-run}"

if [ ! -f "$csv_file" ]; then
  echo "Error: CSV file $csv_file not found"
  exit 1
fi

echo "Migrating function names using $csv_file"

# Source naming standards
shdir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -f "$shdir/functions/_naming_standards.sh" ]; then
  . "$shdir/functions/_naming_standards.sh"
fi

# Skip header line, read CSV
tail -n +2 "$csv_file" | while IFS=',' read -r old_name new_name type; do
  # Skip if new_name is empty or if we don't have old_name
  [ -z "$old_name" ] && continue
  [ -z "$new_name" ] && continue
  [ "$old_name" = "$new_name" ] && continue

  echo "Migrating: $old_name -> $new_name"

  # Find all shell scripts
  find . -name "*.sh" -type f | while read -r file; do
    # Check if file contains the old function name
    if grep -q "\b$old_name\b" "$file"; then
      echo "  Updating $file"

      if [ "$mode" = "--apply" ]; then
        # Use word boundaries for safe replacement
        sed -i "s/\b$old_name\b/$new_name/g" "$file"
        echo "  ✅ Applied: $old_name -> $new_name in $file"
      else
        # Show what would be changed
        grep -n "\b$old_name\b" "$file" | head -3
        echo "  --dry-run: Would replace '$old_name' with '$new_name'"
      fi
    fi
  done
done

if [ "$mode" = "--apply" ]; then
  echo "Migration completed successfully"
else
  echo "Dry run completed. Use --apply to actually rename functions"
fi
