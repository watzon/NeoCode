# Translation Workflow for NeoCode

This project uses Xcode's String Catalog (`.xcstrings`) format with XLIFF export/import for managing translations across multiple languages.

## Supported Languages

- English (en) - Source language
- Spanish (es) - Translated
- Portuguese (pt) - In progress
- French (fr) - In progress
- Italian (it) - In progress

## Directory Structure

```
Localizations/
├── pt.xcloc/                    # Portuguese localization bundle
│   └── Localized Contents/
│       └── pt.xliff            # XLIFF file for Portuguese
├── fr.xcloc/                    # French localization bundle
│   └── Localized Contents/
│       └── fr.xliff            # XLIFF file for French
└── it.xcloc/                    # Italian localization bundle
    └── Localized Contents/
        └── it.xliff            # XLIFF file for Italian
```

## Workflow

### 1. Export Localizations

When you add new strings to the app or want to update translation files:

```bash
./export_localizations.sh
```

This exports all localizations to XLIFF format in the `Localizations/` directory.

### 2. Translate

You have several options for translating:

#### Option A: Edit XLIFF files directly

Open the `.xliff` files in the `Localizations/` directory and fill in the `<target>` elements:

```xml
<trans-unit id="Add project" xml:space="preserve">
  <source>Add project</source>
  <target state="translated">Adicionar projeto</target>
  <note/>
</trans-unit>
```

**Important:**
- Change `state="new"` to `state="translated"` when done
- Preserve placeholders like `%1$@`, `%2$@`, `%lld`, etc.
- Maintain the same structure and attributes

#### Option B: Use Xcode XLIFF Editor

Double-click any `.xcloc` bundle to open it in Xcode's built-in XLIFF editor.

#### Option C: Use Translation Management Tools

The XLIFF format is an industry standard. You can:
- Upload to translation services (Crowdin, Transifex, etc.)
- Use CAT tools (OmegaT, memoQ, etc.)
- Process programmatically

### 3. Import Localizations

After translating, merge the changes back to the `.xcstrings` file:

```bash
./import_localizations.sh
```

This updates `NeoCode/Localization/Localizable.xcstrings` with the new translations.

### 4. Verify

Build the project to ensure everything compiles:

```bash
xcodebuild build -project "NeoCode.xcodeproj" -scheme "NeoCode" -destination 'platform=macOS'
```

## Adding a New Language

1. Add the language case to `NeoCodeAppLanguage` enum in `NeoCode/AppLocalization.swift`
2. Add the language name key to `Localizable.xcstrings` (e.g., "Portuguese", "French", "Italian")
3. Run `./export_localizations.sh` with the new language
4. Translate the XLIFF file
5. Run `./import_localizations.sh`

## Checking Translation Status

Count untranslated strings:

```bash
# For Portuguese
grep -c '<target state="new"/>' Localizations/pt.xcloc/Localized\ Contents/pt.xliff

# List untranslated keys
grep -B1 'state="new"' Localizations/pt.xcloc/Localized\ Contents/pt.xliff | grep 'trans-unit id'
```

## Translation Guidelines

1. **Preserve placeholders**: Keep `%@`, `%1$@`, `%2$@`, `%lld` exactly as they appear
2. **Maintain state**: Set `state="translated"` when done, leave as `state="new"` for untranslated
3. **Context matters**: Check the `<note>` element for context (when available)
4. **Consistency**: Use consistent terminology across all strings
5. **Test**: Always test translations in the app for layout issues

## Current Status

| Language | Total Strings | Translated | Status |
|----------|---------------|------------|--------|
| English  | 288           | 288        | Source |
| Spanish  | 288           | ~280       | Active |
| Portuguese | 288         | 3          | In Progress |
| French   | 288           | 3          | In Progress |
| Italian  | 288           | 3          | In Progress |

## Notes

- The `.xcstrings` file is the source of truth
- XLIFF files are generated from `.xcstrings`
- Always run export before editing translations
- Always run import after completing translations
- Commit both `.xcstrings` and `Localizations/` changes
