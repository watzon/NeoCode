# NeoCode build and release workflow

default:
    @just --list

app_name := "NeoCode"
scheme := "NeoCode"
xcode_project := "NeoCode.xcodeproj"
github_repo := "watzon/NeoCode"
sparkle_version := "2.6.4"
sparkle_key_account := "tech.watzon.NeoCode"
build_dir := "DerivedData/Build/Products"
release_dir := build_dir / "Release"
archive_path := build_dir / app_name + ".xcarchive"
app_bundle := release_dir / app_name + ".app"
dmg_dir := "dist"
dmg_path := dmg_dir / app_name + ".dmg"

clean:
    @echo "Cleaning build artifacts..."
    rm -rf "{{build_dir}}" "{{dmg_dir}}" DerivedData updates appcast.xml
    @echo "Done"

build:
    @echo "Building {{app_name}} (Debug)..."
    xcodebuild \
        -project {{xcode_project}} \
        -scheme {{scheme}} \
        -configuration Debug \
        -derivedDataPath DerivedData \
        build

build-release:
    @echo "Building {{app_name}} (Release)..."
    xcodebuild \
        -project {{xcode_project}} \
        -scheme {{scheme}} \
        -configuration Release \
        -derivedDataPath DerivedData \
        build

test:
    @echo "Running tests..."
    xcodebuild test \
        -project {{xcode_project}} \
        -scheme {{scheme}} \
        -destination 'platform=macOS'

archive: sparkle-tools
    @PUBLIC_KEY="$$(./bin/generate_keys --account {{sparkle_key_account}} -p 2>/dev/null || true)"; \
    if [ -z "$${PUBLIC_KEY}" ]; then \
        echo "Missing Sparkle key for account '{{sparkle_key_account}}'. Run: just sparkle-keygen"; \
        exit 1; \
    fi; \
    echo "Archiving {{app_name}} with Sparkle key account '{{sparkle_key_account}}'..."; \
    xcodebuild archive \
        -project {{xcode_project}} \
        -scheme {{scheme}} \
        -configuration Release \
        -archivePath "{{archive_path}}" \
        SPARKLE_PUBLIC_ED_KEY="$${PUBLIC_KEY}" \
        -allowProvisioningUpdates

export-app: archive
    @echo "Exporting signed app..."
    xcodebuild -exportArchive \
        -archivePath "{{archive_path}}" \
        -exportPath "{{release_dir}}" \
        -exportOptionsPlist scripts/ExportOptions.plist \
        -allowProvisioningUpdates

dmg: export-app
    @./scripts/create-dmg.sh

dmg-quick:
    @./scripts/create-dmg.sh

sign:
    @./scripts/sign-app-bundle.sh "{{app_bundle}}" "Developer ID Application"

verify-signature:
    codesign --verify --deep --strict --verbose=2 "{{app_bundle}}"
    spctl --assess --type execute --verbose=2 "{{app_bundle}}"

notarize dmg_path:
    @PROFILE="${NOTARYTOOL_PROFILE:-notarytool-password}"; \
    echo "Notarizing {{dmg_path}} with profile ${PROFILE}..."; \
    result_file=$$(mktemp) && \
    xcrun notarytool submit "{{dmg_path}}" \
        --keychain-profile "$${PROFILE}" \
        --wait \
        --output-format json > "$${result_file}" && \
    python3 -c 'import json, sys; result=json.load(open(sys.argv[1], encoding="utf-8")); status=result.get("status"); summary=result.get("statusSummary", "Unknown notarization failure"); sys.exit(0 if status == "Accepted" else (print(f"Notarization failed: {status or 'unknown'} - {summary}", file=sys.stderr) or 1))' "$${result_file}" && \
    rm -f "$${result_file}"

staple dmg_path:
    xcrun stapler staple "{{dmg_path}}"

sparkle-tools:
    @mkdir -p bin && \
    if [ ! -f "bin/generate_appcast" ]; then \
        echo "Downloading Sparkle tools {{sparkle_version}}..."; \
        curl -L -o /tmp/Sparkle.tar.xz "https://github.com/sparkle-project/Sparkle/releases/download/{{sparkle_version}}/Sparkle-{{sparkle_version}}.tar.xz"; \
        rm -rf /tmp/sparkle-extract && mkdir -p /tmp/sparkle-extract; \
        tar -xf /tmp/Sparkle.tar.xz -C /tmp/sparkle-extract; \
        cp /tmp/sparkle-extract/bin/generate_appcast bin/; \
        cp /tmp/sparkle-extract/bin/sign_update bin/ 2>/dev/null || true; \
        cp /tmp/sparkle-extract/bin/generate_keys bin/ 2>/dev/null || true; \
        rm -rf /tmp/Sparkle.tar.xz /tmp/sparkle-extract; \
    else \
        echo "Sparkle tools already installed in bin/"; \
    fi

