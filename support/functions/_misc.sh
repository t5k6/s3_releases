#!/bin/bash

sys_exit() {
	err_push_context "sys_exit"
	log_info "SimpleBuild3 is shutting down."
	clear
	ui_show_s3_logo
	# The global EXIT trap handles cleanup automatically.
	exit 0
}

ui_show_newline() {
	log_plain "$re_"
}

sys_edit_s3_config() {
	ui_edit_s3_config
	sys_exit
}

sys_calc_time_diff() {
	Tcalc="$((Te - Ts))"
}
sys_print_time_diff() {
	err_push_context "sys_print_time_diff"
	sys_calc_time_diff
	validate_command "Printing build time" printf "\n |  TIME  >\t[ $txt_buildtime $((Tcalc / 60)) min(s) $((Tcalc % 60)) secs ]\n"
	err_pop_context
}
sys_timer_stop() {
	Te="$(date +%s)"
}

# Determines if a given binary file can be executed on the current host system.
# Takes into account cross-compilation scenarios.
# Returns 0 (true) if runnable, 1 (false) otherwise.
sys_validate_binary_runnable() {
	local binary_path="$1"
	err_push_context "sys_validate_binary_runnable:$binary_path"

	validate_command "Checking binary exists and is executable" [[ -x "$binary_path" ]] || {
		err_pop_context
		return 1
	}

	# 2. Get host architecture using the standard 'uname' command.
	local host_arch
	host_arch=$(uname -m)

	# 3. Robustly parse the binary's architecture using 'file' and a case statement.
	local binary_arch="unknown"
	local file_output
	validate_command "Retrieving binary architecture" file_output=$(file -b "$binary_path") || {
		log_warn "Could not determine binary architecture, assuming cross-compiled."
		err_pop_context
		return 1
	}

	case "$file_output" in
	*86-64* | *amd64*) binary_arch="x86_64" ;;
	*i[3-6]86*) binary_arch="i686" ;;
	*ARM*aarch64*) binary_arch="aarch64" ;;
	*ARM*) binary_arch="arm" ;;
	*MIPS*) binary_arch="mips" ;;
	*PowerPC* | *ppc*) binary_arch="ppc" ;;
	esac

	# 4. Perform the compatibility check.
	if [[ "$host_arch" == "$binary_arch" ]]; then
		err_pop_context
		return 0 # Exact match, runnable.
	elif [[ "$host_arch" == "x86_64" && "$binary_arch" == "i686" ]]; then
		err_pop_context
		return 0 # 64-bit x86 host can run 32-bit x86 binary, runnable.
	fi

	# If none of the above, it's a cross-compiled binary and not runnable.
	err_pop_context
	return 1
}

# Consolidated post-build artifact handling.
# Performs TAR generation (if enabled), diagnostics, and extra copy to binaries dir.
build_finalize_and_archive() {
	local binary_name="$1"
	local mode="${2:-cli}"    # "gui" for progress UI, "cli" otherwise
	local toolchain_name="$3" # For logging cross-compilation messages
	err_push_context "build_finalize_and_archive: $binary_name"

	local binary_path="$bdir/$binary_name"

	# Handle USE_DIAG with cross-compilation-aware check
	if [[ "$(cfg_get_value "s3" "USE_DIAG" "0")" == "1" && -x "$binary_path" ]]; then
		if sys_validate_binary_runnable "$binary_path"; then
			local diag_log="$ldir/diag_$(date +%F_%H-%M-%S)_${binary_name}.log"
			log_info "Generating runtime diagnostics for '$binary_name'"
			if validate_command "Running diagnostics" "$binary_path" -h >"$diag_log" 2>&1; then
				log_info "Diagnostics saved to $diag_log"
			fi
		else
			log_info "Skipping runtime diagnostics: Binary '$binary_name' is not runnable on this host."
		fi
	fi

	# Handle EXTRA_COPY_DIR to copy to working directory
	if [[ "$(cfg_get_value "s3" "EXTRA_COPY_DIR" "0")" == "1" ]]; then
		log_info "Copying artifact to extra directory: $here_"
		if ! validate_command "Copying artifact" cp "$binary_path" "$here_/"; then
			log_warn "Failed to copy artifact to extra directory."
		fi
	fi

	# TAR generation based on configuration
	if [[ "$(cfg_get_value "s3" "USE_TARGZ" "0")" == "1" ]]; then
		log_info "Generating TAR archive"
		local tar_name="${binary_name}.tar.gz"
		local tar_path="$adir/$tar_name"
		local temp_tar_dir=$(mktemp -d)
		cp "$binary_path" "$temp_tar_dir/"
		if [[ "${CUSTOM_CONFDIR:-}" != "not_set" && -d "$CUSTOM_CONFDIR" ]]; then
			validate_command "Including confdir in TAR" cp -r "$CUSTOM_CONFDIR" "$temp_tar_dir/oscam-conf"
		fi
		local progress=""
		[[ "$mode" == "gui" ]] && progress="ui_show_progressbox 'Creating TAR Archive'"
		if file_create_archive "$tar_path" "$temp_tar_dir" "$progress"; then
			log_info "TAR created: $tar_path"
		else
			log_warn "TAR creation failed"
		fi
		rm -rf "$temp_tar_dir"
	fi

	err_pop_context
}

