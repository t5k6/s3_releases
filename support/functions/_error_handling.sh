#!/bin/bash

# =============================================================================
# SIMPLEBUILD3 - Centralized Error Handling System
# =============================================================================
# Provides consistent error handling, logging, and cleanup across all functions.
# All existing functions should be updated to use these patterns.
# =============================================================================

# Exit codes
EXIT_SUCCESS=0
EXIT_ERROR=1
EXIT_PERMISSION=2
EXIT_NETWORK=3
EXIT_MISSING=4
EXIT_INVALID_CONFIG=5

# Error context stack
ERROR_CONTEXT_STACK=()

# ------------------------------------------------------------------------------
# UNIFIED ERROR HANDLING API
# ------------------------------------------------------------------------------

# Global error state
ERR_LAST_COMMAND=""
ERR_LAST_EXIT_CODE=0
ERR_START_TIME=""
ERR_CURRENT_OPERATION=""

# ------------------------------------------------------------------------------
# ERROR HANDLING FUNCTIONS
# ------------------------------------------------------------------------------

err_init() {
    # Initialize error tracking for current operation
    ERR_CURRENT_OPERATION="${1:-Unknown operation}"
    ERR_START_TIME=$(date +%s)
    ERR_LAST_EXIT_CODE=0
}

err_set_exit_code() {
    # Set and track exit code
    ERR_LAST_EXIT_CODE="${1:-$?}"
    ERR_LAST_COMMAND="${2:-$BASH_COMMAND}"
}

log_fatal() {
    # Log a fatal error and exit
    local message="$1"
    local exit_code="${2:-$EXIT_ERROR}"

    log_error "FATAL: $message"
    err_cleanup
    exit "$exit_code"
}

err_check_command_result() {
    # Check result of last command and handle errors
    local exit_code=$?
    local operation="${1:-Command failed}"

    if [ "$exit_code" -ne 0 ]; then
        ERR_LAST_EXIT_CODE="$exit_code"
        ERR_LAST_COMMAND="$operation"
        return "$exit_code"
    fi
    return 0
}

err_cleanup() {
    # Perform cleanup operations
    local end_time=$(date +%s)
    local duration=$(( end_time - ERR_START_TIME ))

    log_debug "Operation '$ERR_CURRENT_OPERATION' completed in ${duration}s with exit code $ERR_LAST_EXIT_CODE"

    # Remove temporary files starting with our prefixes
    _cleanup_temp_files
}

err_exception_handler() {
    # Trap handler for unexpected errors
    local line="${1:-Unknown line}"
    local command="$2"

    log_error "Unexpected error at line $line: $command"
    err_cleanup
}

err_validate_required_var() {
    # Validate that required variables are set
    local var_name="$1"
    local var_value=""

    eval "var_value=\"\$$var_name\""

    if [ -z "$var_value" ]; then
        err_log_and_exit "Required variable '$var_name' is not set" "$EXIT_INVALID_CONFIG"
    fi
}

err_validate_file_exists() {
    # Validate file exists
    local filepath="$1"
    local context="${2:-File validation}"

    if [ ! -f "$filepath" ]; then
        err_log_and_exit "$context: File '$filepath' does not exist" "$EXIT_MISSING"
    fi

    if [ ! -r "$filepath" ]; then
        err_log_and_exit "$context: File '$filepath' is not readable" "$EXIT_PERMISSION"
    fi
}

err_validate_directory_exists() {
    # Validate directory exists
    local dirpath="$1"
    local context="${2:-Directory validation}"

    if [ ! -d "$dirpath" ]; then
        err_log_and_exit "$context: Directory '$dirpath' does not exist" "$EXIT_MISSING"
    fi

    if [ ! -r "$dirpath" ] || [ ! -x "$dirpath" ]; then
        err_log_and_exit "$context: Directory '$dirpath' is not accessible" "$EXIT_PERMISSION"
    fi
}

err_validate_network_connectivity() {
    # Validate network connectivity
    local url="$1"
    local timeout="${2:-10}"

    if ! curl --head --silent --connect-timeout "$timeout" "$url" >/dev/null 2>&1; then
        err_log_and_exit "Network connectivity check failed for URL: $url" "$EXIT_NETWORK"
    fi
}

