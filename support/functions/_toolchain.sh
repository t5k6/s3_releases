#!/bin/bash

# Source dependencies
source "$fdir/_error_handling.sh"

ui_show_build_menu() {
	while true; do
		# Ensure config is loaded if requested (e.g. after toolchain selection)
		if [ "$loadprofile" == "yes" ]; then
			load_config
			loadprofile="no" # Reset flag after loading
		fi

		# Use printf for consistent alignment of header information
		local line1 line2 line3 line4 line5
		printf -v line1 "%-15s = %s" "${txt_info_username}" "$(whoami)"
		printf -v line2 "%-15s = %s" "Toolchain" "$_toolchainname"
		printf -v line3 "%-15s = %s" "${txt_info_compiler}" "${_compiler}gcc"
		printf -v line4 "%-15s = %s" "${txt_info_debug}" "CPU-Threads($(sys_get_cpu_count)) ${REPO^^}($(repo_is_git && repo_get_commit || repo_get_revision)) SCRIPT(${SIMPLEVERSION}.${VERSIONCOUNTER})"
		printf -v line5 "%-15s = %s" "${txt_info_use_variables}" "$(echo "$USESTRING" | sed -e 's/^[ \t]*//')"

		local text="_________________________________________________________ \n${line1}\n${line2}\n${line3}\n${line4}\n${line5}\n_________________________________________________________ \n"

		menu_init "$text" "-[ Build Menu ]-"
		menu_add_option "IMPORT_LEGACY_PROFILE" "$txt_menu_build_import_config"
		menu_add_option "CONFIGURE" "$txt_bmenu_configure"
		menu_add_option "BUILD" "$txt_bmenu_build"
		menu_add_separator
		menu_add_option "EXPORT_LEGACY_PROFILE" "$txt_menu_build_export_config"
		menu_add_option "UPDATE" "$txt_bmenu_update"
		menu_add_option "SHOW_BUILDLOG" "$txt_bmenu_log"
		menu_add_option "BACK" "$txt_bmenu_back"

		if menu_show_list; then
			local selection
			selection="$(menu_get_first_selection)"

			case "$selection" in
			IMPORT_LEGACY_PROFILE) build_import_legacy_profile ;;
			BUILD)
				_gui_build
				# _gui_build now handles its own post-build menu, so we just loop back here when done.
				;;
			CONFIGURE)
				ui_show_config_menu
				;;
			EXPORT_LEGACY_PROFILE)
				build_export_legacy_profile
				;;
			UPDATE)
				plugin_run_toolchain_updater "$_toolchainname" "" "" "2"
				# Loop will naturally redraw the menu
				;;
			SHOW_BUILDLOG)
				if [ -f "$workdir/lastbuild.log" ]; then
					ui_show_textbox "Last Build Log" "$workdir/lastbuild.log"
				else
					ui_show_msgbox "Log File" "No build log found."
				fi
				;;
			BACK | '')
				return 0
				;;
			esac
		else
			# Handle cancel/ESC
			return 0
		fi
	done
}

# Helper function to create a checklist for a specific module category.
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

	menu_init "$menu_title" "$menu_title"

	for module in "${module_list[@]}"; do
		local internal_name
		internal_name=$(build_get_module_long_name "$module")
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
ui_show_module_selection_menu() {
	while true; do
		menu_init "Select Module Category to Configure" "Module Category Selection"
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
	# Refactored to use while loop for robust navigation
	while true; do
		menu_init "Configuration for '$_toolchainname'" "OScam Configuration"
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
			return 0
		fi
	done
}

# Menu dedicated to managing toolchains (Add, Remove, Create).
ui_show_toolchain_management_menu() {
	err_push_context "ui_show_toolchain_management_menu"
	while true; do
		toolchain_fill_arrays

		local title_main_menu="-[ Toolchain Management ]-"
		menu_init "Select a toolchain management task" "$title_main_menu"

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
		CREATE) plugin_run_toolchain_updater "-c" "" "" "1" ;;
		REMOVE) ui_show_toolchain_remove_menu ;;
		esac
	done
	err_pop_context
}

