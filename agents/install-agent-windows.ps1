<#
  PSCyber Site Onboarding - install (or re-point) the Wazuh agent on Windows
  so it reports through the site's PSCyber Site Collector.

    powershell -ExecutionPolicy Bypass -File .\install-agent-windows.ps1 -Collector 192.168.10.50 -Group Acme

  One line, nothing to save first (PowerShell as Administrator; asks for the enrolment password):
    iwr -UseBasicParsing https://raw.githubusercontent.com/prosethsolutionsAI/pscyber-site-onboarding/main/agents/install-agent-windows.ps1 -OutFile $env:TEMP\pscyber-agent.ps1; powershell -ExecutionPolicy Bypass -File $env:TEMP\pscyber-agent.ps1 -Collector 192.168.10.50 -Group Acme

  Run as Administrator. Anything not given is asked for.
  It also installs the PSCyber device-health reporter (live CPU, memory, disk to the
  collector on TCP 1520, numbers only) unless -NoHealth is given, and Microsoft Sysmon with
  the PSCyber configuration (real-time registry monitoring) unless -NoSysmon is given.

  Ready now, turn on later (the customer has not bought the SOC yet, or there is no collector yet):
    powershell -ExecutionPolicy Bypass -File .\install-agent-windows.ps1 -Prepare
  installs the agent STOPPED and DISABLED - pointed at nothing, enrolled nowhere - and keeps
  this script in C:\Program Files\PSCyber. Later, with no internet needed on the machine:
    powershell -ExecutionPolicy Bypass -File "C:\Program Files\PSCyber\pscyber-agent.ps1" -Collector 192.168.10.50 -Group Acme
    powershell -ExecutionPolicy Bypass -File "C:\Program Files\PSCyber\pscyber-agent.ps1" -Status
    powershell -ExecutionPolicy Bypass -File "C:\Program Files\PSCyber\pscyber-agent.ps1" -Uninstall
  (-Uninstall removes the agent, the health reporter and these copies; Sysmon is left - remove it
   with "C:\Program Files\PSCyber\Sysmon\Sysmon64.exe" -u. Remove the machine in the SOC as well.)
#>
param(
    [string]$Collector,
    [string]$Group,
    [string]$EnrollPassword,
    [string]$Name,
    [string]$Version = "4.14.7",
    [switch]$NoHealth,
    [switch]$NoSysmon,
    [switch]$Prepare,
    [switch]$Status,
    [switch]$Uninstall
)
$Raw = "https://raw.githubusercontent.com/prosethsolutionsAI/pscyber-site-onboarding/main/agents"
$ErrorActionPreference = "Stop"

