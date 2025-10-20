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

	# Load URLs config to get the patch URL
	if ! cfg_load_file "urls" "$configdir/urls"; then
		log_error "Failed to load URLs configuration."
		err_pop_context
		return 1
	fi

	local patch_url
	patch_url=$(cfg_get_value "urls" "URL_OSCAM_EMU_PATCH")

	if [[ -z "$patch_url" ]]; then
		log_error "URL_OSCAM_EMU_PATCH not found in URLs configuration."
		err_pop_context
		return 1
	fi

	if ! net_check_url "$patch_url"; then
		log_warn "Could not reach oscam-emu patch URL. Skipping download."
		err_pop_context
		return 1
	fi

	if validate_command "Downloading emu patch" net_download_file "$patch_url" "$dest_file"; then
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
		local patch_name
		patch_name=$(cfg_get_value "patch" "PATCHNAME$i")
		local patch_url
		patch_url=$(cfg_get_value "patch" "PATCHURL$i")

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
_patch_get_strip_level() {
	local ret=1 style='-p1'
	if [ -e "$1" ]; then
		PATCHEDFILES=$(grep -e '^\(---\|+++\) ' -i "$1" | grep -v /dev/null | awk '{print $2}' | sort | uniq)
		for f in ${PATCHEDFILES[@]}; do
			[[ -e "${repodir}/$f" ]] && {
				style='-p0'
				ret=0
				break
			}
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
	local patch_files
	patch_files=(*.patch)

	if [[ ${#patch_files[@]} -eq 0 || ! -f "${patch_files[0]}" ]]; then
		log_info "No .patch files found to apply."
		err_pop_context
		return 0
	fi

	log_header "Applying Patches"
	local patchlog_file="$ldir/patch_run_$(date +%F_%H-%M-%S).log"

	# Sort patches alphabetically for consistent application order
	local sorted_patch_files
	readarray -t sorted_patch_files < <(printf '%s\n' "${patch_files[@]}" | sort)

	for patch_file in "${sorted_patch_files[@]}"; do
		local patch_path="$pdir/$patch_file"
		local strip_level
		strip_level=$(_patch_get_strip_level "$patch_path")
		log_info "Applying patch: $patch_file (strip level: ${strip_level:1})"

		cd "${repodir}" || log_fatal "Repository directory not found: ${repodir}" "$EXIT_MISSING"

		# Determine patch command
		local patch_cmd
		if grep -q 'GIT binary patch' "$patch_path"; then
			log_debug "Binary patch detected, using 'git apply'."
			patch_cmd=("git" "apply" "--verbose" "$strip_level" "$patch_path")
		else
			patch_cmd=("patch" "-f" "$strip_level" "-i" "$patch_path")
		fi

		# Apply the patch, capturing output to a log and checking the result
		if run_with_logging "$patchlog_file" "${patch_cmd[@]}"; then
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
				if validate_command "Restoring last good repo state" repo_restore "last"; then
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
_patch_mark_as_patched() {
	local applied_patches=("$@")
	# Mark oscam-${REPO} as patched by creating the marker file
	# and listing the applied patches within it.
	printf "%s\n" "${applied_patches[@]}" >"$ispatched"
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

# Applies the oscam-emu patch and enables the WITH_EMU module
patch_apply_emu() {
	err_push_context "Apply oscam-emu patch"
	log_header "Applying oscam-emu patch"

	# --- Offer to use local patch before downloading ---
	local patch_file="$pdir/oscam-emu.patch"
	local should_download=true # Default behavior is to download

	if [[ -f "$patch_file" ]]; then
		log_info "Local 'oscam-emu.patch' found."
		if ui_show_yesno "A local patch exists. Use it instead of downloading the latest version?"; then
			log_info "Proceeding with the existing local patch as requested."
			should_download=false
		else
			log_info "User opted to download a fresh copy. The local patch will be overwritten."
		fi
	fi

	if [[ "$should_download" == true ]]; then
		if ! patch_download_emu; then
			# If download fails but a local file still exists, offer it as a fallback.
			if [[ -f "$patch_file" ]]; then
				log_warn "Download failed. An existing local patch is available."
				if ! ui_show_yesno "Do you want to try applying the local patch as a fallback?"; then
					log_error "Aborting patch process."
					err_pop_context
					return 1
				fi
				log_info "Proceeding with local patch as a fallback."
			else
				# This case handles when no local file existed AND the download failed.
				log_error "Download failed and no local patch is available to use as a fallback."
				err_pop_context
				return 1
			fi
		fi
	fi

	if [[ ! -f "$patch_file" ]]; then
		log_error "oscam-emu.patch not found after download attempt."
		err_pop_context
		return 1
	fi

	local strip_level
	strip_level=$(_patch_get_strip_level "$patch_file")

	log_info "Applying patch: oscam-emu.patch (strip level: ${strip_level:1})"
	cd "${repodir}" || log_fatal "Repository directory not found: ${repodir}" "$EXIT_MISSING"

	# Step 2: Ensure a clean state by reverting any previous application.
	# Use -f (force) to avoid errors if the patch isn't already applied.
	log_info "Attempting to revert any existing emu patch to ensure a clean state..."
	if patch -f -R "$strip_level" -i "$patch_file" >/dev/null 2>&1; then
		log_info "Reverted existing emu patch."
	else
		log_warn "Could not revert existing emu patch (perhaps not applied yet). Proceeding."
	fi

	local patch_log
	patch_log=$(mktemp)
	trap 'rm -f "$patch_log"' RETURN

	# Step 3: Perform a dry run to check for compatibility without modifying files.
	log_info "Performing a dry run to check patch compatibility..."
	if ! patch --dry-run --forward "$strip_level" -i "$patch_file" >"$patch_log" 2>&1; then
		log_error "EMU patch is not compatible with the current repository source."
		log_error "Dry run failed. See details below:"
		cat "$patch_log"
		log_warn "You may need to find an updated version of 'oscam-emu.patch'."
		err_pop_context
		return 1
	fi

	log_info "Dry run successful. Proceeding with actual patch application."

	# Step 4: Apply the patch for real.
	if ! patch --forward "$strip_level" -i "$patch_file" >>"$patch_log" 2>&1; then
		local patch_exit_code=$?
		if [[ "$patch_exit_code" -eq 1 ]]; then
			log_warn "EMU Patch applied with warnings (fuzz). This is usually safe. See log for details."
			cat "$patch_log"
		else
			log_error "Failed to apply emu patch even after a successful dry run. Exit code: $patch_exit_code"
			log_error "See details below:"
			cat "$patch_log"

			log_header "Restoring repository due to patch failure"
			if ! validate_command "Restoring last good repo state" repo_restore "last"; then
				log_fatal "Could not restore repository. Workspace may be in a broken state." "$EXIT_ERROR"
			else
				log_info "Repository restored to a clean state."
			fi

			err_pop_context
			return 1
		fi
	fi

	# Step 5: Mark repository as patched and enable the module.
	_patch_mark_as_patched "oscam-emu.patch"
	if ! validate_command "Enabling WITH_EMU module" "${repodir}/config.sh" --enable WITH_EMU; then
		log_warn "Could not automatically enable WITH_EMU module after patching."
	else
		log_info "Successfully enabled WITH_EMU module."
	fi

	log_info "oscam-emu patch applied successfully."
	err_pop_context
	return 0
}
