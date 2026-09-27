# Juniper (Junos: EX, QFX, MX, SRX)

Replace `<COLLECTOR_IP>`, `<COMMUNITY>` and `<LOCAL_IP>`.

```
configure
set system syslog host <COLLECTOR_IP> any notice
set system syslog host <COLLECTOR_IP> authorization info
set system syslog host <COLLECTOR_IP> interactive-commands info
set system syslog host <COLLECTOR_IP> change-log info
set system syslog host <COLLECTOR_IP> source-address <LOCAL_IP>

set snmp community <COMMUNITY> authorization read-only
set snmp trap-options source-address <LOCAL_IP>
set snmp trap-group PSCYBER version v2
set snmp trap-group PSCYBER categories link
set snmp trap-group PSCYBER categories authentication
set snmp trap-group PSCYBER categories startup
set snmp trap-group PSCYBER categories chassis
set snmp trap-group PSCYBER targets <COLLECTOR_IP>
commit check
commit and-quit
```

Management routing instance (`mgmt_junos`): add
`set system syslog host <COLLECTOR_IP> routing-instance mgmt_junos` and
`set snmp trap-group PSCYBER routing-instance mgmt_junos`.

## SRX: security (session and IDP) logs

Security logs on an SRX go out in **event** mode through the syslog configured above:

```
set security log mode event
set system syslog host <COLLECTOR_IP> any info
```

and on the policies you want logged:
`set security policies from-zone <A> to-zone <B> policy <NAME> then log session-close`.
Denied sessions (`then log session-init` on deny policies) are the most useful to start with.
