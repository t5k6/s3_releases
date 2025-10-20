# Find the latest build for a given profile
build_find_latest_for_profile() {
	local profile_file="$1"
	err_push_context "build_find_latest_for_profile:$profile_file"
	local toolchain buildcamname

	err_validate_file_exists "$profdir/$profile_file" "Profile file"

	# Load profile to get toolchain using the unified config manager
	if ! cfg_load_file "profile" "$profdir/$profile_file"; then
		log_error "Failed to load profile: $profdir/$profile_file"
		err_pop_context
		return 1
	fi
	toolchain=$(cfg_get_value "profile" "toolchain")

	# Find newest build by date for toolchain using subshell to avoid side effects
	buildcamname="$(cd "$bdir" && find . -type f \( -iname "*$toolchain*" ! -iname "*list_smargo" ! -iname "*.zip" \) -printf '%T@ %p\n' | sort -n | tail -1 | cut -f2- -d" " | sed 's@./@@g')"

	if [ -z "$buildcamname" ] || [ -z "$toolchain" ]; then
		return 1
	fi

	echo "$buildcamname"
}

# Format bytes into a human-readable string (KB, MB)
file_format_bytes() {
	local bytes="$1"
	if ((bytes < 1024)); then
		echo "${bytes}B"
	elif ((bytes < 1024 * 1024)); then
		# Use awk for floating point division to get one decimal place
		awk -v b="$bytes" 'BEGIN{printf "%.1fKB", b/1024}'
	else
		awk -v b="$bytes" 'BEGIN{printf "%.1fMB", b/1024/1024}'
	fi
}

# Get file size in bytes
file_get_size_bytes() {
	local file_path="$1"
	if [[ ! -f "$file_path" ]]; then
		echo "0"
		return 1
	fi
	stat -c%s "$file_path"
}

# Get file modification time in YYYY-MM-DD HH:MM:SS format
file_get_mtime_formatted() {
	local file_path="$1"
	if [[ ! -f "$file_path" ]]; then
		echo ""
		return 1
	fi
	# stat's %y format is YYYY-MM-DD HH:MM:SS.nanoseconds timezone
	# We just need the date and time part by cutting at the first period.
	stat -c %y "$file_path" | cut -d'.' -f1
}
