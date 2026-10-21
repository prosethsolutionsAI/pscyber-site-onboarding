#!/bin/bash
# PSCyber device reporter 1.0.0 - CPU, memory, disks, network and top processes every 30 s.
# Sends numbers only: no logs, no file contents, no secrets.
# Remove: systemctl disable --now pscyber-metrics.timer; rm -f /usr/local/bin/pscyber-metrics /etc/pscyber-metrics.conf /etc/systemd/system/pscyber-metrics.*
set -u
. /etc/pscyber-metrics.conf
clean() { printf '%s' "$1" | tr -cd 'A-Za-z0-9 ._:/()+@-' | cut -c1-120; }
read -r _ a b c d e f g h _ < /proc/stat; t1=$((a+b+c+d+e+f+g+h)); i1=$((d+e)); sleep 1
read -r _ a b c d e f g h _ < /proc/stat; t2=$((a+b+c+d+e+f+g+h)); i2=$((d+e))
cpu=$(awk -v t=$((t2-t1)) -v i=$((i2-i1)) 'BEGIN{ if (t>0) printf "%.1f", 100*(t-i)/t; else print 0 }')
read -r l1 l5 l15 _ < /proc/loadavg
mt=$(awk '/^MemTotal:/{print $2}' /proc/meminfo); ma=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)
st=$(awk '/^SwapTotal:/{print $2}' /proc/meminfo); sf=$(awk '/^SwapFree:/{print $2}' /proc/meminfo)
swap=$(awk -v t="${st:-0}" -v f="${sf:-0}" 'BEGIN{ if (t>0) printf "%.1f", 100*(t-f)/t; else print 0 }')
up=$(cut -d. -f1 /proc/uptime)
disks=$(df -P -k -x tmpfs -x devtmpfs -x overlay -x squashfs -x efivarfs 2>/dev/null | awk 'NR>1 && $6 ~ /^\// {m=$6; gsub(/["\\]/,"",m); printf "%s{\"mount\":\"%s\",\"size_kb\":%s,\"used_kb\":%s}", (n++?",":""), m, $2, $3}')
read -r rx tx < <(awk -F'[: ]+' 'NR>2 && $2!="lo" {r+=$3; t+=$11} END{printf "%d %d", r, t}' /proc/net/dev)
top=$(ps -eo pid=,pcpu=,rss=,comm= --sort=-pcpu 2>/dev/null | head -5 | awk '{c=$4; for(i=5;i<=NF;i++) c=c" "$i; gsub(/["\\]/,"",c); printf "%s{\"name\":\"%s\",\"pid\":%s,\"cpu\":%s,\"rss_kb\":%s}", (n++?",":""), c, $1, $2, $3}')
agent=$(awk '{print $1; exit}' /var/ossec/etc/client.keys 2>/dev/null | tr -cd '0-9')
body=$(printf '{"version":"1.0.0","os":"linux","hostname":"%s","agent_id":"%s","cpu_pct":%s,"cores":%s,"load":[%s,%s,%s],"mem_total_kb":%s,"mem_avail_kb":%s,"swap_pct":%s,"uptime_s":%s,"disks":[%s],"net_rx":%s,"net_tx":%s,"top":[%s]}' \
  "$(clean "$(hostname)")" "$agent" "$cpu" "$(nproc)" "$l1" "$l5" "$l15" "$mt" "$ma" "$swap" "$up" "$disks" "${rx:-0}" "${tx:-0}" "$top")
auth=(); [ -n "${TOKEN:-}" ] && auth=(-H "Authorization: Bearer $TOKEN")
curl -sS -m 20 ${CURL_TLS:-} ${auth[@]+"${auth[@]}"} -H "Content-Type: application/json" \
  -d "$body" "$REPORT_URL" -o /dev/null -w "%{http_code}\n"
