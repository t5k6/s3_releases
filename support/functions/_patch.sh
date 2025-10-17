#!/bin/bash

# =============================================================================
# SIMPLEBUILD3 - Patch Management System
# =============================================================================
# Provides functions for downloading and applying source code patches.
# This module has been refactored to align with modern project standards,
# including unified function naming, error handling, network operations,
# and configuration management.
# =============================================================================

# Downloads the latest oscam-emu patch from its predefined URL.
patch_download_emu() {
    err_push_context "Download oscam-emu patch"
    local dest_file="$pdir/oscam-emu.patch"
    log_header "Downloading oscam-emu patch"
    log_info "Checking for the latest oscam-emu patch..."

    if ! net_check_url "$URL_OSCAM_EMU_PATCH"; then
        log_warn "Could not reach oscam-emu patch URL. Skipping download."
        err_pop_context
        return 1
    fi

    if validate_command "Downloading emu patch" net_download_file "$URL_OSCAM_EMU_PATCH" "$dest_file"; then
        log_info "Successfully downloaded latest 'oscam-emu.patch'."
    else
        log_error "Failed to download 'oscam-emu.patch'. Patching will continue with existing files."
        err_pop_context
        return 1
    fi
    err_pop_context
    return 0
}

# Downloads custom patches defined in the `patch.url` config file.
patch_download_from_urls() {
    err_push_context "Download custom patches"
    clear
    slogo
    log_header "Downloading Custom Patches from patch.url"
    local patch_url_file="$pdir/patch.url"

    if [[ ! -f "$patch_url_file" ]]; then
        if [[ -f "$patch_url_file.template" ]]; then
            log_warn "Custom patch file not found: '$patch_url_file'."
            log_info "To use this feature, rename 'patch.url.template' to 'patch.url' and configure it."
        else
            log_info "No 'patch.url' file found. Skipping custom patch download."
        fi
        err_pop_context
        return 0
    fi

    # Use UCM for secure, consistent configuration loading.
    if ! cfg_load_file "patch" "$patch_url_file"; then
        log_fatal "Failed to load patch URL configuration: $patch_url_file" "$EXIT_INVALID_CONFIG"
    fi

    local patch_count
    patch_count=$(cfg_get_value "patch" "PATCHCOUNT" "0")
    if [[ "$patch_count" -eq 0 ]]; then
        log_info "PATCHCOUNT is 0 or not set. No custom patches to download."
        err_pop_context
        return 0
    fi

    log_info "Found $patch_count custom patch(es) to download."
    cd "$pdir" || log_fatal "Could not change to patch directory: $pdir" "$EXIT_MISSING"

    for i in $(seq 1 "$patch_count"); do
        local patch_name; patch_name=$(cfg_get_value "patch" "PATCHNAME$i")
        local patch_url; patch_url=$(cfg_get_value "patch" "PATCHURL$i")

        if [[ -n "$patch_name" && -n "$patch_url" ]]; then
            log_info "Processing patch #$i: $patch_name"
            [[ -f "$patch_name" ]] && validate_command "Removing old patch file" rm -f "$patch_name"

            if net_check_url "$patch_url"; then
                if validate_command "Downloading $patch_name" net_download_file "$patch_url" "$patch_name"; then
                    log_info "Successfully downloaded $patch_name."
                else
                    log_error "Download failed for $patch_name from $patch_url."
                fi
            else
                log_error "URL is not accessible: $patch_url"
            fi
        else
            log_warn "Skipping patch #$i due to missing name or URL."
        fi
    done
    err_pop_context
    return 0
}

# Determines the correct strip level (-p0 or -p1) for a patch file.
_patch_get_strip_level(){
	local ret=1 style='-p1'
	if [ -e "$1" ]; then
		PATCHEDFILES=$(grep -e '^\(---\|+++\) ' -i "$1" | grep -v /dev/null | awk '{print $2}' | sort | uniq)
		for f in ${PATCHEDFILES[@]}; do
			[[ -e "${repodir}/$f" ]] && { style='-p0'; ret=0; break; }
		done
	fi
	echo "$style"
	return $ret
}

