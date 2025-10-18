#!/bin/bash

# =============================================================================
# SIMPLEBUILD3 - Unified Build Pipeline
# =============================================================================
# a single, maintainable pipeline.
# =============================================================================

# These are treated as globals so the wrappers can access them for post-build steps.
oscam_name=""
tartmp=""

# --- COMPATIBILITY BRIDGE ---
# Exports key toolchain variables from the UCM cache into the global scope.
# This is required for legacy helper functions (e.g., _generate_oscam_name,
# set_buildtype) that have not yet been refactored to use `cfg_get_value`.
_build_export_toolchain_vars() {
	log_debug "Exporting toolchain variables for backward compatibility."
	export _toolchainname="$(cfg_get_value "toolchain" "_toolchainname")"
	export _compiler="$(cfg_get_value "toolchain" "_compiler")"
	export _sysroot="$(cfg_get_value "toolchain" "_sysroot")"
	export _stagingdir="$(cfg_get_value "toolchain" "_stagingdir")"
	export _androidndkdir="$(cfg_get_value "toolchain" "_androidndkdir")"
	export default_use="$(cfg_get_value "toolchain" "default_use")"
	export _oscamconfdir_default="$(cfg_get_value "toolchain" "_oscamconfdir_default")"
	export _oscamconfdir_custom="$(cfg_get_value "toolchain" "_oscamconfdir_custom")"
	export extra_use="$(cfg_get_value "toolchain" "extra_use")"
	export extra_cc="$(cfg_get_value "toolchain" "extra_cc")"
	export extra_ld="$(cfg_get_value "toolchain" "extra_ld")"
	export extra_c="$(cfg_get_value "toolchain" "extra_c")"
	export _block="$(cfg_get_value "toolchain" "_block")"
	export stapi_lib_custom="$(cfg_get_value "toolchain" "stapi_lib_custom")"
}

# Prepares the entire build environment but does not run `make`.
_build_prepare_environment() {
	local toolchain_name="$1"
	err_push_context "Build Environment Prep for $toolchain_name"

	# Load the toolchain config. Use "true" to export for the bridge.
	cfg_load_file "toolchain" "$tccfgdir/$toolchain_name" "true"

	_build_export_toolchain_vars

	# Set up global paths and env vars
	_make=$(command -v make)
	CROSS="$tcdir/$toolchain_name/bin/$_compiler"
	SYSROOT="$(realpath -sm "$tcdir/$toolchain_name/$_sysroot")"
	[ "$_stagingdir" == "1" ] && export STAGING_DIR="$tcdir/$toolchain_name"
	[ "$_androidndkdir" == "1" ] && export ANDROID_NDK="$tcdir/$toolchain_name"
	[ -f "$configdir/compiler_option" ] && co=$(cat "$configdir/compiler_option") || co="-O2"

	build_ensure_openssl "$SYSROOT" "$tcdir/$toolchain_name" "${CROSS}gcc"

	# Clean repository and apply command-line module selections
	cd "${repodir}"
	make distclean >/dev/null 2>&1
	_reset_config

	for am in "${all_cc[@]}"; do
		if [[ "${am: -3}" == "_on" ]]; then
			"${repodir}/config.sh" -E "${am%_on}"
		elif [[ "${am: -4}" == "_off" ]]; then
			"${repodir}/config.sh" -D "${am%_off}"
		fi
	done

	# Apply USE_vars from command line and toolchain defaults
	for defa in $default_use; do USE_vars[$defa]="$defa=1"; done
	for var_to_disable in "${!USE_vars_disable[@]}"; do USE_vars[$var_to_disable]=""; done
	if [[ "${USE_vars[USE_DIAG]}" == "USE_DIAG=1" ]]; then codecheck=$(command -v scan-build); fi
	if [[ "${USE_vars['USE_PATCH']}" == "USE_PATCH=1" ]]; then patch_apply_console; fi

	# Handle dependencies like smargo and streamrelay
	build_check_smargo_deps
	build_check_streamrelay_deps

	# Prepare variables for make arguments
	if [ -f "$ispatched" ]; then build_patch_webif_info; fi
	EXTRA_USE="" # Initialize for a clean state
	if [ "${USE_vars[USE_EXTRA]}" != "USE_EXTRA=1" ]; then
		unset extra_use extra_cc extra_ld extra_c
	else
		extra="-extra"
		EXTRA_USE="$extra_use" # This was the missing assignment
	fi
	if [ -f "$configdir/max_cpus" ]; then
		cpus="$(cat "$configdir/max_cpus")"
	else
		cpus="$(sys_get_cpu_count)"
	fi
	_verbose="" # Initialize for a clean state
	[ "$(cfg_get_value "s3" "USE_VERBOSE")" == "1" ] && _verbose="V=1"

	check_signing
	set_buildtype

	err_pop_context
}