sys_timer_start() {
	Ts="$(date +%s)"
}
sys_decode_base64() {
	local input="$1"
	if [[ -z "$input" ]]; then
		log_error "sys_decode_base64 was called with an empty string."
		return 1
	fi

	# The `-d` flag is not portable, `--decode` is.
	if ! decoded_val=$(printf "%s" "$input" | base64 --decode 2>/dev/null); then
		log_error "Failed to decode a base64 string. The string may be corrupt."
		return 1
	fi
	printf "%s" "$decoded_val"
}
build_get_module_long_name() {
	printf "%s" "${INTERNAL_MODULES[$1]}"
}

sys_get_arch_type() {
	case "$(uname -m)" in
	x86 | x86_64 | amd64 | i686)
		echo "ok"
		;;
	*)
		echo "bad"
		;;
	esac
}

build_generate_oscam_name() {
	cd "${repodir}" || return 1
	# Read toolchain config from UCM
	local _toolchainname
	_toolchainname=$(cfg_get_value "toolchain" "_toolchainname")
	local _compiler
	_compiler=$(cfg_get_value "toolchain" "_compiler")

	local enabled_modules
	enabled_modules=$("${repodir}/config.sh" -s)

	local _dvbapi=""
	[[ " ${enabled_modules} " =~ " HAVE_DVBAPI " ]] && _dvbapi="-dvbapi"
	[[ " ${enabled_modules} " =~ " CARDREADER_GXAPI " ]] && _dvbapi="-gxapi"

	local _webif=""
	[[ " ${enabled_modules} " =~ " WEBIF " ]] && _webif="-webif"

	local _ssl=""
	[[ " ${enabled_modules} " =~ " WITH_SSL " ]] && _ssl="-ssl"

	local _emu=""
	[[ " ${enabled_modules} " =~ " WITH_EMU " ]] && _emu="-emu"

	local _neon=""
	if [[ " ${enabled_modules} " =~ " WITH_ARM_NEON " ]]; then
		"$tcdir/$_toolchainname/bin/$_compiler""gcc" -dumpmachine 2>/dev/null | grep -q -iE '(arm|aarch64)' && _neon="-neon"
	fi

	local _icam=""
	[[ " ${enabled_modules} " =~ " MODULE_STREAMRELAY " ]] && _icam="-icam"

	local _ipv6=""
	[[ " ${enabled_modules} " =~ " IPV6SUPPORT " ]] && _ipv6="-ipv6"

	local _signed=""
	[[ " ${enabled_modules} " =~ " WITH_SIGNING " ]] && _signed="-signed"

	local _upx=''
	[ "${USE_vars[USE_COMPRESS]}" == "1" ] && _upx="-upx"
	local _b_name
	[ "$_toolchainname" == "native" ] && _b_name="$(uname -s)-$(uname -m)" || _b_name="$_toolchainname"
	local rev commit
	rev=$(repo_get_revision)
	commit=$(repo_get_commit)
	if [ "$(cfg_get_value "s3" "ADD_PROFILE_NAME" "0")" == "0" ] || [ "$pf_name" == "not_set" ]; then
		oscam_name="oscam-${REPO}${rev}$(repo_is_git && printf "@${commit}" || printf "")-${_b_name}${_webif}${_dvbapi}${_ssl}${_usb}${_pcsc}${_dvbcsa}${_stapi}${_stapi5}${_emu}${_ipv6}${_icam}${_neon}$2${_upx}${_signed}"
	else
		oscam_name="oscam-${REPO}${rev}$(repo_is_git && printf "@${commit}" || printf "")-${pf_name%.*}"
	fi
}

