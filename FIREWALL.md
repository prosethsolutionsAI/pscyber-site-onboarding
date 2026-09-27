# Firewall and ports

Three places may need rules. The customer's **internet** firewall needs **outbound
only**; nothing is port-forwarded into the customer.

## 1. Inside the site: sources → collector

Open these from the device/server VLANs **to the collector's IP** (and on the
collector's own host firewall - the collector installer already does this when
`ufw` is active).

| From | To | Protocol / port | Purpose |
|---|---|---|---|
| Switches, routers, firewalls, ESXi, NAS … | Collector | **UDP 514** | syslog (most devices) |
| Devices that support syslog over TCP | Collector | **TCP 514** | syslog over TCP (preferred where available - no silent loss) |
| Devices sending SNMP traps | Collector | **UDP 162** | SNMP traps |
| Servers / VMs with the Wazuh agent | Collector | **TCP 1514** | agent events |
| Servers / VMs with the Wazuh agent | Collector | **TCP 1515** | agent enrolment (first start only, but keep it open) |
| Your admin workstation | Collector | TCP 22 | SSH to manage the collector |

## 2. Customer internet firewall: collector → SOC (outbound only)

| From | To | Protocol / port | Purpose |
|---|---|---|---|
| Collector | **SOC gateway** address | **TCP 51514** | agent + syslog + trap events, mutual TLS |
| Collector | **SOC gateway** address | **TCP 51515** | agent enrolment, mutual TLS |
| Collector | **SOC platform** address | **TCP 8443** | collector enrolment + 1-minute health heartbeat (HTTPS) |
| Collector | `packages.wazuh.com`, `raw.githubusercontent.com`, the OS package mirrors | TCP 443 | **install and updates only** |
| Collector | your NTP server / `pool.ntp.org` | UDP 123 | time |

The **SOC gateway and platform addresses are given by Proseth** with the install
command (usually the same address). If your firewall filters by destination, allow
exactly those; if it does SSL inspection, **exclude** 51514/51515 - the tunnel uses
mutual TLS and an inspecting proxy breaks it (the collector refuses a certificate
that is not the SOC's).

Nothing else leaves the site: agents, switches and firewalls **never** talk to the
internet for this.

## 3. At the SOC (Proseth's side - for reference)

Proseth publishes the gateway on a public address and forwards, to the SOC
gateway host:

| Public | → | Purpose |
|---|---|---|
| TCP 51514 | gateway 51514 | events from collectors |
| TCP 51515 | gateway 51515 | agent enrolment through collectors |
| TCP 8443 | platform 8443 | collector enrolment + heartbeat |

Where a customer has a fixed public IP, Proseth restricts these to it.

## Quick test from the collector

```bash
timeout 3 bash -c '</dev/tcp/<SOC_GATEWAY>/51514' && echo "51514 ok"
timeout 3 bash -c '</dev/tcp/<SOC_GATEWAY>/51515' && echo "51515 ok"
curl -sk -o /dev/null -w '%{http_code}\n' https://<SOC_PLATFORM>:8443/api/health   # 200
pscyber-collector status                                                      # all "active", agent "connected"
```

And from a server at the site, towards the collector:

```powershell
Test-NetConnection <COLLECTOR_IP> -Port 1514      # Windows: TcpTestSucceeded : True
```
```bash
timeout 3 bash -c '</dev/tcp/<COLLECTOR_IP>/1514' && echo ok     # Linux
```
