#!/bin/sh

# Zapret Installer for Asuswrt-Merlin
# Performs architecture detection, copies binaries, sets up configuration,
# registers hooks, and performs initial WebUI injection.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

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
chmod +x /jffs/scripts/zapret

# 5. Hook into boot scripts
echo "Configuring boot script hooks..."

# services-start hook
if [ ! -f /jffs/scripts/services-start ]; then
    echo "#!/bin/sh" > /jffs/scripts/services-start
    chmod +x /jffs/scripts/services-start
fi
if ! grep -q "/jffs/scripts/zapret" /jffs/scripts/services-start; then
    echo "" >> /jffs/scripts/services-start
    echo "/jffs/scripts/zapret webui" >> /jffs/scripts/services-start
    echo "/jffs/scripts/zapret start" >> /jffs/scripts/services-start
    echo "Hooked services-start."
fi

# firewall-start hook
if [ ! -f /jffs/scripts/firewall-start ]; then
    echo "#!/bin/sh" > /jffs/scripts/firewall-start
    chmod +x /jffs/scripts/firewall-start
fi
if ! grep -q "/jffs/scripts/zapret" /jffs/scripts/firewall-start; then
    echo "" >> /jffs/scripts/firewall-start
    echo "/jffs/scripts/zapret start" >> /jffs/scripts/firewall-start
    echo "Hooked firewall-start."
fi

# service-event hook
if [ ! -f /jffs/scripts/service-event ]; then
    echo "#!/bin/sh" > /jffs/scripts/service-event
    chmod +x /jffs/scripts/service-event
fi
if ! grep -q "/jffs/scripts/zapret" /jffs/scripts/service-event; then
    cat <<'EOF' >> /jffs/scripts/service-event

if [ "$1" = "zapret" ] || [ "$2" = "zapret" ]; then
    /jffs/scripts/zapret service_event
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
if ! grep -q "/jffs/scripts/zapret" /jffs/addons/amtm/personalscript.conf; then
    echo "/jffs/scripts/zapret" >> /jffs/addons/amtm/personalscript.conf
    echo "Added to amtm personal scripts config."
fi
if [ ! -f /jffs/addons/amtm/personal_script.mod ]; then
    echo "Downloading amtm personal_script.mod..."
    curl -s -L --retry 3 "https://diversion.ch/amtm_fw/personal_script.mod" -o /jffs/addons/amtm/personal_script.mod || echo "Warning: failed to download amtm module."
fi

# 7. Initial configuration application
echo "Performing initial WebUI injection and starting services..."
/jffs/scripts/zapret webui || echo "Warning: webui injection failed."
/jffs/scripts/zapret start || echo "Warning: service startup failed."

echo "=== Installation complete ==="