sys_show_info() {
	log_header "SYSTEM"
	local system_info
	system_info=$(type -pf lsb_release)
	[ ${#system_info} -ge 11 ] && lsb_release -irc
	log_plain "Uptime:\t\t$(uptime -p)"
	log_header "MEMORY"
	free -mht | awk '/Mem/{print "Memory:\t\tTotal: " $2 "\tUsed: " $3 "\tFree: " $4} /Swap/{print "Swap:\t\tTotal: " $2 "\tUsed: " $3 "\tFree: " $4 }'
	[ -f /sys/dev/block ] && lsblk
	log_header "CPU"
	local cpu_info
	cpu_info=$(type -pf lscpu)
	[ ${#cpu_info} -ge 5 ] && lscpu | grep -iE 'model name|vendor id|Architecture|per socket|MHz'
	log_header "Network"
	log_plain "Hostname:\t$HOSTNAME"
	ip -o addr | awk '/inet /{print "IP (" $2 "):\t" $4}'
	ip route | awk '/default/ { printf "Gateway:\t"$3"\n" }'
	awk '/^nameserver/{ printf "Name Server:\t" $2 "\n"}' /etc/resolv.conf
	ui_show_newline
}

build_ensure_openssl() {
	local sysroot="$1"
	local toolchain_path="$2" # This is the path to the toolchain's root, e.g. .../toolchains/oe20_armv7
	local cc="$3"             # This is the full compiler name, e.g. .../bin/arm-linux-gcc
	local openssl_version
	openssl_version=$(cfg_get_value "s3" "S3_OPENSSL_VERSION" "1.1.1w")

	err_push_context "build_ensure_openssl"

	if [[ ! -d "$sysroot/usr/include" ]]; then
		validate_command "Creating include directory in sysroot" mkdir -p "$sysroot/usr/include"
	fi

	# Check if a key header file exists
	if [[ -f "$sysroot/usr/include/openssl/ssl.h" && -f "$sysroot/usr/lib/libcrypto.a" ]]; then
		log_info "OpenSSL found in toolchain sysroot. Skipping build."
		err_pop_context
		return 0
	fi

	log_warn "OpenSSL not found in toolchain sysroot. Attempting to build it."
	ui_show_msgbox "Missing Dependency" "OpenSSL development files are missing in this toolchain.\n\nSimpleBuild will now attempt to download and compile OpenSSL $openssl_version. This may take a while." 10 70

	# The prefix is the final sysroot, the build function handles staging.
	local prefix="$sysroot"
	local cflags="--sysroot=$sysroot"
	local ldflags="--sysroot=$sysroot -L$sysroot/lib"

	if ! build_openssl "$openssl_version" "$sysroot" "$cflags" "$ldflags" "$toolchain_path" "$cc"; then
		log_fatal "Failed to build and install OpenSSL for the toolchain." "$EXIT_ERROR"
	fi

	log_info "OpenSSL has been successfully built and installed into the toolchain sysroot."
	err_pop_context
	return 0
}

ui_show_main_menu() {
	err_push_context "ui_show_main_menu"
	while true; do
		menu_init "SimpleBuild3 Main Menu" "SimpleBuild3 Main Menu"
		menu_add_option "BUILD" "Build OScam"
		menu_add_separator
		menu_add_option "REPO" "Manage Repository"
		menu_add_option "TOOLCHAINS" "Manage Toolchains"
		menu_add_option "SYSTEM" "System & Configuration"
		menu_add_separator
		menu_add_option "UPDATE_S3" "Update SimpleBuild"
		menu_add_option "EXIT" "Exit"

		if ! menu_show_list; then
			sys_exit # User pressed Cancel or ESC
		fi

		local selection
		selection="$(menu_get_first_selection)"

		case "$selection" in
		BUILD)
			# This is the primary entry into the build workflow.
			# It directly calls the new selection menu.
			ui_show_toolchain_selection_menu
			;;
		REPO) ui_show_repository_menu ;;                 # Implemented below
		TOOLCHAINS) ui_show_toolchain_management_menu ;; # Implemented in _toolchain.sh
		SYSTEM) ui_show_system_config_menu ;;            # Implemented below
		UPDATE_S3) sys_update_self ;;
		EXIT) sys_exit ;;
		esac
	done
	err_pop_context
}

