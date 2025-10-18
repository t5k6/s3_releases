#!/bin/bash

_nl() {
	printf "$rs_\n"
}
_set_dialog_types() {
	gui="$(type -pf dialog)"
	st_="--stdout"
	ib_="--infobox"
	ip_="--inputbox"
	nc_="--no-cancel"
	cl_="--checklist"
	rl_="--radiolist"
	bt_="--backtitle"
	pb_="--progressbox"
	title_="SIMPLEBUILD3 $(version | tr '\n' ' ')"
}

cedit() {
	ui_edit_s3_config
	bye
}
counter() {
	COUNT="$((COUNT + 1))"
}
timer_calc() {
	Tcalc="$((Te - Ts))"
}
timer_stop() {
	Te="$(date +%s)"
}
timer_start() {
	Ts="$(date +%s)"
}
decode() {
	# Decodes a base64 string. Returns non-zero if input is empty or invalid.
	[[ -n "$1" ]] && printf "%s" "$1" | base64 -d 2>/dev/null
}
get_module_name() {
	printf "${INTERNAL_MODULES[$1]}"
}

_wait() {
	printf "$w_l\n"
	read -n1 -r -p "  $txt_help3" key
	tput cuu1
	printf '                                          '
}
_systype() {
	systype="bad"
	case "$(uname -m)" in
	x86 | x86_64 | amd64 | i686)
		systype="ok"
		;;
	esac
}

