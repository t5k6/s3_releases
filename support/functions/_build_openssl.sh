#!/bin/bash
# =============================================================================
# SIMPLEBUILD3 - OpenSSL Build System
# =============================================================================
# Provides a unified function to download, configure, build, and install
# specific versions of OpenSSL for a given toolchain.
# =============================================================================

# Helper to determine OpenSSL config target
_openssl_get_config_target() {
	local cc="$1"
	local arch
	arch=$("$cc" -dumpmachine | awk -F'-' '{print $1}')
	case "$arch" in
	arm | armv7*) echo "linux-armv4" ;;
	aarch64) echo "linux-aarch64" ;;
	mips) echo "linux-mips32" ;;
	powerpc*) echo "linux-ppc" ;;
	sh4) echo "linux-sh" ;;
	i?86 | x86_64) echo "linux-x86_64" ;;
	*) echo "linux-generic32" ;;
	esac
}

# Main entry point for building OpenSSL.
# This function installs to a temporary directory and then copies the
# necessary files to the final sysroot destination.
build_openssl() {
	local version="$1"
	# $2 is the final sysroot, but we don't install there directly.
	local final_sysroot="$2"
	local cflags="$3"
	local ldflags="$4"
	local toolchain_path="$5" # The root of the toolchain dir, e.g., .../toolchains/oe20_armv7
	local cc="$6"             # The full path to the compiler, e.g., .../bin/arm-linux-gcc

	local src_dir="$dldir/openssl-src"
	# Create a temporary, isolated install directory for this build.
	local install_dir
	install_dir=$(mktemp -d -p "$dldir" "openssl_install_XXXXXX")

	local log_file="$ldir/openssl_build_${version}_$(date +%F-%H-%M).log"
	log_info "Attempting to build OpenSSL $version. Full log will be at: $log_file"

	err_push_context "build_openssl:$version"

	# Set Environment
	log_header "Configuring environment for OpenSSL build"
	local original_path="$PATH"
	export PATH="$toolchain_path/bin:$PATH"
	export CFLAGS="$cflags"
	export LDFLAGS="$ldflags"
	export CC="$cc"

	# Download and Extract
	_openssl_download_and_extract "$version" "$src_dir"
	if [[ $? -ne 0 ]]; then
		log_fatal "Failed to download or extract OpenSSL source." "$EXIT_ERROR"
	fi

	local openssl_src_path="$src_dir/openssl-$version"
	cd "$openssl_src_path" || log_fatal "Could not enter OpenSSL source directory: $openssl_src_path" "$EXIT_MISSING"

	# Configure
	log_header "Configuring OpenSSL $version (logging to file)"
	local config_target
	config_target=$(_openssl_get_config_target "$cc")

	local -a config_args=("$config_target" "no-shared" "no-tests" "--prefix=$install_dir")
	if ! { ./Configure "${config_args[@]}" >>"$log_file" 2>&1; }; then
		log_fatal "OpenSSL configuration failed. See log: $log_file" "$EXIT_ERROR"
	fi

	# Build
	log_header "Building OpenSSL $version (logging to file)"
	if ! { make -j"$(sys_get_cpu_count)" >>"$log_file" 2>&1; }; then
		log_fatal "OpenSSL make failed. See log: $log_file" "$EXIT_ERROR"
	fi

	# Install (to temporary directory)
	log_header "Installing OpenSSL $version to staging area (logging to file)"
	if ! { make install_sw >>"$log_file" 2>&1; }; then
		log_fatal "OpenSSL staging install failed. See log: $log_file" "$EXIT_ERROR"
	fi

	# Manually copy the essential files to the final destination.
	log_header "Copying OpenSSL artifacts to toolchain sysroot"
	validate_command "Creating final lib directory" mkdir -p "$final_sysroot/lib"
	validate_command "Creating final include directory" mkdir -p "$final_sysroot/include"
	validate_command "Creating final pkgconfig directory" mkdir -p "$final_sysroot/lib/pkgconfig"

	validate_command "Copying static libraries" cp -a "$install_dir"/lib/*.a "$final_sysroot/lib/"
	validate_command "Copying headers" cp -a "$install_dir"/include/openssl "$final_sysroot/include/"
	validate_command "Copying pkg-config files" cp -a "$install_dir"/lib/pkgconfig/*.pc "$final_sysroot/lib/pkgconfig/"

	# Cleanup
	log_info "Cleaning up temporary OpenSSL install directory..."
	rm -rf "$install_dir"

	log_info "OpenSSL $version build and installation complete."
	export PATH="$original_path"
	err_pop_context
}

# Private helper to handle downloading and extraction
_openssl_download_and_extract() {
	local version="$1"
	local dest_dir="$2"
	err_push_context "_openssl_download_and_extract:$version"

	local archive_name="openssl-$version.tar.gz"
	local archive_path="$dldir/$archive_name"
	local url="https://www.openssl.org/source/$archive_name"

	local expected_hash
	expected_hash=$(net_get_openssl_checksum "$archive_name")
	if [[ -z "$expected_hash" ]]; then
		log_error "Could not retrieve the official checksum for OpenSSL $version. Aborting for safety."
		err_pop_context
		return 1
	fi
	log_info "Retrieved official SHA256 hash for $archive_name: $expected_hash"

	if [[ -f "$archive_path" ]]; then
		log_info "Verifying existing OpenSSL archive..."
		if echo "$expected_hash  $archive_path" | sha256sum --status -c - &>/dev/null; then
			log_info "Checksum valid. Skipping download."
		else
			log_warn "Checksum mismatch. Removing and re-downloading."
			rm -f "$archive_path"
		fi
	fi

	if [[ ! -f "$archive_path" ]]; then
		log_header "Downloading OpenSSL $version"
		if ! net_download_file "$url" "$archive_path" "ui_show_progressbox 'Downloading OpenSSL' 'Downloading $archive_name'"; then
			err_pop_context
			return 1
		fi
		if ! echo "$expected_hash  $archive_path" | sha256sum --status -c - &>/dev/null; then
			log_error "Checksum validation failed after download for '$archive_path'."
			err_pop_context
			return 1
		fi
	fi

	log_header "Extracting OpenSSL $version"
	rm -rf "$dest_dir/openssl-$version"
	if ! validate_command "Extracting OpenSSL archive" tar -xzf "$archive_path" -C "$dest_dir"; then
		log_error "Failed to extract OpenSSL archive."
		err_pop_context
		return 1
	fi
	err_pop_context
}
