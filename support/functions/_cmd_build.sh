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
	local meta_file
	meta_file=$(mktemp)
	trap 'rm -f "$meta_file"' RETURN

	# The pipeline's output is piped to tee for real-time console view and logging.
	_build_run_pipeline "$toolchain_name" "$log_path" "$meta_file" 2>&1 | tee -a "$log_path"
	local pipeline_exit_code=${PIPESTATUS[0]}

	# Update symlink
	if ! validate_command "Update last build log symlink" ln -frs "$log_path" "${workdir}/lastbuild.log"; then
		log_warn "Failed to update lastbuild.log symlink; log file: ${log_path}"
	fi

	# Parse metadata for artifact names
	local oscam_name
	oscam_name=$(head -n1 "$meta_file")
	local artifact_name
	artifact_name=$(head -n2 "$meta_file" | tail -n1)

	if [[ "$pipeline_exit_code" -ne 0 ]]; then
		log_fatal "CLI build failed for toolchain: ${toolchain_name}. Log: ${log_path}" "$EXIT_ERROR"
	fi

	log_info "Build artifact: $oscam_name"
	if [[ -n "$artifact_name" ]]; then
		log_info "Additional artifact: $artifact_name"
	fi

	build_finalize_and_archive "$oscam_name" "cli" "$toolchain_name"

	log_info "CLI Build completed successfully for toolchain: ${toolchain_name}"
	err_pop_context
}
