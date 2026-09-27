#!/usr/bin/env bash
# PSCyber Site Onboarding - install (or re-point) the Wazuh agent on a Linux
# server so it reports through the site's PSCyber Site Collector.
#
#   sudo bash install-agent-linux.sh --collector 192.168.10.50 --group Acme [--password X] [--name Acme-web01]
#
# Anything not given is asked for. The enrolment password can also come from
# the environment (PSCYBER_ENROLL_PASSWORD) so it is not in the shell history.
set -uo pipefail

WAZUH_VERSION="${WAZUH_VERSION:-4.14.7}"
COLLECTOR="${PSCYBER_COLLECTOR:-}"; GROUP="${PSCYBER_GROUP:-}"
PASSWORD="${PSCYBER_ENROLL_PASSWORD:-}"; NAME="${PSCYBER_AGENT_NAME:-}"

say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m ok\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31mERR\033[0m %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --collector) COLLECTOR="$2"; shift 2 ;;
    --group)     GROUP="$2"; shift 2 ;;
    --password)  PASSWORD="$2"; shift 2 ;;
    --name)      NAME="$2"; shift 2 ;;
    -h|--help)   sed -n '2,9p' "$0"; exit 0 ;;
    *) die "unknown option $1 (see --help)" ;;
  esac
done
[ "$(id -u)" -eq 0 ] || die "run as root (sudo bash $0 ...)"

[ -n "$COLLECTOR" ] || read -r -p "  Collector IP: " COLLECTOR
[ -n "$COLLECTOR" ] || die "the collector IP is required"

CONF=/var/ossec/etc/ossec.conf
if [ -x /var/ossec/bin/wazuh-control ] && [ -f "$CONF" ]; then
  # Already an agent: only the manager address changes - its key stays valid,
  # because the collector relays to the same SOC.
  say "a Wazuh agent is already installed - pointing it at the collector $COLLECTOR"
  cp -p "$CONF" "$CONF.bak-$(date +%Y%m%d%H%M%S)"
  sed -i "0,/<address>[^<]*<\/address>/s//<address>$COLLECTOR<\/address>/" "$CONF"
  systemctl restart wazuh-agent || die "wazuh-agent did not restart (journalctl -u wazuh-agent)"
else
  [ -n "$GROUP" ] || read -r -p "  Agent group (pscyber-collector site-agent-command shows it): " GROUP
  [ -n "$GROUP" ] || die "the agent group is required - it is what puts this machine in your SOC tenant"
  if [ -z "$PASSWORD" ]; then
    read -r -p "  Enrolment password (paste, then Enter): " PASSWORD
    printf '\033[1A\033[2K  Enrolment password: got %s characters\n' "${#PASSWORD}"
  fi
  [ -n "$NAME" ] || NAME="${GROUP}-$(hostname -s)"

  say "checking the collector $COLLECTOR is reachable"
  for p in 1514 1515; do
    timeout 3 bash -c "</dev/tcp/$COLLECTOR/$p" 2>/dev/null || die "cannot reach $COLLECTOR TCP $p - open it between this server and the collector (FIREWALL.md)"
  done
  ok "TCP 1514 and 1515 reachable"

  ARCH=$(uname -m)
  export WAZUH_MANAGER="$COLLECTOR" WAZUH_AGENT_GROUP="$GROUP" WAZUH_AGENT_NAME="$NAME"
  [ -n "$PASSWORD" ] && export WAZUH_REGISTRATION_PASSWORD="$PASSWORD"
  cd /tmp
  if command -v dpkg >/dev/null && command -v apt-get >/dev/null; then
    case "$ARCH" in x86_64) A=amd64 ;; aarch64) A=arm64 ;; *) die "unsupported CPU $ARCH" ;; esac
    say "installing wazuh-agent $WAZUH_VERSION ($A .deb) as $NAME in group $GROUP"
    curl -sfo wazuh-agent.deb "https://packages.wazuh.com/4.x/apt/pool/main/w/wazuh-agent/wazuh-agent_${WAZUH_VERSION}-1_${A}.deb" \
      || die "download failed - this server needs HTTPS to packages.wazuh.com just for the install, or copy the .deb over"
    dpkg -i ./wazuh-agent.deb >/tmp/wazuh-agent-install.log 2>&1 || die "install failed (see /tmp/wazuh-agent-install.log)"
    rm -f wazuh-agent.deb
  elif command -v rpm >/dev/null; then
    case "$ARCH" in x86_64) A=x86_64 ;; aarch64) A=aarch64 ;; *) die "unsupported CPU $ARCH" ;; esac
    say "installing wazuh-agent $WAZUH_VERSION ($A .rpm) as $NAME in group $GROUP"
    curl -sfo wazuh-agent.rpm "https://packages.wazuh.com/4.x/yum/wazuh-agent-${WAZUH_VERSION}-1.${A}.rpm" \
      || die "download failed - this server needs HTTPS to packages.wazuh.com just for the install, or copy the .rpm over"
    rpm -ivh ./wazuh-agent.rpm >/tmp/wazuh-agent-install.log 2>&1 || die "install failed (see /tmp/wazuh-agent-install.log)"
    rm -f wazuh-agent.rpm
  else
    die "no dpkg or rpm on this system - install the agent package by hand (agents/README.md)"
  fi
  unset WAZUH_REGISTRATION_PASSWORD
  systemctl daemon-reload
  systemctl enable --now wazuh-agent >/dev/null 2>&1 || die "wazuh-agent did not start (journalctl -u wazuh-agent)"
fi

say "waiting for the agent to connect (up to 60 s)"
for _ in $(seq 1 30); do
  if grep -q "Connected to the server (\[$COLLECTOR\]" /var/ossec/logs/ossec.log 2>/dev/null; then
    ok "connected to the SOC through the collector $COLLECTOR"
    exit 0
  fi
  sleep 2
done
echo "Not connected yet. Last messages:"
grep -E "ERROR|WARNING|Connected" /var/ossec/logs/ossec.log | tail -5
echo "See 'Common problems' in agents/README.md."
exit 1
