#!/bin/zsh
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: $0 <app_path> <output_dir> [version]" >&2
  exit 1
fi

APP_INPUT="${1:-./FinderCut.app}"
OUTPUT_INPUT="$2"

if [[ ! -d "$APP_INPUT" ]]; then
  echo "Error: app bundle not found: $APP_INPUT" >&2
  exit 1
fi

mkdir -p "$OUTPUT_INPUT"
APP_PATH="$(cd "$APP_INPUT" && pwd)"
OUTPUT_DIR="$(cd "$OUTPUT_INPUT" && pwd)"
INFO_PLIST="$APP_PATH/Contents/Info.plist"
ICON_PATH="$APP_PATH/Contents/Resources/AppIcon.icns"
BINARY_PATH="$APP_PATH/Contents/MacOS/FinderCut"

if [[ ! -f "$INFO_PLIST" ]]; then
  echo "Error: missing Info.plist in $APP_PATH" >&2
  exit 1
fi
if [[ ! -f "$ICON_PATH" ]]; then
  echo "Error: missing AppIcon.icns in $APP_PATH" >&2
  exit 1
fi
if [[ ! -x "$BINARY_PATH" ]]; then
  echo "Error: missing executable in $APP_PATH" >&2
  exit 1
fi

VERSION="${3:-$(plutil -extract CFBundleShortVersionString raw -o - "$INFO_PLIST")}"
if [[ -z "$VERSION" ]]; then
  echo "Error: could not determine bundle version" >&2
  exit 1
fi

echo "Verifying app bundle signature and minimum OS target..."
codesign --verify --deep --strict "$APP_PATH"
build_version_info="$(otool -l "$BINARY_PATH" | grep -A 3 LC_BUILD_VERSION || true)"
if [[ "$build_version_info" != *"minos 13.0"* ]]; then
  echo "Error: Mach-O binary does not target minos 13.0" >&2
  echo "$build_version_info" >&2
  exit 1
fi

VOL_NAME="FinderCut $VERSION"
if [[ -e "/Volumes/$VOL_NAME" ]]; then
  echo "Error: volume already mounted at /Volumes/$VOL_NAME; detach it first" >&2
  exit 1
fi

WORK_DIR="$(mktemp -d)"
STAGE_DIR="$WORK_DIR/stage"
VERIFY_MNT="$WORK_DIR/verify"
RW_DMG="$WORK_DIR/temp-rw.dmg"
DMG_NAME="FinderCut-v${VERSION}-arm64.dmg"
DMG_PATH="$OUTPUT_DIR/$DMG_NAME"
SHA_PATH="$DMG_PATH.sha256"
RW_DEVICE=""
VERIFY_DEVICE=""

detach_if_needed() {
  local dev="$1"
  if [[ -n "$dev" ]]; then
    hdiutil detach "$dev" >/dev/null 2>&1 || hdiutil detach -force "$dev" >/dev/null 2>&1 || true
  fi
}

