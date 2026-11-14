<#
  PSCyber Site Onboarding - install (or update) Microsoft Sysmon with the PSCyber configuration, so the
  SOC sees registry changes on attacker-used keys IN REAL TIME, with the user and the program behind
  each one. The Wazuh agent (installed by install-agent-windows.ps1) forwards Sysmon's log.

    powershell -ExecutionPolicy Bypass -File .\install-sysmon-windows.ps1

  Run as Administrator. Sysmon itself comes from Microsoft (download.sysinternals.com); its
  configuration from this repository. Re-running updates the configuration in place.
  Remove: "C:\Program Files\PSCyber\Sysmon\Sysmon64.exe" -u

  Ransomware decoys (since 1.9.0): a hidden "!PSCyber-check" folder in Public Documents and on each data
  drive holds five ordinary-looking files nobody uses, and the Wazuh agent watches them in real time
  (Windows file-change notifications - no scanning, no measurable CPU). Ransomware encrypts everything it can
  reach, so a change there alerts the SOC within seconds of encryption starting. Skip: -NoDecoy
  (also stops the watching; the files are left for you to delete).
#>
param([string]$Config, [switch]$NoDecoy)
$ErrorActionPreference = "Stop"
$Raw = "https://raw.githubusercontent.com/prosethsolutionsAI/pscyber-site-onboarding/main/agents"
function Say($m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Ok($m)  { Write-Host " ok $m" -ForegroundColor Green }
function Die($m) { Write-Host "ERR $m" -ForegroundColor Red; exit 1 }

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { Die "run PowerShell as Administrator" }
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$dir = Join-Path $env:ProgramFiles "PSCyber\Sysmon"
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$cfg = Join-Path $dir "pscyber-sysmon.xml"
if ($Config -and (Test-Path $Config)) { Copy-Item $Config $cfg -Force }
elseif ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot "pscyber-sysmon.xml"))) { Copy-Item (Join-Path $PSScriptRoot "pscyber-sysmon.xml") $cfg -Force }
else { try { (New-Object Net.WebClient).DownloadFile("$Raw/pscyber-sysmon.xml", $cfg) } catch { Die "could not download the PSCyber Sysmon configuration" } }

$svc = Get-Service Sysmon64, Sysmon -ErrorAction SilentlyContinue | Select-Object -First 1
if ($svc) {
    Say "Sysmon is already installed ($($svc.Name)) - applying the PSCyber configuration"
    $exe = (Get-CimInstance Win32_Service -Filter "Name='$($svc.Name)'").PathName.Trim('"')
    & $exe -c $cfg | Out-Null
    if ($LASTEXITCODE -ne 0) { Die "Sysmon refused the configuration (exit $LASTEXITCODE)" }
} else {
    Say "downloading Sysmon from Microsoft (download.sysinternals.com)"
    $zip = Join-Path $env:TEMP "Sysmon.zip"
    try { (New-Object Net.WebClient).DownloadFile("https://download.sysinternals.com/files/Sysmon.zip", $zip) }
    catch { Die "download failed - this machine needs HTTPS to download.sysinternals.com just for the install" }
    $sig = $null
    Expand-Archive $zip -DestinationPath $dir -Force; Remove-Item $zip
    $exe = Join-Path $dir "Sysmon64.exe"
    $sig = Get-AuthenticodeSignature $exe
    if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'Microsoft') { Die "Sysmon64.exe is not validly signed by Microsoft - not installing" }
    Say "installing Sysmon (signed by Microsoft) with the PSCyber configuration"
    & $exe -accepteula -i $cfg | Out-Null
    if ($LASTEXITCODE -ne 0) { Die "Sysmon install failed (exit $LASTEXITCODE)" }
}
$s = Get-Service Sysmon64, Sysmon -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $s -or $s.Status -ne 'Running') { Die "Sysmon is not running after the install" }
Ok "Sysmon running - registry changes on attacker-used keys are now reported in real time"

