#!/bin/bash

repo_checkout_git() {
	err_push_context "Git checkout operation"
	log_header "Starting Git Checkout"

	# Use the new network validation, which is already integrated into the error system
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

	log_info "Repository: $g_l$URL_OSCAM_REPO${w_l}"
	local commit="${1:-master}"
	if [[ "$commit" != "master" ]]; then
		log_info "Target: $y_l$(REFTYPE "$commit") $commit${w_l}"
	else
		log_info "Target: $y_l$txt_latest${w_l}"
	fi

	# The gitclone function already contains the core logic
	if ! validate_command "Cloning repository" gitclone "$commit"; then
		log_fatal "Git clone operation failed." "$EXIT_ERROR"
	fi

	if [ ! -f "${repodir}/config.sh" ]; then
		log_fatal "Checkout failed: 'config.sh' not found in repository." "$EXIT_MISSING"
	fi

	log_info "Revision:  $y_l$(REVISION) @ $(COMMIT) @ $(BRANCH)${w_l}"
	log_info "Local Path: $y_l${repodir}${w_l}"

	# Reset and backup repository state
	validate_command "Resetting config" "${repodir}/config.sh" -R
	[ -f "$ispatched" ] && rm -f "$ispatched"
	validate_command "Backing up repository" tar_repo

	err_pop_context
	return 0
}

repo_update_git() {
	err_push_context "Git update operation"
	log_header "Starting Git Update"

	if ! net_check_url "$URL_OSCAM_REPO"; then
		log_fatal "Repository URL is not accessible: $URL_OSCAM_REPO" "$EXIT_NETWORK"
	fi

	if [ -d "${repodir}" ]; then
		log_info "Updating existing repository in ${repodir}"
	else
		log_warn "Repository not found. Performing initial checkout instead."
		repo_checkout_git
		err_pop_context
		return 0
	fi

	log_info "Repository: $g_l$URL_OSCAM_REPO${w_l}"

	#check shallow cloned repo
	cd "${repodir}"
	if [ ! -f "$(git rev-parse --git-dir)"/shallow ]; then
		validate_command "Resetting local changes" git reset --hard HEAD
		validate_command "Switching to master branch" git checkout --quiet master
		validate_command "Pulling latest changes" git pull --quiet
		validate_command "Fetching tags" git pull --quiet --tags
	else
		log_warn "Repository is a shallow clone. Performing a fresh checkout to ensure consistency."
		cd "$workdir"
		branch="$(BRANCH)"
		validate_command "Removing shallow clone directory" rm -rf "${repodir}"
		local clone_depth
		clone_depth=$(cfg_get_value "s3" "GIT_CLONE_DEPTH" "1")
		validate_command "Cloning fresh shallow copy" git clone -c advice.detachedHead=false --quiet --depth="$clone_depth" --branch "$branch" "$URL_OSCAM_REPO" "${repodir}"
	fi

	if [ ! -f "${repodir}/config.sh" ]; then
		log_fatal "Update failed: 'config.sh' not found in repository." "$EXIT_MISSING"
	fi

	log_info "Revision:  $y_l$(REVISION) @ $(COMMIT) @ $(BRANCH)${w_l}"
	log_info "Local Path: $y_l${repodir}${w_l}"

	validate_command "Resetting config" "${repodir}/config.sh" -R
	tar_repo
	err_pop_context
	return 0
}

gitclone() {
	local clone_depth
	clone_depth=$(cfg_get_value "s3" "GIT_CLONE_DEPTH" "0")

	if [ "$clone_depth" -eq 0 ] || [ "$(REFTYPE "$1")" == 'sha' ]; then
		# Full clone (slow) is required for specific SHAs or if shallow clone is disabled.
		if [[ "$(REFTYPE "$1")" == 'sha' && "$clone_depth" -gt 0 ]]; then
			log_warn "Shallow cloning is enabled, but a specific commit SHA was requested. Performing a full clone."
		fi
		if ! git clone "$URL_OSCAM_REPO" "${repodir}"; then
			return 1
		fi
		if [ "$1" != "master" ]; then
			cd "${repodir}" && git -c advice.detachedHead=false checkout "$1"
		fi
	else
		# Shallow clone a repo (fast)
		log_info "Performing a shallow clone with depth: $clone_depth"
		if ! git clone -c advice.detachedHead=false --depth="$clone_depth" --branch "$1" "$URL_OSCAM_REPO" "${repodir}"; then
			return 1
		fi
	fi
	return 0
}

giturl() {
	git config --get remote.origin.url
}

repo_get_git_revision() {
	if echo "$1" | grep -qocP '^(https?|git@.*)://\S+'; then
		git ls-remote $1 2>/dev/null | head -1 | awk '{print substr($1, 1, 7)}' || echo 0
	else
		git -C $1 rev-parse --short HEAD 2>/dev/null || echo 0
	fi
}
