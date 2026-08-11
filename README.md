# Zapret for Asuswrt-Merlin Router

An easily installable, dynamically web-managed Zapret (transparent proxy / packet queue) extension built specifically for Asuswrt-Merlin routers (supporting `aarch64` and `arm` architectures).

This package wraps bol-van's frozen Zapret C-binaries into a native Merlin-style addon with a built-in control daemon, boot-time firewall integration, amtm personal script menu integration, and a natively styled Administration settings tab.

---

## Features

- **No External Dependencies**: 100% lightweight C-binaries with zero requirements on OpenWrt packages or Lua runtimes.
- **Auto-Architecture Detection**: The installer automatically detects if your router is running `aarch64` (ARM64) or `arm` (ARMv7) and deploys optimized binaries.
- **Merlin WebUI Integration**: Dynamically injects a native administration tab right under the **WAN settings section** (after the NAT Passthrough tab) using a firmware-safe bind-mount of `menuTree.js`.
- **amtm Integration**: Installs `/jffs/scripts/zapret` as the `amtm` personal scripts `p1` entry with an interactive status/control menu.
- **Firewall Persistence**: Automatically handles firewall rule persistence across restarts, IP additions, and WAN updates.
- **Watchdog Health Check**: Installs `/jffs/scripts/zapret-watchdog` and registers a once-per-minute `cru` job to reapply rules or restart the selected daemon when an active interception path becomes inconsistent.
- **Automated Validation Loop**: Includes a comprehensive [validate.sh](validate.sh) testing script to perform automated verification of firewall rules, daemons, and slots.

---

## Directory Structure

```
├── .agents/
│   └── AGENTS.md            # Coder-Validator loop behavioral rules
├── .github/
│   └── workflows/
│       └── release.yml      # GitHub Actions release packager workflow
├── binaries/
│   ├── linux-arm/           # Frozen binaries for ARMv7
│   └── linux-arm64/         # Frozen binaries for ARM64 (aarch64)
├── config.json              # Default config template
├── install.sh               # System architecture-aware installer
├── userpage_zapret.asp      # Merlin-native configuration UI dashboard
├── validate.sh              # Automated E2E verification test suite
├── zapret                   # Service daemon controller and amtm menu (/jffs/scripts/zapret)
└── zapret-watchdog          # Health watchdog installed to /jffs/scripts/zapret-watchdog
```

---

## Installation

Log in to your router via SSH and run the installer:

### Online Single-Command Installer
```sh
curl -s -L "https://github.com/tkiethuynh/zapret-asuswrt/releases/latest/download/install.sh" | sh
```

### Manual/Local Installation
If you have cloned the repository, copy it to your router's `/tmp` directory and run:
```sh
sh install.sh
```

---

## Configuration

Once installed, navigate to your router's WebUI:
1. Go to **Advanced Settings** -> **WAN**.
2. Click on the **Zapret** tab (inserted right after the *NAT Passthrough* tab).
3. Configure your desired bypass strategy:
   - **Mode**: Choose between `tpws` (transparent proxy) and `nfqws` (netfilter queue).
   - **Filtering Strategy**: Filter `all` websites or target a `custom` hostlist.
   - **Host List**: Add target websites in the hostlist field (comma-delimited).
4. Click **Apply** to save changes. The system automatically updates `/jffs/addons/zapret/config.json`, rewrites `hostlist.txt`, clears custom variables, and restarts the backend daemon.

---

## Service Controller Commands

The daemon script `/jffs/scripts/zapret` supports the following commands:

- `start`: Starts the transparent proxies/queue daemons and registers the corresponding iptables rules.
- `stop`: Halts active daemons and tears down all custom iptables redirect/mangle rules.
- `restart`: Performs a stop/start sequence.
- `status`: Displays running state of daemons (with PIDs) and prints active iptables redirect rules.
- `webui`: Regenerates slot mounts in `/tmp/var/wwwext/` and re-applies the `menuTree.js` bind-mount.
- `fix_perms`: Re-applies safe permissions to zapret state and generated WebUI files.
- `watchdog_enable` / `watchdog_disable`: Enables or disables the once-per-minute `cru` watchdog.
- `menu` or no argument: Opens the interactive amtm-friendly zapret menu.

---

## Verifying It Works

`status` only proves the daemon is up and the rules are installed — it does **not** prove the
bypass is actually defeating DPI. Use the A/B/A test below for that.