cleanup() {
  detach_if_needed "$VERIFY_DEVICE"
  detach_if_needed "$RW_DEVICE"
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

mkdir -p "$STAGE_DIR/.background" "$VERIFY_MNT"
ditto "$APP_PATH" "$STAGE_DIR/FinderCut.app"
ln -s /Applications "$STAGE_DIR/Applications"

echo "Generating Retina drag-to-Applications background..."
swift - "$WORK_DIR/bg_1x.png" "$WORK_DIR/bg_2x.png" <<'SWIFT'
import AppKit

let out1x = CommandLine.arguments[1]
let out2x = CommandLine.arguments[2]
let logicalSize = NSSize(width: 600, height: 380)

func renderBackground(scale: CGFloat, to path: String) throws {
    let pixelW = Int(logicalSize.width * scale)
    let pixelH = Int(logicalSize.height * scale)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelW,
        pixelsHigh: pixelH,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("Failed to allocate bitmap")
    }
    rep.size = logicalSize

    NSGraphicsContext.saveGraphicsState()
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
        fatalError("Failed to create graphics context")
    }
    NSGraphicsContext.current = ctx

    let rect = NSRect(origin: .zero, size: logicalSize)
    let gradient = NSGradient(
        starting: NSColor(calibratedRed: 0.969, green: 0.973, blue: 0.980, alpha: 1.0),
        ending: NSColor(calibratedRed: 0.925, green: 0.937, blue: 0.957, alpha: 1.0)
    )
    gradient?.draw(in: rect, angle: -90)

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center

    let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 17, weight: .semibold),
        .foregroundColor: NSColor(calibratedWhite: 0.14, alpha: 1.0),
        .paragraphStyle: paragraph
    ]
    NSString(string: "FinderCut").draw(
        in: NSRect(x: 40, y: 318, width: 520, height: 24),
        withAttributes: titleAttrs
    )

    let subAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12, weight: .regular),
        .foregroundColor: NSColor(calibratedWhite: 0.42, alpha: 1.0),
        .paragraphStyle: paragraph
    ]
    NSString(string: "Drag FinderCut into Applications").draw(
        in: NSRect(x: 40, y: 296, width: 520, height: 18),
        withAttributes: subAttrs
    )

    // Draw centered directional arrow between left icon (x=165) and right icon (x=435).
    // Finder icon position y=200 (from top) aligns with ~y=190 in AppKit bottom-left coordinates.
    let arrowY: CGFloat = 190
    let startX: CGFloat = 266
    let endX: CGFloat = 334
    let headSize: CGFloat = 10

    let arrow = NSBezierPath()
    arrow.lineWidth = 3.0
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.move(to: NSPoint(x: startX, y: arrowY))
    arrow.line(to: NSPoint(x: endX, y: arrowY))
    arrow.move(to: NSPoint(x: endX - headSize, y: arrowY + headSize))
    arrow.line(to: NSPoint(x: endX, y: arrowY))
    arrow.line(to: NSPoint(x: endX - headSize, y: arrowY - headSize))

    NSColor(calibratedRed: 0.431, green: 0.463, blue: 0.506, alpha: 0.85).setStroke()
    arrow.stroke()

    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("Failed to encode PNG")
    }
    try png.write(to: URL(fileURLWithPath: path))
}

try renderBackground(scale: 1.0, to: out1x)
try renderBackground(scale: 2.0, to: out2x)
SWIFT

tiffutil -cathidpicheck "$WORK_DIR/bg_1x.png" "$WORK_DIR/bg_2x.png" -out "$STAGE_DIR/.background/bg.tiff"

echo "Creating writable HFS+ disk image..."
hdiutil create -volname "$VOL_NAME" -srcfolder "$STAGE_DIR" -fs HFS+ -format UDRW -ov "$RW_DMG" >/dev/null
hdiutil resize -size 32m "$RW_DMG" >/dev/null

ATTACH_PLIST="$WORK_DIR/attach.plist"
hdiutil attach -readwrite -noverify -noautoopen -plist "$RW_DMG" > "$ATTACH_PLIST"

eval "$(python3 - "$ATTACH_PLIST" <<'PY'
import plistlib, shlex, sys

with open(sys.argv[1], "rb") as f:
    data = plistlib.load(f)

device = ""
mount_point = ""
for ent in data.get("system-entities", []):
    mp = ent.get("mount-point")
    if mp:
        device = ent.get("dev-entry", "")
        mount_point = mp
        break

if not device or not mount_point:
    raise SystemExit("Failed to find mounted writable volume device/mount-point")

print(f"RW_DEVICE={shlex.quote(device)}")
print(f"MOUNT_DIR={shlex.quote(mount_point)}")
PY
)"

DISK_NAME="$(basename "$MOUNT_DIR")"
echo "Configuring Finder window layout and volume icon on $MOUNT_DIR..."

osascript - "$DISK_NAME" "$MOUNT_DIR" <<'APPLESCRIPT'
on run argv
    set diskName to item 1 of argv
    set mountPath to item 2 of argv
    set bgAlias to POSIX file (mountPath & "/.background/bg.tiff")

    tell application "Finder"
        tell disk diskName
            open
            delay 0.5
            set current view of container window to icon view
            set toolbar visible of container window to false
            set statusbar visible of container window to false
            set the bounds of container window to {200, 200, 800, 608}

            set viewOptions to the icon view options of container window
            set arrangement of viewOptions to not arranged
            set icon size of viewOptions to 108
            set text size of viewOptions to 13
            set background picture of viewOptions to bgAlias

            set position of item "FinderCut.app" of container window to {165, 200}
            set position of item "Applications" of container window to {435, 200}

            close
            open
            update without registering applications
            delay 2
            close
        end tell
    end tell
