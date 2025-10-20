#!/bin/bash

_update_me_logic() {
	local current_branch
	current_branch=$(git rev-parse --abbrev-ref HEAD)
	if [[ -z "$current_branch" ]]; then
		log_error "Could not determine current branch. Aborting update."
		err_pop_context
		return 1
	fi
	log_info "Current branch is '$current_branch'."

	log_info "Fetching latest changes from remote..."
	if ! validate_command "Fetching from remote" git fetch --prune; then
		log_error "Failed to fetch from remote. Check your network connection and repository URL."
		err_pop_context
		return 1
	fi

	log_info "Checking for local and remote differences..."
	# Use @{u} which is a safe shorthand for the upstream branch
	local local_hash remote_hash
	local_hash=$(git rev-parse HEAD)
	remote_hash=$(git rev-parse "@{u}")

	if [[ "$local_hash" == "$remote_hash" ]]; then
		log_info "SimpleBuild3 is already up to date."
		err_pop_context
		return 0
	else
		log_info "Updates available. Your HEAD is at ${local_hash:0:7}, remote is at ${remote_hash:0:7}."

		# Check for uncommitted changes before doing a hard reset.
		if ! git diff-index --quiet HEAD --; then
			log_warn "You have local, uncommitted changes. Stashing them before update..."
			validate_command "Stashing local changes" git stash push -m "s3-autostash-before-update"
		fi

		if ! validate_command "Hard resetting to upstream branch" git reset --hard "@{u}"; then
			log_fatal "Update failed during hard reset. Manual intervention may be required." "$EXIT_ERROR"
		fi

		log_info "SimpleBuild3 update completed successfully."
	fi

	err_pop_context
}

sys_update_self() {
	err_push_context "Update s3 operation"
	clear
	ui_show_s3_logo
	printf "  s3_git CHECK:\n  -------------\n"

	if ! validate_command "Checking repository URL" net_check_url "$URL_S3_REPO"; then
		log_warn "Could not reach the S3 repository. Skipping update check."
		err_pop_context
		sleep 2
		return 1
	fi

	# SimpleBuild3 now requires Git repository mode for safety
	logfile="$ldir/$(date +%F.%H%M%S)_update_me.log"
	run_with_logging "$logfile" _update_me_logic
	if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
		log_error "Update operation failed. See log for details: $logfile"
		err_pop_context
		return 1
	fi

	err_pop_context
	sleep 2
}

sys_repair_self() {
	# Since we no longer support non-git mode, repair means reset to remote
	err_push_context "Repair s3 operation"
	clear
	ui_show_s3_logo

	log_info "Repairing SimpleBuild3 by resetting to remote state..."

	# Ensure we're in a git repository (should already be verified by main script)
	if [[ ! -d "$workdir/.git" ]]; then
		log_fatal "SimpleBuild3 must be run from a Git repository." "$EXIT_INVALID_CONFIG"
	fi

	# Force update by doing a hard reset to remote
	if ! validate_command "Fetching from remote" git fetch --prune; then
		log_error "Failed to fetch from remote during repair."
		err_pop_context
		return 1
	fi

	if ! validate_command "Hard resetting to origin/master" git reset --hard origin/master; then
		log_error "Failed to reset to origin/master. Trying current branch's upstream..."
		if ! validate_command "Hard resetting to upstream" git reset --hard "@{u}"; then
			log_fatal "Repair failed. Manual intervention required." "$EXIT_ERROR"
		fi
	fi

	log_info "SimpleBuild3 has been repaired and reset to remote state."
	err_pop_context
	sleep 2
}
