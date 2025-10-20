#!/bin/bash

repo_checkout_svn() {
	err_push_context "SVN checkout operation"
	log_header "Starting SVN Checkout"

	if ! net_check_url "$URL_OSCAM_REPO"; then
		log_fatal "Repository URL is not accessible: $URL_OSCAM_REPO" "$EXIT_NETWORK"
	fi

	if [ -d "${repodir}" ]; then
		log_info "Removing existing repository directory: ${repodir}"
		if ! validate_command "Removing old directory" rm -rf "${repodir}"; then
			log_fatal "Failed to remove existing repository directory." "$EXIT_ERROR"
		fi
	else
		log_info "No existing repository found. Proceeding with new checkout."
	fi

	local opt_=''
	local mac_=''
	if [ -n "$1" ] && [ "$1" -gt 6999 ]; then
		opt_="-r$1"
		mac_="($txt_selected)"
	fi

	log_info "Repository: $g_l$URL_OSCAM_REPO${w_l}"
	if [ -n "$opt_" ]; then
		log_info "Target: $y_l$(REFTYPE "$1") $1${w_l}"
	else
		log_info "Target: $y_l$txt_latest${w_l}"
	fi

	# Count total files for potential progress reporting
	local total_files
	total_files=$(svn info -R "$URL_OSCAM_REPO" 2>/dev/null | grep '^URL' | uniq | wc -l)
	log_info "Total files to checkout: $total_files"

	if ! validate_command "Checking out repository" svn co "$URL_OSCAM_REPO" $opt_ "${repodir}"; then
		log_fatal "SVN checkout operation failed." "$EXIT_ERROR"
	fi

	if [ ! -f "${repodir}/config.sh" ]; then
		log_fatal "Checkout failed: 'config.sh' not found in repository." "$EXIT_MISSING"
	fi

	log_info "Revision:  $y_l$(repo_get_revision) @ $(repo_get_branch)${mac_:+$w_l$mac_}${w_l}"
	log_info "Local Path: $y_l${repodir}${w_l}"

	validate_command "Resetting config" "${repodir}/config.sh" -R
	[ -f "$ispatched" ] && rm -f "$ispatched"

	if ! repo_backup; then
		log_warn "Initial repository backup failed."
	fi

	err_pop_context
	return 0
}

repo_update_svn() {
	err_push_context "SVN update operation"
	log_header "Starting SVN Update"

	if ! net_check_url "$URL_OSCAM_REPO"; then
		log_fatal "Repository URL is not accessible: $URL_OSCAM_REPO" "$EXIT_NETWORK"
	fi

	if [ -d "${repodir}" ]; then
		log_info "Updating existing repository in ${repodir}"
	else
		log_warn "Repository not found. Performing initial checkout instead."
		repo_checkout_svn
		err_pop_context
		return 0
	fi

	log_info "Repository: $g_l$URL_OSCAM_REPO${w_l}"

	if ! validate_command "Updating repository" svn update "${repodir}"; then
		log_fatal "SVN update operation failed." "$EXIT_ERROR"
	fi

	if [ ! -f "${repodir}/config.sh" ]; then
		log_fatal "Update failed: 'config.sh' not found in repository." "$EXIT_MISSING"
	fi

	log_info "Revision:  $y_l$(repo_get_revision) @ $(repo_get_branch)${w_l}"
	log_info "Local Path: $y_l${repodir}${w_l}"

	validate_command "Resetting config" "${repodir}/config.sh" -R

	if ! repo_backup; then
		log_warn "Repository backup failed after update."
	fi

	err_pop_context
	return 0
}
