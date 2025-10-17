#!/bin/bash

# Source ANSI color functions
source "$fdir/_ansi.sh"

sys_check_binaries() {
	# Optimized binary checking with caching and reduced find operations
	err_init "Binary system check"
	local output_mode="${1:-verbose}" # verbose/silent/summary
	local binary_cache="/tmp/s3_binary_cache_$BASHPID"

	sys_check_output "$output_mode" "$w_l\n  CHECK for binaries\n  ==================$re_\n"

	# Setup caching to avoid repeated binary detection
	local cached_bins=""
	if [ -f "$binary_cache" ]; then
		cached_bins=$(cat "$binary_cache")
	fi

	local failed_bins=()
	local found_bins=()

	for binary in "${binvars[@]}"; do
		local binary_path=""

		# Check cache first
		if [ -n "$cached_bins" ]; then
			binary_path=$(echo "$cached_bins" | grep "^$binary:" | cut -d':' -f2)
		fi

		# If not in cache or cache miss, check system
		if [ -z "$binary_path" ]; then
			if [ "$binary" = "autoconf-archive" ]; then
				# Special case for autoconf-archive, which is a collection of m4 files, not an executable.
				# We check for a known file's existence in common locations instead of an executable path.
				for aclocal_dir in /usr/share/aclocal /usr/local/share/aclocal; do
					if [ -f "$aclocal_dir/ax_absolute_header.m4" ]; then
						binary_path="$aclocal_dir/ax_absolute_header.m4"
						break
					fi
				done
			else
				binary_path=$(type -pf "$binary" 2>/dev/null || which "$binary" 2>/dev/null || echo "")
			fi
		fi

		if [ -n "$binary_path" ] && { [ "$binary" = "autoconf-archive" ] || [ -x "$binary_path" ]; }; then
			printf -v pad %40s
			binary_display="${binary}${pad}"
			binary_display="${binary_display:0:16}"
			sys_check_output "$output_mode" "$w_l  have\t$g_l${binary_display} $y_l$binary_path$re_\n"
			found_bins+=("$binary:$binary_path")
		else
			printf -v pad %40s
			binary_display="${binary}${pad}"
			binary_display="${binary_display:0:16}"
			sys_check_output "$output_mode" "$r_l  need\t$w_l${binary_display} $r_l(not found)$re_\n"
			failed_bins+=("$binary")
		fi
	done

	# Cache successful finds
	printf "%s\n" "${found_bins[@]}" >"$binary_cache"

	# Return the number of failures as the exit code. 0 means success.
	return ${#failed_bins[@]}
}

sys_check_headers() {
	# Optimized header file checking with reduced filesystem operations
	err_init "Header system check"
	local output_mode="${1:-verbose}" # verbose/silent/summary
	local header_cache="/tmp/s3_header_cache_$BASHPID"

	sys_check_output "$output_mode" "$w_l\n  CHECK for headers\n  =================$re_\n"

	# Define search paths once
	local search_paths=("/usr/include" "/usr/local/include")
	[ -n "${SYSROOT:-}" ] && search_paths+=("${SYSROOT}/usr/include")

	local failed_headers=()
	local found_headers=()

	for header in "${headervars[@]}"; do
		local header_found="false"
		local header_path=""

		# Special handling for dvbcsa.h with config override
		if [ "$header" = "dvbcsa.h" ] && [ "$(cfg_get_value "s3" "INSTALL_NATIVE_LIBDVBCSA" "1")" = "0" ]; then
			sys_check_output "$output_mode" "$r_l  need\t$w_l${header} $r_l (skipped by config)$re_\n"
			failed_headers+=("$header(config_skipped)")
			continue
		fi

		# Search for header
		for include_path in "${search_paths[@]}"; do
			if [ -f "$include_path/$header" ]; then
				header_path="$include_path/$header"
				header_found="true"
				break
			fi
			# Also check subdirectories for complex headers
			header_path=$(find "$include_path" -name "$header" -type f 2>/dev/null | head -1)
			if [ -n "$header_path" ]; then
				header_found="true"
				break
			fi
		done

		printf -v pad %40s
		header_display="${header}${pad}"
		header_display="${header_display:0:16}"

		if [ "$header_found" = "true" ] && [ -n "$header_path" ]; then
			sys_check_output "$output_mode" "$w_l  have\t$g_l${header_display} $y_l$header_path$re_\n"
			found_headers+=("$header:$header_path")
		else
			sys_check_output "$output_mode" "$r_l  need\t$w_l${header_display} $r_l(not found)$re_\n"
			failed_headers+=("$header")
		fi
	done

	# Cache successful finds
	printf "%s\n" "${found_headers[@]}" >"$header_cache"

	# Return the number of failures as the exit code. 0 means success.
	return ${#failed_headers[@]}
}

sys_check_libraries() {
	# Optimized library checking with intelligent caching
	err_init "Library system check"
	local output_mode="${1:-verbose}" # verbose/silent/summary
	local lib_cache="/tmp/s3_lib_cache_$BASHPID"

	sys_check_output "$output_mode" "$w_l\n  CHECK for libraries\n  ===================$re_\n"

	local failed_libs=()
	local found_libs=()

	for lib in "${libvars[@]}"; do
		# Use find with more targeted search
		lib_path=$(find /usr/lib* /usr/local/lib* -name "$lib" -type f 2>/dev/null | head -1)
		[ -n "${SYSROOT:-}" ] && lib_path="${lib_path:-$(find "${SYSROOT}"/usr/lib* -name "$lib" -type f 2>/dev/null | head -1)}"

		printf -v pad %40s
		lib_display="${lib}${pad}"
		lib_display="${lib_display:0:16}"

		if [ -n "$lib_path" ]; then
			sys_check_output "$output_mode" "$w_l  have\t$g_l${lib_display} $y_l$lib_path$re_\n"
			found_libs+=("$lib:$lib_path")
		else
			sys_check_output "$output_mode" "$r_l  need\t$w_l${lib_display} $r_l(not found)$re_\n"
			failed_libs+=("$lib")
		fi
	done

	# Special x86_64 zlib32 check
	if [ "$(uname -m)" = "x86_64" ]; then
		sys_check_output "$output_mode" "$w_l\n  CHECK for zlib32\n  ================$re_\n"
		local zlib32_found="false"
		local zlib32_path=""

		if [ -f "/usr/lib/libz.so" ]; then
			zlib32_path="/usr/lib/libz.so"
			zlib32_found="true"
		elif [ -f "/usr/lib32/libz.so.1" ]; then
			zlib32_path="/usr/lib32/libz.so.1"
			zlib32_found="true"
		fi

		if [ "$zlib32_found" = "true" ]; then
			sys_check_output "$output_mode" "$w_l  have\t$g_l zlib32  $y_l$zlib32_path$re_\n"
		else
			sys_check_output "$output_mode" "$r_l  need\t$w_l zlib32  $r_l(not found)$re_\n"
			failed_libs+=("zlib32")
		fi
	fi

	# Cache successful finds
	printf "%s\n" "${found_libs[@]}" >"$lib_cache"

	# Return the number of failures as the exit code. 0 means success.
	return ${#failed_libs[@]}
}

sys_check_output() {
	# Centralized output control for system checks
	local mode="$1"
	shift
	local message="$*"

	case "$mode" in
	"verbose")
		printf "%s" "$message" >&2
		;;
	"silent")
		: # No output
		;;
	"summary")
		# Could collect for later summary output
		: # For now, same as silent
		;;
	*)
		printf "%s" "$message" >&2
		;;
	esac
}

