#!/bin/bash

_gui_build() {
	err_push_context "GUI Build Execution"

	local toolchain_name="$_toolchainname"
	if [[ -z "$toolchain_name" ]]; then
		log_fatal "No toolchain name provided for GUI build." "$EXIT_MISSING"
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

	log_info "Starting build pipeline for toolchain: ${toolchain_name}"

	# --- Use process substitution with 'tee' to both display output and capture the return value ---
	# This allows the`ui_show_programbox` to display the scrolling build log while
	# still allowing the pipeline's final return values (oscam_name) to be captured.
	local pipeline_output
	pipeline_output=$(_build_run_pipeline "$toolchain_name" "$log_path" | tee >(ui_show_programbox "Build $(REPOIDENT)"))
	local pipeline_exit_code=${PIPESTATUS[0]}

	local oscam_name
	oscam_name=$(echo "$pipeline_output" | head -n 1)

	# Handle TAR generation (this part remains the same)
	if [[ "$(cfg_get_value "s3" "USE_TARGZ" "0")" == "1" ]]; then
		log_info "Generating TAR archive for build artifact"
		if ! run_with_logging "$log_path" tar_cam_gui "$oscam_name" "$tartmp" | ui_show_progressbox "TAR Binary" "" 10 70; then
			log_warn "TAR archive generation failed; continuing post-processing"
		fi
	fi

	if ! validate_command "Update last build log symlink" ln -frs "$log_path" "${workdir}/lastbuild.log"; then
		log_warn "Failed to update lastbuild.log symlink; log file: ${log_path}"
	fi

	# --- Provide explicit UI feedback for both success and failure ---
	if [[ "$pipeline_exit_code" -ne 0 ]]; then
		if [[ -z "$oscam_name" ]]; then
			log_warn "Failed to retrieve binary name from build pipeline, as the build failed."
		fi
		ui_show_msgbox "Build Failed" "The build failed. Check log:\n\n${log_path}"
	else
		log_info "GUI Build completed successfully for toolchain: ${toolchain_name}"
		ui_show_msgbox "Build Successful" "The binary has been created successfully:\n\n${bdir}/${oscam_name}"
	fi

	err_pop_context
}
