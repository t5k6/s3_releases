#!/bin/bash

# =============================================================================
# SIMPLEBUILD3 - Unified Menu Construction System
# =============================================================================
# Provides consistent menu creation and handling across all GUI operations.
# Replaces scattered dialog/menu code with centralized, reusable functions.
# =============================================================================

# ------------------------------------------------------------------------------
# MENU STATE MANAGEMENT
# ------------------------------------------------------------------------------

_MENU_OPTION_COUNT=0
_MENU_TITLE=""
_MENU_ITEMS=()
_MENU_OPTIONS_LIST=()
_MENU_SELECTED_OPTION=""

# ------------------------------------------------------------------------------
# MENU INITIALIZATION FUNCTIONS
# ------------------------------------------------------------------------------

menu_init() {
    # Initialize a new menu
    local title="${1:-Menu}"
    _MENU_OPTION_COUNT=0
    _MENU_TITLE="$title"
    _MENU_ITEMS=()
    _MENU_OPTIONS_LIST=()
}

menu_add_option() {
    # Add option to menu
    local option_id="$1"
    local option_text="$2"
    local state="${3:-off}" # on/off/disabled

    # Replace newline characters in option text to prevent dialog argument errors
    option_text="${option_text//$'\n'/ }"

    if [ "$_MENU_OPTION_COUNT" -gt 0 ]; then
        _MENU_OPTIONS_LIST[${_MENU_OPTION_COUNT}]="${option_id}#${option_text}#${state}"
    else
        _MENU_OPTIONS_LIST[0]="${option_id}#${option_text}#${state}"
    fi

    _MENU_ITEMS[${_MENU_OPTION_COUNT}]="${option_id}"
    _MENU_OPTION_COUNT=$((_MENU_OPTION_COUNT + 1))
}

menu_add_separator() {
    # Add visual separator
    local separator_text="${1:--}"
    menu_add_option "---$separator_text---" "$separator_text" "disabled"
}

# ------------------------------------------------------------------------------
# MENU DISPLAY FUNCTIONS
# ------------------------------------------------------------------------------

_menu_show_internal() {
    local menu_type="$1"
    local height="$2"
    local width="$3"
    shift 3

    # --- ARCHITECTURAL FIX: Build arguments in an array ---
    # This is a robust replacement for the fragile `IFS` method. It correctly
    # handles empty strings and spaces within arguments.
    local cmd_args=("$gui" "$st_" "$bt_" "$title_" "$menu_type" "$_MENU_TITLE" "$height" "$width")

    case "$menu_type" in
        --checklist|--radiolist|--menu)
            # These types require the item count as an argument
            cmd_args+=("$_MENU_OPTION_COUNT")
            ;;
    esac

    # Manually parse each item and add its parts to the command array
    for item_str in "${_MENU_OPTIONS_LIST[@]}"; do
        local tag text state
        tag=$(echo "$item_str" | cut -d'#' -f1)
        text=$(echo "$item_str" | cut -d'#' -f2)
        if [[ "$menu_type" == "--menu" ]]; then
            cmd_args+=("$tag" "$text")
        else
            state=$(echo "$item_str" | cut -d'#' -f3)
            cmd_args+=("$tag" "$text" "$state")
        fi
    done

    log_debug "Executing dialog for menu: '$_MENU_TITLE'"

    # Execute and capture output and stderr
    local dialog_stderr_file
    dialog_stderr_file=$(mktemp /tmp/s3_dialog_stderr.XXXXXX)
    _MENU_SELECTED_OPTION=$("${cmd_args[@]}" 2> "$dialog_stderr_file")
    local exit_code=$?
    local dialog_stderr
    dialog_stderr=$(<"$dialog_stderr_file")
    rm -f "$dialog_stderr_file"

    if [[ "$exit_code" -ne 0 && "$exit_code" -ne 1 ]]; then # Exit code 1 is Cancel/ESC, which is not an error
        log_error "Menu system failed (dialog exit code: $exit_code) for menu '$_MENU_TITLE'."
        [[ -n "$dialog_stderr" ]] && log_error "Dialog's own error message was: '$dialog_stderr'"
        log_error "The full command that failed was (arguments printed one per line for clarity):"
        printf "    %s\n" "${cmd_args[@]}" | while IFS= read -r line; do log_error "    '${line//$'\n'/ }'"; done
        return "$exit_code"
    fi

    return "$exit_code"
}


