#!/bin/bash
# =============================================================================
# SIMPLEBUILD3 - OpenSSL Build System
# =============================================================================
# Provides a unified function to download, configure, build, and install
# specific versions of OpenSSL for a given toolchain.
# =============================================================================

# Main entry point for building OpenSSL. Called by the library build orchestrator.
# Usage: build_openssl <version> <prefix> <cflags> <ldflags> <toolchain_path> <cc>
build_openssl() {
	local version="$1"
	local prefix="$2"
	local cflags="$3"
	local ldflags="$4"
	local toolchain_path="$5"
	local cc="$6"
	local src_dir="$dldir/openssl-src"
	local log_file="$ldir/openssl_build_${version}_$(date +%F-%H-%M).log"
	log_info "Attempting to build OpenSSL $version. Full log will be available at: $log_file"

	err_push_context "build_openssl:$version"

	# 3. Set Environment
	log_header "Configuring environment for OpenSSL build"
	local original_path="$PATH"
	export PATH="$toolchain_path/bin:$PATH" # Prepend toolchain bin to PATH
	export CFLAGS="$cflags"
	export LDFLAGS="$ldflags"
	export CC="$cc"

	# 2. Download and Extract using unified functions
	_openssl_download_and_extract "$version" "$src_dir"
	if [[ $? -ne 0 ]]; then
		log_fatal "Failed to download or extract OpenSSL source." "$EXIT_ERROR"
	fi

	local openssl_src_path="$src_dir/openssl-$version"
	cd "$openssl_src_path" || log_fatal "Could not enter OpenSSL source directory: $openssl_src_path" "$EXIT_MISSING"

	# 4. Configure
	log_header "Configuring OpenSSL $version (logging to file)"
	local target_arch
	target_arch=$("$cc" -dumpmachine | awk -F'-' '{print $1}')
	local config_target
	case "$target_arch" in
	arm | armv7*) config_target="linux-armv4" ;;
	aarch64) config_target="linux-aarch64" ;;
	mips) config_target="linux-mips32" ;;
	powerpc*) config_target="linux-ppc" ;;
	sh4) config_target="linux-sh" ;;
	i?86 | x86_64) config_target="linux-x86_64" ;;
	*)
		log_warn "Could not determine a specific OpenSSL target for arch '$target_arch'. Using generic 'linux-generic32'."
		config_target="linux-generic32"
		;;
	esac
	local config_flags="$config_target no-shared no-tests" # no-shared builds static libs
	if ! (./Configure --prefix="$prefix" $config_flags >>"$log_file" 2>&1); then
		log_fatal "OpenSSL configuration failed. See log for details: $log_file" "$EXIT_ERROR"
	fi

	# 5. Build
	log_header "Building OpenSSL $version (logging to file)"
	if ! (make -j"$(sys_get_cpu_count)" >>"$log_file" 2>&1); then
		log_fatal "OpenSSL make failed. See log for details: $log_file" "$EXIT_ERROR"
	fi

	# 6. Install
	log_header "Installing OpenSSL $version (logging to file)"
	if ! (make install_sw >>"$log_file" 2>&1); then
		log_fatal "OpenSSL install failed. See log for details: $log_file" "$EXIT_ERROR"
	fi

	log_info "OpenSSL $version build and installation complete."
	export PATH="$original_path" # Restore original PATH
	err_pop_context
	return 0
}

# Private helper to handle downloading and extraction
_openssl_download_and_extract() {
	local version="$1"
	local dest_dir="$2"

	local archive_name="openssl-$version.tar.gz"
	local archive_path="$dldir/$archive_name"
	local url="https://www.openssl.org/source/$archive_name"

	# Dynamically fetch the expected checksum
	local expected_hash
	expected_hash=$(net_get_openssl_checksum "$archive_name")
	if [[ -z "$expected_hash" ]]; then
		log_error "Could not retrieve the official checksum for OpenSSL $version. Aborting build for safety."
		return 1
	fi
	log_info "Retrieved official SHA256 hash for $archive_name: $expected_hash"

	# Check if archive exists and is valid
	if [[ -f "$archive_path" ]]; then
		log_info "Verifying existing OpenSSL archive..."
		if sha256sum -c <<<"$expected_hash  $archive_path" &>/dev/null; then
			log_info "Checksum valid. Skipping download."
		else
			log_warn "Checksum mismatch. Removing and re-downloading."
			rm -f "$archive_path"
		fi
	fi

	# Download if needed
	if [[ ! -f "$archive_path" ]]; then
		log_header "Downloading OpenSSL $version"
		if ! net_download_file "$url" "$archive_path" "ui_show_progressbox 'Downloading OpenSSL' 'Downloading $archive_name'"; then
			return 1
		fi
		if ! sha256sum -c <<<"$expected_hash  $archive_path" &>/dev/null; then
			log_error "Checksum validation failed after download for '$archive_path'."
			return 1
		fi
	fi

	# Extract
	log_header "Extracting OpenSSL $version"
	# Clean destination before extracting
	rm -rf "$dest_dir/openssl-$version"
	if ! file_extract_archive "$archive_path" "$dest_dir"; then
		return 1
	fi

	return 0
}
