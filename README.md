# Zapret for Asuswrt-Merlin Router

An easily installable, dynamically web-managed Zapret (transparent proxy / packet queue) extension built specifically for Asuswrt-Merlin routers (supporting `aarch64` and `arm` architectures).

This package wraps bol-van's frozen Zapret C-binaries into a native Merlin-style addon with a built-in control daemon, boot-time firewall integration, amtm personal script menu integration, and a natively styled Administration settings tab.

---

## Features

- **No External Dependencies**: 100% lightweight C-binaries with zero requirements on OpenWrt packages or Lua runtimes.
- **Auto-Architecture Detection**: The installer automatically detects if your router is running `aarch64` (ARM64) or `arm` (ARMv7) and deploys optimized binaries.
- **Merlin WebUI Integration**: Dynamically injects a native administration tab right under the **WAN settings section** (after the NAT Passthrough tab) using a firmware-safe bind-mount of `menuTree.js`.
- **amtm Integration**: Appends to the `amtm` personal scripts menu using the official module definition.
- **Firewall Persistence**: Automatically handles firewall rule persistence across restarts, IP additions, and WAN updates.
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
└── zapret                   # Service daemon controller (/jffs/scripts/zapret)
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
