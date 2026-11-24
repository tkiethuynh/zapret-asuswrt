#!/bin/sh

# Zapret Installer for Asuswrt-Merlin
# Performs architecture detection, copies binaries, sets up configuration,
# registers hooks, and performs initial WebUI injection.

set -e

SCRIPT_DIR="$(cd "$(dirname -- "$0")" 2>/dev/null && pwd || pwd)"
ONLINE_TMP=""

cleanup() {
    [ -n "$ONLINE_TMP" ] && rm -rf "$ONLINE_TMP"
}
trap cleanup EXIT

if [ ! -f "$SCRIPT_DIR/zapret" ] || [ ! -d "$SCRIPT_DIR/binaries" ]; then
    echo "Local package files not found; downloading latest release archive..."
    ONLINE_TMP="/tmp/zapret-online-install.$$"
    mkdir -p "$ONLINE_TMP"
    curl -fsSL --retry 3 "https://github.com/tkiethuynh/zapret-asuswrt/releases/latest/download/zapret-merlin.tar.gz" -o "$ONLINE_TMP/zapret-merlin.tar.gz"
    tar -xzf "$ONLINE_TMP/zapret-merlin.tar.gz" -C "$ONLINE_TMP"
    SCRIPT_DIR="$ONLINE_TMP"
fi

echo "=== Zapret Asuswrt-Merlin Installer ==="

# 1. Detect system architecture
ARCH=$(uname -m)
echo "Detected architecture: $ARCH"

if [ "$ARCH" = "aarch64" ]; then
    BIN_SRC="$SCRIPT_DIR/binaries/linux-arm64"
elif echo "$ARCH" | grep -q "^arm"; then
    BIN_SRC="$SCRIPT_DIR/binaries/linux-arm"
else
    echo "Error: Unsupported architecture ($ARCH). Only arm/aarch64 are supported." >&2
    exit 1
fi

if [ ! -d "$BIN_SRC" ]; then
    echo "Error: Source binaries directory ($BIN_SRC) not found." >&2
    exit 1
fi

# 2. Copy binaries to /opt/bin
echo "Installing binaries to /opt/bin..."
mkdir -p /opt/bin
cp "$BIN_SRC/tpws" /opt/bin/tpws
cp "$BIN_SRC/nfqws" /opt/bin/nfqws
cp "$BIN_SRC/ip2net" /opt/bin/ip2net
cp "$BIN_SRC/mdig" /opt/bin/mdig
chmod +x /opt/bin/tpws /opt/bin/nfqws /opt/bin/ip2net /opt/bin/mdig

# 3. Create addons directory and copy configuration/web files
echo "Setting up /jffs/addons/zapret..."
mkdir -p /jffs/addons/zapret
chmod 755 /jffs/addons/zapret
if [ ! -f /jffs/addons/zapret/config.json ]; then
    cp "$SCRIPT_DIR/config.json" /jffs/addons/zapret/config.json
    chmod 644 /jffs/addons/zapret/config.json
else
    echo "config.json already exists, preserving settings."
fi
cp "$SCRIPT_DIR/userpage_zapret.asp" /jffs/addons/zapret/userpage_zapret.asp
chmod 644 /jffs/addons/zapret/userpage_zapret.asp

# 4. Copy control script
echo "Installing control script to /jffs/scripts/zapret..."
mkdir -p /jffs/scripts
cp "$SCRIPT_DIR/zapret" /jffs/scripts/zapret
chmod 755 /jffs/scripts/zapret

# 5. Hook into boot scripts
echo "Configuring boot script hooks..."

ensure_trailing_newline() {
    local file="$1"
    if [ -s "$file" ] && [ -n "$(tail -c 1 "$file" 2>/dev/null)" ]; then
        echo "" >> "$file"
    fi
}

add_hook() {
    local file="/jffs/scripts/$1"; shift
    [ -f "$file" ] || { echo "#!/bin/sh" > "$file"; chmod +x "$file"; }
    ensure_trailing_newline "$file"
    local added=0
    for line in "$@"; do
        if ! grep -Fqx "$line" "$file"; then
            echo "$line" >> "$file"
            added=1
        fi
    done
    [ "$added" -eq 1 ] && echo "Hooked $(basename "$file")." || true
}

