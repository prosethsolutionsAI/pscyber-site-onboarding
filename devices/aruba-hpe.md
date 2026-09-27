# Aruba / HPE

Replace `<COLLECTOR_IP>` and `<COMMUNITY>`.

## AOS-CX (CX 6000/6100/6300/8xxx)

```
configure terminal
 logging <COLLECTOR_IP> severity info vrf mgmt
 snmp-server vrf mgmt
 snmp-server community <COMMUNITY>
 snmp-server host <COLLECTOR_IP> trap version v2c community <COMMUNITY> vrf mgmt
end
write memory
```

In-band (no OOBM): replace `vrf mgmt` with `vrf default`.
TCP: `logging <COLLECTOR_IP> tcp 514 severity info vrf mgmt`.

## AOS-S / ProCurve (2530, 2930, 3810, 5400R)

```
configure
 logging <COLLECTOR_IP>
 logging severity info
 logging facility local7
 snmp-server community "<COMMUNITY>" operator
 snmp-server host <COLLECTOR_IP> community "<COMMUNITY>"
 snmp-server enable traps authentication
write memory
```

Out-of-band management port: `logging <COLLECTOR_IP> oobm`.

## Aruba Instant / Central-managed APs

Syslog is set per group in **Aruba Central → Devices → Access Points → Config →
System → Syslog server**: `<COLLECTOR_IP>`. Instant VC (standalone): **System →
Monitoring → Syslog server**.