function Say($m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Ok($m)  { Write-Host " ok $m" -ForegroundColor Green }
function Die($m) { Write-Host "ERR $m" -ForegroundColor Red; exit 1 }

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { Die "run PowerShell as Administrator" }

$dir = Join-Path ${env:ProgramFiles(x86)} "ossec-agent"
$conf = Join-Path $dir "ossec.conf"
$log = Join-Path $dir "ossec.log"
$kept = Join-Path $env:ProgramFiles "PSCyber"          # this script + its helpers, for turning on offline
$mark = Join-Path $dir ".pscyber-prepared"

if ($Uninstall) {
    Unregister-ScheduledTask -TaskName 'PSCyber Metrics' -Confirm:$false -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force "$env:ProgramData\PSCyber" -ErrorAction SilentlyContinue
    $pkg = Get-CimInstance Win32_Product -Filter "Name LIKE 'Wazuh Agent%'" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pkg) {
        Stop-Service WazuhSvc -ErrorAction SilentlyContinue
        $p = Start-Process msiexec.exe -ArgumentList "/x $($pkg.IdentifyingNumber) /q" -Wait -PassThru
        if ($p.ExitCode -ne 0) { Die "msiexec could not remove the agent (exit $($p.ExitCode))" }
    }
    Remove-Item -Recurse -Force $dir -ErrorAction SilentlyContinue
    # Keep Sysmon's folder (it is still running from there); remove only our copies.
    foreach ($f in 'pscyber-agent.ps1', 'pscyber-metrics.ps1', 'install-sysmon-windows.ps1', 'pscyber-sysmon.xml') {
        Remove-Item -Force (Join-Path $kept $f) -ErrorAction SilentlyContinue
    }
    Ok "PSCyber agent removed from this machine (Sysmon left: `"$kept\Sysmon\Sysmon64.exe`" -u removes it)"
    Write-Host "  If it was enrolled, also remove it in the SOC (its name stays registered until then)."
    exit 0
}

if ($Status) {
    if (-not (Test-Path $conf)) { Write-Host "OFF: no Wazuh agent on this machine" }
    elseif (Test-Path $mark) { Write-Host "READY: agent installed, stopped, enrolled nowhere. Turn on: & `"$kept\pscyber-agent.ps1`" -Collector IP -Group GROUP" }
    else {
        $svc = Get-Service WazuhSvc -ErrorAction SilentlyContinue
        $addr = ([regex]'<address>([^<]*)</address>').Match([IO.File]::ReadAllText($conf)).Groups[1].Value
        Write-Host "ON: agent $($svc.Status), manager $addr"
    }
    exit 0
}

# Keep this script and its helpers, so turning the agent on - or re-pointing it - later needs no internet.
function Save-Helper {
    New-Item -ItemType Directory -Force -Path $kept | Out-Null
    icacls $kept /inheritance:r /grant:r 'SYSTEM:(OI)(CI)F' 'Administrators:(OI)(CI)F' 'Users:(OI)(CI)RX' | Out-Null
    foreach ($f in @(@{ src = 'install-agent-windows.ps1'; dst = 'pscyber-agent.ps1' }, @{ src = 'pscyber-metrics.ps1'; dst = 'pscyber-metrics.ps1' },
                     @{ src = 'install-sysmon-windows.ps1'; dst = 'install-sysmon-windows.ps1' }, @{ src = 'pscyber-sysmon.xml'; dst = 'pscyber-sysmon.xml' })) {
        $here = if ($f.src -eq 'install-agent-windows.ps1') { $PSCommandPath } else { Join-Path $PSScriptRoot $f.src }
        $to = Join-Path $kept $f.dst
        if ($here -and ((Resolve-Path $here -ErrorAction SilentlyContinue).Path -eq (Resolve-Path $to -ErrorAction SilentlyContinue).Path)) { continue }
        try {
            if ($here -and (Test-Path $here)) { Copy-Item $here $to -Force }
            else { (New-Object Net.WebClient).DownloadFile("$Raw/$($f.src)", $to) }
        } catch { Write-Host "  (could not keep $($f.dst) - turning it on later may need the download line again)" }
    }
}

