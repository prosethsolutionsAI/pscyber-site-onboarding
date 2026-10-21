#!/usr/bin/env bash
# PSCyber Site Onboarding - install (or re-point) the Wazuh agent on a Linux
# server so it reports through the site's PSCyber Site Collector.
#
#   sudo bash install-agent-linux.sh --collector 192.168.10.50 --group Acme [--password X] [--name Acme-web01] [--no-health]
#
# One line, nothing to save first (asks for the enrolment password):
#   curl -fsSL https://raw.githubusercontent.com/prosethsolutionsAI/pscyber-site-onboarding/main/agents/install-agent-linux.sh | sudo bash -s -- --collector 192.168.10.50 --group Acme
#
# Anything not given is asked for (from the terminal, so it works piped from curl too). The enrolment password can also come from
# the environment (PSCYBER_ENROLL_PASSWORD) so it is not in the shell history.
# It also installs the PSCyber device-health reporter (live CPU, memory, disk to the
# collector on TCP 1520, numbers only) unless --no-health is given.
set -uo pipefail

WAZUH_VERSION="${WAZUH_VERSION:-4.14.7}"
COLLECTOR="${PSCYBER_COLLECTOR:-}"; GROUP="${PSCYBER_GROUP:-}"
PASSWORD="${PSCYBER_ENROLL_PASSWORD:-}"; NAME="${PSCYBER_AGENT_NAME:-}"; HEALTH=1
RAW="https://raw.githubusercontent.com/prosethsolutionsAI/pscyber-site-onboarding/main/agents"

say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m ok\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31mERR\033[0m %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --collector) COLLECTOR="$2"; shift 2 ;;
    --group)     GROUP="$2"; shift 2 ;;
    --password)  PASSWORD="$2"; shift 2 ;;
    --name)      NAME="$2"; shift 2 ;;
    --no-health) HEALTH=0; shift ;;
    -h|--help)   sed -n '2,14p' "$0" 2>/dev/null || echo "see agents/README.md"; exit 0 ;;
    *) die "unknown option $1 (see --help)" ;;
  esac
done
[ "$(id -u)" -eq 0 ] || die "run as root (sudo bash ...)"
# Questions are read from the TERMINAL, not stdin: piped from curl, stdin is this script.
ask() {
  [ -r /dev/tty ] || die "$1 is required - pass it as an option (no terminal to ask on)"
  read -r -p "  $1: " "$2" </dev/tty
}

[ -n "$COLLECTOR" ] || ask "Collector IP" COLLECTOR
[ -n "$COLLECTOR" ] || die "the collector IP is required"

CONF=/var/ossec/etc/ossec.conf
LOG=/var/ossec/logs/ossec.log
# Only log lines written AFTER this point count: an old "Connected" from before the restart
# must not read as success (seen on a re-run).
LOG_FROM=$(stat -c %s "$LOG" 2>/dev/null || echo 0)
if [ -x /var/ossec/bin/wazuh-control ] && [ -f "$CONF" ]; then
  # Already an agent: only the manager address changes - its key stays valid,
  # because the collector relays to the same SOC.
  say "a Wazuh agent is already installed - pointing it at the collector $COLLECTOR"
  cp -p "$CONF" "$CONF.bak-$(date +%Y%m%d%H%M%S)"
  sed -i "0,/<address>[^<]*<\/address>/s//<address>$COLLECTOR<\/address>/" "$CONF"
  systemctl restart wazuh-agent || die "wazuh-agent did not restart (journalctl -u wazuh-agent)"
else
  [ -n "$GROUP" ] || ask "Agent group (pscyber-collector site-agent-command shows it)" GROUP
  [ -n "$GROUP" ] || die "the agent group is required - it is what puts this machine in your SOC tenant"
  if [ -z "$PASSWORD" ]; then
    ask "Enrolment password (paste, then Enter)" PASSWORD
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

# Device health: live CPU, memory, disks, network and top processes, every 30 s, to the
# collector (TCP 1520), which relays it to the SOC - numbers only, no token on this machine.
# The reporter program comes with this script (beside it, or from this repository over HTTPS),
# never from the network the readings travel on.
install_health() {
  if ! timeout 3 bash -c "</dev/tcp/$COLLECTOR/1520" 2>/dev/null; then
    echo "  (device health skipped: the collector does not answer on TCP 1520 - update it to 1.2.5+ and open 1520, then re-run this script)"
    return
  fi
  local src; src="$(dirname "$0")/pscyber-metrics.sh"
  if [ ! -f "$src" ]; then
    src=/tmp/pscyber-metrics.sh
    curl -sfo "$src" "$RAW/pscyber-metrics.sh" || { echo "  (device health skipped: could not download pscyber-metrics.sh)"; return; }
  fi
  umask 077
  printf 'REPORT_URL="http://%s:1520/report"\nTOKEN=""\nCURL_TLS=""\n' "$COLLECTOR" > /etc/pscyber-metrics.conf
  install -m 700 "$src" /usr/local/bin/pscyber-metrics
  cat > /etc/systemd/system/pscyber-metrics.service <<'EOF'
[Unit]
Description=PSCyber device health report
[Service]
Type=oneshot
ExecStart=/usr/local/bin/pscyber-metrics
Nice=10
EOF
  cat > /etc/systemd/system/pscyber-metrics.timer <<'EOF'
[Unit]
Description=PSCyber device health report every 30 s
[Timer]
OnBootSec=30s
OnUnitActiveSec=30s
AccuracySec=2s
[Install]
WantedBy=timers.target
EOF
  systemctl daemon-reload
  systemctl enable --now pscyber-metrics.timer >/dev/null 2>&1
  local code; code=$(/usr/local/bin/pscyber-metrics 2>/dev/null || true)
  if [ "$code" = "200" ]; then ok "device health reporting through the collector (live CPU, memory, disk)"
  else echo "  device health installed; first report answered HTTP ${code:-none} (the collector relays it once it is 1.2.5+)"; fi
  echo "  remove later: systemctl disable --now pscyber-metrics.timer && rm -f /usr/local/bin/pscyber-metrics /etc/pscyber-metrics.conf /etc/systemd/system/pscyber-metrics.*"
}

say "waiting for the agent to connect (up to 60 s)"
for _ in $(seq 1 30); do
  if tail -c +"$((LOG_FROM + 1))" "$LOG" 2>/dev/null | grep -q "Connected to the server (\[$COLLECTOR\]"; then
    ok "connected to the SOC through the collector $COLLECTOR"
    [ "$HEALTH" = 1 ] && install_health
    exit 0
  fi
  sleep 2
done
echo "Not connected yet. Last messages:"
tail -c +"$((LOG_FROM + 1))" "$LOG" 2>/dev/null | grep -E "ERROR|WARNING|Connected" | tail -5
echo "See 'Common problems' in agents/README.md."
exit 1
