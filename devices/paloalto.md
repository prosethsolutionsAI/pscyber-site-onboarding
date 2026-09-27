# Palo Alto Networks (PAN-OS)

PAN-OS forwards logs through **profiles**, so it is three steps in the web UI
(Panorama: the same in the template / device group), then **Commit**.

## 1. Syslog server profile

**Device → Server Profiles → Syslog → Add**

| Field | Value |
|---|---|
| Name | `PSCyber-Collector` |
| Syslog Server | `<COLLECTOR_IP>` |
| Transport | UDP (or TCP) |
| Port | 514 |
| Format | **BSD** |
| Facility | LOG_USER |

## 2. Send system, configuration and user-ID logs

**Device → Log Settings**: in **System**, **Configuration**, **User-ID** and
**GlobalProtect**, *Add* a match list with filter *All Logs* and forward method
**Syslog → PSCyber-Collector**.

## 3. Send traffic and threat logs

**Objects → Log Forwarding → Add** a profile (name it `default` and PAN-OS
applies it to new security rules automatically):

| Log type | Filter | Forward to |
|---|---|---|
| threat | All Logs | Syslog: PSCyber-Collector |
| url | All Logs | Syslog: PSCyber-Collector |
| wildfire | All Logs | Syslog: PSCyber-Collector |
| traffic | `(action neq allow)` to start with - denied only | Syslog: PSCyber-Collector |

Attach the profile to the security rules: **Policies → Security → (rule) →
Actions → Log Forwarding**. Allowed traffic is large - add it only where Proseth asks.

The logs leave from the **management interface** unless a *Service Route* for
Syslog says otherwise (**Device → Setup → Services → Service Route Configuration**).

## SNMP traps

**Device → Server Profiles → SNMP Trap → Add**: version **V2c**, server
`<COLLECTOR_IP>`, community `<COMMUNITY>`. Select it in **Device → Log Settings →
System** for the severities you want (high and critical as a minimum).

**Commit.**
