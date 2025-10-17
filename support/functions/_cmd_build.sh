#!/bin/bash

# A unified pipeline function to run the make command, ensuring consistent build logic
# with the GUI build process. It only contains the make command itself.
_build_run_make_pipeline() {
	# The 'codecheck' variable (scan-build) is handled by the caller.
	$codecheck $_make -j"$cpus" $_verbose \
		"CONF_DIR=$CONFDIR" \
		"OSCAM_BIN=$bdir/$oscam_name" \
		"CC_OPTS=$co $cc_opts $extra_cc" \
		"CC_WARN=$cc_warn" \
		"EXTRA_LDFLAGS=$extra_ld" \
		"EXTRA_CFLAGS=$extra_c" \
		$EXTRA_USE \
		$COMP_LEVEL \
		"CROSS=$CROSS" $STAPI_LIB $USESTRING $LIBCRYPTO_LIB $SSL_LIB $LIBUSB_LIB $PCSC_LIB $LIBDVBCSA_LIB
}

_cmd_build() {
	[ ! -d "${repodir}" ] || [ -f "$workdir/NEED-CHECKOUT" ] && checkout

	local timestamp
	timestamp=$(date +%F.%H-%M-%S) # Format: YYYY-MM-DD.HH-MM-SS

	if [ "$_toolchainname" == "native" ]; then
		log_name="${timestamp}.$(hostname).log"

	else
		log_name="${timestamp}.$_toolchainname.log"
	fi

	cfg_load_toolchain_config "$_toolchainname"
	_reset_config
	printf $WH
	ologo >"$ldir/$log_name"

	#set build defaults
	CROSS="$tcdir/$_toolchainname/bin/$_compiler"
	SYSROOT="$(realpath -sm $tcdir/$_toolchainname/$_sysroot)"
	[ "$_stagingdir" == "1" ] && export STAGING_DIR="$tcdir/$_toolchainname"
	[ "$_androidndkdir" == "1" ] && export ANDROID_NDK="$tcdir/$_toolchainname"
	[ -f "$configdir/compiler_option" ] && co=$(cat "$configdir/compiler_option") || co="-O2"

	# --- DEPENDENCY CHECK ---
	# Ensure critical libraries like OpenSSL are present in the toolchain's sysroot.
	# If not, this function will attempt to build and install them automatically.
	build_ensure_openssl "$SYSROOT" "$tcdir/$_toolchainname" "$CROSS""gcc"

	#toolchain defaults
	for defa in $default_use; do
		USE_vars[$defa]="$defa=1"
	done

	#disable by cmd
	for e in ${USE_vars[*]}; do

		for d in ${USE_vars_disable[*]}; do
			[ "$e" == "$d" ] && USE_vars[${e:0:-2}]=
		done

		if [ $e == "USE_DIAG=1" ]; then
			codecheck=$(command -v scan-build)
		fi
	done
	cd "${repodir}"

	#make clean
	make distclean >/dev/null 2>&1

	#patching
	if [ "${USE_vars['USE_PATCH']}" == "USE_PATCH=1" ]; then
		patch_apply_console
	fi

	#do enable and disable modules
	for am in "${all_cc[@]}"; do

		chose="false"
		if [ "${am:${#am}-3}" == "_on" ]; then
			e="${am:0:-3}"
			"${repodir}/config.sh" -E "$e" | awk '{printf "\033[1;37m"} {printf " |    %s : ", $1} {printf "\033[1;32m"} {printf "%s\n", $2}'
		fi

		if [ "${am:${#am}-4}" == "_off" ]; then
			d="${am:0:-4}"
			"${repodir}/config.sh" -D "$d" | awk '{printf "\033[1;37m"} {printf " |   %s : ", $1} {printf "\033[1;31m"} {printf "%s\n", $2}'
		fi

	done
	echo -en "\e[1A"

	#fix smargo case
	if [ "$(./config.sh -e CARDREADER_SMARGO)" == "Y" ] || [ "${USE_vars[$e]}" == "USE_LIBUSB=1" ]; then
		silent=$(./config.sh -E CARDREADER_SMARGO)
		check_smargo
	else
		silent=$(./config.sh -D CARDREADER_SMARGO)
		check_smargo
	fi

	#fix streamrelay case
	build_check_streamrelay_deps

	#fill use variables and set name addons
	USESTRING=
	EXTRA_USE=
	buildtype=""
	libcount=0
	statcount=0
	_usb=
	_pcsc=
	_dvbcsa=
	_stapi=
	_stapi5=
	_make="make"
	for e in "${!USE_vars[@]}"; do
		for e1 in $_block; do
			USE_vars[$e1]=
		done

		uv=${USE_vars[$e]}
		if [ ! "$e" == "USE_CONFDIR" ]; then
			USESTRING="$uv $USESTRING"
			if [ "${#USE_vars[$e]}" -gt "5" ]; then
				printf "\n$y_l |       set : ${USE_vars[$e]}"
			fi
		fi

		case "$uv" in
		"USE_LIBCRYPTO=1")
			((libcount++))
			;;
		"USE_SSL=1")
			((libcount++))
			;;
		"USE_LIBUSB=1")
			((libcount++))
			_usb="-libusb"
			;; # set libusb suffix to name
		"USE_PCSC=1")
			((libcount++))
			_pcsc_on
			_pcsc="-pcsc"
			;; # set pcsc suffix to name
		"USE_LIBDVBCSA=1")
			((libcount++))
			_dvbcsa="-libdvbcsa"
			;; # set libdvbcsa suffix to name
		"USE_TARGZ=1")
			s3cfg_vars[TARGZ]=1
			;; # overwrite global
		"USE_STAPI=1")
			_stapi="-stapi"
			[ -z "$stapi_lib_custom" ] && STAPI_LIB="STAPI_LIB=$sdir/stapi/liboscam_stapi.a" || STAPI_LIB="STAPI_LIB=$sdir/stapi/${stapi_lib_custom}"
			printf "$y_l\n |       LIB : ${c_l}$(basename "$STAPI_LIB")${w_l}"
			;;
		"USE_STAPI5=1")
			_stapi5="-stapi5"
			[ "$OPENBOX" == "1" ] && STAPI_LIB="STAPI5_LIB=$sdir/stapi/liboscam_stapi5_OPENBOX.a" && printf "$y_l\n |       LIB : "$c_l"liboscam_stapi5_OPENBOX.a"$w_l
			[ "$UFS916003" == "1" ] && STAPI_LIB="STAPI5_LIB=$sdir/stapi/liboscam_stapi5_UFS916_0.03.a" && printf "$y_l\n |       LIB : "$c_l"liboscam_stapi5_UFS916_0.03.a"$w_l
			[ "$UFS916003" == "0" ] && [ "$OPENBOX" == "0" ] && STAPI_LIB="STAPI5_LIB=$sdir/stapi/liboscam_stapi5_UFS916.a" && printf "$y_l\n |       LIB : "$c_l"liboscam_stapi5_UFS916.a"$w_l
			;;
		esac

	done

	#change default oscam CONF_DIR

	CONFDIR="$_oscamconfdir_default"
	cdtag="CONF_DIR=$CONFDIR"

	if [ ! -z "$_oscamconfdir_custom" ]; then
		if [ ! "$_oscamconfdir_custom" == "not_set" ]; then
			CONFDIR="$_oscamconfdir_custom"
			cdtag="${r_l}custom CONF_DIR=$_oscamconfdir_custom (via toolchain.cfg)"
		fi
	fi

	if [ ! "$CUSTOM_CONFDIR" == "not_set" ]; then
		CONFDIR="$CUSTOM_CONFDIR"
		cdtag="${r_l}custom CONF_DIR=$CUSTOM_CONFDIR (via CUSTOM_CONFDIR)"
	fi

	printf "$y_l\n |       set : ${cdtag}$w_l"

	#if build with profile
	[ ! "$pf" == "empty" ] && printf "\n$y_l |   PROFILE : $pf_name"

	#IF REPO is Patched
	if [ -f "$ispatched" ]; then
		printf "$y_l\n | ISPATCHED :$P YES (integrate patch information into WebIf)"
		build_patch_webif_info
	fi

	#prepare extra_* variables
	if [ "${USE_vars[USE_EXTRA]}" == "USE_EXTRA=1" ]; then
		printf "$y_l\n | EXTRAFLAGS: enabled"
		extra="-extra"
	else
		printf "$y_l\n | EXTRAFLAGS: disabled"
		unset extra_use extra_cc extra_ld extra_c
	fi

	#dynamic, static, mixed build
	set_buildtype

	#max cpu usage
	if [ -f "$configdir/max_cpus" ]; then
		cpus="$(cat "$configdir/max_cpus")"
		[ ! "$cpus" -gt "1" ] && cpus="1"
		[ "$cpus" -gt "$(sys_get_cpu_count)" ] && cpus="$(sys_get_cpu_count)"
		printf "$y_l\n |  MAX_CPUS : $txt_use $cpus $txt_of $(sys_get_cpu_count) CPU(s)"
	else
		cpus="$(sys_get_cpu_count)"
	fi

	[ "${s3cfg_vars[USE_VERBOSE]}" == "1" ] && _verbose="V=1"

	#signing case
	check_signing

	#build
	if [ ${#USE_vars[USE_OSCAMNAME]} -gt 0 ]; then
		oscam_name=$(echo ${USE_vars[USE_OSCAMNAME]} | cut -d "=" -f2)
	else
		_generate_oscam_name "$_toolchainname" "$extra$buildtype"
	fi

	if [[ $oscam_name =~ -upx ]]; then
		[ -f "$configdir/upx_option" ] && source "$configdir/upx_option"
		COMP_LEVEL="COMP_LEVEL=$upx_c"
	fi
	_nl
	USESTRING=${USE_vars[@]}
	EXTRA_USE=$extra_use
	timer_start
	run_with_logging "$ldir/$log_name" _build_run_make_pipeline |
		sed -e "s/^|/"$Y" |/g;s/^RM/"$R" REMOVE ----->$W/g;s/^CONF/"$C" CONFIG ----->$W/g;s/^LINK/"$P" LINK ------->$W/g;s/^STRIP/"$P" STRIP ------>$W/g;s/^CC\|^HOSTCC\|^BUILD/"$G" BUILD ------>$W/g;s/^GEN/"$C" GEN -------->/g;s/^UPX/"$GH" UPX -------->$W/g;s/^SIGN/"$YH" SIGN ------->$W/g;
	s/WEBIF_//g;s/WITH_//g;s/MODULE_//g;s/CS_//g;s/HAVE_//g;s/_CHARSETS//g;s/CW_CYCLE_CHECK/CWCC/g;s/SUPPORT//g;s/= /: /g;"

	# Check the exit status of the 'make' command (the first in the pipe).
	if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
		log_fatal "Build failed for $_toolchainname. See log for details: $ldir/$log_name" "$EXIT_ERROR"
	fi

	#calc buildtime
	timer_stop
	timer_calc
	bt="[ $txt_buildtime $((Tcalc / 60)) min(s) $((Tcalc % 60)) secs ]"

	#save list_smargo
	cd "${repodir}/Distribution"
	lsmn="$(ls list_smargo* 2>/dev/null)"

	if [ "${s3cfg_vars[SAVE_LISTSMARGO]}" == "1" ] && [ -f "${repodir}/Distribution/$lsmn" ]; then

		if [ "$_toolchainname" == "native" ]; then
			printf "$g_n"" SAVE -------> $w_l$lsmn$g_l $txt_as$y_l oscam-${REPO}$(REVISION)$($(USEGIT) && printf "@$(COMMIT)" || printf "")-$(hostname)-list_smargo"
			mv -f "$lsmn" "$bdir/oscam-${REPO}$(REVISION)$($(USEGIT) && printf "@$(COMMIT)" || printf "")-$(hostname)-list_smargo"
			tartmp="oscam-${REPO}$(REVISION)$($(USEGIT) && printf "@$(COMMIT)" || printf "")-$(hostname)-list_smargo"
		else
			printf "$g_n"" SAVE -------> $w_l$lsmn$g_l $txt_as$y_l oscam-${REPO}$(REVISION)$($(USEGIT) && printf "@$(COMMIT)" || printf "")-$_toolchainname-list_smargo"
			mv -f "$lsmn" "$bdir/oscam-${REPO}$(REVISION)$($(USEGIT) && printf "@$(COMMIT)" || printf "")-$_toolchainname-list_smargo"
			tartmp="oscam-${REPO}$(REVISION)$($(USEGIT) && printf "@$(COMMIT)" || printf "")-$_toolchainname-list_smargo"
		fi

	fi

	#remove debug binary
	if [ "${s3cfg_vars[delete_oscamdebugbinary]}" == "1" ] && [ -f "$bdir/$oscam_name.debug" ]; then
		printf "$r_l"" REMOVE ----->  $w_l$bdir/$oscam_name.debug"
		rm "$bdir/$oscam_name.debug"
	fi

	#show build time
	printf "$g_n""\n TIME -------> $bt$re_\n\n"

	if [ "${s3cfg_vars[TARGZ]}" == "1" ]; then
		printf "$w_l"" ENABLE -----> TARGZ:$y_l $txt_wait\n"
		tar_cam "$oscam_name" "$tartmp"
	fi

	#link lastlog
	ln -frs "$ldir/$log_name" "$workdir/lastbuild.log"
	if [ "${USE_vars[USE_DIAG]}" == "USE_DIAG=1" ]; then
		grep -v "^CC\|^GEN\|^CONF\|^RM\|^UPX\|^SIGN\|^BUILD\|STRIP\|LINK\|^SIGN\|^+\|^scan-build: R\|^scan-build: U\|HOSTCC\|^|" -i "$workdir/lastbuild.log" |
			sed $'s/ generated./ generated.\\\n\\\n\\\n/g' >"$workdir/USE_DIAG.log"
	fi

	#EXTRA_COPY_DIR
	if [ $EXTRA_COPY_DIR -eq 1 ]; then
		cd $bdir
		cp $oscam_name $here_
	fi

	log_info "Build process completed successfully."
	printf "$re_$w_l"
	return 0
}
