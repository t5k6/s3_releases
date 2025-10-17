#!/bin/bash

#simplebuild_plugin list_ssh_profiles

# Plugin entry point for creating/editing SSH profiles.
# This wrapper calls the refactored, standardized UI function.
ssh_editor() {
    ui_edit_ssh_profile "$@"
}

# Plugin entry point for listing SSH profiles from the command line.
list_ssh_profiles() {
    sys_list_ssh_profiles
    exit 0
}

# Core UI logic for the SSH profile editor.
# Adheres to modern standards: UCM, robust UI loops, and error handling.
ui_edit_ssh_profile() {
    err_push_context "SSH Profile Editor"
    local profile_file_arg="$1"

    # --- Configuration Loading ---
    # Use the Unified Configuration Manager (UCM) for secure loading.
    local loginname password ip port replace_target stop_target targetcam toolchain remote_command
    if [[ -n "$profile_file_arg" && -f "$profdir/$profile_file_arg" ]]; then
        log_info "Loading existing profile: $profile_file_arg"
        if ! cfg_load_file "profile" "$profdir/$profile_file_arg"; then
            log_fatal "Failed to load profile '$profile_file_arg'. Check file format." "$EXIT_INVALID_CONFIG"
        fi
        loginname=$(cfg_get_value "profile" "loginname")
        password=$(cfg_get_value "profile" "password")
        ip=$(cfg_get_value "profile" "ip")
        port=$(cfg_get_value "profile" "port" "22")
        replace_target=$(cfg_get_value "profile" "replace_target" "y")
        stop_target=$(cfg_get_value "profile" "stop_target" "y")
        targetcam=$(cfg_get_value "profile" "targetcam" "/usr/bin/oscam")
        toolchain=$(cfg_get_value "profile" "toolchain")
        remote_command=$(cfg_get_value "profile" "remote_command" "none")
    else
        log_info "Creating new profile."
        # Set defaults for a new profile
        loginname="$(whoami)"
        password="" # Security: Do not suggest a default password
        ip="192.168.1.1"
        port="22"
        replace_target="y"
        stop_target="y"
        targetcam="/usr/bin/oscam"
        toolchain=""
        remote_command="none"
    fi

    # --- UI Loop ---
    # Use a loop instead of recursion for robust input handling.
    while true; do
        local form_items=("${txt_loginname:-Login Name:}"      1 1 "$loginname" 1 18 40 39
                          "${txt_password:-Password:}"         2 1 "$password" 2 18 40 39
                          "IP Address/Hostname:" 3 1 "$ip" 3 18 40 39
                          "SSH Port:"            4 1 "$port" 4 18 6 5
                          "Associated Toolchain:"  5 1 "$toolchain" 5 18 40 39
                          "Remote Binary Path:"  6 1 "$targetcam" 6 18 40 39
                          "Replace Binary? (y/n):" 7 1 "$replace_target" 7 18 2 2
                          "Stop Service? (y/n):"   8 1 "$stop_target" 8 18 2 2)

        local config_parts
        config_parts=$(ui_show_form "SSH Transfer Profile Editor" " " 15 65 8 "${form_items[@]}")
        local return_value=$?
        # Handle Cancel/ESC
        if [[ $return_value -ne 0 ]]; then
            log_info "Profile creation/edit cancelled."
            err_pop_context
            return 1
        fi

        # Extract values from the form output
        loginname=$(echo "$config_parts" | sed -n '1p')
        password=$(echo "$config_parts" | sed -n '2p')
        ip=$(echo "$config_parts" | sed -n '3p')
        port=$(echo "$config_parts" | sed -n '4p')
        toolchain=$(echo "$config_parts" | sed -n '5p')
        targetcam=$(echo "$config_parts" | sed -n '6p')
        replace_target=$(echo "$config_parts" | sed -n '7p')
        stop_target=$(echo "$config_parts" | sed -n '8p')

        remote_command=$(ui_get_input "Post-Upload Command (use 'none' to disable)" "" "$remote_command" 7 60)
        [[ $? -ne 0 ]] && { log_info "Cancelled."; err_pop_context; return 1; }

        local default_filename="${profile_file_arg%.ssh}"
        [[ -z "$default_filename" ]] && default_filename="${toolchain}_${ip//./-}"

        local config_file_name
        config_file_name=$(ui_get_input "$txt_ssh_profiles_name" "$txt_ssh_profiles_example" "$default_filename" 8 60)
        [[ $? -ne 0 ]] && { log_info "Cancelled."; err_pop_context; return 1; }

        if [[ -z "$config_file_name" ]]; then
            ui_show_msgbox "Input Error" "Profile name cannot be empty."
            continue # Retry the loop
        fi

        # --- Configuration Saving ---
        # Use UCM to set values in the cache and then save to file.
        cfg_set_value "profile" "loginname" "$loginname"
        cfg_set_value "profile" "password" "$password"
        cfg_set_value "profile" "ip" "$ip"
        cfg_set_value "profile" "port" "$port"
        cfg_set_value "profile" "toolchain" "$toolchain"
        cfg_set_value "profile" "targetcam" "$targetcam"
        cfg_set_value "profile" "replace_target" "$replace_target"
        cfg_set_value "profile" "stop_target" "$stop_target"
        cfg_set_value "profile" "remote_command" "$remote_command"

        local final_path="$profdir/${config_file_name}.ssh"
        if cfg_save_file "profile" "$final_path"; then
            log_info "Profile saved successfully to: $final_path"
            break # Exit the loop on success
        else
            ui_show_msgbox "Error" "Failed to save profile. Check permissions on '$profdir'."
            continue
        fi
    done

    sys_list_ssh_profiles
    err_pop_context
    return 0
}


# Lists all available SSH profiles to the console using standard logging.
sys_list_ssh_profiles() {
    clear
    slogo # Keep the branding consistent
    log_header "Available SSH Profiles"
    log_info "To use a profile: ./s3 upload <profile_name.ssh>"

    local profiles
    mapfile -t profiles < <(find "$profdir" -maxdepth 1 -type f -name "*.ssh" -printf "%f\n" 2>/dev/null | sort)

    if [[ ${#profiles[@]} -gt 0 ]]; then
        local i=1
        for profile in "${profiles[@]}"; do
            echo "  ($i) > ${g_l}${profile}${re_}" # Use echo for simpler formatting here
            ((i++))
        done
    else
        log_warn "No SSH profiles found in '$profdir'."
        log_info "Create one with: ./s3 ssh_editor"
    fi
    echo "" # Add a final newline for spacing
}