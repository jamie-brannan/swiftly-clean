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
# Normal clean removes:
#   - all Xcode DerivedData (~/Library/Developer/Xcode/DerivedData)
#   - SwiftPM global cache (~/Library/Caches/org.swift.swiftpm)
#   - SwiftPM security fingerprints (~/Library/org.swift.swiftpm/security)
#   - local .build for the current directory
#
# Deep clean additionally removes:
#   - full SwiftPM user state at ~/Library/org.swift.swiftpm

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

echo ""
echo -e "${BOLD}${BLUE}🧹 swiftly-clean${RESET}"
echo -e "${DIM}Deep-cleans Xcode and SwiftPM build state.${RESET}"
echo ""

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

echo ""

if ! $FORCE; then
    read -r -p "$(echo -e "${BOLD}Continue?${RESET} [y/N] ")" confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || {
        echo -e "${YELLOW}Aborted.${RESET}"
        exit 0
    }
fi

if pgrep -x "Xcode" > /dev/null; then
    echo -e "${YELLOW}⚠ Xcode is currently running.${RESET}"

    if ! $FORCE; then
        read -r -p "$(echo -e "${BOLD}Quit Xcode first?${RESET} [y/N] ")" quit_xcode

        if [[ "$quit_xcode" =~ ^[Yy]$ ]]; then
            osascript -e 'tell application "Xcode" to quit'
            echo -e "  ${GREEN}✓${RESET} Asked Xcode to quit"
        else
            echo -e "  ${YELLOW}⚠${RESET} Xcode is still running"
        fi
    else
        osascript -e 'tell application "Xcode" to quit'
        echo -e "  ${GREEN}✓${RESET} Asked Xcode to quit"
    fi
fi

echo ""
echo -e "${BOLD}${CYAN}Cleaning...${RESET}"
echo ""

if [ -d "$DERIVED_DATA" ]; then
    rm -rf "$DERIVED_DATA"
    echo -e "  ${GREEN}✓${RESET} Cleared Xcode DerivedData"
else
    echo -e "  ${DIM}• Xcode DerivedData not found${RESET}"
fi

if [ -d "$SPM_CACHE" ]; then
    rm -rf "$SPM_CACHE"
    echo -e "  ${GREEN}✓${RESET} Cleared SwiftPM global cache"
else
    echo -e "  ${DIM}• SwiftPM global cache not found${RESET}"
fi

if $DEEP; then
    if [ -d "$SPM_USER_STATE" ]; then
        rm -rf "$SPM_USER_STATE"
        echo -e "  ${GREEN}✓${RESET} Cleared SwiftPM user state ${BOLD}(full)${RESET}"
    else
        echo -e "  ${DIM}• SwiftPM user state not found${RESET}"
    fi
else
    if [ -d "$SPM_FINGERPRINTS" ]; then
        rm -rf "$SPM_FINGERPRINTS"
        echo -e "  ${GREEN}✓${RESET} Cleared SwiftPM security fingerprints"
    else
        echo -e "  ${DIM}• SwiftPM security fingerprints not found${RESET}"
    fi
fi

if [ -d "$LOCAL_BUILD" ]; then
    rm -rf "$LOCAL_BUILD"
    echo -e "  ${GREEN}✓${RESET} Cleared local .build"
else
    echo -e "  ${DIM}• Local .build not found${RESET}"
fi

echo ""
echo -e "${BOLD}${GREEN}✅ Done.${RESET}"
echo -e "${DIM}Re-open your .xcworkspace and let SwiftPM resolve.${RESET}"
echo ""
