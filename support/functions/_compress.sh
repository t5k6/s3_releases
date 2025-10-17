#!/bin/bash

# =============================================================================
# SIMPLEBUILD3 - File Operations Abstraction Layer
# =============================================================================
# Provides unified file/archive operations with consistent error handling.
# Replaces direct tar, unzip, and other archive manipulation commands.
# =============================================================================

# ------------------------------------------------------------------------------
# FILE EXTRACTION FUNCTIONS
# ------------------------------------------------------------------------------
# Main file/archive operations with unified error handling

file_extract_archive() {
    # Extract an archive file to a specified destination
    local archive_file="$1"
    local dest_path="${2:-.}"
    local progress_callback="${3:-}"
    local title="${4:-Extracting Archive}"
    local message="${5:-Please wait while extracting ${archive_file}}"

    err_init "Archive extraction from $archive_file"

    # Validate parameters
    err_validate_file_exists "$archive_file" "Archive extraction"

    if [ -z "$dest_path" ]; then
        err_log_and_exit "Destination path not specified" "$EXIT_INVALID_CONFIG"
    fi

    # Create destination directory if it doesn't exist
    if [ ! -d "$dest_path" ]; then
        mkdir -p "$dest_path" || err_log_and_exit "Failed to create destination directory: $dest_path"
    fi

    log_debug "Extracting $archive_file to $dest_path"

    # Detect archive type and extract accordingly
    local archive_type=""
    local extract_cmd=""

    # Determine archive type from file extension and content
    if [[ "$archive_file" =~ \.(tar\.gz|tgz)$ ]] || tar -tzf "$archive_file" >/dev/null 2>&1; then
        archive_type="tar.gz"
        extract_cmd="tar -xzf \"$archive_file\" -C \"$dest_path\""
    elif [[ "$archive_file" =~ \.(tar\.bz2|tbz2)$ ]] || tar -tjf "$archive_file" >/dev/null 2>&1; then
        archive_type="tar.bz2"
        extract_cmd="tar -xjf \"$archive_file\" -C \"$dest_path\""
    elif [[ "$archive_file" =~ \.(tar\.xz|txz)$ ]] || tar -tJf "$archive_file" >/dev/null 2>&1; then
        archive_type="tar.xz"
        extract_cmd="tar -xJf \"$archive_file\" -C \"$dest_path\""
    elif [[ "$archive_file" =~ \.tar$ ]] || tar -tf "$archive_file" >/dev/null 2>&1; then
        archive_type="tar"
        extract_cmd="tar -xf \"$archive_file\" -C \"$dest_path\""
    elif [[ "$archive_file" =~ \.zip$ ]] || unzip -l "$archive_file" >/dev/null 2>&1; then
        archive_type="zip"
        extract_cmd="unzip -q \"$archive_file\" -d \"$dest_path\""
    elif [[ "$archive_file" =~ \.(gz|gzip)$ ]]; then
        archive_type="gzip"
        extract_cmd="gunzip -c \"$archive_file\" > \"${dest_path}/$(basename "${archive_file%.gz}")\""
    elif [[ "$archive_file" =~ \.(bz2|bzip2)$ ]]; then
        archive_type="bzip2"
        extract_cmd="bunzip2 -c \"$archive_file\" > \"${dest_path}/$(basename "${archive_file%.bz2}")\""
    elif [[ "$archive_file" =~ \.xz$ ]]; then
        archive_type="xz"
        extract_cmd="unxz -c \"$archive_file\" > \"${dest_path}/$(basename "${archive_file%.xz}")\""
    else
        err_log_and_exit "Unsupported archive format: $archive_file" "$EXIT_INVALID_CONFIG"
    fi

    log_debug "Detected archive type: $archive_type"

    # Handle progress display if callback provided
    if [ -n "$progress_callback" ]; then
        # Use custom progress display
        { eval "$extract_cmd"; } 2>&1 | $progress_callback
    else
        # Execute extraction directly
        eval "$extract_cmd"
    fi

    err_check_command_result "$?" "Archive extraction: $archive_file to $dest_path"
}

file_create_archive() {
    # Create an archive from a file or directory
    local archive_file="$1"
    local source_path="$2"

    err_init "Archive creation to $archive_file"

    # Validate parameters
    if [ -z "$archive_file" ]; then
        err_log_and_exit "Archive file not specified" "$EXIT_INVALID_CONFIG"
    fi

    err_validate_file_exists "$source_path" "Archive creation"

    log_debug "Creating archive $archive_file from $source_path"

    # Create parent directory if needed
    mkdir -p "$(dirname "$archive_file")" || err_log_and_exit "Failed to create archive directory: $(dirname "$archive_file")"

    # Determine archive type from file extension
    if [[ "$archive_file" =~ \.(tar\.gz|tgz)$ ]]; then
        tar -czf "$archive_file" -C "$(dirname "$source_path")" "$(basename "$source_path")"
    elif [[ "$archive_file" =~ \.(tar\.bz2|tbz2)$ ]]; then
        tar -cjf "$archive_file" -C "$(dirname "$source_path")" "$(basename "$source_path")"
    elif [[ "$archive_file" =~ \.(tar\.xz|txz)$ ]]; then
        tar -cJf "$archive_file" -C "$(dirname "$source_path")" "$(basename "$source_path")"
    elif [[ "$archive_file" =~ \.tar$ ]]; then
        tar -cf "$archive_file" -C "$(dirname "$source_path")" "$(basename "$source_path")"
    elif [[ "$archive_file" =~ \.zip$ ]]; then
        cd "$(dirname "$source_path")" && zip -q -r "$(basename "$archive_file")" "$(basename "$source_path")"
    else
        err_log_and_exit "Unsupported archive format for creation: $archive_file" "$EXIT_INVALID_CONFIG"
    fi

    err_check_command_result "$?" "Archive creation: $source_path to $archive_file"
}