if ($Prepare) {
    if ((Test-Path $conf) -and -not (Test-Path $mark)) {
        Save-Helper
        Ok "a Wazuh agent is already installed and set up - nothing to prepare (re-point it: & `"$kept\pscyber-agent.ps1`" -Collector IP)"
        exit 0
    }
    if (-not (Test-Path $conf)) {
        Say "downloading wazuh-agent $Version"
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $msi = Join-Path $env:TEMP "wazuh-agent-$Version-1.msi"
        try { (New-Object Net.WebClient).DownloadFile("https://packages.wazuh.com/4.x/windows/wazuh-agent-$Version-1.msi", $msi) }
        catch { Die "download failed - this machine needs HTTPS to packages.wazuh.com just for the install" }
        Say "installing (ready mode - not started, pointed at nothing)"
        $p = Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /q" -Wait -PassThru
        Remove-Item $msi -ErrorAction SilentlyContinue
        if ($p.ExitCode -ne 0) { Die "msiexec failed with exit code $($p.ExitCode)" }
    }
    Stop-Service WazuhSvc -ErrorAction SilentlyContinue
    Set-Service WazuhSvc -StartupType Disabled
    New-Item -ItemType File -Force -Path $mark | Out-Null
    Save-Helper
    Ok "READY: the Wazuh agent is installed but STOPPED - pointed at nothing, sending nothing"
    Write-Host "  Turn on later (no internet needed):"
    Write-Host "    powershell -ExecutionPolicy Bypass -File `"$kept\pscyber-agent.ps1`" -Collector <COLLECTOR_IP> -Group <GROUP>"
    exit 0
}

if (-not $Collector) { $Collector = Read-Host "  Collector IP" }
if (-not $Collector) { Die "the collector IP is required" }

# Only log lines written AFTER this point count: an old "Connected" from before the restart
# must not read as success (seen on a re-run on Linux).
$logFrom = if (Test-Path $log) { (Get-Item $log).Length } else { 0 }
function New-LogText {
    if (-not (Test-Path $log)) { return "" }
    $fs = [IO.File]::Open($log, 'Open', 'Read', 'ReadWrite')
    try {
        if ($fs.Length -lt $logFrom) { $script:logFrom = 0 }  # rotated
        [void]$fs.Seek($logFrom, 'Begin')
        (New-Object IO.StreamReader($fs)).ReadToEnd()
    } finally { $fs.Close() }
}

function Test-Ports {
    foreach ($p in 1514, 1515) {
        $t = New-Object Net.Sockets.TcpClient
        $r = $t.BeginConnect($Collector, $p, $null, $null)
        $okc = $r.AsyncWaitHandle.WaitOne(3000) -and $t.Connected
        $t.Close()
        if (-not $okc) { Die "cannot reach $Collector TCP $p - open it between this machine and the collector (FIREWALL.md)" }
    }
    Ok "TCP 1514 and 1515 reachable"
}

if ((Test-Path $mark) -and (Test-Path (Join-Path $dir "agent-auth.exe"))) {
    # Prepared earlier (-Prepare): installed, never enrolled. Enrol it now through the collector,
    # then start it. The password goes to agent-auth in a file removed straight after - never argv.
    if (-not $Group) { $Group = Read-Host "  Agent group (pscyber-collector site-agent-command shows it)" }
    if (-not $Group) { Die "the agent group is required - it is what puts this machine in your SOC tenant" }
    if (-not $EnrollPassword) {
        $EnrollPassword = Read-Host "  Enrolment password (paste, then Enter)"
        Write-Host "  Enrolment password: got $($EnrollPassword.Length) characters"
    }
    if (-not $Name) { $Name = "$Group-$env:COMPUTERNAME" }
    Say "checking the collector $Collector is reachable"
    Test-Ports
    Copy-Item $conf "$conf.bak-$(Get-Date -Format yyyyMMddHHmmss)"
    $text = [IO.File]::ReadAllText($conf)
    $text = (New-Object Text.RegularExpressions.Regex "<address>[^<]*</address>").Replace($text, "<address>$Collector</address>", 1)
    [IO.File]::WriteAllText($conf, $text)
    $passf = Join-Path $dir "authd.pass"
    [IO.File]::WriteAllText($passf, $EnrollPassword)
    Say "enrolling as $Name in group $Group"
    $ErrorActionPreference = "Continue"   # agent-auth writes progress to stderr; under Stop that would throw
    $out = & (Join-Path $dir "agent-auth.exe") -m $Collector -G $Group -A $Name 2>&1
    $rc = $LASTEXITCODE
    $ErrorActionPreference = "Stop"
    Remove-Item $passf -Force -ErrorAction SilentlyContinue
    if ($rc -ne 0) { $out | Select-Object -Last 3 | Write-Host; Die "enrolment refused (see 'Common problems' in agents/README.md)" }
    Remove-Item $mark -Force
    Set-Service WazuhSvc -StartupType Automatic
    Start-Service WazuhSvc
}
elseif (Test-Path $conf) {
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
    Test-Ports

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

# Device health: live CPU, memory, disks, network and top processes, every 30 s, to the
# collector (TCP 1520), which relays it to the SOC - numbers only, no token on this machine.
# The reporter program comes with this script (beside it, or from this repository over HTTPS),
# never from the network the readings travel on.
function Install-Health {
    $t = New-Object Net.Sockets.TcpClient
    $r = $t.BeginConnect($Collector, 1520, $null, $null)
    $open = $r.AsyncWaitHandle.WaitOne(3000) -and $t.Connected
    $t.Close()
    if (-not $open) { Write-Host "  (device health skipped: the collector does not answer on TCP 1520 - update it to 1.2.5+ and open 1520, then re-run this script)"; return }
    $hd = "$env:ProgramData\PSCyber"
    New-Item -ItemType Directory -Force -Path $hd | Out-Null
    icacls $hd /inheritance:r /grant:r 'SYSTEM:(OI)(CI)F' 'Administrators:(OI)(CI)F' | Out-Null
    $src = Join-Path $PSScriptRoot "pscyber-metrics.ps1"
    try {
        if (Test-Path $src) { Copy-Item $src "$hd\pscyber-metrics.ps1" -Force }
        else { (New-Object Net.WebClient).DownloadFile("$Raw/pscyber-metrics.ps1", "$hd\pscyber-metrics.ps1") }
    } catch { Write-Host "  (device health skipped: could not get pscyber-metrics.ps1)"; return }
    @{ report_url = "http://$($Collector):1520/report"; token = ''; thumbprint = '' } | ConvertTo-Json | Set-Content -Encoding ASCII "$hd\metrics.json"
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$hd\pscyber-metrics.ps1`""
    $settings = New-ScheduledTaskSettingsSet -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName 'PSCyber Metrics' -Action $action -Trigger (New-ScheduledTaskTrigger -AtStartup) -Settings $settings -User 'SYSTEM' -RunLevel Highest -Force | Out-Null
    Stop-ScheduledTask -TaskName 'PSCyber Metrics' -ErrorAction SilentlyContinue
    Start-ScheduledTask -TaskName 'PSCyber Metrics'
    Ok "device health reporting through the collector (live CPU, memory, disk)"
    Write-Host "  remove later: Unregister-ScheduledTask -TaskName 'PSCyber Metrics' -Confirm:`$false; Remove-Item -Recurse '$hd'"
}

# Real-time registry monitoring: Microsoft Sysmon with the PSCyber configuration (its own script, so a
# machine that already has the agent can get it alone). A failure here never undoes the agent.
function Install-Sysmon {
    $src = Join-Path $PSScriptRoot "install-sysmon-windows.ps1"
    try {
        if (-not (Test-Path $src)) { $src = Join-Path $env:TEMP "pscyber-sysmon.ps1"; (New-Object Net.WebClient).DownloadFile("$Raw/install-sysmon-windows.ps1", $src) }
        & powershell -NoProfile -ExecutionPolicy Bypass -File $src
    } catch { Write-Host "  (real-time registry monitoring skipped: $($_.Exception.Message) - run install-sysmon-windows.ps1 later)" }
}

Say "waiting for the agent to connect (up to 60 s)"
for ($i = 0; $i -lt 30; $i++) {
    if ((New-LogText).Contains("Connected to the server ([$Collector]")) {
        Ok "connected to the SOC through the collector $Collector"
        if (-not $NoHealth) { Install-Health }
        if (-not $NoSysmon) { Install-Sysmon }
        Save-Helper
        exit 0
    }
    Start-Sleep 2
}
Write-Host "Not connected yet. Last messages:"
(New-LogText) -split "`n" | Where-Object { $_ -match "ERROR|WARNING|Connected" } | Select-Object -Last 5
Write-Host "See 'Common problems' in agents/README.md."
exit 1