# ---- Ransomware decoys (SOC rules 101330/101331) ---------------------------------------------------------
# Files are created only when missing - an existing decoy is never rewritten (that would be a change the
# agent reports). Our block in the agent's ossec.conf sits between two markers and is the only thing written;
# the agent is restarted only when that block changed, and put back as it was if it then fails to start.
$DecoyNames = 'Finance-2026.xlsx', 'Contracts-2026.docx', 'Payroll-2026.pdf', 'Passwords-backup.txt'
function New-Decoy([string]$Path) {
    $d = New-Item -ItemType Directory -Force -Path $Path
    $d.Attributes = $d.Attributes -bor [IO.FileAttributes]::Hidden
    $note = Join-Path $Path '!README-PSCyber.txt'
    if (-not (Test-Path $note)) {
        [IO.File]::WriteAllText($note, "PSCyber SOC security check.`r`nThe files in this folder exist only to detect ransomware: any change to them alerts the SOC at once.`r`nPlease do not open, move or delete this folder. Questions: your IT provider.`r`n")
    }
    $rng = New-Object Random
    foreach ($n in $DecoyNames) {
        $f = Join-Path $Path $n
        if (Test-Path $f) { continue }
        $b = New-Object byte[] (49152 + $rng.Next(32768)); $rng.NextBytes($b)
        [IO.File]::WriteAllBytes($f, $b)
    }
}
function Set-Decoys {
    $agentDir = Join-Path ${env:ProgramFiles(x86)} 'ossec-agent'
    $agentConf = Join-Path $agentDir 'ossec.conf'
    if (-not (Test-Path $agentConf)) { Write-Host "  (ransomware decoys skipped: no Wazuh agent on this machine yet - re-run after installing it)"; return }
    $begin = '<!-- PSCyber decoys BEGIN - written by install-sysmon-windows.ps1, re-run it to change -->'
    $end = '<!-- PSCyber decoys END -->'
    $dirs = @()
    if (-not $NoDecoy) {
        $dirs += Join-Path ([Environment]::GetFolderPath('CommonDocuments')) '!PSCyber-check'
        Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | Where-Object { $_.DeviceID -ne $env:SystemDrive } |
            ForEach-Object { $dirs += "$($_.DeviceID)\!PSCyber-check" }
        foreach ($p in $dirs) { try { New-Decoy $p } catch { Write-Host "  (decoy folder $p skipped: $($_.Exception.Message))" } }
        $dirs = @($dirs | Where-Object { Test-Path $_ })
    }
    $old = [IO.File]::ReadAllText($agentConf)
    $new = [regex]::Replace($old, '(?s)\r?\n?' + [regex]::Escape($begin) + '.*?' + [regex]::Escape($end), '')
    if ($dirs.Count) {
        $lines = ($dirs | ForEach-Object { "    <directories realtime=`"yes`" check_all=`"yes`">$_</directories>" }) -join "`r`n"
        $new = $new.TrimEnd() + "`r`n$begin`r`n<ossec_config>`r`n  <syscheck>`r`n$lines`r`n  </syscheck>`r`n</ossec_config>`r`n$end`r`n"
    }
    if ($new -eq $old) {
        if ($dirs.Count) { Ok "ransomware decoys: already in place and watched ($($dirs -join ', '))" }
        return
    }
    $bak = "$agentConf.bak-decoy"
    Copy-Item $agentConf $bak -Force
    [IO.File]::WriteAllText($agentConf, $new)
    $logf = Join-Path $agentDir 'ossec.log'
    $from = if (Test-Path $logf) { (Get-Item $logf).Length } else { 0 }
    Restart-Service WazuhSvc -ErrorAction SilentlyContinue
    Start-Sleep 8
    $tail = ''
    if (Test-Path $logf) {
        $fs = [IO.File]::Open($logf, 'Open', 'Read', 'ReadWrite')
        try { if ($fs.Length -ge $from) { [void]$fs.Seek($from, 'Begin') }; $tail = (New-Object IO.StreamReader($fs)).ReadToEnd() } finally { $fs.Close() }
    }
    if ((Get-Service WazuhSvc).Status -ne 'Running' -or $tail -match '(?i)(CRITICAL|ERROR).*(configuration|XML|syscheck)') {
        Copy-Item $bak $agentConf -Force
        Restart-Service WazuhSvc -ErrorAction SilentlyContinue
        Write-Host "  (ransomware decoys skipped: the agent refused the change - its configuration was put back as it was)"
        return
    }
    Remove-Item $bak -Force -ErrorAction SilentlyContinue
    if ($dirs.Count) { Ok "ransomware decoys watched in real time: $($dirs -join ', ')" }
    else { Ok "ransomware decoys no longer watched (the folders are left - delete them by hand if you wish)" }
}
Set-Decoys
