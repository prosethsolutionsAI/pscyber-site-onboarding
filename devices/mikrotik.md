# MikroTik (RouterOS 6 / 7)

Replace `<COLLECTOR_IP>` and `<COMMUNITY>`. Paste in a terminal (WinBox → New Terminal, or SSH).

```
/system logging action add name=pscyber target=remote remote=<COLLECTOR_IP> remote-port=514 bsd-syslog=yes syslog-facility=local7
/system logging add topics=info action=pscyber
/system logging add topics=warning action=pscyber
/system logging add topics=error action=pscyber
/system logging add topics=critical action=pscyber
/system logging add topics=account action=pscyber

/snmp community add name=<COMMUNITY> addresses=<COLLECTOR_IP>/32 read-access=yes write-access=no
/snmp set enabled=yes trap-community=<COMMUNITY> trap-version=2 trap-target=<COLLECTOR_IP> trap-generators=interfaces,start-trap
```

- `topics=account` carries logins and failed logins.
- If RouterOS rejects `bsd-syslog=yes` (newer 7.x releases), use
  `remote-log-format=bsd-syslog` instead.
- Firewall rule logging: add `log=yes log-prefix="DROP"` to the drop rules you care
  about - those messages then go out with topic `firewall`; add
  `/system logging add topics=firewall action=pscyber`.
- Check: `/log print where topics~"account"` shows what is being sent.
