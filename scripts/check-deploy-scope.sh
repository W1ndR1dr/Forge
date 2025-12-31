#!/bin/bash
# Helper script to determine which platforms need deployment
# Used by both deploy-to-testflight.sh and release-macos.sh

FORGE_DIR="/Users/Brian/Projects/Active/Forge"
APP_DIR="$FORGE_DIR/ForgeApp"

# Get the last release tags
LAST_IOS_TAG=$(git tag -l "ios-*" --sort=-v:refname | head -1)
LAST_MACOS_TAG=$(git tag -l "v*" --sort=-v:refname | head -1)

# Determine which files changed since last deploy
get_changed_files() {
    local since_tag="$1"
    if [ -n "$since_tag" ]; then
        git diff --name-only "$since_tag"..HEAD -- ForgeApp/
    else
        git diff --name-only HEAD~10..HEAD -- ForgeApp/
    fi
}

# Check if changes affect a specific platform
check_platform_changes() {
    local changed_files="$1"
    local platform="$2"  # "ios" or "macos"

    # Shared directories (affect both platforms)
    local shared_patterns="Models/|Services/|Shared/|Design/|Views/"

    # Platform-specific directories
    local ios_only="App-iOS/"
    local macos_only="App/"

    local has_shared=$(echo "$changed_files" | grep -E "$shared_patterns" | head -1)
    local has_ios_only=$(echo "$changed_files" | grep -E "$ios_only" | head -1)
    local has_macos_only=$(echo "$changed_files" | grep -E "$macos_only" | grep -v "App-iOS" | head -1)

    if [ "$platform" = "ios" ]; then
        # iOS needs deploy if: shared code changed OR iOS-specific code changed
        if [ -n "$has_shared" ] || [ -n "$has_ios_only" ]; then
            echo "yes"
        else
            echo "no"
        fi
    elif [ "$platform" = "macos" ]; then
        # macOS needs deploy if: shared code changed OR macOS-specific code changed
        if [ -n "$has_shared" ] || [ -n "$has_macos_only" ]; then
            echo "yes"
        else
            echo "no"
        fi
    fi
}

# Main check function - call with current platform to see if other needs deploy
check_companion_deploy() {
    local current_platform="$1"  # "ios" or "macos"
    local changed_files=$(get_changed_files "")

    if [ "$current_platform" = "ios" ]; then
        # We just deployed iOS, check if macOS also needs it
        local macos_needed=$(check_platform_changes "$changed_files" "macos")
        if [ "$macos_needed" = "yes" ]; then
            echo "macos"
        fi
    elif [ "$current_platform" = "macos" ]; then
        # We just deployed macOS, check if iOS also needs it
        local ios_needed=$(check_platform_changes "$changed_files" "ios")
        if [ "$ios_needed" = "yes" ]; then
            echo "ios"
        fi
    fi
}

# If called directly, show status
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    echo "📱 Deployment Scope Check"
    echo "========================="

    changed=$(get_changed_files "")

    echo ""
    echo "Changed files in ForgeApp/:"
    echo "$changed" | head -20

    echo ""
    ios_needed=$(check_platform_changes "$changed" "ios")
    macos_needed=$(check_platform_changes "$changed" "macos")

    echo "iOS deploy needed: $ios_needed"
    echo "macOS deploy needed: $macos_needed"
fi
