#!/bin/bash
set -e
cd "$(dirname "$0")"
APP_NAME=FluckDumper
PRODUCT_TIPA=iOSIL2CPPDumper.tipa
rm -rf build
mkdir build
cd build

xcodebuild -project "../$APP_NAME.xcodeproj" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -derivedDataPath "$PWD/DerivedDataApp" \
    -destination 'generic/platform=iOS' \
    clean build \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGN_ENTITLEMENTS="" CODE_SIGNING_ALLOWED=NO

APP="$PWD/DerivedDataApp/Build/Products/Release-iphoneos/$APP_NAME.app"
TARGET_APP="$PWD/$APP_NAME.app"
cp -R "$APP" "$TARGET_APP"

codesign --remove "$TARGET_APP" 2>/dev/null || true
rm -rf "$TARGET_APP/_CodeSignature" "$TARGET_APP/embedded.mobileprovision" 2>/dev/null || true

ldid -S"../entitlements.plist" "$TARGET_APP/$APP_NAME"

mkdir Payload
cp -r "$APP_NAME.app" "Payload/$APP_NAME.app"
zip -qr "$PRODUCT_TIPA" Payload
rm -rf "$APP_NAME.app" Payload DerivedDataApp
echo "Built: $(pwd)/$PRODUCT_TIPA (com.zexis.iosil2cppdumper)"