patch_apply_console() {
    err_push_context "Apply patches (console)"

    if [[ -f "$ispatched" ]]; then
        log_info "Workspace is already patched. Skipping."
        err_pop_context
        return 0
    fi

    cd "$pdir" || log_fatal "Patch directory not found: $pdir" "$EXIT_MISSING"
    local patch_files; patch_files=(*.patch)

    if [[ ${#patch_files[@]} -eq 0 || ! -f "${patch_files[0]}" ]]; then
        log_info "No .patch files found to apply."
        err_pop_context
        return 0
    fi

    log_header "Applying Patches"
    local patchlog_file="$ldir/patch_run_$(date +%F_%H-%M-%S).log"

    # Sort patches alphabetically for consistent application order
    local sorted_patch_files; readarray -t sorted_patch_files < <(printf '%s\n' "${patch_files[@]}" | sort)

    for patch_file in "${sorted_patch_files[@]}"; do
        local patch_path="$pdir/$patch_file"
        local strip_level; strip_level=$(_patch_get_strip_level "$patch_path")
        log_info "Applying patch: $patch_file (strip level: ${strip_level:1})"

        cd "${repodir}" || log_fatal "Repository directory not found: ${repodir}" "$EXIT_MISSING"

        # Determine patch command
        local patch_cmd
        if grep -q 'GIT binary patch' "$patch_path"; then
            log_debug "Binary patch detected, using 'git apply'."
            patch_cmd=("git" "apply" "--verbose" "$strip_level")
        else
            patch_cmd=("patch" "-f" "$strip_level")
        fi

        # Apply the patch, capturing output to a log and checking the result
        if run_with_logging "$patchlog_file" "${patch_cmd[@]}" < "$patch_path"; then
            log_info "Successfully applied '$patch_file'."
        else
            # patch returns 1 for successful application with "fuzz" (hunks), which is a warning.
            # patch returns >1 for a hard failure.
            local patch_exit_code=${PIPESTATUS[0]}
            if [[ $patch_exit_code -eq 1 ]]; then
                log_warn "Patch '$patch_file' applied with warnings (fuzz). Check log for details: $patchlog_file"
            else
                log_error "Failed to apply patch '$patch_file' (exit code: $patch_exit_code). See log: $patchlog_file"
                log_header "Restoring repository due to patch failure"
                if validate_command "Restoring last good repo state" repo_restore "last-${REPO}${ID}"; then
                     log_info "Repository restored."
                else
                     log_error "Could not restore repository. Workspace may be in a broken state."
                fi
                log_fatal "Patching process aborted." "$EXIT_ERROR"
            fi
        fi
    done

    # Link the consolidated log to a stable name
    ln -frs "$patchlog_file" "$workdir/lastpatch.log"
    _patch_mark_as_patched "${sorted_patch_files[@]}"
    log_info "All patches applied."

    err_pop_context
    return 0
}

# Creates the patch marker file to prevent re-patching.
_patch_mark_as_patched(){
	local applied_patches=("$@")
	# Mark oscam-${REPO} as patched by creating the marker file
	# and listing the applied patches within it.
	printf "%s\n" "${applied_patches[@]}" > "$ispatched"
}

# Injects patch information into the WebIF source code before building.
build_patch_webif_info() {
    err_push_context "Patch WebIF Info"

    # This function only runs if the PATCH_WEBIF config is enabled and the repo is patched.
    if [[ "$(cfg_get_value "s3" "PATCH_WEBIF" "1")" != "1" || ! -f "$ispatched" ]]; then
        log_debug "Skipping WebIF patch info injection."
        err_pop_context
        return 0
    fi

    log_info "Injecting patch information into WebIF."

    local patches
    if [[ -s "$ispatched" ]]; then
        # Format the list of patches for display in C code.
        # It expects a string like: "yes\\n\\t\\tpatch1.patch\\n\\t\\tpatch2.patch"
        patches="yes\\\\n\\\\t\\\\t$(paste -sd '\\\\n\\\\t\\\\t' "$ispatched")"
    else
        patches='yes'
    fi

    local config_h_file="${repodir}/config.h"
    local oscam_c_file="${repodir}/oscam.c"

    if [[ ! -f "$config_h_file" || ! -f "$oscam_c_file" ]]; then
        log_warn "Could not find config.h or oscam.c to inject WebIF info."
        err_pop_context
        return 1
    fi

	# Atomically apply a series of sed commands to modify the source files.
	sed -i -e '/^#define S3PATCHED/d' \
		-e "/^#endif \/\/OSCAM_CONFIG_H_/s/^/#define S3PATCHED \"${patches}\"\\n/" \
		"$config_h_file"

	sed -i -e '/#ifdef S3PATCHED/,+3d' \
		-e "/fprintf(fp, \"WebifPort:.*/s/$/\\n#endif\\n\\n#ifdef S3PATCHED\\n\\tfprintf(fp, \"Patched:\\\\t\\%s\\\\n\", S3PATCHED);/" \
		"$oscam_c_file"

    log_info "WebIF patch info injected successfully."
    err_pop_context
    return 0
}

# DEPRECATED name wrappers for backward compatibility
patch_download_custom(){ patch_download_from_urls; }
get_emu_patch() { patch_download_emu; }
repo_apply_patches(){
	if [ -f "$ispatched" ]; then
		repo_restore_quick "$_toolchainname" 2>/dev/null
	fi

	# This function is called from the build menu and should be interactive
	# However, the interactive version is not yet fully implemented.
	# Falling back to console version for now.
	patch_apply_console
}
patch_webif(){ build_patch_webif_info; }
