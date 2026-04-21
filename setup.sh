# Traffic Classification System – SDN Assignment
## Mininet + POX Controller (OpenFlow 1.0)

---

## Project Overview

This SDN application classifies network traffic by protocol type in real time using an OpenFlow controller (POX) and Mininet.

| Goal | Implementation |
|---|---|
| Identify TCP / UDP / ICMP packets | `packet_in` handler + `nw_proto` match |
| Maintain statistics | `ProtoStats` class (packets, bytes, flows, blocked) |
| Display classification results | ASCII dashboard + JSON file + `display_stats.py` |
| Analyze traffic distribution | Percentage bar chart per protocol |

---

## Project Structure

```
TrafficClassifier/
├── controller/
│   └── traffic_classifier.py   ← Main POX controller (all logic here)
├── topology/
│   └── topology.py             ← Mininet star topology + scenario runners
├── tests/
│   ├── display_stats.py        ← Live statistics dashboard
│   └── validate.py             ← Automated validation & regression suite
├── logs/                       ← Runtime logs (created by setup.sh)
├── setup.sh                    ← One-command setup + runner
└── README.md
```

---

## How It Works

### Controller Architecture

```
  Mininet Hosts
       │  (OpenFlow 1.0 over TCP:6633)
  ┌────▼────────────────────────────────────────────┐
  │              POX Controller                      │
  │                                                  │
  │  ┌─────────────────────────────────────────┐     │
  │  │  SwitchClassifier  (per switch)         │     │
  │  │                                         │     │
  │  │  1. Install proactive rules on connect  │     │
  │  │     ARP  prio=400 → FLOOD               │     │
  │  │     ICMP prio=300 → FLOOD / DROP        │     │
  │  │     TCP  prio=200 → NORMAL              │     │
  │  │     UDP  prio=200 → NORMAL / DROP       │     │
  │  │     *    prio= 10 → CONTROLLER          │     │
  │  │                                         │     │
  │  │  2. Handle packet_in (unmatched flows)  │     │
  │  │     Classify → update ProtoStats        │     │
  │  │     Install port-level block if needed  │     │
  │  │     Forward or DROP                     │     │
  │  └─────────────────────────────────────────┘     │
  │                                                  │
  │  ┌──────────────────┐  ┌────────────────────┐    │
  │  │  Dashboard Timer │  │  Stats Dump Timer  │    │
  │  │  every 5s        │  │  every 10s → JSON  │    │
  │  └──────────────────┘  └────────────────────┘    │
  └──────────────────────────────────────────────────┘
```

### OpenFlow Match+Action Rules

| Protocol | Priority | Match Fields | Action |
|---|---|---|---|
| ARP | 400 | `dl_type=0x0806` | `OUTPUT:FLOOD` |
| ICMP | 300 | `dl_type=0x0800, nw_proto=1` | `FLOOD` or `DROP` (configurable) |
| TCP | 200 | `dl_type=0x0800, nw_proto=6` | `OUTPUT:NORMAL` |
| UDP | 200 | `dl_type=0x0800, nw_proto=17` | `NORMAL` or `DROP` (configurable) |
| Port block | 250 | `nw_proto=X, tp_dst=Y` | `DROP` (reactive) |
| Default miss | 10 | `*` (wildcard) | `OUTPUT:CONTROLLER` |

---

## Quick Start

### Step 1 – Install

```bash
chmod +x setup.sh
./setup.sh install
```

### Step 2 – Start the Controller (Terminal 1)

```bash
# All traffic allowed (classify only)
./setup.sh run

# Block all UDP
./setup.sh run-block-udp

# Block all ICMP (pings will fail)
./setup.sh run-block-icmp

# Block specific ports: TCP:22, TCP:23, UDP:161
./setup.sh run-block-ports
```

### Step 3 – Launch Mininet (Terminal 2)

```bash
# Interactive CLI with star topology
./setup.sh topo

# Automated Scenario 1: Allowed vs Blocked
./setup.sh scenario1

# Automated Scenario 2: Normal vs Link Failure
./setup.sh scenario2
```

### Step 4 – Monitor (Terminal 3)

```bash
# Live stats dashboard (refreshes every 3s)
./setup.sh stats

# Run full validation suite
./setup.sh validate

# Open Wireshark on s1-eth1
./setup.sh wireshark
```

---

## Test Scenarios

### Scenario 1: Allowed vs Blocked

Demonstrates the **classification + enforcement** capability.

| Sub-test | Traffic | Expected |
|---|---|---|
| 1a | ICMP: h3 → h4 | ✅ SUCCESS (allowed) |
| 1b | UDP iperf: h2 → h4 | ✅ SUCCESS (allowed) |
| 1c | TCP port 80: h1 → h4 | ✅ SUCCESS (allowed) |
| 1d | TCP port 23: h1 → h4 | ❌ BLOCKED |

