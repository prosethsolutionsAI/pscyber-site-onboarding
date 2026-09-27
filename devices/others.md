# Other devices

Replace `<COLLECTOR_IP>` everywhere. Menu names move between releases - look for
**Remote logging**, **Syslog server** or **Log forwarding**.

## Sophos Firewall (SFOS / XGS)

1. **System services → Log settings → Syslog servers → Add**: name `PSCyber-Collector`,
   IP `<COLLECTOR_IP>`, port 514, facility DAEMON, severity **Information**, format
   **Standard format**.
2. In the **Log settings** table below, tick the collector's column for: Firewall
   (denied at least), IPS, Anti-virus, Web filter, ATP, Admin, Authentication, VPN.
3. **Apply**.

SNMP traps: **Administration → SNMP → Add trap receiver** (v2c), `<COLLECTOR_IP>`.

## pfSense

**Status → System Logs → Settings → Remote Logging Options**: tick *Enable Remote
Logging*, *Remote log servers* `<COLLECTOR_IP>:514`, *Remote Syslog Contents*
**Everything** (or System, Firewall events, Authentication, VPN). **Save**.
Firewall rules log only when *Log packets that are handled by this rule* is ticked.

## OPNsense

**System → Settings → Logging / targets → +**: transport **UDP(4)**, applications
*all*, levels *info … emerg*, hostname `<COLLECTOR_IP>`, port 514. **Save → Apply**.

## Ubiquiti UniFi (Network application)

**Settings → CyberSecure → Traffic Logging** (older: **Settings → System →
Remote Logging**): enable **SIEM Server / Remote Syslog**, host `<COLLECTOR_IP>`,
port 514. Applies to the gateway and managed devices.

## VMware ESXi

SSH or the ESXi Shell:

```
esxcli system syslog config set --loghost='udp://<COLLECTOR_IP>:514'
esxcli system syslog reload
esxcli network firewall ruleset set --ruleset-id=syslog --enabled=true
esxcli network firewall refresh
```

Or in vCenter: host → **Configure → System → Advanced System Settings →
`Syslog.global.logHost`** = `udp://<COLLECTOR_IP>:514` (and enable the *syslog*
outgoing firewall rule).

**vCenter Server** itself: VAMI `https://<vcenter>:5480` → **Syslog → Configure**,
`<COLLECTOR_IP>`, UDP, 514.

Virtual machines are covered by installing the Wazuh agent **inside** each VM
([agents](../agents/README.md)), not through the hypervisor.

## Linux servers without an agent (appliances)

Prefer the Wazuh agent. Where one cannot be installed, forward syslog - create
`/etc/rsyslog.d/90-pscyber.conf`:

```
*.info;mail.none;cron.none  @@<COLLECTOR_IP>:514
```

(`@@` = TCP, `@` = UDP), then `sudo systemctl restart rsyslog`.

## Synology / QNAP NAS

Synology: **Log Center → Log Sending → Send logs to a syslog server**:
`<COLLECTOR_IP>`, 514, UDP, format BSD.
QNAP: **QuLog Center → Log Sender → Add destination**: `<COLLECTOR_IP>`, 514, UDP.

## Anything else (UPS, printers, cameras, storage)

If it has a *syslog server* or *SNMP trap receiver* setting: `<COLLECTOR_IP>`,
UDP 514 / UDP 162 with the collector's community, severity informational. Check it
arrives with the **Verify** steps in [README.md](README.md#verify).
