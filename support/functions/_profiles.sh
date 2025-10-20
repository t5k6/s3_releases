#!/bin/bash

sys_show_profiles() {
	_list_profiles
	return 0
}

_list_profiles() {
	cd "$profdir"
	profiles=(*.profile)
	if [ ${#profiles[@]} -gt 0 ]; then
		printf "$c_l"
		clear
		slogo
		printf "$y_l\n  $txt_profiles $txt_found $txt_for ( ./$(basename "$0") \"tcname\" -p=name.profile )\n"
		echo -e "$w_l  ======================================================\n"
		i=0
		for e in "${profiles[@]}"; do
			((i++))
			printf "$w_l  ($i) > $e\n"
		done
	fi
	printf "\n$rs_"
}

build_export_legacy_profile() {
	err_push_context "build_export_legacy_profile"

	# This function saves from the live repository state to a legacy .profile file
	# for backward compatibility or user editing.
	local profile_name
	profile_name=$(ui_get_input "Save Build Profile" "Enter a name for this profile (legacy .profile format):" "$_toolchainname")

	if [[ -z "$profile_name" ]]; then
		log_info "Profile export cancelled by user."
		err_pop_context
		return 0
	fi

	# Get all currently enabled modules and USE_vars to build the profile content
	local enabled_modules use_vars_string
	enabled_modules=$("${repodir}/config.sh" -s)
	local -a use_vars_temp=()
	for key in "${!USE_vars[@]}"; do
		[[ -n "${USE_vars[$key]}" ]] && use_vars_temp+=("$key")
	done
	use_vars_string="${use_vars_temp[*]}"

	# Convert long module names into their short forms for the profile file
	local profile_content
	profile_content=$(echo "$enabled_modules $use_vars_string" | sed -e 's/CARDREADER_//g;s/READER_//g;s/MODULE_//g;s/HAVE_//g;s/WEBIF_//g;s/WITH_//g;s/CS_//g;s/_CHARSETS//g;s/CW_CYCLE_CHECK/CWCC/g;s/SUPPORT//g;')

	local profile_path="$profdir/$profile_name.profile"
	if ! printf "%s\n" "$profile_content" >"$profile_path"; then
		log_error "Failed to write profile to '$profile_path'."
		ui_show_msgbox "Error" "Failed to save profile file."
		err_pop_context
		return 1
	fi

	log_info "Legacy profile exported successfully: $profile_path"
	ui_show_msgbox "Success" "Profile '$profile_name.profile' has been exported."
	err_pop_context
}

build_import_legacy_profile() {
	err_push_context "build_import_legacy_profile"
	cd "$profdir"
	local p_files
	p_files=(*.profile)

	if [[ ${#p_files[@]} -eq 0 || ! -f "${p_files[0]}" ]]; then
		ui_show_msgbox "Profile" "$txt_no_profile_found"
		err_pop_context
		return
	fi

	menu_init "$txt_select_profile_title" "$txt_select_profile_title"
	for e in "${p_files[@]}"; do
		menu_add_option "$e" "$e"
	done

	local pselect
	if menu_show_list; then
		pselect="$(menu_get_first_selection)"
	else
		err_pop_context
		return # User cancelled
	fi

	ui_show_msgbox "$txt_confirm_profile_select" "$pselect"

	if [[ -f "$profdir/$pselect" ]]; then
		local profile_vars
		profile_vars=$(cat "$profdir/$pselect")

		# Convert short module names from profile back to long names
		local -a modules_to_enable=()
		local -a use_vars_to_set=()

		for item in $profile_vars; do
			# Check if it's a USE_var
			if [[ -v "USE_vars[$item]" ]]; then
				use_vars_to_set+=("$item")
			else
				# Assume it's a short module name
				local long_name
				long_name=$(build_get_module_long_name "$item")
				[[ -n "$long_name" ]] && modules_to_enable+=("$long_name")
			fi
		done

		# Instead of applying changes directly, save them to the canonical build config file.
		local namespace="build_profile:$_toolchainname"
		cfg_set_value "$namespace" "enabled_modules" "${modules_to_enable[*]}"
		cfg_set_value "$namespace" "use_vars" "${use_vars_to_set[*]}"
		# This is a global from _toolchain.sh, clear it when loading a profile.
		stapivar=""
		cfg_set_value "$namespace" "stapivar" ""

		if cfg_save_file "$namespace" "$menudir/$_toolchainname.cfg"; then
			log_info "Legacy profile '$pselect' imported and saved to modern config format."
			load_config
		else
			log_error "Failed to save imported profile to UCM config."
		fi
	fi
	err_pop_context
}

sys_create_native_toolchain_profile() {
	local ns="toolchain:native"
	local gcc_machine gcc_ver

	# Detect binaries safely
	gcc_machine=$(gcc -dumpmachine 2>/dev/null || echo "unknown")
	gcc_ver=$(gcc --version | head -n1 2>/dev/null || echo "unknown")

	# Set symlinks (unchanged)
	[ ! -d "$tcdir/native/bin" ] && mkdir -p "$tcdir/native/bin"
	cd "$tcdir/native/bin"
	g="$(type -pf gcc)"
	gpp="$(type -pf g++)"
	stripvar="$(type -pf strip)"
	objcopy="$(type -pf objcopy)"
	objdump="$(type -pf objdump)"
	if [ -f "$g" ]; then
		compiler_link="$($g -dumpmachine)-gcc"
		[ -L "$compiler_link" ] || ln -sf "$g" "$compiler_link"
	fi
	if [ -f "$gpp" ]; then
		gpp_link="$($g -dumpmachine)-g++"
		[ -L "$gpp_link" ] || ln -sf "$gpp" "$gpp_link"
	fi
	if [ -f "$stripvar" ]; then
		strip_link="$($g -dumpmachine)-strip"
		[ -L "$strip_link" ] || ln -sf "$stripvar" "$strip_link"
	fi
	if [ -f "$objcopy" ]; then
		objcopy_link="$($g -dumpmachine)-objcopy"
		[ -L "$objcopy_link" ] || ln -sf "$objcopy" "$objcopy_link"
	fi
	if [ -f "$objdump" ]; then
		objdump_link="$($g -dumpmachine)-objdump"
		[ -L "$objdump_link" ] || ln -sf "$objdump" "$objdump_link"
	fi

	# Use UCM for config
	cfg_set_value "$ns" "_toolchainname" "native"
	cfg_set_value "$ns" "default_use" "USE_LIBCRYPTO"
	cfg_set_value "$ns" "_oscamconfdir_default" "/usr/local/etc"
	cfg_set_value "$ns" "_oscamconfdir_custom" "not_set"
	cfg_set_value "$ns" "_compiler" "${gcc_machine}-"
	cfg_set_value "$ns" "_tc_info" "Native System Compiler ${gcc_ver}"
	cfg_set_value "$ns" "_libsearchdir" "/lib"
	cfg_set_value "$ns" "_menuname" "native"
	cfg_set_value "$ns" "_sysroot" "/usr/include"

	if cfg_save_file "$ns" "$tccfgdir/native"; then
		log_info "Native toolchain profile created via UCM."
	else
		log_fatal "Failed to create native profile." "$EXIT_ERROR"
	fi
}
