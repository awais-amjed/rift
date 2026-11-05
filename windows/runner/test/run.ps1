# Builds windows/runner/stream_draw.cpp and stream_device.cpp with their tests,
# outside Flutter, and runs them on each adapter given (DXGI's order; 0 is the
# one Flutter takes when Rift names no GPU):
#   powershell -File windows\runner\test\run.ps1 0 1
# Needs Visual Studio's C++ tools, found with vswhere. The shaders are compiled
# here with the Windows SDK's fxc, as the app's build has MSBuild do it.
$adapters = if ($args.Count) { $args | ForEach-Object { [int]$_ } } else { @(0) }
$ErrorActionPreference = 'Stop'
$runner = Split-Path $PSScriptRoot -Parent
$out = Join-Path $runner '..\..\build\stream_draw_test'
New-Item -ItemType Directory -Force $out | Out-Null
$out = (Resolve-Path $out).Path

$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vs) { throw 'no Visual Studio C++ tools found' }
$vcvars = Join-Path $vs 'VC\Auxiliary\Build\vcvars64.bat'

$cl = "cl /nologo /std:c++17 /EHsc /W4 /WX /O2 /DNOMINMAX /I`"$runner`" /I`"$out`" /Fo`"$out\\`""
$build = @(
  "set `"PATH=%PATH%;$(Split-Path $vswhere)`"",
  "call `"$vcvars`" >nul",
  "fxc /nologo /T vs_5_0 /E main /Vn kStreamDrawVs /Fh `"$out\stream_draw_vs.h`" `"$runner\stream_draw_vs.hlsl`" >nul",
  "fxc /nologo /T ps_5_0 /E main /Vn kStreamDrawPs /Fh `"$out\stream_draw_ps.h`" `"$runner\stream_draw_ps.hlsl`" >nul",
  "fxc /nologo /T ps_5_0 /E main /Vn kStreamDrawNv12Ps /Fh `"$out\stream_draw_nv12_ps.h`" `"$runner\stream_draw_nv12_ps.hlsl`" >nul",
  "$cl /Fe`"$out\stream_draw_test.exe`" `"$runner\test\stream_draw_test.cpp`" `"$runner\stream_draw.cpp`" d3d11.lib dxgi.lib",
  "$cl /Fe`"$out\stream_device_test.exe`" `"$runner\test\stream_device_test.cpp`" `"$runner\stream_device.cpp`" `"$runner\stream_draw.cpp`" d3d11.lib d3d12.lib dxgi.lib"
) -join ' && '
cmd /c $build
if ($LASTEXITCODE) { throw "build failed ($LASTEXITCODE)" }

$failed = 0
foreach ($a in $adapters) {
  foreach ($test in 'stream_draw_test', 'stream_device_test') {
    & "$out\$test.exe" $a
    if ($LASTEXITCODE) { $failed++ }
  }
}
if ($failed) { throw "$failed run(s) failed" }
