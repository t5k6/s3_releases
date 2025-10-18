#!/bin/bash

# =============================================================================
# SIMPLEBUILD3 - File Operations Abstraction Layer
# =============================================================================
# Provides unified file/archive operations with consistent error handling.
# Replaces direct tar, unzip, and other archive manipulation commands.
# =============================================================================

# ------------------------------------------------------------------------------
# CORE ARCHIVE FUNCTIONS
# ------------------------------------------------------------------------------

file_extract_archive() {
	# Extract an archive file to a specified destination
	local archive_file="$1"
	local dest_path="${2:-.}"
	local progress_callback="${3:-}"

	err_init "Archive extraction from $archive_file"

	err_validate_file_exists "$archive_file" "Archive extraction"

	if [ -z "$dest_path" ]; then
		err_log_and_exit "Destination path not specified" "$EXIT_INVALID_CONFIG"
	fi

	if [ ! -d "$dest_path" ]; then
		mkdir -p "$dest_path" || err_log_and_exit "Failed to create destination directory: $dest_path"
	fi

	log_debug "Extracting $archive_file to $dest_path"

	local extract_cmd=""
	# Detect archive type based on extension or basic signature content
	if [[ "$archive_file" =~ \.(tar\.gz|tgz)$ ]] || tar -tzf "$archive_file" >/dev/null 2>&1; then
		extract_cmd="tar -xzf \"$archive_file\" -C \"$dest_path\""
	elif [[ "$archive_file" =~ \.(tar\.bz2|tbz2)$ ]] || tar -tjf "$archive_file" >/dev/null 2>&1; then
		extract_cmd="tar -xjf \"$archive_file\" -C \"$dest_path\""
	elif [[ "$archive_file" =~ \.(tar\.xz|txz)$ ]] || tar -tJf "$archive_file" >/dev/null 2>&1; then
		extract_cmd="tar -xJf \"$archive_file\" -C \"$dest_path\""
	elif [[ "$archive_file" =~ \.tar$ ]] || tar -tf "$archive_file" >/dev/null 2>&1; then
		extract_cmd="tar -xf \"$archive_file\" -C \"$dest_path\""
	elif [[ "$archive_file" =~ \.zip$ ]] || unzip -l "$archive_file" >/dev/null 2>&1; then
		extract_cmd="unzip -q \"$archive_file\" -d \"$dest_path\""
	else
		err_log_and_exit "Unsupported or unrecognized archive format: $archive_file" "$EXIT_INVALID_CONFIG"
	fi

	# Execute extraction, optionally piping through a progress callback (like ui_show_progressbox)
	if [ -n "$progress_callback" ]; then
		{ eval "$extract_cmd"; } 2>&1 | eval "$progress_callback"
	else
		eval "$extract_cmd"
	fi

	err_check_command_result "$?" "Archive extraction: $archive_file"
}

file_create_archive() {
	# Create an archive from a file or directory
	local archive_file="$1"
	local source_path="$2"

	err_init "Archive creation to $archive_file"

	if [ -z "$archive_file" ]; then
		err_log_and_exit "Archive filename not specified" "$EXIT_INVALID_CONFIG"
	fi

	err_validate_file_exists "$source_path" "Archive creation source"

	log_debug "Creating archive $archive_file from $source_path"

	mkdir -p "$(dirname "$archive_file")" || err_log_and_exit "Failed to create parent directory for archive"

	# Determine archive type from requested filename extension
	if [[ "$archive_file" =~ \.(tar\.gz|tgz)$ ]]; then
		tar -czf "$archive_file" -C "$(dirname "$source_path")" "$(basename "$source_path")"
	elif [[ "$archive_file" =~ \.(tar\.bz2|tbz2)$ ]]; then
		tar -cjf "$archive_file" -C "$(dirname "$source_path")" "$(basename "$source_path")"
	elif [[ "$archive_file" =~ \.(tar\.xz|txz)$ ]]; then
		tar -cJf "$archive_file" -C "$(dirname "$source_path")" "$(basename "$source_path")"
	elif [[ "$archive_file" =~ \.tar$ ]]; then
		tar -cf "$archive_file" -C "$(dirname "$source_path")" "$(basename "$source_path")"
	elif [[ "$archive_file" =~ \.zip$ ]]; then
		(cd "$(dirname "$source_path")" && zip -q -r "$(basename "$archive_file")" "$(basename "$source_path")")
	else
		err_log_and_exit "Unsupported output archive format: $archive_file" "$EXIT_INVALID_CONFIG"
	fi

	err_check_command_result "$?" "Archive creation"
}

# ------------------------------------------------------------------------------
# LEGACY WRAPPERS (Refactored to use new core functions)
# ------------------------------------------------------------------------------

tar_cam() {
	local binary_name="$1"
	# Optional second argument for additional files to include, handled by just
	# archiving the main binary for now to maintain simple abstraction.
	# If complex multi-file archiving is needed, file_create_archive needs extension.

	local source_file="$bdir/$binary_name"
	local archive_file="$adir/${binary_name}.tar.gz"

	log_info "Archiving binary: $binary_name"

	if [[ ! -f "$source_file" ]]; then
		log_error "Cannot archive: Binary not found at $source_file"
		return 1
	fi

	if file_create_archive "$archive_file" "$source_file"; then
		log_info "Archive created successfully: $archive_file"
		return 0
	else
		log_error "Failed to create archive for $binary_name"
		return 1
	fi
}

tar_cam_gui() {
	# GUI wrapper for tar_cam, ensuring output works with progress boxes if needed.
	# Currently just calls the main function as it now uses standard logging.
	tar_cam "$1" "$2"
}
