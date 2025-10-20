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

	# Use metadata file to reliably capture build artifacts
	local meta_file
	meta_file=$(mktemp)
	trap 'rm -f "$meta_file"' RETURN

	# Show a waiting message to the user, as the build will now run synchronously.
	ui_show_msgbox "Build Starting" "The build process for '$toolchain_name' is starting.\n\nPlease wait, this may take several minutes.\nThe screen will update upon completion." "8" "70"

	# Run the build pipeline synchronously. All output is handled by the pipeline's internal logging.
	_build_run_pipeline "$toolchain_name" "$log_path" "$meta_file"
	local pipeline_exit_code=$?

	# Create the lastbuild.log symlink immediately after the build finishes.
	if [[ -f "$log_path" ]]; then
		if ! validate_command "Update last build log symlink" ln -frs "$log_path" "${workdir}/lastbuild.log"; then
			log_warn "Failed to update lastbuild.log symlink; log file: ${log_path}"
		fi
	else
		log_warn "Build log file '$log_path' was not created. Cannot create symlink."
	fi

	local oscam_name
	oscam_name=$(head -n1 "$meta_file")

	# --- Provide explicit UI feedback for both success and failure ---
	if [[ "$pipeline_exit_code" -ne 0 ]]; then
		log_error "GUI Build failed for toolchain: ${toolchain_name}"
		# On failure, automatically show the user the log file.
		ui_show_msgbox "Build Failed" "The build failed. The log file will now be displayed."
		ui_show_textbox "Build Log: $log_name" "$log_path"
	else
		log_info "GUI Build completed successfully for toolchain: ${toolchain_name}"

		build_finalize_and_archive "$oscam_name" "gui" "$toolchain_name"

		# On success, show the interactive post-build menu.
		ui_show_post_build_menu "$toolchain_name" "$oscam_name"
	fi

	err_pop_context
}
