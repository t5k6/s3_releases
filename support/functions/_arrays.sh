#!/bin/bash

_fill_tc_array() {
	unset AVAI_TCLIST
	unset INST_TCLIST
	tcempty=0

	cd "$tccfgdir"
	if [ "$(ls -A "$tccfgdir")" ]; then
		AVAI_TCLIST=(*)
	else
		printf "\n error in _fill_tc_array()\n please report error\n\n"
		exit
	fi

	cd "$tcdir"
	if [ "$(ls -A "$tcdir")" ]; then
		tmp_tclist=(*)
		for t in "${tmp_tclist[@]}"; do
			for a in "${AVAI_TCLIST[@]}"; do
				[ "$t" == "$a" ] && INST_TCLIST+=($t)
			done
		done
	else
		tcempty=1
	fi

	if [ "$tcempty" == "1" ]; then
		MISS_TCLIST=$(echo ${AVAI_TCLIST[@]} | sort)
	else
		MISS_TCLIST=(
			$(for el in $(diff_array AVAI_TCLIST[@] INST_TCLIST[@]); do
				echo "$el"
			done | sort)
		)
	fi
}

_create_module_arrays() {
	# Clear arrays to ensure a clean state on re-runs
	SHORT_ADDONS=() SHORT_PROTOCOLS=() SHORT_READERS=() SHORT_CARD_READERS=()
	SHORT_MODULENAMES=() ALL_MODULES_LONG=()
	declare -gA INTERNAL_MODULES=()

	# Process Addons
	for long_name in $addons; do
		short_name=$(echo "$long_name" | sed 's/WEBIF_//g;s/WITH_//g;s/MODULE_//g;s/CS_//g;s/HAVE_//g;s/_CHARSETS//g;s/CW_CYCLE_CHECK/CWCC/g;s/SUPPORT//g')
		SHORT_ADDONS+=("$short_name")
		SHORT_MODULENAMES+=("$short_name")
		ALL_MODULES_LONG+=("$long_name")
		INTERNAL_MODULES["$short_name"]="$long_name"
	done

	# Process Protocols
	for long_name in $protocols; do
		short_name=${long_name#MODULE_}
		SHORT_PROTOCOLS+=("$short_name")
		SHORT_MODULENAMES+=("$short_name")
		ALL_MODULES_LONG+=("$long_name")
		INTERNAL_MODULES["$short_name"]="$long_name"
	done

	# Process Readers
	for long_name in $readers; do
		short_name=${long_name#READER_}
		SHORT_READERS+=("$short_name")
		SHORT_MODULENAMES+=("$short_name")
		ALL_MODULES_LONG+=("$long_name")
		INTERNAL_MODULES["$short_name"]="$long_name"
	done

	# Process Card Readers
	for long_name in $card_readers; do
		short_name=${long_name#CARDREADER_}
		SHORT_CARD_READERS+=("$short_name")
		SHORT_MODULENAMES+=("$short_name")
		ALL_MODULES_LONG+=("$long_name")
		INTERNAL_MODULES["$short_name"]="$long_name"
	done
}

diff_array() {
	awk 'BEGIN{RS=ORS=" "}{NR==FNR?a[$0]++:a[$0]--}END{for(k in a)if(a[k])print k}' <(echo -n "${!1}") <(echo -n "${!2}")
}
