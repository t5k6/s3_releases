#!/bin/bash

# =============================================================================
# SIMPLEBUILD3 - Network Operations Abstraction Layer
# =============================================================================
# Provides unified SSH/SCP operations with consistent error handling.
# Replaces ad-hoc network code in existing functions.
# =============================================================================

# ------------------------------------------------------------------------------
# GLOBAL NETWORK SETTINGS
# ------------------------------------------------------------------------------
NET_DEFAULT_TIMEOUT=30
NET_SSH_PORT_DEFAULT=22

# ------------------------------------------------------------------------------
# SSH/SCP ABSTRACTION FUNCTIONS
# ------------------------------------------------------------------------------
# Main network operations with unified error handling

net_ssh_execute() {
	# Execute command on remote host via SSH
	local user_host="$1"
	local remote_command="$2"
	local port="${3:-$NET_SSH_PORT_DEFAULT}"

	err_init "SSH execution to $user_host"

	# Validate parameters
	if [ -z "$user_host" ]; then
		err_log_and_exit "User@host not specified" "$EXIT_INVALID_CONFIG"
	fi

	if [ -z "$remote_command" ]; then
		err_log_and_exit "Remote command not specified" "$EXIT_INVALID_CONFIG"
	fi

	log_debug "Executing on $user_host (port $port): $remote_command"

	# Execute command with proper error handling
	ssh -o BatchMode=yes \
		-o ConnectTimeout="$NET_DEFAULT_TIMEOUT" \
		-o StrictHostKeyChecking=no \
		-p "$port" \
		"$user_host" \
		"$remote_command"

	err_check_command_result "$?" "SSH execution: $remote_command"
}

net_scp_upload() {
	# Upload file to remote host via SCP
	local local_file="$1"
	local user_host="$2"
	local remote_path="$3"
	local port="${4:-$NET_SSH_PORT_DEFAULT}"

	err_init "SCP upload to $user_host"

	# Validate parameters
	err_validate_file_exists "$local_file" "SCP Upload"

	if [ -z "$user_host" ]; then
		err_log_and_exit "User@host not specified" "$EXIT_INVALID_CONFIG"
	fi

	if [ -z "$remote_path" ]; then
		err_log_and_exit "Remote path not specified" "$EXIT_INVALID_CONFIG"
	fi

	log_debug "Uploading $local_file to $user_host:$remote_path (port $port)"

	# Upload file with error handling
	scp -P "$port" \
		-o BatchMode=yes \
		-o ConnectTimeout="$NET_DEFAULT_TIMEOUT" \
		-o StrictHostKeyChecking=no \
		"$local_file" \
		"$user_host:$remote_path"

	err_check_command_result "$?" "SCP upload: $local_file to $remote_path"
}

net_scp_download() {
	# Download file from remote host via SCP
	local user_host="$1"
	local remote_file="$2"
	local local_path="$3"
	local port="${4:-$NET_SSH_PORT_DEFAULT}"

	err_init "SCP download from $user_host"

	# Validate parameters
	if [ -z "$user_host" ]; then
		err_log_and_exit "User@host not specified" "$EXIT_INVALID_CONFIG"
	fi

	if [ -z "$remote_file" ]; then
		err_log_and_exit "Remote file not specified" "$EXIT_INVALID_CONFIG"
	fi

	if [ -z "$local_path" ]; then
		err_log_and_exit "Local path not specified" "$EXIT_INVALID_CONFIG"
	fi

	log_debug "Downloading $user_host:$remote_file to $local_path (port $port)"

	# Download file with error handling
	scp -P "$port" \
		-o BatchMode=yes \
		-o ConnectTimeout="$NET_DEFAULT_TIMEOUT" \
		-o StrictHostKeyChecking=no \
		"$user_host:$remote_file" \
		"$local_path"

	err_check_command_result "$?" "SCP download: $remote_file to $local_path"
}

net_remote_file_exists() {
	# Check if file exists on remote host
	local user_host="$1"
	local remote_file="$2"
	local port="${3:-$NET_SSH_PORT_DEFAULT}"

	local check_command="[ -f '$remote_file' ]"

	if net_ssh_execute "$user_host" "$check_command" "$port" >/dev/null 2>&1; then
		return 0 # Exists
	else
		return 1 # Doesn't exist or error
	fi
}

