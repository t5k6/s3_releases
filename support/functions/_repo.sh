#!/bin/bash

# =============================================================================
# SIMPLEBUILD3 - Repository Management
# =============================================================================
# Centralizes all operations related to the OScam source repository, including
# checkout, update, cleaning, backup, and restoration.
# =============================================================================

repo_checkout() {
	if $(repo_is_git); then
		repo_checkout_git "$@"
	else
		repo_checkout_svn "$@"
	fi
}

repo_update() {
	if $(repo_is_git); then
		repo_update_git "$@"
	else
		repo_update_svn "$@"
	fi
}

repo_clean() {
	err_push_context "Repository Clean"

	# Identify targets for cleaning
	local wc_folders
	mapfile -t wc_folders < <(find "$workdir" -maxdepth 1 -type d -name "oscam-${REPO}${ID}" -printf "%P\n")

	local backup_files
	mapfile -t backup_files < <(find "$brepo" -maxdepth 1 -name "*-${REPO}${ID}.tar.gz" -printf "%f\n")

	local count_wc="${#wc_folders[@]}"
	local count_backups="${#backup_files[@]}"

	if [[ "$count_wc" -eq 0 && "$count_backups" -eq 0 ]]; then
		ui_show_msgbox "Clean Workspace" "Nothing to clean. No active repository or backups found for ${REPO}${ID}."
		err_pop_context
		return 0
	fi

	# Confirm action with user
	local msg="This will PERMANENTLY DELETE:\n\n"
	msg+="  - ${count_wc} Active Source Folder(s)\n"
	msg+="  - ${count_backups} Backup Archive(s)\n\n"
	msg+="For target: oscam-${REPO}${ID}\n\nAre you sure you want to proceed?"

	if ! ui_show_yesno "$msg"; then
		log_info "Clean operation cancelled by user."
		err_pop_context
		return 0
	fi

	log_header "Cleaning Workspace for ${REPO}${ID}"

	# Process Source Folders
	if [[ "$count_wc" -gt 0 ]]; then
		for wc in "${wc_folders[@]}"; do
			if validate_command "Removing source $wc" rm -rf "$workdir/$wc"; then
				log_info "Removed source directory: $wc"
			fi
		done
	fi

	# Process Backups
	if [[ "$count_backups" -gt 0 ]]; then
		for b in "${backup_files[@]}"; do
			if validate_command "Removing backup $b" rm -f "$brepo/$b"; then
				log_info "Removed backup file: $b"
			fi
		done
	fi

	# Clean patch marker
	if [[ -f "$ispatched" ]]; then
		rm -f "$ispatched"
		log_debug "Removed patch marker file."
	fi

	log_info "Clean operation completed."
	sleep 1
	err_pop_context
}

repo_backup() {
	err_push_context "Repository Backup"

	if [[ ! -d "${repodir}" ]]; then
		log_error "Cannot backup: Repository directory not found at ${repodir}"
		err_pop_context
		return 1
	fi

	local rev
	rev="$($(repo_is_git) && repo_get_commit || repo_get_revision)"
	local backup_name="${rev}-${REPO}${ID}.tar.gz"
	local backup_path="$brepo/$backup_name"
	local latest_link="$brepo/last-${REPO}${ID}.tar.gz"

	log_info "Creating repository backup: $backup_name"

	# Save a master copy of config files before backup
	if [[ -f "${repodir}/config.sh" ]]; then
		validate_command "Backing up master config.sh" cp -f "${repodir}/config.sh" "$configdir/config.sh.master"
	fi
	if [[ -f "${repodir}/Makefile" ]]; then
		validate_command "Backing up master Makefile" cp -f "${repodir}/Makefile" "$configdir/Makefile.master"
	fi

	# Use unified archive creation
	if file_create_archive "$backup_path" "${repodir}"; then
		# Manage 'latest' symlink
		if validate_command "Updating latest link" ln -frs "$backup_path" "$latest_link"; then
			log_info "Backup successful. Marked as latest."
		fi
	else
		log_error "Backup failed."
		err_pop_context
		return 1
	fi

	err_pop_context
	return 0
}

