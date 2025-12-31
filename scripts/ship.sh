#!/bin/bash
# Forge Ship Script
# One command to rule them all: builds and deploys whatever needs deploying
#
# USAGE:
#   ./scripts/ship.sh              # Check what needs deploying, do it
#   ./scripts/ship.sh --dry-run    # Just show what would happen
#   ./scripts/ship.sh --force      # Deploy even if nothing changed

set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

DRY_RUN=false
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run) DRY_RUN=true; shift ;;
        --force) FORCE=true; shift ;;
        --help)
            echo "Usage: ./scripts/ship.sh [--dry-run] [--force]"
            echo ""
            echo "Checks what platforms need updates and deploys them."
            echo ""
            echo "Options:"
            echo "  --dry-run   Show what would be deployed without doing it"
            echo "  --force     Deploy both platforms even if no changes detected"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

echo ""
echo -e "${BLUE}🚢 Forge Ship${NC}"
echo "=============="
echo ""

# Check git status
UNCOMMITTED=$(git status --porcelain 2>/dev/null | grep -v "^??" | head -1)
if [[ -n "$UNCOMMITTED" ]]; then
    echo -e "${YELLOW}⚠️  Uncommitted changes detected${NC}"
    git status --short | head -10
    echo ""
    echo "Commit your changes first, or they won't be in the deploy."
    echo ""
    read -p "Continue anyway? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Source the scope checker
source "$PROJECT_DIR/scripts/check-deploy-scope.sh"

# Check what needs deploying
changed=$(get_changed_files "")
ios_needed=$(check_platform_changes "$changed" "ios")
macos_needed=$(check_platform_changes "$changed" "macos")

if [[ "$FORCE" == true ]]; then
    ios_needed="yes"
    macos_needed="yes"
fi

echo -e "📱 iOS needs deploy:   ${ios_needed}"
echo -e "💻 macOS needs deploy: ${macos_needed}"
echo ""

if [[ "$ios_needed" == "no" ]] && [[ "$macos_needed" == "no" ]]; then
    echo -e "${GREEN}✅ Everything is up to date!${NC}"
    echo ""
    echo "No ForgeApp/ changes since last deploy."
    echo "Use --force to deploy anyway."
    exit 0
fi

if [[ "$DRY_RUN" == true ]]; then
    echo -e "${YELLOW}🔍 Dry run - would deploy:${NC}"
    [[ "$macos_needed" == "yes" ]] && echo "   • macOS app (release-macos.sh)"
    [[ "$ios_needed" == "yes" ]] && echo "   • iOS to TestFlight (deploy-to-testflight.sh)"
    echo ""
    echo "Run without --dry-run to actually deploy."
    exit 0
fi

# Deploy macOS first (faster, good sanity check)
if [[ "$macos_needed" == "yes" ]]; then
    echo ""
    echo -e "${BLUE}💻 Deploying macOS...${NC}"
    echo "─────────────────────────────────────"

    # Use release-macos.sh for proper versioning, LLM notes, and Sparkle signing
    ./scripts/release-macos.sh --auto

    echo -e "${GREEN}✅ macOS app deployed${NC}"
fi

# Deploy iOS
if [[ "$ios_needed" == "yes" ]]; then
    echo ""
    echo -e "${BLUE}📱 Deploying iOS to TestFlight...${NC}"
    echo "─────────────────────────────────────"

    ./scripts/deploy-to-testflight.sh --auto

    # Commit the version bump
    if [[ -n $(git status --porcelain ForgeApp/App-iOS/Info.plist 2>/dev/null) ]]; then
        VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" ForgeApp/App-iOS/Info.plist)
        BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" ForgeApp/App-iOS/Info.plist)
        git add ForgeApp/App-iOS/Info.plist
        git commit -m "chore: Bump iOS to $VERSION ($BUILD) for TestFlight"
        git push
    fi
fi

# Update and restart Pi server if Python files changed
PYTHON_CHANGED=$(echo "$changed" | grep -E "\.py$" | head -1)
if [[ -n "$PYTHON_CHANGED" ]] || [[ "$FORCE" == true ]]; then
    echo ""
    echo -e "${BLUE}🍓 Updating Pi server...${NC}"
    echo "─────────────────────────────────────"

    # Pi is the ONLY server in this architecture (no local server)
    # Check if Pi is reachable and update it
    if ssh -o ConnectTimeout=5 brian@raspberrypi "echo ok" &>/dev/null; then
        ssh brian@raspberrypi "cd ~/forge && git pull && sudo systemctl restart forge"
        sleep 2
        if curl -s --connect-timeout 5 http://raspberrypi:8081/health > /dev/null; then
            echo -e "${GREEN}✅ Pi server updated and restarted${NC}"
        else
            echo -e "${YELLOW}⚠️  Pi server may not have started - check with: ssh brian@raspberrypi 'sudo journalctl -u forge -n 20'${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  Pi not reachable - skipping server update${NC}"
        echo "   Make sure Pi is on and connected to Tailscale"
    fi
fi

echo ""
echo -e "${GREEN}🎉 Ship complete!${NC}"
echo ""
[[ "$macos_needed" == "yes" ]] && echo "   💻 macOS: Released via Sparkle (GitHub + /Applications)"
[[ "$ios_needed" == "yes" ]] && echo "   📱 iOS: Uploaded to TestFlight (check App Store Connect in ~10 min)"
echo ""

# Launch the app
open /Applications/Forge.app 2>/dev/null || true
