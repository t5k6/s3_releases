#!/bin/bash

_cmd_build() {
	local toolchain_name="$1"

	if [ ! -d "${repodir}" ] || [ -f "$workdir/NEED-CHECKOUT" ]; then
		checkout
	fi

	local timestamp
	timestamp=$(date +%F.%H-%M-%S) # Format: YYYY-MM-DD.HH-MM-SS

	local log_name
	if [ "$toolchain_name" == "native" ]; then
		log_name="${timestamp}.$(hostname).log"
	else
		log_name="${timestamp}.${toolchain_name}.log"
	fi

	# Run the unified pipeline, teeing output for logging and console display.
	_build_run_pipeline "$toolchain_name" "$ldir/$log_name" 2>&1 | tee -a "$ldir/$log_name"
	local exit_code=${PIPESTATUS[0]}

	# Post-build actions specific to command-line
	if [[ "$(cfg_get_value "s3" "USE_TARGZ")" == "1" ]]; then
		printf "$w_l"" ENABLE -----> TARGZ:$y_l $txt_wait\n"
		tar_cam "$oscam_name" "$tartmp"
	fi
	ln -frs "$ldir/$log_name" "$workdir/lastbuild.log"
	if [[ "${USE_vars[USE_DIAG]}" == "USE_DIAG=1" ]]; then
		grep -v "^CC\|^GEN\|^CONF\|^RM\|^UPX\|^SIGN\|^BUILD\|STRIP\|LINK\|^SIGN\|^+\|^scan-build: R\|^scan-build: U\|HOSTCC\|^|" -i "$workdir/lastbuild.log" |
			sed $'s/ generated./ generated.\\\n\\\n\\\n/g' >"$workdir/USE_DIAG.log"
	fi
	if [[ ${EXTRA_COPY_DIR:-0} -eq 1 ]]; then
		cd "$bdir"
		cp "$oscam_name" "$here_"
	fi

	# Check build status
	if [[ $exit_code -ne 0 ]]; then
		log_fatal "Build failed for $toolchain_name. See log for details: $ldir/$log_name" "$EXIT_ERROR"
	fi
}