# Generates the final list of arguments to pass to the `make` command.
_build_generate_make_arguments() {
	if [[ ${#USE_vars[USE_OSCAMNAME]} -gt 0 ]]; then
		oscam_name=$(echo "${USE_vars[USE_OSCAMNAME]}" | cut -d "=" -f2)
	else
		_generate_oscam_name "$_toolchainname" "$extra$buildtype"
	fi

	if [[ -z "$oscam_name" ]]; then
		log_fatal "Failed to generate a valid binary name. Repository state may be broken." "$EXIT_ERROR"
	fi

	local COMP_LEVEL="" # Initialize for a clean state
	if [[ $oscam_name =~ -upx ]]; then
		[ -f "$configdir/upx_option" ] && source "$configdir/upx_option"
		COMP_LEVEL="COMP_LEVEL=$upx_c"
	fi

	# Determine final CONF_DIR
	CONFDIR="$_oscamconfdir_default"
	if [[ -n "$_oscamconfdir_custom" && "$_oscamconfdir_custom" != "not_set" ]]; then
		CONFDIR="$_oscamconfdir_custom"
	fi
	if [[ "$CUSTOM_CONFDIR" != "not_set" ]]; then
		CONFDIR="$CUSTOM_CONFDIR"
	fi

	# Build argument array
	local -a args

	if [[ "${USE_vars[USE_PCSC]}" == "USE_PCSC=1" ]]; then
		extra_c+=" -DCARDREADER_PCSC=1"
	fi
	if [[ "${USE_vars[USE_STAPI5]}" == "USE_STAPI5=1" ]]; then
		extra_c+=" -DCARDREADER_STAPI5=1"
	fi

	args+=(-j"$cpus")
	args+=("CONF_DIR=$CONFDIR" "OSCAM_BIN=$bdir/$oscam_name")
	args+=("CC_OPTS=$co $cc_opts $extra_cc" "CC_WARN=$cc_warn")
	args+=("EXTRA_LDFLAGS=$extra_ld" "EXTRA_CFLAGS=$extra_c")
	args+=("CROSS=$CROSS")
	# Conditionally add optional arguments to avoid passing empty strings to make
	[[ -n "$_verbose" ]] && args+=("$_verbose")
	[[ -n "$EXTRA_USE" ]] && args+=("$EXTRA_USE")
	[[ -n "$COMP_LEVEL" ]] && args+=("$COMP_LEVEL")
	[[ -n "$stapivar" ]] && args+=("$stapivar")

	local use_string_args
	use_string_args=$(echo "${USE_vars[@]}" | xargs)
	args+=($use_string_args)
	args+=($LIBCRYPTO_LIB $SSL_LIB $LIBUSB_LIB $PCSC_LIB $LIBDVBCSA_LIB)

	printf '%s\n' "${args[@]}"
}

# Executes the make command and handles logging.
_build_execute_make() {
	local log_file="$1"
	shift
	local -a make_args=("$@")

	timer_start
	# This unified pipeline is used by both GUI and CMD, so it needs to be parsable by both.
	# The sed expression is a common denominator for colored console output.
	$_make "${make_args[@]}" |
		sed -u "s/^|/ |/g;/^[[:space:]]*[[:digit:]]* ->/ s/./ |  UPX   > &/;s/^RM/ |  REMOVE>/g;s/^CONF/ |  CONFIG>/g;s/^LINK/ |  LINK  >/g;s/^STRIP/ |  STRIP >/g;s/^CC\|^HOSTCC\|^BUILD/ |  BUILD >/g;s/^GEN/ |  GEN   >/g;s/^UPX/ |  UPX   >/g;s/^SIGN/ |  SIGN  >/g;
		s/WEBIF_//g;s/WITH_//g;s/MODULE_//g;s/CS_//g;s/HAVE_//g;s/_CHARSETS//g;s/CW_CYCLE_CHECK/CWCC/g;s/SUPPORT//g;s/= /: /g;"
}

# Handles post-build tasks like artifact saving and cleanup.
_build_handle_artifacts() {
	local toolchain_name="$1"
	local log_file="$2"

	# Save list_smargo
	cd "${repodir}/Distribution"
	local lsmn
	lsmn="$(ls list_smargo* 2>/dev/null)"
	if [[ "$(cfg_get_value "s3" "SAVE_LISTSMARGO" "1")" == "1" && -f "$lsmn" ]]; then
		local smargo_name_base="oscam-${REPO}$(REVISION)$($(USEGIT) && printf "@$(COMMIT)" || printf "")"
		local smargo_name
		if [[ "$toolchain_name" == "native" ]]; then
			smargo_name="${smargo_name_base}-$(hostname)-list_smargo"
		else
			smargo_name="${smargo_name_base}-${toolchain_name}-list_smargo"
		fi
		mv -f "$lsmn" "$bdir/$smargo_name"
		tartmp="$smargo_name" # Set global for wrappers
		echo "SAVE\t$lsmn as $smargo_name" >>"$log_file"
	fi

	# Show build time
	timer_stop
	timer_calc
	printf "\n |  TIME  >\t[ $txt_buildtime $((Tcalc / 60)) min(s) $((Tcalc % 60)) secs ]\n"

	# Remove debug binary
	if [[ "$(cfg_get_value "s3" "delete_oscamdebugbinary" "1")" == "1" && -f "$bdir/$oscam_name.debug" ]]; then
		rm "$bdir/$oscam_name.debug"
		printf "\n $txt_delete $oscam_name.debug\n"
	fi
}

# The main, unified build process entry point.
_build_run_pipeline() {
	local toolchain_name="$1"
	local log_file="$2"

	# 1. Prepare the entire environment
	_build_prepare_environment "$toolchain_name"

	# 2. Generate the final `make` command arguments
	local -a make_args
	mapfile -t make_args < <(_build_generate_make_arguments)

	# 3. Execute the build and capture its exit code
	_build_execute_make "$log_file" "${make_args[@]}"
	local make_exit_code=${PIPESTATUS[0]}

	# 4. Handle post-build artifacts
	_build_handle_artifacts "$toolchain_name" "$log_file"

	# 5. Return the exit code of the make process
	return $make_exit_code
}

# Export the function so it's available in subshells (needed for GUI build)
export -f _build_run_pipeline
