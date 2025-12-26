#!/bin/bash
# FlowForge iOS TestFlight Deployment Script
# Automates: Archive → Export → Upload to TestFlight → Auto-Generate Release Notes
#
# CREDENTIALS SETUP (one-time):
#   Uses shared credentials from ~/.appstore/credentials (same as AirFit)
#   See AirFit/scripts/deploy-to-testflight.sh for setup instructions
#
# USAGE:
#   ./scripts/deploy-to-testflight.sh                    # Deploy current version
#   ./scripts/deploy-to-testflight.sh --auto             # [RECOMMENDED] Claude decides version bump
#   ./scripts/deploy-to-testflight.sh --bump-build       # Only increment build number
#   ./scripts/deploy-to-testflight.sh --bump-version     # Force Claude to pick major/minor/patch
#   ./scripts/deploy-to-testflight.sh --version 1.2.0    # Set specific version
#   ./scripts/deploy-to-testflight.sh --skip-notes       # Skip changelog generation
#   ./scripts/deploy-to-testflight.sh --force            # Deploy even with uncommitted changes
#
# FEATURES:
#   - Auto-generates friendly release notes using Claude CLI
#   - Pushes "What's New" to TestFlight via App Store Connect API
#   - Development workflow tool with a maker-friendly tone

set -e

# ============================================================================
# Configuration
# ============================================================================

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR/FlowForgeApp"

SCHEME="FlowForgeApp-iOS"
PROJECT="FlowForgeApp.xcodeproj"
BUNDLE_ID="com.flowforge.app.ios"
TEAM_ID="2H43Q8Y3CR"
APP_APPLE_ID=""  # Set this after first upload shows the ID

BUILD_DIR="$PROJECT_DIR/FlowForgeApp/build/testflight"
ARCHIVE_PATH="$BUILD_DIR/FlowForgeApp-iOS.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
EXPORT_OPTIONS_PATH="$PROJECT_DIR/FlowForgeApp/ExportOptions.plist"

# ============================================================================
# Helper Functions
# ============================================================================

# Check if Python cryptography library is available for JWT signing
check_jwt_deps() {
    python3 -c "from cryptography.hazmat.primitives import hashes" 2>/dev/null
}

# Generate JWT for App Store Connect API using Python
generate_jwt() {
    local key_id="$1"
    local issuer_id="$2"
    local key_path="$3"

    if ! check_jwt_deps; then
        echo ""
        return 1
    fi

    python3 << EOF
import json
import time
import base64
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature
from cryptography.hazmat.backends import default_backend

def base64url_encode(data):
    if isinstance(data, str):
        data = data.encode('utf-8')
    return base64.urlsafe_b64encode(data).rstrip(b'=').decode('utf-8')

with open("$key_path", "rb") as f:
    private_key = serialization.load_pem_private_key(f.read(), password=None, backend=default_backend())

header = {"alg": "ES256", "kid": "$key_id", "typ": "JWT"}
now = int(time.time())
payload = {"iss": "$issuer_id", "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"}

header_b64 = base64url_encode(json.dumps(header, separators=(',', ':')))
payload_b64 = base64url_encode(json.dumps(payload, separators=(',', ':')))
message = f"{header_b64}.{payload_b64}".encode('utf-8')

signature_der = private_key.sign(message, ec.ECDSA(hashes.SHA256()))
r, s = decode_dss_signature(signature_der)
r_bytes = r.to_bytes(32, byteorder='big')
s_bytes = s.to_bytes(32, byteorder='big')
signature_b64 = base64url_encode(r_bytes + s_bytes)

print(f"{header_b64}.{payload_b64}.{signature_b64}")
EOF
}

