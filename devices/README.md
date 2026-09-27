# Network devices → Site Collector (syslog + SNMP traps)

Point every switch, router, firewall and hypervisor at the **collector's IP**:

| Send | To | Port |
|---|---|---|
| **Syslog** | collector | **UDP 514** (or **TCP 514** where the device supports it) |
| **SNMP traps** (v2c) | collector | **UDP 162**, with the collector's community |

Each device's logs land on the collector in `/var/log/pscyber/syslog/<device-ip>.log`
and are shipped to the SOC; the SOC sees them under the **device's IP**. Traps land
in `/var/log/pscyber/snmptraps.log`. The SOC raises alerts on, among others,
**interface down (level 8)**, **SNMP authentication failure (level 9)**, device
restarts, failed logins and configuration changes.

## Vendor guides

| Vendor | Guide |
|---|---|
| Cisco IOS / IOS-XE, NX-OS, ASA, Firepower (FTD) | [cisco.md](cisco.md) |
| Fortinet FortiGate, FortiSwitch | [fortinet.md](fortinet.md) |
| Palo Alto Networks (PAN-OS) | [paloalto.md](paloalto.md) |
| Juniper (Junos: EX, QFX, MX, SRX) | [juniper.md](juniper.md) |
| Huawei (VRP switches and routers) | [huawei.md](huawei.md) |
| Aruba / HPE (AOS-CX, AOS-S / ProCurve) | [aruba-hpe.md](aruba-hpe.md) |
| MikroTik (RouterOS) | [mikrotik.md](mikrotik.md) |
| Sophos, pfSense, OPNsense, Ubiquiti UniFi, VMware ESXi / vCenter, Linux, NAS, anything else | [others.md](others.md) |

In every guide replace:

| Placeholder | With |
|---|---|
| `<COLLECTOR_IP>` | the collector's LAN IP |
| `<COMMUNITY>` | the SNMP community the collector was installed with |
| `<SOURCE_INTERFACE>` / `<LOCAL_IP>` | the device's interface/IP that faces the collector (so every message comes from ONE stable address) |

## Rules of thumb

- **Source address**: set it (the `source-interface` / `source-ip` lines). A device
  that sends from whichever interface is nearest shows up in the SOC as several
  devices.
- **Severity informational** (6). Not debugging.
- **NTP on**, and the device's timezone set - see the main README.
- **Firewall traffic logs** are large. Start with security events (IPS, AV, web
  filter, VPN, admin logins, config changes) and add allowed-traffic logs only where
  Proseth asks; denied traffic is usually worth sending.
- If a management **VRF** is used (`vrf mgmt`, `use-vrf management`), the collector must
  be reachable **in that VRF**.

## Verify

On the collector:

```bash
ls -l /var/log/pscyber/syslog/                      # one file per device that has sent something
sudo tail -f /var/log/pscyber/syslog/<device-ip>.log
sudo tail -f /var/log/pscyber/snmptraps.log
pscyber-collector status                            # "syslog sources: N"
```

Generate an event on the device - log out and in again, or enter and leave
configuration mode - and watch it appear. For traps, shut and re-enable an
**unused** port, or send a test trap from the collector itself:

```bash
snmptrap -v 2c -c <COMMUNITY> 127.0.0.1 '' 1.3.6.1.6.3.1.1.5.3     # arrives in snmptraps.log
logger -n 127.0.0.1 -P 514 -d "PSCyber test message"            # arrives in syslog/127.0.0.1.log
```

> A **new** device's very first lines can take about a minute to be picked up by the
> collector's agent (it scans for new per-device files once a minute). Generate a
> second event after a minute if the first did not reach the SOC.

Nothing arriving? Check in this order: the device's own log shows it is sending;
the VLAN firewall allows UDP 514 / UDP 162 to the collector ([FIREWALL.md](../FIREWALL.md));
`sudo tcpdump -ni any port 514 or port 162` on the collector shows packets;
for traps, the community on the device matches the collector's exactly.