# Menu to manage the source code repository.
ui_show_repository_menu() {
	err_push_context "ui_show_repository_menu"
	while true; do
		menu_init "Repository Management" "Repository Management"
		menu_add_option "UPDATE" "Checkout/Update OScam Source"
		menu_add_option "CLEAN" "Clean Workspace (removes source & backups)"
		menu_add_option "RESTORE" "Restore Last Good Repository Backup"
		menu_add_separator
		menu_add_option "BACK" "Back to Main Menu"
		menu_add_option "EXIT" "Exit SimpleBuild"

		if ! menu_show_list; then return 0; fi
		local selection
		selection="$(menu_get_first_selection)"

		case "$selection" in
		UPDATE) repo_update ;;
		CLEAN) repo_clean ;;
		RESTORE) repo_restore "last-${REPO}${ID}" ;;
		BACK) return 0 ;;
		EXIT) sys_exit ;;
		esac
	done
	err_pop_context
}

# Menu for system and configuration tasks.
ui_show_system_config_menu() {
	err_push_context "ui_show_system_config_menu"
	while true; do
		menu_init "System & Configuration" "System & Configuration"
		menu_add_option "S3_CONFIG" "Edit SimpleBuild Config (simplebuild.config)"
		menu_add_option "SSH_PROFILES" "Edit SSH Upload Profiles"
		menu_add_option "SYSCHECK" "Run System Prerequisite Check"
		menu_add_separator
		menu_add_option "BACK" "Back to Main Menu"
		menu_add_option "EXIT" "Exit SimpleBuild"

		if ! menu_show_list; then return 0; fi
		local selection
		selection="$(menu_get_first_selection)"

		case "$selection" in
		S3_CONFIG) ui_edit_s3_config ;;
		SSH_PROFILES) ui_edit_ssh_profile ;;
		SYSCHECK) sys_run_checks_interactive "auto" "now" ;;
		BACK) return 0 ;;
		EXIT) sys_exit ;;
		esac
	done
	err_pop_context
}

