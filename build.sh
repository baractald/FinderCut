#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="FinderCut"
APP_BUNDLE="$SCRIPT_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

echo "Compiling $APP_NAME..."
swiftc \
  -swift-version 5 \
  -target arm64-apple-macos13.0 \
  -O \
  -framework AppKit \
  -framework Carbon \
  -framework CoreGraphics \
  -framework ApplicationServices \
  -framework ServiceManagement \
  "$SCRIPT_DIR/Sources/"*.swift \
  -o "$MACOS_DIR/$APP_NAME"

cp "$SCRIPT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"

for lproj in "$SCRIPT_DIR/Resources/"*.lproj; do
  cp -R "$lproj" "$RESOURCES_DIR/"
done

# Generate a clean Apple-style AppIcon.icns using AppKit + iconutil.
ICONSET_DIR="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET_DIR"
swift - "$ICONSET_DIR" <<'SWIFT'
import AppKit

let outDir = CommandLine.arguments[1]
let sizes: [(String, CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, px) in sizes {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(px),
        pixelsHigh: Int(px),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let rect = NSRect(x: 0, y: 0, width: px, height: px)
    let inset = px * 0.08
    let bgRect = rect.insetBy(dx: inset, dy: inset)
    let path = NSBezierPath(roundedRect: bgRect, xRadius: px * 0.22, yRadius: px * 0.22)

    let gradient = NSGradient(
        starting: NSColor(calibratedRed: 0.24, green: 0.25, blue: 0.28, alpha: 1.0),
        ending: NSColor(calibratedRed: 0.14, green: 0.15, blue: 0.17, alpha: 1.0)
    )
    gradient?.draw(in: path, angle: -90)

    NSColor.white.withAlphaComponent(0.15).setStroke()
    path.lineWidth = max(1, px * 0.015)
    path.stroke()

    let cfg = NSImage.SymbolConfiguration(pointSize: px * 0.44, weight: .regular)
    if let sym = NSImage(systemSymbolName: "scissors", accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg) {
        let tinted = NSImage(size: sym.size)
        tinted.lockFocus()
        NSColor.white.set()
        let symRect = NSRect(origin: .zero, size: sym.size)
        sym.draw(in: symRect)
        symRect.fill(using: .sourceAtop)
        tinted.unlockFocus()

        let drawRect = NSRect(
            x: (px - sym.size.width) / 2,
            y: (px - sym.size.height) / 2,
            width: sym.size.width,
            height: sym.size.height
        )
        tinted.draw(in: drawRect)
    }

    NSGraphicsContext.restoreGraphicsState()
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: outDir).appendingPathComponent(name))
}
SWIFT

iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"
rm -rf "$(dirname "$ICONSET_DIR")"

echo "Signing $APP_NAME.app (ad-hoc)..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo "Built successfully: $APP_BUNDLE"
