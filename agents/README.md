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
