#!/bin/bash
# FlowForge macOS Release Script
# Automated Sparkle release - similar to TestFlight deployment

set -e

# Configuration
APP_NAME="FlowForge"
BUNDLE_ID="com.flowforge.app"
FLOWFORGE_DIR="/Users/Brian/Projects/Active/FlowForge"
APP_DIR="$FLOWFORGE_DIR/FlowForgeApp"
BUILD_DIR="$APP_DIR/build"
RELEASES_DIR="$FLOWFORGE_DIR/releases"
KEYS_DIR="$HOME/.flowforge-keys"
SPARKLE_VERSION="2.6.0"
SPARKLE_DIR="$KEYS_DIR/Sparkle"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}🚀 FlowForge macOS Release (Sparkle)${NC}"
echo "======================================="

# Parse arguments
AUTO_VERSION=false
BUMP_BUILD=false
BUMP_VERSION=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --auto)
            AUTO_VERSION=true
            shift
            ;;
        --bump-build)
            BUMP_BUILD=true
            shift
            ;;
        --bump-version)
            BUMP_VERSION=true
            shift
            ;;
        *)
            VERSION="$1"
            shift
            ;;
    esac
done

# Create directories
mkdir -p "$RELEASES_DIR"
mkdir -p "$KEYS_DIR"

# Step 0: Check git status
echo -e "\n${BLUE}🔍 Checking git status...${NC}"
cd "$FLOWFORGE_DIR"
if [[ -n $(git status --porcelain) ]]; then
    echo -e "${YELLOW}⚠️  Warning: Uncommitted changes exist${NC}"
    git status --short
    echo ""
fi
COMMIT_SHA=$(git rev-parse --short HEAD)
echo -e "✅ Deploying commit ${GREEN}$COMMIT_SHA${NC}"

# Ensure Sparkle tools exist
if [ ! -d "$SPARKLE_DIR" ]; then
    echo -e "\n${BLUE}📥 Downloading Sparkle tools...${NC}"
    curl -L "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz" -o /tmp/sparkle.tar.xz
    mkdir -p "$SPARKLE_DIR"
    tar -xf /tmp/sparkle.tar.xz -C "$SPARKLE_DIR"
    rm /tmp/sparkle.tar.xz
fi

# Ensure signing keys exist in Keychain
echo -e "\n${BLUE}🔐 Checking Sparkle signing keys...${NC}"
"$SPARKLE_DIR/bin/generate_keys" 2>/dev/null || true

# Get current version from Info.plist
cd "$APP_DIR"
INFO_PLIST="$APP_DIR/App/Info.plist"
CURRENT_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST" 2>/dev/null || echo "1.0.0")
CURRENT_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO_PLIST" 2>/dev/null || echo "1")

# Determine new version
if [ "$AUTO_VERSION" = true ]; then
    echo -e "\n${BLUE}🤖 Analyzing commits to determine versioning...${NC}"

    # Get commits since last tag
    LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
    if [ -n "$LAST_TAG" ]; then
        COMMITS=$(git log "$LAST_TAG"..HEAD --oneline)
    else
        COMMITS=$(git log --oneline -10)
    fi

    # Check for breaking changes or major features
    if echo "$COMMITS" | grep -qiE "BREAKING|major|redesign|overhaul"; then
        BUMP_TYPE="MAJOR"
    elif echo "$COMMITS" | grep -qiE "feat|feature|add|new"; then
        BUMP_TYPE="MINOR"
    elif echo "$COMMITS" | grep -qiE "fix|bug|patch|refactor"; then
        BUMP_TYPE="PATCH"
    else
        BUMP_TYPE="BUILD"
    fi

    # Parse current version
    IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"

    case $BUMP_TYPE in
        MAJOR)
            NEW_VERSION="$((MAJOR + 1)).0.0"
            NEW_BUILD="1"
            ;;
        MINOR)
            NEW_VERSION="$MAJOR.$((MINOR + 1)).0"
            NEW_BUILD="1"
            ;;
        PATCH)
            NEW_VERSION="$MAJOR.$MINOR.$((PATCH + 1))"
            NEW_BUILD="1"
            ;;
        BUILD)
            NEW_VERSION="$CURRENT_VERSION"
            NEW_BUILD="$((CURRENT_BUILD + 1))"
            ;;
    esac

    echo -e "   Decision: ${GREEN}$BUMP_TYPE${NC} → $CURRENT_VERSION → $NEW_VERSION (build $NEW_BUILD)"
    VERSION="$NEW_VERSION"
    BUILD_NUMBER="$NEW_BUILD"

elif [ "$BUMP_BUILD" = true ]; then
    VERSION="$CURRENT_VERSION"
    BUILD_NUMBER="$((CURRENT_BUILD + 1))"
    echo -e "📝 Build bump: $CURRENT_BUILD → $BUILD_NUMBER"

elif [ "$BUMP_VERSION" = true ]; then
    IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"
    VERSION="$MAJOR.$((MINOR + 1)).0"
    BUILD_NUMBER="1"
    echo -e "📝 Version bump: $CURRENT_VERSION → $VERSION"

elif [ -n "$VERSION" ]; then
    BUILD_NUMBER="1"
    echo -e "📝 Manual version: $VERSION"

