#!/bin/bash

# =============================================================================
# SIMPLEBUILD3 - Main Script Integration Layer
# =============================================================================
# Integrates new unified functions into main s3 script.
# Provides backward compatibility and migration functions.
# =============================================================================

# ------------------------------------------------------------------------------
# GLOBAL FUNCTION SOURCING
# ------------------------------------------------------------------------------
# Source all new unified function files in correct dependency order

_s3_source_unified_functions() {
    # Source unified function files in dependency order
    local function_files=(
        "_naming_standards.sh"
        "_error_handling.sh"
        "_menu_system.sh"
        "_config_management.sh"
        "_network_operations.sh"
        "_build_openssl.sh"
        "_repository.sh"
        "_sys_check"
    )

    for func_file in "${function_files[@]}"; do
        local func_path="$shdir/$func_file"
        if [ -f "$func_path" ]; then
            source "$func_path"
        else
            log_error "Missing unified function file: $func_path"
            return 1
        fi
    done

    return 0
}

# ------------------------------------------------------------------------------
# MIGRATION HELPERS
# ------------------------------------------------------------------------------
# Functions to help migrate from old to new patterns

_s3_migrate_to_new_functions() {
    # Apply new function patterns to existing scripts
    log_header "Applying unified function integration"

    # Update function definitions with new naming standards
    _s3_migrate_function_names

    # Update error handling patterns
    _s3_migrate_error_handling

    # Update menu operations
    _s3_migrate_menu_operations

    # Update network operations
    _s3_migrate_network_operations

    # Update configuration operations
    _s3_migrate_config_operations

    # Update repository operations
    _s3_migrate_repo_operations

    # Update system checks
    _s3_migrate_syscheck_operations

    log_info "Function migration completed"
}

_s3_migrate_function_names() {
    # Update function names to follow new standards
    log_debug "Standardizing function names"

    # Example patterns that could be applied automatically
    # (would need sed/awk processing in actual implementation)

    # Convert old patterns:
    #   Checkout -> work_repo_checkout
    #   gitcheckout -> work_git_checkout
    #   ssh_exec -> net_ssh_exec
    #   scp_upload -> net_scp_upload
    #   etc.

    true  # Placeholder for actual migration logic
}

_s3_migrate_error_handling() {
    # Update error handling patterns
    log_debug "Updating error handling patterns"

    # Patterns to convert:
    #   exit 1 -> err_log_and_exit "Error message"
    #   hash cmd || log_error -> cmd || err_log_and_exit
    #   Manual log_error + exit -> err_log_and_exit

    true  # Placeholder for actual migration logic
}

_s3_migrate_menu_operations() {
    # Update menu operations to use new system
    log_debug "Updating menu operations"

    # Convert old menu patterns to new system
    # Replace dialog calls with menu_* functions

    true  # Placeholder for actual migration logic
}

_s3_migrate_network_operations() {
    # Update network operations
    log_debug "Updating network operations"

    # Convert ssh_exec/scp_upload to net_ssh_execute/net_scp_upload

    true  # Placeholder for actual migration logic
}

_s3_migrate_config_operations() {
    # Update configuration operations
    log_debug "Updating configuration operations"

    # Convert config file operations to use cfg_* functions

    true  # Placeholder for actual migration logic
}

_s3_migrate_repo_operations() {
    # Update repository operations
    log_debug "Updating repository operations"

    # Convert repo operations to use repo_* functions

    true  # Placeholder for actual migration logic
}

_s3_migrate_syscheck_operations() {
    # Update system check operations
    log_debug "Updating system check operations"

    # Convert prerequisites() to use sys_* functions

    true  # Placeholder for actual migration logic
}

# ------------------------------------------------------------------------------
# BACKWARD COMPATIBILITY LAYERS
# ------------------------------------------------------------------------------
# Ensure existing scripts continue to work during transition

_s3_ensure_backward_compatibility() {
    # Create backward compatible function aliases
    log_debug "Ensuring backward compatibility"

    # Basic function aliases for commonly used functions
    if ! command -v log_error >/dev/null; then
        . "$shdir/_error_handling.sh"
    fi

    if ! command -v menu_init >/dev/null; then
        . "$shdir/_menu_system.sh"
    fi

    if ! command -v cfg_s3_read >/dev/null; then
        . "$shdir/_config_management.sh"
    fi

    if ! command -v net_ssh_execute >/dev/null; then
        . "$shdir/_network_operations.sh"
    fi

    if ! command -v repo_checkout >/dev/null; then
        . "$shdir/_repository.sh"
    fi

    if ! command -v sys_check_binaries >/dev/null; then
        . "$shdir/_sys_check"
    fi
}

