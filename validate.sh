#!/bin/bash
set -eo pipefail

# SSH config
ROUTER_IP="192.168.9.1"
ROUTER_PORT="61453"
ROUTER_USER="tkiethuynh"
SSH_CMD="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p $ROUTER_PORT $ROUTER_USER@$ROUTER_IP"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

echo "=== Coder-Validator Integration Test Suite ==="

# 1. Connectivity Check
echo -n "Checking SSH connectivity to $ROUTER_USER@$ROUTER_IP:$ROUTER_PORT... "
if $SSH_CMD uname -m >/dev/null 2>&1; then
    echo -e "${GREEN}CONNECTED${NC}"
else
    echo -e "${RED}FAILED${NC}"
    exit 1
fi

# 2. Cleanup Environment on Router
echo "Resetting environment on router..."
$SSH_CMD '
    /jffs/scripts/zapret stop || true
    if mount | grep -q "/www/require/modules/menuTree.js"; then
        umount -l /www/require/modules/menuTree.js || umount /www/require/modules/menuTree.js || true
    fi
    rm -rf /jffs/addons/zapret
    rm -f /opt/bin/tpws /opt/bin/nfqws /opt/bin/ip2net /opt/bin/mdig /jffs/scripts/zapret
    rm -f /jffs/addons/amtm/personal_script.mod
    if [ -f /jffs/scripts/service-event ]; then
        awk '\''
        /if .*zapret.*/ { skip=1; next }
        skip && /fi/ { skip=0; next }
        skip { next }
        { print }
        '\'' /jffs/scripts/service-event > /tmp/service-event.new
        mv /tmp/service-event.new /jffs/scripts/service-event
        chmod +x /jffs/scripts/service-event
    fi
    if [ -f /jffs/scripts/services-start ]; then
        sed -i '\''/zapret/d'\'' /jffs/scripts/services-start
    fi
    if [ -f /jffs/scripts/firewall-start ]; then
        sed -i '\''/zapret/d'\'' /jffs/scripts/firewall-start
    fi
    if [ -f /jffs/addons/amtm/personalscript.conf ]; then
        sed -i '\''/zapret/d'\'' /jffs/addons/amtm/personalscript.conf
    fi
'

# 3. Upload files to router
echo "Uploading files to /tmp/zapret-install..."
$SSH_CMD "rm -rf /tmp/zapret-install && mkdir -p /tmp/zapret-install"
# Tar current files and extract on router
tar -czf - -C "$(dirname "$0")" --exclude=.git --exclude=.agents . | $SSH_CMD "tar -xzf - -C /tmp/zapret-install"

# 4. Run installer
echo "Running install.sh on router..."
INSTALL_LOG=$($SSH_CMD "sh /tmp/zapret-install/install.sh" 2>&1)
echo "$INSTALL_LOG"

# Verify installer completed successfully
if echo "$INSTALL_LOG" | grep -q "=== Installation complete ==="; then
    echo -e "${GREEN}[PASS] Installer run${NC}"
else
    echo -e "${RED}[FAIL] Installer run failed${NC}"
    exit 1
fi

# 5. Verify Binaries
echo "Verifying binaries installation..."
if $SSH_CMD 'test -f /opt/bin/tpws && test -f /opt/bin/nfqws && test -f /opt/bin/ip2net && test -f /opt/bin/mdig'; then
    echo -e "${GREEN}[PASS] Binaries deployed${NC}"
else
    echo -e "${RED}[FAIL] Binaries missing from /opt/bin/${NC}"
    exit 1
fi

# 6. Verify amtm download
echo "Verifying amtm personal_script.mod size/presence..."
MOD_SIZE=$($SSH_CMD 'wc -c /jffs/addons/amtm/personal_script.mod | awk "{print \$1}"')
if [ "$MOD_SIZE" -gt 1000 ]; then
    echo -e "${GREEN}[PASS] personal_script.mod downloaded (size: $MOD_SIZE bytes)${NC}"
else
    echo -e "${RED}[FAIL] personal_script.mod has unexpected size: $MOD_SIZE bytes${NC}"
    exit 1
fi

# 7. Verify Hooks
echo "Verifying hook scripts..."
HOOKS_PASS=true
$SSH_CMD 'grep -q "/jffs/scripts/zapret" /jffs/scripts/services-start' || HOOKS_PASS=false
$SSH_CMD 'grep -q "/jffs/scripts/zapret" /jffs/scripts/firewall-start' || HOOKS_PASS=false
$SSH_CMD 'grep -q "/jffs/scripts/zapret" /jffs/scripts/service-event' || HOOKS_PASS=false
$SSH_CMD 'grep -q "/jffs/scripts/zapret" /jffs/addons/amtm/personalscript.conf' || HOOKS_PASS=false

if [ "$HOOKS_PASS" = true ]; then
    echo -e "${GREEN}[PASS] Boot and event hooks registered${NC}"
else
    echo -e "${RED}[FAIL] Hook check failed${NC}"
    exit 1
fi

# 8. Test nfqws mode & mangle rules
echo "Testing nfqws mode and hostlist custom filtering..."
$SSH_CMD '
    cat <<EOF > /jffs/addons/custom_settings.txt
