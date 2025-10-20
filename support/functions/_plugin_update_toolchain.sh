#!/bin/bash

# Source dependencies
source "$fdir/_error_handling.sh"

# =============================================================================
# SIMPLEBUILD3 PLUGIN - Toolchain Updater (s3.TUP)
# =============================================================================
# Manages the creation, modification, and updating of toolchains and their libraries.
# Refactored for Standardization, Robustness, and Abstraction.
# =============================================================================

# --- Plugin Metadata ---
pversion="0.27.0"
pname="s3.TUP"
pdesc="Plugin $pname v$pversion"

# --- Plugin Configuration & Paths ---
tc_url="aHR0cHM6Ly9zaW1wbGVidWlsZC5kZWR5bi5pby90b29sY2hhaW5zLw=="
configname="$configdir/plugin_update_toolchain.config"
configtemplate="${configname}.template"
ctdir="$sdir/crosstool"
cttpldir="$ctdir/templates"
ctngsrcdir="$ctdir/crosstool-ng"
fngsrcdir="$ctdir/freetz-ng"
andksrcdir="$ctdir/android-ndk"

# Retrieves the path to the pkgconfig directory for a given toolchain prefix.
_toolchain_get_pkgconfig_path() {
	local prefixdir="$1"
	local pkgdir

	# Try to find pkgconfig directory in common locations
	local pkgconfig_paths=("$prefixdir/lib/pkgconfig" "$prefixdir/usr/lib/pkgconfig" "$prefixdir/lib64/pkgconfig" "$prefixdir/usr/lib64/pkgconfig")

	for pkgdir in "${pkgconfig_paths[@]}"; do
		if [ -d "$pkgdir" ]; then
			echo "$pkgdir"
			return 0
		fi
	done

	# Fallback to default
	echo "$prefixdir/lib/pkgconfig"
}

# Checks if a given toolchain appears to be correctly installed.
toolchain_validate_installation() {
	local tc_name="$1"
	if [[ ! -d "$tcdir/$tc_name" ]]; then
		log_error "Toolchain '$tc_name' is not installed or its directory is missing."
		return 1
	fi
	return 0
}

