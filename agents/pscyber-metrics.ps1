# PSCyber device reporter 1.0.0 (Windows) - CPU, memory, disks, network and top processes every 30 s.
# Sends numbers only: no logs, no file contents, no secrets. Runs as a SYSTEM scheduled task "PSCyber Metrics".
$ErrorActionPreference = 'SilentlyContinue'
$conf = Get-Content "$env:ProgramData\PSCyber\metrics.json" -Raw | ConvertFrom-Json
[Net.ServicePointManager]::SecurityProtocol = 'Tls12'
if ($conf.thumbprint) { [Net.ServicePointManager]::ServerCertificateValidationCallback = { param($s, $c) $c.GetCertHashString() -eq $conf.thumbprint } }
$keys = @("${env:ProgramFiles(x86)}\ossec-agent\client.keys", "$env:ProgramFiles\ossec-agent\client.keys")
$agent = ''
foreach ($k in $keys) { if (Test-Path $k) { $agent = ((Get-Content $k -TotalCount 1) -split ' ')[0]; break } }
while ($true) {
  try {
    $os = Get-CimInstance Win32_OperatingSystem
    $cpu = (Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'").PercentProcessorTime
    $cores = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
    $disks = @(Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | Where-Object { $_.Size } | ForEach-Object {
      @{ mount = $_.DeviceID; size_kb = [math]::Round($_.Size / 1KB); used_kb = [math]::Round(($_.Size - $_.FreeSpace) / 1KB) } })
    $net = Get-CimInstance Win32_PerfRawData_Tcpip_NetworkInterface
    $rx = ($net | Measure-Object BytesReceivedPersec -Sum).Sum; $tx = ($net | Measure-Object BytesSentPersec -Sum).Sum
    $top = @(Get-CimInstance Win32_PerfFormattedData_PerfProc_Process | Where-Object { $_.Name -notin '_Total', 'Idle' } |
      Sort-Object PercentProcessorTime -Descending | Select-Object -First 5 | ForEach-Object {
        @{ name = ($_.Name -replace '#\d+$', ''); pid = $_.IDProcess; cpu = [math]::Round($_.PercentProcessorTime / [math]::Max(1, $cores), 1); rss_kb = [math]::Round($_.WorkingSetPrivate / 1KB) } })
    $pf = Get-CimInstance Win32_PageFileUsage | Select-Object -First 1
    $swap = if ($pf -and $pf.AllocatedBaseSize) { [math]::Round(100 * $pf.CurrentUsage / $pf.AllocatedBaseSize, 1) } else { 0 }
    $body = @{ version = '1.0.0'; os = 'windows'; hostname = $env:COMPUTERNAME; agent_id = $agent; cpu_pct = $cpu; cores = $cores
      mem_total_kb = $os.TotalVisibleMemorySize; mem_avail_kb = $os.FreePhysicalMemory; swap_pct = $swap
      uptime_s = [int]((Get-Date) - $os.LastBootUpTime).TotalSeconds; disks = $disks; net_rx = $rx; net_tx = $tx; top = $top } | ConvertTo-Json -Depth 4 -Compress
    $headers = @{}; if ($conf.token) { $headers.Authorization = "Bearer $($conf.token)" }
    Invoke-RestMethod -Uri $conf.report_url -Method Post -Body $body -ContentType 'application/json' -Headers $headers -TimeoutSec 20 | Out-Null
  } catch { }
  Start-Sleep -Seconds 30
}