# This menu is solely for SELECTING a toolchain to start a build.
ui_show_toolchain_selection_menu() {
	toolchain_fill_arrays

	local rev_info
	local revision
	revision=$(repo_get_revision)
	if repo_is_git; then
		local commit branch
		commit=$(repo_get_commit)
		branch=$(repo_get_branch)
		rev_info="${revision}${commit:+" @ $commit"}${branch:+" @ $branch"}"
	fi
	local text_main_menu="${txt_main_revision}${rev_info}"
	local title_main_menu="-[ Select Toolchain to Build $(repo_get_identifier) ]-"
	menu_init "$text_main_menu" "$title_main_menu"

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

# Private helper encapsulating all archive download, checksum, and extraction.
# Shared by both interactive install and repair routines.
# Usage: _toolchain_install_archive "$toolchain_name" "repair|install"
_toolchain_install_archive() {
	local toolchain_name="$1"
	local mode="${2:-install}" # "repair" or "install" - affects logging and behavior
	err_push_context "Install toolchain '$toolchain_name' ($mode)"

	err_validate_file_exists "$tccfgdir/$toolchain_name" "Toolchain config"
	if ! cfg_load_file "toolchain" "$tccfgdir/$toolchain_name"; then
		log_fatal "Failed to parse toolchain configuration for '$toolchain_name'." "$EXIT_INVALID_CONFIG"
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
		log_info "Archive '$archive_filename' found locally. Verifying checksum..."

		local actual_md5
		actual_md5=$(md5sum "$archive_path" | awk '{print $1}')

		if [[ "$actual_md5" == "$expected_md5" ]]; then
			log_info "Checksum validation successful. Skipping download."
			needs_download=false
		else
			log_warn "Checksum validation failed. Removing corrupted archive and re-downloading."
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
		toolchain_url=$(sys_decode_base64 "$toolchain_url_b64")

		if [[ "$mode" == "repair" ]]; then
			log_header "Downloading Toolchain: $archive_filename"
		fi

		# Unified download and checksum logic
		if ! net_download_file "$toolchain_url" "$archive_path" "ui_show_progressbox 'Downloading Toolchain' 'Downloading $archive_filename'"; then
			log_fatal "Failed to download toolchain from '$toolchain_url'." "$EXIT_NETWORK"
		fi
		log_info "Download complete. Verifying checksum..."
		if ! md5sum -c <<<"$expected_md5  $archive_path" &>/dev/null; then
			log_fatal "Checksum validation failed after download for '$archive_path'." "$EXIT_ERROR"
		fi
		log_info "Checksum for downloaded file is correct."
	fi

	log_header "Installing Toolchain: $toolchain_name"
	local extract_strip
	extract_strip=$(cfg_get_value "toolchain" "_extract_strip" "0")
	local dest_dir="$tcdir/$toolchain_name"

	if ! file_extract_archive "$archive_path" "$dest_dir" "ui_show_progressbox 'Extracting Toolchain' 'Extracting $(basename "$archive_path")'" "$extract_strip" "true"; then
		log_fatal "Toolchain extraction failed." "$EXIT_ERROR"
	fi

	log_info "Toolchain '$toolchain_name' has been successfully ${mode}ed."
	err_pop_context
	return 0
}

_toolchain_check() {
	local tc_name="$1"
	err_push_context "Toolchain Check: $tc_name"

	log_header "Checking Toolchain: $tc_name"

	local -a headervars=(crypto.h pcsclite.h libusb.h pthread.h dvbcsa.h zlib.h)
	if ! cfg_load_file "toolchain" "$tccfgdir/$tc_name"; then
		log_error "Failed to load toolchain config for '$tc_name'"
		err_pop_context
		return 1
	fi

	# Define formats for aligned output.
	# NOTE: Retaining color variables ($w_l, $y_l, etc.) assuming they are globally available from initializeANSI.
	# If not, standard log functions should be used instead.
	local fmtg="  ${w_l}%-16s ${y_l}%-20s ${g_l}%-8s $p_l%-20s %-17s ${g_l}%s"
	local fmtb="  ${w_l}%-16s ${y_l}%-20s ${r_l}(%s)"

	if ! cd "$tcdir/$tc_name/bin"; then
		log_error "Toolchain '$tc_name' is not installed at $tcdir/$tc_name"
		err_pop_context
		return 1
	fi

	log_plain "${C}Compiler info -----> $tc_name${w_l}"

	local _compiler
	_compiler=$(cfg_get_value "toolchain" "_compiler")
	local _realcompiler
	_realcompiler=$(cfg_get_value "toolchain" "_realcompiler")
	local _androidndkdir
	_androidndkdir=$(cfg_get_value "toolchain" "_androidndkdir")
	local _sysroot
	_sysroot=$(cfg_get_value "toolchain" "_sysroot")

	local sysroot compilername
	if [ -z "$sysroot" ] && [ ! "$tc_name" == "native" ]; then
		compilername="$_compiler""gcc"
		[ ${#_realcompiler} -gt 4 ] && compilername="$_realcompiler"
		local version
		version=$("./$compilername" -dumpversion)
		local sr
		[ "$_androidndkdir" == "1" ] && sr="$tcdir/$tc_name/sysroot" || sr=$("./$compilername" -print-sysroot 2>/dev/null)
		sysroot=$(realpath -sm "$sr" --relative-to="$tcdir/$tc_name")
		local compilerpath
		compilerpath=$(realpath -sm "./$compilername" --relative-to="$tcdir/$tc_name")

		log_plain "$(printf "$fmtg" "GCC Version :" "$version" "" "" "")"
		log_plain "$(printf "$fmtg" "GCC Binary  :" "$compilerpath" "" "" "")"
		log_plain "$(printf "$fmtg" "GCC Sysroot :" "$sysroot" "" "" "")"

		local gversion
		gversion=$("./$_compiler""gdb" --version 2>/dev/null | head -n1 | awk '{print $NF}')
		[ -n "$gversion" ] && log_plain "$(printf "$fmtg" "GDB Version :" "$gversion" "" "" "")"

		local lversion
		lversion=$("./$_compiler""ld" --version 2>/dev/null | head -n1 | awk '{print $NF}')
		[ -n "$lversion" ] && log_plain "$(printf "$fmtg" "LD Version  :" "$lversion" "" "" "")"

		log_plain "$(printf "$fmtg" "HOST arch   :" "$(_get_compiler_arch host)" "" "" "")"
		log_plain "$(printf "$fmtg" "TARGET arch :" "$(_get_compiler_arch target)" "" "" "")"
		log_plain "$(printf "$fmtg" "C11 Support :" "$(! _check_compiler_capability 'c11' && printf 'No' || printf 'Yes')" "" "" "")"
		[ -z "$sysroot" ] && sysroot="$r_l$txt_too_old"
	fi

	if [ "$tc_name" == "native" ]; then
		log_plain "$(printf "$fmtg" "GCC Version :" "$(gcc --version | head -n 1)" "" "" "")"
		log_plain "$(printf "$fmtg" "GCC Binary  :" "$(which $(gcc -dumpmachine)-gcc || which gcc)" "" "" "")"
	fi

	log_plain "${C}Sysroot config ----> $_sysroot${w_l}"

	if ! ([ "$tc_name" == "native" ] && cd "$_sysroot" || cd "$tcdir/$tc_name/$_sysroot"); then
		log_error "Could not enter sysroot directory for '$tc_name'"
		err_pop_context
		return 1
	fi

	local linux linuxc linuxv
	linux="$(_linux_version $([ "$tc_name" == "native" ] && printf "/usr/src/linux-headers-$(uname -r)" || printf "."))"
	linuxc="$(echo "$linux" | awk -F';' '{print $1}')"
	linuxv="$(echo "$linux" | awk -F';' '{print $2}')"
	[ ! -z "$linux" ] && log_plain "$(printf "$fmtg" "Linux       :" "version.h" "${linuxv::8}" "$linuxc" "")" || log_plain "$(printf "$fmtb" "Linux       :" "version.h" "missing linux headers")"

	local libc libcf libcl libcv
	libc="$(_libc_version "$tc_name")"
	libcf="$(echo "$libc" | awk -F';' '{print $1}')"
	libcl="$(echo "$libc" | awk -F';' '{print $2}')"
	libcv="$(echo "$libc" | awk -F';' '{print $3}')"
	[ ! -z "$libcl" ] && log_plain "$(printf "$fmtg" "C-Library   :" "${libcf::20}" "${libcv::8}" "$libcl" "")" || log_plain "$(printf "$fmtb" "C-Library   :" "${libcf::20}" "$txt_not_found")"

	for e in "${headervars[@]}"; do
		local temp
		temp=$(find * | grep -wm1 "$e")
		[ ${#temp} -gt 5 ] && log_plain "$(printf "$fmtg" "Header File :" "${e::20}" "$txt_found" "" "" "")" || log_plain "$(printf "$fmtb" "Header File :" "${e::20}" "$txt_not_found")"
	done

	local pkgs
	[ "$tc_name" == "native" ] && pkgs=$(find ../* -name "pkgconfig" -type d) || pkgs=$(find . -name "pkgconfig" -type d)
	if [ ${#pkgs} -gt 0 ]; then
		for pkg in ${pkgs}; do
			if [ "$tc_name" == "native" ]; then
				cd "$_sysroot/$pkg" || continue
				log_plain "${C}Library config ----> $PWD${w_l}"
			else
				cd "$tcdir/$tc_name/$_sysroot/$pkg" || continue
				log_plain "${C}Library config ----> $(realpath -sm "$PWD" --relative-to="$tcdir/$tc_name")${w_l}"
			fi

			for f in *.pc; do
				[ -e "$f" ] || continue
				unset type
				local ff="${f/zlib/"libz"}"
				ff="${ff/openssl/"libcrypto"}"
				local content na ver
				content=$(cat "$f" 2>/dev/null) && na=$(echo "$content" | grep 'Name:' | sed -e "s/Name: //g") && ver=$(echo "$content" | grep 'Version:' | sed -e "s/Version: //g")
				[ -n "$(find "$PWD/../" -name "${ff%.*}.a" -xtype f -print -quit)" ] && type="static"
				[ -n "$(find "$PWD/../" \( -name "${ff%.*}.so" -o -name "${ff%.*}.so.*" \) -xtype f -print -quit)" ] && type+="$([ -n "$type" ] && echo '+')dynamic"
				[ ${#content} -gt 0 ] && log_plain "$(printf "$fmtg" "Library Config :" "${f::20}" "$txt_found" "${na::20}" "$ver" "$type")" || log_plain "$(printf "$fmtb" "Library Config :" "${f::20}" "($txt_not_found)")"

			done
		done
	else
		log_plain "${C}Library config ----> no libraries found in pkgconfig${w_l}"
	fi

	log_plain "$re_"
	err_pop_context
	return 0
}

# Unified helper for toolchain add/remove menus.
# Usage: _ui_show_toolchain_menu "add|remove" "list_ref" "menu_title"
_ui_show_toolchain_menu() {
	local mode="$1"     # "add" or "remove"
	local list_ref="$2" # "MISS_TCLIST" or "INST_TCLIST"
	local menu_title="$3"

	toolchain_fill_arrays

	menu_init "$menu_title" "$menu_title"

	if [ "$tcempty" == "0" ]; then
		local -a list_arr
		declare -n list_arr="$list_ref" # Use nameref to access the correct array
		for i in "${list_arr[@]}"; do
			if [ ! "$i" == "native" ]; then
				# Use Unified Configuration Manager (UCM) for secure loading
				if cfg_load_file "toolchain" "$tccfgdir/$i"; then
					local toolchain_name=$(cfg_get_value "toolchain" "_toolchainname" "$i")
					local description=$(cfg_get_value "toolchain" "_description" "No description")
					menu_add_option "$toolchain_name" "$description"
				else
					log_warn "Could not load or parse toolchain config for $mode menu: $i"
				fi
			fi
		done
	fi
	menu_add_option "EXIT" "$txt_menu_builder1"

	if menu_show_list; then
		local selection
		selection="$(menu_get_first_selection)"

		case "$selection" in
		EXIT) sys_exit ;;
		*)
			if [[ "$mode" == "add" ]]; then
				# Install selected toolchain
				first="$selection"
				ui_install_toolchain_interactive
			else
				# Remove selected toolchain
				if [[ -d "$tcdir/$selection" ]]; then
					validate_command "Removing toolchain '$selection'" rm -rf "$tcdir/$selection"
				fi
			fi
			;; # After action, loop will show the management menu again
		esac
	else
		# Handle cancel/ESC
		return 0
	fi
}

ui_show_toolchain_add_menu() {
	_ui_show_toolchain_menu "add" "MISS_TCLIST" " -[ $txt_add_menu$(repo_get_identifier) ]-"
}

ui_show_toolchain_remove_menu() {
	_ui_show_toolchain_menu "remove" "INST_TCLIST" " -[ $txt_remove_menu$(repo_get_identifier) ]-"
}

sys_repair_toolchain() {
	local toolchain_name="$1"
	err_push_context "Repair toolchain '$toolchain_name'"
	clear
	ui_show_s3_logo

	_toolchain_install_archive "$toolchain_name" "repair"

	err_pop_context
	sleep 2
	return 0
}

ui_install_toolchain_interactive() {
	local toolchain_name="$first" # 'first' is a global from the menu selection
	err_push_context "Install toolchain '$toolchain_name' interactively"

	_toolchain_install_archive "$toolchain_name" "install"

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

		menu_init "EMU & SoftCam Settings" "EMU & SoftCam Settings"
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
				sys_exit # Exit the whole application
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
	menu_init "$title" "$title"

	for opt in "${options[@]}"; do
		local state="off"
		# Special check for non-USE_vars
		if [[ "$opt" == "WITH_EMU" || "$opt" == "MODULE_STREAMRELAY" ]]; then
			[[ "$("${repodir}/config.sh" --enabled "$opt")" == "Y" ]] && state="on"
		else
			[[ "${USE_vars[$opt]}" == "1" ]] && state="on"
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
					USE_vars[$opt]="1"
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
				USE_vars[$opt]="1"
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

	menu_init "Select STAPI Mode" "STAPI Configuration"
	menu_add_option "STAPI_OFF" "Disable STAPI" "on"
	menu_add_option "USE_STAPI" "Enable STAPI" "off"
	menu_add_option "USE_STAPI5_UFS916" "Enable STAPI5 (UFS916)" "off"
	menu_add_option "USE_STAPI5_UFS916003" "Enable STAPI5 (UFS916003)" "off"
	menu_add_option "USE_STAPI5_OPENBOX" "Enable STAPI5 (OPENBOX)" "off"

	if menu_show_radiolist; then
		local selection
		selection="$(menu_get_first_selection)"

		stapivar=""
		# Reset STAPI-related USE_vars for a clean slate, then re-add based on selection.
		unset 'USE_vars[USE_STAPI]' 'USE_vars[USE_STAPI5]'
		case "$selection" in
		STAPI_OFF) stapivar= ;;
		USE_STAPI)
			[ -z "$stapi_lib_custom" ] && stapivar="STAPI_LIB=$sdir/stapi/liboscam_stapi.a" || stapivar="STAPI_LIB=$sdir/stapi/${stapi_lib_custom}"
			USE_vars[USE_STAPI]="1"
			;;
		USE_STAPI5_UFS916)
			stapivar="STAPI5_LIB=$sdir/stapi/liboscam_stapi5_UFS916.a"
			USE_vars[USE_STAPI5]="1"
			;;
		USE_STAPI5_UFS916003)
			stapivar="STAPI5_LIB=$sdir/stapi/liboscam_stapi5_UFS916_0.03.a"
			USE_vars[USE_STAPI5]="1"
			;;
		USE_STAPI5_OPENBOX)
			stapivar="STAPI5_LIB=$sdir/stapi/liboscam_stapi5_OPENBOX.a"
			USE_vars[USE_STAPI5]="1"
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
		validate_command "Disabling WITH_COMPRESS for sh4" "${repodir}/config.sh" --disable WITH_COMPRESS
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
	if [[ "$stapi_allowed" == "1" && "${#stapivar}" -gt "15" ]]; then
		[[ "${USE_vars[USE_STAPI]}" == "1" ]] && use_vars_string="$use_vars_string USE_STAPI" || use_vars_string="$use_vars_string USE_STAPI5"
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
	if [[ -f "$menudir/$_toolchainname.save" ]]; then
		validate_command "Removing legacy build save file" rm -f "$menudir/$_toolchainname.save"
	fi
	err_pop_context
}

load_config() {
	err_push_context "load_config"
	log_debug "Loading build configuration for '$_toolchainname'"

	# Clear previous state
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
			validate_command "Resetting all modules before load" "${repodir}/config.sh" -D all
			if [[ -n "$enabled_modules" ]]; then
				validate_command "Enabling modules from profile" "${repodir}/config.sh" -E $enabled_modules
			fi
			# NOTE: Disabled modules are saved but rarely need re-application after a full reset.
			# This could be added if specific use cases require it.

			# Re-populate USE_vars array
			for var in $use_vars_string; do
				USE_vars[$var]="1"
			done
		fi
	else
		log_debug "No saved config found. Applying defaults."
		build_reset_config
		if [[ "$(cfg_get_value "s3" "USE_TARGZ")" == "1" ]]; then
			USE_vars[USE_TARGZ]="1"
		fi
		# Get default_use from the toolchain config, which should already be loaded
		local default_use
		default_use=$(cfg_get_value "toolchain" "default_use")
		for var in $default_use; do
			USE_vars[$var]="1"
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