# Main entry point for the toolchain updater plugin.
plugin_run_toolchain_updater() {
	err_push_context "Toolchain Updater Plugin"
	[ -f "$workdir/DEVELOPMENT" ] && disable_syscheck="1" && disable_template_versioning="1" && source "$workdir/DEVELOPMENT" # DEVELOPMENT should contain a CURL_GITHUB_TOKEN to avoid github rate limiting

	local sys_tc="$1"
	local option1="$2"
	local option2="$3"
	local flag="${4:-0}" #0 - from s3.TUP, 1 - from main menu, 2 - from build menu;
	local tc="$sys_tc"

	if [[ "$flag" -gt 0 && -z "$disable_syscheck" ]]; then
		plugin_check_dependencies_tcupdater
	fi

	# --- Configuration Handling ---
	if [ "$sys_tc" == "-r" ] || [ "$sys_tc" == "--reset" ]; then
		if [ -f "$configname" ]; then
			if ! net_check_github_api_limit 12; then
				log_info "Backing up existing updater configuration before reset..."
				local bcn="$configname".$(date +"%Y%m%d%H%M%S")
				validate_command "Backing up config" mv "$configname" "$bcn"
				log_info "Configuration backed up to '$bcn'"
			else
				log_warn "GitHub API limit is low. Please wait a while before resetting."
				sleep 30
			fi
		fi
		sys_tc="--reset"
	fi

	if [ ! -f "$configname" ]; then
		log_info "No updater configuration found, creating a new one from template."
		if ! plugin_create_config_tcupdater; then
			log_fatal "Failed to create toolchain updater configuration." "$EXIT_ERROR"
		fi
		log_info "New configuration created at '$configname'. Please review it."
		[[ "$sys_tc" == "--reset" ]] && sys_exit
		sleep 5
	fi

	if [ "$sys_tc" == "-cfg" ] || [ "$sys_tc" == "--config" ]; then
		plugin_set_config_value_tcupdater "$option1" "$option2"
		[[ "$flag" == "1" ]] && return || sys_exit
	fi

	if ! cfg_load_file "tup_plugin" "$configname"; then
		log_fatal "Failed to load TUP plugin config." "$EXIT_INVALID_CONFIG"
	fi

	plugin_check_config_version_tcupdater

	local ctng_build_as_root
	ctng_build_as_root=$(cfg_get_value "tup_plugin" "CTNG_BUILD_AS_ROOT" "0")
	local ct_start_build=0
	if [[ "$EUID" -ne 0 || "$ctng_build_as_root" == "1" ]]; then
		ct_start_build=1
	else
		log_error "Building toolchains as root is not recommended for security reasons."
		log_info "To override this, run: ./s3 tcupdate --config \"CTNG_BUILD_AS_ROOT\" \"1\""
	fi

	# --- Command Processing ---
	case "$sys_tc" in
	-c | --create)
		ui_show_menu_tcupdater_create "$option1" "3" "$flag"
		[[ "$flag" == "1" ]] && return || sys_exit
		;;
	-dl | --download)
		if [ -n "$option1" ]; then
			ui_show_menu_tcupdater_create "$option1" "0" "$flag"
		else
			log_error "Toolchain name for download not specified."
			[[ "$flag" == "1" ]] && sleep 2 && return || log_fatal "Missing argument." "$EXIT_ERROR"
		fi
		[[ "$flag" == "1" ]] && return || sys_exit
		;;
	-s | --setup)
		plugin_setup_build_tools "" "$ct_start_build"
		sys_exit
		;;
	-b | --backup)
		if toolchain_validate_installation "$option1"; then
			toolchain_backup_archive "$option1" "$option1" >/dev/null
			[[ "$flag" == "1" ]] && return || sys_exit
		fi
		;;
	-d | --duplicate)
		if toolchain_validate_installation "$option1"; then
			if ! toolchain_validate_installation "$option2"; then
				sys_repair_toolchain "$(toolchain_backup_archive "$option1" "$option2")"
			else
				log_error "Destination toolchain '$option2' already exists."
			fi
			sys_exit
		else
			log_fatal "Source toolchain '$option1' not found." "$EXIT_MISSING"
		fi
		;;
	-ctng | --crosstool-ng | -fng | --freetz-ng | -andk | --android-ndk)
		local template_type
		template_type=$(tc_template_get_type "$cttpldir/$option1")
		ui_show_template_editor_tcupdater "${template_type%%;*}" "$option1"
		sys_exit
		;;
	"")
		_ui_show_menu_tcupdater_main "$flag"
		;;
	*)
		if [ -n "$tc" ]; then
			ui_show_menu_tcupdater_libraries "$tc" "$option1" "$flag"
			[[ "$flag" -gt 0 ]] && return || sys_exit
		fi
		;;
	esac
	err_pop_context
}

# Shows the main interactive menu for the toolchain updater.
_ui_show_menu_tcupdater_main() {
	local flag="$1"
	local tc=""
	while true; do
		toolchain_fill_arrays
		local count=0
		menu_init "Toolchain Updater" "Toolchain Updater"
		if [ "$tcempty" == "0" ]; then
			for i in "${INST_TCLIST[@]}"; do
				[[ "$i" == "native" ]] && continue
				cfg_load_file "toolchain" "$tccfgdir/$i"
				local description
				description=$(cfg_get_value "toolchain" "_description" "No description")
				menu_add_option "$i" "$description"
				((count++))
			done
		fi

		menu_add_separator
		menu_add_option "CREATE" "Create a new toolchain..."
		menu_add_option "SETUP" "Setup/Update build environments (crosstool-NG, etc.)"
		menu_add_option "BACK" "Back to main menu"

		if ! menu_show_list; then
			[[ "$flag" == "1" ]] && return || sys_exit
		fi

		local selection
		selection="$(menu_get_first_selection)"
		tc="$selection"

		case "$selection" in
		CREATE)
			ui_show_menu_tcupdater_create "" "" "1"
			;;
		SETUP)
			local ctng_build_as_root
			ctng_build_as_root=$(cfg_get_value "tup_plugin" "CTNG_BUILD_AS_ROOT" "0")
			local ct_start_build=0
			if [[ "$EUID" -ne 0 || "$ctng_build_as_root" == "1" ]]; then
				ct_start_build=1
			fi
			plugin_setup_build_tools "" "$ct_start_build"
			;;
		BACK | '')
			[[ "$flag" == "1" ]] && return || sys_exit
			;;
		*)
			_ui_show_menu_tcupdater_actions "$selection"
			;;
		esac
	done
}

