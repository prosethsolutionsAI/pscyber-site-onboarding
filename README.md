# PSCyber Site Onboarding

How to connect a customer site to the **Proseth SOC** once the
[PSCyber Site Collector](https://github.com/prosethsolutionsAI/pscyber-site-collector)
is installed there:

| What | Guide |
|---|---|
| **Firewall and ports** - what to open, in which direction, to which address | [FIREWALL.md](FIREWALL.md) |
| **Servers and VMs** (Windows, Linux, macOS) - install the Wazuh agent pointing at the collector | [agents/](agents/README.md) |
| **Switches, routers, firewalls, hypervisors** - send syslog and SNMP traps to the collector | [devices/](devices/README.md) |
| **Microsoft 365** - sign-ins, mailbox rules, file sharing: the collector fetches them from Microsoft | [microsoft365.md](microsoft365.md) |

```
                     CUSTOMER SITE                                   │        PROSETH SOC
                                                                     │
 Windows / Linux / macOS agents ──TCP 1514, 1515──┐                  │
 switches, routers, firewalls ────UDP/TCP 514─────┤  Site Collector  │
 devices sending SNMP traps ──────UDP 162─────────┘  (one Linux VM) ─┼──► SOC gateway ──► Wazuh ──► Agentic AI
                                                          outbound only: TCP 51514, 51515 (mutual TLS)
                                                                         TCP 8443 (enrolment, health)
```

**Everything at the site talks only to the collector.** Only the collector talks
to the SOC, only outbound, through one mutual-TLS tunnel. Nothing inbound has to be
opened on the customer's internet firewall, and no device at the site needs
internet access.

## Before you start - collect these four values

| Value | Where it comes from | Example |
|---|---|---|
| **Collector IP** | the collector's LAN address - `hostname -I` on it, also printed at the end of its install | `192.168.10.50` |
| **Agent group** | on the collector: `pscyber-collector site-agent-command` | `Acme` |
| **Enrolment password** | same command, or ask Proseth | *(given privately)* |
| **SNMP community** | the one chosen when the collector was installed | *(given privately)* |

## Order of work

1. Open the ports in [FIREWALL.md](FIREWALL.md) (internal VLAN rules to the collector,
   and the collector's outbound rule).
2. Install agents on servers: [agents/README.md](agents/README.md).
3. Point network devices at the collector: [devices/README.md](devices/README.md).
4. Check each source arrived ([devices/README.md → Verify](devices/README.md#verify)),
   then ask Proseth to confirm it appears in your SOC tenant.

## Good practice for every source

- **Time**: every device on NTP. A device with the wrong clock sends events the SOC
  sorts into the wrong hour, and correlation across devices stops working.
- **Hostname** set on every device - it is what analysts see.
- **Severity**: *informational* is right for most devices. *debugging* floods the
  link and hides the real events.
- **One destination per device** is enough - the collector forwards to the SOC; do not
  also send the same logs directly.

## Files

| File | Purpose |
|---|---|
| `FIREWALL.md` | Every port, direction and protocol |
| `agents/README.md` | Agent installation and re-pointing existing agents |
| `agents/install-agent-linux.sh` | One-command Linux agent install (Debian/Ubuntu/RHEL family) |
| `agents/install-agent-windows.ps1` | One-command Windows agent install |
| `devices/*.md` | Syslog + SNMP configuration per vendor |
| `microsoft365.md` | Microsoft 365 audit logs: the app to create, the one command, the firewall |