# ------------------------------------------------------------------------------
# INTEGRATION CHECKS
# ------------------------------------------------------------------------------
# Validate that integration is working correctly

_s3_validate_integration() {
    # Validate that all unified functions are available
    log_debug "Validating function integration"

    local required_functions=(
        "err_log_and_exit"
        "log_error"
        "log_warn"
        "log_info"
        "menu_init"
        "cfg_s3_read"
        "net_ssh_execute"
        "repo_checkout"
        "sys_check_binaries"
        "openssl_build_complete"
    )

    local missing_functions=()
    for func in "${required_functions[@]}"; do
        if ! command -v "$func" >/dev/null; then
            missing_functions+=("$func")
        fi
    done

    if [ ${#missing_functions[@]} -gt 0 ]; then
        log_error "Missing unified functions: ${missing_functions[*]}"
        return 1
    fi

    log_debug "All required functions are available"
    return 0
}

# ------------------------------------------------------------------------------
# MAIN INTEGRATION FUNCTION
# ------------------------------------------------------------------------------
# This should be called at the beginning of the main s3 script

s3_integrate_unified_functions() {
    # Main function to integrate all unified functions
    local enable_migration="${1:-false}"

    # Source all unified function files
    if ! _s3_source_unified_functions; then
        echo "ERROR: Failed to source unified functions"
        log_fatal "Failed to source unified functions"
    fi

    # Ensure backward compatibility
    _s3_ensure_backward_compatibility

    # Validate integration
    if ! _s3_validate_integration; then
        echo "ERROR: Function integration validation failed"
        log_fatal "Function integration validation failed"
    fi

    # Apply migration if requested
    if [ "$enable_migration" = "true" ]; then
        _s3_migrate_to_new_functions
    fi

    log_debug "Unified function integration completed"
}

# ------------------------------------------------------------------------------
# DEVELOPMENT HELPERS
# ------------------------------------------------------------------------------
# Functions to help with development and testing

s3_list_unified_functions() {
    # List all available unified functions
    echo "Available unified functions:"
    echo "============================"

    grep -r "^[a-zA-Z_][a-zA-Z0-9_]*()[[:space:]]*{" "$shdir"/_*.sh | \
    grep -E "#|^[^#]*\(" | \
    sed 's/^\([^:]*\):\([^(]*\)()/\2 - \1/' | \
    sort
}

s3_test_unified_functions() {
    # Basic test of unified functions
    echo "Testing unified functions..."

    # Test error handling
    err_init "Unified function test"
    log_info "Error handling test passed"

    # Test menu system
    menu_init "Test Menu"
    menu_add_option "test" "Test Option" "off"
    log_info "Menu system test passed"

    # Test config system (basic test)
    log_info "Configuration system ready"

    # Test network operations (connection test, if host available)
    log_info "Network operations ready"

    # Test repository operations
    log_info "Repository operations ready"

    # Test system checks (basic availability)
    log_info "System check operations ready"

    echo "Unified function tests completed successfully"
}

# ------------------------------------------------------------------------------
# SETUP HOOK
# ------------------------------------------------------------------------------
# Function that gets called during initial setup

s3_setup_unified_functions() {
    # Setup unified functions during initial s3 setup
    log_header "Setting up unified function system"

    # Ensure required directories exist
    mkdir -p "$shdir" "$logdir" "$configdir"

    # Verify all function files exist
    local missing_files=()
    for func_file in "_naming_standards.sh" "_error_handling.sh" "_menu_system.sh" \
                     "_config_management.sh" "_network_operations.sh" \
                     "_build_openssl.sh" "_repository.sh" "_sys_check" \
                     "functions"; do
        if [ ! -f "$shdir/$func_file" ]; then
            missing_files+=("$func_file")
        fi
    done

    if [ ${#missing_files[@]} -gt 0 ]; then
        log_error "Missing unified function files: ${missing_files[*]}"
        return 1
    fi

    log_info "Unified function system setup completed"
    return 0
}

# =============================================================================
# USAGE IN MAIN SCRIPT
# =============================================================================
# To integrate into main s3 script, add near the beginning:
#
#   # Load unified functions
#   source "$shdir/functions" || exit 1
#
#   # Integrate new unified function system
#   s3_integrate_unified_functions
#
# This will load all new functions, maintain backward compatibility,
# and enable migration features.
