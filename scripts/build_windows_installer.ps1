# Builds the Windows installer.
#
# inno_bundle builds the app and writes its Inno Setup script; this adds what
# inno_bundle has no option for (windows\installer\uninstall_cleanup.iss, which
# removes Rift's registry keys at uninstall) and compiles the result with the
# Inno Setup inno_bundle installed. Extra arguments go to inno_bundle.
#
#   powershell -File scripts\build_windows_installer.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Push-Location $root
try {
  dart run inno_bundle --release --no-installer @args
  if ($LASTEXITCODE) { exit $LASTEXITCODE }

  $script = Join-Path $root 'build\windows\x64\installer\Release\inno-script.iss'
  $cleanup = Join-Path $root 'windows\installer\uninstall_cleanup.iss'
  Add-Content -Path $script -Encoding ascii -Value "`r`n#include `"$cleanup`""

  $iscc = Get-ChildItem "$env:USERPROFILE\.inno_bundle\versions\*\ISCC.exe" -ErrorAction SilentlyContinue |
    Sort-Object { [version]$_.Directory.Name } -Descending | Select-Object -First 1
  if (-not $iscc) { $iscc = Get-Command ISCC.exe -ErrorAction Stop }
  & $iscc.FullName $script
  exit $LASTEXITCODE
} finally {
  Pop-Location
}
