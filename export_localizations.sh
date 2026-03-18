#!/bin/bash
# Script to export localizations for new languages

PROJECT="NeoCode.xcodeproj"
LOCALIZATIONS_DIR="Localizations"

# Create localizations directory
mkdir -p "$LOCALIZATIONS_DIR"

# Export localizations for new languages
echo "Exporting localizations for Portuguese, French, and Italian..."
xcodebuild -exportLocalizations \
    -project "$PROJECT" \
    -localizationPath "$LOCALIZATIONS_DIR" \
    -exportLanguage pt \
    -exportLanguage fr \
    -exportLanguage it

echo "Export complete! Check $LOCALIZATIONS_DIR/ for .xcloc bundles"
echo ""
echo "Next steps:"
echo "1. Open each .xcloc bundle in Xcode or edit the .xliff files directly"
echo "2. Fill in <target> elements for untranslated strings"
echo "3. Change state=\"new\" to state=\"translated\""
echo "4. Run import_localizations.sh to merge back"
