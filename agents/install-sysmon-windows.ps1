<#
  PSCyber Site Onboarding - install (or update) Microsoft Sysmon with the PSCyber configuration, so the
  SOC sees registry changes on attacker-used keys IN REAL TIME, with the user and the program behind
  each one. The Wazuh agent (installed by install-agent-windows.ps1) forwards Sysmon's log.

    powershell -ExecutionPolicy Bypass -File .\install-sysmon-windows.ps1

  Run as Administrator. Sysmon itself comes from Microsoft (download.sysinternals.com); its
  configuration from this repository. Re-running updates the configuration in place.
  Remove: "C:\Program Files\PSCyber\Sysmon\Sysmon64.exe" -u
#>
param([string]$Config)
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