tar_cam_gui(){
	cd "$bdir"
	erg=$(tar zcf $1.tar.gz $1 $2)

	if [ -f "$1.tar.gz" ]
	then
		printf "\n$1.tar.gz\ncreated\n"
		if [ -f "$adir/$1.tar.gz" ]
		then
			rm -rf "$adir/$1.tar.gz"
			mv -f "$1.tar.gz" "$adir"
			printf "\n$1.tar.gz\n$txt_to\n$workdir/archive\n"
		else
			mv -f "$1.tar.gz" "$adir"
			printf "\n$1.tar.gz\n$txt_to\n$workdir/archive\n"
		fi
	else
		printf "\nerror\nno $1.tar.gz\ncreated\n"
	fi
}

tar_cam(){
	cd "$bdir"

	if [ -n $2 ]
	then
		printf "$y_n\n TAR -------->$w_l $1$g_l $txt_as$w_l $1.tar.gz$rs_"
	fi

	erg=$(tar zcf $1.tar.gz $1 $2)

	if [ -f "$1.tar.gz" ]
	then
		printf "$p_n$txt_done$rs_\n"

		if [ -f "$adir/$1.tar.gz" ]
		then
			rm -rf "$adir/$1.tar.gz"
			mv -f "$1.tar.gz" "$adir"
			printf "$c_l"" MOVE -------> $p_l$1.tar.gz $g_l$txt_to $y_n$workdir/archive$rs_\n\n"
		else
			mv -f "$1.tar.gz" "$adir"
			printf "$c_l"" MOVE -------> $p_l$1.tar.gz $g_l$txt_to $y_n$workdir/archive$rs_\n\n"
		fi

	else
		printf "$r_l\nerror\n no $1.tar.gz\n created$rs_\n"
	fi
}

tar_repo(){
	cd "$workdir"
	rev="$($(USEGIT) && printf "$(COMMIT)" || printf "$(REVISION)")"

	if [ -f "${repodir}/config.sh" ]
	then
		cp -f "${repodir}/config.sh" "$configdir/config.sh.master"
		[ -f "${repodir}/Makefile" ] && cp -f "${repodir}/Makefile" "$configdir/Makefile.master"
		printf "$w_l  ${REPO^^} Backup    :$c_l "
		tar -zcf "$brepo/$rev-${REPO}${ID}.tar.gz" $(basename ${repodir})
	fi

	cd "$brepo"
	ln -frs "$brepo/$rev-${REPO}${ID}.tar.gz" "last-${REPO}${ID}.tar.gz"
	printf "done$re_\n\n"
}

untar_repo(){
	cd "$workdir"
	[ -d $(basename ${repodir}) ] && rm -rf $(basename ${repodir});
	if [ -z "$1" ]
	then
		[ -f "$brepo/last-${REPO}${ID}.tar.gz" ] && tar -xf "$brepo/last-${REPO}${ID}.tar.gz"
		printf "\e[1A $w_l ${REPO^^} Revision  : $c_l$(basename $(readlink -f $brepo/last-${REPO}${ID}.tar.gz) .tar.gz)$w_l\n"
	else
		if [ -f "$brepo/$1-${REPO}${ID}.tar.gz" ]
		then
			tar -xf "$brepo/$1-${REPO}${ID}.tar.gz"
			cd $brepo
			ln -frs "$brepo/$($(USEGIT) && printf "$(COMMIT)" || printf "$(REVISION)")-${REPO}${ID}.tar.gz" "last-${REPO}${ID}.tar.gz"
			printf "\e[1A $w_l ${REPO^^} Revision  : $c_l$(basename $(readlink -f $brepo/last-${REPO}${ID}.tar.gz) .tar.gz)$w_l\n"
		else
			if [ -f "$brepo/last-${REPO}${ID}.tar.gz" ]
			then
				tar -xf "$brepo/last-${REPO}${ID}.tar.gz"
				printf "\e[1A $w_l ${REPO^^} Revision  : $c_l$(basename $(readlink -f $brepo/last-${REPO}${ID}.tar.gz) .tar.gz)$w_l\n"
			else
				printf "$w_l  ${REPO^^} Backup    :$r_l $txt_not_found\n"
				sleep 3
				checkout
			fi
		fi
	fi

	[ -f "$ispatched" ] && rm -f "$ispatched"
}
