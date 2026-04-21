#!/usr/bin/env bash
# =============================================================================
# setup.sh  ─  Traffic Classification SDN Project ─ One-Command Setup
# =============================================================================
# Usage:
#   chmod +x setup.sh
#   ./setup.sh                  ← full install
#   ./setup.sh run              ← start POX (allowed mode)
#   ./setup.sh run-block-udp    ← start POX with UDP blocked
#   ./setup.sh run-block-icmp   ← start POX with ICMP blocked
#   ./setup.sh run-block-ports  ← block TCP:23,TCP:22,UDP:161
#   ./setup.sh topo             ← launch Mininet (star topology)
#   ./setup.sh scenario1        ← allowed vs blocked demo
#   ./setup.sh scenario2        ← normal vs failure demo
#   ./setup.sh stats            ← live stats dashboard
#   ./setup.sh validate         ← run validation suite
#   ./setup.sh wireshark        ← open Wireshark on s1-eth1
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POX_DIR="$SCRIPT_DIR/pox"
CONTROLLER_DIR="$SCRIPT_DIR/controller"
LOG_DIR="$SCRIPT_DIR/logs"

G='\033[0;32m'; Y='\033[1;33m'; R='\033[0;31m'; C='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${G}[INFO]${NC} $*"; }
warn()  { echo -e "${Y}[WARN]${NC} $*"; }
error() { echo -e "${R}[ERR ]${NC} $*" >&2; exit 1; }
step()  { echo -e "\n${C}══ $* ══${NC}"; }

# =============================================================================
check_prereqs() {
    step "Checking prerequisites"
    local missing=()
    for cmd in python3 git ovs-vsctl mn iperf; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        warn "Missing: ${missing[*]} – installing..."
        sudo apt-get update -qq
        sudo apt-get install -y \
            openvswitch-switch mininet git \
            python3 python3-pip iperf iperf3 \
            curl net-tools wireshark-common \
            tcpdump 2>/dev/null || true
    fi
    info "Prerequisites OK"
}

