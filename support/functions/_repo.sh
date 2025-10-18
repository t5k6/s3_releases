#!/bin/bash

repo_checkout() {
	if $(USEGIT); then
		repo_checkout_git "$@"
	else
		repo_checkout_svn "$@"
	fi
}

repo_clean() {
	clear
	echo -en "$c_l"
	ui_show_logo_s3

	cd "$workdir"
	wcfolders="$(find . -maxdepth 1 -type d -name "oscam-${REPO}${ID}" | sed 's|./||')"
	bcount=$(echo "$wcfolders" | wc -w)

	if [ "$bcount" -gt "0" ]; then
		echo -e "\n$c_l    ${bcount}$w_l oscam-${REPO}${ID} $txt_wc ${txt_found}\n    ___________________________________$re_\n"
		for wc in $wcfolders; do
			rm -rf $wc
			echo -e "$c_l    --> $w_l$txt_delete $txt_wc $wc"
		done
		_nl
	else
		echo -e "\n$r_l    ${bcount}$w_l oscam-${REPO}${ID} $txt_wc ${txt_found}\n    ___________________________________$re_\n"
	fi

	cd "$brepo"
	bfiles="$(find . -maxdepth 1 -name "*-${REPO}${ID}.tar.gz" | sed 's|./||')"
	bcount=$(echo "$bfiles" | wc -w)

	if [ "$bcount" -gt "0" ]; then
		echo -e "\n$c_l    ${bcount}$w_l ${REPO}${ID} backup ${txt_found}\n    _______________________$re_\n"
		for b in $bfiles; do
			rm -f $b
			echo -e "$c_l    --> $w_l$txt_delete backup $b"
		done
		_nl
	else
		echo -e "\n$r_l    ${bcount}$w_l ${REPO}${ID} backup ${txt_found}\n    _______________________$re_\n"
	fi
	[ -f "$ispatched" ] && rm -f "$ispatched"
}

repo_restore() {
	clear
	echo -en "$c_l"
	ui_show_logo_s3

	if [ "$1" == "list" ]; then
		cd "$brepo"
		bfiles="$(find . -type f -name "*-${REPO}${ID}.tar.gz" | sed 's|./||' | sed 's|.tar.gz||')"
		bcount=$(echo "$bfiles" | wc -w)

		if [ "$bcount" -gt "0" ]; then
			echo -e "\n$c_l    $bcount$w_l ${REPO}${ID} backups found\n    ____________________$re_\n"
			for b in $bfiles; do
				echo -e "$c_l    --> $w_l$b"
			done
			_nl
		else
			echo -e "\n$r_l    $bcount$w_l ${REPO}${ID} backups found\n    ____________________$re_\n"
		fi

		exit
	fi

	if [ -d "${repodir}" ]; then
		rm -rf "${repodir}"
		printf "$p_l\n  $txt_delete $txt_existing oscam-${REPO}${ID} $re_\n"
	else
		printf "$p_l\n  $txt_no oscam-${REPO}${ID} $txt_found\n$re_"
	fi
	_nl
	file_extract_archive $1
	printf "\e[1A\t\t\t\t\t$y_l""restored\n\n$re_"
	[ -L "$workdir/lastbuild.log" ] && rm "$workdir/lastbuild.log"
	[ -L "$workdir/lastpatch.log" ] && rm "$workdir/lastpatch.log"
	[ -f "$ispatched" ] && rm -f "$ispatched"
}

repo_update() {
	if $(USEGIT); then
		repo_update_git "$@"
	else
		repo_update_svn "$@"
	fi
}

repo_get_revision() {
	if [ -d "${repodir}" ]; then
		(
			cd "${repodir}"
			if grep -q -- '--oscam-revision' "${repodir}/config.sh"; then
				./config.sh --oscam-revision
			else
				./config.sh --oscam-version | cut -d '-' -f 2-
			fi
		)
	fi
}

repo_get_commit() {
	if [ -d "${repodir}" ]; then
		(cd "${repodir}" && $(USEGIT) && git rev-parse --short HEAD 2>/dev/null) || printf ''
	fi
}

BRANCH() {
	if [ -d "${repodir}" ]; then
		(cd "${repodir}" && {
			if $(USEGIT); then
				ref="$(git name-rev --name-only "$(COMMIT)" 2>/dev/null | awk -F'/' '{ print $NF }' | awk -F'~' '{ print $1 }' | awk -F'^' '{ print $1 }')"
				if [ "$ref" == "$(REVISION)" ]; then
					branch=$(git branch | tail -n1 | tr -d ' *')
					[ "$branch" == "(nobranch)" ] && printf 'master' || printf "$branch"
				else
					printf "$ref"
				fi
			else
				printf "$trunkurl" | awk -F'/' '{ print $NF }'
			fi
		})
	fi
}

repo_is_git() {
	echo $URL_OSCAM_REPO | grep -qe '^git@\|.git$'
}

USEGIT() {
	repo_is_git
}

REFTYPE() {
	if [[ "$1" =~ ^[0-9a-f]{8,40}$ ]]; then
		printf 'sha'
	elif [ "$1" -eq "$1" ] 2>/dev/null; then
		printf 'tag'
	else
		printf 'branch'
	fi
}

REPOTYPE() {
	$(USEGIT) && printf 'git' || printf 'svn'
}

REPOURL() {
	if [ -d "${repodir}" ] && cd "${repodir}"; then
		if $(USEGIT); then
			giturl
		else
			svnurl
		fi
	else
		printf "$URL_OSCAM_REPO"
	fi
}

REPOURLDIRTY() {
	[ "$(REPOURL)" == "$URL_OSCAM_REPO" ] && return 1 || return 0
}

REPOIDENT() {
	if [ -v SOURCE ]; then
		printf " $SOURCE"
	else
		printf ""
	fi
}

REVISION() {
	repo_get_revision
}

COMMIT() {
	repo_get_commit
}