### Scope: LAN traffic only

Firewall rules hook `-i br0` in `mangle` PREROUTING and FORWARD, i.e. **traffic from LAN
clients**. The router's own outbound traffic (OUTPUT chain) is deliberately not covered.

> **A `curl` run on the router itself will fail against a censored site even when Zapret is
> working perfectly for every LAN device.** Never use a router-local fetch as a health check.

### A/B/A test (the only way to prove causation)

This exploits the scope gap above: temporarily hook the router's own traffic, test, remove.

```sh
TARGET=https://www.bbc.com/vietnamese   # any site on your hostlist

# A — control. Expect timeout with tls=0.000000 (TCP connects, TLS handshake stalls)
curl -sS -o /dev/null -w '%{http_code} tls=%{time_appconnect}\n' --max-time 10 "$TARGET"

# B — hook router traffic through nfqws.
# The mark exclusion stops nfqws's own injected packets from re-entering the queue.
iptables -t mangle -I OUTPUT -p tcp -m multiport --dports 80,443 \
  -m mark ! --mark 0x40000000/0x40000000 -j ZAPRET

curl -sS -o /dev/null -w '%{http_code} tls=%{time_appconnect}\n' --max-time 15 "$TARGET"
# Expect HTTP 200, TLS ~0.2s

# A' — ALWAYS remove the temporary rule (same args, -D instead of -I)
iptables -t mangle -D OUTPUT -p tcp -m multiport --dports 80,443 \
  -m mark ! --mark 0x40000000/0x40000000 -j ZAPRET
```

Safe to run over SSH: Merlin's SSH port is not 80/443, so these rules cannot lock you out.

A control that times out with `tls=0.000000` (TCP completes, TLS does not) confirms
**SNI/ClientHello-based DPI** — exactly what `--dpi-desync=split2` targets. If the control
*succeeds*, the site was not blocked in the first place and the test proves nothing.

### Troubleshooting: don't reach for a packet capture

**Packet capture is the wrong tool here — do not install `tcpdump` for this.** Merlin/Entware
ships without it, and installing it (`opkg install tcpdump libpcap`) will not answer the
question, for a structural reason:

Broadcom's **software flow cache** (`swaccel=N` in `/proc/net/nf_conntrack`) bypasses the Linux
network stack once a flow is accelerated. `nfqws` mode disables only the hardware *runner*
(`hwaccel`); `swaccel` intentionally stays on to preserve fast-path throughput.

Consequence: `tcpdump -i br0` shows fresh SYNs, DNS, and handshakes, but **never the ongoing
data of an established connection**. Chasing a "Zapret isn't working" report with packet
captures produces empty files that look like proof of failure but prove nothing.

Use connection state instead — available on stock firmware, no packages needed:

```sh
# ESTABLISHED + [ASSURED] == bidirectional traffic confirmed to that destination
grep '<destination-ip-prefix>' /proc/net/nf_conntrack | grep '<lan-client-ip>'
```

Also note a browser **refresh reuses keep-alive HTTP/2 sockets**, so it generates no new
handshake to observe. Force a fresh one:

```sh
conntrack -D -s <lan-client-ip> -d <destination-ip>
```

### Hostlist matching

`--hostlist` **auto-matches subdomains**, so `bbc.com` already covers `www.bbc.com`; there is
no need to list both.

When identifying traffic by IP, beware shared CDN ranges — `bbc.com` resolves to Fastly
`151.101.{0,64,128,192}.81`, but neighbouring `151.101.*.91` addresses on the same range
belong to entirely different Fastly customers. A bare `151.101.` match is not proof of BBC
traffic.

---

## Developer Testing Suite

The repository includes a validation script [validate.sh](validate.sh) to test modifications and verify system stability on the router before committing.

To run tests:
```sh
bash validate.sh
```
The test suite performs:
1. SSH connectivity check.
2. Clean environment teardown on the router.
3. Fresh binary copy and `personal_script.mod` module retrieval.
4. Hook injection verification.
5. End-to-end `nfqws` daemon start and firewall mangle rules verification.
6. End-to-end `tpws` daemon start and firewall NAT redirect rules verification.
7. Graceful daemon stopping and firewall cleanup.
8. WebUI slot rendering checks.
9. Disables redirect routing and shuts down active daemons to keep your PC's connection uninterrupted.
