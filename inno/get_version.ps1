# versións válidas en pubspec.yaml: 1.0.1+2, 1.0.1-beta+2, 1.0.1-beta, 1.0.1,...

$VER = (& dart run ../lib/tools/print_version.dart).Trim()

$parts = $VER.Split('+')
$AppVersion = $parts[0].Trim()
$buildCode = if ($parts.Count -ge 2) { $parts[1] } else { "0" }

# números de AppVersion (1.0.1 de "1.0.1[-algo]")
$nums = @()
foreach ($p in $AppVersion.Split('.')) {
  $m = [regex]::Match($p, '\d+')
  $nums += if ($m.Success) { $m.Value } else { '0' }
}
while ($nums.Count -lt 3) { $nums += '0' }
$nums = $nums[0..2]

# cuarto número do "+N" (só díxitos)
$codeMatch = [regex]::Match($buildCode, '\d+')
$buildNum = if ($codeMatch.Success) { $codeMatch.Value } else { '0' }

$VersionInfoVersion = "{0}.{1}.{2}.{3}" -f $nums[0], $nums[1], $nums[2], $buildNum

$ISCC = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"

Write-Host "=== Invocando ISCC con ==="
Write-Host "/DAppVersion=$AppVersion"
Write-Host "/DVersionInfoVersion=$VersionInfoVersion"

& $ISCC `
  "/DAppVersion=$AppVersion" `
  "/DVersionInfoVersion=$VersionInfoVersion" `
  "installer.iss"
