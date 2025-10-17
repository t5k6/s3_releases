#!/bin/bash

net_upload_cam_profile(){
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
	local loginname=$(cfg_get_value "profile" "loginname")
	local ip=$(cfg_get_value "profile" "ip")
	local port=$(cfg_get_value "profile" "port")
	local stop_target=$(cfg_get_value "profile" "stop_target")
	local replace_target=$(cfg_get_value "profile" "replace_target")
	local targetcam=$(cfg_get_value "profile" "targetcam")
	local remote_command=$(cfg_get_value "profile" "remote_command")

	local build_binary
	build_binary=$(find_latest_build_for_profile "$profile_file")
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
	local file_size; file_size=$(stat -c%s "$bdir/$build_binary")
	log_info "FILEDATE/SIZE: $(stat -c %y "$bdir/$build_binary" | awk '{print $1" " substr($2,1,8)}') / $(file_format_bytes "$file_size")"

	# Upload the binary using abstracted network operations
	log_header "Uploading $build_binary"
	if ! validate_command "Uploading binary" net_scp_upload "$bdir/$build_binary" "$remote_user_host" "/tmp/" "$port"; then
		log_fatal "Upload failed" "$EXIT_NETWORK"
	fi
	log_info "Upload complete."

	# Stop the remote service if requested
	if [[ "$stop_target" == "y" ]]; then
		log_header "Stopping remote service"
		local stop_command="killall -9 $(basename "$targetcam")"
		if ! validate_command "Stopping remote service" net_ssh_execute "$remote_user_host" "$stop_command" "$port"; then
			log_warn "Failed to stop remote service (it may not have been running)."
		fi
		log_info "Stop command sent."
	fi

	# Replace the binary on the remote host if requested
	if [[ "$replace_target" == "y" ]]; then
		log_header "Replacing remote binary"
		# Use here-doc for a clean, readable remote script
		local replace_script
		read -r -d '' replace_script << EOF
if [ ! -f "/tmp/$build_binary" ]; then
    echo "Uploaded binary not found on remote." >&2
    exit 1
fi
if [ -f "$targetcam" ]; then
    cp -pf "$targetcam" "$targetcam.backup"
fi
mv -f "/tmp/$build_binary" "$targetcam"
chmod +x "$targetcam"
echo "Binary replaced successfully."
EOF
		if ! validate_command "Replacing remote binary" net_ssh_execute "$remote_user_host" "$replace_script" "$port"; then
			log_fatal "Failed to replace the remote binary" "$EXIT_ERROR"
		fi
		log_info "Remote binary replaced."
	fi

	# Run the post-upload remote command if specified
	if [[ "$remote_command" != "none" ]]; then
		log_header "Executing remote command"
		if ! validate_command "Executing remote command" net_ssh_execute "$remote_user_host" "$remote_command" "$port"; then
			log_fatal "Remote command failed" "$EXIT_ERROR"
		fi
		log_info "Remote command executed."
	fi

	log_info "Upload process completed successfully."
	err_pop_context
	return 0
}