# =============================================================================
setup_pox() {
    step "Setting up POX controller"
    if [[ -d "$POX_DIR" ]]; then
        info "POX found – updating..."
        git -C "$POX_DIR" pull --quiet || true
    else
        info "Cloning POX..."
        git clone --quiet https://github.com/noxrepo/pox.git "$POX_DIR"
    fi

    # Create ext package for our controller
    mkdir -p "$POX_DIR/ext/traffic_classifier"
    touch    "$POX_DIR/ext/traffic_classifier/__init__.py"

    # Symlink every controller + utils file
    for src in "$CONTROLLER_DIR"/*.py; do
        [[ -f "$src" ]] || continue
        dst="$POX_DIR/ext/traffic_classifier/$(basename "$src")"
        ln -sf "$src" "$dst"
        info "  linked: $(basename "$src")"
    done

    info "POX ready at $POX_DIR"
}

# =============================================================================
start_ovs() {
    step "Starting Open vSwitch"
    sudo service openvswitch-switch start 2>/dev/null || \
    sudo systemctl start openvswitch-switch 2>/dev/null || true
    sudo ovs-vsctl show &>/dev/null && info "OVS running" || \
        error "OVS failed to start"
}

# =============================================================================
# Controller runners
# =============================================================================
_pox_base() {
    cd "$POX_DIR"
    mkdir -p "$LOG_DIR"
    echo ""
    info "POX controller starting on port 6633..."
    info "Dashboard refreshes every 5s in this terminal."
    info "Open a new terminal and run:  ./setup.sh topo"
    echo ""
}

run_normal() {
    _pox_base
    ./pox.py \
        log.level --INFO \
        log.color \
        openflow.of_01 --port=6633 \
        traffic_classifier.traffic_classifier \
            --block_udp=False \
            --block_icmp=False \
            --stats_interval=10 \
        2>&1 | tee "$LOG_DIR/pox.log"
}

run_block_udp() {
    _pox_base
    info "Mode: UDP BLOCKED"
    ./pox.py \
        log.level --INFO \
        log.color \
        openflow.of_01 --port=6633 \
        traffic_classifier.traffic_classifier \
            --block_udp=True \
            --block_icmp=False \
            --stats_interval=10 \
        2>&1 | tee "$LOG_DIR/pox_block_udp.log"
}

run_block_icmp() {
    _pox_base
    info "Mode: ICMP BLOCKED"
    ./pox.py \
        log.level --INFO \
        log.color \
        openflow.of_01 --port=6633 \
        traffic_classifier.traffic_classifier \
            --block_udp=False \
            --block_icmp=True \
            --stats_interval=10 \
        2>&1 | tee "$LOG_DIR/pox_block_icmp.log"
}

run_block_ports() {
    _pox_base
    info "Mode: TCP ports 22,23 blocked; UDP port 161 blocked"
    ./pox.py \
        log.level --INFO \
        log.color \
        openflow.of_01 --port=6633 \
        traffic_classifier.traffic_classifier \
            --block_udp=False \
            --block_icmp=False \
            --blocked_tcp_ports="22,23" \
            --blocked_udp_ports="161" \
            --stats_interval=10 \
        2>&1 | tee "$LOG_DIR/pox_block_ports.log"
}

# =============================================================================
run_topo() {
    step "Launching Mininet"
    sudo mn -c 2>/dev/null || true   # clean previous
    sudo python3 "$SCRIPT_DIR/topology/topology.py"
}

run_scenario() {
    local s="${1:-1}"
    step "Running Scenario $s"
    sudo mn -c 2>/dev/null || true
    sudo python3 "$SCRIPT_DIR/topology/topology.py" "$s"
}

show_stats() {
    python3 "$SCRIPT_DIR/tests/display_stats.py"
}

run_validate() {
    step "Running validation suite"
    python3 "$SCRIPT_DIR/tests/validate.py" "$@"
}

open_wireshark() {
    step "Opening Wireshark"
    info "Capturing on s1-eth1 (traffic between s1 and h1)"
    sudo wireshark -i s1-eth1 -k &
}

# =============================================================================
full_install() {
    step "Traffic Classification SDN – Full Setup"
    check_prereqs
    setup_pox
    start_ovs
    mkdir -p "$LOG_DIR"

    echo ""
    echo -e "${G}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${G}║         SETUP COMPLETE  ─  Quick Reference               ║${NC}"
    echo -e "${G}╠══════════════════════════════════════════════════════════╣${NC}"
    echo -e "${G}║${NC}  Terminal 1 (controller):                               ${G}║${NC}"
    echo -e "${G}║${NC}    ./setup.sh run              # all traffic allowed     ${G}║${NC}"
    echo -e "${G}║${NC}    ./setup.sh run-block-udp    # UDP blocked             ${G}║${NC}"
    echo -e "${G}║${NC}    ./setup.sh run-block-icmp   # ICMP blocked            ${G}║${NC}"
    echo -e "${G}║${NC}    ./setup.sh run-block-ports  # specific ports blocked  ${G}║${NC}"
    echo -e "${G}║${NC}                                                          ${G}║${NC}"
    echo -e "${G}║${NC}  Terminal 2 (Mininet):                                   ${G}║${NC}"
    echo -e "${G}║${NC}    ./setup.sh topo             # star topology + CLI     ${G}║${NC}"
    echo -e "${G}║${NC}    ./setup.sh scenario1        # allowed vs blocked      ${G}║${NC}"
    echo -e "${G}║${NC}    ./setup.sh scenario2        # normal vs failure       ${G}║${NC}"
    echo -e "${G}║${NC}                                                          ${G}║${NC}"
    echo -e "${G}║${NC}  Terminal 3 (monitoring):                                ${G}║${NC}"
    echo -e "${G}║${NC}    ./setup.sh stats            # live dashboard          ${G}║${NC}"
    echo -e "${G}║${NC}    ./setup.sh validate         # run all tests           ${G}║${NC}"
    echo -e "${G}║${NC}    ./setup.sh wireshark        # packet capture          ${G}║${NC}"
    echo -e "${G}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# =============================================================================
case "${1:-install}" in
    install)           full_install ;;
    run)               run_normal ;;
    run-block-udp)     run_block_udp ;;
    run-block-icmp)    run_block_icmp ;;
    run-block-ports)   run_block_ports ;;
    topo)              run_topo ;;
    scenario1)         run_scenario 1 ;;
    scenario2)         run_scenario 2 ;;
    stats)             show_stats ;;
    validate)          run_validate "${@:2}" ;;
    wireshark)         open_wireshark ;;
    clean)
        info "Cleaning Mininet state..."
        sudo mn -c 2>/dev/null || true
        ;;
    *)
        echo "Usage: $0 {install|run|run-block-udp|run-block-icmp|run-block-ports"
        echo "           |topo|scenario1|scenario2|stats|validate|wireshark|clean}"
        exit 1 ;;
esac
