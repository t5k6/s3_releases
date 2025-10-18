#!/bin/bash

_cmd_build() {
	err_push_context "Command-Line Build Execution"
	local toolchain_name="$1"

	# Validate input
	if [[ -z "$toolchain_name" ]]; then
		log_fatal "No toolchain name provided for CLI build." "$EXIT_MISSING"
	fi

	# Check repository state with error checking
	if [[ ! -d "${repodir}" || -f "${workdir}/NEED-CHECKOUT" ]]; then
		log_info "Initiating repository checkout..."
		if ! validate_command "Checkout repository" repo_checkout; then
			log_fatal "Repository checkout failed." "$EXIT_ERROR"
		fi
	fi

	local timestamp
	timestamp=$(date +%F.%H-%M-%S)
	local log_name
	if [[ "$toolchain_name" == "native" ]]; then
		log_name="${timestamp}.$(hostname).log"
	else
		log_name="${timestamp}.${toolchain_name}.log"
	fi
	local log_path="${ldir}/${log_name}"

	# Execute pipeline with unified logging
	log_info "Starting build pipeline for toolchain: ${toolchain_name}"
	local pipeline_output
	pipeline_output=$(_build_run_pipeline "$toolchain_name" "$log_path" 2>&1 | tee -a "$log_path")
	local pipeline_exit_code=${PIPESTATUS[0]}

	# Parse pipeline output for artifact name
	local oscam_name
	oscam_name=$(echo "$pipeline_output" | head -n 1)
	if [[ -z "$oscam_name" ]]; then
		log_warn "Failed to retrieve binary name from pipeline."
	fi

	# Handle TAR generation
	if [[ "$(cfg_get_value "s3" "USE_TARGZ" "0")" == "1" ]]; then
		log_info "Generating TAR archive"
		if ! validate_command "Generate TAR archive" tar_cam "$oscam_name" "$tartmp"; then
			log_warn "TAR generation failed; continuing post-processing"
		fi
	fi

	# Update symlink
	if ! validate_command "Update last build log symlink" ln -frs "$log_path" "${workdir}/lastbuild.log"; then
		log_warn "Failed to update lastbuild.log symlink; log file: ${log_path}"
	fi

	# Handle USE_DIAG with unified logging
	if [[ "${USE_vars[USE_DIAG]}" == "USE_DIAG=1" ]]; then
		log_info "Generating diagnostic log"
		local diag_log="${workdir}/USE_DIAG.log"
		# This is a complex pipe; validating the whole thing is sufficient.
		if ! validate_command "Generate diagnostic log" sh -c "grep -v '^CC|^GEN|^CONF|^RM|^UPX|^SIGN|^BUILD|STRIP|LINK|^SIGN|^+\|^scan-build: R\|^scan-build: U\|HOSTCC\|^|' -i \"${workdir}/lastbuild.log\" | sed $'s/ generated./ generated.\\\n\\\n\\\n/g' > \"$diag_log\""; then
			log_warn "Diagnostic log generation failed; skipping"
		fi
	fi

	# Handle extra copy with error checking
	if [[ ${EXTRA_COPY_DIR:-0} -eq 1 ]]; then
		log_info "Copying artifact to extra directory"
		local original_dir
		original_dir=$(pwd)
		if validate_command "Enter binaries directory" cd "${bdir}"; then
			if ! validate_command "Copy artifact" cp "$oscam_name" "$here_"; then
				log_warn "Failed to copy artifact to extra directory"
			fi
			cd "$original_dir" # Return to original directory
		else
			log_warn "Failed to enter binaries directory; skipping extra copy"
		fi
	fi

	# Final status check
	if [[ "$pipeline_exit_code" -ne 0 ]]; then
		log_fatal "CLI build failed for toolchain: ${toolchain_name}. Log: ${log_path}" "$EXIT_ERROR"
	fi

	log_info "CLI Build completed successfully for toolchain: ${toolchain_name}"
	err_pop_context
}
