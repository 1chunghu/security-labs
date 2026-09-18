# Detecting the attack chain

The [attack write-up](../README.md) takes `lab.local` from an unauthenticated
foothold to Domain Admin using only misconfigurations. This is the other half:
**what each step leaves in the logs, and how to catch it.** Building the attack
is only useful if you can also say how a defender would have seen it.

Every attack in the parent lab maps to a control that costs nothing. Most of
them also map to a concrete piece of telemetry — and one deliberately does not,
which is itself the lesson.

## What you have to turn on first

None of this is visible with default audit policy. On the DC, the relevant
subcategories have to be enabled (Group Policy → *Advanced Audit Policy*):

| Telemetry | Subcategory to enable |
|-----------|------------------------|
| 4768 (TGT requests) | Account Logon → **Audit Kerberos Authentication Service** |
| 4769 (service tickets) | Account Logon → **Audit Kerberos Service Ticket Operations** |
| 4625 / 4624 (logons) | Logon/Logoff → **Audit Logon** |
| 4740 (lockouts) | Account Management → **Audit User Account Management** |

Reproducibility note: the same discipline as the attack lab applies — after
turning auditing on, generate one known-bad event and confirm it actually lands
before trusting a rule that says "no hits".

## Attack → detection

### 1. AS-REP roasting → event 4768, no pre-auth, RC4

`jdoe` has pre-auth disabled, so the KDC hands out an AS-REP to anyone. On the
wire the giveaway is a **TGT request (4768) with `PreAuthType = 0` and
`TicketEncryptionType = 0x17` (RC4)**. A normal Kerberos logon pre-authenticates
and negotiates AES, so this combination is the signature, not just a heuristic.

- Rule: [`sigma/asrep_roasting.yml`](sigma/asrep_roasting.yml)
- Tuning: the only legitimate source of this event is an account intentionally
  set without pre-auth. That set should be *empty or inventoried*, so this rule
  is close to zero-false-positive in a healthy domain — which is exactly why it
  is worth alerting on at `high`.

### 2. Kerberoasting → event 4769, RC4 service ticket

Any authenticated user can ask for a service ticket for `svc-sql`; the ticket is
encrypted with the account's password and cracks offline. The atomic event is a
**4769 with `TicketEncryptionType = 0x17` and `TicketOptions = 0x40810000`** for
a user (non-`$`) SPN.

- Rule: [`sigma/kerberoasting.yml`](sigma/kerberoasting.yml)
- The honest caveat: a single 4769 is **not** an incident — RC4 service tickets
  still happen for real. The signal that separates roasting from normal use is
  **one principal requesting many distinct SPNs in a short window**. Treat the
  Sigma rule as the primitive and do the aggregation in your SIEM
  (`count(distinct ServiceName) by TargetUserName` over ~10 min). Baseline the
  handful of legacy RC4 SPNs first so "new RC4 SPN" becomes the real trigger.

### 3. Password in a description field → *not a detection, a hunt*

This is the instructive one. `asmith`'s password sits in the `description`
attribute; the attacker reads it with a single, ordinary LDAP query that looks
identical to any other directory read. **There is no clean event that says
"a secret was just read."** Chasing 4662 / 1644 here produces noise, not signal.

The correct answer is to stop trying to detect the *read* and instead detect the
*exposure* — sweep the directory yourself, on a schedule, the same way an
attacker would:

- Hunt script: [`hunt/find-secrets-in-attributes.ps1`](hunt/find-secrets-in-attributes.ps1)

If your own sweep finds it, so will theirs. The control is hygiene plus a
recurring hunt, not an alert.

### 4. Weak password → Domain Admin → spray shape, then a privileged logon

`backupadm` is in Domain Admins with a weak password, reached by spraying. Two
things fire:

- **The spray**: many failed network logons (**4625, logon type 3**) against
  *distinct* accounts from one source in a short window — a different shape from
  a single-account brute force (which hammers one `TargetUserName`) and from a
  lockout storm. Rule: [`sigma/password_spray.yml`](sigma/password_spray.yml).
- **The success that matters**: once `backupadm` logs on, a **4672** (special
  privileges assigned at logon) for a Domain Admin **from an unusual source** is
  the high-value alert. 4672 alone is far too noisy to alert on blindly; it is
  useful only scoped to your DA set *and* an unexpected source host. Pair it with
  the 4624 that carries the source address.

## Coverage summary

| Attack | Primary telemetry | Detectability |
|--------|-------------------|---------------|
| AS-REP roasting | 4768, PreAuth 0, RC4 | High — near zero-FP signature |
| Kerberoasting | 4769, RC4 SPN | Medium — needs aggregation, not a single event |
| Description-field secret | (none) | Not detectable at read time — hunt the exposure |
| Weak-password spray → DA | 4625 spray shape + 4672 scoped | High for the spray, medium for the success |

The pattern worth taking away: two of the four are crisp signatures, one needs
behavioural aggregation, and one is not an alert at all. Knowing *which* is which
before an engagement is the difference between a rule that fires and a dashboard
that only produces noise.
