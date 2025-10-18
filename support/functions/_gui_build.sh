#!/bin/bash

_gui_build() {
	local toolchain_name="$_toolchainname" # Passed as a global from the menu

	local timestamp
	timestamp=$(date +%F.%H-%M-%S) # Format: YYYY-MM-DD.HH-MM-SS

	local log_name
	if [ "$toolchain_name" == "native" ]; then
		log_name="${timestamp}.$(hostname).log"
	else
		log_name="${timestamp}.${toolchain_name}.log"
	fi

	(
		# Run the unified build pipeline, saving full output to the log file.
		_build_run_pipeline "$toolchain_name" "$ldir/$log_name"
	) | ui_show_progressbox "Build $(REPOIDENT)"
	local exit_code=${PIPESTATUS[0]}

	# TAR handling for GUI (separate from pipeline)
	if [[ "$(cfg_get_value "s3" "USE_TARGZ")" == "1" ]]; then
		(tar_cam_gui "$oscam_name" "$tartmp") | tee -a "$ldir/$log_name" | ui_show_progressbox "TAR Binary" "" 10 70
	fi

	#link log
	ln -frs "$ldir/$log_name" "$workdir/lastbuild.log"

	# Final status check
	if [[ $exit_code -ne 0 ]]; then
		ui_show_msgbox "Build Failed" "The build failed. Please check the log file for details:\n\n$ldir/$log_name"
		log_fatal "GUI Build failed for $toolchain_name." "$EXIT_ERROR"
	fi
}
