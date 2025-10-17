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
	menu_add_option "FEATURES" "OScam Features (STAPI, PCSC, IPv6, etc.)..."
	menu_add_option "EMU" "EMU & SoftCam Settings..."
	menu_add_option "BUILD_OPTS" "Build Process Options (Static, Debug, etc.)..."
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
		FEATURES)
			_oscam_extra_menu
			;;
		EMU) ui_show_emu_menu ;; # This is the new function
		BUILD_OPTS)
			_build_extra_menu
			;;
		RESET)
			_reset_config
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
				# Use legacy source for now, as .cfg files are not clean key-value pairs
				source "$tccfgdir/$i"
				if [ "$systype" == "ok" -o "$_self_build" == "yes" ]; then
					menu_add_option "$_toolchainname" "$_description"
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
			# Attempt to use the new system, fall back to legacy source
			if ! cfg_load_file "toolchain" "$tccfgdir/$selection"; then
				source "$tccfgdir/$selection"
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
	[ ! -z "$1" ] && source "$tccfgdir/$1"
	local dln="$(basename "$(decode "$_toolchainfilename")")"
	local tc_dl="$dldir/$dln"
	local url="$(decode "$_toolchainfilename")"

	clear
	slogo # Use a standard logo
	ologo
	log_header "Loading Toolchain: $dln"

	if ! net_download_file "$url" "$tc_dl" "ui_show_progressbox 'Downloading Toolchain' 'Downloading $dln'"; then
		log_fatal "Failed to download toolchain from '$url'." "$EXIT_NETWORK"
	fi

	log_info "Toolchain '$dln' downloaded successfully."
}

# New private helper function for consistent toolchain extraction
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
	[ -f "$tccfgdir/$1" ] && source "$tccfgdir/$1"

	fmtg="  ${w_l}%-16s ${y_l}%-20s ${g_l}%-8s $p_l%-20s %-17s ${g_l}%s\n"
	fmtb="  ${w_l}%-16s ${y_l}%-20s ${r_l}%s\n"

	if [ -d "$tcdir/$1/bin" ]; then
		cd "$tcdir/$1/bin"
	else
		log_error "Toolchain '$1' is not installed"
		err_log_and_exit "Toolchain not found" "$EXIT_MISSING"
	fi

	printf "$w_l  Compiler info -----> $C$1$w_l\n  ====================\n"

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
	err_push_context "Toolchain repair operation for '$toolchain_name'"
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
		toolchain_url=$(decode "$toolchain_url_b64")

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
			# Use legacy source for now, as .cfg files are not clean key-value pairs
			source "$tccfgdir/$i"
			menu_add_option "$_toolchainname" "$_description"
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
				# Use legacy source for now, as .cfg files are not clean key-value pairs
				source "$tccfgdir/$i"
				menu_add_option "$_toolchainname" "$_description"
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
	err_push_context "Toolchain UI installation for '$toolchain_name'"

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
		toolchain_url=$(decode "$toolchain_url_b64")

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
		menu_add_option "TOGGLE_EMU" "Enable WITH_EMU in OScam config" "$emu_state"
		menu_add_separator
		menu_add_option "PATCH" "Download & Apply latest oscam-emu.patch"
		menu_add_option "SOFTCAM" "Download latest SoftCam.Key"
		menu_add_separator
		menu_add_option "BACK" "Back to Configuration Menu"

		if menu_show_checkbox; then # Using checkbox to allow toggling the EMU state
			local selection
			selection=($(menu_get_selected_options))
			local action
			action="${selection[0]}" # Get the first (and likely only) action selected

			case "$action" in
			TOGGLE_EMU)
				if [[ "$emu_state" == "on" ]]; then
					validate_command "Disabling WITH_EMU" "${repodir}/config.sh" --disable WITH_EMU
				else
					validate_command "Enabling WITH_EMU" "${repodir}/config.sh" --enable WITH_EMU
				fi
				;;
			PATCH)
				if patch_apply_emu; then
					ui_show_msgbox "Success" "EMU Patch applied and module enabled."
				else
					ui_show_msgbox "Error" "Failed to apply EMU patch. Please check the logs."
				fi
				;;
			SOFTCAM)
				# Download to the binaries directory for easy access after build
				if net_download_softcam_key "$bdir"; then
					ui_show_msgbox "Success" "SoftCam.Key downloaded to the binaries folder."
				else
					ui_show_msgbox "Error" "Failed to download SoftCam.Key."
				fi
				;;
			BACK)
				return 0
				;;
			esac
		else
			return 0 # User pressed ESC/Cancel
		fi
	done
}

cfg_load_toolchain_config() {
	local toolchain_name="$1"
	local config_path="$tccfgdir/$toolchain_name"
	if [[ -f "$config_path" ]]; then
		source "$config_path"
		return 0
	else
		log_error "Toolchain config not found: $config_path"
		return 1
	fi
}