end run
APPLESCRIPT

/usr/bin/SetFile -a V "$MOUNT_DIR/.background"
cp "$ICON_PATH" "$MOUNT_DIR/.VolumeIcon.icns"
/usr/bin/SetFile -a V "$MOUNT_DIR/.VolumeIcon.icns"
/usr/bin/SetFile -a C "$MOUNT_DIR"
sync

if [[ ! -f "$MOUNT_DIR/.DS_Store" ]]; then
  echo "Error: Finder layout did not generate .DS_Store inside DMG" >&2
  exit 1
fi
if [[ ! -f "$MOUNT_DIR/.VolumeIcon.icns" ]]; then
  echo "Error: missing .VolumeIcon.icns on writable DMG mount" >&2
  exit 1
fi

detached=0
for i in 1 2 3 4 5; do
  if hdiutil detach "$RW_DEVICE" >/dev/null 2>&1; then
    detached=1
    RW_DEVICE=""
    break
  fi
  sleep 1
done
if [[ "$detached" -ne 1 ]]; then
  echo "Error: failed to cleanly detach writable DMG device $RW_DEVICE" >&2
  exit 1
fi

echo "Converting to compressed UDZO DMG: $DMG_PATH..."
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -ov -o "$DMG_PATH" >/dev/null
hdiutil verify "$DMG_PATH"

echo "Verifying final read-only DMG contents..."
VERIFY_PLIST="$WORK_DIR/verify.plist"
hdiutil attach -nobrowse -readonly -noautoopen -mountpoint "$VERIFY_MNT" -plist "$DMG_PATH" > "$VERIFY_PLIST"
VERIFY_DEVICE="$(python3 - "$VERIFY_PLIST" <<'PY'
import plistlib, sys
with open(sys.argv[1], "rb") as f:
    data = plistlib.load(f)
for ent in data.get("system-entities", []):
    if ent.get("mount-point"):
        print(ent.get("dev-entry", ""))
        break
PY
)"
if [[ -z "$VERIFY_DEVICE" ]]; then
  echo "Error: failed to determine mounted verification device from $VERIFY_PLIST" >&2
  cat "$VERIFY_PLIST" >&2 || true
  exit 1
fi

for req_file in ".VolumeIcon.icns" ".DS_Store" ".background/bg.tiff"; do
  if [[ ! -f "$VERIFY_MNT/$req_file" ]]; then
    echo "Error: missing required DMG file: $req_file" >&2
    ls -la "$VERIFY_MNT" >&2 || true
    exit 1
  fi
done
if [[ ! -L "$VERIFY_MNT/Applications" ]]; then
  echo "Error: missing Applications symlink in DMG" >&2
  ls -la "$VERIFY_MNT" >&2 || true
  exit 1
fi

if command -v GetFileInfo >/dev/null 2>&1; then
  attrs="$(GetFileInfo -a "$VERIFY_MNT" || true)"
  if [[ "$attrs" != *C* ]]; then
    echo "Error: custom volume icon attribute (C) missing on DMG root (got: '$attrs')" >&2
    exit 1
  fi
fi

codesign --verify --deep --strict "$VERIFY_MNT/FinderCut.app"
mounted_ver="$(plutil -extract CFBundleShortVersionString raw -o - "$VERIFY_MNT/FinderCut.app/Contents/Info.plist")"
if [[ "$mounted_ver" != "$VERSION" ]]; then
  echo "Error: mounted Info.plist version '$mounted_ver' != expected '$VERSION'" >&2
  exit 1
fi
mounted_build_ver="$(otool -l "$VERIFY_MNT/FinderCut.app/Contents/MacOS/FinderCut" | grep -A 3 LC_BUILD_VERSION || true)"
if [[ "$mounted_build_ver" != *"minos 13.0"* ]]; then
  echo "Error: mounted binary does not target minos 13.0" >&2
  echo "$mounted_build_ver" >&2
  exit 1
fi

hdiutil detach "$VERIFY_DEVICE" >/dev/null
VERIFY_DEVICE=""

(cd "$OUTPUT_DIR" && shasum -a 256 "$DMG_NAME" > "${DMG_NAME}.sha256")
echo "Packaged and verified successfully:"
echo "  DMG:    $DMG_PATH"
echo "  SHA256: $(cat "$SHA_PATH")"