else
    VERSION="$CURRENT_VERSION"
    BUILD_NUMBER="$((CURRENT_BUILD + 1))"
    echo -e "📝 Default: build bump $CURRENT_BUILD → $BUILD_NUMBER"
fi

echo -e "\n📦 Version: ${GREEN}$VERSION${NC} (Build $BUILD_NUMBER)"

# Update version in Info.plist
echo -e "\n${BLUE}📝 Updating version in Info.plist...${NC}"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$INFO_PLIST"

# Regenerate Xcode project
echo -e "\n${BLUE}🔧 Regenerating Xcode project...${NC}"
xcodegen generate

# Build Release
echo -e "\n${BLUE}📦 Building Release...${NC}"
xcodebuild -project FlowForgeApp.xcodeproj \
    -scheme FlowForgeApp \
    -configuration Release \
    -derivedDataPath build \
    ONLY_ACTIVE_ARCH=YES \
    -quiet

# Create release zip
echo -e "\n${BLUE}📦 Creating release archive...${NC}"
APP_PATH="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"
ZIP_NAME="$APP_NAME-$VERSION.zip"
ZIP_PATH="$RELEASES_DIR/$ZIP_NAME"

rm -f "$ZIP_PATH"
cd "$BUILD_DIR/Build/Products/Release"
ditto -c -k --keepParent "$APP_NAME.app" "$ZIP_PATH"

FILE_SIZE=$(stat -f%z "$ZIP_PATH")
echo "Archive: $ZIP_PATH ($FILE_SIZE bytes)"

# Sign the release
echo -e "\n${BLUE}🔏 Signing with Sparkle...${NC}"
SIGNATURE=$("$SPARKLE_DIR/bin/sign_update" "$ZIP_PATH")
echo "Signature: ${SIGNATURE:0:20}..."

# Update appcast.xml
echo -e "\n${BLUE}📝 Updating appcast.xml...${NC}"
APPCAST="$FLOWFORGE_DIR/appcast.xml"
DOWNLOAD_URL="https://github.com/W1ndR1dr/FlowForge/releases/download/v$VERSION/$ZIP_NAME"
PUB_DATE=$(date -R)

# Generate release notes from recent commits
if [ -n "$LAST_TAG" ]; then
    RELEASE_NOTES=$(git log "$LAST_TAG"..HEAD --pretty=format:"• %s" | head -5)
else
    RELEASE_NOTES=$(git log --oneline -5 --pretty=format:"• %s")
fi

cat > "$APPCAST" << EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>FlowForge Updates</title>
        <link>https://github.com/W1ndR1dr/FlowForge</link>
        <description>FlowForge auto-update feed</description>
        <language>en</language>

        <item>
            <title>FlowForge $VERSION</title>
            <description><![CDATA[
                <h2>What's New in $VERSION</h2>
                <ul>
$(echo "$RELEASE_NOTES" | sed 's/^• \(.*\)$/                    <li>\1<\/li>/')
                </ul>
            ]]></description>
            <pubDate>$PUB_DATE</pubDate>
            <sparkle:version>$BUILD_NUMBER</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <enclosure
                url="$DOWNLOAD_URL"
                sparkle:edSignature="$SIGNATURE"
                length="$FILE_SIZE"
                type="application/octet-stream"/>
        </item>

    </channel>
</rss>
EOF

# Install to Applications
echo -e "\n${BLUE}📲 Installing to /Applications...${NC}"
rm -rf "/Applications/$APP_NAME.app"
cp -R "$APP_PATH" "/Applications/"

# Create GitHub release and push
echo -e "\n${BLUE}🚀 Creating GitHub release...${NC}"
cd "$FLOWFORGE_DIR"

# Commit appcast and version changes
git add appcast.xml "$INFO_PLIST"
git commit -m "Release v$VERSION for macOS (Sparkle)

🤖 Generated with [Claude Code](https://claude.com/claude-code)" || true

git push origin main

# Create GitHub release
gh release create "v$VERSION" "$ZIP_PATH" \
    --title "FlowForge $VERSION" \
    --notes "## What's New

$RELEASE_NOTES

---
🤖 Generated with [Claude Code](https://claude.com/claude-code)" \
    2>/dev/null || echo -e "${YELLOW}⚠️  Release v$VERSION may already exist${NC}"

# Summary
echo -e "\n${GREEN}============================================${NC}"
echo -e "${GREEN}🎉 SUCCESS! macOS Release Complete${NC}"
echo -e "${GREEN}============================================${NC}"
echo -e "Version: ${GREEN}$VERSION${NC} (Build $BUILD_NUMBER)"
echo -e "Archive: $ZIP_PATH"
echo ""
echo "Sparkle will auto-update existing users!"
echo "GitHub: https://github.com/W1ndR1dr/FlowForge/releases/tag/v$VERSION"

# Check if iOS companion also needs deployment
source "$FLOWFORGE_DIR/scripts/check-deploy-scope.sh" 2>/dev/null || true
COMPANION=$(check_companion_deploy "macos" 2>/dev/null || echo "")
if [ "$COMPANION" = "ios" ]; then
    echo ""
    echo -e "${YELLOW}📱 Shared code changed - iOS app may need update too${NC}"
    echo "   Run: ./scripts/deploy-to-testflight.sh --auto"
fi