# Determine version bump type using Claude CLI
determine_version_bump() {
    local previous_tag="$1"
    local force_version="$2"

    local commits
    if [[ -n "$previous_tag" ]]; then
        commits=$(git log --oneline "$previous_tag"..HEAD 2>/dev/null | head -30)
    else
        commits=$(git log --oneline -20 2>/dev/null)
    fi

    if [[ -z "$commits" ]]; then
        if [[ "$force_version" == "true" ]]; then
            echo "PATCH"
        else
            echo "BUILD"
        fi
        return
    fi

    if ! command -v claude &> /dev/null; then
        if [[ "$force_version" == "true" ]]; then
            echo "PATCH"
        else
            echo "BUILD"
        fi
        return
    fi

    local prompt
    if [[ "$force_version" == "true" ]]; then
        prompt="You are analyzing git commits to determine the semantic version bump for an iOS app.

RESPOND WITH EXACTLY ONE WORD: MAJOR, MINOR, or PATCH

Rules:
- MAJOR: Breaking changes, major UI redesigns, data migrations
- MINOR: New features, new screens, significant enhancements
- PATCH: Bug fixes, UI polish, refactoring, performance improvements

Commits to analyze:
$commits

Your response (one word only):"
    else
        prompt="You are analyzing git commits to determine if a version bump is warranted.

RESPOND WITH EXACTLY ONE WORD: MAJOR, MINOR, PATCH, or BUILD

Rules:
- MAJOR: Breaking changes, major redesigns, API changes
- MINOR: New user-facing features, new screens
- PATCH: Bug fixes that users would notice
- BUILD: Internal changes only - refactoring, cleanup, minor tweaks

Be conservative: most commits are BUILD.

Commits to analyze:
$commits

Your response (one word only):"
    fi

    local bump_type
    bump_type=$(echo "$prompt" | claude --print 2>/dev/null | grep -oE '(MAJOR|MINOR|PATCH|BUILD)' | head -1)

    if [[ -z "$bump_type" ]]; then
        if [[ "$force_version" == "true" ]]; then
            echo "PATCH"
        else
            echo "BUILD"
        fi
    else
        echo "$bump_type"
    fi
}

calculate_new_version() {
    local current="$1"
    local bump_type="$2"

    local major minor patch
    IFS='.' read -r major minor patch <<< "$current"
    major=${major:-1}
    minor=${minor:-0}
    patch=${patch:-0}

    case "$bump_type" in
        MAJOR) echo "$((major + 1)).0.0" ;;
        MINOR) echo "${major}.$((minor + 1)).0" ;;
        PATCH) echo "${major}.${minor}.$((patch + 1))" ;;
        *) echo "${major}.${minor}.$((patch + 1))" ;;
    esac
}

generate_changelog() {
    local previous_tag="$1"

    local commits
    if [[ -n "$previous_tag" ]]; then
        commits=$(git log --oneline "$previous_tag"..HEAD 2>/dev/null | head -20)
    else
        commits=$(git log --oneline -15 2>/dev/null)
    fi

    if [[ -z "$commits" ]]; then
        echo "• Bug fixes and performance improvements"
        return
    fi

    if ! command -v claude &> /dev/null; then
        echo "• Various improvements and bug fixes"
        return
    fi

    local prompt="You are writing TestFlight release notes for FlowForge, a development workflow tool.

Based on these git commits, write 2-4 bullet points for users. Be:
- Friendly and encouraging (for indie developers)
- Focus on user benefits, not technical details
- Keep each bullet under 80 characters
- Use emoji sparingly (1-2 max)

Format: Just the bullet points, no intro text.

Example style:
• Feature tracking now syncs faster between devices
• Added quick capture for those shower-thought ideas
• Fixed that bug where prompts occasionally vanished

Commits:
$commits"

    local changelog
    changelog=$(echo "$prompt" | claude --print 2>/dev/null | head -10)

    if [[ -z "$changelog" ]]; then
        echo "• Bug fixes and performance improvements"
    else
        echo "$changelog"
    fi
}

# ============================================================================
# Parse Arguments
# ============================================================================

