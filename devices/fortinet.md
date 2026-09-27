# Fortinet

Replace `<COLLECTOR_IP>`, `<COMMUNITY>` and `<LOCAL_IP>` (the FortiGate's IP
facing the collector). With VDOMs, run these under `config global`.

## FortiGate (FortiOS 6.4 / 7.x)

```
config log syslogd setting
    set status enable
    set server "<COLLECTOR_IP>"
    set mode udp
    set port 514
    set facility local7
    set source-ip "<LOCAL_IP>"
    set format default
end
config log syslogd filter
    set severity information
    set forward-traffic enable
    set local-traffic enable
    set multicast-traffic disable
    set sniffer-traffic disable
    set anomaly enable
end
```

`mode reliable` sends over TCP 514 instead of UDP.

**Which logs**: a firewall policy only logs what its *Log Allowed Traffic* setting
says. Start with **Security Events** (`set logtraffic utm`) on internet-facing
policies; switch individual policies to **All Sessions** (`set logtraffic all`)
where Proseth asks. Admin logins, VPN, IPS, antivirus and web-filter events are
sent regardless.

GUI alternative: **Log & Report → Log Settings → Send logs to syslog**, IP `<COLLECTOR_IP>`.

### SNMP traps

```
config system snmp sysinfo
    set status enable
end
config system snmp community
    edit 1
        set name "<COMMUNITY>"
        config hosts
            edit 1
                set ip <COLLECTOR_IP> 255.255.255.255
                set host-type trap
            next
        end
        set trap-v1-status disable
        set trap-v2c-status enable
    next
end
```

## FortiSwitch

Managed by a FortiGate (FortiLink): the switch's events arrive with the
FortiGate's logs - nothing to do on the switch.

Standalone:

```
config log syslogd setting
    set status enable
    set server "<COLLECTOR_IP>"
    set port 514
    set facility local7
end
config log syslogd filter
    set severity information
end
```