_generate_oscam_name() {
	cd "${repodir}"
	_dvbapi=$(
		[ "$(./config.sh --enabled HAVE_DVBAPI)" == Y ] && echo -dvbapi || printf ''
	)
	_dvbapi=$(
		[ "$(./config.sh --enabled CARDREADER_GXAPI)" == Y ] && echo -gxapi || echo -n $_dvbapi
	)
	_webif=$(
		[ "$(./config.sh --enabled WEBIF)" == Y ] && echo -webif || printf ''
	)
	_ssl=$(
		[ "$(./config.sh --enabled WITH_SSL)" == Y ] && echo -ssl || printf ''
	)
	_emu=$(
		[ "$(./config.sh --enabled WITH_EMU)" == Y ] && echo -emu || printf ''
	)
	_neon=$(
		[ "$(./config.sh --enabled WITH_ARM_NEON)" == Y ] && "$tcdir/$_toolchainname/bin/$_compiler""gcc" -dumpmachine 2>/dev/null | grep -i -E '(arm|aarch64)' &>/dev/null && echo -neon || printf ''
	)
	_icam=$(
		[ "$(./config.sh --enabled MODULE_STREAMRELAY)" == Y ] && echo -icam || printf ''
	)
	_ipv6=$(
		[ "$(./config.sh --enabled IPV6SUPPORT)" == Y ] && echo -ipv6 || printf ''
	)
	_signed=$(
		[ "$(./config.sh --enabled WITH_SIGNING)" == Y ] && echo -signed || printf ''
	)
	[ "${USE_vars[USE_COMPRESS]}" == "USE_COMPRESS=1" ] && _upx="-upx" || _upx=''
	[ "$1" == "native" ] && _b_name="$(uname -s)-$(uname -m)" || _b_name="$1"
	if [ "${s3cfg_vars[ADD_PROFILE_NAME]}" == "0" ] || [ $pf_name == "not_set" ]; then
		oscam_name="oscam-${REPO}$(REVISION)$($(USEGIT) && printf "@$(COMMIT)" || printf "")-$_b_name$_webif$_dvbapi$_ssl$_usb$_pcsc$_dvbcsa$_stapi$_stapi5$_emu$_ipv6$_icam$_neon$2$_upx$_signed"
	else
		oscam_name="oscam-${REPO}$(REVISION)$($(USEGIT) && printf "@$(COMMIT)" || printf "")-${pf_name%.*}"
	fi
}
e_readers() {
	silent=$("${repodir}/config.sh" -s readers)
	echo ${silent//READER_/}
}
e_protocols() {
	silent=$("${repodir}/config.sh" -s protocols)
	echo ${silent//MODULE_/}
}
e_card_readers() {
	silent=$("${repodir}/config.sh" -s card_readers)
	echo ${silent//CARDREADER_/}
}
e_addons() {
	"${repodir}/config.sh" -s addons | sed 's/WEBIF_//g;s/WITH_//g;s/MODULE_//g;s/CS_//g;s/HAVE_//g;s/_CHARSETS//g;s/CW_CYCLE_CHECK/CWCC/g;s/SUPPORT//g'
}
sysinfo() {
	printf "$g_l\nSYSTEM$w_l\n"
	system_info=$(type -pf lsb_release)
	[ ${#system_info} -ge 11 ] && lsb_release -irc
	printf "Uptime:\t\t$(uptime -p)\n"
	printf "$g_l\nMEMORY$w_l\n"
	free -mht | awk '/Mem/{print "Memory:\t\tTotal: " $2 "Mb\tUsed: " $3 "Mb\tFree: " $4 "Mb"} /Swap/{print "Swap:\t\tTotal: " $2 "Mb\tUsed: " $3 "Mb\tFree: " $4 "Mb" }'
	[ -f /sys/dev/block ] && lsblk
	printf "$g_l\n CPU$w_l\n"
	cpu_info=$(type -pf lscpu)
	[ ${#cpu_info} -ge 5 ] && lscpu | grep -iE 'model name|vendor id|Architecture|per socket|MHz'
	printf "$g_l\nNetwork\n"
	printf "$w_l""Hostname:\t$HOSTNAME\n"
	ip -o addr | awk '/inet /{print "IP (" $2 "):\t" $4}'
	ip route | awk '/default/ { printf "Gateway:\t"$3"\n" }'
	awk '/^nameserver/{ printf "Name Server:\t" $2 "\n"}' /etc/resolv.conf
	printf "$re_\n"
}
_sz() {
	lmin=24
	lmax=40
	_lin=$(tput lines)
	cmin=79
	cmax=200
	_col=$(tput cols)
	if [ "$_lin" -gt "$lmin" ]; then
		if [ "$_lin" -lt "$lmax" ] || [ "$_lin" -eq "$lmax" ]; then
			_lines="$((_lin - 6))"
		fi
		if [ "$_lin" -gt "$lmax" ]; then
			_lines="$((lmax - 6))"
		fi
	fi
	if [ "$_col" -gt "$cmin" ]; then
		if [ "$_col" -lt "$cmax" ] || [ "$_col" -eq "$cmax" ]; then
			_cols="$((_col - 6))"
		fi
		if [ "$_col" -gt "$cmax" ]; then
			_cols="$((cmax - 6))"
		fi
	fi
}

build_ensure_openssl() {
	local sysroot="$1"
	local toolchain_path="$2" # This is the path to the toolchain's root, e.g. .../toolchains/oe20_armv7
	local cc="$3"             # This is the full compiler name, e.g. .../bin/arm-linux-gcc
	local openssl_version
	openssl_version=$(cfg_get_value "s3" "S3_OPENSSL_VERSION" "1.1.1w")

	err_push_context "Dependency Check: OpenSSL"

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
		menu_init "SimpleBuild3 Main Menu"
		menu_add_option "BUILD" "Build OScam"
		menu_add_separator
		menu_add_option "REPO" "Manage Repository"
		menu_add_option "TOOLCHAINS" "Manage Toolchains"
		menu_add_option "SYSTEM" "System & Configuration"
		menu_add_separator
		menu_add_option "UPDATE_S3" "Update SimpleBuild"
		menu_add_option "EXIT" "Exit"

		if ! menu_show_list; then
			bye # User pressed Cancel or ESC
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
		EXIT) bye ;;
		esac
	done
	err_pop_context
}

# Menu to manage the source code repository.
ui_show_repository_menu() {
	err_push_context "ui_show_repository_menu"
	while true; do
		menu_init "Repository Management"
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
		EXIT) bye ;;
		esac
	done
	err_pop_context
}

# Menu for system and configuration tasks.
ui_show_system_config_menu() {
	err_push_context "ui_show_system_config_menu"
	while true; do
		menu_init "System & Configuration"
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
		SSH_PROFILES) ssh_editor ;;
		SYSCHECK) syscheck auto now ;;
		BACK) return 0 ;;
		EXIT) bye ;;
		esac
	done
	err_pop_context
}

_gtedit() {
	local toolchain_name="$1"
	if [ -f "$tccfgdir/$toolchain_name" ]; then
		# Source the specific toolchain config to get its current values
		source "$tccfgdir/$toolchain_name"

		local confdir
		confdir=$(ui_get_input " -[ $toolchain_name Toolchain$(REPOIDENT) ]- " "Enter new CONF_DIR path. Default is '$_oscamconfdir_default'." "$_oscamconfdir_custom")

		case "$?" in
		0)
			# If user entered something
			if [ -n "$confdir" ]; then
				validate_command "Updating toolchain config" sed -i "s@^_oscamconfdir_custom.*@_oscamconfdir_custom=\"$confdir\"@" "$tccfgdir/$toolchain_name"
			else # User cleared the input, revert to default
				validate_command "Updating toolchain config" sed -i "s@^_oscamconfdir_custom.*@_oscamconfdir_custom=\"\"@" "$tccfgdir/$toolchain_name"
			fi
			;;
		*)
			# ESC or cancel - keep current setting
			: # Do nothing
			;;
		esac
	fi
}
check_smargo() {
	build_check_smargo_deps
}
build_check_smargo_deps() {
	if [ -f "${repodir}/config.sh" ]; then
		if [ "$("${repodir}/config.sh" --enabled CARDREADER_SMARGO)" == "Y" ]; then
			USE_vars[USE_LIBUSB]="USE_LIBUSB=1"
		else
			USE_vars[USE_LIBUSB]=
		fi
	fi
}
build_check_streamrelay_deps() {
	if [ -f "${repodir}/config.sh" ]; then
		if [ "$("${repodir}/config.sh" --enabled MODULE_STREAMRELAY)" == "Y" ]; then
			USE_vars[USE_LIBDVBCSA]="USE_LIBDVBCSA=1"
		else
			USE_vars[USE_LIBDVBCSA]=
		fi
	fi
}
check_signing() {
	if [ -f "$configdir/sign" ]; then
		source "$configdir/sign"
		if [ -f "$x509cert" ] && [ -f "$privkey" ] && [ -f "$repodir/config.sh" ]; then
			if [ "$("${repodir}/config.sh" --enabled WITH_SIGNING)" == "Y" ]; then
				"${repodir}/config.sh" --add-cert "$x509cert" "$privkey"
				printf "$YH\n |   SIGNING : use provided $(basename $x509cert) and $(basename $privkey) files"
			fi
		fi
	fi
}
set_buildtype() {
	local statcount=0
	local libcount=0

	[ "$_toolchainname" == "native" ] && SEARCHDIR="$(ldconfig -v 2>/dev/null | grep -v ^$'\t' | awk -F':' '{print $1}')" || SEARCHDIR="$SYSROOT"

	# For each potential static library, check if static linking is requested.
	# If so, increment libcount. Then try to find the .a file and increment statcount on success.

	if [[ "${USE_vars[USE_STATIC]}" == "USE_STATIC=1" || "${USE_vars[STATIC_LIBCRYPTO]}" == "STATIC_LIBCRYPTO=1" ]]; then
		((libcount++))
		local found_lib
		found_lib=$(find "$SEARCHDIR" -name "libcrypto.a" -type f -print -quit 2>/dev/null)
		if [[ -n "$found_lib" ]]; then
			LIBCRYPTO_LIB="LIBCRYPTO_LIB=$found_lib"
			((statcount++))
		fi
	fi

	if [[ "${USE_vars[USE_STATIC]}" == "USE_STATIC=1" || "${USE_vars[STATIC_SSL]}" == "STATIC_SSL=1" ]]; then
		((libcount++))
		local found_lib
		found_lib=$(find "$SEARCHDIR" -name "libssl.a" -type f -print -quit 2>/dev/null)
		if [[ -n "$found_lib" ]]; then
			SSL_LIB="SSL_LIB=$found_lib"
			((statcount++))
		fi
	fi

	if [[ "${USE_vars[USE_STATIC]}" == "USE_STATIC=1" || "${USE_vars[STATIC_LIBUSB]}" == "STATIC_LIBUSB=1" ]]; then
		((libcount++))
		local found_lib
		found_lib=$(find "$SEARCHDIR" -name "libusb-1.0.a" -type f -print -quit 2>/dev/null)
		if [[ -n "$found_lib" ]]; then
			LIBUSB_LIB="LIBUSB_LIB=$found_lib"
			((statcount++))
		fi
	elif [[ "$_androidndkdir" == "1" ]]; then
		LIBUSB_LIB="LIBUSB_LIB=-lusb-1.0"
	fi

	if [[ "${USE_vars[USE_STATIC]}" == "USE_STATIC=1" || "${USE_vars[STATIC_PCSC]}" == "STATIC_PCSC=1" ]]; then
		((libcount++))
		local found_lib
		found_lib=$(find "$SEARCHDIR" -name "libpcsclite.a" -type f -print -quit 2>/dev/null)
		if [[ -n "$found_lib" ]]; then
			PCSC_LIB="PCSC_LIB=$found_lib"
			((statcount++))
		fi
	fi

	if [[ "${USE_vars[USE_STATIC]}" == "USE_STATIC=1" || "${USE_vars[STATIC_LIBDVBCSA]}" == "STATIC_LIBDVBCSA=1" ]]; then
		((libcount++))
		local found_lib
		found_lib=$(find "$SEARCHDIR" -name "libdvbcsa.a" -type f -print -quit 2>/dev/null)
		if [[ -n "$found_lib" ]]; then
			LIBDVBCSA_LIB="LIBDVBCSA_LIB=$found_lib"
			((statcount++))
		fi
	fi

	# Determine buildtype based on counts.
	if [[ "$statcount" -gt 0 && "$statcount" -lt "$libcount" ]]; then
		printf "$y_l\n | BUILDTYPE : mixed"
		buildtype="-mixed"
	elif [[ "$libcount" -gt 0 && "$statcount" -eq "$libcount" ]]; then
		printf "$y_l\n | BUILDTYPE : static"
		buildtype="-static"
	else
		printf "$y_l\n | BUILDTYPE : dynamic"
		buildtype=""
	fi
}
_reset_config() {
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
	menu_init "Select Log Level"
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

	menu_init "Enable/Disable SimpleBuild3 Options"
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

	# Part 3: Select OpenSSL version using the new dynamic menu
	if menu_yes_no "Change OpenSSL version for dependency builds?"; then
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

	menu_init "Select OpenSSL Version"
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
_stapi_select() {
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
		usevars=$(echo $usevars | sed "s@USE_STAPI5@@" | xargs)
		usevars=$(echo $usevars | sed "s@USE_STAPI@@" | xargs)

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
	usevars=
	enabled=
	disabled=
	build_check_smargo_deps
	enabled=($("${repodir}/config.sh" -s))
	disabled=($("${repodir}/config.sh" -Z))
	[ "$_toolchainname" == "sh4" ] && silent=$("${repodir}/config.sh" --disable WITH_COMPRESS)
	[ "$_toolchainname" == "sh_4" ] && silent=$("${repodir}/config.sh" --disable WITH_COMPRESS)
	unset USE_vars[USE_STAPI]
	unset USE_vars[USE_STAPI5]

	for e in ${USE_vars[*]}; do
		usevars="${e:0:-2} $usevars"
	done

	[ -f "$menudir/$_toolchainname.save" ] && rm -rf "$menudir/$_toolchainname.save"
	printf "enabled=\"${enabled[*]}\"\n" >"$menudir/$_toolchainname.save"
	printf "disabled=\"${disabled[*]}\"\n" >>"$menudir/$_toolchainname.save"
	if [ "$stapi_allowed" == "1" ]; then
		if [ "${#stapivar}" -gt "15" ]; then
			printf "stapivar=\"$stapivar\"\n" >>"$menudir/$_toolchainname.save"
			printf "usevars=\"$usevars $addstapi\"\n" >>"$menudir/$_toolchainname.save"
		else
			printf "usevars=\"$usevars\"\n" >>"$menudir/$_toolchainname.save"
		fi
	else
		printf "usevars=\"$usevars\"\n" >>"$menudir/$_toolchainname.save"
	fi
}
load_config() {
	_stapi=
	_stapi5=
	enabled=
	disabled=
	stapivar=""
	USESTRING=
	usevars=
	unset USE_vars[USE_STAPI]
	unset USE_vars[USE_STAPI5]
	if [ -f "$menudir/$_toolchainname.save" ]; then
		source "$menudir/$_toolchainname.save"
		ena=$("${repodir}/config.sh" -E $enabled)
		dis=$("${repodir}/config.sh" -D $disabled)
		for e in $usevars; do
			USE_vars[$e]="$e=1"
			[ "$e" == "USE_LIBUSB" ] && silent=$("${repodir}/config.sh" --enable CARDREADER_SMARGO)
		done
	else
		_reset_config
		[ "${s3cfg_vars[USE_TARGZ]}" == "1" ] && USE_vars[USE_TARGZ]="USE_TARGZ=1"
		for e in $default_use; do
			USE_vars[$e]="$e=1"
		done
	fi
	check_smargo
	build_check_streamrelay_deps
	[ "$_toolchainname" == "sh4" ] && silent=$("${repodir}/config.sh" --disable WITH_COMPRESS)
	[ "$_toolchainname" == "sh_4" ] && silent=$("${repodir}/config.sh" --disable WITH_COMPRESS)
	USESTRING="$(echo "${USE_vars[@]}" | sed 's@USE_@@g' | sed 's@=1@@g' | tr -s ' ')"
}
_get_config_con() {
	if [ ! "$1" == "checkout" ] && [ ! "$1" == "clean" ]; then
		tmp="$(mktemp)"

		if [ -f "${repodir}/config.sh" ]; then
			while read -r _l; do
				c=$(echo "$_l" | tr -cd \" | wc -c)
				_c=$((_c + c))
				[ ${_c} -lt 11 ] && echo "$_l" >>"$tmp"
				[ ${_c} -eq 10 ] && break
			done <"${repodir}/config.sh"
		else
			while read -r _l; do
				c=$(echo "$_l" | tr -cd \" | wc -c)
				_c=$((_c + c))
				[ ${_c} -lt 11 ] && echo "$_l" >>"$tmp"
				[ ${_c} -eq 10 ] && break
			done <"$configdir/config.sh.master"
		fi

		if [ -f "${repodir}/Makefile" ]; then
			str_="$(grep '^   USE_' "${repodir}/Makefile" | sort -u | awk '{print $1}')"
			for e in $str_; do
				es="${e:0:-2}"
				USE_vars[$es]=
			done
		else
			if [ -f "$configdir/Makefile.master" ]; then
				str_="$(grep '^   USE_' "$configdir/Makefile.master" | sort -u | awk '{print $1}')"
				for e in $str_; do
					es="${e:0:-2}"
					USE_vars[$es]=
				done
			fi
		fi

		check_smargo
		build_check_streamrelay_deps
		source "$tmp"
		rm -rf "$tmp" "$tmp1"
		rm -rf "$tmp.load" "$tmp1.load"
	fi
}

version() {
	echo -e "${SIMPLEVERSION}.${VERSIONCOUNTER} by ${DEVELOPER}\n- in memory of gorgone -"
}
tcupdate() {
	plugin_run_toolchain_updater "$1" "$2" "$3" "$4"
}