appcast dmg_path: sparkle-tools
    @if [ ! -f "{{dmg_path}}" ]; then \
        echo "DMG not found: {{dmg_path}}"; \
        exit 1; \
    fi
    @TAG_VERSION="v$$(grep 'MARKETING_VERSION = ' {{xcode_project}}/project.pbxproj | head -1 | sed 's/.*= \(.*\);/\1/')"; \
    DOWNLOAD_PREFIX="https://github.com/{{github_repo}}/releases/download/$${TAG_VERSION}/"; \
    rm -rf updates && mkdir -p updates && cp "{{dmg_path}}" updates/; \
    KEY_FILE=""; \
    APPCAST_ARGS=""; \
    if [ -n "${SPARKLE_PRIVATE_KEY:-}" ] && ./bin/generate_appcast --help 2>&1 | grep -q -- '--ed-key-file'; then \
        KEY_FILE=$$(mktemp); \
        printf '%s' "${SPARKLE_PRIVATE_KEY}" > "$${KEY_FILE}"; \
        APPCAST_ARGS="--ed-key-file $${KEY_FILE}"; \
    elif ./bin/generate_appcast --help 2>&1 | grep -q -- '--account'; then \
        APPCAST_ARGS="--account {{sparkle_key_account}}"; \
    fi; \
    if ./bin/generate_appcast --help 2>&1 | grep -q -- '--download-url-prefix'; then \
        ./bin/generate_appcast $${APPCAST_ARGS} --download-url-prefix "$${DOWNLOAD_PREFIX}" updates/; \
    else \
        ./bin/generate_appcast $${APPCAST_ARGS} updates/; \
    fi; \
    cp updates/appcast.xml appcast.xml; \
    rm -rf updates; \
    if [ -n "$${KEY_FILE}" ]; then rm -f "$${KEY_FILE}"; fi

release-beta version:
    GITHUB_RELEASE_PRERELEASE=1 just release "{{version}}"

sparkle-public-key-value: sparkle-tools
	@./bin/generate_keys --account {{sparkle_key_account}} -p

sparkle-public-key: sparkle-tools
	@echo "Sparkle public key for {{sparkle_key_account}}:"
	@./bin/generate_keys --account {{sparkle_key_account}} -p

sparkle-keygen: sparkle-tools
	@./bin/generate_keys --account {{sparkle_key_account}}

release-notes version:
    #!/usr/bin/env bash
    set -euo pipefail

    VERSION="{{version}}"
    TAG="v${VERSION}"
    NOTES_DIR="release-notes"
    NOTES_PATH="${NOTES_DIR}/${TAG}.md"

    if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "Invalid version format: $VERSION"
        exit 1
    fi

    mkdir -p "${NOTES_DIR}"

    if [ -f "${NOTES_PATH}" ]; then
        echo "Release notes already exist: ${NOTES_PATH}"
        exit 0
    fi

    if git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null 2>&1; then
        PREV_TAG=$(git tag --sort=-version:refname | awk -v tag="${TAG}" '$0 != tag {print; exit}')
    else
        PREV_TAG=$(git tag --sort=-version:refname | head -1)
    fi

    COMMITS=$(git log --no-merges --pretty=format:'- %s' "${PREV_TAG:+${PREV_TAG}..HEAD}" | head -8 || true)
    COMPARE_URL=""
    if [ -n "${PREV_TAG}" ]; then
        COMPARE_URL="https://github.com/{{github_repo}}/compare/${PREV_TAG}...${TAG}"
    fi

    printf '%s\n' \
        "## What's New" \
        '' \
        "- TODO: Add 2-5 user-facing highlights for ${TAG}." \
        '' \
        '## Improvements' \
        '' \
        '- TODO: Add notable fixes, polish, or release prep changes users should know about.' \
        '' \
        '## Full Changelog' \
        '' \
        "${COMPARE_URL:-TODO: Add compare URL}" \
        > "${NOTES_PATH}"

    if [ -n "${COMMITS}" ]; then
        printf '\n## Commit Context (for drafting)\n\n%s\n' "${COMMITS}" >> "${NOTES_PATH}"
    fi

    echo "Draft release notes created: ${NOTES_PATH}"