menu_show_checkbox() {
    local height="${1:-$(( _MENU_OPTION_COUNT + 8 ))}"
    local width="${2:-75}"
    _menu_show_internal "--checklist" "$height" "$width"
}

menu_show_radiolist() {
    local height="${1:-$(( _MENU_OPTION_COUNT + 8 ))}"
    local width="${2:-75}"
    _menu_show_internal "--radiolist" "$height" "$width"
}

menu_show_list() {
    local height="${1:-$(( _MENU_OPTION_COUNT + 8 ))}"
    local width="${2:-75}"
    _menu_show_internal "--menu" "$height" "$width"
}

# ------------------------------------------------------------------------------
# MENU RESULT PROCESSING
# ------------------------------------------------------------------------------

menu_get_selected_options() {
    # Get selected options as array
    local selected=()
    local option

    for option in $_MENU_SELECTED_OPTION; do
        selected+=("$(echo "$option" | sed 's/^"\(.*\)"$/\1/')")
    done

    echo "${selected[@]}"
}

menu_is_option_selected() {
    # Check if specific option is selected
    local option_id="$1"
    local selected_options
    selected_options="$_MENU_SELECTED_OPTION"
    local option

    for option in $selected_options; do
        option="$(echo "$option" | sed 's/^"\(.*\)"$/\1/')"
        if [ "$option" = "$option_id" ]; then
            return 0
        fi
    done

    return 1
}

menu_get_first_selection() {
    # Get first selected option (for radiolist/single selection)
    local selected_options
    selected_options="$_MENU_SELECTED_OPTION"
    local first_option

    first_option="$(echo "$selected_options" | awk '{print $1}' | sed 's/^"\(.*\)"$/\1/')"
    echo "$first_option"
}

# ------------------------------------------------------------------------------
# UTILITY FUNCTIONS
# ------------------------------------------------------------------------------

menu_get_max_option_length() {
    # Calculate maximum option text length for auto-sizing
    local max_length=0
    local length
    local option_text

    for option_def in "${_MENU_OPTIONS_LIST[@]}"; do
        option_text="$(echo "$option_def" | cut -d'#' -f2)"
        length="${#option_text}"
        [ "$length" -gt "$max_length" ] && max_length="$length"
    done

    echo "$max_length"
}

menu_clear_state() {
    # Clear all menu state
    _MENU_OPTION_COUNT=0
    _MENU_TITLE=""
    _MENU_ITEMS=()
    _MENU_OPTIONS_LIST=()
    _MENU_SELECTED_OPTION=""
}

# ------------------------------------------------------------------------------
# PREDEFINED MENU TYPES
# ------------------------------------------------------------------------------
# Common menu patterns that can be reused

ui_show_msgbox() {
    # Display a message box
    local title="$1"
    local text="$2"
    local height="${3:-8}"
    local width="${4:-50}"
    "$gui" "$st_" "$bt_" "$title_" --title "$title" --msgbox "$text" "$height" "$width"
}

ui_show_progressbox() {
    # Display a progress box, piping from command output
    # Usage: ui_show_progressbox "Title" < <(command_that_outputs_progress)
    local title="$1"
    local text="${2:-Please wait...}"
    local height="${3:-8}"
    local width="${4:-75}"
    "$gui" "$st_" "$bt_" "$title_" --title "$title" --gauge "$text" "$height" "$width"
}

