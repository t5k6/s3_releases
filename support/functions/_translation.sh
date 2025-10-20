#!/bin/bash

# =============================================================================
# lang_load_file: Securely parse language files into UCM 'lang' namespace
# =============================================================================
lang_load_file() {
	local lang_file="$1"
	err_push_context "Loading language file: $lang_file"

	if [[ ! -f "$lang_file" ]]; then
		log_error "Language file does not exist: $lang_file"
		err_pop_context
		return 1
	fi

	# Parse: key=value, ignore comments/empty lines
	local line key value
	while IFS='=' read -r key value; do
		# Trim whitespace and skip comments/empty
		key="${key%%\#*}" key="${key#"${key%%[![:space:]]*}"}" key="${key%"${key##*[![:space:]]}"}"
		value="${value%%\#*}" value="${value#"${value%%[![:space:]]*}"}" value="${value%"${value##*[![:space:]]}"}"
		[[ -z "$key" || "$key" =~ ^# ]] && continue

		# Handle quoted values for multi-line support (simple expansion)
		if [[ "$value" =~ ^\".*\"$ ]]; then
			value="${value#\"}" value="${value%\"}"
		fi

		cfg_set_value "lang" "$key" "$value"

		# Backward compatibility: Set global variables for existing code with variable expansion
		if [[ "$key" =~ ^txt_ ]]; then
			eval "declare -g $key=\"$value\""
		fi
	done <"$lang_file"

	log_debug "Language strings from '$lang_file' loaded into UCM 'lang' namespace."
	err_pop_context
}

sys_language_apply() {
	cd "$tdir" || return 1
	langsupport=(*)

	# Always load English as the base fallback. This is robust.
	if [[ -f "$tdir/en" ]]; then
		lang_load_file "$tdir/en"
	else
		log_error "Default English language file 'en' not found. UI text will be missing."
	fi

	# Determine the language to apply (forced or auto-detected).
	local target_lang=""
	local forced_lang=""
	forced_lang=$(cfg_get_value "s3" "S3_FORCED_LANG")

	if [[ -n "$forced_lang" ]]; then
		target_lang="$forced_lang"
		log_debug "Attempting to apply forced language: '$target_lang'"
	else
		target_lang="${LANG:0:2}"
		log_debug "Attempting to apply auto-detected language: '$target_lang'"
	fi

	# If the target language is not English and the file exists, load it.
	# This will overwrite the English defaults with the translated strings.
	if [[ -n "$target_lang" && "$target_lang" != "en" ]]; then
		local found=false
		for lng in "${langsupport[@]}"; do
			if [[ "$lng" == "$target_lang" ]]; then
				lang_load_file "$tdir/$lng"
				log_info "Language set to '$lng'."
				found=true
				break
			fi
		done
		if ! $found && [[ -n "$forced_lang" ]]; then
			log_warn "Forced language '$forced_lang' not found. Using English fallback."
		fi
	else
		log_debug "Language is English, no overrides needed."
	fi
}

ui_menu_language_select() {
	# Abstraction: Get current settings from UCM.
	local forced_lang
	forced_lang=$(cfg_get_value "s3" "S3_FORCED_LANG")
	local system_lang="${LANG:0:2}"

	menu_init "Language Selection" "Language Selection"

	for e in "${langsupport[@]}"; do
		local state="off"
		if [[ -n "$forced_lang" ]]; then
			# If a language is forced, that one is 'on'
			[[ "$forced_lang" == "$e" ]] && state="on"
		else
			# Otherwise, the auto-detected system language is 'on'
			[[ "$system_lang" == "$e" ]] && state="on"
		fi

		# Securely load the language file into a temporary namespace to read its description.
		# This avoids fragile text parsing by using the robust UCM API.
		local lang_ns="lang_desc:$e"
		cfg_load_file "$lang_ns" "$tdir/$e"
		local txt
		txt=$(cfg_get_value "$lang_ns" "txt_menu_langdesc" "$e") # Use language code as fallback
		menu_add_option "$e" "$txt" "$state"
	done

	if menu_show_radiolist "18" "40"; then
		local selected_lang
		selected_lang="$(menu_get_first_selection)"

		# Abstraction: Save selection to UCM instead of a file.
		if [[ "$system_lang" == "$selected_lang" ]]; then
			# If user selects the system default, clear the override.
			log_info "Reverting to system default language ($system_lang)."
			cfg_set_value "s3" "S3_FORCED_LANG" ""
		else
			log_info "Forcing language to '$selected_lang'."
			cfg_set_value "s3" "S3_FORCED_LANG" "$selected_lang"
		fi
		# Load the selected language securely via UCM
		lang_load_file "$tdir/$selected_lang"

		# Robustness: Always save the main config after making a change.
		if ! validate_command "Saving configuration" cfg_save_file "s3" "$s3cfg"; then
			ui_show_msgbox "Error" "Failed to save language setting."
		fi
	fi
}