BUMP_BUILD=false
BUMP_VERSION=false
AUTO_VERSION=false
NEW_VERSION=""
SKIP_NOTES=false
FORCE_DEPLOY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --force) FORCE_DEPLOY=true; shift ;;
        --auto) AUTO_VERSION=true; BUMP_BUILD=true; shift ;;
        --bump-build) BUMP_BUILD=true; shift ;;
        --bump-version) BUMP_VERSION=true; BUMP_BUILD=true; shift ;;
        --version) NEW_VERSION="$2"; shift 2 ;;
        --skip-notes) SKIP_NOTES=true; shift ;;
        --help) head -25 "$0" | tail -22; exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# ============================================================================
# Validate Prerequisites
# ============================================================================

echo "🚀 FlowForge iOS TestFlight Deployment"
echo "======================================="
echo ""

# Auto-source credentials
CREDENTIALS_FILE="$HOME/.appstore/credentials"
if [[ -f "$CREDENTIALS_FILE" ]]; then
    echo "🔐 Loading credentials from ~/.appstore/credentials"
    source "$CREDENTIALS_FILE"
fi

if [[ -z "$APP_STORE_CONNECT_API_KEY_ID" ]] || \
   [[ -z "$APP_STORE_CONNECT_API_ISSUER_ID" ]] || \
   [[ -z "$APP_STORE_CONNECT_API_KEY_PATH" ]]; then
    echo "⚠️  App Store Connect API credentials not found."
    echo ""
    echo "Quick setup:"
    echo "  1. Create ~/.appstore/credentials with:"
    echo "     export APP_STORE_CONNECT_API_KEY_ID=\"your-key-id\""
    echo "     export APP_STORE_CONNECT_API_ISSUER_ID=\"your-issuer-id\""
    echo "     export APP_STORE_CONNECT_API_KEY_PATH=\"\$HOME/.appstore/AuthKey_XXX.p8\""
    echo ""
    exit 1
fi

if [[ ! -f "$APP_STORE_CONNECT_API_KEY_PATH" ]]; then
    echo "❌ API key file not found: $APP_STORE_CONNECT_API_KEY_PATH"
    exit 1
fi

echo "✅ API credentials configured"

# ============================================================================
# Git Pre-flight Check
# ============================================================================

echo ""
echo "🔍 Checking git status..."

cd "$PROJECT_DIR"

STAGED_CHANGES=$(git diff --cached --name-only 2>/dev/null)
UNSTAGED_CHANGES=$(git diff --name-only 2>/dev/null)
UNTRACKED_FILES=$(git ls-files --others --exclude-standard 2>/dev/null | grep -E '\.(swift|py|plist|json|yml|yaml|sh)$' || true)

HAS_ISSUES=false

if [[ -n "$STAGED_CHANGES" ]]; then
    echo "⚠️  Staged changes not committed:"
    echo "$STAGED_CHANGES" | sed 's/^/   /'
    HAS_ISSUES=true
fi

if [[ -n "$UNSTAGED_CHANGES" ]]; then
    echo "⚠️  Unstaged changes:"
    echo "$UNSTAGED_CHANGES" | sed 's/^/   /'
    HAS_ISSUES=true
fi

if [[ "$HAS_ISSUES" == true ]] && [[ "$FORCE_DEPLOY" != true ]]; then
    echo ""
    echo "❌ Cannot deploy: uncommitted changes detected"
    echo ""
    echo "Options:"
    echo "  1. Commit your changes first"
    echo "  2. Force deploy: $0 --force"
    exit 1
fi

CURRENT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null)
echo "✅ Deploying commit $CURRENT_COMMIT"

# ============================================================================
# Version/Build Management
# ============================================================================

cd "$PROJECT_DIR/FlowForgeApp"
INFO_PLIST="$PROJECT_DIR/FlowForgeApp/App-iOS/Info.plist"

CURRENT_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST" 2>/dev/null || echo "1.0.0")
PREVIOUS_VERSION_TAG=$(git tag -l "v*" --sort=-version:refname | head -1)

