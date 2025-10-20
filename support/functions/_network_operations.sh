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

	if [[ -z "$user_host" || -z "$remote_command" ]]; then
		log_error "net_ssh_execute requires user_host and remote_command."
		return 1
	fi

	log_debug "Executing on $user_host (port $port): $remote_command"

	# Execute command. The calling function is responsible for validation.
	ssh -o BatchMode=yes \
		-o ConnectTimeout="$NET_DEFAULT_TIMEOUT" \
		-o StrictHostKeyChecking=no \
		-o UserKnownHostsFile=/dev/null \
		-p "$port" \
		"$user_host" \
		"$remote_command"
}

net_scp_upload() {
	# Upload file to remote host via SCP
	local local_file="$1"
	local user_host="$2"
	local remote_path="$3"
	local port="${4:-$NET_SSH_PORT_DEFAULT}"

	if [[ -z "$local_file" || -z "$user_host" || -z "$remote_path" ]]; then
		log_error "net_scp_upload requires local_file, user_host, and remote_path."
		return 1
	fi

	log_debug "Uploading $local_file to $user_host:$remote_path (port $port)"

	scp -P "$port" \
		-o BatchMode=yes \
		-o ConnectTimeout="$NET_DEFAULT_TIMEOUT" \
		-o StrictHostKeyChecking=no \
		-o UserKnownHostsFile=/dev/null \
		"$local_file" \
		"$user_host:$remote_path"
}

net_scp_download() {
	# Download file from remote host via SCP
	local user_host="$1"
	local remote_file="$2"
	local local_path="$3"
	local port="${4:-$NET_SSH_PORT_DEFAULT}"

	if [[ -z "$user_host" || -z "$remote_file" || -z "$local_path" ]]; then
		log_error "net_scp_download requires user_host, remote_file, and local_path."
		return 1
	fi

	log_debug "Downloading $user_host:$remote_file to $local_path (port $port)"

	scp -P "$port" \
		-o BatchMode=yes \
		-o ConnectTimeout="$NET_DEFAULT_TIMEOUT" \
		-o StrictHostKeyChecking=no \
		-o UserKnownHostsFile=/dev/null \
		"$user_host:$remote_file" \
		"$local_path"
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

	if [[ -z "$user_host" ]]; then
		log_error "net_test_connection requires a user_host."
		return 1
	fi

	log_debug "Testing SSH connection to $user_host:$port"

	# Try simple echo command to test connection. The return code of net_ssh_execute is passed through.
	if net_ssh_execute "$user_host" "echo 'Connection test successful'" "$port" >/dev/null 2>&1; then
		log_info "SSH connection to $user_host successful."
		return 0
	else
		# The calling validate_command will log the failure, so we don't log "failed" here
		# to avoid duplicate messages. We just return the error code.
		return 1
	fi
}

net_check_url() {
	# Check HTTP/HTTPS URL connectivity
	local url="$1"
	local timeout="${2:-$NET_DEFAULT_TIMEOUT}"

	if [[ -z "$url" ]]; then
		log_error "net_check_url requires a URL."
		return 1
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
		log_warn "URL is not reachable: $url (cURL exit: $curl_exit, HTTP status: $http_code)"
		return 1
	fi
}

