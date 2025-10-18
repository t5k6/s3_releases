#!/bin/bash

profiles() {
	_list_profiles
	exit
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

_save_profile() {
	err_push_context "_save_profile"

	# Retrieve the current build configuration from the UCM cache.
	# This cache should be populated by previous actions in the build menu.
	local namespace="build_profile:$_toolchainname"
	local enabled_modules use_vars
	enabled_modules=$(cfg_get_value "$namespace" "enabled_modules")
	use_vars=$(cfg_get_value "$namespace" "use_vars")

	if [[ -z "$enabled_modules" && -z "$use_vars" ]]; then
		ui_show_msgbox "Error" "No build configuration is currently loaded for '$_toolchainname'.\nPlease configure the build before saving a profile."
		err_pop_context
		return 1
	fi

	local profile_name
	profile_name=$(ui_get_input "Save Build Profile" "Enter a name for this profile:" "$_toolchainname")

	if [[ -z "$profile_name" ]]; then
		log_info "Profile save cancelled by user."
		err_pop_context
		return 0
	fi

	# The .profile format is a space-separated list of short module names and USE_ vars.
	# Convert the long module names from the config into their short forms.
	local profile_content
	profile_content=$(echo "$enabled_modules $use_vars" | sed -e 's/CARDREADER_//g;s/READER_//g;s/MODULE_//g;s/HAVE_//g;s/WEBIF_//g;s/WITH_//g;s/CS_//g;s/_CHARSETS//g;s/CW_CYCLE_CHECK/CWCC/g;s/SUPPORT//g;')

	local profile_path="$profdir/$profile_name.profile"

	# Use printf for robust file writing.
	if ! printf "%s\n" "$profile_content" >"$profile_path"; then
		log_error "Failed to write profile to '$profile_path'. Check permissions."
		ui_show_msgbox "Error" "Failed to save profile file."
		err_pop_context
		return 1
	fi

	log_info "Profile saved successfully: $profile_path"
	ui_show_msgbox "Success" "Profile '$profile_name.profile' has been saved."
	err_pop_context
}

_load_profile() {
	if [ "$(ls -A "$profdir")" ]; then
		ok=0
		loadprofile="no"
		USESTRING=
		_create_module_arrays
		cd "$profdir"
		p_files=(*.profile)

		menu_init "$txt_select_profile_title"

		for e in "${p_files[@]}"; do
			menu_add_option "$e" "$e" "off"
		done

		if menu_show_list; then
			pselect="$(menu_get_first_selection)"
		else
			# Cancel/ESC pressed - return to build menu
			loadprofile="yes"
			ui_show_build_menu
			return
		fi

		ui_show_msgbox "$txt_confirm_profile_select" "$pselect"

		if [ -f "$profdir/$pselect" ]; then
			profile_vars=$(cat "$profdir/$pselect")
			reset_="$("${repodir}/config.sh" -D all)"

			for e in "${!USE_vars[@]}"; do
				USE_vars[$e]=
			done

			for e1 in $profile_vars; do
				for e2 in "${!USE_vars[@]}"; do
					[ "$e1" == "$e2" ] && USE_vars[$e1]="$e1=1"
				done
				for sm in "${SHORT_MODULENAMES[@]}"; do
					if [ "$e1" == "$sm" ]; then
						_em_="$_em_ $(get_module_name "$sm")"
					fi
				done
			done

			_set_=$("${repodir}/config.sh" -E $_em_)
			USESTRING="$(echo "${USE_vars[@]}" | sed 's@USE_@@g' | sed 's@=1@@g' | tr -s ' ')"
			loadprofile="yes"
		fi
	else
		ui_show_msgbox "Profile" "$txt_no_profile_found"
	fi
	loadprofile="no"
}

_create_native_profile() {

	[ ! -d "$tcdir/native/bin" ] && mkdir -p "$tcdir/native/bin"
	cd "$tcdir/native/bin"
	g="$(type -pf gcc)"
	gpp="$(type -pf g++)"
	stripvar="$(type -pf strip)"
	objcopy="$(type -pf objcopy)"
	objdump="$(type -pf objdump)"
	if [ -f $g ]; then
		compiler_link="$($g -dumpmachine)-gcc"
		[ -L "$compiler_link" ] || ln -sf "$g" "$compiler_link"
	fi
	if [ -f $gpp ]; then
		gpp_link="$($g -dumpmachine)-g++"
		[ -L "$gpp_link" ] || ln -sf "$gpp" "$gpp_link"
	fi
	if [ -f $stripvar ]; then
		strip_link="$($g -dumpmachine)-strip"
		[ -L "$strip_link" ] || ln -sf "$stripvar" "$strip_link"
	fi
	if [ -f $objcopy ]; then
		objcopy_link="$($g -dumpmachine)-objcopy"
		[ -L "$objcopy_link" ] || ln -sf "$objcopy" "$objcopy_link"
	fi
	if [ -f $objdump ]; then
		objdump_link="$($g -dumpmachine)-objdump"
		[ -L "$objdump_link" ] || ln -sf "$objdump" "$objdump_link"
	fi
	cd "$tccfgdir"

	if [ ! -f native ]; then
		cat <<EOF >native
_toolchainname="native";
default_use="USE_LIBCRYPTO";
_oscamconfdir_default="/usr/local/etc";
_oscamconfdir_custom="not_set";
_compiler="$($g -dumpmachine)-";
_tc_info="Native System Compiler \
$(gcc --version)";
_libsearchdir="/lib";
_menuname="native";
_sysroot="/usr/include";
EOF
	fi

	cd "$workdir"

}
