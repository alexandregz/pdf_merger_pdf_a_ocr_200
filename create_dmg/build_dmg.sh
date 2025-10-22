#!/usr/bin/env bash
set -euo pipefail

# traballamos no raiz
cd "$(dirname "$0")/.." || exit 1

APP_NAME="CIG Combinador PDF"
DMG_NAME="CIG Combinador PDF.dmg"

echo "==> 0) Dependencias rápidas"
command -v flutter >/dev/null || { echo "Instala Flutter primeiro"; exit 1; }
if ! command -v create-dmg >/dev/null; then
  echo "Instalando create-dmg con Homebrew..."
  brew install create-dmg
fi

echo "==> 1) Forzar build universal (arm64 + x86_64) en Release sen abrir Xcode"
XC_REL="macos/Flutter/Flutter-Release.xcconfig"
mkdir -p "$(dirname "$XC_REL")"
# Engadimos/actualizamos flags (idempotente)
grep -q '^ARCHS *= *arm64 x86_64' "$XC_REL" 2>/dev/null || echo 'ARCHS = arm64 x86_64' >> "$XC_REL"
grep -q '^ONLY_ACTIVE_ARCH *= *NO' "$XC_REL" 2>/dev/null || echo 'ONLY_ACTIVE_ARCH = NO' >> "$XC_REL"
# Evitar exclusións de arquitecturas
grep -q '^EXCLUDED_ARCHS\[sdk=macos\*\] *= *$' "$XC_REL" 2>/dev/null || echo 'EXCLUDED_ARCHS[sdk=macos*] =' >> "$XC_REL"

echo "==> 2) Build Release de macOS (Flutter)"
flutter clean
flutter pub get
flutter build macos --release

APP_PATH="build/macos/Build/Products/Release/$APP_NAME.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Non atopo $APP_PATH — revisa o build"; exit 1
fi

echo "==> 3) Verificar que o binario é universal"
ARCHS=$(lipo -archs "$APP_PATH/Contents/MacOS/$APP_NAME")
echo "Arquitecturas atopadas: $ARCHS"
echo "$ARCHS" | grep -q "x86_64" || { echo "Falta x86_64"; exit 1; }
echo "$ARCHS" | grep -q "arm64"  || { echo "Falta arm64";  exit 1; }


echo "==> 4) Asinar ad-hoc (sen hardened runtime)"
codesign --deep --force -s - "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"


echo "==> 5) Preparar unha copia co nome amigable para o DMG"
WORKDIR="$(mktemp -d)"
APP_NAMED="$WORKDIR/${APP_NAME}.app"
cp -R "$APP_PATH" "$APP_NAMED"

echo "==> 6) Crear DMG con create-dmg + ligazón a Applications"
# Eliminamos DMG previo
rm -f "$DMG_NAME"
create-dmg \
  --volname "$APP_NAME" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 120 \
  --app-drop-link 425 200 \
  --icon "${APP_NAME}.app" 175 200 \
  "$DMG_NAME" \
  "$APP_NAMED"

# echo "==> 7) Comprobacións básicas"
# hdiutil verify "$DMG_NAME"
# spctl --assess --type open --verbose "$DMG_NAME" || true

echo "Listo! DMG xerado: $DMG_NAME"
echo
echo "NOTA IMPORTANTE:"
echo "- En *outros* Macs, ao non estar notarizado con Developer ID, Gatekeeper pode amosar aviso."
echo "- Para probas no teu Mac: abre o DMG, arrastra a Applications e, se che avisa, click dereito > Open > Open."
echo
echo "Se máis adiante queres eliminar calquera aviso en Macs alleos, activa o bloque de notarización inferior."
echo

################################################################################
# OPCIONAL: Asinado con Developer ID + Notarización para evitar avisos en outros Macs
# 1) Precisas conta Apple Developer Program
# 2) Instala o certificado 'Developer ID Application: O Teu Nome (TEAMID)' en Keychain
# 3) Garda unhas credenciais para notarytool:
#    xcrun notarytool store-credentials "notary-profile" \
#      --apple-id "teu_email@exemplo.com" --team-id "TEAMID" --app-password "CONTRASINAL-APP"
#
# Descomenta e adapta as liñas seguintes para usar asinatura oficial + notarizar o DMG:
#
# CERT="Developer ID Application: O Teu Nome (TEAMID)"
# echo "==> [DEV ID] Re-asinando a app con Developer ID + timestamp"
# codesign --deep --force --options runtime --timestamp --sign "$CERT" "$APP_NAMED"
# codesign --verify --deep --strict --verbose=2 "$APP_NAMED"
#
echo "==> [DEV ID] Crear de novo o DMG asinando a app oficial"
rm -f "$DMG_NAME"
create-dmg \
  --volname "$APP_NAME" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 120 \
  --app-drop-link 425 200 \
  --icon "${APP_NAME}.app" 175 200 \
  "$DMG_NAME" \
  "$APP_NAMED"
#
# echo "==> [DEV ID] Enviar a notarización e esperar resultado"
# xcrun notarytool submit "$DMG_NAME" --keychain-profile "notary-profile" --wait
# echo "==> [DEV ID] Engrapar (staple) o ticket ao DMG"
# xcrun stapler staple "$DMG_NAME"
# echo "==> [DEV ID] Validación final"
# spctl --assess --type open --verbose "$DMG_NAME"
################################################################################
