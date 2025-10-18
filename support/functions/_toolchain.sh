#!/bin/bash

# Source dependencies
source "$fdir/_error_handling.sh"

ui_show_build_menu() {
	[ "$loadprofile" == "yes" ] && load_config

	local text="_________________________________________________________ \n $txt_bmenu_user = $(whoami)\n Toolchain       = $_toolchainname\n $txt_bmenu_comp = $_compiler""gcc\n $txt_bmenu_debu = CPU-Threads($(sys_get_cpu_count)) ${REPO^^}($($(USEGIT) && printf "$(COMMIT)" || printf "$(REVISION)")) SCRIPT(${SIMPLEVERSION}.${VERSIONCOUNTER})\n $txt_bmenu_use  = $(echo $USESTRING | sed -e 's/^[ \t]*//')\n _________________________________________________________ \n"
	local title=" -[ $txt_bmenu_title$(REPOIDENT) ]- "

	menu_init "$text"
	menu_add_option "LOAD_PROFILE" "$txt_bmenu_profile"
	menu_add_option "CONFIGURE" "Configure OScam, EMU & Build Options..."
	menu_add_option "BUILD" "▶ Start Build"
	menu_add_separator
	menu_add_option "SAVE_PROFILE" "$txt_bmenus_profile"
	menu_add_option "UPDATE" "Update Toolchain Libraries..."
	menu_add_option "SHOW_BUILDLOG" "$txt_bmenu_log"
	menu_add_option "BACK" "$txt_bmenu_back"

	if menu_show_list; then
		local selection
		selection="$(menu_get_first_selection)"

		case "$selection" in
		LOAD_PROFILE) _load_profile ;;
		BUILD) _gui_build ;;
		CONFIGURE)
			ui_show_config_menu
			;;
		SAVE_PROFILE)
			_save_profile
			;;
		UPDATE)
			tcupdate "$_toolchainname" "" "" "2"
			ui_show_build_menu
			;;
		SHOW_BUILDLOG)
			if [ -f "$workdir/lastbuild.log" ]; then
				ui_show_textbox "Last Build Log" "$workdir/lastbuild.log"
			else
				ui_show_msgbox "Log File" "No build log found."
			fi
			ui_show_build_menu
			;;
		BACK | '')
			ui_show_toolchain_selection_menu
			;;
		esac
	else
		# Handle cancel/ESC
		ui_show_toolchain_selection_menu
	fi

	ui_show_build_menu
}

# Helper function to create a checklist for a specific module category.
# This function is the core of the new module configuration UI.
# $1: Menu Title (e.g., "Addon Modules")
# $2: Name of the array holding module short names (e.g., "SHORT_ADDONS")
# $3: The flag for config.sh to get/set modules for this category (e.g., "addons")
_ui_show_module_category_checklist() {
	local menu_title="$1"
	declare -n module_list="$2" # Use nameref to get the array by name
	local config_sh_category="$3"

	# Get currently enabled modules for this category
	local enabled_modules
	enabled_modules=$("${repodir}/config.sh" -s "$config_sh_category")

	menu_init "$menu_title"

	for module in "${module_list[@]}"; do
		local internal_name
		internal_name=$(get_module_name "$module")
		local state="off"
		# Check if the internal module name is in the list of enabled modules
		if [[ " ${enabled_modules} " =~ " ${internal_name} " ]]; then
			state="on"
		fi
		menu_add_option "$internal_name" "$module" "$state"
	done

	if menu_show_checkbox; then
		local selected_options
		selected_options=($(menu_get_selected_options))

		# Atomically update the configuration: disable all, then enable selected.
		# This prevents issues with modules being left in an incorrect state.
		validate_command "Disabling all ${config_sh_category}" "${repodir}/config.sh" -D "$config_sh_category"
		if [[ ${#selected_options[@]} -gt 0 ]]; then
			validate_command "Enabling selected ${config_sh_category}" "${repodir}/config.sh" -E "${selected_options[@]}"
		fi
		log_info "Module configuration for '${config_sh_category}' updated."
	fi
}

# Main menu for selecting which category of OScam modules to configure.
# This replaces the call to the external 'config.sh -g' script.
ui_show_module_selection_menu() {
	while true; do
		menu_init "Select Module Category to Configure"
		menu_add_option "ADDONS" "Addon Modules"
		menu_add_option "PROTOCOLS" "Protocol Modules"
		menu_add_option "READERS" "Reader Modules"
		menu_add_option "CARD_READERS" "Card Reader Modules"
		menu_add_option "BACK" "Back to Configuration Menu"

		if menu_show_list; then
			local selection
			selection="$(menu_get_first_selection)"
			case "$selection" in
			ADDONS) _ui_show_module_category_checklist "Addon Modules" "SHORT_ADDONS" "addons" ;;
			PROTOCOLS) _ui_show_module_category_checklist "Protocol Modules" "SHORT_PROTOCOLS" "protocols" ;;
			READERS) _ui_show_module_category_checklist "Reader Modules" "SHORT_READERS" "readers" ;;
			CARD_READERS) _ui_show_module_category_checklist "Card Reader Modules" "SHORT_CARD_READERS" "card_readers" ;;
			BACK) return 0 ;;
			esac
		else
			return 0 # User pressed ESC/Cancel
		fi
	done
}

