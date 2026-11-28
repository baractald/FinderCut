# FinderCut

**English** | [简体中文](./README.zh-CN.md) | [Website](https://findercut.oneman.work)

A lightweight, zero-dependency native macOS menu bar utility that brings familiar **`⌘X` Cut → `⌘V` Move** file workflows to Finder.

## Features

- **Native Finder Move Engine**: Pressing `⌘X` triggers a standard copy and marks items as pending cut; pressing `⌘V` in the destination directory translates cleanly to Finder's native `⌥⌘V` (*Move Item Here*). Preserves native progress dialogs, conflict resolution, cross-volume moves, and `⌘Z` Undo—with zero Finder process injection and no SIP changes required.
- **Smart Input & Preview Bypass**: Automatically detects inline file renaming, search fields, Get Info tag fields (`AXTokenField`), password prompts (`AXSecureTextField`), sheets, and Quick Look preview windows so regular text cut/paste stays untouched. Any subsequent clipboard copy automatically invalidates the pending cut state.
- **Subtle Visual & Audio Feedback**: Native macOS 26+ Liquid Glass HUD overlay (with a rounded frosted glass fallback on macOS 13–15), gentle system sound confirmation, and hideable menu bar icon (reopen FinderCut anytime to bring it back)—all independently toggleable and persisted.
- **Multi-Language & Non-QWERTY Layout Support**: Ships with 8 languages (English, Simplified Chinese, Traditional Chinese, Japanese, Korean, French, German, Spanish), matching the system locale automatically with live menu bar switching, plus dynamic `X` / `C` / `V` key resolution via Carbon `TIS` / `UCKeyTranslate`.
- **Single-Instance Guard & Self-Healing**: Prevents duplicate instances from intercepting events twice, and monitors Accessibility permission and `CGEventTap` health periodically and after system wake.

## Requirements

- macOS 13.0 or later
- Apple Silicon (`arm64`)

## Install

### Homebrew (Recommended)

```zsh
brew install --cask baractald/tap/findercut
```

To upgrade later:

```zsh
brew upgrade --cask findercut
```

### Direct Download

Download the latest Apple Developer ID signed and Apple-notarized `FinderCut-v*.dmg` from [GitHub Releases](https://github.com/baractald/FinderCut/releases) or [findercut.oneman.work](https://findercut.oneman.work/), drag `FinderCut.app` into `/Applications/`, launch it, and grant permission under **System Settings → Privacy & Security → Accessibility** when prompted.

## Build from Source

```zsh
./build.sh
```

This compiles and signs `FinderCut.app` in the repository root. Drag or copy `FinderCut.app` into `/Applications/` and launch it.

## Usage

1. Select one or more files or folders in Finder (or on the Desktop) and press `⌘X`.
2. The menu bar icon displays `⌘X` (with optional HUD overlay and sound feedback).
3. Switch to the destination folder and press `⌘V` to move, or press `Esc` / click **Cancel Pending Cut** in the menu bar to abort.
4. If you choose **Hide Menu Bar Icon**, FinderCut keeps running in the background; open FinderCut again anytime via Spotlight, Launchpad, or `/Applications/FinderCut.app` to restore the menu bar icon.

## Project Structure

```text
FinderCut/
├── Sources/
│   ├── main.swift                   # App entry, single-instance guard & permission/wake monitor
│   ├── KeyInterceptor.swift         # CGEventTap interception & cut/move state machine
│   ├── KeyboardLayoutResolver.swift # Dynamic TIS/UCKeyTranslate shortcut key resolver
│   ├── FocusInspector.swift         # AXUIElement focus & window bypass checks
│   ├── HUDController.swift          # Liquid Glass / frosted HUD overlay & persisted toggle
│   ├── SoundFeedbackManager.swift   # Subtle sound feedback & persisted toggle
│   ├── MenuBarController.swift      # Status menu, toggles, language switcher & icon visibility
│   ├── LoginItemManager.swift       # SMAppService launch-at-login & Settings redirect
│   ├── SupportManager.swift         # Menu support action & sparse local reminder
│   ├── UpdateChecker.swift          # GitHub Release update checker (startup & manual)
│   ├── AboutWindowController.swift  # Native About window with version & quick actions
│   └── L10n.swift                   # Localization & persisted language preference
├── Resources/
│   ├── Info.plist                   # Bundle configuration (LSUIElement=true & localizations)
│   └── *.lproj/Localizable.strings  # Localized strings for 8 languages
├── docs/
│   ├── index.html                   # Single-file responsive product website
│   └── og-image.png                 # Social share preview card (1200x630)
├── wrangler.jsonc                   # Cloudflare Workers Static Assets & custom domain config
└── build.sh                         # swiftc build, bundle assembly & signing script
```
