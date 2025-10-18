#!/bin/bash

_update_me_logic() {
	err_push_context "s3 Self-Update Logic"

	cd $workdir
	GIT_OPT='-c color.ui=always --no-pager'

	log_info "Determining current git branch..."
	if ! validate_command "Getting current branch" git branch | tail -n1 | tr -d ' *'; then
		log_error "Could not determine current branch. Aborting update."
		err_pop_context
		return 1
	fi
	GIT_BRANCH="$(git branch | tail -n1 | tr -d ' *')"

	log_info "Fetching latest changes from remote..."
	if ! validate_command "Fetching from remote" git $GIT_OPT fetch --prune; then
		log_error "Failed to fetch from remote. Check network connection."
		err_pop_context
		return 1
	fi

	log_info "Checking for local and remote differences..."
	ahead=$(git rev-list origin/$GIT_BRANCH..HEAD --count) #local commits made or forced pushes on remote branch
	behind=$(git rev-list HEAD..origin/$GIT_BRANCH --count)
	local_revision=$(git rev-list HEAD --count)
	local_commit=$(git --no-pager log HEAD -n1 --oneline)
	online_revision=$(git rev-list origin/$GIT_BRANCH --count)
	online_commit=$(git --no-pager log origin/$GIT_BRANCH -n1 --oneline)

	if [ $behind -eq 0 -a $ahead -eq 0 ]; then
		log_info "s3 is already up to date (revision $local_revision)"
	else
		log_info "Updates available. Local: $local_revision, Remote: $online_revision"

		if [ $ahead -gt 0 ]; then
			log_info "Attempting reset to handle forced pushes..."
			if ! validate_command "Hard resetting to origin/$GIT_BRANCH" git reset origin/$GIT_BRANCH --hard; then
				log_error "Could not perform hard reset. You may have local changes that are difficult to resolve."
				log_info "Consider running 'git status' and resolving conflicts manually."
				err_pop_context
				return 1
			fi
		else
			log_info "Starting standard pull process..."
		fi

		log_info "Attempting to pull latest changes..."
		if ! validate_command "Pulling changes from origin" git $GIT_OPT pull; then
			log_warn "Standard pull failed. This can happen due to local modifications."
			log_info "Attempting to resolve conflicts automatically..."

			# Try to resolve by checking out conflicting files
			if git $GIT_OPT pull 2>&1 | grep -q '^ '; then
				log_info "Resetting conflicting tracked files..."
				if ! git $GIT_OPT pull 2>&1 | grep '^ ' | xargs git checkout; then
					log_warn "Checkout failed. Stashing conflicting tracked files..."
					if ! validate_command "Stashing tracked files" git $GIT_OPT stash; then
						log_error "Could not stash files. Manual intervention required."
						err_pop_context
						return 1
					fi
					log_info "Removing conflicting untracked files..."
					git $GIT_OPT pull 2>&1 | grep '^ ' | xargs rm -rf
				fi
			fi

			if ! validate_command "Final pull after conflict resolution" git $GIT_OPT pull; then
				log_error "Update failed after multiple attempts."
				log_info "Cleaning up stash and recommending manual update."
				validate_command "Clearing stash" git $GIT_OPT stash clear
				err_pop_context
				return 1
			fi

			validate_command "Clearing temporary stash" git $GIT_OPT stash clear
		fi

		log_info "s3 update completed successfully."
	fi

	err_pop_context
}

sys_update_self() {
	err_push_context "Update s3 operation"
	clear
	s3logo
	printf "  s3_git CHECK:\n  -------------\n"
	local_revision=0
	online_revision=0
	# Use the new, robust network check function
	if ! validate_command "Checking repository URL" net_check_url "$URL_S3_REPO"; then
		log_warn "Could not reach the S3 repository. Skipping update check."
		err_pop_context
		sleep 2
		return 1
	fi

	if [ ! -d $workdir/.git ]; then
		s3local="$dldir/s3_github"

		local_revision=$(repo_get_git_revision $s3local)
		online_revision=$(repo_get_git_revision $URL_S3_REPO)

		if [ ! "$local_revision" == "$online_revision" ]; then
			printf "  update s3_git\n  Local revision: $local_revision\n Online revision: $online_revision\n"
			rm -rf "$s3local"
			git clone "$URL_S3_REPO" "$s3local" &>/dev/null
			cd "$s3local"
			printf "  updating all files ...\n\n"
			yes | cp -rf ./s3 "$workdir/s3"
			yes | cp -rf ./support/* "$workdir/support"
		else
			printf "  is up to date\n   Online revision: $online_revision\n\n"
		fi
	else
		logfile="$ldir/$(date +%F.%H%M%S)_update_me.log"
		run_with_logging "$logfile" _update_me_logic
		if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
			log_fatal "Update operation failed. See log for details: $logfile" "$EXIT_ERROR"
		fi
	fi
	err_pop_context
	sleep 2
}

sys_repair_self() {
	clear
	s3logo
	s3local="$dldir/s3_github"

	[ -d "$s3local" ] && rm -rf $s3local
	sys_update_self
}