zapret_enabled 1
zapret_mode nfqws
zapret_tpws_enabled 0
zapret_tpws_port 10080
zapret_tpws_args --fooling=md5sig
zapret_nfqws_enabled 1
zapret_nfqws_args --fooling=md5sig
zapret_nfqws_queue 200
zapret_hostlist_mode custom
zapret_hostlist_raw google.com,youtube.com
EOF
    /jffs/scripts/zapret service_event
'

# Verify nfqws daemon running
if $SSH_CMD 'pidof nfqws >/dev/null'; then
    echo -e "${GREEN}[PASS] nfqws daemon running${NC}"
else
    echo -e "${RED}[FAIL] nfqws daemon failed to start${NC}"
    exit 1
fi

# Verify hostlist populated correctly
HOSTS=$($SSH_CMD 'cat /jffs/addons/zapret/hostlist.txt')
if echo "$HOSTS" | grep -q "google.com" && echo "$HOSTS" | grep -q "youtube.com"; then
    echo -e "${GREEN}[PASS] hostlist.txt created and populated${NC}"
else
    echo -e "${RED}[FAIL] hostlist.txt incorrect: $HOSTS${NC}"
    exit 1
fi

# Verify mangle rules injected
if $SSH_CMD 'iptables -t mangle -S ZAPRET | grep -q "NFQUEUE --queue-num 200"'; then
    echo -e "${GREEN}[PASS] iptables mangle rules injected${NC}"
else
    echo -e "${RED}[FAIL] iptables mangle rules missing${NC}"
    exit 1
fi

# 9. Test tpws mode
echo "Testing tpws mode..."
$SSH_CMD '
    cat <<EOF > /jffs/addons/custom_settings.txt
zapret_enabled 1
zapret_mode tpws
zapret_tpws_enabled 1
zapret_tpws_port 10080
zapret_tpws_args --fooling=md5sig
zapret_nfqws_enabled 0
zapret_nfqws_queue 200
zapret_hostlist_mode all
EOF
    /jffs/scripts/zapret service_event
'

# Verify nfqws stopped and tpws running
if ! $SSH_CMD 'pidof nfqws >/dev/null' && $SSH_CMD 'pidof tpws >/dev/null'; then
    echo -e "${GREEN}[PASS] tpws running, nfqws stopped${NC}"
else
    echo -e "${RED}[FAIL] Daemon mode transition failed${NC}"
    exit 1
fi

# Verify nat rules injected
if $SSH_CMD 'iptables -t nat -S ZAPRET | grep -q "REDIRECT --to-ports 10080"'; then
    echo -e "${GREEN}[PASS] iptables nat rules injected${NC}"
else
    echo -e "${RED}[FAIL] iptables nat redirect rules missing${NC}"
    exit 1
fi

# 10. Test stop
echo "Testing stop command..."
$SSH_CMD '/jffs/scripts/zapret stop'

if ! $SSH_CMD 'pidof tpws >/dev/null' && ! $SSH_CMD 'pidof nfqws >/dev/null'; then
    echo -e "${GREEN}[PASS] Daemons stopped${NC}"
else
    echo -e "${RED}[FAIL] Daemons still running after stop${NC}"
    exit 1
fi

if ! $SSH_CMD 'iptables -t nat -S 2>/dev/null | grep -q "ZAPRET"' && ! $SSH_CMD 'iptables -t mangle -S 2>/dev/null | grep -q "ZAPRET"'; then
    echo -e "${GREEN}[PASS] iptables rules cleared${NC}"
else
    echo -e "${RED}[FAIL] iptables rules still present after stop${NC}"
    exit 1
fi

# 11. Test WebUI
echo "Testing WebUI slot and bind-mount..."
# Start again to check mounts
$SSH_CMD '/jffs/scripts/zapret start'
$SSH_CMD '/jffs/scripts/zapret webui'

MOUNT_ACTIVE=$($SSH_CMD 'mount | grep -c "/www/require/modules/menuTree.js"')
if [ "$MOUNT_ACTIVE" -eq 1 ]; then
    echo -e "${GREEN}[PASS] menuTree.js bind-mount active${NC}"
else
    echo -e "${RED}[FAIL] menuTree.js bind-mount not active${NC}"
    exit 1
fi

ASP_SLOT=$($SSH_CMD 'ls -l /tmp/var/wwwext/user*.asp | head -n 1 | awk "{print \$NF}"')
if [ -n "$ASP_SLOT" ]; then
    echo -e "${GREEN}[PASS] WebUI page mounted to slot: $ASP_SLOT${NC}"
else
    echo -e "${RED}[FAIL] No WebUI slot allocated${NC}"
    exit 1
fi

# Restore default disabled config and stop daemons to prevent routing disruption
echo "Cleaning up router active state (disabling and stopping redirects)..."
$SSH_CMD '
    cat <<EOF > /jffs/addons/zapret/config.json
{
  "enabled": "0",
  "mode": "nfqws",
  "tpws_enabled": "0",
  "tpws_port": "10080",
  "tpws_args": "--fooling=md5sig",
  "nfqws_enabled": "0",
  "nfqws_args": "--fooling=md5sig",
  "nfqws_queue": "200",
  "hostlist_mode": "all"
}
EOF
    /jffs/scripts/zapret stop
    rm -f /jffs/addons/zapret/hostlist.txt
'

# Cleanup install dir on router
$SSH_CMD "rm -rf /tmp/zapret-install"

echo -e "\n${GREEN}ALL TESTS PASSED SUCCESSFULLY!${NC}"
exit 0
