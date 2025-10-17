#!/bin/bash
# =============================================================================
# SIMPLEBUILD3 - OpenSSL Build System
# =============================================================================
# Provides a unified function to download, configure, build, and install
# specific versions of OpenSSL for a given toolchain.
# =============================================================================

# This associative array separates data (versions, hashes) from logic.
# It could also be moved to a dedicated config file loaded via cfg_load_file.
declare -gA _OPENSSL_RECIPES=(
    ["3.0.13"]="c842b3e599833453982f1703642e46f6f3a7b97355152b865529124378f44d18:linux-generic32"
    ["1.1.1w"]="b8b1511728387754c731e065fb02657d4a040b07b165b5fd87c0205b0a39a9c1:linux-generic32"
    ["1.0.2u"]="ecd0c6ffb493dd06707d38b14bb4d8c228c26928a5038b38779a57201248721c:linux-generic32"
)

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

    err_push_context "build_openssl:$version"

    # 1. Validate version and get recipe
    local recipe="${_OPENSSL_RECIPES[$version]}"
    if [[ -z "$recipe" ]]; then
        log_fatal "Unsupported OpenSSL version specified: $version" "$EXIT_INVALID_CONFIG"
    fi
    IFS=':' read -r expected_hash config_target <<< "$recipe"

    # 2. Download and Extract using unified functions
    _openssl_download_and_extract "$version" "$expected_hash" "$src_dir"
    if [[ $? -ne 0 ]]; then
        log_fatal "Failed to download or extract OpenSSL source." "$EXIT_ERROR"
    fi

    local openssl_src_path="$src_dir/openssl-$version"
    cd "$openssl_src_path" || log_fatal "Could not enter OpenSSL source directory: $openssl_src_path" "$EXIT_MISSING"

    # 3. Set Environment
    log_header "Configuring environment for OpenSSL build"
    export PATH="$toolchain_path/bin:$PATH"
    export CFLAGS="$cflags"
    export LDFLAGS="$ldflags"
    export CC="$cc"

    # 4. Configure
    log_header "Configuring OpenSSL $version"
    local config_flags="$config_target shared no-tests"
    validate_command "OpenSSL configure" ./Configure --prefix="$prefix" $config_flags
    if [[ $? -ne 0 ]]; then
        log_fatal "OpenSSL configuration failed." "$EXIT_ERROR"
    fi

    # 5. Build
    log_header "Building OpenSSL $version"
    validate_command "OpenSSL make" make -j"$(sys_get_cpu_count)"
    if [[ $? -ne 0 ]]; then
        log_fatal "OpenSSL make failed." "$EXIT_ERROR"
    fi

    # 6. Install
    log_header "Installing OpenSSL $version"
    validate_command "OpenSSL install" make install_sw
    if [[ $? -ne 0 ]]; then
        log_fatal "OpenSSL install failed." "$EXIT_ERROR"
    fi

    log_info "OpenSSL $version build and installation complete."
    err_pop_context
    return 0
}

# Private helper to handle downloading and extraction
_openssl_download_and_extract() {
    local version="$1"
    local expected_hash="$2"
    local dest_dir="$3"

    local archive_name="openssl-$version.tar.gz"
    local archive_path="$dldir/$archive_name"
    local url="https://www.openssl.org/source/$archive_name"

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
