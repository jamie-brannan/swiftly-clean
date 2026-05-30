#!/usr/bin/env bash
# swiftly-clean — deep-cleans Xcode/SPM build state after local package changes
# Usage:
#   swiftly-clean
#   swiftly-clean --force
#   swiftly-clean --deep
#   swiftly-clean --force --deep
#   swiftly-clean --resolve
#   swiftly-clean --resolve --force
#   swiftly-clean --help
#   swiftly-clean -h
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
#
# Resolve clean (--resolve):
#   - searches the current directory tree for Package.resolved files
#   - lists them and offers to delete all, selected ones, or none

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
RESOLVE_PACKAGES=false

print_help() {
    printf '%s\n' "swiftly-clean - deep-cleans Xcode/SPM build state"
    printf '\n'
    printf '%s\n' "Usage:"
    printf '%s\n' "  swiftly-clean"
    printf '%s\n' "  swiftly-clean --force"
    printf '%s\n' "  swiftly-clean --deep"
    printf '%s\n' "  swiftly-clean --force --deep"
    printf '%s\n' "  swiftly-clean --resolve"
    printf '%s\n' "  swiftly-clean --resolve --force"
    printf '%s\n' "  swiftly-clean --help"
    printf '%s\n' "  swiftly-clean -h"
    printf '\n'
    printf '%s\n' "Options:"
    printf '%s\n' "  --force      Skip confirmation prompts"
    printf '%s\n' "  --deep       Remove full SwiftPM user state instead of only security fingerprints"
    printf '%s\n' "  --resolve    Find Package.resolved files and offer to delete them"
    printf '%s\n' "  --help, -h   Show help"
}

for arg in "$@"; do
    case "$arg" in
        --help|-h)
            print_help
            exit 0
            ;;
        --force)
            FORCE=true
            ;;
        --deep)
            DEEP=true
            ;;
        --resolve)
            RESOLVE_PACKAGES=true
            ;;
        *)
            echo -e "${RED}✗ Unknown option:${RESET} $arg"
            echo -e "${DIM}Usage: swiftly-clean [--force] [--deep] [--resolve] [--help]${RESET}"
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

    # Must live under $HOME/Library
    local home_library="$HOME/Library"
    if [[ "$target" != "$home_library"* && "$target" != "$PWD/.build" ]]; then
        echo -e "${RED}✗ Refusing to delete: path is outside expected locations (${target}).${RESET}"
        exit 1
    fi

    rm -rf "$target"
}

# Safe delete for a single Package.resolved file found under $PWD.
safe_rm_resolved() {
    local target="$1"

    # Must be non-empty
    if [[ -z "$target" ]]; then
        echo -e "${RED}✗ Refusing to delete: path is empty.${RESET}"
        exit 1
    fi

    # Must be named Package.resolved
    if [[ "$(basename "$target")" != "Package.resolved" ]]; then
        echo -e "${RED}✗ Refusing to delete: not a Package.resolved file (${target}).${RESET}"
        exit 1
    fi

    # Must live under $PWD
    local real_target real_pwd target_dir
    target_dir="$(dirname "$target")"
    if ! real_target="$(cd "$target_dir" 2>/dev/null && pwd -P)"; then
        echo -e "${RED}✗ Refusing to delete: could not resolve path (${target}).${RESET}"
        exit 1
    fi
    real_target="$real_target/$(basename "$target")"
    real_pwd="$(cd "$PWD" && pwd -P)"
    if [[ "$real_target" != "$real_pwd"/* ]]; then
        echo -e "${RED}✗ Refusing to delete: path is outside current directory (${target}).${RESET}"
        exit 1
    fi

    rm -f "$target"
}

# MARK: - Package.resolved search and destroy

if $RESOLVE_PACKAGES; then
    echo ""
    echo -e "${BOLD}${BLUE}🧹 swiftly-clean${RESET}"
    echo -e "${DIM}Searching for Package.resolved files under:${RESET} ${DIM}$PWD${RESET}"
    echo ""

    resolved_files=()
    while IFS= read -r -d '' file; do
        resolved_files+=("$file")
    done < <(find "$PWD" -name "Package.resolved" -not -path "*/.git/*" -print0 2>/dev/null | sort -z)

    if [ ${#resolved_files[@]} -eq 0 ]; then
        echo -e "  ${DIM}• No Package.resolved files found${RESET}"
        echo ""
        exit 0
    fi

    echo -e "  Found ${BOLD}${#resolved_files[@]}${RESET} Package.resolved file(s):"
    echo ""
    for i in "${!resolved_files[@]}"; do
        echo -e "  ${YELLOW}[$((i+1))]${RESET} ${DIM}${resolved_files[$i]}${RESET}"
    done
    echo ""

    if $FORCE; then
        resolve_action=a
    else
        read -r -p "$(echo -e "${BOLD}Delete all, select individually, or skip?${RESET} [a/i/N] ")" resolve_action
    fi

    if [[ "$resolve_action" =~ ^[Aa]$ ]]; then
        echo ""
        for file in "${resolved_files[@]}"; do
            safe_rm_resolved "$file"
            echo -e "  ${GREEN}✓${RESET} Deleted ${DIM}$file${RESET}"
        done
    elif [[ "$resolve_action" =~ ^[Ii]$ ]]; then
        echo ""
        for file in "${resolved_files[@]}"; do
            read -r -p "$(echo -e "  Delete ${DIM}$file${RESET}? [y/N] ")" del_confirm
            if [[ "$del_confirm" =~ ^[Yy]$ ]]; then
                safe_rm_resolved "$file"
                echo -e "  ${GREEN}✓${RESET} Deleted ${DIM}$file${RESET}"
            else
                echo -e "  ${DIM}  • Skipped${RESET}"
            fi
        done
    else
        echo -e "  ${YELLOW}Skipped.${RESET}"
    fi

    echo ""
    echo -e "${BOLD}${GREEN}✅ Done.${RESET}"
    echo ""
    exit 0
fi

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

echo ""
echo -e "${BOLD}${GREEN}✅ Done.${RESET}"
echo -e "${DIM}Re-open your .xcworkspace and let SwiftPM resolve.${RESET}"

# MARK: - Post-clean hint: branch-pinned packages

branch_resolved_files=()
while IFS= read -r -d '' file; do
    if grep -q '"branch": "' "$file" 2>/dev/null; then
        branch_resolved_files+=("$file")
    fi
done < <(find "$PWD" -name "Package.resolved" -not -path "*/.git/*" -print0 2>/dev/null)

if [ ${#branch_resolved_files[@]} -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}⚠ Branch-pinned packages detected in Package.resolved:${RESET}"
    for file in "${branch_resolved_files[@]}"; do
        echo -e "  ${DIM}$file${RESET}"
    done
    echo -e "  ${DIM}If build issues persist, stale pins may be the cause.${RESET}"
    echo -e "  ${DIM}Run:${RESET} ${BOLD}swiftly-clean --resolve${RESET}"
fi

echo ""
