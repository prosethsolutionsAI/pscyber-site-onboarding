# Wazuh agents on the site's servers and VMs

Each Windows, Linux or macOS machine runs the **Wazuh agent 4.14.7** with the
**collector's IP as its manager**. The collector relays it to the SOC through its
TLS tunnel, so the machine never needs internet access.

You need (see the main [README](../README.md#before-you-start---collect-these-four-values)):
**collector IP**, **agent group**, **enrolment password**. On the collector,
this prints all three ready to paste:

```bash
pscyber-collector site-agent-command
```

> **Agent names must be unique across the whole SOC**, not just your site - two
> customers both have a `DC01`. The scripts default the name to
> `<group>-<hostname>` (for example `Acme-DC01`); keep that pattern if you set it by hand.
>
> Do not install an agent version **newer** than 4.14.7 - the SOC managers refuse
> agents newer than themselves.

## One line per machine (agent + live device health)

`pscyber-collector site-agent-command` on the collector prints these with its IP and group filled in.
Each asks for the enrolment password.

```bash
# Linux, as root
curl -fsSL https://raw.githubusercontent.com/prosethsolutionsAI/pscyber-site-onboarding/main/agents/install-agent-linux.sh | sudo bash -s -- --collector 192.168.10.50 --group Acme
```

```powershell
# Windows, PowerShell as Administrator
iwr -UseBasicParsing https://raw.githubusercontent.com/prosethsolutionsAI/pscyber-site-onboarding/main/agents/install-agent-windows.ps1 -OutFile $env:TEMP\pscyber-agent.ps1; powershell -ExecutionPolicy Bypass -File $env:TEMP\pscyber-agent.ps1 -Collector 192.168.10.50 -Group Acme
```

## Ready now, turn on later (and uninstall)

For servers built before the customer's SOC is live - or before there is a site
collector - install the agent **stopped and disabled**: pointed at nothing,
enrolled nowhere, sending nothing. The script is kept on the machine, so turning
it on later needs **no internet**.

```bash
# Linux
curl -fsSL https://raw.githubusercontent.com/prosethsolutionsAI/pscyber-site-onboarding/main/agents/install-agent-linux.sh | sudo bash -s -- --prepare
sudo pscyber-agent --collector 192.168.10.50 --group Acme     # later: enrols through the collector and starts
sudo pscyber-agent --status                                     # OFF / READY / ON, and the manager address
sudo pscyber-agent --uninstall                                  # agent + health reporter + the kept script
```

```powershell
# Windows, PowerShell as Administrator
iwr -UseBasicParsing https://raw.githubusercontent.com/prosethsolutionsAI/pscyber-site-onboarding/main/agents/install-agent-windows.ps1 -OutFile $env:TEMP\pscyber-agent.ps1; powershell -ExecutionPolicy Bypass -File $env:TEMP\pscyber-agent.ps1 -Prepare
powershell -ExecutionPolicy Bypass -File "C:\Program Files\PSCyber\pscyber-agent.ps1" -Collector 192.168.10.50 -Group Acme
powershell -ExecutionPolicy Bypass -File "C:\Program Files\PSCyber\pscyber-agent.ps1" -Status
powershell -ExecutionPolicy Bypass -File "C:\Program Files\PSCyber\pscyber-agent.ps1" -Uninstall
```

The enrolment password is asked for (or `PSCYBER_ENROLL_PASSWORD`); it reaches
`agent-auth` through a root-only file removed straight after, never the command
line. Uninstall also removes the health reporter; Sysmon is left (`Sysmon64.exe -u`).
Remove the agent in the SOC as well. Uninstall refuses to run on a site collector.

**Proseth AIOps on the same server:** no conflict - AIOps adds only an rsyslog
file sending TCP 514 to the AIOps collector; this agent uses TCP 1514/1515 to the
PSCyber collector. Either can be prepared first. The two **collectors** must be
separate machines (both receive syslog on 514 and traps on 162).

**Cloned VMs:** a VM cloned from one that already had the agent carries the SAME
key - both then fight over one agent in the SOC. On the clone run
`sudo pscyber-agent --uninstall`, then install fresh.

## Windows (Server 2012 R2 and later, Windows 10/11)

**Script** - PowerShell **as Administrator**:

```powershell
Invoke-WebRequest https://raw.githubusercontent.com/prosethsolutionsAI/pscyber-site-onboarding/main/agents/install-agent-windows.ps1 -OutFile install-agent.ps1
powershell -ExecutionPolicy Bypass -File .\install-agent.ps1 -Collector 192.168.10.50 -Group Acme
```

It asks for the enrolment password (shows only how many characters it got),
checks the collector is reachable on 1514/1515 first, installs, starts the
service and waits until the agent reports **Connected**.

**By hand**:

```powershell
Invoke-WebRequest https://packages.wazuh.com/4.x/windows/wazuh-agent-4.14.7-1.msi -OutFile wazuh-agent.msi
msiexec.exe /i wazuh-agent.msi /q WAZUH_MANAGER="<COLLECTOR_IP>" WAZUH_AGENT_GROUP="<GROUP>" WAZUH_REGISTRATION_PASSWORD="<PASSWORD>" WAZUH_AGENT_NAME="<GROUP>-%COMPUTERNAME%"
NET START WazuhSvc
```

**Many machines (GPO / Intune / SCCM)**: deploy the same MSI with the same
properties on the command line; the name is taken from the computer name if
`WAZUH_AGENT_NAME` is left out, so set it to `<GROUP>-%COMPUTERNAME%` in the
deployment tool.

## Linux (Ubuntu, Debian, RHEL, Rocky, Alma, CentOS, Amazon Linux, SUSE)

**Script** - as root:

```bash
curl -sO https://raw.githubusercontent.com/prosethsolutionsAI/pscyber-site-onboarding/main/agents/install-agent-linux.sh
sudo bash install-agent-linux.sh --collector 192.168.10.50 --group Acme
```

**By hand** (Debian/Ubuntu, x86_64):

```bash
curl -so wazuh-agent.deb https://packages.wazuh.com/4.x/apt/pool/main/w/wazuh-agent/wazuh-agent_4.14.7-1_amd64.deb
sudo WAZUH_MANAGER='<COLLECTOR_IP>' WAZUH_AGENT_GROUP='<GROUP>' WAZUH_REGISTRATION_PASSWORD='<PASSWORD>' \
     WAZUH_AGENT_NAME="<GROUP>-$(hostname -s)" dpkg -i ./wazuh-agent.deb
sudo systemctl daemon-reload && sudo systemctl enable --now wazuh-agent
```

RHEL family: the same with
`https://packages.wazuh.com/4.x/yum/wazuh-agent-4.14.7-1.x86_64.rpm` and `rpm -ivh`.
ARM servers: `_arm64.deb` / `.aarch64.rpm`.

## macOS

```bash
curl -so wazuh-agent.pkg https://packages.wazuh.com/4.x/macos/wazuh-agent-4.14.7-1.arm64.pkg   # Intel: .intel64.pkg
echo "WAZUH_MANAGER='<COLLECTOR_IP>' && WAZUH_AGENT_GROUP='<GROUP>' && WAZUH_REGISTRATION_PASSWORD='<PASSWORD>' && WAZUH_AGENT_NAME='<GROUP>-$(scutil --get LocalHostName)'" > /tmp/wazuh_envs
sudo installer -pkg ./wazuh-agent.pkg -target /
sudo /Library/Ossec/bin/wazuh-control start
```

## Live device health (CPU, memory, disk)

Both scripts also install the small **PSCyber device-health reporter** once the agent is
connected. Every 30 seconds it sends the machine's CPU, memory, disk, network and top
processes to the **collector on TCP 1520**, which relays them to the SOC - so each machine's
page in the SOC (and your portal) shows them live. It sends **numbers only** (no logs, no
files, no passwords), holds no token, and cannot run anything. The program itself is
`pscyber-metrics.sh` / `pscyber-metrics.ps1` in this folder.

- Needs collector **1.2.5 or later** and **TCP 1520** open to the collector ([FIREWALL.md](../FIREWALL.md)).
  If 1520 does not answer, the script says so and skips it - the agent is unaffected.
- Skip it: `--no-health` (Linux) / `-NoHealth` (Windows).
- Machine that already has the agent: just re-run the script - it re-points the agent and adds the reporter.
- Remove: Linux `systemctl disable --now pscyber-metrics.timer && rm -f /usr/local/bin/pscyber-metrics /etc/pscyber-metrics.conf /etc/systemd/system/pscyber-metrics.*`;
  Windows `Unregister-ScheduledTask -TaskName 'PSCyber Metrics' -Confirm:$false; Remove-Item -Recurse "$env:ProgramData\PSCyber"`.

## Real-time registry monitoring (Windows, Sysmon)

The Windows script also installs **Microsoft Sysmon** (from download.sysinternals.com, signature
checked) with the PSCyber configuration `pscyber-sysmon.xml`. Every change to a registry key that
attackers use - autostart (Run/RunOnce), services, Winlogon, Image File Execution Options, LSA,
Defender and firewall settings, scheduled tasks, UAC - is reported **the moment it happens**, with
the user and the program, tagged with its MITRE ATT&CK technique. Skip it with `-NoSysmon`.

Machine that already has the agent (PowerShell as Administrator):

```powershell
iwr -UseBasicParsing https://raw.githubusercontent.com/prosethsolutionsAI/pscyber-site-onboarding/main/agents/install-sysmon-windows.ps1 -OutFile $env:TEMP\pscyber-sysmon.ps1; powershell -ExecutionPolicy Bypass -File $env:TEMP\pscyber-sysmon.ps1
```

Re-running it updates the configuration. Remove: `"C:\Program Files\PSCyber\Sysmon\Sysmon64.exe" -u`.

## A machine that ALREADY has a Wazuh agent

If it used to report straight to a Wazuh manager, only its manager address has to
change - its key stays valid, because the collector relays to the same SOC:

- **Both scripts do this automatically** when they find an agent already installed.
- By hand: in `ossec.conf` (Windows `C:\Program Files (x86)\ossec-agent\ossec.conf`,
  Linux `/var/ossec/etc/ossec.conf`) set `<address><COLLECTOR_IP></address>` inside
  `<client><server>`, then restart the agent (`Restart-Service WazuhSvc` /
  `systemctl restart wazuh-agent`).

If it belonged to a **different** Wazuh (another company's), remove it first and
install fresh.

## Check it worked

| | Command | Good result |
|---|---|---|
| Windows | `Get-Content "C:\Program Files (x86)\ossec-agent\ossec.log" -Tail 20` | `Connected to the server ([<COLLECTOR_IP>]:1514/tcp)` |
| Linux | `sudo grep "Connected to the server" /var/ossec/logs/ossec.log \| tail -1` | same |
| macOS | `sudo grep "Connected to the server" /Library/Ossec/logs/ossec.log \| tail -1` | same |

Then give Proseth the machine names so they confirm them in your SOC tenant.

## Common problems

| Symptom in ossec.log | Cause | Fix |
|---|---|---|
| `Unable to connect to enrollment service` / `(1216)` | 1515 blocked between the machine and the collector | open TCP 1515 to the collector ([FIREWALL.md](../FIREWALL.md)) |
| `Invalid password` / `(1405)` | wrong or missing enrolment password | re-run with the password from `pscyber-collector site-agent-command` |
| `Duplicate agent name` | the name is already used in the SOC | set a unique `WAZUH_AGENT_NAME` (`<group>-<host>`) |
| `Agent version must be lower or equal to manager version` | agent newer than 4.14.7 | install 4.14.7 |
| `Unable to connect to ... 1514` after enrolling | 1514 blocked, or the collector's tunnel is down | open TCP 1514; on the collector run `pscyber-collector status` |
