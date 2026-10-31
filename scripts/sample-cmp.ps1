# Sample GPU power/clocks/PCIe link during a benchmark run. ASCII-only.
param([string]$Out = 'gpu-power-cmp90hx-baseline.csv', [int]$Seconds = 420)
'timestamp,sm_mhz,mem_mhz,power_w,temp_c,util_pct,throttle,pcie_gen,pcie_width' |
    Set-Content -LiteralPath $Out -Encoding ASCII
$end = (Get-Date).AddSeconds($Seconds)
while ((Get-Date) -lt $end) {
    $v = & 'C:\Windows\System32\nvidia-smi.exe' --query-gpu=timestamp,clocks.current.sm,clocks.current.memory,power.draw,temperature.gpu,utilization.gpu,clocks_event_reasons.active,pcie.link.gen.current,pcie.link.width.current --format=csv,noheader,nounits 2>$null
    if ($v) { Add-Content -LiteralPath $Out -Value $v -Encoding ASCII }
    Start-Sleep -Seconds 2
}