release-local: clean test dmg
    @echo "Release build complete: {{dmg_path}}"
    @echo "Next: just notarize {{dmg_path}} && just staple {{dmg_path}} && just appcast {{dmg_path}}"

release version: sparkle-tools
    #!/usr/bin/env bash
    set -euo pipefail

    VERSION="{{version}}"
    TAG="v${VERSION}"
    DMG_PATH="{{dmg_path}}"
    APPCAST_PATH="appcast.xml"
    NOTES_PATH="release-notes/${TAG}.md"
    RELEASE_TITLE="NeoCode ${TAG}"
    RELEASE_FLAGS=()

    if [ "${GITHUB_RELEASE_PRERELEASE:-0}" = "1" ]; then
        RELEASE_FLAGS+=(--prerelease)
        RELEASE_TITLE="NeoCode ${TAG} Beta"
    fi

    if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "Invalid version format: $VERSION"
        exit 1
    fi

    if ! ./bin/generate_keys --account {{sparkle_key_account}} -p >/dev/null 2>&1; then
        echo "Missing Sparkle key for account '{{sparkle_key_account}}'. Run: just sparkle-keygen"
        exit 1
    fi

    if ! git diff --quiet || ! git diff --cached --quiet; then
        echo "You have uncommitted changes. Commit or stash them before releasing."
        exit 1
    fi

    for tool in just gh create-dmg; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            echo "Required tool not found: $tool"
            exit 1
        fi
    done

    if ! gh auth status -h github.com >/dev/null 2>&1; then
        echo "GitHub CLI is not authenticated. Run: gh auth login"
        exit 1
    fi

    if gh release view "${TAG}" --repo "{{github_repo}}" >/dev/null 2>&1; then
        echo "GitHub release already exists: ${TAG}"
        exit 1
    fi

    if [ ! -f "${NOTES_PATH}" ]; then
        just release-notes "${VERSION}"
        echo "Draft release notes created at ${NOTES_PATH}. Review them and rerun just release ${VERSION}."
        exit 1
    fi

    if grep -q "TODO" "${NOTES_PATH}"; then
        echo "Release notes still contain TODO markers: ${NOTES_PATH}"
        exit 1
    fi

    CURRENT_VERSION=$(grep 'MARKETING_VERSION = ' {{xcode_project}}/project.pbxproj | head -1 | sed 's/.*= \(.*\);/\1/')
    CURRENT_BUILD=$(grep 'CURRENT_PROJECT_VERSION = ' {{xcode_project}}/project.pbxproj | head -1 | sed 's/.*= \(.*\);/\1/')

    if [ "$CURRENT_VERSION" != "$VERSION" ]; then
        NEXT_BUILD=$((CURRENT_BUILD + 1))
        sed -i '' "s/MARKETING_VERSION = ${CURRENT_VERSION};/MARKETING_VERSION = ${VERSION};/g" {{xcode_project}}/project.pbxproj
        sed -i '' "s/CURRENT_PROJECT_VERSION = ${CURRENT_BUILD};/CURRENT_PROJECT_VERSION = ${NEXT_BUILD};/g" {{xcode_project}}/project.pbxproj
        git add {{xcode_project}}/project.pbxproj
        git commit -m "chore: bump version to ${VERSION} (build ${NEXT_BUILD})"
    fi

    just test
    just dmg
    just notarize "${DMG_PATH}"
    just staple "${DMG_PATH}"
    just appcast "${DMG_PATH}"

    if ! git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null 2>&1; then
        git tag -a "${TAG}" -m "Release ${TAG}"
    fi

    gh release create "${TAG}" "${DMG_PATH}" "${APPCAST_PATH}" \
        --repo "{{github_repo}}" \
        --title "${RELEASE_TITLE}" \
        --notes-file "${NOTES_PATH}" \
        "${RELEASE_FLAGS[@]}"

check-tools:
    @command -v xcodebuild >/dev/null 2>&1 || echo "xcodebuild not found"
    @command -v create-dmg >/dev/null 2>&1 || echo "create-dmg not found (brew install create-dmg)"
    @command -v gh >/dev/null 2>&1 || echo "gh not found"

show-settings:
    xcodebuild -project {{xcode_project}} -scheme {{scheme}} -showBuildSettings

version:
    @echo "Marketing version:" && @grep 'MARKETING_VERSION = ' {{xcode_project}}/project.pbxproj | head -1
    @echo "Build number:" && @grep 'CURRENT_PROJECT_VERSION = ' {{xcode_project}}/project.pbxproj | head -1
