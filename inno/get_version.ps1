# Coller versión do pubspec
$VER = dart run ../lib/tools/print_version.dart

# Separar name/code (parte antes/despois do '+')
$parts = $VER.Split('+')
$AppVersionName = $parts[0]                 # "1.4.2"
$AppVersionCode = ($parts.Count -ge 2) ? $parts[1] : '0'  # "37" ou "0"

# 3) Compilar Inno pasando defines
$ISCC = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
& $ISCC `
  "/DAppVersion=$VER" `
  "/DAppVersionName=$AppVersionName" `
  "/DAppVersionCode=$AppVersionCode" `
  "installer.iss"
