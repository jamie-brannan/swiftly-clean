#!/usr/bin/env bash
# swiftly-clean — deep-cleans Xcode/SPM build state after local package changes
# Usage:
#   swiftly-clean
#   swiftly-clean --force
#   swiftly-clean --deep
#   swiftly-clean --force --deep
#
# Run from the root of the project/package you want to clean.
#
# --force  skips all confirmation prompts, quits Xcode automatically,
#          and (when CocoaPods is detected) reinstalls pods without prompting.
# --deep   additionally removes ~/Library/org.swift.swiftpm (full SwiftPM state)
#          and Podfile.lock (if a Podfile is present).
#
# Normal clean removes:
#   - all Xcode DerivedData (~/Library/Developer/Xcode/DerivedData)
#   - SwiftPM global cache (~/Library/Caches/org.swift.swiftpm)
#   - SwiftPM security fingerprints (~/Library/org.swift.swiftpm/security)
#   - local .build for the current directory
#   - local Pods/ directory (if a Podfile is present)
#   - CocoaPods global cache (~/Library/Caches/CocoaPods)
#
# Deep clean additionally removes:
#   - full SwiftPM user state at ~/Library/org.swift.swiftpm
#   - Podfile.lock (if a Podfile is present)

set -euo pipefail

# MARK: - Colors

BOLD="\033[1m"
DIM="\033[2m"
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
BLUE="\033[0;34m"
CYAN="\033[0;36m"
RESET="\033[0m"

# MARK: - Paths

DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData"
SPM_CACHE="$HOME/Library/Caches/org.swift.swiftpm"
SPM_FINGERPRINTS="$HOME/Library/org.swift.swiftpm/security"
SPM_USER_STATE="$HOME/Library/org.swift.swiftpm"
LOCAL_BUILD="$PWD/.build"

PODS_DIR="$PWD/Pods"
PODS_CACHE="$HOME/Library/Caches/CocoaPods"
PODFILE="$PWD/Podfile"
PODFILE_LOCK="$PWD/Podfile.lock"
GEMFILE="$PWD/Gemfile"

FORCE=false
DEEP=false

for arg in "$@"; do
    case "$arg" in
        --force)
            FORCE=true
            ;;
        --deep)
            DEEP=true
            ;;
        *)
            echo -e "${RED}✗ Unknown option:${RESET} $arg"
            echo -e "${DIM}Usage: swiftly-clean [--force] [--deep]${RESET}"
            exit 1
            ;;
    esac
done

# MARK: - Safety guard

# Refuse to run if $HOME is empty or resolves to root, which would make our
# Library-relative paths catastrophically broad.
safe_rm_rf() {
    local target="$1"

    # Must be non-empty
    if [[ -z "$target" ]]; then
        echo -e "${RED}✗ Refusing to delete: path is empty.${RESET}"
        exit 1
    fi

    # Must not be / or $HOME
    local real_target
    real_target="$(cd "$target" 2>/dev/null && pwd -P || true)"
    if [[ "$real_target" == "/" || "$real_target" == "$HOME" ]]; then
        echo -e "${RED}✗ Refusing to delete: path resolves to ${real_target}.${RESET}"
        exit 1
    fi

    # Must live under $HOME/Library or be a known local project path
    local home_library="$HOME/Library"
    if [[ "$target" != "$home_library"* && \
          "$target" != "$PWD/.build" && \
          "$target" != "$PWD/Pods" && \
          "$target" != "$PWD/Podfile.lock" ]]; then
        echo -e "${RED}✗ Refusing to delete: path is outside expected locations (${target}).${RESET}"
        exit 1
    fi

    rm -rf "$target"
}

echo ""
echo -e "${BOLD}${BLUE}🧹 swiftly-clean${RESET}"
echo -e "${DIM}Deep-cleans Xcode and SwiftPM build state.${RESET}"
echo ""

# MARK: - CocoaPods detection

HAS_PODS=false
USE_BUNDLER=false