# Parameters (all optional):
#   $1: installer name (or "auto")
#   $2: add architecture (not implemented yet)
#
# Example:
#   syscheck debian_os
#     call installer 'debian_os' (Do not care about the actual Linux distribution.)

syscheck() {
	[[ $1 ]] && [ "$1" != "auto" ] && override="$1"
	now=$2
	if [ -d "$osdir" ]; then
		cd "$osdir" || return 1
		x=(*)
		for i in "${x[@]}"; do
			source "$i"
		done
	fi

	unset binvars
	unset headervars
	unset libvars
	mapfile -t binvars < <(echo "${3:-dialog grep gawk wget tar bzip2 git bc xz upx patch gcc g++ make automake autoconf autoconf-archive libtool jq scp sshpass openssl dos2unix curl}" | tr ' ' '\n')
	mapfile -t headervars < <(echo "${4:-crypto.h libusb.h pcsclite.h pthread.h opensslconf.h dvbcsa.h}" | tr ' ' '\n')
	mapfile -t libvars < <(echo "${5:-libccidtwin.so}" | tr ' ' '\n')
	sanity=1

	if ! sys_run_check || [ "$now" == "now" ]; then
		clear
		s3logo
		# Rerun checks in verbose mode to show the user what is missing
		sys_check_binaries "verbose"
		sys_check_headers "verbose"
		sys_check_libraries "verbose"
		sanity=0
		rootuser="$(ps -jf 1 | tail -n 1 | awk '{print $1}')"
		if [ "$EUID" -ne 0 ]; then
			! hash "sudo" 2>/dev/null && prefix="su $rootuser -c" || prefix="sudo sh -c"
		else
			prefix="sh -c"
		fi
		installer="unknown"

		# Debian and Ubuntu
		[ -f /etc/debian_version ] && installer="debian_os"

		# CentOS and Redhat
		[ -f /etc/redhat-release ] && installer="redhat_os"

		# Manjaro (/etc/os-release)
		[ -f /etc/manjaro-release ] || [ -f /etc/arch-release ] && installer="manjaro_os"

		# SuSE (/etc/SuSE-release is depreciated -> check for YaST2)
		[ -d /etc/YaST2 ] && installer="suse_os"

		# Optional override via parameter
		#[[ $override ]] && installer=$override;
		printf '\n%s  Selected installer:    %s\n' "$w_l" "$P$installer"

		if type -t "$installer" >/dev/null; then
			$installer && sys_run_check && sanity=1
		else
			printf '\n%s  Needs manual installation.\n' "$r_l"
		fi

		printf '%s\n' "$re_"
	fi

	return $sanity
}