# ------------------------------------------------------------------------------
# CLEANUP FUNCTIONS
# ------------------------------------------------------------------------------

_cleanup_temp_files() {
    # Clean up temporary files created by this script
    local temp_patterns=("*.tmp" "*.temp" "*$$*.tmp")
    local find_patterns=""

    # Build find pattern
    for pattern in "${temp_patterns[@]}"; do
        find_patterns="${find_patterns}${pattern}|"
    done
    find_patterns="${find_patterns%|}"

    # Clean temp files in standard directories
    for dir in "/tmp" "$workdir" "$ldir"; do
        if [ -d "$dir" ]; then
            find "$dir" -name "s3_tmp_*" -type f -mtime +1 -delete 2>/dev/null || true
        fi
    done
}

# ------------------------------------------------------------------------------
# UNIFIED ERROR HANDLING FUNCTIONS
# ------------------------------------------------------------------------------

err_push_context() {
    # Push a new error context onto the stack
    ERROR_CONTEXT_STACK+=("$1")
}

err_pop_context() {
    # Pop the last error context from the stack
    if [ ${#ERROR_CONTEXT_STACK[@]} -gt 0 ]; then
        unset ERROR_CONTEXT_STACK[-1]
    fi
}

err_log_and_exit() {
    # Log a fatal error and exit
    local message="$1"
    local exit_code="${2:-$EXIT_ERROR}"

    log_error "FATAL: $message"
    err_cleanup
    exit "$exit_code"
}


validate_command() {
    # Validate command execution and log errors
    local command_description="$1"
    shift

    if ! "$@"; then
        log_error "$command_description failed"
        return 1
    fi
    return 0
}

err_setup() {
    # Initialize the error handling system
    ERROR_CONTEXT_STACK=()

    # Set up global traps
    trap 'err_exception_handler "$LINENO" "$BASH_COMMAND"' ERR
    trap 'err_cleanup' EXIT

    log_debug "Error handling system initialized"
}

# ------------------------------------------------------------------------------
# TRAP SETUP
# ------------------------------------------------------------------------------

err_setup_traps() {
    # Set up trap handlers for current function
    trap 'err_exception_handler "$LINENO" "$BASH_COMMAND"' ERR
    trap 'err_cleanup' EXIT
}

# ------------------------------------------------------------------------------
# LOGGING FUNCTIONS
# ------------------------------------------------------------------------------
# Define log levels
LOG_LEVEL_FATAL=0
LOG_LEVEL_ERROR=1
LOG_LEVEL_WARN=2
LOG_LEVEL_INFO=3
LOG_LEVEL_DEBUG=4

log_error() {
    local message="$@"
    printf "$r_l ERROR: $message$re_\n" >&2

    # Also log to file if available
    if [ -w "$ldir" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: $message" >> "$ldir/error.log"
    fi
}

log_warn() {
    (( S3_LOG_LEVEL < LOG_LEVEL_WARN )) && return
    local message="$@"
    printf "$y_l WARNING: $message$re_\n"
}

log_info() {
    (( S3_LOG_LEVEL < LOG_LEVEL_INFO )) && return
    local message="$@"
    printf "$g_l INFO: $message$re_\n"
}

log_header() {
    local message="$1"
    local mode="${2:-verbose}"
    # Respect quiet/silent mode to avoid interfering with command capture
    if [ "$mode" != "silent" ] && [ "${S3_OUTPUT_MODE:-}" != "silent" ]; then
        printf "%s" "$b_l\n=== $message ===$w_l\n" >&2
    fi
}

log_debug() {
    (( S3_LOG_LEVEL < LOG_LEVEL_DEBUG )) && return
    local message="$@"
    printf "$c_l DEBUG: $message$re_\n"
}

# ------------------------------------------------------------------------------
# LOG FILE MANAGEMENT
# ------------------------------------------------------------------------------

# Executed a command while capturing all output to a log file.
# Usage: run_with_logging "/path/to/logfile.log" command arg1 arg2 ...
run_with_logging() {
    local log_file="$1"
    shift
    # Ensure the logs directory exists
    mkdir -p "$(dirname "$log_file")"
    # Execute the command, teeing stdout and stderr to the log file.
    # The sed command strips ANSI color codes from the file output.
    { "$@" ; } 2>&1 | tee >(sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g" >> "$log_file")
}