if [ -f "$PODFILE" ]; then
    HAS_PODS=true
    if [ -f "$GEMFILE" ]; then
        USE_BUNDLER=true
    fi
fi

if $HAS_PODS; then
    if $USE_BUNDLER; then
        echo -e "${DIM}CocoaPods project detected (Bundler present — will use \`bundle exec pod install\`).${RESET}"
    else
        echo -e "${DIM}CocoaPods project detected.${RESET}"
    fi
    echo ""
fi

echo -e "${BOLD}${YELLOW}This will remove:${RESET}"
echo -e "  ${YELLOW}•${RESET} All Xcode DerivedData         ${DIM}($DERIVED_DATA)${RESET}"
echo -e "  ${YELLOW}•${RESET} SwiftPM global cache          ${DIM}($SPM_CACHE)${RESET}"

if $DEEP; then
    echo -e "  ${RED}•${RESET} SwiftPM user state ${BOLD}(full)${RESET}  ${DIM}($SPM_USER_STATE)${RESET}"
else
    echo -e "  ${YELLOW}•${RESET} SwiftPM security fingerprints ${DIM}($SPM_FINGERPRINTS)${RESET}"
fi

if [ -d "$LOCAL_BUILD" ]; then
    echo -e "  ${YELLOW}•${RESET} Local .build                  ${DIM}($LOCAL_BUILD)${RESET}"
fi

if $HAS_PODS; then
    if [ -d "$PODS_DIR" ]; then
        echo -e "  ${YELLOW}•${RESET} CocoaPods Pods directory      ${DIM}($PODS_DIR)${RESET}"
    fi
    echo -e "  ${YELLOW}•${RESET} CocoaPods global cache        ${DIM}($PODS_CACHE)${RESET}"
    if $DEEP; then
        if [ -f "$PODFILE_LOCK" ]; then
            echo -e "  ${RED}•${RESET} Podfile.lock ${BOLD}(deep)${RESET}          ${DIM}($PODFILE_LOCK)${RESET}"
        fi
    fi
fi

echo ""

if ! $FORCE; then
    read -r -p "$(echo -e "${BOLD}Continue?${RESET} [y/N] ")" confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || {
        echo -e "${YELLOW}Aborted.${RESET}"
        exit 0
    }
fi

# MARK: - Xcode check

if pgrep -x "Xcode" > /dev/null; then
    echo -e "${YELLOW}⚠ Xcode is currently running.${RESET}"

    quit_xcode=n
    if ! $FORCE; then
        read -r -p "$(echo -e "${BOLD}Quit Xcode first?${RESET} [y/N] ")" quit_xcode
    else
        quit_xcode=y
    fi

    if [[ "$quit_xcode" =~ ^[Yy]$ ]]; then
        osascript -e 'tell application "Xcode" to quit'
        echo -e "  ${GREEN}✓${RESET} Asked Xcode to quit"

        # Wait for Xcode to fully exit (up to 30 seconds)
        local_timeout=30
        while pgrep -x "Xcode" > /dev/null; do
            if (( local_timeout <= 0 )); then
                echo -e "  ${RED}✗${RESET} Xcode did not quit within 30 seconds. Aborting."
                exit 1
            fi
            sleep 1
            (( local_timeout-- ))
        done
        echo -e "  ${GREEN}✓${RESET} Xcode has exited"
    else
        echo -e "  ${RED}✗${RESET} Xcode is still running. Aborting to avoid incomplete cleanup."
        echo -e "  ${DIM}Quit Xcode first, then re-run swiftly-clean.${RESET}"
        exit 1
    fi
fi

echo ""
echo -e "${BOLD}${CYAN}Cleaning...${RESET}"
echo ""

if [ -d "$DERIVED_DATA" ]; then
    safe_rm_rf "$DERIVED_DATA"
    echo -e "  ${GREEN}✓${RESET} Cleared Xcode DerivedData"
else
    echo -e "  ${DIM}• Xcode DerivedData not found${RESET}"
fi