repo_restore() {
	local target_backup="$1"
	err_push_context "Repository Restore"

	# If no specific backup requested, show selection menu
	if [[ -z "$target_backup" || "$target_backup" == "list" ]]; then
		local backups
		mapfile -t backups < <(find "$brepo" -maxdepth 1 -name "*-${REPO}${ID}.tar.gz" -printf "%f\n" | sort -r)

		if [[ ${#backups[@]} -eq 0 ]]; then
			ui_show_msgbox "Restore" "No backups found for ${REPO}${ID}."
			err_pop_context
			return 1
		fi

		menu_init "Select Backup to Restore" "Restore Backup from Archive"
		menu_add_option "last" "Latest available backup"
		for b in "${backups[@]}"; do
			menu_add_option "$b" "$b"
		done

		if menu_show_list; then
			target_backup="$(menu_get_first_selection)"
		else
			log_info "Restore cancelled."
			err_pop_context
			return 0
		fi
	fi

	local backup_path="$brepo/$target_backup"
	# Handle "last" keyword specifically if passed via CLI or menu
	if [[ "$target_backup" == "last" ]]; then
		backup_path="$brepo/last-${REPO}${ID}.tar.gz"
	fi

	if [[ ! -f "$backup_path" ]]; then
		log_error "Backup file not found: $backup_path"
		err_pop_context
		return 1
	fi

	log_header "Restoring Repository from $(basename "$backup_path")"

	# Clean existing repo if it exists
	if [[ -d "${repodir}" ]]; then
		log_info "Removing current repository directory..."
		if ! validate_command "Cleaning repodir" rm -rf "${repodir}"; then
			log_fatal "Failed to remove existing repository before restore." "$EXIT_PERMISSION"
		fi
	fi

	# Use unified Archive Extraction
	# We extract to workdir because the archive contains the 'oscam-svn' folder itself
	if file_extract_archive "$backup_path" "$workdir" "ui_show_progressbox 'Restoring Backup' 'Extracting $(basename "$backup_path")...'"; then
		log_info "Restore complete."

		# Cleanup old state files
		rm -f "$workdir/lastbuild.log" "$workdir/lastpatch.log" "$ispatched" 2>/dev/null
	else
		log_fatal "Failed to extract backup archive." "$EXIT_ERROR"
	fi

	err_pop_context
	return 0
}

# -----------------------------------------------------------------------------
# Helper & Information Functions
# -----------------------------------------------------------------------------

repo_get_revision() {
	if [[ -d "${repodir}" ]]; then
		# Execute inside subshell to avoid changing main script's CWD
		(
			cd "${repodir}" || return
			if grep -q -- '--oscam-revision' "config.sh"; then
				./config.sh --oscam-revision
			else
				./config.sh --oscam-version | cut -d '-' -f 2-
			fi
		)
	else
		echo "0"
	fi
}

repo_get_branch() {
	err_push_context "Get repo branch"
	if [[ ! -d "${repodir}" ]]; then
		echo ""
		err_pop_context
		return
	fi

	if repo_is_git; then
		# A robust way to find the current branch or tag
		git -C "${repodir}" symbolic-ref --short -q HEAD ||
			git -C "${repodir}" describe --tags --exact-match 2>/dev/null ||
			git -C "${repodir}" rev-parse --short HEAD
	else
		# SVN fallback remains the same
		echo "$trunkurl" | awk -F'/' '{ print $NF }'
	fi
	err_pop_context
}

repo_get_type() {
	repo_is_git && echo "git" || echo "svn"
}

repo_get_url() {
	if [[ -d "${repodir}" ]]; then
		if repo_is_git; then
			git -C "${repodir}" config --get remote.origin.url
		else
			svn info "${repodir}" | sed -ne 's/^URL: //p'
		fi
	else
		echo "$URL_OSCAM_REPO"
	fi
}

repo_is_url_dirty() {
	# Compares the working copy's remote URL to the one defined in the s3 config.
	# Returns true (0) if they are different.
	[[ "$(repo_get_url)" != "$URL_OSCAM_REPO" ]]
}

repo_get_identifier() {
	if [[ -n "${SOURCE:-}" ]]; then
		echo "${SOURCE}"
	else
		echo ""
	fi
}

repo_is_git() {
	echo "$URL_OSCAM_REPO" | grep -qe '^git@\|.git$'
}

repo_get_commit() {
	if [[ -d "${repodir}" ]] && repo_is_git; then
		git -C "${repodir}" rev-parse --short HEAD 2>/dev/null || echo ""
	else
		echo ""
	fi
}
