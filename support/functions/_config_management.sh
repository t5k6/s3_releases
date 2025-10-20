#!/bin/bash
# =============================================================================
# SIMPLEBUILD3 - Unified Configuration Management
# =============================================================================
# Provides standardized loading, saving, and access for configuration files.
# Replaces scattered `source`, `read`, and `printf` logic.
# =============================================================================

# This global associative array should be declared in the main `s3` script.
# Example: declare -A S3_CONFIGS=()

cfg_load_file() {
	# Loads a key-value file into the global S3_CONFIGS cache.
	# Usage: cfg_load_file <namespace> <file_path> [export_vars]
	local namespace="$1"
	local config_file="$2"
	local export_vars="${3:-false}" # Optional third parameter to export as shell variables

	err_push_context "cfg_load_file:$namespace"

	if [[ ! -f "$config_file" ]]; then
		log_warn "Configuration file not found: $config_file"
		err_pop_context
		return 1
	fi

	log_debug "Loading config '$namespace' from: $config_file"

	while IFS= read -r line || [[ -n "$line" ]]; do
		# Skip comments, empty lines, and lines without an equals sign
		if [[ "$line" =~ ^#.*$ || -z "$line" || ! "$line" == *"="* ]]; then
			continue
		fi

		# Safely split key and value
		key="${line%%=*}"
		value="${line#*=}"

		# Sanitize key
		key=$(echo "$key" | awk '{$1=$1};1') # Trim whitespace

		# Sanitize value: Trim whitespace, then remove an optional trailing semicolon,
		# then remove surrounding quotes. This is more robust for legacy .cfg files.
		value="${value#"${value%%[![:space:]]*}"}" # Trim leading whitespace
		value="${value%"${value##*[![:space:]]}"}" # Trim trailing whitespace
		if [[ "${value: -1}" == ';' ]]; then
			value="${value:0:${#value}-1}"
		fi
		if [[ "${value:0:1}" == '"' && "${value: -1}" == '"' ]]; then
			value="${value:1:${#value}-2}"
		fi

		S3_CONFIGS["${namespace}:${key}"]="$value"

		# If requested, export the key as a variable in the current shell's scope
		if [[ "$export_vars" == "true" ]]; then
			# Ensure the key is a valid shell identifier before exporting
			if [[ "$key" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
				export "$key=$value"
			else
				log_debug "Skipped export of invalid identifier: '$key' from $config_file"
			fi
		fi
	done <"$config_file"

	log_debug "Loaded ${namespace} config."
	err_pop_context
	return 0
}

cfg_save_file() {
	# Saves a configuration namespace from the cache to a file.
	# Usage: cfg_save_file <namespace> <file_path>
	local namespace="$1"
	local output_file="$2"

	err_push_context "cfg_save_file:$namespace"

	# Create directory if it doesn't exist
	mkdir -p "$(dirname "$output_file")"

	{
		echo "# SimpleBuild3 Configuration: ${namespace}"
		echo "# Auto-generated on: $(date)"
		echo ""

		# Sort keys for consistent output
		for cache_key in $(echo "${!S3_CONFIGS[@]}" | tr ' ' '\n' | sort); do
			if [[ "$cache_key" == "${namespace}:"* ]]; then
				local key="${cache_key#${namespace}:}"
				printf '%s="%s"\n' "$key" "${S3_CONFIGS[$cache_key]}"
			fi
		done
	} >"$output_file"

	if [[ $? -ne 0 ]]; then
		log_error "Failed to save configuration to $output_file"
		err_pop_context
		return 1
	fi

	log_debug "Configuration '$namespace' saved to: $output_file"
	err_pop_context
}

cfg_get_value() {
	# Gets a configuration value from the cache, with a fallback default.
	# Usage: local my_var=$(cfg_get_value <namespace> <key> [default_value])
	local namespace="$1"
	local key="$2"
	local default_value="${3:-}"
	local cache_key="${namespace}:${key}"

	if [[ -v S3_CONFIGS[$cache_key] ]]; then
		echo "${S3_CONFIGS[$cache_key]}"
	else
		echo "$default_value"
	fi
}

cfg_set_value() {
	# Sets a configuration value in the cache.
	# Usage: cfg_set_value <namespace> <key> <value>
	local namespace="$1"
	local key="$2"
	local value="$3"

	S3_CONFIGS["${namespace}:${key}"]="$value"
	log_debug "Set config [${namespace}:${key}] = ${value}"
}