if [ -d "$SPM_CACHE" ]; then
    safe_rm_rf "$SPM_CACHE"
    echo -e "  ${GREEN}✓${RESET} Cleared SwiftPM global cache"
else
    echo -e "  ${DIM}• SwiftPM global cache not found${RESET}"
fi

if $DEEP; then
    if [ -d "$SPM_USER_STATE" ]; then
        safe_rm_rf "$SPM_USER_STATE"
        echo -e "  ${GREEN}✓${RESET} Cleared SwiftPM user state ${BOLD}(full)${RESET}"
    else
        echo -e "  ${DIM}• SwiftPM user state not found${RESET}"
    fi
else
    if [ -d "$SPM_FINGERPRINTS" ]; then
        safe_rm_rf "$SPM_FINGERPRINTS"
        echo -e "  ${GREEN}✓${RESET} Cleared SwiftPM security fingerprints"
    else
        echo -e "  ${DIM}• SwiftPM security fingerprints not found${RESET}"
    fi
fi

if [ -d "$LOCAL_BUILD" ]; then
    safe_rm_rf "$LOCAL_BUILD"
    echo -e "  ${GREEN}✓${RESET} Cleared local .build"
else
    echo -e "  ${DIM}• Local .build not found${RESET}"
fi

# MARK: - CocoaPods cleanup

if $HAS_PODS; then
    if [ -d "$PODS_DIR" ]; then
        safe_rm_rf "$PODS_DIR"
        echo -e "  ${GREEN}✓${RESET} Cleared CocoaPods Pods directory"
    else
        echo -e "  ${DIM}• CocoaPods Pods directory not found${RESET}"
    fi

    if [ -d "$PODS_CACHE" ]; then
        safe_rm_rf "$PODS_CACHE"
        echo -e "  ${GREEN}✓${RESET} Cleared CocoaPods global cache"
    else
        echo -e "  ${DIM}• CocoaPods global cache not found${RESET}"
    fi

    if $DEEP; then
        if [ -f "$PODFILE_LOCK" ]; then
            safe_rm_rf "$PODFILE_LOCK"
            echo -e "  ${GREEN}✓${RESET} Removed Podfile.lock ${BOLD}(deep)${RESET}"
        else
            echo -e "  ${DIM}• Podfile.lock not found${RESET}"
        fi
    fi
fi

echo ""
echo -e "${BOLD}${GREEN}✅ Done.${RESET}"
if $HAS_PODS; then
    echo -e "${DIM}Run \`pod install\` (or \`bundle exec pod install\`) then re-open your .xcworkspace.${RESET}"
else
    echo -e "${DIM}Re-open your .xcworkspace and let SwiftPM resolve.${RESET}"
fi
echo ""

# MARK: - CocoaPods reinstall prompt

if $HAS_PODS; then
    reinstall_pods=n
    if ! $FORCE; then
        if $USE_BUNDLER; then
            read -r -p "$(echo -e "${BOLD}Run \`bundle exec pod install\` now?${RESET} [y/N] ")" reinstall_pods
        else
            read -r -p "$(echo -e "${BOLD}Run \`pod install\` now?${RESET} [y/N] ")" reinstall_pods
        fi
    else
        reinstall_pods=y
    fi

    if [[ "$reinstall_pods" =~ ^[Yy]$ ]]; then
        echo ""
        if $USE_BUNDLER; then
            if command -v bundle &> /dev/null; then
                bundle exec pod install
                echo ""
                echo -e "  ${GREEN}✓${RESET} Pods reinstalled via Bundler"
            else
                echo -e "  ${RED}✗${RESET} 'bundle' command not found. Run manually: ${DIM}bundle exec pod install${RESET}"
            fi
        else
            if command -v pod &> /dev/null; then
                pod install
                echo ""
                echo -e "  ${GREEN}✓${RESET} Pods reinstalled"
            else
                echo -e "  ${RED}✗${RESET} 'pod' command not found. Run manually: ${DIM}pod install${RESET}"
            fi
        fi
        echo ""
    fi
fi