ui_show_config_menu() {
	menu_init "Configuration for '$_toolchainname'"
	menu_add_option "MODULES" "OScam Modules (Addons, Protocols, Readers)..."
	menu_add_option "FEATURES" "OScam Core Features (DVBAPI, WebIF, SSL, etc.)..."
	menu_add_option "READERS" "Hardware Reader Features (PCSC, STAPI, etc.)..."
	menu_add_option "EMU" "EMU & SoftCam Settings..."
	menu_add_option "BUILD_OPTS" "Build Process Options (Static, Verbose, etc.)..."
	menu_add_separator
	menu_add_option "RESET" "Reset Configuration to Defaults"
	menu_add_option "BACK" "Back to Build Menu"

	if menu_show_list; then
		local selection
		selection="$(menu_get_first_selection)"

		case "$selection" in
		MODULES)
			# Replace the direct, non-compliant call to config.sh with the new unified UI function.
			ui_show_module_selection_menu
			cfg_save_build_profile
			;;
		FEATURES) _ui_show_core_features_menu ;;
		READERS) _ui_show_reader_features_menu ;;
		EMU) ui_show_emu_menu ;;
		BUILD_OPTS) _ui_show_build_options_menu ;;
		RESET)
			build_reset_config
			load_config
			;;
		BACK)
			return 0
			;;
		esac
	else
		# Handle cancel/ESC - go back to the previous menu.
		return 0
	fi
}

# Menu dedicated to managing toolchains (Add, Remove, Create).
ui_show_toolchain_management_menu() {
	err_push_context "ui_show_toolchain_management_menu"
	while true; do
		_fill_tc_array

		local title_main_menu="-[ Toolchain Management ]-"
		menu_init "Select a toolchain management task"

		if [ "$systype" == "ok" ]; then
			menu_add_option "ADD" "Add/Install a new toolchain from the list"
			menu_add_option "CREATE" "Create a new custom toolchain"
			[ "$tcempty" == "0" ] && menu_add_option "REMOVE" "Remove an existing installed toolchain"
		else
			menu_add_option "UNSUPPORTED" "Management is only supported on x86/x86_64 systems." "disabled"
		fi

		menu_add_separator
		menu_add_option "BACK" "Back to Main Menu"

		if ! menu_show_list; then return 0; fi # User pressed Cancel or ESC

		local selection
		selection="$(menu_get_first_selection)"
		case "$selection" in
		BACK) return 0 ;;
		ADD) ui_show_toolchain_add_menu ;;
		CREATE) tcupdate "-c" "" "" "1" ;;
		REMOVE) ui_show_toolchain_remove_menu ;;
		esac
	done
	err_pop_context
}

# This menu is solely for SELECTING a toolchain to start a build.
ui_show_toolchain_selection_menu() {
	_fill_tc_array

	local text_main_menu="$txt_main_revision$(REVISION)$($(USEGIT) && printf " @ $(COMMIT) @ $(BRANCH)" || printf " on $(BRANCH)")"
	local title_main_menu="-[ Select Toolchain to Build $(REPOIDENT) ]-"
	menu_init "$text_main_menu"

	if [ "$tcempty" == "0" ]; then
		for i in "${INST_TCLIST[@]}"; do
			if [ ! "$i" == "native" ]; then
				unset _self_build
				# Use Unified Configuration Manager (UCM) for secure loading
				if cfg_load_file "toolchain" "$tccfgdir/$i"; then
					local toolchain_name=$(cfg_get_value "toolchain" "_toolchainname" "$i")
					local description=$(cfg_get_value "toolchain" "_description" "No description")
					local self_build=$(cfg_get_value "toolchain" "_self_build" "no")

					if [[ "$systype" == "ok" || "$self_build" == "yes" ]]; then
						menu_add_option "$toolchain_name" "$description"
					fi
				else
					log_warn "Could not load or parse toolchain config: $i"
				fi
			fi
		done
	fi
	menu_add_separator
	menu_add_option "BACK" "$txt_back_main"

	if menu_show_list; then
		local selection
		selection="$(menu_get_first_selection)"

		case "$selection" in
		BACK | '')
			ui_show_main_menu
			;; # Go back to the main menu
		*)
			# Resetting all optional config variables
			unset _stagingdir _androidndkdir _self_build extra_use extra_cc extra_ld extra_c stapi_allowed stapi_lib_custom
			_toolchainname="$selection"

			# Attempt to use the new system
			if ! cfg_load_file "toolchain" "$tccfgdir/$selection"; then
				log_fatal "Failed to load configuration for '$selection'. The file may be missing or corrupt." "$EXIT_INVALID_CONFIG"
			fi
			loadprofile="yes"
			ui_show_build_menu "$selection"
			;;
		esac
	else
		# Handle cancel/ESC
		ui_show_main_menu
	fi
}

_load_toolchain() {
	local toolchain_name="$1"
	err_push_context "Load toolchain '$toolchain_name'"

	if ! cfg_load_file "toolchain" "$tccfgdir/$toolchain_name" "true"; then
		log_fatal "Failed to load configuration for toolchain '$toolchain_name'." "$EXIT_INVALID_CONFIG"
	fi

	local dln="$(basename "$(util_decode_base64 "$_toolchainfilename")")"
	local tc_dl="$dldir/$dln"
	local url="$(util_decode_base64 "$_toolchainfilename")"

	clear
	slogo
	ologo
	log_header "Loading Toolchain: $dln"

	if ! net_download_file "$url" "$tc_dl" "ui_show_progressbox 'Downloading Toolchain' 'Downloading $dln'"; then
		log_fatal "Failed to download toolchain from '$url'." "$EXIT_NETWORK"
	fi

	log_info "Toolchain '$dln' downloaded successfully."
	err_pop_context
}

