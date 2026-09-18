# Network Security Labs

Hands-on labs I built in [EVE-NG](https://www.eve-ng.net/) to practise the
sides of the job that matter: breaking into a network, hardening the plumbing
underneath it, and understanding how it performs. Each write-up focuses on the reasoning and the findings, not on
click-by-click screenshots.

| Lab | What it demonstrates |
|-----|----------------------|
| [**Active Directory attack lab**](ad-attack-lab/) | Taking a Windows domain from an unauthenticated foothold to Domain Admin using **only misconfigurations — no software exploits**. Kerberoasting, AS-REP roasting, credential-in-description, and a weak-password path to DA. Plus a [**detection companion**](ad-attack-lab/detection/): the telemetry each step leaves and Sigma rules to catch it. |
| [**Switching security lab**](switching-security-lab/) | Five Cisco switches in a redundant Layer-2 triangle. An attacker on an access-layer switch **steals the spanning-tree root with one command** and pulls the VLAN's traffic through itself; root guard shuts it down. Real console captures, and an honest note on what the IOL image can and cannot do. |
| [**Firewall throughput lab**](firewall-throughput-lab/) | Two VLANs behind a FortiGate, benchmarked with iperf3. The interesting part is not the numbers but working out **why** they are what they are: the ceiling is packet rate, not bandwidth, and single numbers are noise until you run them several times. |

Both run on a single machine (nested KVM → EVE-NG → the lab nodes), completely
isolated from any real network. Everything here is reproducible; the labs use
throwaway VMs and evaluation images.

## The thread through all of them

Network security work is offensive and defensive at once. The AD lab is the
attacker's view: how an ordinary, "patched" domain still falls to configuration
mistakes. The switching lab is the same lesson one layer down: a fully working
network still hands over the wire when a protocol trust decision was left at its
default. The throughput lab is the operator's view: how to measure a data path
honestly and not be fooled by a benchmark. The common thread is **not trusting a
default or a single result** — every planted object is verified to exist, every
attack is paired with the control that stops it, and no measurement is believed
until it is repeated.

## A note on the environment

These are built and driven **headless**. The Windows nodes have no working
mouse pointer over the console, so the whole build is keyboard-only until
Windows Remote Management (WinRM) is up; from there it is a proper text channel.
That tooling is its own small story and is summarised in each lab where relevant.
