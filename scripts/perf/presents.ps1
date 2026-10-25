# Counts DXGI Present calls per process over N seconds: how many frames each
# program drew (ETW, Microsoft-Windows-DXGI). Needs an elevated PowerShell.
#
#   powershell -File scripts\perf\presents.ps1 -Seconds 10
param([int]$Seconds = 10, [string]$Process = 'RiftChat')
$ErrorActionPreference = 'Stop'
$etl = Join-Path $env:TEMP 'rift-dxgi.etl'
$csv = Join-Path $env:TEMP 'rift-dxgi.csv'
Remove-Item $etl, $csv -ErrorAction SilentlyContinue
logman stop riftdxgi -ets 2>$null | Out-Null
logman start riftdxgi -p "Microsoft-Windows-DXGI" 0xFFFFFFFF 5 -o $etl -ets | Out-Null
Start-Sleep $Seconds
logman stop riftdxgi -ets | Out-Null
tracerpt $etl -o $csv -of CSV -y | Out-Null
$target = (Get-Process $Process -ErrorAction SilentlyContinue | Select-Object -First 1).Id
"$Process pid: $target (frames/s = Present count / $Seconds)"
Import-Csv $csv | Where-Object { $_.'Event Name' -match 'Present' } |
  Group-Object 'Event Name', 'Process ID' | Sort-Object Count -Descending |
  Select-Object -First 8 Count, Name | Format-Table -AutoSize