upx_native_installer() {
	echo -e "$w_l  Installing ${g_l}upx$w_l precompiled binary..." | _log "$install_log"
	case $(uname -m) in
	i386 | i686) HOST_ARCH="i386" ;;
	aarch64 | arm64) HOST_ARCH="arm64" ;;
	arm*) HOST_ARCH="arm" ;;
	*) HOST_ARCH="amd64" ;;
	esac
	rm -rf "/tmp/upx_$HOST_ARCH.tar.xz" 2>/dev/null
	UPX_TAG="$(git ls-remote --sort=-version:refname https://github.com/upx/upx.git --tags v*.*.* | grep -v '5.0.0\|alpha\|beta\|\-pre\|\-rc\|\^' | awk -F'/' 'NR==1 {print $NF}')"
	echo -e "$w_l  ${g_l}upx$w_l version:$y_l $UPX_TAG ($HOST_ARCH)" | _log "$install_log"
	UPX_URL="$(curl --silent "https://api.github.com/repos/upx/upx/releases/tags/$UPX_TAG" | jq -r '.assets | .[] | select( (.name | contains("-'$HOST_ARCH'_")) and (.name | endswith(".tar.xz"))) | .browser_download_url' | sed -e 's#\"##g')"
	echo -e "$w_l  Downloading ${g_l}upx$w_l from $UPX_URL..." | _log "$install_log"
	curl --silent -L --output "/tmp/upx_$HOST_ARCH.tar.xz" "$UPX_URL"
	echo -e "$w_l  Installing ${g_l}upx$w_l to /usr/local/bin...$re_" | _log "$install_log"
	[[ "$prefix" =~ ^su[[:space:]].* ]] && echo -en "$r_l\n  (upx installer) Enter $rootuser Password: "
	$prefix "
			(cd /usr/local/bin;
			 tar -xvf "/tmp/upx_$HOST_ARCH.tar.xz" \$(tar -tf "/tmp/upx_$HOST_ARCH.tar.xz" | grep 'upx$') --strip-components=1);
	" |& _log "$install_log" &>/dev/null
	[[ "$prefix" =~ ^su[[:space:]].* ]] && echo
	rm -rf "/tmp/upx_$HOST_ARCH.tar.xz" 2>/dev/null
}