# Remove legacy pre-USB start from services-start (post-mount and firewall-start handle daemon startup)
if [ -f /jffs/scripts/services-start ]; then
    sed -i '/^\/jffs\/scripts\/zapret start[[:space:]]*&\?$/d' /jffs/scripts/services-start 2>/dev/null || true
fi

# Clean legacy inline zapret ipset/QUIC snippets now managed directly by /jffs/scripts/zapret
if [ -f /jffs/scripts/firewall-start ]; then
    sed -i '/# Block QUIC for Zapret domains/d' /jffs/scripts/firewall-start 2>/dev/null || true
    sed -i '/--match-set zapret_domains dst -p udp --dport 443 -j REJECT/d' /jffs/scripts/firewall-start 2>/dev/null || true
fi
if [ -f /jffs/scripts/dnsmasq.postconf ]; then
    awk '
    /# Sync Zapret QUIC-block ipset lines from hostlist\.txt/ { skip=1; next }
    skip && /^fi[[:space:]]*$/ { skip=0; next }
    skip { next }
    { print }
    ' /jffs/scripts/dnsmasq.postconf > /tmp/dnsmasq.postconf.zapret && mv /tmp/dnsmasq.postconf.zapret /jffs/scripts/dnsmasq.postconf
    chmod +x /jffs/scripts/dnsmasq.postconf
fi

add_hook services-start "/jffs/scripts/zapret webui"
add_hook firewall-start "/jffs/scripts/zapret start &"
add_hook post-mount '[ -x "${1}/entware/bin/opkg" ] && [ -x /jffs/scripts/zapret ] && /jffs/scripts/zapret start &'
add_hook dnsmasq.postconf '/jffs/scripts/zapret dnsmasq_postconf "$1"'

# service-event hook
if [ ! -f /jffs/scripts/service-event ]; then
    echo "#!/bin/sh" > /jffs/scripts/service-event
    chmod +x /jffs/scripts/service-event
fi
if ! grep -q "/jffs/scripts/zapret" /jffs/scripts/service-event; then
    ensure_trailing_newline /jffs/scripts/service-event
    cat <<'EOF' >> /jffs/scripts/service-event
if [ "$1" = "zapret" ] || [ "$2" = "zapret" ]; then
    { /jffs/scripts/zapret service_event; } &
fi
EOF
    echo "Hooked service-event."
fi

# 6. amtm integration
echo "Configuring amtm integration..."
mkdir -p /jffs/addons/amtm
if [ ! -f /jffs/addons/amtm/personalscript.conf ]; then
    touch /jffs/addons/amtm/personalscript.conf
fi
# Keep zapret as p1 in amtm Personal Scripts. Preserve up to three existing non-zapret entries.
grep -vx "/jffs/scripts/zapret" /jffs/addons/amtm/personalscript.conf | head -n 3 > /tmp/zapret_personalscript.conf
{
    echo "/jffs/scripts/zapret"
    cat /tmp/zapret_personalscript.conf
} > /jffs/addons/amtm/personalscript.conf
rm -f /tmp/zapret_personalscript.conf
chmod 644 /jffs/addons/amtm/personalscript.conf
echo "Added zapret as amtm personal script p1."
if [ ! -f /jffs/addons/amtm/personal_script.mod ]; then
    echo "Downloading amtm personal_script.mod..."
    if ! curl -fsSL --retry 3 "https://diversion.ch/amtm_fw/personal_script.mod" -o /jffs/addons/amtm/personal_script.mod; then
        rm -f /jffs/addons/amtm/personal_script.mod
        echo "Warning: failed to download amtm module."
    fi
fi

# 7. Clean up legacy watchdog artifacts (if upgrading)
rm -f /jffs/scripts/zapret-watchdog /tmp/zapret-watchdog.log
if [ -x /usr/sbin/cru ]; then
    /usr/sbin/cru d zapret_watchdog 2>/dev/null || true
fi

# 8. Initial configuration application
echo "Performing initial WebUI injection and starting services..."
/jffs/scripts/zapret webui || echo "Warning: webui injection failed."
/jffs/scripts/zapret fix_perms || echo "Warning: permission hardening failed."
/jffs/scripts/zapret start || echo "Warning: service startup failed."

echo "=== Installation complete ==="