# Shows the action menu for a selected toolchain.
_ui_show_menu_tcupdater_actions() {
	local tc="$1"
	while true; do
		menu_init "Actions for '$tc'" "Toolchain Actions for '$tc'"
		menu_add_option "UPDATE_LIBS" "Update/Integrate Libraries"
		menu_add_option "BACKUP" "Backup Toolchain"
		menu_add_option "REPAIR" "Repair Toolchain"
		menu_add_option "BACK" "Back"

		if ! menu_show_list; then return 0; fi

		local action
		action="$(menu_get_first_selection)"

		case "$action" in
		UPDATE_LIBS)
			ui_show_menu_tcupdater_libraries "$tc" "" "1"
			;;
		BACKUP)
			toolchain_backup_archive "$tc" "$tc" >/dev/null
			ui_show_msgbox "Success" "Toolchain '$tc' backup completed."
			;;
		REPAIR)
			sys_repair_toolchain "$tc"
			;;
		BACK | '')
			return 0
			;;
		esac
	done
}

# UI to select and integrate libraries into a toolchain.
ui_show_menu_tcupdater_libraries() {
	local tc="$1"
	local libkeys_arg="$2"
	local libs_list_beta
	libs_list_beta=$(cfg_get_value "tup_plugin" "LIBS_LIST_BETA" "0")

	if ! toolchain_validate_installation "$tc"; then
		sleep 2
		return
	fi

	local props
	props=$(tc_get_properties "$tc")
	local prefixdir
	prefixdir=$(echo "$props" | awk -F';' '{print $5}' | xargs)

	while true; do
		local pkgconfigdir
		pkgconfigdir=$(_toolchain_get_pkgconfig_path "$prefixdir")
		local tc_libs
		tc_libs=$(tc_get_installed_libs "$pkgconfigdir" "$props")

		menu_init "Update Libraries for '$tc'" "Update Libraries for '$tc'"
		local -a libs_keys
		mapfile -t libs_keys < <(cfg_get_value "tup_plugin" "LIBS")

		for libkey in "${libs_keys[@]}"; do
			[[ "$(cfg_get_value "tup_plugin" "$libkey")" == "0" ]] && continue
			local libbeta_key="${libkey}_beta"
			[[ "$libs_list_beta" == "0" && "$(cfg_get_value "tup_plugin" "$libbeta_key")" == "1" ]] && continue

			local libname libversion libdesc
			libname=$(_tc_template_replace_tokens "$(cfg_get_value "tup_plugin" "${libkey}_name")" "$props")
			libversion=$(_tc_template_replace_tokens "$(cfg_get_value "tup_plugin" "${libkey}_version")" "$props")
			libdesc=$(_tc_template_replace_tokens "$(cfg_get_value "tup_plugin" "${libkey}_desc")" "$props")
			[[ -z "$libdesc" ]] && libdesc="$libname $libversion"

			local state="off"
			while IFS='|' read -r _ _ key; do
				if [[ "$key" == "$libkey" ]]; then
					state="on"
					break
				fi
			done < <(echo "$tc_libs" | tr ";" "\n")
			[[ " ${libkeys_arg} " =~ " ${libkey} " ]] && state="on"

			menu_add_option "$libkey" "$libdesc" "$state"
		done

		if ! menu_show_checkbox; then return 0; fi

		local selected_opts
		selected_opts=($(menu_get_selected_options))
		local err=0
		local i=0
		local icount=${#selected_opts[@]}
		for opt in "${selected_opts[@]}"; do
			((i++))
			local lib_url
			lib_url=$(cfg_get_value "tup_plugin" "${opt}_url")

			local -a buildtasks
			mapfile -t buildtasks < <(
				for task in $(cfg_get_value "tup_plugin" "${opt}_tasks"); do
					_tc_template_replace_tokens "$task" "$props"
				done
			)

			local tmpdir="/tmp/lib_source/$(date +%F.%H%M%S)"
			validate_command "Creating temp dir" mkdir -p "$tmpdir"
			local lib_file="$tmpdir/$(basename "$lib_url")"

			local libname libversion
			libname=$(_tc_template_replace_tokens "$(cfg_get_value "tup_plugin" "${opt}_name")" "$props")
			libversion=$(_tc_template_replace_tokens "$(cfg_get_value "tup_plugin" "${opt}_version")" "$props")
			local logfile="$ldir/$(date +%F.%H%M%S)_tup_${tc}_${libname}_${libversion}.log"

			if ! net_download_file "$lib_url" "$lib_file" "ui_show_progressbox 'Downloading ${libname} ${libversion}...'"; then
				log_error "Failed to download ${libname} ${libversion}"
				continue
			fi
			if ! file_extract_archive "$lib_file" "$tmpdir" "ui_show_progressbox 'Extracting ${libname} ${libversion}...'"; then
				log_error "Failed to extract ${libname} ${libversion}"
				continue
			fi
			local lib_srcdir
			lib_srcdir="$tmpdir/$(basename "$lib_file" | sed 's|\.tar\.gz\|\.tar\.bz2\|\.tar\.xz\|\.tgz\|\.tbz2\|\.txz\|\.tar\|\.zip\|\.7z\|\.rar\|\.exe||')"

			build_run_library_task "($i/$icount) $tc: Lib ${libname} ${libversion}" "$lib_srcdir" "$logfile" "${buildtasks[@]}"
			local task_status=$?
			err=$((err + task_status))
			[[ $task_status -eq 0 ]] && rm -rf "$tmpdir"
		done
	done
}

# The main UI for creating a new toolchain from templates.
ui_show_menu_tcupdater_create() {
	local tpl="$1"
	local ret="$2"
	local flag="$3"

	while true; do
		menu_init "Create New Toolchain from Template" "Create New Toolchain"
		local -a tpl_list=()
		if [[ -d "$cttpldir" && "$(ls -A "$cttpldir")" ]]; then
			cd "$cttpldir" || return 1
			mapfile -t tpl_list < <(ls -1)
			for t in "${tpl_list[@]}"; do
				local props desc
				props=$(tc_template_get_properties "$t")
				desc=$(echo "$props" | awk -F'^' '{print $1}' | xargs)
				menu_add_option "$t" "$desc"
			done
		else
			menu_add_option "NONE" "No templates found. Run './s3 plugin_run_toolchain_updater -s' to setup." "disabled"
		fi
		menu_add_separator
		menu_add_option "BACK" "Back"

		if ! menu_show_list; then return 0; fi

		local selection
		selection="$(menu_get_first_selection)"
		[[ "$selection" == "BACK" || "$selection" == "NONE" ]] && return 0

		_ui_show_menu_tcupdater_template_actions "$selection"
	done
}

# Shows the action menu for a selected toolchain template.
_ui_show_menu_tcupdater_template_actions() {
	local tpl="$1"
	local ctng_build_as_root
	ctng_build_as_root=$(cfg_get_value "tup_plugin" "CTNG_BUILD_AS_ROOT" "0")
	local ct_start_build=0
	if [[ "$EUID" -ne 0 || "$ctng_build_as_root" == "1" ]]; then
		ct_start_build=1
	fi

	while true; do
		menu_init "Actions for template '$tpl'" "Template Actions for '$tpl'"
		menu_add_option "BUILD" "Build this toolchain"
		menu_add_option "DOWNLOAD" "Download pre-built version"
		menu_add_option "EDIT" "Edit template"
		menu_add_option "BACK" "Back"

		if ! menu_show_list; then return 0; fi

		local action
		action="$(menu_get_first_selection)"

		case "$action" in
		BUILD)
			plugin_setup_build_tools "" "$ct_start_build"
			if [[ "$ct_start_build" -eq 1 ]]; then
				build_run_crosstool "$tpl"
			else
				ui_show_msgbox "Error" "Cannot build as root unless configured. See logs."
			fi
			return 0
			;;
		DOWNLOAD)
			ui_install_toolchain_interactive "$tpl"
			;;
		EDIT)
			local template_type
			template_type=$(tc_template_get_type "$cttpldir/$tpl")
			ui_show_template_editor_tcupdater "${template_type%%;*}" "$tpl"
			;;
		BACK | '')
			return 0
			;;
		esac
	done
}

