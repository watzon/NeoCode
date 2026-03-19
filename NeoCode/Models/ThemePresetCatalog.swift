import Foundation

enum NeoCodeThemePresetCatalog {
    private static let decodedPresets: ([NeoCodeThemePreset], String?) = {
        let data = Data(json.utf8)

        do {
            return (try JSONDecoder().decode([NeoCodeThemePreset].self, from: data), nil)
        } catch {
            return ([], String(describing: error))
        }
    }()

    static let presets: [NeoCodeThemePreset] = decodedPresets.0
    static let decodeFailureDescription: String? = decodedPresets.1

    static func presets(for kind: ThemeProfileKind) -> [NeoCodeThemePreset] {
        presets.filter { $0.theme(for: kind) != nil }
    }

    private static let json = #"""
    [
      {
        "id": "absolutely",
        "title": "Absolutely",
        "badgeText": "Aa",
        "badgeBackgroundHex": "#f9f9f7",
        "badgeForegroundHex": "#cc7d5e",
        "lightTheme": {
          "accentHex": "#cc7d5e",
          "backgroundHex": "#f9f9f7",
          "foregroundHex": "#2d2d2b",
          "contrast": 45,
          "isSidebarTranslucent": true,
          "diffAddedHex": "#00c853",
          "diffRemovedHex": "#ff5f38",
          "skillHex": "#cc7d5e",
          "uiFontName": "SF Pro",
          "codeFontName": "SF Mono"
        },
        "darkTheme": {
          "accentHex": "#cc7d5e",
          "backgroundHex": "#2d2d2b",
          "foregroundHex": "#f9f9f7",
          "contrast": 60,
          "isSidebarTranslucent": true,
          "diffAddedHex": "#00c853",
          "diffRemovedHex": "#ff5f38",
          "skillHex": "#cc7d5e",
          "uiFontName": "SF Pro",
          "codeFontName": "SF Mono"
        }
      },
      {
        "id": "ayu",
        "title": "Ayu",
        "badgeText": "Aa",
        "badgeBackgroundHex": "#0b0e14",
        "badgeForegroundHex": "#e6b450",
        "darkTheme": {
          "accentHex": "#e6b450",
          "backgroundHex": "#0b0e14",
          "foregroundHex": "#bfbdb6",
          "contrast": 60,
          "isSidebarTranslucent": true,
          "diffAddedHex": "#7fd962",
          "diffRemovedHex": "#ea6c73",
          "skillHex": "#cda1fa",
          "uiFontName": "SF Pro",
          "codeFontName": "SF Mono"
        }
      },
      {
        "id": "catppuccin",
        "title": "Catppuccin",
        "badgeText": "Aa",
        "badgeBackgroundHex": "#eff1f5",
        "badgeForegroundHex": "#8839ef",
        "lightTheme": {
          "accentHex": "#8839ef",
          "backgroundHex": "#eff1f5",
          "foregroundHex": "#4c4f69",
          "contrast": 45,
          "isSidebarTranslucent": true,
          "diffAddedHex": "#40a02b",
          "diffRemovedHex": "#d20f39",
          "skillHex": "#8839ef",
          "uiFontName": "SF Pro",
          "codeFontName": "SF Mono"
        },
        "darkTheme": {
          "accentHex": "#cba6f7",
          "backgroundHex": "#1e1e2e",
          "foregroundHex": "#cdd6f4",
          "contrast": 60,
          "isSidebarTranslucent": true,
          "diffAddedHex": "#a6e3a1",
          "diffRemovedHex": "#f38ba8",
          "skillHex": "#cba6f7",
          "uiFontName": "SF Pro",
          "codeFontName": "SF Mono"
        }
      },
      {
        "id": "codex",
        "title": "Codex",
        "badgeText": "Aa",
        "badgeBackgroundHex": "#ffffff",
        "badgeForegroundHex": "#0169cc",
        "lightTheme": {
          "accentHex": "#0169cc",
          "backgroundHex": "#ffffff",
          "foregroundHex": "#0d0d0d",
          "contrast": 45,
          "isSidebarTranslucent": true,
          "diffAddedHex": "#00a240",
          "diffRemovedHex": "#e02e2a",
          "skillHex": "#751ed9",
          "uiFontName": "SF Pro",
          "codeFontName": "SF Mono"
        },
        "darkTheme": {
          "accentHex": "#0169cc",
          "backgroundHex": "#111111",
          "foregroundHex": "#fcfcfc",
          "contrast": 60,
          "isSidebarTranslucent": true,
          "diffAddedHex": "#00a240",
          "diffRemovedHex": "#e02e2a",
          "skillHex": "#b06dff",
          "uiFontName": "SF Pro",
          "codeFontName": "SF Mono"
        }
      },
      {
        "id": "dracula",
        "title": "Dracula",
        "badgeText": "Aa",
        "badgeBackgroundHex": "#282a36",
        "badgeForegroundHex": "#ff79c6",
        "darkTheme": {
          "accentHex": "#ff79c6",
          "backgroundHex": "#282a36",
          "foregroundHex": "#f8f8f2",
          "contrast": 60,
          "isSidebarTranslucent": true,
          "diffAddedHex": "#50fa7b",
          "diffRemovedHex": "#ff5555",
          "skillHex": "#ff79c6",
          "uiFontName": "SF Pro",
          "codeFontName": "SF Mono"
        }
      },
      {
        "id": "everforest",
        "title": "Everforest",
        "badgeText": "Aa",
        "badgeBackgroundHex": "#fdf6e3",
        "badgeForegroundHex": "#93b259",
        "lightTheme": {
          "accentHex": "#93b259",
          "backgroundHex": "#fdf6e3",
          "foregroundHex": "#5c6a72",
          "contrast": 45,
          "isSidebarTranslucent": true,
          "diffAddedHex": "#8da101",
          "diffRemovedHex": "#f85552",
          "skillHex": "#df69ba",
          "uiFontName": "SF Pro",
          "codeFontName": "SF Mono"
        },
        "darkTheme": {
          "accentHex": "#a7c080",
          "backgroundHex": "#2d353b",
          "foregroundHex": "#d3c6aa",
          "contrast": 60,
          "isSidebarTranslucent": true,
          "diffAddedHex": "#a7c080",
          "diffRemovedHex": "#e67e80",
          "skillHex": "#d699b6",
          "uiFontName": "SF Pro",
          "codeFontName": "SF Mono"
        }
      },
      {
        "id": "github",
        "title": "GitHub",
        "badgeText": "Aa",
        "badgeBackgroundHex": "#ffffff",
        "badgeForegroundHex": "#0969da",
        "lightTheme": {
          "accentHex": "#0969da",
          "backgroundHex": "#ffffff",
          "foregroundHex": "#1f2328",
          "contrast": 45,
          "isSidebarTranslucent": true,
          "diffAddedHex": "#1a7f37",
          "diffRemovedHex": "#cf222e",
          "skillHex": "#8250df",
          "uiFontName": "SF Pro",
          "codeFontName": "SF Mono"
        },
        "darkTheme": {
          "accentHex": "#1f6feb",
          "backgroundHex": "#0d1117",
          "foregroundHex": "#e6edf3",
          "contrast": 60,
          "isSidebarTranslucent": true,
          "diffAddedHex": "#3fb950",
          "diffRemovedHex": "#f85149",
          "skillHex": "#bc8cff",
          "uiFontName": "SF Pro",
          "codeFontName": "SF Mono"
        }
      },
      {
        "id": "gruvbox",
        "title": "Gruvbox",
        "badgeText": "Aa",
        "badgeBackgroundHex": "#fbf1c7",
        "badgeForegroundHex": "#458588",
        "lightTheme": {
          "accentHex": "#458588",
          "backgroundHex": "#fbf1c7",
          "foregroundHex": "#3c3836",
          "contrast": 45,
          "isSidebarTranslucent": true,
          "diffAddedHex": "#3c3836",
          "diffRemovedHex": "#cc241d",
          "skillHex": "#b16286",
          "uiFontName": "SF Pro",
          "codeFontName": "SF Mono"
        },
        "darkTheme": {
          "accentHex": "#458588",
          "backgroundHex": "#282828",
          "foregroundHex": "#ebdbb2",
          "contrast": 60,
          "isSidebarTranslucent": true,
          "diffAddedHex": "#ebdbb2",
          "diffRemovedHex": "#cc241d",
          "skillHex": "#b16286",
          "uiFontName": "SF Pro",
          "codeFontName": "SF Mono"
        }
      },
      {
        "id": "linear",
        "title": "Linear",
        "badgeText": "Aa",
        "badgeBackgroundHex": "#f7f8fa",
        "badgeForegroundHex": "#5e6ad2",
        "lightTheme": {
          "accentHex": "#5e6ad2",
          "backgroundHex": "#f7f8fa",
          "foregroundHex": "#2a3140",
          "contrast": 45,
          "isSidebarTranslucent": false,
          "diffAddedHex": "#00a240",
          "diffRemovedHex": "#ba2623",
          "skillHex": "#8160d8",
          "uiFontName": "Inter",
          "codeFontName": "SF Mono"
        },
        "darkTheme": {
          "accentHex": "#5e6ad2",
          "backgroundHex": "#17181d",
          "foregroundHex": "#e6e9ef",
          "contrast": 60,
          "isSidebarTranslucent": false,
          "diffAddedHex": "#7ad9c0",
          "diffRemovedHex": "#fa423e",
          "skillHex": "#c2a1ff",
          "uiFontName": "Inter",
          "codeFontName": "SF Mono"
        }
      },
      {
        "id": "lobster",
        "title": "Lobster",
        "badgeText": "Aa",
        "badgeBackgroundHex": "#111827",
        "badgeForegroundHex": "#ff5c5c",
        "darkTheme": {
          "accentHex": "#ff5c5c",
          "backgroundHex": "#111827",
          "foregroundHex": "#e4e4e7",
          "contrast": 60,
          "isSidebarTranslucent": false,
          "diffAddedHex": "#22c55e",
          "diffRemovedHex": "#ff5c5c",
          "skillHex": "#3b82f6",
          "uiFontName": "Satoshi",
          "codeFontName": "SF Mono"
        }
      },
      {
        "id": "material",
        "title": "Material",
        "badgeText": "Aa",
        "badgeBackgroundHex": "#212121",
        "badgeForegroundHex": "#80cbc4",
        "darkTheme": {
          "accentHex": "#80cbc4",
          "backgroundHex": "#212121",
          "foregroundHex": "#eeffff",
          "contrast": 60,
          "isSidebarTranslucent": false,
          "diffAddedHex": "#c3e88d",
          "diffRemovedHex": "#f07178",
          "skillHex": "#c792ea",
          "uiFontName": "Satoshi",
          "codeFontName": "SF Mono"
        }
      },
      {
        "id": "maple",
        "title": "Maple",
        "badgeText": "Aa",
        "badgeBackgroundHex": "#15120F",
        "badgeForegroundHex": "#E8872B",
        "darkTheme": {
          "accentHex": "#E8872B",
          "backgroundHex": "#15120F",
          "foregroundHex": "#E8E0D6",
          "contrast": 77,
          "isSidebarTranslucent": false,
          "diffAddedHex": "#54B47C",
          "diffRemovedHex": "#D68642",
          "skillHex": "#E8872B",
          "uiFontName": "SF Pro",
          "codeFontName": "SF Mono"
        }
      },
      {
        "id": "matrix",
        "title": "Matrix",
        "badgeText": "Aa",
        "badgeBackgroundHex": "#040805",
        "badgeForegroundHex": "#1eff5a",
        "darkTheme": {
          "accentHex": "#1eff5a",
          "backgroundHex": "#040805",
          "foregroundHex": "#b8ffca",
          "contrast": 60,
          "isSidebarTranslucent": false,
          "diffAddedHex": "#1eff5a",
          "diffRemovedHex": "#fa423e",
          "skillHex": "#1eff5a",
          "uiFontName": "ui-monospace, \"SFMono-Regular\", \"SF Mono\", Menlo, Consolas, \"Liberation Mono\", monospace",
          "codeFontName": "SF Mono"
        }
      },
      {
        "id": "monokai",
        "title": "Monokai",
        "badgeText": "Aa",
        "badgeBackgroundHex": "#272822",
        "badgeForegroundHex": "#99947c",
        "darkTheme": {
          "accentHex": "#99947c",
          "backgroundHex": "#272822",
          "foregroundHex": "#f8f8f2",
          "contrast": 60,
          "isSidebarTranslucent": false,
          "diffAddedHex": "#86b42b",
          "diffRemovedHex": "#c4265e",
          "skillHex": "#8c6bc8",
          "uiFontName": "ui-monospace, \"SFMono-Regular\", \"SF Mono\", Menlo, Consolas, \"Liberation Mono\", monospace",
          "codeFontName": "SF Mono"
        }
      },
      {
        "id": "night-owl",
        "title": "Night Owl",
        "badgeText": "Aa",
        "badgeBackgroundHex": "#011627",
        "badgeForegroundHex": "#44596b",
        "darkTheme": {
          "accentHex": "#44596b",
          "backgroundHex": "#011627",
          "foregroundHex": "#d6deeb",
          "contrast": 60,
          "isSidebarTranslucent": false,
          "diffAddedHex": "#c5e478",
          "diffRemovedHex": "#ef5350",
          "skillHex": "#c792ea",
          "uiFontName": "ui-monospace, \"SFMono-Regular\", \"SF Mono\", Menlo, Consolas, \"Liberation Mono\", monospace",
          "codeFontName": "SF Mono"
        }
      },
      {
        "id": "nord",
        "title": "Nord",
        "badgeText": "Aa",
        "badgeBackgroundHex": "#2e3440",
        "badgeForegroundHex": "#88c0d0",
        "darkTheme": {
          "accentHex": "#88c0d0",
          "backgroundHex": "#2e3440",
          "foregroundHex": "#d8dee9",
          "contrast": 60,
          "isSidebarTranslucent": false,
          "diffAddedHex": "#a3be8c",
          "diffRemovedHex": "#bf616a",
          "skillHex": "#b48ead",
          "uiFontName": "ui-monospace, \"SFMono-Regular\", \"SF Mono\", Menlo, Consolas, \"Liberation Mono\", monospace",
          "codeFontName": "SF Mono"
        }
      },
      {
        "id": "notion",
        "title": "Notion",
        "badgeText": "Aa",
        "badgeBackgroundHex": "#ffffff",
        "badgeForegroundHex": "#3183d8",
        "lightTheme": {
          "accentHex": "#3183d8",
          "backgroundHex": "#ffffff",
          "foregroundHex": "#37352f",
          "contrast": 45,
          "isSidebarTranslucent": false,
          "diffAddedHex": "#008000",
          "diffRemovedHex": "#a31515",
          "skillHex": "#0000ff",
          "uiFontName": "SF Pro",
          "codeFontName": "SF Mono"
        },
        "darkTheme": {
          "accentHex": "#3183d8",
          "backgroundHex": "#191919",
          "foregroundHex": "#d9d9d8",
          "contrast": 60,
          "isSidebarTranslucent": false,
          "diffAddedHex": "#4ec9b0",
          "diffRemovedHex": "#fa423e",
          "skillHex": "#3183d8",
          "uiFontName": "SF Pro",
          "codeFontName": "SF Mono"
        }
      },
      {
        "id": "one",
        "title": "One",
        "badgeText": "Aa",
        "badgeBackgroundHex": "#fafafa",
        "badgeForegroundHex": "#526fff",
        "lightTheme": {
          "accentHex": "#526fff",
          "backgroundHex": "#fafafa",
          "foregroundHex": "#383a42",
          "contrast": 45,
          "isSidebarTranslucent": false,
          "diffAddedHex": "#3bba54",
          "diffRemovedHex": "#e45649",
          "skillHex": "#526fff",
          "uiFontName": "SF Pro",
          "codeFontName": "SF Mono"
        },
        "darkTheme": {
          "accentHex": "#4d78cc",
          "backgroundHex": "#282c34",
          "foregroundHex": "#abb2bf",
          "contrast": 60,
          "isSidebarTranslucent": false,
          "diffAddedHex": "#8cc265",
          "diffRemovedHex": "#e05561",
          "skillHex": "#c162de",
          "uiFontName": "SF Pro",
          "codeFontName": "SF Mono"
        }
      },
      {
        "id": "oscurange",
        "title": "Oscurange",
        "badgeText": "Aa",
        "badgeBackgroundHex": "#0b0b0f",
        "badgeForegroundHex": "#f9b98c",
        "darkTheme": {
          "accentHex": "#f9b98c",
          "backgroundHex": "#0b0b0f",
          "foregroundHex": "#e6e6e6",
          "contrast": 60,
          "isSidebarTranslucent": false,
          "diffAddedHex": "#40c977",
          "diffRemovedHex": "#fa423e",
          "skillHex": "#479ffa",
          "uiFontName": "SF Pro",
          "codeFontName": "SF Mono"
        }
      },
      {
        "id": "proof",
        "title": "Proof",
        "badgeText": "Aa",
        "badgeBackgroundHex": "#f5f3ed",
        "badgeForegroundHex": "#3d755d",
        "lightTheme": {
          "accentHex": "#3d755d",
          "backgroundHex": "#f5f3ed",
          "foregroundHex": "#2f312d",
          "contrast": 45,
          "isSidebarTranslucent": true,
          "diffAddedHex": "#3d755d",
          "diffRemovedHex": "#ba2623",
          "skillHex": "#5f6ac2",
          "uiFontName": "SF Pro",
          "codeFontName": "SF Mono"
        }
      },
      {
        "id": "rose-pine",
        "title": "Rose Pine",
        "badgeText": "Aa",
        "badgeBackgroundHex": "#faf4ed",
        "badgeForegroundHex": "#d7827e",
        "lightTheme": {
          "accentHex": "#d7827e",
          "backgroundHex": "#faf4ed",
          "foregroundHex": "#575279",
          "contrast": 45,
          "isSidebarTranslucent": true,
          "diffAddedHex": "#56949f",
          "diffRemovedHex": "#797593",
          "skillHex": "#907aa9",
          "uiFontName": "SF Pro",
          "codeFontName": "SF Mono"
        },
        "darkTheme": {
          "accentHex": "#ea9a97",
          "backgroundHex": "#232136",
          "foregroundHex": "#e0def4",
          "contrast": 60,
          "isSidebarTranslucent": false,
          "diffAddedHex": "#9ccfd8",
          "diffRemovedHex": "#908caa",
          "skillHex": "#c4a7e7",
          "uiFontName": "SF Pro",
          "codeFontName": "SF Mono"
        }
      },
      {
        "id": "sentry",
        "title": "Sentry",
        "badgeText": "Aa",
        "badgeBackgroundHex": "#2d2935",
        "badgeForegroundHex": "#7055f6",
        "darkTheme": {
          "accentHex": "#7055f6",
          "backgroundHex": "#2d2935",
          "foregroundHex": "#e6dff9",
          "contrast": 60,
          "isSidebarTranslucent": false,
          "diffAddedHex": "#8ee6d7",
          "diffRemovedHex": "#fa423e",
          "skillHex": "#7055f6",
          "uiFontName": "SF Pro",
          "codeFontName": "SF Mono"
        }
      },
      {
        "id": "solarized",
        "title": "Solarized",
        "badgeText": "Aa",
        "badgeBackgroundHex": "#fdf6e3",
        "badgeForegroundHex": "#b58900",
        "lightTheme": {
          "accentHex": "#b58900",
          "backgroundHex": "#fdf6e3",
          "foregroundHex": "#657b83",
          "contrast": 45,
          "isSidebarTranslucent": true,
          "diffAddedHex": "#859900",
          "diffRemovedHex": "#dc322f",
          "skillHex": "#d33682",
          "uiFontName": "SF Pro",
          "codeFontName": "SF Mono"
        },
        "darkTheme": {
          "accentHex": "#d30102",
          "backgroundHex": "#002b36",
          "foregroundHex": "#839496",
          "contrast": 60,
          "isSidebarTranslucent": false,
          "diffAddedHex": "#859900",
          "diffRemovedHex": "#dc322f",
          "skillHex": "#d33682",
          "uiFontName": "SF Pro",
          "codeFontName": "SF Mono"
        }
      },
      {
        "id": "temple",
        "title": "Temple",
        "badgeText": "Aa",
        "badgeBackgroundHex": "#02120c",
        "badgeForegroundHex": "#e4f222",
        "darkTheme": {
          "accentHex": "#e4f222",
          "backgroundHex": "#02120c",
          "foregroundHex": "#c7e6da",
          "contrast": 60,
          "isSidebarTranslucent": false,
          "diffAddedHex": "#40c977",
          "diffRemovedHex": "#fa423e",
          "skillHex": "#e4f222",
          "uiFontName": "SF Pro",
          "codeFontName": "SF Mono"
        }
      },
      {
        "id": "tokyo-night",
        "title": "Tokyo Night",
        "badgeText": "Aa",
        "badgeBackgroundHex": "#1a1b26",
        "badgeForegroundHex": "#3d59a1",
        "darkTheme": {
          "accentHex": "#3d59a1",
          "backgroundHex": "#1a1b26",
          "foregroundHex": "#a9b1d6",
          "contrast": 60,
          "isSidebarTranslucent": false,
          "diffAddedHex": "#449dab",
          "diffRemovedHex": "#914c54",
          "skillHex": "#9d7cd8",
          "uiFontName": "SF Pro",
          "codeFontName": "SF Mono"
        }
      },
      {
        "id": "vscode-plus",
        "title": "VS Code Plus",
        "badgeText": "Aa",
        "badgeBackgroundHex": "#ffffff",
        "badgeForegroundHex": "#007acc",
        "lightTheme": {
          "accentHex": "#007acc",
          "backgroundHex": "#ffffff",
          "foregroundHex": "#000000",
          "contrast": 45,
          "isSidebarTranslucent": true,
          "diffAddedHex": "#008000",
          "diffRemovedHex": "#ee0000",
          "skillHex": "#0000ff",
          "uiFontName": "SF Pro",
          "codeFontName": "SF Mono"
        },
        "darkTheme": {
          "accentHex": "#007acc",
          "backgroundHex": "#1e1e1e",
          "foregroundHex": "#d4d4d4",
          "contrast": 60,
          "isSidebarTranslucent": false,
          "diffAddedHex": "#369432",
          "diffRemovedHex": "#f44747",
          "skillHex": "#000080",
          "uiFontName": "SF Pro",
          "codeFontName": "SF Mono"
        }
      }
    ]
    """#
}