net_download_file() {
	err_push_context "net_download_file:$2"
	# Download file from URL with progress display support
	local url="$1"
	local output_file="$2"
	local progress_callback="${3:-}"

	if [[ -z "$url" || -z "$output_file" ]]; then
		log_error "net_download_file requires a URL and output file path."
		err_pop_context
		return 1
	fi

	log_debug "Downloading $url to $output_file"

	if [[ -n "$progress_callback" ]]; then
		{ wget -O "$output_file" --progress=dot:giga "$url" 2>&1; } |
			grep --line-buffered -o '[0-9]\+%' | sed -u 's/%//' | eval "$progress_callback"
	else
		# Use wget with progress display
		wget --progress=bar:force -q --show-progress "$url" -O "$output_file"
	fi

	local exit_code="${PIPESTATUS[0]}"
	err_pop_context
	return "$exit_code"
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

	# Abstraction: Get URL from the Unified Configuration Manager (UCM).
	local softcam_url
	softcam_url=$(cfg_get_value "urls" "URL_SOFTCAM_KEY")

	if [[ -z "$softcam_url" ]]; then
		log_error "URL for SoftCam.Key is not defined in the 'urls' configuration."
		err_pop_context
		return 1
	fi

	local dest_file="$dest_dir/SoftCam.Key"
	if ! validate_command "Downloading SoftCam.Key" net_download_file "$softcam_url" "$dest_file"; then
		log_error "Failed to download SoftCam.Key from $softcam_url"
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

	# Use grep to extract the 64-character hex hash, which is
	# format-agnostic and works for both old and new checksum file styles.
	local hash
	hash=$(grep -oE '[0-9a-f]{64}' "$checksum_file")
	rm -f "$checksum_file"

	# Validation to ensure we got a real hash, not HTML from a 404 page.
	if [[ "$hash" =~ ^[0-9a-f]{64}$ ]]; then
		echo "$hash"
		return 0
	else
		log_error "Could not parse a valid SHA256 hash from '$checksum_url'. The file may not exist or the format is unexpected."
		return 1
	fi
}

# Fetches a sorted list of stable OpenSSL release versions from the official git repo.
# Caches the result in a temp file to avoid repeated network calls.
net_get_openssl_versions() {
	local cache_file="/tmp/s3_openssl_versions_cache"
	# Use cache if it's less than a day old to be a good network citizen
	if [[ -f "$cache_file" && -n "$(find "$cache_file" -mtime -1)" ]]; then
		cat "$cache_file"
		return 0
	fi

	log_info "Fetching available OpenSSL versions from git..."
	local openssl_git_url="https://github.com/openssl/openssl.git"

	# Use git ls-remote to get all tags without cloning the repo.
	# Sort by version number descending.
	# Filter for stable 1.1.1 series (e.g., openssl-1.1.1w) and 3.x series (e.g., openssl-3.0.13)
	# Use awk to clean up the tag name.
	git ls-remote --tags --sort=-v:refname "$openssl_git_url" |
		grep -E 'refs/tags/openssl-(1\.1\.1[a-z]$|[3-9]+\.[0-9]+\.[0-9]+$)' |
		awk -F'/' '{print $3}' |
		sed 's/^openssl-//' >"$cache_file"

	if [[ ! -s "$cache_file" ]]; then
		log_error "Could not retrieve OpenSSL versions. Check network or git installation."
		return 1
	fi
	cat "$cache_file"
}

# Checks for GitHub API rate limiting.
net_check_github_api_limit() {
	local min_requests="$1"
	local limit remaining reset reset_time
	local api_reply_file
	api_reply_file=$(mktemp)
	trap 'rm -f "$api_reply_file"' RETURN

	if ! validate_command "Querying GitHub API" curl --silent "${CURL_GITHUB_TOKEN:-}" "https://api.github.com/rate_limit" -o "$api_reply_file"; then
		log_warn "Could not query GitHub API rate limit."
		return 1 # Assume OK if check fails
	fi

	limit=$(jq -r '.resources.core.limit' "$api_reply_file")
	remaining=$(jq -r '.resources.core.remaining' "$api_reply_file")
	reset=$(jq -r '.resources.core.reset' "$api_reply_file")
	reset_time=$(date -d @"$reset")

	if [[ "$remaining" -lt "$min_requests" ]]; then
		log_warn "GitHub API request limit is low ($remaining/$limit). You may be rate-limited. Limit resets at: $reset_time"
		return 0 # 0 means limit is low (true)
	else
		log_debug "GitHub API limit is sufficient ($remaining/$limit)."
		return 1 # 1 means limit is fine (false)
	fi
}