# UI for editing a crosstool template.
ui_show_template_editor_tcupdater() {
	local type="$1"
	local tpl="$2"
	err_push_context "Template Editor: $tpl"

	plugin_setup_build_tools "$type"

	local props
	props=$(tc_template_get_properties "$cttpldir/$tpl")
	local desc
	desc=$(echo "$props" | awk -F'(' '{print $1}' | xargs)
	local version
	version=$(echo "$props" | awk -F'^' '{print $2}' | xargs)
	[ -z "$version" ] && version=0
	[ -z "$disable_template_versioning" ] && ((version += 1))
	local cflags ldflags
	cflags=$(echo "$props" | awk -F'^' '{print $3}' | xargs)
	ldflags=$(echo "$props" | awk -F'^' '{print $4}' | xargs)

	local editordir_var="${type,,}srcdir"
	local editordir="${!editordir_var}"

	if [ -f "$cttpldir/$tpl" ]; then
		validate_command "Copying template for editing" cp -f "$cttpldir/$tpl" "$editordir/.config"
	else
		validate_command "Creating new template file" touch "$editordir/.config"
	fi

	cd "$editordir" || log_fatal "Cannot enter editor directory '$editordir'" "$EXIT_MISSING"
	local md5
	md5=$(md5sum .config | awk '{printf $1}')

	local tasks_var="${type}_CONFIG_tasks[@]"
	local -a config_tasks=("${!tasks_var}")
	local -a exec_tasks=()
	for task in "${config_tasks[@]}"; do
		exec_tasks+=("$(_tc_template_replace_tokens "$task")")
	done

	# This must be run directly in the foreground to show the TUI
	"${exec_tasks[@]}"

	if [[ "$md5" != "$(md5sum .config | awk '{printf $1}')" ]]; then
		log_info "Template was modified, saving changes."
		validate_command "Copying back edited template" cp -f ".config" "$cttpldir/$tpl"
		sed -i -e '/^$\|^#$/d' \
			-e '/^#toolchain template.*:.*/d' \
			"$cttpldir/$tpl"
		# Inject headers
		{
			echo "#toolchain template: $desc"
			echo "#toolchain template version: $version"
			[ -n "$cflags" ] && echo "#toolchain template cflags: $cflags"
			[ -n "$ldflags" ] && echo "#toolchain template ldflags: $ldflags"
			echo "#toolchain template updated: $(date -r "$cttpldir/$tpl" "+%F %T")"
			cat "$cttpldir/$tpl"
		} >"$cttpldir/$tpl.tmp" && validate_command "Updating template file" mv "$cttpldir/$tpl.tmp" "$cttpldir/$tpl"
	else
		log_info "Template was not modified, no changes saved."
	fi
	err_pop_context
}

