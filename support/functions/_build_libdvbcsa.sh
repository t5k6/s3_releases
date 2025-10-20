#!/bin/bash
# =============================================================================
# SIMPLEBUILD3 - libdvbcsa Build System
# =============================================================================
# Provides a unified function to download, configure, build, and install
# libdvbcsa for a given toolchain, required for Stream Relay functionality.
# =============================================================================

# Main entry point for ensuring libdvbcsa is available.
build_ensure_libdvbcsa() {
	local sysroot="$1"
	local toolchain_path="$2"
	local cc="$3"

	err_push_context "Dependency Check: libdvbcsa"

	# Check if the library is already present in the sysroot
	if [[ -f "$sysroot/usr/include/dvbcsa/dvbcsa.h" && -f "$sysroot/usr/lib/libdvbcsa.a" ]]; then
		log_info "libdvbcsa found in toolchain sysroot. Skipping build."
		err_pop_context
		return 0
	fi

	log_warn "libdvbcsa not found in toolchain sysroot. Attempting to build it now."
	ui_show_msgbox "Missing Dependency" "libdvbcsa is missing in this toolchain and is required for Stream Relay.\n\nSimpleBuild will now attempt to download and compile it. This may take a moment." 10 70

	if ! _build_libdvbcsa "$sysroot" "$toolchain_path" "$cc"; then
		log_fatal "Failed to build and install libdvbcsa for the toolchain." "$EXIT_ERROR"
	fi

	log_info "libdvbcsa has been successfully built and installed into the toolchain sysroot."
	err_pop_context
	return 0
}

# Private helper function to perform the actual build process.
_build_libdvbcsa() {
	local final_sysroot="$1"
	local toolchain_path="$2"
	local cc="$3"

	local src_dir="$dldir/libdvbcsa-src"
	local log_file="$ldir/libdvbcsa_build_$(date +%F-%H-%M).log"
	log_info "Building libdvbcsa. Full log will be at: $log_file"

	err_push_context "build_libdvbcsa"

	# Set up environment variables for cross-compilation
	local original_path="$PATH"
	export PATH="$toolchain_path/bin:$PATH"
	export CC="$cc"

	# Download/Clone the source
	log_header "Acquiring libdvbcsa source code"
	if [[ -d "$src_dir" ]]; then
		validate_command "Updating libdvbcsa repository" git -C "$src_dir" pull
	else
		if ! validate_command "Cloning libdvbcsa repository" git clone "https://github.com/oe-mirrors/libdvbcsa.git" "$src_dir"; then
			log_fatal "Failed to clone libdvbcsa repository." "$EXIT_ERROR"
		fi
	fi
	cd "$src_dir" || log_fatal "Could not enter libdvbcsa source directory." "$EXIT_MISSING"

	# Configure
	log_header "Configuring libdvbcsa (logging to file)"
	local host_target
	host_target=$("$cc" -dumpmachine)

	# Run bootstrap first to generate the configure script
	if ! { ./bootstrap >>"$log_file" 2>&1; }; then
		log_fatal "libdvbcsa bootstrap failed. See log: $log_file" "$EXIT_ERROR"
	fi

	local -a config_args=("--prefix=/usr" "--host=$host_target" "CFLAGS=--sysroot=$final_sysroot" "LDFLAGS=--sysroot=$final_sysroot")
	if ! { ./configure "${config_args[@]}" >>"$log_file" 2>&1; }; then
		log_fatal "libdvbcsa configuration failed. See log: $log_file" "$EXIT_ERROR"
	fi

	# Build and Install (to the final sysroot destination)
	log_header "Building and installing libdvbcsa (logging to file)"
	local -a make_args=("-j$(sys_get_cpu_count)" "install" "DESTDIR=$final_sysroot")
	# Here we use run_with_logging because it's the main build step and we want its output.
	# We can tee it to the main build log as well for consolidation.
	# For simplicity in this dependency, we'll log silently.
	if ! { make "${make_args[@]}" >>"$log_file" 2>&1; }; then
		log_fatal "libdvbcsa make/install failed. See log: $log_file" "$EXIT_ERROR"
	fi

	export PATH="$original_path"
	err_pop_context
	return 0
}
