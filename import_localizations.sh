#!/bin/bash
# Script to import localizations from XLIFF files

PROJECT="NeoCode.xcodeproj"
LOCALIZATIONS_DIR="Localizations"

# Import each language
echo "Importing Portuguese..."
xcodebuild -importLocalizations \
    -project "$PROJECT" \
    -localizationPath "$LOCALIZATIONS_DIR/pt.xcloc"

echo "Importing French..."
xcodebuild -importLocalizations \
    -project "$PROJECT" \
    -localizationPath "$LOCALIZATIONS_DIR/fr.xcloc"

echo "Importing Italian..."
xcodebuild -importLocalizations \
    -project "$PROJECT" \
    -localizationPath "$LOCALIZATIONS_DIR/it.xcloc"

echo "Import complete!"
