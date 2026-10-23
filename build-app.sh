#!/bin/bash
# VitalMac — .app paketleyici ve ad-hoc imzalayıcı.
# Kullanım: ./build-app.sh   (sonuç: ./VitalMac.app)
set -euo pipefail

APP_NAME="VitalMac"
EXEC_NAME="VitalMac"
BUNDLE_ID="com.hattat.vitalmac"
VERSION="1.0"
BUILD="1"

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"   # swift build paket kökünde çalışsın
APP_DIR="$ROOT/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "▶︎ Release derlemesi yapılıyor…"
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/$EXEC_NAME"
if [[ ! -f "$BIN_PATH" ]]; then
  echo "✗ İkili bulunamadı: $BIN_PATH"; exit 1
fi

# İkon yoksa üret
if [[ ! -f "$ROOT/AppIcon.icns" ]]; then
  echo "▶︎ Uygulama ikonu üretiliyor…"
  ( cd "$ROOT" && swift generate-icon.swift && iconutil -c icns AppIcon.iconset -o AppIcon.icns )
fi

echo "▶︎ Paket yapısı oluşturuluyor…"
rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"
cp "$BIN_PATH" "$MACOS/$EXEC_NAME"
[[ -f "$ROOT/AppIcon.icns" ]] && cp "$ROOT/AppIcon.icns" "$RESOURCES/AppIcon.icns"

# Diller: macOS dili İngilizceyse İngilizce, Türkçeyse Türkçe; diğer dillerde İngilizce.
echo "▶︎ Dil dosyaları üretiliyor…"
python3 "$ROOT/Localization/build_strings.py"
for lproj in "$ROOT"/Localization/*.lproj; do
  cp -R "$lproj" "$RESOURCES/"
done

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>$EXEC_NAME</string>
    <key>CFBundleDisplayName</key>     <string>$APP_NAME</string>
    <key>CFBundleDevelopmentRegion</key> <string>en</string>
    <key>CFBundleLocalizations</key>   <array><string>en</string><string>tr</string></array>
    <key>CFBundleAllowMixedLocalizations</key> <false/>
    <key>CFBundleIdentifier</key>      <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>      <string>$EXEC_NAME</string>
    <key>CFBundleIconFile</key>        <string>AppIcon</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>$VERSION</string>
    <key>CFBundleVersion</key>         <string>$BUILD</string>
    <key>LSMinimumSystemVersion</key>  <string>14.0</string>
    <key>NSHighResolutionCapable</key> <true/>
    <key>LSUIElement</key>             <false/>
    <key>NSPrincipalClass</key>        <string>NSApplication</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Bellek temizleme gibi yönetici işlemleri için sistem şifre penceresi açılır.</string>
    <key>NSSystemAdministrationUsageDescription</key>
    <string>Performans iyileştirme işlemleri için sistem erişimi gerekir.</string>
</dict>
</plist>
PLIST

# PkgInfo
printf 'APPL????' > "$CONTENTS/PkgInfo"

echo "▶︎ Ad-hoc imzalanıyor…"
codesign --force --deep --sign - "$APP_DIR"

echo "✓ Hazır: $APP_DIR"
echo "  Çalıştırmak için:  open \"$APP_DIR\""