# Post-build menu for upload options.
ui_show_post_build_menu() {
	local toolchain_name="$1"
	local binary_name="$2"
	err_push_context "Post-Build Menu"

	while true; do
		local -a compatible_profiles=()
		# Scan for compatible SSH profiles
		if [[ -d "$profdir" ]]; then
			for profile_path in "$profdir"/*.ssh; do
				if [[ -f "$profile_path" ]]; then
					# Use a unique namespace to avoid conflicts
					if cfg_load_file "profile_check" "$profile_path"; then
						local profile_tc
						profile_tc=$(cfg_get_value "profile_check" "toolchain")
						if [[ "$profile_tc" == "$toolchain_name" ]]; then
							compatible_profiles+=("$(basename "$profile_path")")
						fi
					fi
				fi
			done
		fi

		local menu_text="Build successful for '$toolchain_name'.\nBinary: $binary_name\n\nWhat would you like to do next?"
		menu_init "$menu_text" "Build Successful"

		if [[ ${#compatible_profiles[@]} -gt 0 ]]; then
			log_info "Found ${#compatible_profiles[@]} compatible upload profile(s)."
			for profile in "${compatible_profiles[@]}"; do
				menu_add_option "$profile" "Upload using profile: $profile"
			done
			menu_add_separator
			# Use more contextual text when profiles already exist.
			menu_add_option "CREATE_PROFILE" "Create another upload profile for '$toolchain_name'..."
		else
			menu_add_option "CREATE_PROFILE" "Create new upload profile for '$toolchain_name'..."
		fi

		menu_add_option "FINISH" "Finish and return to build menu"

		# Use an explicit width to prevent text from being cut off.
		# Also check the return code to handle ESC/Cancel. A fixed height prevents layout issues.
		if ! menu_show_list 15 70; then
			break # User pressed ESC or Cancel
		fi

		local selection
		selection="$(menu_get_first_selection)"

		case "$selection" in
		FINISH | "")
			break # Exit the post-build menu loop
			;;
		CREATE_PROFILE)
			# Pre-fill the toolchain name in the editor for better UX
			local new_profile_name
			new_profile_name=$(ui_edit_ssh_profile "" "$toolchain_name")
			if [[ -n "$new_profile_name" ]]; then
				log_info "New profile '$new_profile_name' created. Proceeding with upload."
				net_upload_cam_profile "$new_profile_name"
				break # Upload was attempted, exit the post-build menu
			else
				log_info "Profile creation was cancelled."
				# Loop continues, allowing user to choose another option
			fi
			;;
		*)
			# Any other selection is a profile name
			net_upload_cam_profile "$selection"
			break # Exit the loop after performing the upload.
			;;
		esac
	done

	err_pop_context
}

ui_edit_toolchain_confdir() {
	local toolchain_name="$1"
	err_push_context "Edit toolchain confdir for '$toolchain_name'"

	local config_path="$tccfgdir/$toolchain_name"
	if [[ ! -f "$config_path" ]]; then
		log_error "Toolchain configuration file not found: $config_path"
		err_pop_context
		return 1
	fi

	# Use Unified Configuration Manager for secure loading and saving
	if ! cfg_load_file "toolchain" "$config_path"; then
		log_warn "Could not load toolchain configuration for '$toolchain_name'"
		err_pop_context
		return 1
	fi

	local default_dir current_dir confdir
	default_dir=$(cfg_get_value "toolchain" "_oscamconfdir_default")
	current_dir=$(cfg_get_value "toolchain" "_oscamconfdir_custom")
	[[ "$current_dir" == "not_set" ]] && current_dir=""

	confdir=$(ui_get_input " -[ $toolchain_name Toolchain$(REPOIDENT) ]- " "Enter new CONF_DIR path. Default is '$default_dir'.\nLeave empty to use default." "$current_dir")

	# ui_get_input returns 1 on Cancel/ESC
	if [[ $? -eq 0 ]]; then
		if [[ -n "$confdir" ]]; then
			cfg_set_value "toolchain" "_oscamconfdir_custom" "$confdir"
		else # User cleared the input, revert to using the default
			cfg_set_value "toolchain" "_oscamconfdir_custom" "not_set"
		fi

		if ! cfg_save_file "toolchain" "$config_path"; then
			ui_show_msgbox "Error" "Failed to save updated toolchain configuration."
		fi
	fi
	err_pop_context
}
build_check_smargo_deps() {
	if [ -f "${repodir}/config.sh" ]; then
		if [ "$("${repodir}/config.sh" --enabled CARDREADER_SMARGO)" == "Y" ]; then
			USE_vars[USE_LIBUSB]="1"
		else
			USE_vars[USE_LIBUSB]=
		fi
	fi
}
build_check_streamrelay_deps() {
	if [ -f "${repodir}/config.sh" ]; then
		if [ "$("${repodir}/config.sh" --enabled MODULE_STREAMRELAY)" == "Y" ]; then
			USE_vars[USE_LIBDVBCSA]="1"
		else
			USE_vars[USE_LIBDVBCSA]=
		fi
	fi
}
build_check_signing() {
	local sign_config_file="$configdir/sign"
	if [[ ! -f "$sign_config_file" ]]; then
		return
	fi

	# Use UCM instead of directly sourcing the config file for security and consistency.
	if ! cfg_load_file "sign" "$sign_config_file"; then
		log_warn "Could not load signing configuration from '$sign_config_file'."
		return
	fi

	local x509cert privkey
	x509cert=$(cfg_get_value "sign" "x509cert")
	privkey=$(cfg_get_value "sign" "privkey")

	if [[ -f "$x509cert" && -f "$privkey" && -f "$repodir/config.sh" ]]; then
		if [[ "$("${repodir}/config.sh" --enabled WITH_SIGNING)" == "Y" ]]; then
			"${repodir}/config.sh" --add-cert "$x509cert" "$privkey"
			log_info "SIGNING: Using provided $(basename "$x509cert") and $(basename "$privkey") files"
		fi
	fi
}
build_set_type() {
	local toolchain_name="$1"
	local sysroot_path="$2"
	local statcount=0
	local libcount=0

	if [[ "$toolchain_name" == "native" ]]; then
		SEARCHDIR="/usr/lib /usr/local/lib /lib /usr/lib/x86_64-linux-gnu /usr/lib/i386-linux-gnu"
	else
		SEARCHDIR="$sysroot_path"
	fi

	# For each potential static library, check if static linking is requested.
	# If so, increment libcount. Then try to find the .a file and increment statcount on success.

	if [[ "${USE_vars[USE_STATIC]}" == "1" || "${USE_vars[STATIC_LIBCRYPTO]}" == "1" ]]; then
		((libcount++))
		local found_lib
		found_lib=$(find $SEARCHDIR -name "libcrypto.a" -type f -print -quit 2>/dev/null)
		if [[ -n "$found_lib" ]]; then
			LIBCRYPTO_LIB="LIBCRYPTO_LIB=$found_lib"
			((statcount++))
		fi
	fi

	if [[ "${USE_vars[USE_STATIC]}" == "1" || "${USE_vars[STATIC_SSL]}" == "1" ]]; then
		((libcount++))
		local found_lib
		found_lib=$(find $SEARCHDIR -name "libssl.a" -type f -print -quit 2>/dev/null)
		if [[ -n "$found_lib" ]]; then
			SSL_LIB="SSL_LIB=$found_lib"
			((statcount++))
		fi
	fi

	if [[ "${USE_vars[USE_STATIC]}" == "1" || "${USE_vars[STATIC_LIBUSB]}" == "1" ]]; then
		((libcount++))
		local found_lib
		found_lib=$(find $SEARCHDIR -name "libusb-1.0.a" -type f -print -quit 2>/dev/null)
		if [[ -n "$found_lib" ]]; then
			LIBUSB_LIB="LIBUSB_LIB=$found_lib"
			((statcount++))
		fi
	elif [[ "$(cfg_get_value "toolchain" "_androidndkdir")" == "1" ]]; then
		LIBUSB_LIB="LIBUSB_LIB=-lusb-1.0"
	fi

	if [[ "${USE_vars[USE_STATIC]}" == "1" || "${USE_vars[STATIC_PCSC]}" == "1" ]]; then
		((libcount++))
		local found_lib
		found_lib=$(find $SEARCHDIR -name "libpcsclite.a" -type f -print -quit 2>/dev/null)
		if [[ -n "$found_lib" ]]; then
			PCSC_LIB="PCSC_LIB=$found_lib"
			((statcount++))
		fi
	fi

	if [[ "${USE_vars[USE_STATIC]}" == "1" || "${USE_vars[STATIC_LIBDVBCSA]}" == "1" ]]; then
		((libcount++))
		local found_lib
		found_lib=$(find $SEARCHDIR -name "libdvbcsa.a" -type f -print -quit 2>/dev/null)
		if [[ -n "$found_lib" ]]; then
			LIBDVBCSA_LIB="LIBDVBCSA_LIB=$found_lib"
			((statcount++))
		fi
	fi

	# Determine buildtype based on counts.
	if [[ "$statcount" -gt 0 && "$statcount" -lt "$libcount" ]]; then
		log_info "BUILDTYPE: mixed"
		buildtype="-mixed"
	elif [[ "$libcount" -gt 0 && "$statcount" -eq "$libcount" ]]; then
		log_info "BUILDTYPE: static"
		buildtype="-static"
	else
		log_info "BUILDTYPE: dynamic"
		buildtype=""
	fi
}
cfg_reset_build_config() {
	if [ -f "${repodir}/config.sh" ]; then
		[ -f "$menudir/$_toolchainname.save" ] && rm -rf "$menudir/$_toolchainname.save"
		if [ ! -f "$ispatched" ]; then
			# Reset config and then check dependencies
			reset_="$("${repodir}/config.sh" -R)"
		fi
	else
		ui_show_main_menu
	fi
}
ui_edit_s3_config() {
	err_push_context "ui_edit_s3_config"

	# Part 1: Edit S3_LOG_LEVEL using a radiolist for single selection.
	menu_init "Select Log Level" "Edit SimpleBuild Config"
	local current_level
	current_level=$(cfg_get_value "s3" "S3_LOG_LEVEL" "2")

	menu_add_option "0" "Fatal only" "$([[ "$current_level" == "0" ]] && echo "on" || echo "off")"
	menu_add_option "1" "Fatal + Error" "$([[ "$current_level" == "1" ]] && echo "on" || echo "off")"
	menu_add_option "2" "Fatal + Error + Warn (Default)" "$([[ "$current_level" == "2" ]] && echo "on" || echo "off")"
	menu_add_option "3" "Fatal + Error + Warn + Info" "$([[ "$current_level" == "3" ]] && echo "on" || echo "off")"
	menu_add_option "4" "Fatal + Error + Warn + Info + Debug" "$([[ "$current_level" == "4" ]] && echo "on" || echo "off")"

	if menu_show_radiolist; then
		local selected_level
		selected_level="$(menu_get_first_selection)"
		cfg_set_value "s3" "S3_LOG_LEVEL" "$selected_level"
	fi

	# Part 2: Edit boolean (0/1) settings using a checklist.
	# Define a list of user-editable boolean settings for clarity and security.
	local editable_options=(
		"ADD_PROFILE_NAME"
		"DELETE_OSCAMDEBUG"
		"NO_REPO_AUTOUPDATE"
		"PATCH_WEBIF"
		"S3_URL_CHECK"
		"SAVE_LISTSMARGO"
		"USE_TARGZ"
		"USE_VERBOSE"
	)

	menu_init "Enable/Disable SimpleBuild3 Options" "Edit SimpleBuild Config"
	for option in "${editable_options[@]}"; do
		local state="off"
		[[ "$(cfg_get_value "s3" "$option" "0")" == "1" ]] && state="on"
		menu_add_option "$option" "$option" "$state"
	done

	if menu_show_checkbox; then
		local selected_options
		selected_options=($(menu_get_selected_options))

		# Atomically update all options based on the user's selection.
		for option in "${editable_options[@]}"; do
			if [[ " ${selected_options[*]} " =~ " ${option} " ]]; then
				cfg_set_value "s3" "$option" "1"
			else
				cfg_set_value "s3" "$option" "0"
			fi
		done
	fi

	# Part 3: Select OpenSSL version using the dynamic menu
	if ui_show_yesno "Change OpenSSL version for dependency builds?"; then
		# This function handles getting and setting the value
		ui_select_openssl_version_menu
	fi

	# Part 4: Save all changes back to the configuration file.
	validate_command "Saving SimpleBuild3 configuration" cfg_save_file "s3" "$s3cfg"
	err_pop_context
}

# UI Menu for selecting the target OpenSSL version for dependency builds.
ui_select_openssl_version_menu() {
	err_push_context "ui_select_openssl_version_menu"

	local versions
	mapfile -t versions < <(net_get_openssl_versions)

	if [[ ${#versions[@]} -eq 0 ]]; then
		ui_show_msgbox "Network Error" "Could not fetch the list of available OpenSSL versions. Please check your internet connection."
		err_pop_context
		return 1
	fi

	local current_version
	current_version=$(cfg_get_value "s3" "S3_OPENSSL_VERSION" "1.1.1w")

	menu_init "Select OpenSSL Version" "Select OpenSSL Version"
	for version in "${versions[@]}"; do
		local state="off"
		[[ "$version" == "$current_version" ]] && state="on"
		menu_add_option "$version" "OpenSSL $version" "$state"
	done

	if menu_show_radiolist; then
		local selected_version
		selected_version="$(menu_get_first_selection)"
		if [[ -n "$selected_version" ]]; then
			log_info "Setting OpenSSL version to: $selected_version"
			cfg_set_value "s3" "S3_OPENSSL_VERSION" "$selected_version"
		fi
	fi

	err_pop_context
	return 0
}

sys_populate_module_and_use_vars() {
	# This function replaces the fragile _get_config_con parsing.
	# It populates global variables (addons, protocols, etc.) and USE_vars array keys.
	err_push_context "Populating module and USE_vars definitions"

	local config_sh_path="${repodir}/config.sh"
	local makefile_path="${repodir}/Makefile"

	if [[ ! -f "$config_sh_path" ]]; then
		config_sh_path="$configdir/config.sh.master"
	fi
	if [[ ! -f "$makefile_path" ]]; then
		makefile_path="$configdir/Makefile.master"
	fi

	if [[ ! -f "$config_sh_path" ]]; then
		log_warn "Could not find config.sh or master copy. Module lists will be empty."
		err_pop_context
		return 1
	fi

	# Safely extract and evaluate the module list definitions from config.sh
	# This is safer than sourcing a file fragment with potential executable code.
	# It extracts lines like `addons="..."` and evaluates them in the current shell.
	local definitions
	definitions=$(grep -E '^(addons|protocols|readers|card_readers)=' "$config_sh_path")
	if [[ -n "$definitions" ]]; then
		# The globals `addons`, `protocols`, etc. are intentionally set here
		# for consumption by the legacy _create_module_arrays function.
		eval "$definitions"
	else
		log_warn "Could not extract module definitions from '$config_sh_path'."
	fi

	# Populate USE_vars array keys from the Makefile
	if [[ -f "$makefile_path" ]]; then
		local use_var_keys
		# Extracts 'USE_...' keys from the Makefile.
		mapfile -t use_var_keys < <(grep '^ *USE_' "$makefile_path" | sort -u | awk '{print $1}' | sed 's/://')
		for key in "${use_var_keys[@]}"; do
			# Initialize the key in the associative array if it's not already set.
			# This preserves any values set by profiles or CLI args.
			if ! [[ -v "USE_vars[$key]" ]]; then
				USE_vars[$key]=""
			fi
		done
	else
		log_warn "Could not find Makefile or master copy. USE_vars list will be incomplete."
	fi

	# These checks modify USE_vars based on module selections and must be run after population.
	build_check_smargo_deps
	build_check_streamrelay_deps

	log_debug "Module and USE_vars lists populated."
	err_pop_context
	return 0
}

sys_show_version() {
	echo -e "${SIMPLEVERSION}.${VERSIONCOUNTER} by ${DEVELOPER}\n- in memory of gorgone -"
}

sys_initialize_environment() {
	err_push_context "System Initialization"
	log_info "Setting up SimpleBuild3 directory structure..."

	# Create essential directories
	if ! validate_command "Creating native toolchain bin directory" mkdir -p "$tcdir/native/bin"; then
		log_fatal "Failed to create essential directories. Check permissions." "$EXIT_PERMISSION"
	fi
	if ! validate_command "Creating support directories" mkdir -p "$sdir"/{archive,binaries,downloads,software,logs,patches,backup_repo,menu_save}; then
		log_fatal "Failed to create support directories." "$EXIT_PERMISSION"
	fi

	# Remove placeholder patch file if it exists
	[ -f "$sdir/patches/no.patch" ] && rm -f "$sdir/patches/no.patch"

	# Handle deprecated directory migrations
	log_info "Checking for deprecated backup directories..."
	for migdir in backup_svn backup_git; do
		if [[ -d "$sdir/$migdir" ]]; then
			log_info "Migrating deprecated '$migdir' directory..."

			shopt -s dotglob
			if ! validate_command "Moving contents from $migdir to backup_repo" mv -f "$sdir/$migdir"/* "$brepo/"; then
				log_error "Migration step failed, continuing..."
			fi
			shopt -u dotglob

			local last_archive="$brepo/last${migdir: -3}.tar.gz"
			if [[ -e "$brepo/last.tar.gz" ]]; then
				if ! validate_command "Renaming migrated archive" mv "$brepo/last.tar.gz" "$last_archive"; then
					log_error "Archive rename failed, continuing..."
				fi
			fi

			if [[ -L "$last_archive" ]]; then
				local target
				target=$(readlink "$last_archive" | awk -F'/' '{print $NF}')
				if ! validate_command "Creating relative symlink" ln -fs "$target" "$brepo/last${migdir: -3}.tar.gz"; then
					log_error "Symlink creation failed, continuing..."
				fi
			fi

			validate_command "Removing old migration directory" rmdir "$sdir/$migdir"
		fi
	done

	# Verify logs directory exists before creating symlinks
	if [[ ! -d "$ldir" ]]; then
		log_fatal "Logs directory creation failed." "$EXIT_PERMISSION"
	fi

	# Create symlinks if they don't exist
	local links=(
		"$ldir:$workdir/logs"
		"$adir:$workdir/archive"
		"$pdir:$workdir/patches"
		"$bdir:$workdir/binaries"
		"$sodir:$workdir/software"
		"$profdir:$workdir/profiles"
	)

	for link_spec in "${links[@]}"; do
		IFS=':' read -r target link <<<"$link_spec"
		if [[ ! -L "$link" ]]; then
			if ! validate_command "Creating symlink for $(basename "$target")" ln -frs "$target" "$link"; then
				log_error "Failed to create symlink: $link -> $target"
			fi
		fi
	done

	# URLs are loaded in the main s3 script via source and manual cfg_set_value calls

	err_pop_context
}
