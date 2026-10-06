# Builds the Windows release, ready for scripts/vpk_pack.sh to pack.
#
# Obfuscated, as the Windows release has been since the Inno Setup installer
# (which always passed --obfuscate): saved state is keyed by fixed names
# (HydratedKeys) for exactly this reason. The C++ runtime's DLLs are copied in
# beside rift.exe, so nobody has to install the Visual C++ redistributable.
#
#   powershell -File scripts\build_windows.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Push-Location $root
try {
  flutter build windows --release --obfuscate --split-debug-info=build/obfuscate @args
  if ($LASTEXITCODE) { exit $LASTEXITCODE }

  $release = Join-Path $root 'build\windows\x64\runner\Release'
  foreach ($dll in 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll') {
    Copy-Item (Join-Path $env:SystemRoot "System32\$dll") $release
  }
} finally {
  Pop-Location
}