if [[ "$AUTO_VERSION" == true ]]; then
    echo ""
    echo "🤖 Analyzing commits to determine versioning..."
    BUMP_TYPE=$(determine_version_bump "$PREVIOUS_VERSION_TAG" "false")

    if [[ "$BUMP_TYPE" == "BUILD" ]]; then
        echo "   Decision: BUILD only (no version bump)"
    else
        NEW_VERSION=$(calculate_new_version "$CURRENT_VERSION" "$BUMP_TYPE")
        echo "   Decision: $BUMP_TYPE → $CURRENT_VERSION → $NEW_VERSION"
    fi
fi

if [[ "$BUMP_VERSION" == true ]]; then
    echo ""
    echo "🤖 Analyzing commits for version bump..."
    BUMP_TYPE=$(determine_version_bump "$PREVIOUS_VERSION_TAG" "true")
    NEW_VERSION=$(calculate_new_version "$CURRENT_VERSION" "$BUMP_TYPE")
    echo "   $BUMP_TYPE: $CURRENT_VERSION → $NEW_VERSION"
fi

if [[ -n "$NEW_VERSION" ]]; then
    echo "📝 Setting version to $NEW_VERSION..."
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEW_VERSION" "$INFO_PLIST"
fi

if [[ "$BUMP_BUILD" == true ]]; then
    CURRENT_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO_PLIST" 2>/dev/null || echo "0")
    NEW_BUILD=$((CURRENT_BUILD + 1))
    echo "📝 Build: $CURRENT_BUILD → $NEW_BUILD"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_BUILD" "$INFO_PLIST"
fi

CURRENT_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST" 2>/dev/null || echo "1.0")
CURRENT_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO_PLIST" 2>/dev/null || echo "1")

echo ""
echo "📦 Version: $CURRENT_VERSION ($CURRENT_BUILD)"

# ============================================================================
# Build & Upload
# ============================================================================

echo ""
echo "🧹 Cleaning..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

if command -v xcodegen &> /dev/null; then
    echo "🔧 Regenerating Xcode project..."
    xcodegen generate
fi

echo ""
echo "📦 Archiving..."
xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination 'generic/platform=iOS' \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -allowProvisioningUpdates \
    CODE_SIGN_STYLE=Automatic \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    -quiet

echo "✅ Archive created"

echo ""
echo "📤 Exporting & uploading to TestFlight..."
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS_PATH" \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$APP_STORE_CONNECT_API_KEY_PATH" \
    -authenticationKeyID "$APP_STORE_CONNECT_API_KEY_ID" \
    -authenticationKeyIssuerID "$APP_STORE_CONNECT_API_ISSUER_ID"

echo ""
echo "============================================"
echo "🎉 SUCCESS! Uploaded to TestFlight"
echo "============================================"
echo "Version: $CURRENT_VERSION ($CURRENT_BUILD)"

# ============================================================================
# Release Notes
# ============================================================================

if [[ "$SKIP_NOTES" == false ]]; then
    echo ""
    echo "✍️  Generating release notes..."

    PREVIOUS_TAG=$(git tag -l "build-*" --sort=-version:refname | head -1)
    [[ -z "$PREVIOUS_TAG" ]] && PREVIOUS_TAG=$(git tag -l "v*" --sort=-version:refname | head -1)

    CHANGELOG=$(generate_changelog "$PREVIOUS_TAG")

    echo ""
    echo "📋 Release Notes:"
    echo "─────────────────────────────────────────"
    echo "$CHANGELOG"
    echo "─────────────────────────────────────────"

    git tag -f "build-$CURRENT_BUILD" HEAD 2>/dev/null || true
fi

echo ""
echo "Next steps:"
echo "  1. Wait ~5-15 minutes for processing"
echo "  2. Check App Store Connect for status"
echo ""
echo "App Store Connect: https://appstoreconnect.apple.com"

# Check if macOS companion also needs deployment
source "$PROJECT_DIR/scripts/check-deploy-scope.sh" 2>/dev/null || true
COMPANION=$(check_companion_deploy "ios" 2>/dev/null || echo "")
if [ "$COMPANION" = "macos" ]; then
    echo ""
    echo -e "${YELLOW}💻 Shared code changed - macOS app may need update too${NC}"
    echo "   Run: ./scripts/release-macos.sh --auto"
fi
