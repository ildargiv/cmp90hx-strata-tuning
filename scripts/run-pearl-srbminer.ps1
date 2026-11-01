# Run a timed PearlHash (PRL) hashrate test with SRBMiner-MULTI and sample the GPU at 1 s.
# ASCII-only on purpose: Windows PowerShell 5.1 reads BOM-less .ps1 as ANSI.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-pearl-srbminer.ps1 `
#       -Wallet prl1p... -Seconds 600 -Tag post2
#
# Writes  results/raw/pearl-srbminer-<Tag>-gpu.csv  and leaves the miner log in $MinerDir.

param(
    [Parameter(Mandatory = $true)][string]$Wallet,
    [string]$MinerDir = 'C:\Users\User\Pearl\miner\SRBMiner-Multi-3-8-3',
    [string]$Worker   = 'cmp90hx',
    [string]$Pool     = 'prl.kryptex.network:7048',
    [int]$Seconds     = 600,
    [string]$Tag      = 'run',
    [string]$OutDir
)

$ErrorActionPreference = 'Stop'
if (-not $OutDir) { $OutDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'results\raw' }
if (-not (Test-Path -LiteralPath $OutDir)) { New-Item -ItemType Directory -Force -Path $OutDir | Out-Null }

$exe = Join-Path $MinerDir 'SRBMiner-MULTI.exe'
if (-not (Test-Path -LiteralPath $exe)) { throw "SRBMiner-MULTI.exe not found in $MinerDir" }

$csv     = Join-Path $OutDir "pearl-srbminer-$Tag-gpu.csv"
$logName = "pearl-$Tag.log"
$log     = Join-Path $MinerDir $logName
Remove-Item -LiteralPath $csv, $log -Force -ErrorAction SilentlyContinue

# ---- 1 s GPU sampler -------------------------------------------------------
$sampler = Start-Job -ScriptBlock {
    param($Path, $Secs)
    $q = 'timestamp,utilization.gpu,memory.used,power.draw,temperature.gpu,clocks.sm,clocks.mem,pcie.link.gen.current,pcie.link.width.current'
    $q | Set-Content -LiteralPath $Path -Encoding UTF8
    $end = (Get-Date).AddSeconds($Secs)
    while ((Get-Date) -lt $end) {
        $v = & 'C:\Windows\System32\nvidia-smi.exe' --query-gpu=$q --format=csv,noheader,nounits 2>$null
        if ($v) { Add-Content -LiteralPath $Path -Value $v -Encoding UTF8 }
        Start-Sleep -Milliseconds 1000
    }
} -ArgumentList $csv, ($Seconds + 20)
Start-Sleep -Seconds 2

# ---- miner -----------------------------------------------------------------
$argList = @('--disable-cpu', '--algorithm-gpu', 'pearlhash',
             '--pool', $Pool, '--wallet', $Wallet, '--worker', $Worker,
             '--api-enable', '--api-port', '21550', '--log-file', $logName)

$p = Start-Process -FilePath $exe -ArgumentList $argList -WorkingDirectory $MinerDir -NoNewWindow -PassThru `
        -RedirectStandardOutput (Join-Path $MinerDir "$Tag.out.txt") `
        -RedirectStandardError  (Join-Path $MinerDir "$Tag.err.txt")

Start-Sleep -Seconds $Seconds
$alive = -not $p.HasExited
if ($alive) { Stop-Process -Id $p.Id -Force }

Stop-Job $sampler -ErrorAction SilentlyContinue
Remove-Job $sampler -Force -ErrorAction SilentlyContinue

# ---- summary ---------------------------------------------------------------
Write-Output "[$Tag] alive through ${Seconds}s: $alive"
Write-Output "[$Tag] log: $log"
Write-Output "[$Tag] csv: $csv"
$hs = Get-Content -LiteralPath $log |
      Select-String -Pattern 'GPU1 CMP 90HX: ([0-9.]+) TH/s' |
      ForEach-Object { [double]$_.Matches[0].Groups[1].Value }
if ($hs.Count) {
    $m = $hs | Measure-Object -Average -Minimum -Maximum
    'hashrate: {0} samples, avg {1:N2} TH/s, min {2:N2}, max {3:N2}' -f $hs.Count, $m.Average, $m.Minimum, $m.Maximum
}
Get-Content -LiteralPath $log | Select-String -Pattern 'share accepted|rejected' |
    Select-Object -Last 5 | ForEach-Object { $_.Line }
