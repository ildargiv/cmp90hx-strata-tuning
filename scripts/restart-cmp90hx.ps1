# Restart the Strata server for the CMP 90HX 10 GB card, with the 10gb config.
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File restart-cmp90hx.ps1
$ErrorActionPreference = 'Stop'
Start-Transcript -Path 'C:\Users\User\AppData\Local\Temp\opencode\strata-restart-cmp.log' -Force | Out-Null
$root = $PSScriptRoot
Set-Location -LiteralPath $root

# 1. Stop the running server and its engine/vision children.
$conn = Get-NetTCPConnection -State Listen -LocalPort 8090 -ErrorAction SilentlyContinue | Select-Object -First 1
if ($conn) {
    $serverPid = $conn.OwningProcess
    Write-Host "Stopping server PID $serverPid"
    Get-CimInstance Win32_Process | Where-Object { $_.ParentProcessId -eq $serverPid } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Stop-Process -Id $serverPid -Force -ErrorAction SilentlyContinue
} else {
    Write-Host 'Port 8090 is not listening; nothing to stop.'
}
Start-Sleep -Seconds 3
Get-Process strata, strata-vision -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# 2. Start the server hidden, with the 10gb config.
$env:STRATA_PREFILL_RING = '32'
$env:PYTHONUTF8 = '1'
$py = Join-Path $root '.venv\Scripts\python.exe'
if (-not (Test-Path $py)) { throw "Missing $py" }
$out = Join-Path $root 'server-stdout.log'
$err = Join-Path $root 'server-stderr.log'
Remove-Item $out, $err -ErrorAction SilentlyContinue
Start-Process -FilePath $py `
    -ArgumentList @('serve\server.py', '--engine', 'strata', '--config', 'strata-iq3_xxs-10gb.json', '--port', '8090') `
    -WorkingDirectory $root -WindowStyle Hidden `
    -RedirectStandardOutput $out -RedirectStandardError $err

# 3. Wait until the engine reports its context.
$deadline = (Get-Date).AddMinutes(20)
$ready = $false
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 5
    try {
        $m = Invoke-RestMethod -Uri 'http://127.0.0.1:8090/v1/models' -TimeoutSec 5
        $n = $m.data[0].meta.n_ctx
        if ($n -and [int]$n -gt 0) {
            Write-Host "READY n_ctx=$n"
            $ready = $true
            break
        }
    } catch { }
}
if (-not $ready) {
    Write-Host 'NOT READY within 20 minutes'
    if (Test-Path $err) { Get-Content $err -Tail 30 }
    exit 1
}

# 4. Report the new state.
& 'C:\Windows\System32\nvidia-smi.exe' --query-gpu=memory.used,memory.total,power.draw --format=csv,noheader
Get-CimInstance Win32_Process | Where-Object { $_.Name -in 'python.exe', 'strata.exe', 'strata-vision.exe' } |
    Select-Object ProcessId, ParentProcessId, Name, @{n = 'RAM_MB'; e = { [math]::Round($_.WorkingSetSize / 1MB) } } |
    Format-Table -AutoSize
Write-Host 'DONE'
Stop-Transcript | Out-Null
