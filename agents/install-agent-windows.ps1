<#
  PSCyber Site Onboarding - install (or re-point) the Wazuh agent on Windows
  so it reports through the site's PSCyber Site Collector.

    powershell -ExecutionPolicy Bypass -File .\install-agent-windows.ps1 -Collector 192.168.10.50 -Group Acme

  Run as Administrator. Anything not given is asked for.
#>
param(
    [string]$Collector,
    [string]$Group,
    [string]$EnrollPassword,
    [string]$Name,
    [string]$Version = "4.14.7"
)
$ErrorActionPreference = "Stop"

function Say($m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Ok($m)  { Write-Host " ok $m" -ForegroundColor Green }
function Die($m) { Write-Host "ERR $m" -ForegroundColor Red; exit 1 }

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { Die "run PowerShell as Administrator" }

if (-not $Collector) { $Collector = Read-Host "  Collector IP" }
if (-not $Collector) { Die "the collector IP is required" }

$dir = Join-Path ${env:ProgramFiles(x86)} "ossec-agent"
$conf = Join-Path $dir "ossec.conf"
$log = Join-Path $dir "ossec.log"

if (Test-Path $conf) {
    # Already an agent: only the manager address changes - its key stays valid,
    # because the collector relays to the same SOC.
    Say "a Wazuh agent is already installed - pointing it at the collector $Collector"
    Copy-Item $conf "$conf.bak-$(Get-Date -Format yyyyMMddHHmmss)"
    $text = [IO.File]::ReadAllText($conf)
    $rx = New-Object Text.RegularExpressions.Regex "<address>[^<]*</address>"
    $text = $rx.Replace($text, "<address>$Collector</address>", 1)
    [IO.File]::WriteAllText($conf, $text)
    Restart-Service WazuhSvc
}
else {
    if (-not $Group) { $Group = Read-Host "  Agent group (pscyber-collector site-agent-command shows it)" }
    if (-not $Group) { Die "the agent group is required - it is what puts this machine in your SOC tenant" }
    if (-not $EnrollPassword) {
        $EnrollPassword = Read-Host "  Enrolment password (paste, then Enter)"
        Write-Host "  Enrolment password: got $($EnrollPassword.Length) characters"
    }
    if (-not $Name) { $Name = "$Group-$env:COMPUTERNAME" }

    Say "checking the collector $Collector is reachable"
    foreach ($p in 1514, 1515) {
        $t = New-Object Net.Sockets.TcpClient
        $r = $t.BeginConnect($Collector, $p, $null, $null)
        $okc = $r.AsyncWaitHandle.WaitOne(3000) -and $t.Connected
        $t.Close()
        if (-not $okc) { Die "cannot reach $Collector TCP $p - open it between this machine and the collector (FIREWALL.md)" }
    }
    Ok "TCP 1514 and 1515 reachable"

    Say "downloading wazuh-agent $Version"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $msi = Join-Path $env:TEMP "wazuh-agent-$Version-1.msi"
    try {
        (New-Object Net.WebClient).DownloadFile("https://packages.wazuh.com/4.x/windows/wazuh-agent-$Version-1.msi", $msi)
    } catch {
        Die "download failed - this machine needs HTTPS to packages.wazuh.com just for the install, or copy the .msi over and run msiexec by hand (agents/README.md)"
    }

    Say "installing as $Name in group $Group"
    $msiArgs = "/i `"$msi`" /q WAZUH_MANAGER=`"$Collector`" WAZUH_AGENT_GROUP=`"$Group`" WAZUH_AGENT_NAME=`"$Name`""
    if ($EnrollPassword) { $msiArgs += " WAZUH_REGISTRATION_PASSWORD=`"$EnrollPassword`"" }
    $p = Start-Process msiexec.exe -ArgumentList $msiArgs -Wait -PassThru
    Remove-Item $msi -ErrorAction SilentlyContinue
    if ($p.ExitCode -ne 0) { Die "msiexec failed with exit code $($p.ExitCode)" }
    Start-Service WazuhSvc
}

Say "waiting for the agent to connect (up to 60 s)"
for ($i = 0; $i -lt 30; $i++) {
    if ((Test-Path $log) -and (Select-String -Path $log -SimpleMatch "Connected to the server ([$Collector]" -Quiet)) {
        Ok "connected to the SOC through the collector $Collector"
        exit 0
    }
    Start-Sleep 2
}
Write-Host "Not connected yet. Last messages:"
if (Test-Path $log) { Select-String -Path $log -Pattern "ERROR|WARNING|Connected" | Select-Object -Last 5 | ForEach-Object { $_.Line } }
Write-Host "See 'Common problems' in agents/README.md."
exit 1