libdvbcsa_native_installer() {
	echo -e "$w_l  Installing ${g_l}libdvbcsa$w_l from source..." | _log "$install_log"
	FLAGS="$(cat /proc/cpuinfo | grep -im1 flags | awk -F':' '{print $2}')"
	FLAGS+="$(cat /proc/cpuinfo | grep -im1 features | awk -F':' '{print $2}')"
	echo -e "FLAGS=\"$FLAGS\"\n" |& _log "$install_log" &>/dev/null

	echo "$FLAGS" | grep -qiw 'altivec' && optimization="--enable-altivec"
	[ -z "$optimization" ] && echo "$FLAGS" | grep -qiw "avx2" && optimization="--enable-avx2"
	[ -z "$optimization" ] && echo "$FLAGS" | grep -qiw "ssse3" && optimization="--enable-ssse3"
	[ -z "$optimization" ] && echo "$FLAGS" | grep -qiw "sse2" && optimization="--enable-sse2"
	[ -z "$optimization" ] && echo "$FLAGS" | grep -qiw "mmx" && optimization="--enable-mmx"
	if [ -z "$optimization" ]; then
		if [ -n "$(find "/usr/lib" -name "arm_neon.h" -type f -print -quit)" ]; then
			echo "$FLAGS" | grep -qiw "neon\|simd\|asimd" && optimization="--enable-neon"
		fi
	fi
	[ -z "$optimization" ] && optimization="--enable-uint32"
	echo -e "$w_l  ${g_l}libdvbcsa$w_l optimization autodetection:$y_l $optimization" | _log "$install_log"

	rm -rf /tmp/libdvbcsa 2>/dev/null
	echo -e "\ngit clone https://github.com/oe-mirrors/libdvbcsa.git /tmp/libdvbcsa" |& _log "$install_log" &>/dev/null
	git clone https://github.com/oe-mirrors/libdvbcsa.git /tmp/libdvbcsa |& _log "$install_log" &>/dev/null
	cd /tmp/libdvbcsa || return 1

	echo -e "$w_l  Building ${g_l}libdvbcsa$w_l..." | _log "$install_log"
	echo -e "\n./bootstrap && ./configure $optimization" |& _log "$install_log" &>/dev/null
	(./bootstrap && ./configure "$optimization") |& _log "$install_log" &>/dev/null
	if ! (./bootstrap && ./configure "$optimization") |& _log "$install_log" &>/dev/null; then
		return 1
	fi

	echo -e "\nmake -j$(sys_get_cpu_count)" |& _log "$install_log" &>/dev/null
	if ! make "-j$(sys_get_cpu_count)" |& _log "$install_log" &>/dev/null; then
		return 1
	fi

	echo -e "$w_l  Installing ${g_l}libdvbcsa$w_l...$re_" | _log "$install_log"
	echo -e "\n$prefix make install" |& _log "$install_log" &>/dev/null
	echo -e "\n$prefix \$(which ldconfig || printf '/sbin/ldconfig') && $prefix \$(which ldconfig || printf '/sbin/ldconfig') -v" |& _log "$install_log" &>/dev/null
	[[ "$prefix" =~ ^su[[:space:]].* ]] && echo -en "$r_l\n  (libdvbcsa installer) Enter $rootuser Password: "
	$prefix "
			make install || return 1;
			$(which ldconfig || printf '/sbin/ldconfig') && $(which ldconfig || printf '/sbin/ldconfig') -v;
	" |& _log "$install_log" &>/dev/null
	[[ "$prefix" =~ ^su[[:space:]].* ]] && echo
	rm -rf /tmp/libdvbcsa 2>/dev/null
}

sys_get_cpu_count() {
	nproc
}

# System prerequisite check function for main script (legacy name, to be renamed via migration)
sys_run_check() {
	# It is called from the main s3 script to silently check if all dependencies are met.
	local output_mode="silent"
	local total_failures=0

	sys_check_binaries "$output_mode"
	total_failures=$((total_failures + $?))

	sys_check_headers "$output_mode"
	total_failures=$((total_failures + $?))

	sys_check_libraries "$output_mode"
	total_failures=$((total_failures + $?))

	# Clean up caches created by the checks
	rm -f "/tmp/s3_"*"_cache_$BASHPID"

	return $total_failures
}
