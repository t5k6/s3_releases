# Find the latest build for a given profile
find_latest_build_for_profile() {
	local profile_file="$1"
	local toolchain buildcamname

	if [ ! -f "$profdir/$profile_file" ]; then
		log_error "Profile file not found: $profdir/$profile_file"
		return 1
	fi

	# Load profile to get toolchain using the unified config manager
	if ! cfg_load_file "profile" "$profdir/$profile_file"; then
		log_error "Failed to load profile: $profdir/$profile_file"
		return 1
	fi
	toolchain=$(cfg_get_value "profile" "toolchain")

	cd "$bdir"
	# Find newest build by date for toolchain
	buildcamname="$(find . -type f \( -iname "*$toolchain*" ! -iname "*list_smargo" ! -iname "*.zip" \) -printf '%T@ %p\n' | sort -n | tail -1 | cut -f2- -d" " | sed 's@./@@g')"
	cd "$workdir"

	if [ -z "$buildcamname" ] || [ -z "$toolchain" ]; then
		return 1
	fi

	echo "$buildcamname"
}

# Generalized function to build a library (used for refactoring build logic later)
build_library() {
	local title="$1" libsrcdir="$2" logfile="$3"
	shift 3
	local tasks=("$@")

	_build_library "$title" "$libsrcdir" "$logfile" "${tasks[@]}"
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