_toolchain_extract_archive() {
	local toolchain_name="$1"
	local archive_path="$2"
	local strip_count="$3"
	local dest_dir="$tcdir/$toolchain_name"

	err_init "Extracting toolchain $toolchain_name"

	log_info "Preparing destination: $dest_dir"
	validate_command "Removing old directory" rm -rf "$dest_dir"
	validate_command "Creating new directory" mkdir -p "$dest_dir"

	local strip_arg=""
	if [[ "$strip_count" -gt 0 ]]; then
		strip_arg="--strip-components=$strip_count"
	fi

	log_info "Extracting archive $(basename "$archive_path")..."

	# Use tar directly piped to the UI progress box. Check PIPE_STATUS for tar's exit code.
	(
		tar -xf "$archive_path" -C "$dest_dir" "$strip_arg"
	) | ui_show_progressbox "Extracting Toolchain" "Extracting $(basename "$archive_path")"

	if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
		log_fatal "Failed to extract toolchain archive '$archive_path'." "$EXIT_ERROR"
	fi

	log_info "Extraction complete."
	return 0
}

_toolchain_check() {
	clear
	printf "$w_l"
	s3logo
	headervars=(crypto.h pcsclite.h libusb.h pthread.h dvbcsa.h zlib.h)
	if ! cfg_load_file "toolchain" "$tccfgdir/$1"; then
		log_fatal "Failed to load toolchain config for '$1'" "$EXIT_INVALID_CONFIG"
	fi

	fmtg="  ${w_l}%-16s ${y_l}%-20s ${g_l}%-8s $p_l%-20s %-17s ${g_l}%s\n"
	fmtb="  ${w_l}%-16s ${y_l}%-20s ${r_l}%s\n"

	if [ -d "$tcdir/$1/bin" ]; then
		cd "$tcdir/$1/bin"
	else
		log_error "Toolchain '$1' is not installed"
		err_log_and_exit "Toolchain not found" "$EXIT_MISSING"
	fi

	printf "$w_l  Compiler info -----> $C$1$w_l\n  ====================\n"

	local _compiler
	_compiler=$(cfg_get_value "toolchain" "_compiler")
	local _realcompiler
	_realcompiler=$(cfg_get_value "toolchain" "_realcompiler")
	local _androidndkdir
	_androidndkdir=$(cfg_get_value "toolchain" "_androidndkdir")
	local _sysroot
	_sysroot=$(cfg_get_value "toolchain" "_sysroot")

	if [ -z "$sysroot" ] && [ ! "$1" == "native" ]; then
		compilername="$_compiler""gcc"
		[ ${#_realcompiler} -gt 4 ] && compilername="$_realcompiler"
		version=$("./$compilername" -dumpversion)
		[ "$_androidndkdir" == "1" ] && sr="$tcdir/$1/sysroot" || sr=$("./$compilername" -print-sysroot 2>/dev/null)
		sysroot=$(realpath -sm "$sr" --relative-to="$tcdir/$1")
		compilerpath=$(realpath -sm "./$compilername" --relative-to="$tcdir/$1")
		printf "$fmtg" "GCC Version :" "$version"
		printf "$fmtg" "GCC Binary  :" "$compilerpath"
		printf "$fmtg" "GCC Sysroot :" "$sysroot"
		gversion=$("./$_compiler""gdb" --version 2>/dev/null | head -n1 | awk '{print $NF}')
		[ -n "$gversion" ] && printf "$fmtg" "GDB Version :" "$gversion"
		lversion=$("./$_compiler""ld" --version 2>/dev/null | head -n1 | awk '{print $NF}')
		[ -n "$lversion" ] && printf "$fmtg" "LD Version  :" "$lversion"
		printf "$fmtg" "HOST arch   :" "$(_get_compiler_arch host)"
		printf "$fmtg" "TARGET arch :" "$(_get_compiler_arch target)"
		printf "$fmtg" "C11 Support :" "$(! _check_compiler_capability 'c11' && printf 'No' || printf 'Yes')"
		[ -z "$sysroot" ] && sysroot="$r_l$txt_too_old\n"
	fi

	if [ "$1" == "native" ]; then
		printf "$fmtg" "GCC Version :" "$(gcc --version | head -n 1)"
		printf "$fmtg" "GCC Binary  :" "$(which $(gcc -dumpmachine)-gcc || which gcc)"
	fi

	printf "\n$w_l  Sysroot config ----> $C$_sysroot$w_l\n  ====================\n"

	[ "$1" == "native" ] && cd "$_sysroot" || cd "$tcdir/$1/$_sysroot"

	linux="$(_linux_version $([ "$1" == "native" ] && printf "/usr/src/linux-headers-$(uname -r)" || printf "."))"
	linuxc="$(echo $linux | awk -F';' '{print $1}')"
	linuxv="$(echo $linux | awk -F';' '{print $2}')"
	[ ! -z "$linux" ] && printf "$fmtg" "Linux       :" "version.h" "${linuxv::8}" "($linuxc)" || printf "$fmtb" "Linux       :" "version.h" "(missing linux headers)"

	libc="$(_libc_version $1)"
	libcf="$(echo $libc | awk -F';' '{print $1}')"
	libcl="$(echo $libc | awk -F';' '{print $2}')"
	libcv="$(echo $libc | awk -F';' '{print $3}')"
	[ ! -z "$libcl" ] && printf "$fmtg" "C-Library   :" "${libcf::20}" "${libcv::8}" "($libcl)" || printf "$fmtb" "C-Library   :" "${libcf::20}" "($txt_not_found)"

	for e in "${headervars[@]}"; do
		temp=$(find * | grep -wm1 "$e")
		[ ${#temp} -gt 5 ] && printf "$fmtg" "Header File :" "${e::20}" "${txt_found}" || printf "$fmtb" "Header File :" "${e::20}" "($txt_not_found)"
	done

	[ "$1" == "native" ] && pkgs=$(find ../* -name "pkgconfig" -type d) || pkgs=$(find . -name "pkgconfig" -type d)
	if [ ${#pkgs} -gt 0 ]; then
		for pkg in ${pkgs}; do
			if [ "$1" == "native" ]; then
				cd "$_sysroot/$pkg"
				printf "\n$w_l  Library config ----> $C$PWD$w_l\n  ====================\n"
			else
				cd "$tcdir/$1/$_sysroot/$pkg"
				printf "\n$w_l  Library config ----> $C$(realpath -sm "$PWD" --relative-to="$tcdir/$1")$w_l\n  ====================\n"
			fi

			for f in *.pc; do
				unset type
				ff="${f/zlib/"libz"}"
				ff="${ff/openssl/"libcrypto"}"
				content=$(cat "$f" 2>/dev/null) && na=$(echo "$content" | grep 'Name:' | sed -e "s/Name: //g") && ver=$(echo "$content" | grep 'Version:' | sed -e "s/Version: //g")
				sp1=$(printf '%*s' $((20 - ${#f})) | tr ' ' ' ') && sp2=$(printf '%*s' $((20 - ${#na})) | tr ' ' ' ')
				[ -n "$(find "$PWD/../" -name "${ff%.*}.a" -xtype f -print -quit)" ] && type="static"
				[ -n "$(find "$PWD/../" \( -name "${ff%.*}.so" -o -name "${ff%.*}.so.*" \) -xtype f -print -quit)" ] && type+="$([ -n "$type" ] && echo '+')dynamic"
				[ ${#content} -gt 0 ] && printf "$fmtg" "Library Config :" "${f::20}" "$txt_found" "${na::20}" "$ver" "$type" || printf "$fmtb" "Library Config :" "${f::20}" "($txt_not_found)"

			done
		done
	else
		printf "\n$w_l  Library config ----> $C no libraries found in pkgconfig$w_l\n  ====================\n"
	fi

	printf "$re_\n"
	exit
}

sys_repair_toolchain() {
	local toolchain_name="$1"
	err_push_context "sys_repair_toolchain"
	clear
	s3logo

	if ! cfg_load_file "toolchain" "$tccfgdir/$toolchain_name"; then
		log_fatal "Failed to load toolchain configuration for '$toolchain_name'." "$EXIT_INVALID_CONFIG"
	fi

	local md5sum_string
	md5sum_string=$(cfg_get_value "toolchain" "_md5sum")
	if [[ -z "$md5sum_string" ]]; then
		log_fatal "MD5 checksum not defined in '$toolchain_name' config." "$EXIT_INVALID_CONFIG"
	fi

	local expected_md5
	local archive_filename
	expected_md5=$(echo "$md5sum_string" | awk '{print $1}')
	archive_filename=$(echo "$md5sum_string" | awk '{print $2}')
	local archive_path="$dldir/$archive_filename"

	local needs_download=true
	if [[ -f "$archive_path" ]]; then
		log_header "Verifying Local Archive"
		log_info "Archive '$archive_filename' found locally. Verifying checksum..."

		local actual_md5
		actual_md5=$(md5sum "$archive_path" | awk '{print $1}')

		if [[ "$actual_md5" == "$expected_md5" ]]; then
			log_info "MD5 check successful. Skipping download."
			needs_download=false
		else
			log_warn "MD5 check failed. Removing corrupted archive and re-downloading."
			validate_command "Removing corrupted archive" rm -f "$archive_path"
		fi
	fi

	if [[ "$needs_download" == true ]]; then
		local toolchain_url_b64
		toolchain_url_b64=$(cfg_get_value "toolchain" "_toolchainfilename")
		if [[ -z "$toolchain_url_b64" ]]; then
			log_fatal "Toolchain URL not defined in '$toolchain_name' config." "$EXIT_INVALID_CONFIG"
		fi

		local toolchain_url
		toolchain_url=$(util_decode_base64 "$toolchain_url_b64")

		log_header "Downloading Toolchain: $archive_filename"
		if ! net_download_file "$toolchain_url" "$archive_path" "ui_show_progressbox 'Downloading Toolchain' 'Downloading $archive_filename'"; then
			log_fatal "Failed to download toolchain from '$toolchain_url'." "$EXIT_NETWORK"
		fi

		log_info "Download complete. Verifying checksum..."
		if ! md5sum -c <<<"$expected_md5  $archive_path" >/dev/null 2>&1; then
			log_fatal "Checksum validation failed after download for '$archive_path'." "$EXIT_ERROR"
		fi
		log_info "Checksum for downloaded file is correct."
	fi

	log_header "Installing Toolchain: $toolchain_name"
	local extract_strip
	extract_strip=$(cfg_get_value "toolchain" "_extract_strip" "0")

	if ! _toolchain_extract_archive "$toolchain_name" "$archive_path" "$extract_strip"; then
		log_fatal "Toolchain extraction failed." "$EXIT_ERROR"
	fi

	log_info "Toolchain '$toolchain_name' has been successfully repaired."
	err_pop_context
	sleep 2
	return 0
}

ui_show_toolchain_add_menu() {
	_fill_tc_array

	local text_add_menu="$txt_main_revision$(REVISION)"
	local title_add_menu="-[ $txt_add_menu$(REPOIDENT) ]-"

	menu_init "$text_add_menu"

	for i in "${MISS_TCLIST[@]}"; do
		if [ ! "$i" == "native" ]; then
			# Use Unified Configuration Manager (UCM) for secure loading
			if cfg_load_file "toolchain" "$tccfgdir/$i"; then
				local toolchain_name=$(cfg_get_value "toolchain" "_toolchainname" "$i")
				local description=$(cfg_get_value "toolchain" "_description" "No description")
				menu_add_option "$toolchain_name" "$description"
			else
				log_warn "Could not load or parse toolchain config for add menu: $i"
			fi
		fi
	done
	menu_add_option "EXIT" "$txt_menu_builder1"

	if menu_show_list; then
		local selection
		selection="$(menu_get_first_selection)"

		case "$selection" in
		EXIT) bye ;;
		*)
			# Install selected toolchain
			first="$selection"
			ui_install_toolchain_interactive
			;; # After install, loop will show the management menu again
		esac
	else
		# Handle cancel/ESC
		return 0
	fi
}

ui_show_toolchain_remove_menu() {
	_fill_tc_array

	local text_remove_menu="$txt_main_revision$(REVISION)"
	local title_remove_menu="-[ $txt_remove_menu$(REPOIDENT) ]-"

	menu_init "$text_remove_menu"

	if [ "$tcempty" == "0" ]; then
		for i in "${INST_TCLIST[@]}"; do
			if [ ! "$i" == "native" ]; then
				# Use Unified Configuration Manager (UCM) for secure loading
				if cfg_load_file "toolchain" "$tccfgdir/$i"; then
					local toolchain_name=$(cfg_get_value "toolchain" "_toolchainname" "$i")
					local description=$(cfg_get_value "toolchain" "_description" "No description")
					menu_add_option "$toolchain_name" "$description"
				else
					log_warn "Could not load or parse toolchain config for remove menu: $i"
				fi
			fi
		done
	fi
	menu_add_option "EXIT" "$txt_menu_builder1"

	if menu_show_list; then
		local selection
		selection="$(menu_get_first_selection)"

		case "$selection" in
		EXIT) bye ;;
		*)
			# Remove selected toolchain
			[ -d "$tcdir/$selection" ] && rm -rf "$tcdir/$selection"
			;; # Loop will refresh the menu
		esac
	else
		# Handle cancel/ESC
		return 0
	fi
}

ui_install_toolchain_interactive() {
	local toolchain_name="$first" # 'first' is a global from the menu selection
	err_push_context "ui_install_toolchain_interactive"

	if ! cfg_load_file "toolchain" "$tccfgdir/$toolchain_name"; then
		log_fatal "Failed to load toolchain configuration for '$toolchain_name'." "$EXIT_INVALID_CONFIG"
	fi

	local md5sum_string
	md5sum_string=$(cfg_get_value "toolchain" "_md5sum")
	if [[ -z "$md5sum_string" ]]; then
		log_fatal "MD5 checksum not defined in '$toolchain_name' config." "$EXIT_INVALID_CONFIG"
	fi

	local expected_md5
	expected_md5=$(echo "$md5sum_string" | awk '{print $1}')
	local archive_filename
	archive_filename=$(echo "$md5sum_string" | awk '{print $2}')
	local archive_path="$dldir/$archive_filename"

	local needs_download=true
	if [[ -f "$archive_path" ]]; then
		local actual_md5
		actual_md5=$(md5sum "$archive_path" | awk '{print $1}')
		if [[ "$actual_md5" == "$expected_md5" ]]; then
			needs_download=false
		else
			ui_show_msgbox "Checksum Mismatch" "Local archive is corrupt. Re-downloading." "6" "70"
			rm -f "$archive_path" || log_fatal "Failed to remove corrupt archive." "$EXIT_ERROR"
		fi
	fi

	if [[ "$needs_download" == true ]]; then
		local toolchain_url_b64
		toolchain_url_b64=$(cfg_get_value "toolchain" "_toolchainfilename")
		if [[ -z "$toolchain_url_b64" ]]; then
			log_fatal "Toolchain URL not defined in '$toolchain_name' config." "$EXIT_INVALID_CONFIG"
		fi
		local toolchain_url
		toolchain_url=$(util_decode_base64 "$toolchain_url_b64")

		if ! net_download_file "$toolchain_url" "$archive_path" "ui_show_progressbox 'Downloading Toolchain' 'Downloading $archive_filename'"; then
			log_fatal "Failed to download toolchain from '$toolchain_url'." "$EXIT_NETWORK"
		fi

		if ! md5sum -c <<<"$expected_md5  $archive_path" &>/dev/null; then
			log_fatal "Checksum validation failed after download for '$archive_path'." "$EXIT_ERROR"
		fi
	fi

	local extract_strip
	extract_strip=$(cfg_get_value "toolchain" "_extract_strip" "0")

	if ! _toolchain_extract_archive "$toolchain_name" "$archive_path" "$extract_strip"; then
		log_fatal "Toolchain extraction failed." "$EXIT_ERROR"
	fi

	ui_show_msgbox "Success" "Toolchain '$toolchain_name' has been successfully installed." "6" "70"
	err_pop_context
	return 0
}

_libc_version() {
	local libcfile libcname verstr

	if [ "$1" == "native" ]; then
		libcfile="ldd"
		verstr="$(ldd --version | head -n1 | awk '{printf $3 "-" $5}')"
		verstr="${verstr,,}"
	else
		libcfile="$(find . -name "libc.so.?" -o -name "libc-*.so" -o -name "libuClibc-*.so" 2>/dev/null | head -n1)"
		if [ -L "$libcfile" ] && [ -e "$libcfile" ]; then
			libcfile="$(readlink "$libcfile")"
		else
			libcfile="$(basename "$libcfile")"
		fi
		libcname=$(echo $libcfile | sed 's/\.so$//')

		# glibc
		verstr="$(strings "$(find . -name "$libcfile" | head -n1)" 2>/dev/null | grep -Po '^GLIBC_(\d+\.)+\d+' | sort -Vr | head -n1)"
		if [ -n "$verstr" ]; then
			verstr="${verstr,,}"
			verstr="${verstr//_/-}"

		# uclibc
		elif [ "$libcname" != "${libcname#libuClibc-}" ]; then
			verstr="${libcname#lib}"

		# musl
		elif [ "$(strings "$(find . -name "libc.so" | head -n1)" 2>/dev/null | grep '^musl')" ]; then
			libcfile="$(basename $(find . -name "libc.so" | head -n1))"
			verstr="musl-$(strings "$(find . -name "libc.so" | head -n1)" | grep '^[0-1]\.[0-9]\.[0-9][0-9]*$')"

		# bionic
		elif [ "$(strings "$(find . -name "libc.so" ! -path "*/x86_64-linux-android/*" | head -n1)" 2>/dev/null | grep 'bionic')" ]; then
			libcfile="$(basename $(find . -name "libc.so" ! -path "*/x86_64-linux-android/*" | head -n1))"
			verstr="bionic-$(strings "$(find . -name "libc.so" ! -path "*/x86_64-linux-android/*" | head -n1)" | grep '^C[0-2]\.[0-9]*$')"

		#unknown
		else
			libcfile="[g|uc]libc|musl"
		fi
	fi

	printf "$libcfile;${verstr//-/;}"
}

_linux_version() {
	local vcode base major patch sub

	vcode=$(find "$1" -name "version.h" -type f -exec grep -m1 "LINUX_VERSION_CODE" {} \; | awk '{print $3}')

	# LINUX_VERSION_CODE is X*65536 + Y*256 + Z
	[ -z $vcode ] && return || base=$vcode
	major=$(($base / 65536))
	mp=$(($major * 65536))
	base=$(($base - mp))

	patch=$(($base / 256))
	pp=$(($patch * 256))
	sub=$(($base - pp))

	printf "$vcode;$major.$patch.$sub"
}

_check_compiler_capability() {
	check_filename="s3_gcc_cap_$1"
	case "$1" in
	"c11") #checking if $CC supports -std=c11
		echo "_Thread_local int x; int main(){x = 42; ; return 0;}" | "$(realpath -s $compilername)" -std=c11 -x c -o "/tmp/${check_filename}.chk" - &>"/tmp/${check_filename}.log" ;;
	"neon") #checking if toolchain supports neon
		[[ "$2" =~ android ]] && return 1
		[[ "$2" =~ aarch64 ]] && mfpu='' || mfpu='-mfpu=neon'
		echo -e "#include <arm_neon.h>\nint main(){return 0;}" | "$(realpath -s $compilername)" $mfpu -x c -o "/tmp/${check_filename}.chk" - &>"/tmp/${check_filename}.log"
		;;
	"altivec") #checking if toolchain supports altivec
		echo -e "#include <altivec.h>\nint main(){return 0;}" | "$(realpath -s $compilername)" -maltivec -x c -o "/tmp/${check_filename}.chk" - &>"/tmp/${check_filename}.log" ;;
	*) false ;;
	esac
	ret=$?
	find /tmp -name "${check_filename}.chk" -type f -exec rm {} \; &>/dev/null
	return $ret
}

_get_compiler_arch() {
	ret=''
	case "$1" in
	"build") #checking build system architecture
		ret="$(uname -m)" ;;
	"host") #checking host architecture the compiler was build for
		# Use ranlib instead of gcc to compatible with android toolchains, gcc is a wrapper script there
		ret="$(file -b $(realpath "$_compiler""ranlib") | awk -F',' '{print $2}' | xargs)" ;;
	"target") #checking target architecture the compiler produces binaries for
		ret="$("./$compilername" -dumpmachine | awk -F'-' '{print $1}' | xargs)" ;;
	esac
	printf "$ret"
}

ui_show_emu_menu() {
	while true; do
		local emu_state="off"
		if [[ "$("${repodir}/config.sh" --enabled WITH_EMU)" == "Y" ]]; then
			emu_state="on"
		fi

		menu_init "EMU & SoftCam Settings"
		menu_add_option "PATCH" "Download & Apply latest oscam-emu.patch"
		menu_add_option "SOFTCAM" "Download latest SoftCam.Key"
		menu_add_separator
		menu_add_option "BACK" "Back"
		menu_add_option "EXIT" "Exit SimpleBuild"

		if menu_show_list; then
			local selection
			selection="$(menu_get_first_selection)"
			case "$selection" in
			PATCH)
				if patch_apply_emu; then
					ui_show_msgbox "Success" "EMU Patch applied and module enabled."
				else
					ui_show_msgbox "Error" "Failed to apply EMU patch. Please check the logs."
				fi
				# After action, loop back to this menu
				;;
			SOFTCAM)
				# Download to the repository directory for easy access after build
				if net_download_softcam_key "$repodir"; then
					ui_show_msgbox "Success" "SoftCam.Key downloaded to the oscam source folder."
				else
					ui_show_msgbox "Error" "Failed to download SoftCam.Key."
				fi
				# After action, loop back to this menu
				;;
			BACK)
				return 0 # Exit this function to go back to the previous menu
				;;
			EXIT)
				bye # Exit the whole application
				;;
			esac
		else
			return 0 # User pressed ESC/Cancel
		fi
	done
}

# Helper to reduce duplication in feature/build options menus
_ui_show_generic_options_menu() {
	local title="$1"
	shift
	local -a options=("$@")
	menu_init "$title"

	for opt in "${options[@]}"; do
		local state="off"
		# Special check for non-USE_vars
		if [[ "$opt" == "WITH_EMU" || "$opt" == "MODULE_STREAMRELAY" ]]; then
			[[ "$("${repodir}/config.sh" --enabled "$opt")" == "Y" ]] && state="on"
		else
			[[ "${#USE_vars[$opt]}" -gt 4 ]] && state="on"
		fi
		menu_add_option "$opt" "Enable $opt" "$state"
	done

	if menu_show_checkbox; then
		local selections=($(menu_get_selected_options))
		for opt in "${options[@]}"; do
			if [[ " ${selections[*]} " =~ " ${opt} " ]]; then
				if [[ "$opt" == "WITH_EMU" || "$opt" == "MODULE_STREAMRELAY" ]]; then
					validate_command "Enabling $opt" "${repodir}/config.sh" --enable "$opt"
				else
					USE_vars[$opt]="$opt=1"
				fi
			else
				if [[ "$opt" == "WITH_EMU" || "$opt" == "MODULE_STREAMRELAY" ]]; then
					validate_command "Disabling $opt" "${repodir}/config.sh" --disable "$opt"
				else
					USE_vars[$opt]=""
				fi
			fi
		done
		cfg_save_build_profile
		# Re-run dependency checks after changing options
		build_check_smargo_deps
		build_check_streamrelay_deps
	fi
}

_ui_show_core_features_menu() {
	_ui_show_generic_options_menu "OScam Core Features" "USE_DVBAPI" "USE_WEBIF" "USE_IPV6SUPPORT" "USE_SSL" "WITH_EMU" "MODULE_STREAMRELAY"
}

_ui_show_reader_features_menu() {
	_ui_show_generic_options_menu "Hardware Reader Features" "USE_PCSC" "USE_LIBUSB"
	# STAPI is handled separately after the generic menu
	if menu_show_checkbox; then
		local selections=($(menu_get_selected_options))
		for opt in "${options[@]}"; do
			if [[ " ${selections[*]} " =~ " ${opt} " ]]; then
				USE_vars[$opt]="$opt=1"
			else
				USE_vars[$opt]=""
			fi
		done

		if [[ " ${selections[*]} " =~ " STAPI_CONFIG " ]]; then
			ui_show_stapi_menu
		fi
	fi
}

_ui_show_build_options_menu() {
	_ui_show_generic_options_menu "Build Process Options" "USE_STATIC" "STATIC_LIBCRYPTO" "STATIC_SSL" "STATIC_LIBUSB" "STATIC_PCSC" "STATIC_LIBDVBCSA" "USE_TARGZ" "USE_VERBOSE" "USE_DIAG" "USE_PATCH" "USE_EXTRA" "USE_CONFDIR" "USE_OSCAMNAME"
}
ui_show_stapi_menu() {
	if [[ "$stapi_allowed" != "1" ]]; then
		ui_show_msgbox "STAPI Info" "STAPI is not available for the '$_toolchainname' toolchain."
		return
	fi

	menu_init "Select STAPI Mode"
	menu_add_option "STAPI_OFF" "Disable STAPI" "on"
	menu_add_option "USE_STAPI" "Enable STAPI" "off"
	menu_add_option "USE_STAPI5_UFS916" "Enable STAPI5 (UFS916)" "off"
	menu_add_option "USE_STAPI5_UFS916003" "Enable STAPI5 (UFS916003)" "off"
	menu_add_option "USE_STAPI5_OPENBOX" "Enable STAPI5 (OPENBOX)" "off"

	if menu_show_radiolist; then
		local selection
		selection="$(menu_get_first_selection)"

		stapivar=''
		addstapi=
		usevars=$(echo "$usevars" | sed "s@USE_STAPI5@@" | xargs)
		usevars=$(echo "$usevars" | sed "s@USE_STAPI@@" | xargs)

		case "$selection" in
		STAPI_OFF) stapivar= ;;
		USE_STAPI)
			[ -z "$stapi_lib_custom" ] && stapivar="STAPI_LIB=$sdir/stapi/liboscam_stapi.a" || stapivar="STAPI_LIB=$sdir/stapi/${stapi_lib_custom}"
			addstapi="USE_STAPI"
			;;
		USE_STAPI5_UFS916)
			stapivar="STAPI5_LIB=$sdir/stapi/liboscam_stapi5_UFS916.a"
			addstapi="USE_STAPI5"
			;;
		USE_STAPI5_UFS916003)
			stapivar="STAPI5_LIB=$sdir/stapi/liboscam_stapi5_UFS916_0.03.a"
			addstapi="USE_STAPI5"
			;;
		USE_STAPI5_OPENBOX)
			stapivar="STAPI5_LIB=$sdir/stapi/liboscam_stapi5_OPENBOX.a"
			addstapi="USE_STAPI5"
			;;
		esac

		cfg_save_build_profile
	fi
}
cfg_save_build_profile() {
	err_push_context "cfg_save_build_profile"
	log_debug "Saving build configuration for '$_toolchainname'"

	local enabled_modules disabled_modules use_vars_string
	enabled_modules=$("${repodir}/config.sh" -s)
	disabled_modules=$("${repodir}/config.sh" -Z)

	# Handle toolchain-specific quirks during config application, not saving.
	if [[ "$_toolchainname" == "sh4" || "$_toolchainname" == "sh_4" ]]; then
		"${repodir}/config.sh" --disable WITH_COMPRESS >/dev/null 2>&1
	fi

	local -a use_vars_temp=()
	for key in "${!USE_vars[@]}"; do
		# Only save variables that are actually set (not empty)
		if [[ -n "${USE_vars[$key]}" ]]; then
			# Store just the key, not the 'KEY=1' value
			use_vars_temp+=("$key")
		fi
	done
	use_vars_string="${use_vars_temp[*]}"

	# Handle STAPI vars separately, adding the selected mode to the use_vars list
	if [[ "$stapi_allowed" == "1" && "${#stapivar}" -gt "15" && -n "$addstapi" ]]; then
		use_vars_string="$use_vars_string $addstapi"
	fi

	local namespace="build_profile:$_toolchainname"
	local config_file="$menudir/$_toolchainname.cfg"

	cfg_set_value "$namespace" "enabled_modules" "$enabled_modules"
	cfg_set_value "$namespace" "disabled_modules" "$disabled_modules"
	cfg_set_value "$namespace" "use_vars" "$use_vars_string"
	cfg_set_value "$namespace" "stapivar" "$stapivar"

	if ! cfg_save_file "$namespace" "$config_file"; then
		log_error "Failed to save build configuration for '$_toolchainname' to $config_file"
	else
		log_debug "Build configuration saved successfully."
	fi

	# Clean up the legacy file format if it exists
	[ -f "$menudir/$_toolchainname.save" ] && rm -f "$menudir/$_toolchainname.save"
	err_pop_context
}
load_config() {
	err_push_context "load_config"
	log_debug "Loading build configuration for '$_toolchainname'"

	# Clear previous state
	_stapi=""
	_stapi5=""
	stapivar=""
	USESTRING=""
	for key in "${!USE_vars[@]}"; do USE_vars[$key]=""; done

	local namespace="build_profile:$_toolchainname"
	local config_file="$menudir/$_toolchainname.cfg"

	if [ -f "$config_file" ]; then
		log_debug "Found existing config file: $config_file"
		if ! cfg_load_file "$namespace" "$config_file"; then
			log_warn "Could not load saved config '$config_file', applying defaults."
			# Fall through to the 'else' block
		else
			local enabled_modules disabled_modules use_vars_string
			enabled_modules=$(cfg_get_value "$namespace" "enabled_modules")
			disabled_modules=$(cfg_get_value "$namespace" "disabled_modules")
			use_vars_string=$(cfg_get_value "$namespace" "use_vars")
			stapivar=$(cfg_get_value "$namespace" "stapivar") # This is a global

			# Re-apply module configuration
			validate_command "Enabling modules from profile" "${repodir}/config.sh" -E $enabled_modules
			validate_command "Disabling modules from profile" "${repodir}/config.sh" -D $disabled_modules

			# Re-populate USE_vars array
			for var in $use_vars_string; do
				USE_vars[$var]="$var=1"
				if [[ "$var" == "USE_LIBUSB" ]]; then
					"${repodir}/config.sh" --enable CARDREADER_SMARGO >/dev/null 2>&1
				fi
			done
		fi
	else
		log_debug "No saved config found. Applying defaults."
		build_reset_config
		if [[ "$(cfg_get_value "s3" "USE_TARGZ")" == "1" ]]; then
			USE_vars[USE_TARGZ]="USE_TARGZ=1"
		fi
		# Get default_use from the toolchain config, which should already be loaded
		local default_use
		default_use=$(cfg_get_value "toolchain" "default_use")
		for var in $default_use; do
			USE_vars[$var]="$var=1"
		done
	fi

	# Post-load dependency checks and updates
	build_check_smargo_deps
	build_check_streamrelay_deps

	if [[ "$_toolchainname" == "sh4" || "$_toolchainname" == "sh_4" ]]; then
		"${repodir}/config.sh" --disable WITH_COMPRESS >/dev/null 2>&1
	fi

	local -a use_string_temp=()
	for key in "${!USE_vars[@]}"; do
		if [[ -n "${USE_vars[$key]}" ]]; then
			use_string_temp+=("$(echo "$key" | sed 's@USE_@@g')")
		fi
	done
	USESTRING="${use_string_temp[*]}" # This is a global

	err_pop_context
}