ui_show_form() {
    # Display a form for data input
    # Usage: ui_show_form "Title" "Text" height width form_height "item1" "item2" ...
    local title="$1"
    local text="$2"
    local height="$3"
    local width="$4"
    local form_height="$5"
    shift 5
    local form_items=("$@")
    "$gui" "$st_" "$bt_" "$title_" --title "$title" --form "$text" "$height" "$width" "$form_height" "${form_items[@]}"
}

ui_get_input() {
    # Get user input via inputbox
    # Usage: ui_get_input "Title" "Prompt" ["Default"] height width
    local title="$1"
    local prompt="$2"
    local default="${3:-}"
    local height="${4:-7}"
    local width="${5:-60}"
    "$gui" "$st_" "$bt_" "$title_" --title "$title" --inputbox "$prompt" "$height" "$width" "$default"
}

ui_show_textbox() {
    # Display a text file in a textbox view
    # Usage: ui_show_textbox "Title" "file_path" [height] [width]
    local title="$1"
    local file_path="$2"
    local height="${3:-20}"
    local width="${4:-75}"
    "$gui" "$st_" "$bt_" "$title_" --title "$title" --textbox "$file_path" "$height" "$width"
}

menu_config_checkbox() {
    # Configuration checklist from associative array
    local config_description="$1"
    shift
    declare -n config_vars="$1"

    menu_init "$config_description Configuration"

    for var in "${!config_vars[@]}"; do
        local display_text="${var}"
        local state="off"
        [ "${config_vars[$var]}" = "1" ] && state="on"
        menu_add_option "$var" "$display_text" "$state"
    done

    if menu_show_checkbox; then
        for option in $(menu_get_selected_options); do
            config_vars[$option]="1"
        done

        # Mark unselected as 0
        for var in "${!config_vars[@]}"; do
            if ! menu_is_option_selected "$var"; then
                config_vars[$var]="0"
            fi
        done
    fi
}

menu_yes_no() {
    # Simple yes/no dialog
    local question="$1"
    local default="${2:-yes}"

    menu_init "$question"
    menu_add_option "yes" "Yes" "off"
    menu_add_option "no" "No" "off"

    if [ "$default" = "yes" ]; then
        _MENU_OPTIONS_LIST[0]="yes#Yes#on"
        _MENU_OPTIONS_LIST[1]="no#No#off"
    else
        _MENU_OPTIONS_LIST[0]="yes#Yes#off"
        _MENU_OPTIONS_LIST[1]="no#No#on"
    fi

    if menu_show_radiolist "7" "40"; then
        local selection="$(menu_get_first_selection)"
        case "$selection" in
            "yes") return 0 ;;
            "no") return 1 ;;
            *) return 1 ;;
        esac
    fi
    return 1
}

menu_file_selection() {
    # File/directory selection menu
    local prompt="$1"
    local directory="${2:-.}"
    local file_pattern="${3:-*}"

    local files=()
    local item_count=0

    menu_init "$prompt"

    while IFS= read -r -d '' file; do
        local rel_path="${file#$directory/}"
        files+=("$rel_path")
        menu_add_option "$rel_path" "$rel_path" "off"
        item_count=$((item_count + 1))
    done < <(find "$directory" -maxdepth 1 -name "$file_pattern" -type f -print0 | sort -z)

    if [ "$item_count" -eq 0 ]; then
        menu_add_option "none" "(No files found)" "off"
    fi

    local result
    if [ "$item_count" -eq 0 ]; then
        "$gui" "$st_" "$bt_" "$title_" --msgbox "No files found matching pattern '$file_pattern' in $directory" 6 50
        return 1
    elif menu_show_radiolist; then
        result="$(menu_get_first_selection)"
        echo "$result"
        return 0
    fi

    return 1
}

# ------------------------------------------------------------------------------
# BACKWARD COMPATIBILITY
# ------------------------------------------------------------------------------
# Stub functions for gradual migration

_menu_init(){
    menu_init "$@"
}

_init_menu(){
    menu_init "Simplebuild3 Menu"
}

_menu_select(){
    menu_show_checkbox
}

_select_menu(){
    # Stub for main menu - handled by calling function
    true
}
