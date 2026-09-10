# Firewall Throughput Lab

Two Windows hosts on separate VLANs, a Cisco switch doing L2, and a FortiGate
routing and filtering between the segments, so that **iperf3 traffic has to
cross the firewall**. The goal was not to produce a big throughput number — the
whole thing is nested virtualisation and the numbers mean nothing in absolute
terms — but to practise *measuring a data path honestly* and to understand what
actually limits it.

## Topology

```
        VLAN 10                                  VLAN 20
     10.0.10.0/24                             10.0.20.0/24

   ┌─────────────┐                          ┌─────────────┐
   │     PC1     │                          │     PC2     │
   │ 10.0.10.100 │                          │ 10.0.20.100 │
   └──────┬──────┘                          └──────┬──────┘
          │ access/VLAN10                          │ access/VLAN20
       ┌──┴────────────────  SW1 (L2)  ────────────┴──┐
       │        Et0/0,Et0/2            Et0/1,Et0/3     │
       └──────┬──────────────────────────────┬────────┘
        port2 │ 10.0.10.1            10.0.20.1 │ port3
           ┌──┴──────────────────────────────┴──┐
           │            FortiGate                │  policies:
           │   VLAN10 <-> VLAN20 (both ways)     │  VLAN10<->VLAN20
           │   internal -> WAN (NAT)             │  internal->WAN
           └─────────────────────────────────────┘
```

Every VLAN10↔VLAN20 flow is routed and policy-checked by the firewall; a
same-VLAN flow only touches the switch. Comparing the two isolates the
firewall's cost.

## The measurements

Cross-segment (through the FortiGate) vs same-segment (switch only):

| Path | Single stream | 4 parallel streams |
|------|--------------:|-------------------:|
| Through the FortiGate | 178–200 Mbit/s | 376 Mbit/s |
| Same VLAN, switch only | 239 Mbit/s | 455 Mbit/s |

- **Firewall overhead:** roughly −25% single-stream, −17% parallel.
- Enabling full traffic logging (`set logtraffic all`) cost almost nothing on a
  single long-lived connection (176 vs 178 Mbit/s) — because it logs once per
  *session*, not per packet. Measuring its real cost would need many short
  connections, not one big one.

**These numbers are not hardware numbers.** The forwarding path is software
(IOS-on-Linux user-space forwarding + a 1-vCPU FortiGate + nested virt), so they
only make sense *relative to each other* inside this lab.

## The actual finding: the ceiling is packet rate, not bandwidth

The most useful result came from an experiment that looked like a fault. Running
with a tiny 6-byte write size and Nagle disabled produced ~1.5 Mbit/s and looked
broken. Three controlled runs (8 parallel streams each) explained it:

| Parameters | Throughput |
|------------|-----------:|
| `-l 6 -N` (6-byte writes, TCP_NODELAY) | 1.29 Mbit/s |
| `-l 6` (6-byte writes, Nagle left on) | 48.8 Mbit/s |
| default block size | 374 Mbit/s |

Converting to packets per second is what makes it click:

- `-l 6 -N` ≈ **27,000 pps**
- default block size ≈ **32,000 pps**

The two are *almost the same packet rate* despite a 290× difference in bit rate.
A software forwarding path charges **per packet**, not per byte — so the ceiling
of this path is a packet rate (roughly **27,000–33,000 pps**), and the Mbit/s
figure is just that rate multiplied by whatever payload you happen to be sending.
Interpreting any number from this lab starts with "what's the pps?".

## Why the honest answer is a *range*, not a number

The first instinct was to state a crisp "~30,000 pps ceiling". Re-running the
same parameters three times each showed why that would have been wrong:

| Parameters | Run 1 | Run 2 | Run 3 |
|------------|------:|------:|------:|
| `-l 6 -N` (6-byte) | 27,708 | 27,708 | 27,917 |
| `-l 64 -N` (64-byte) | 30,078 | 30,664 | 29,102 |

The 64-byte case swings ~1,500 pps between identical runs — more than the gap
between the two payload sizes. The apparent "small packets are slower" effect
was mostly **noise from nested-virtualisation scheduling jitter** (the host also
runs another VM competing for CPU). The correct statement is the range
**27k–33k pps**, established by running everything ≥3× and reporting the
interval — never a single run.

## Notes that save time

- **iperf3 on Windows is unofficial.** ESnet does not ship or endorse a Windows
  iperf3 build; their FAQ says use iperf2 on Windows. The community Cygwin build
  works but its server binds IPv6 wildcard (`::`) by default, so an IPv4 client
  gets *Connection refused* until you pass `-B <your-ipv4>`.
- **iperf3 has been multi-threaded since 3.16** — `-P N` really does spawn N
  worker threads (verified: `-P 1` → 8 threads, `-P 8` → 15). The old "iperf3 is
  single-threaded" advice no longer applies. Here the client VM only has 2 vCPUs,
  so the threads still contend; the bottleneck is the software forwarding path,
  not iperf's threading model.
- A stuck test ending in `SERVER ERROR - server test duration expired` is
  usually the *client* being starved (huge syscall count from tiny writes, or a
  console stuck in Windows "Mark" selection mode freezing output) — not a network
  fault. Turning off console QuickEdit avoids the second one.

## If you needed real line-rate numbers

This lab is the wrong tool for absolute performance — the limit is EVE-NG's
software forwarding, not the traffic generator. Getting real numbers means
moving past a generic tool: `ntttcp` (Windows-native, multi-threaded),
`netperf TCP_RR` (transactions/sec), then kernel-bypass generators like
TRex or pktgen-DPDK to reach line rate, with RFC 2544 (64→1518-byte sweep) as
the methodology. The value of *this* lab is the reasoning, not the throughput.
