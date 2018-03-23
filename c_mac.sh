# ! /bin/bash

NIC="ens4"
MAC=$(ifconfig $NIC | grep "HWaddr\b" | awk '{print $5}')  
ovs-vsctl add-br br0 -- set bridge br0 other-config:hwaddr=$MAC
ovs-vsctl add-port br0 $NIC > /dev/null 2>&1
ifconfig $NIC 0.0.0.0
LAST_MAC_CHAR=${MAC:(-1)}
AUX="${MAC:0:${#MAC}-1}"
if [ "$LAST_MAC_CHAR" -eq "$LAST_MAC_CHAR" ] 2>/dev/null; then
    NL="a"
else
    NL="1"
fi
NEW_MAC="$AUX$NL"
ifconfig $NIC hw ether $NEW_MAC
