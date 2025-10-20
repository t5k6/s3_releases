#!/bin/bash

# =============================================================================
# SIMPLEBUILD3 - Unified Build Pipeline
# =============================================================================
# This file contains the core logic for the OScam build process, providing
# a single, maintainable pipeline used by both command-line and GUI builds.
# =============================================================================

# Source dependencies
source "$fdir/_build_libdvbcsa.sh"

# These are treated as globals so the wrappers can access them for post-build steps.
oscam_name=""
tartmp=""

# Applies configuration from all sources (toolchain defaults, CLI args)
# to the current repository state. This is a private helper for the pipeline.
build_apply_config() {
	local toolchain_name="$1"
	err_push_context "Build Apply Config for $toolchain_name"

	# For command-line builds, we reset. For GUI builds, the state is already set.
	# We differentiate based on whether CLI-specific variables are populated.
	if [[ ${#module_configs[@]} -gt 0 ]]; then
		log_info "CLI build detected. Resetting repository configuration."
		cfg_reset_build_config
	else
		log_info "GUI build detected. Preserving UI-configured repository state."
	fi

	# Apply module selections passed from the command line (e.g., all_on, reader_off)
	for am in "${module_configs[@]}"; do
		if [[ "${am: -3}" == "_on" ]]; then
			validate_command "Enabling module ${am%_on}" "${repodir}/config.sh" -E "${am%_on}"
		elif [[ "${am: -4}" == "_off" ]]; then
			validate_command "Disabling module ${am%_off}" "${repodir}/config.sh" -D "${am%_off}"
		fi
	done

	# Apply USE_vars from command line and toolchain defaults
	local default_use
	default_use=$(cfg_get_value "toolchain" "default_use")
	log_debug "Applying toolchain default USE_vars: $default_use"
	for defa in $default_use; do USE_vars[$defa]="1"; done

	# Disable any explicitly disabled vars
	for var_to_disable in "${!USE_vars_disable[@]}"; do USE_vars[$var_to_disable]=""; done

	# Special handling for command-line USE_vars
	if [[ "${USE_vars[USE_DIAG]}" == "1" ]]; then
		if ! command -v scan-build >/dev/null; then
			log_warn "'scan-build' not found, disabling USE_DIAG."
			USE_vars[USE_DIAG]=""
		fi
	fi
	if [[ "${USE_vars['USE_PATCH']}" == "1" ]]; then
		validate_command "Applying patches from console request" patch_apply_console
	fi

	# Run dependency checks that might enable other USE_vars
	log_debug "Running post-config dependency checks."
	build_check_smargo_deps
	build_check_streamrelay_deps

	log_info "Build configuration applied successfully."
	err_pop_context
}

# Prepares the entire build environment but does not run `make`.
_build_prepare_environment() {
	local toolchain_name="$1"
	local log_file="$2"
	err_push_context "Build Environment Prep for $toolchain_name"

	# Load the toolchain config.
	cfg_load_file "toolchain" "$tccfgdir/$toolchain_name"

	# Set up global paths and env vars
	local _make
	_make=$(command -v make)
	if [[ -z "$_make" ]]; then
		log_fatal "Required binary 'make' not found." "$EXIT_MISSING"
	fi

	local _compiler
	_compiler=$(cfg_get_value "toolchain" "_compiler")
	CROSS="$tcdir/$toolchain_name/bin/$_compiler"
	local _sysroot
	_sysroot=$(cfg_get_value "toolchain" "_sysroot")
	SYSROOT="$(realpath -sm "$tcdir/$toolchain_name/$_sysroot")"
	[ "$(cfg_get_value "toolchain" "_stagingdir")" == "1" ] && export STAGING_DIR="$tcdir/$toolchain_name"
	[ "$(cfg_get_value "toolchain" "_androidndkdir")" == "1" ] && export ANDROID_NDK="$tcdir/$toolchain_name"
	local co
	co=$(cfg_get_value "s3" "compiler_option" "-O2")

	validate_command "Ensuring OpenSSL dependency is met" build_ensure_openssl "$SYSROOT" "$tcdir/$toolchain_name" "${CROSS}gcc"

	# Clean repository and apply ALL configuration through the unified function
	if ! validate_command "Entering repository directory" cd "${repodir}"; then
		log_fatal "Could not enter repository directory: ${repodir}" "$EXIT_MISSING"
	fi
	# Silently run distclean, log output, but don't fail the build if it exits non-zero.
	if ! { make distclean >>"$log_file" 2>&1; }; then
		log_warn "Repository 'distclean' failed; proceeding anyway (dirty state may affect build)"
	fi
	build_apply_config "$toolchain_name"

	# Ensure libdvbcsa is present if required by streamrelay (check is post-config)
	if [[ "${USE_vars[USE_LIBDVBCSA]}" == "1" ]]; then
		validate_command "Ensuring libdvbcsa dependency is met" build_ensure_libdvbcsa "$SYSROOT" "$tcdir/$toolchain_name" "${CROSS}gcc"
	fi

	# Prepare variables for make arguments
	if [ -f "$ispatched" ]; then
		validate_command "Patching WebIF info" build_patch_webif_info
	fi
	local EXTRA_USE="" # Initialize for a clean state
	if [[ "${USE_vars[USE_EXTRA]}" == "1" ]]; then
		EXTRA_USE=$(cfg_get_value "toolchain" "extra_use")
	fi
	local cpus
	cpus=$(cfg_get_value "s3" "max_cpus" "$(sys_get_cpu_count)")

	local _verbose="" # Initialize for a clean state
	[ "$(cfg_get_value "s3" "USE_VERBOSE")" == "1" ] && _verbose="V=1"

	validate_command "Checking for signing configuration" build_check_signing
	validate_command "Setting build type (static/dynamic)" build_set_type "$toolchain_name" "$SYSROOT"

	err_pop_context
}

# Generates the final list of arguments to pass to the `make` command.
_build_generate_make_arguments() {
	local cpus
	cpus=$(cfg_get_value "s3" "max_cpus" "$(sys_get_cpu_count)")

	if [[ ${#USE_vars[USE_OSCAMNAME]} -gt 0 ]]; then
		oscam_name=$(echo "${USE_vars[USE_OSCAMNAME]}" | cut -d "=" -f2)
	else
		build_generate_oscam_name
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
	local _oscamconfdir_default
	_oscamconfdir_default=$(cfg_get_value "toolchain" "_oscamconfdir_default")
	CONFDIR="$_oscamconfdir_default"

	local _oscamconfdir_custom
	_oscamconfdir_custom=$(cfg_get_value "toolchain" "_oscamconfdir_custom")
	if [[ -n "$_oscamconfdir_custom" && "$_oscamconfdir_custom" != "not_set" ]]; then
		CONFDIR="$_oscamconfdir_custom"
	fi
	if [[ "$CUSTOM_CONFDIR" != "not_set" ]]; then
		CONFDIR="$CUSTOM_CONFDIR"
	fi

	# Build argument array
	local -a args
	local extra_c
	extra_c=$(cfg_get_value "toolchain" "extra_c")
	if [[ "${USE_vars[USE_PCSC]}" == "1" ]]; then
		extra_c+=" -DCARDREADER_PCSC=1"
	fi
	if [[ "${USE_vars[USE_STAPI5]}" == "1" ]]; then
		extra_c+=" -DCARDREADER_STAPI5=1"
	fi

	local extra_cc extra_ld co _verbose EXTRA_USE
	extra_cc=$(cfg_get_value "toolchain" "extra_cc")
	extra_ld=$(cfg_get_value "toolchain" "extra_ld")
	co=$(cfg_get_value "s3" "compiler_option" "-O2")
	_verbose=$([[ "$(cfg_get_value "s3" "USE_VERBOSE")" == "1" ]] && echo "V=1")
	EXTRA_USE=$([[ "${USE_vars[USE_EXTRA]}" == "1" ]] && cfg_get_value "toolchain" "extra_use")

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

	for key in "${!USE_vars[@]}"; do
		if [[ "${USE_vars[$key]}" == "1" ]]; then
			args+=("${key}=1")
		fi
	done
	args+=($LIBCRYPTO_LIB $SSL_LIB $LIBUSB_LIB $PCSC_LIB $LIBDVBCSA_LIB)

	# Return oscam_name as first line, then arguments
	printf '%s\n' "$oscam_name"
	printf '%s\n' "${args[@]}"
}

# Executes the make command and handles logging.
_build_execute_make() {
	local _make="$1"
	shift
	local -a make_args=("$@")

	sys_timer_start
	# This unified pipeline is used by both GUI and CMD, so it needs to be parsable by both.
	# The sed expression is a common denominator for colored console output.
	# Redirect stderr (2>&1) into the pipe so it's captured by sed and the logger.
	"$_make" "${make_args[@]}" 2>&1 |
		sed -u \
			-e 's/^|/ |/g' \
			-e '/^[[:space:]]*[[:digit:]]* ->/ s/./ |  UPX   > &/' \
			-e 's/^RM/ |  REMOVE>/g' -e 's/^CONF/ |  CONFIG>/g' \
			-e 's/^LINK/ |  LINK  >/g' -e 's/^STRIP/ |  STRIP >/g' \
			-e 's/^CC\|^HOSTCC\|^BUILD/ |  BUILD >/g' \
			-e 's/^GEN/ |  GEN   >/g' -e 's/^UPX/ |  UPX   >/g' \
			-e 's/^SIGN/ |  SIGN  >/g' -e 's/WEBIF_//g' \
			-e 's/WITH_//g' -e 's/MODULE_//g' -e 's/CS_//g' \
			-e 's/HAVE_//g' -e 's/_CHARSETS//g' \
			-e 's/CW_CYCLE_CHECK/CWCC/g' -e 's/SUPPORT//g' -e 's/= /: /g'
}

# Handles post-build tasks like artifact saving and cleanup.
_build_handle_artifacts() {
	local toolchain_name="$1"
	local log_file="$2"
	local artifact_name=""

	# Save list_smargo
	cd "${repodir}/Distribution" || return 1
	local lsmn
	lsmn="$(ls list_smargo* 2>/dev/null)"
	if [[ "$(cfg_get_value "s3" "SAVE_LISTSMARGO" "1")" == "1" && -f "$lsmn" ]]; then
		local smargo_name_base="oscam-${REPO}$(repo_get_revision)$(repo_is_git && printf "@$(repo_get_commit)" || printf "")"
		local smargo_name
		if [[ "$toolchain_name" == "native" ]]; then
			smargo_name="${smargo_name_base}-$(hostname)-list_smargo"
		else
			smargo_name="${smargo_name_base}-${toolchain_name}-list_smargo"
		fi
		mv -f "$lsmn" "$bdir/$smargo_name"
		artifact_name="$smargo_name" # Set return value for caller
		echo "SAVE	$lsmn as $smargo_name" >>"$log_file"
	fi

	# Show build time
	sys_print_time_diff

	# Remove debug binary
	if [[ "$(cfg_get_value "s3" "delete_oscamdebugbinary" "1")" == "1" && -f "$bdir/$oscam_name.debug" ]]; then
		rm "$bdir/$oscam_name.debug"
		printf "\n $txt_delete $oscam_name.debug\n"
	fi

	# Return artifact name to caller
	printf '%s\n' "$artifact_name"
}

# The main, unified build process entry point.
_build_run_pipeline() {
	local toolchain_name="$1"
	local log_file="$2"
	local meta_file="${3:-/dev/null}"

	local _make
	_make=$(command -v make)
	if [[ -z "$_make" ]]; then
		log_fatal "Required binary 'make' not found." "$EXIT_MISSING"
		return "$EXIT_MISSING"
	fi

	# 1. Prepare the entire environment
	_build_prepare_environment "$toolchain_name" "$log_file"

	# 2. Generate the final `make` command arguments and capture oscam_name
	local make_args_output
	make_args_output=$(_build_generate_make_arguments)

	# 3. Parse oscam_name and args from the output
	local -a make_args
	read -r oscam_name < <(echo "$make_args_output")
	mapfile -t make_args < <(echo "$make_args_output" | tail -n +2)

	# 4. Execute the build and capture its exit code
	_build_execute_make "$_make" "${make_args[@]}"
	local make_exit_code=${PIPESTATUS[0]}

	# 5. Handle post-build artifacts and capture return value
	local artifact_name
	artifact_name=$(_build_handle_artifacts "$toolchain_name" "$log_file")

	# 6. Write metadata to the dedicated file for robust IPC
	if [[ "$meta_file" != "/dev/null" ]]; then
		printf '%s\n%s\n' "$oscam_name" "$artifact_name" >"$meta_file"
	fi

	return $make_exit_code
}
