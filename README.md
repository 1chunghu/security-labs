# Network Security Labs

Two hands-on labs I built in [EVE-NG](https://www.eve-ng.net/) to practise the
two halves of the job: breaking into a network and understanding how it
performs. Each write-up focuses on the reasoning and the findings, not on
click-by-click screenshots.

| Lab | What it demonstrates |
|-----|----------------------|
| [**Active Directory attack lab**](ad-attack-lab/) | Taking a Windows domain from an unauthenticated foothold to Domain Admin using **only misconfigurations — no software exploits**. Kerberoasting, AS-REP roasting, credential-in-description, and a weak-password path to DA. Plus a [**detection companion**](ad-attack-lab/detection/): the telemetry each step leaves and Sigma rules to catch it. |
| [**Firewall throughput lab**](firewall-throughput-lab/) | Two VLANs behind a FortiGate, benchmarked with iperf3. The interesting part is not the numbers but working out **why** they are what they are: the ceiling is packet rate, not bandwidth, and single numbers are noise until you run them several times. |

Both run on a single machine (nested KVM → EVE-NG → the lab nodes), completely
isolated from any real network. Everything here is reproducible; the labs use
throwaway VMs and evaluation images.

## Why these two

Network security work is offensive and defensive at once. The AD lab is the
attacker's view: how an ordinary, "patched" domain still falls to configuration
mistakes. The throughput lab is the operator's view: how to measure a data path
honestly and not be fooled by a benchmark. The thread common to both is
**not trusting a single result** — the AD lab verifies every planted object
actually exists, and the throughput lab treats any single measurement as
provisional until repeated.

## A note on the environment

These are built and driven **headless**. The Windows nodes have no working
mouse pointer over the console, so the whole build is keyboard-only until
Windows Remote Management (WinRM) is up; from there it is a proper text channel.
That tooling is its own small story and is summarised in each lab where relevant.