# Creates a compressed archive of a toolchain for distribution or backup.
toolchain_backup_archive() {
	local src="$1"
	local dest="$2"
	local xzfile="$dldir/$(sys_decode_base64 "$URL_TOOLCHAIN_BASE_B64")$dest.tar.xz"
	local log_file="$ldir/backup_${dest}.log"

	(
		run_with_logging "$log_file" file_create_archive "$xzfile" "$tcdir/$src"
	) | ui_show_progressbox "Backing up '$src'"

	if [[ ${PIPESTATUS[0]} -eq 0 ]]; then
		toolchain_create_config_file "$tcdir/$src" "$dest"
		echo "$dest"
		return 0
	fi
	return 1
}

# Checks if required packages for the plugin are installed.
plugin_check_dependencies_tcupdater() {
	err_push_context "TUPdater dependency check"
	log_info "Verifying dependencies for the toolchain updater plugin..."

	if ! sys_run_check; then
		log_error "Core system dependencies are missing. Please run './s3 syscheck auto now' to install them."
		err_pop_context
		return 1
	fi

	local missing_pkgs=()
	local plugin_pkgs=(gperf bison flex makeinfo help2man python3-config libtoolize rsync pkg-config python3 gettext)
	for pkg in "${plugin_pkgs[@]}"; do
		if ! command -v "$pkg" &>/dev/null; then
			missing_pkgs+=("$pkg")
		fi
	done

	if [[ ${#missing_pkgs[@]} -gt 0 ]]; then
		log_error "The toolchain updater plugin requires additional packages that are not installed:"
		log_error "  ${missing_pkgs[*]}"
		log_error "Please install them using your system's package manager and try again."
		err_pop_context
		return 1
	fi

	log_info "All toolchain updater dependencies are met."
	err_pop_context
	return 0
}

# Ensures build tools like crosstool-NG are set up.
plugin_setup_build_tools() {
	local type="$1"
	local can_build="$2"
	err_push_context "Setup build tools"

	if [[ "$type" == "CTNG" || -z "$type" ]] && [[ ! -f "$ctngsrcdir/ct-ng" ]]; then
		log_info "crosstool-NG not found, initiating setup..."
		sleep 2
		_plugin_setup_ctng_internal "$can_build" || log_fatal "crosstool-NG setup failed." "$EXIT_ERROR"
	fi
	if [[ "$type" == "FNG" || -z "$type" ]] && [[ ! -d "$fngsrcdir/dl" ]]; then
		log_info "Freetz-NG not found, initiating setup..."
		sleep 2
		_plugin_setup_fng_internal "$can_build" || log_fatal "Freetz-NG setup failed." "$EXIT_ERROR"
	fi
	if [[ "$type" == "ANDK" || -z "$type" ]] && [[ ! -f "$andksrcdir/toolchains/llvm/prebuilt/linux-x86_64/AndroidVersion.txt" ]]; then
		log_info "Android NDK not found, initiating setup..."
		sleep 2
		_plugin_setup_andk_internal "$can_build" || log_fatal "Android NDK setup failed." "$EXIT_ERROR"
	fi
	err_pop_context
}

# Checks the toolchain updater config version against its template.
plugin_check_config_version_tcupdater() {
	local tpl_version
	tpl_version=$(grep -i '^S3TUP_CONFIG_VERSION=' "$configtemplate" | awk -F'"' '{print $2}' | xargs)
	local current_version
	current_version=$(cfg_get_value "tup_plugin" "S3TUP_CONFIG_VERSION" "0")

	if [[ "$tpl_version" > "$current_version" ]]; then
		log_error "Your toolchain updater configuration is outdated (v$current_version vs template v$tpl_version)."
		log_error "Please reset your configuration to get the latest updates."
		log_info "Run: ./s3 tcupdate --reset"
		sleep 10
		return 1
	fi
	return 0
}

# Sets a value in the toolchain updater config file.
plugin_set_config_value_tcupdater() {
	local key="$1"
	local value="$2"
	err_push_context "Set TUP config value"

	if [[ -z "$(cfg_get_value "tup_plugin" "$key")" ]]; then
		log_error "Configuration key '$key' does not exist."
		err_pop_context
		return 1
	fi

	log_info "Setting config value: $key = $value"
	cfg_set_value "tup_plugin" "$key" "$value"
	if ! cfg_save_file "tup_plugin" "$configname"; then
		log_error "Failed to save configuration."
	fi
	sleep 2
	err_pop_context
}

# Private helper to resolve dynamic values from the trusted config template.
# This uses 'eval', which is normally forbidden, but is deemed acceptable here as it only
# operates on trusted, project-internal template values during initial setup.
_plugin_resolve_dynamic_value() {
	local value_string="$1"
	if [[ -z "$value_string" ]]; then
		echo ""
		return
	fi
	# This is intentionally using eval to resolve command substitutions like "$(some_func)"
	# that are stored as strings in the config template.
	eval echo "$value_string"
}

# Creates the initial toolchain updater config from the template.
plugin_create_config_tcupdater() {
	err_push_context "Create TUP config"
	if [[ ! -f "$configtemplate" ]]; then
		log_fatal "Configuration template not found: $configtemplate" "$EXIT_MISSING"
	fi
	if ! command -v jq >/dev/null; then
		log_fatal "Required command 'jq' is not installed. Please install it." "$EXIT_MISSING"
	fi

	validate_command "Copying config template" cp -f "$configtemplate" "$configname"
	cfg_load_file "tup_plugin" "$configname"

	log_info "Resolving dynamic values from template for the new configuration..."
	local libs
	libs=$(cfg_get_value "tup_plugin" "LIBS")
	for lib in $libs; do
		for prop_suffix in tag version check url; do
			local prop_key="${lib}_${prop_suffix}"
			local dynamic_val
			dynamic_val=$(cfg_get_value "tup_plugin" "$prop_key")
			local resolved_val
			resolved_val=$(_plugin_resolve_dynamic_value "$dynamic_val")
			cfg_set_value "tup_plugin" "$prop_key" "$resolved_val"
		done
	done

	if ! cfg_save_file "tup_plugin" "$configname"; then
		err_pop_context
		return 1
	fi
	err_pop_context
	return 0
}

# Creates a toolchain.cfg file based on a built toolchain.
toolchain_create_config_file() {
	local tc_path="$1"
	local tc_name="$2"
	err_push_context "Create toolchain config for $tc_name"

	local template_file="$tc_path/.config"
	if [[ ! -f "$template_file" ]]; then
		log_error "Cannot create config for '$tc_name': .config template not found in build directory."
		err_pop_context
		return 1
	fi

	local props tpl_type_full tpl_type tpl_type_name desc cflags ldflags
	props=$(tc_template_get_properties "$template_file")
	tpl_type_full=$(tc_template_get_type "$template_file")
	tpl_type="${tpl_type_full%%;*}"
	tpl_type_name="${tpl_type_full##*;}"
	desc=$(echo "$props" | awk -F'^' '{print $1}' | xargs)
	cflags=$(echo "$props" | awk -F'^' '{print $3}' | xargs)
	ldflags=$(echo "$props" | awk -F'^' '{print $4}' | xargs)

	local target compiler_prefix sysroot libsearchdir compilername
	compiler_prefix=$(grep -oP '(?<=CT_TARGET_ALIAS=").*(?=")' "$template_file" || echo "${tc_name}")
	target="${compiler_prefix}"
	compiler_prefix+='-'
	cd "$tc_path/bin" || return 1
	compilername=$(realpath -s "${compiler_prefix}gcc")
	sysroot=$("$compilername" -print-sysroot 2>/dev/null)
	sysroot=$(realpath -sm "$sysroot" 2>/dev/null)
	sysroot="${sysroot#$(realpath "$tc_path")/}"
	libsearchdir="/usr/lib"

	local archive_name archive_path
	archive_name="$(sys_decode_base64 "$URL_TOOLCHAIN_BASE_B64")$tc_name.tar.xz"
	archive_path="$dldir/$archive_name"

	local ns="toolchain"
	cfg_set_value "$ns" "_toolchainname" "$tc_name"
	cfg_set_value "$ns" "default_use" "USE_LIBCRYPTO"
	cfg_set_value "$ns" "_description" "$desc"
	cfg_set_value "$ns" "_compiler" "$compiler_prefix"
	cfg_set_value "$ns" "_sysroot" "$sysroot"
	cfg_set_value "$ns" "_libsearchdir" "$libsearchdir"
	cfg_set_value "$ns" "_self_build" "yes"
	cfg_set_value "$ns" "extra_cc" "$cflags"
	cfg_set_value "$ns" "extra_ld" "$ldflags"
	cfg_set_value "$ns" "_extract_strip" "0"
	cfg_set_value "$ns" "_toolchainfilename" "$(echo "$(sys_decode_base64 "$tc_url")${pversion}/$archive_name" | base64 -w0)"
	cfg_set_value "$ns" "_md5sum" "$(cd "$dldir" && md5sum "$archive_name")"
	cfg_set_value "$ns" "_tc_info" "$tpl_type_name Toolchain: $desc"

	if [[ "$tpl_type" == "ANDK" ]]; then
		cfg_set_value "$ns" "_oscamconfdir_custom" "/data/plugin/oscam"
		cfg_set_value "$ns" "_androidndkdir" "1"
		cfg_set_value "$ns" "stapi_allowed" "1"
	fi

	cfg_save_file "$ns" "$tccfgdir/$tc_name"
	err_pop_context
}
