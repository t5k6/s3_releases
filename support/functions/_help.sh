#!/bin/bash

# =============================================================================
# SIMPLEBUILD3 - Unified Help and Usage Display
# =============================================================================
# Provides standardized functions for displaying command-line help text.
# =============================================================================

# ------------------------------------------------------------------------------
# UI HELPER FUNCTIONS
# ------------------------------------------------------------------------------

# Formats a list of items into aligned columns for display.
#
# Usage: ui_helper_format_columns <max_line_width> <item_suffix> <item1> <item2> ...
#   $1: max_line_width - The maximum character width before wrapping to a new line.
#   $2: item_suffix    - A string to append to each item (e.g., "(_off)"). Can be empty.
#   $@: items          - An array of strings to format.
ui_helper_format_columns() {
	local max_width="$1"
	local suffix="$2"
	shift 2
	local -a items=("$@")
	local sorted_items=()
	local line_length=2 # Start with indent length

	# Sort items uniquely for consistent display
	mapfile -t sorted_items < <(printf "%s\n" "${items[@]}" | sort -u)

	printf "  "
	for item in "${sorted_items[@]}"; do
		# Skip empty items that might result from array expansion
		[[ -z "$item" ]] && continue

		# Calculate the length of the next item to be printed
		local display_item="${item}${suffix}"
		local item_length=$((${#display_item} + 1)) # +1 for the space

		if ((line_length > 2 && (line_length + item_length) > max_width)); then
			printf "\n  "
			line_length=2
		fi

		printf "%s " "$display_item"
		line_length=$((line_length + item_length))
	done
	printf "\n"
}

# Displays the list of available toolchains.
ui_show_help_toolchains() {
	printf "$w_l  toolchains :\n  ------------$g_n\n"
	# Use a wide format for better readability on standard terminals
	ui_helper_format_columns 75 "" "${AVAI_TCLIST[@]}"
}

# ------------------------------------------------------------------------------
# MAIN HELP DISPLAY
# ------------------------------------------------------------------------------

# Displays the main help screen with all available options.
ui_show_help() {
	clear
	slogo
	printf "  --------------------------------------\n"
	printf "  $txt_help1 $0 menu\n"
	printf "  $txt_help2\n"
	printf "  --------------------------------------\n"

	# Toolchains
	ui_show_help_toolchains

	# SimpleBuild Options
	printf "$w_l\n  simplebuild options :\n  ---------------------$c_n\n"
	ui_helper_format_columns 75 "" "${s3opts[@]}"

	# Config Cases
	printf "$w_l\n  config_cases :\n  --------------$c_n\n"
	ui_helper_format_columns 75 "(_off)" "${config_cases[@]}"

	# Addons
	printf "$w_l\n\n  addons :\n  --------$p_l\n"
	ui_helper_format_columns 75 "(_off)" "${SHORT_ADDONS[@]}"

	# Protocols
	printf "$w_l\n  protocols :\n  -----------$y_l\n"
	ui_helper_format_columns 75 "(_off)" "${SHORT_PROTOCOLS[@]}"

	# Readers
	printf "$w_l\n\n  readers :\n  ---------$r_l\n"
	ui_helper_format_columns 75 "(_off)" "${SHORT_READERS[@]}"

	# Card Readers
	printf "$w_l\n  card_readers :\n  --------------$b_l\n"
	ui_helper_format_columns 75 "(_off)" "${SHORT_CARD_READERS[@]}"

	# USE_vars
	printf "$w_l\n\n  use_vars :\n  --------$w_n\n"
	ui_helper_format_columns 75 "(_off)" "${!USE_vars[@]}"

	ui_show_newline # Final newline
}
