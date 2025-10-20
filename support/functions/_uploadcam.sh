#!/bin/bash

net_upload_cam_profile() {
	err_push_context "Upload CAM operation"
	clear
	slogo
	local profile_file="$1"

	# Input validation
	if [[ ! -f "$profdir/$profile_file" ]]; then
		log_fatal "$profile_file $txt_upload_cam1" "$EXIT_MISSING"
	else
		log_info "CONFIG: $g_l$profile_file $txt_upload_cam2"
	fi

	# Load configuration
	if ! cfg_load_file "profile" "$profdir/$profile_file"; then
		log_fatal "Failed to load profile configuration: $profile_file" "$EXIT_INVALID_CONFIG"
	fi

	# Populate variables from loaded profile configuration
	local loginname
	loginname=$(cfg_get_value "profile" "loginname")
	local ip
	ip=$(cfg_get_value "profile" "ip")
	local port
	port=$(cfg_get_value "profile" "port")
	local stop_target
	stop_target=$(cfg_get_value "profile" "stop_target")
	local replace_target
	replace_target=$(cfg_get_value "profile" "replace_target")
	local targetcam
	targetcam=$(cfg_get_value "profile" "targetcam")
	local remote_command
	remote_command=$(cfg_get_value "profile" "remote_command")

	local build_binary
	build_binary=$(build_find_latest_for_profile "$profile_file")
	if [[ -z "$build_binary" ]]; then
		log_fatal "Matching binary not found for profile $profile_file" "$EXIT_MISSING"
	fi

	local remote_user_host="${loginname}@${ip}"

	# Test connection first before proceeding
	log_header "Testing connection to $remote_user_host"
	if ! validate_command "Connection test" net_test_connection "$remote_user_host" "$port"; then
		log_fatal "Could not connect to remote host. Check IP, port, and SSH key." "$EXIT_NETWORK"
	fi

	log_info "CAMNAME: $y_l$build_binary"
	local file_size
	file_size=$(file_get_size_bytes "$bdir/$build_binary")
	local file_mtime
	file_mtime=$(file_get_mtime_formatted "$bdir/$build_binary")
	log_info "FILEDATE/SIZE: $file_mtime / $(file_format_bytes "$file_size")"

	# Upload the binary using abstracted network operations
	log_header "Uploading $build_binary"
	if ! validate_command "Uploading binary" net_scp_upload "$bdir/$build_binary" "$remote_user_host" "/tmp/" "$port"; then
		log_fatal "Upload failed" "$EXIT_NETWORK"
	fi
	log_info "Upload complete."

	log_header "Performing remote operations"
	# Consolidate remote operations into a single SSH session for efficiency.
	# This here-doc constructs a script that is executed on the remote host.
	local remote_script
	read -r -d '' remote_script <<EOF
set -e # Exit immediately if any command fails.

# Stop the remote service if requested
if [[ "$stop_target" == "y" ]]; then
    echo "Stopping remote service..."
    killall -9 "$(basename "$targetcam")" || echo "Service was not running, proceeding..."
fi

# Replace the binary on the remote host if requested
if [[ "$replace_target" == "y" ]]; then
    echo "Replacing remote binary..."
    if [ ! -f "/tmp/$build_binary" ]; then
        echo "Error: Uploaded binary not found on remote at '/tmp/$build_binary'" >&2
        exit 1
    fi
    if [ -f "$targetcam" ]; then
        echo "Backing up existing binary to $targetcam.backup"
        cp -pf "$targetcam" "$targetcam.backup"
    fi
    echo "Moving new binary into place..."
    mv -f "/tmp/$build_binary" "$targetcam"
    chmod +x "$targetcam"
fi

# Run the post-upload remote command if specified
if [[ "$remote_command" != "none" ]]; then
    echo "Executing post-upload command..."
    $remote_command
fi

echo "Remote operations completed."
EOF
	if ! validate_command "Executing remote operations script" net_ssh_execute "$remote_user_host" "$remote_script" "$port"; then
		log_fatal "One or more remote operations failed." "$EXIT_ERROR"
	fi
	log_info "All remote operations completed."

	log_info "Upload process completed successfully."
	err_pop_context
	return 0
}