**Run it:**
```bash
# Terminal 1 (with port 23 blocked):
./setup.sh run-block-ports

# Terminal 2:
./setup.sh scenario1
```

**Expected POX dashboard output:**
```
Protocol   Packets     Bytes   %Total  Blocked  Flows
TCP          1,240   890,400    61.2%        8      1  ████████████
UDP            430   310,000    26.7%        0      1  ████████
ICMP           230    19,320    14.3%        0      1  ████
ARP             24       984     1.5%        0      1  ▌
OTHER            0         0     0.0%        0      0
```

---

### Scenario 2: Normal vs Link Failure

Demonstrates **resilience** and how the classifier handles topology changes.

| Sub-test | Action | Expected |
|---|---|---|
| 2a | Normal TCP iperf h1 → h4 | ✅ Baseline throughput recorded |
| 2b | h2 link taken down | ❌ h2 UNREACHABLE |
| 2c | h2 link restored | ✅ h2 REACHABLE again |

**Run it:**
```bash
./setup.sh scenario2
```

---

## Generating Traffic for Classification

Inside the Mininet CLI:

```bash
# ICMP (ping)
mininet> h3 ping h4 -c 10

# TCP iperf (5 seconds)
mininet> h4 iperf -s &
mininet> h1 iperf -c 10.0.0.4 -t 5

# UDP iperf
mininet> h4 iperf -s -u &
mininet> h2 iperf -c 10.0.0.4 -u -t 5 -b 1M

# HTTP (TCP port 80)
mininet> h4 python3 -m http.server 80 &
mininet> h1 curl http://10.0.0.4/

# Telnet attempt (blocked if run-block-ports used)
mininet> h1 nc -zv 10.0.0.4 23

# Check flow table on s1
mininet> sh ovs-ofctl dump-flows s1
```

---

## Wireshark / tcpdump Validation

```bash
# Capture on the switch port connected to h1
sudo tcpdump -i s1-eth1 -n

# Filter by protocol
sudo tcpdump -i s1-eth1 icmp
sudo tcpdump -i s1-eth1 tcp
sudo tcpdump -i s1-eth1 udp

# Wireshark GUI
sudo wireshark -i s1-eth1 -k &

# Useful Wireshark display filters:
#   icmp
#   tcp
#   udp
#   tcp.port == 23
#   ip.proto == 17
```

---

## Validation Suite

```bash
./setup.sh validate
```

Runs 8 automated tests:

| Test | Checks |
|---|---|
| T1 OVS Connection | Switch connected to controller on port 6633 |
| T2 Flow Rules | ARP / ICMP / TCP / UDP / default rules present |
| T3 Stats File | JSON stats file written by controller |
| T4 Classification Accuracy | All proto counters ≥ 0, percentages sum to 100% |
| T5 Block Enforcement | Blocked protocols have blocked counter > 0 |
| T6 Counter Regression | Counters never decrease between snapshots |
| T7 ICMP Reachability | Ping from host succeeds (when not blocked) |
| T8 Flow Count Sanity | At least 5 proactive flow entries present |

---

## Controller Configuration Options

```bash
./pox.py traffic_classifier.traffic_classifier \
    --block_udp=False          # True → DROP all UDP
    --block_icmp=False         # True → DROP all ICMP
    --blocked_tcp_ports="22,23"  # comma-separated TCP ports to DROP
    --blocked_udp_ports="161"    # comma-separated UDP ports to DROP
    --stats_interval=10          # JSON dump every N seconds
```

---

## Stats JSON Format

Written to `controller/traffic_stats.json` every 10 seconds:

```json
{
  "timestamp": 1718000000.0,
  "uptime_s": 120,
  "config": {
    "block_udp": false,
    "block_icmp": false,
    "blocked_tcp_ports": [23],
    "blocked_udp_ports": []
  },
  "switches": {
    "00:00:00:00:00:00:00:01": {
      "TCP":  { "packets": 1240, "bytes": 890400, "flows": 1, "blocked": 8 },
      "UDP":  { "packets":  430, "bytes": 310000, "flows": 1, "blocked": 0 },
      "ICMP": { "packets":  230, "bytes":  19320, "flows": 1, "blocked": 0 },
      "ARP":  { "packets":   24, "bytes":    984, "flows": 1, "blocked": 0 },
      "OTHER":{ "packets":    0, "bytes":      0, "flows": 0, "blocked": 0 }
    }
  }
}
```

---

## Troubleshooting

```bash
# Clean up Mininet state after a crash
sudo mn -c

# Restart OVS
sudo service openvswitch-switch restart

# Check OVS flows manually
sudo ovs-ofctl dump-flows s1

# Verify POX is listening
ss -tlnp | grep 6633

# Force OpenFlow 1.0 on a switch
sudo ovs-vsctl set bridge s1 protocols=OpenFlow10
```