net_test_connection() {
	# Test SSH connection to remote host
	local user_host="$1"
	local port="${2:-$NET_SSH_PORT_DEFAULT}"

	err_init "SSH connection test to $user_host"

	if [ -z "$user_host" ]; then
		err_log_and_exit "User@host not specified" "$EXIT_INVALID_CONFIG"
	fi

	log_debug "Testing SSH connection to $user_host:$port"

	# Try simple echo command to test connection
	if net_ssh_execute "$user_host" "echo 'Connection test successful'" "$port" >/dev/null 2>&1; then
		log_info "SSH connection to $user_host successful"
		return 0
	else
		log_error "SSH connection to $user_host failed"
		return 1
	fi
}

net_check_url() {
	# Check HTTP/HTTPS URL connectivity
	local url="$1"
	local timeout="${2:-$NET_DEFAULT_TIMEOUT}"

	err_init "URL connectivity check for $url"

	if [ -z "$url" ]; then
		err_log_and_exit "URL not specified" "$EXIT_INVALID_CONFIG"
	fi

	log_debug "Checking connectivity to $url"

	# Use curl for HTTP checking
	local http_code
	http_code=$(curl --head --silent --write-out "%{http_code}" --connect-timeout "$timeout" --max-time "$((timeout * 2))" -o /dev/null "$url")
	local curl_exit=$?

	if [[ "$curl_exit" -eq 0 && "$http_code" -ne "000" ]]; then
		log_debug "URL is reachable: $url (HTTP status: $http_code)"
		return 0
	else
		log_warn "$url is not reachable! (cURL exit: $curl_exit, HTTP status: $http_code)"
		return 1
	fi
}

net_download_file() {
	# Download file from URL with progress display support
	local url="$1"
	local output_file="$2"
	local progress_callback="${3:-}"

	err_init "File download from $url"

	# Validate parameters
	if [ -z "$url" ]; then
		err_log_and_exit "URL not specified" "$EXIT_INVALID_CONFIG"
	fi

	if [ -z "$output_file" ]; then
		err_log_and_exit "Output file not specified" "$EXIT_INVALID_CONFIG"
	fi

	log_debug "Downloading $url to $output_file"

	# Handle progress callback if provided
	if [ -n "$progress_callback" ]; then
		# Use custom progress display.
		# The original implementation was flawed because `wget --progress=dot` does not produce
		# a clean stream of numbers for `dialog --gauge`.
		# This new implementation pipes wget's stderr through a parser that extracts percentages.
		{ wget -O "$output_file" --progress=dot:giga "$url" 2>&1; } |
			grep --line-buffered -o '[0-9]\+%' | sed -u 's/%//' | eval "$progress_callback"
	else
		# Use wget with progress display
		wget --progress=bar:force -q --show-progress "$url" -O "$output_file"
	fi

	# Check the exit status of wget from the pipe
	err_check_command_result "${PIPESTATUS[0]}" "File download: $url to $output_file"
}

net_download_softcam_key() {
	local dest_dir="$1"
	err_push_context "Download SoftCam.Key"
	log_header "Downloading SoftCam.Key"

	if [[ ! -d "$dest_dir" ]]; then
		log_error "Destination directory does not exist: $dest_dir"
		err_pop_context
		return 1
	fi

	local dest_file="$dest_dir/SoftCam.Key"
	if ! validate_command "Downloading SoftCam.Key" net_download_file "$URL_SOFTCAM_KEY" "$dest_file"; then
		log_error "Failed to download SoftCam.Key from $URL_SOFTCAM_KEY"
		err_pop_context
		return 1
	fi

	log_info "SoftCam.Key successfully downloaded to $dest_file"
	err_pop_context
	return 0
}

# Fetches the official SHA256 checksum for a given OpenSSL archive name from openssl.org
# Usage: local hash=$(net_get_openssl_checksum "openssl-1.1.1w.tar.gz")
net_get_openssl_checksum() {
	local archive_name="$1"
	local checksum_url="https://www.openssl.org/source/${archive_name}.sha256"
	local checksum_file
	checksum_file=$(mktemp)

	log_debug "Fetching OpenSSL checksum from: $checksum_url"

	# Download the checksum file quietly
	if ! wget --quiet -O "$checksum_file" "$checksum_url"; then
		log_warn "Could not download checksum file from $checksum_url."
		rm -f "$checksum_file"
		return 1
	fi

	# The file format is simple: "SHA256(archive_name)= hash"
	local hash
	hash=$(awk '{print $NF}' "$checksum_file")
	rm -f "$checksum_file"

	if [[ -n "$hash" ]]; then
		echo "$hash"
		return 0
	else
		log_warn "Could not parse checksum from $checksum_url."
		return 1
	fi
}
