# Start the Strata server in a VISIBLE console window, CMP 90HX 10 GB config.
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File start-server-visible-cmp.ps1
# ASCII-only script (PowerShell 5.1 safe).
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
Set-Location -LiteralPath $root

# stop anything already holding port 8090
$conn = Get-NetTCPConnection -State Listen -LocalPort 8090 -ErrorAction SilentlyContinue | Select-Object -First 1
if ($conn) {
    $serverPid = $conn.OwningProcess
    Get-CimInstance Win32_Process | Where-Object { $_.ParentProcessId -eq $serverPid } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Stop-Process -Id $serverPid -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
}
Get-Process strata, strata-vision -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

$env:STRATA_PREFILL_RING = '32'
$env:PYTHONUTF8 = '1'
$py = Join-Path $root '.venv\Scripts\python.exe'
if (-not (Test-Path $py)) { throw "Missing $py" }

$Host.UI.RawUI.WindowTitle = 'Strata CMP 90HX 10GB: Qwen3.8-Flash-Next IQ3_XXS, 262144 tokens, port 8090'
& $py 'serve\server.py' --engine strata --config strata-iq3_xxs-10gb.json --port 8090
