# Cisco

Replace `<COLLECTOR_IP>`, `<COMMUNITY>` and `<SOURCE_INTERFACE>` (for example
`Vlan10`, `Loopback0`, `GigabitEthernet0/0`).

## IOS / IOS-XE (Catalyst, ISR, ASR, C8000)

```
configure terminal
 service timestamps log datetime msec localtime show-timezone
 logging source-interface <SOURCE_INTERFACE>
 logging host <COLLECTOR_IP>
 logging trap informational
 ! login attempts and configuration changes
 login on-failure log
 login on-success log
 archive
  log config
   logging enable
   notify syslog contenttype plaintext
   hidekeys
 ! SNMP traps
 snmp-server community <COMMUNITY> RO
 snmp-server trap-source <SOURCE_INTERFACE>
 snmp-server enable traps snmp authentication linkdown linkup coldstart warmstart
 snmp-server enable traps config
 snmp-server host <COLLECTOR_IP> version 2c <COMMUNITY>
end
write memory
```

Management VRF: `logging host <COLLECTOR_IP> vrf Mgmt-vrf` and
`snmp-server host <COLLECTOR_IP> vrf Mgmt-vrf version 2c <COMMUNITY>`.
TCP syslog (IOS-XE): `logging host <COLLECTOR_IP> transport tcp port 514`.

## NX-OS (Nexus)

```
configure terminal
 logging server <COLLECTOR_IP> 6 use-vrf management
 logging source-interface mgmt0
 logging timestamp milliseconds
 snmp-server community <COMMUNITY> group network-operator
 snmp-server host <COLLECTOR_IP> traps version 2c <COMMUNITY>
 snmp-server host <COLLECTOR_IP> use-vrf management
 snmp-server enable traps link
 snmp-server enable traps snmp authentication
end
copy running-config startup-config
```

If the collector is reached in-band, use `use-vrf default` and a loopback as the source.

## ASA

```
configure terminal
 logging enable
 logging timestamp
 logging device-id hostname
 logging trap informational
 logging host <INTERFACE_NAME> <COLLECTOR_IP>
 snmp-server host <INTERFACE_NAME> <COLLECTOR_IP> community <COMMUNITY> version 2c
 snmp-server enable traps snmp authentication linkup linkdown coldstart warmstart
end
write memory
```

`<INTERFACE_NAME>` is the ASA interface name facing the collector (`inside`,
`management`). TCP instead of UDP: `logging host inside <COLLECTOR_IP> 6/514`
- but note an ASA with TCP syslog **blocks new connections** when the syslog
server is unreachable unless `logging permit-hostdown` is set. UDP is the safe default.

## Firepower Threat Defense (FTD, managed by FMC)

In FMC: **Devices → Platform Settings → (policy) → Syslog**:

1. *Logging Setup*: enable logging.
2. *Logging Destinations*: add **Syslog Servers**, severity *informational*.
3. *Syslog Servers*: add `<COLLECTOR_IP>`, UDP 514, the interface facing the collector.

Intrusion and connection events: **Policies → Actions → Alerts → Syslog alert**
pointing at the collector, then select it in the access-control policy's Logging
tab. Deploy.
