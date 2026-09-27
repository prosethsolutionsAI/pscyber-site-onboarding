# Huawei (VRP: S-series switches, AR/NE routers)

Replace `<COLLECTOR_IP>`, `<COMMUNITY>` and `<SOURCE_INTERFACE>` (for example
`Vlanif10`, `LoopBack0`, `MEth0/0/1`).

```
system-view
 info-center enable
 info-center loghost source <SOURCE_INTERFACE>
 info-center loghost <COLLECTOR_IP> facility local7
 info-center source default channel loghost log level informational
 info-center timestamp log date precision-time millisecond

 snmp-agent
 snmp-agent sys-info version v2c
 snmp-agent community read cipher <COMMUNITY>
 snmp-agent trap source <SOURCE_INTERFACE>
 snmp-agent target-host trap address udp-domain <COLLECTOR_IP> params securityname cipher <COMMUNITY> v2c
 snmp-agent trap enable
quit
save
```

Management VPN instance: `info-center loghost <COLLECTOR_IP> vpn-instance <NAME> facility local7`
and add `vpn-instance <NAME>` to the `target-host` line.

On some older VRP releases the keyword is `snmp-agent community read <COMMUNITY>`
(without `cipher`), and the trap line takes `securityname <COMMUNITY>`.
