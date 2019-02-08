#!/tmp/mnt/sda1/entware/bin/bash
####################################################################################################
# Script: IPSET_Netflix_Domains.sh
# Version 1.0
# Author: Xentrk
# Date: 7-September-2018
#
# Description:
#    Selective Routing Script for Netflix using Asuswrt-Merlin firmware.  This version uses the ipset method
#    built into dnsmasq.
#
# Grateful:
#   Thank you to @Martineau on snbforums.com for sharing his Selective Routing expertise
#   and on-going support!
#
####################################################################################################
logger -t "($(basename "$0"))" $$ Starting Script Execution

# Uncomment the line below for debugging
#set -x

PROGNAME=$(basename "$0")
LOCKFILE_DIR=/tmp
LOCK_FD=200

lock() {
    local prefix=$1
    local fd=${2:-$LOCK_FD}
    local lock_file=$LOCKFILE_DIR/$prefix.lock

    # create lock file
    eval "exec $fd>$lock_file"

    # acquier the lock
    flock -n "$fd" \
        && return 0 \
        || return 1
}

error_exit() {
    error_str="$@"
    logger -t "($(basename "$0"))" $$ "$error_str"
    exit 1
}

main() {
    lock "$PROGNAME" || error_exit "Exiting $PROGNAME. Only one instance of $PROGNAME can run at one time."

###
set_domain_array () {
  declare -gA DOMAINS
  DOMAINS[WAN]='/plex.tv'
  # US
  DOMAINS[OVPNC2]='/amazonaws.com/netflix.com/nflxext.com/nflximg.net/nflxso.net/nflxvideo.net'
  # UK
  DOMAINS[OVPNC4]='/bbc.gscontxt.net/bbci.co.uk/bbc.co.uk/bbc.com/bbctvapps.co.uk/bbciplayer.metafaq.com/xhst.bbci/bbci.co.uk/bbc.co.uk/bbcfmt.hs.llnwd.net/bbc.net.uk'
  # SE
  DOMAINS[OVPNC5]='/akamaized.net/svt.demdex.net/play.svt.se/svt.d3.sc.omtrdc.net/svtstatic.se'
}

### Define interface/bitmask to route traffic to below
set_fwmark_array () {
    declare -gA FWMARK
    FWMARK[WAN]="0x8000/0x8000"
    FWMARK[OVPNC1]="0x1000/0x1000"
    FWMARK[OVPNC2]="0x2000/0x2000"
    FWMARK[OVPNC3]="0x3000/0x3000"
    FWMARK[OVPNC4]="0x4000/0x4000"
    FWMARK[OVPNC5]="0x5000/0x5000"
}

create_fwmarks () {
# WAN
    ip rule del fwmark "${FWMARK[WAN]}" > /dev/null 2>&1
    ip rule add from 0/0 fwmark "${FWMARK[WAN]}" table 254 prio 9990

#VPN Client 1
    ip rule del fwmark "${FWMARK[OVPNC1]}" > /dev/null 2>&1
    ip rule add from 0/0 fwmark "${FWMARK[OVPNC1]}" table 111 prio 9995

#VPN Client 2
    ip rule del fwmark "${FWMARK[OVPNC2]}" > /dev/null 2>&1
    ip rule add from 0/0 fwmark "${FWMARK[OVPNC2]}" table 112 prio 9994

#VPN Client 3
    ip rule del fwmark "${FWMARK[OVPNC3]}" > /dev/null 2>&1
    ip rule add from 0/0 fwmark "${FWMARK[OVPNC3]}" table 113 prio 9993

#VPN Client 4
    ip rule del fwmark "${FWMARK[OVPNC4]}" > /dev/null 2>&1
    ip rule add from 0/0 fwmark "${FWMARK[OVPNC4]}" table 114 prio 9992

#VPN Client 5
    ip rule del fwmark "${FWMARK[OVPNC5]}" > /dev/null 2>&1
    ip rule add from 0/0 fwmark "${FWMARK[OVPNC5]}" table 115 prio 9991

    ip route flush cache
}


# Chk_Entware function provided by @Martineau at snbforums.com

Chk_Entware () {

    # ARGS [wait attempts] [specific_entware_utility]

    local READY=1                   # Assume Entware Utilities are NOT available
    local ENTWARE="opkg"
    ENTWARE_UTILITY=                # Specific Entware utility to search for
    local MAX_TRIES=30

    if [ ! -z "$2" ] && [ ! -z "$(echo $2 | grep -E '^[0-9]+$')" ];then
        local MAX_TRIES=$2
    fi

    if [ ! -z "$1" ] && [ -z "$(echo $1 | grep -E '^[0-9]+$')" ];then
        ENTWARE_UTILITY=$1
    else
        if [ -z "$2" ] && [ ! -z "$(echo $1 | grep -E '^[0-9]+$')" ];then
            MAX_TRIES=$1
        fi
    fi

   # Wait up to (default) 30 seconds to see if Entware utilities available.....
   local TRIES=0

   while [ "$TRIES" -lt "$MAX_TRIES" ];do
      if [ ! -z "$(which "$ENTWARE")" ] && [ "$("$ENTWARE" -v | grep -o "version")" == "version" ];then
         if [ ! -z "$ENTWARE_UTILITY" ];then            # Specific Entware utility installed?
            if [ ! -z "$("$ENTWARE" list-installed "$ENTWARE_UTILITY")" ];then
                READY=0                                 # Specific Entware utility found
            else
                # Not all Entware utilities exists as a stand-alone package e.g. 'find' is in package 'findutils'
                if [ -d /opt ] && [ ! -z "$(find /opt/ -name "$ENTWARE_UTILITY")" ];then
                  READY=0                               # Specific Entware utility found
                fi
            fi
         else
            READY=0                                     # Entware utilities ready
         fi
         break
      fi
      sleep 1
      logger -st "($(basename $0))" $$ "Entware" $ENTWARE_UTILITY "not available - wait time" $((MAX_TRIES - TRIES-1))" secs left"
      local TRIES=$((TRIES + 1))
   done

   return $READY
}

# check if /jffs/configs/dnsmasq.conf.add contains entry for Netflix domains
# takes the interface as parameter
check_dnsmasq () {
    IFACE="$1"
    IFACE_DOMAINS=${DOMAINS[$IFACE]}
    if [ -s /jffs/configs/dnsmasq.conf.add ]; then  # dnsmasq.conf.add file exists
        if [ "$(grep -c "ipset=$IFACE_DOMAINS/${IFACE}_DNSMASQ" "/jffs/configs/dnsmasq.conf.add")" -eq "0" ]; then  # see if line exists for OVPNC1_DNSMASQ
            printf "ipset=$IFACE_DOMAINS/${IFACE}_DNSMASQ\n" >> /jffs/configs/dnsmasq.conf.add # add NETFLIX entry to dnsmasq.conf.add
            service restart_dnsmasq > /dev/null 2>&1
        fi
    else
        printf "ipset=$IFACE_DOMAINS/${IFACE}_DNSMASQ\n" > /jffs/configs/dnsmasq.conf.add # dnsmasq.conf.add does not exist, create dnsmasq.conf.add
        service restart_dnsmasq > /dev/null 2>&1
    fi
}

check_ipset_list () {
    IFACE="$1"
    if [ "$(ipset list -n ${IFACE}_DNSMASQ 2>/dev/null)" != "${IFACE}_DNSMASQ" ]; then #does NETFLIX ipset list exist?
        if [ -s "/opt/tmp/${IFACE}_DNSMASQ" ]; then # does OVPNC1_DNSMASQ ipset restore file exist?
            ipset restore -! < /opt/tmp/${IFACE}_DNSMASQ   # Restore ipset list if restore file exists at /opt/tmp/OVPNC1_DNSMASQ
        else
            ipset create ${IFACE}_DNSMASQ hash:net family inet hashsize 1024 maxelem 65536  # No restore file, so create OVPNC1_DNSMASQ ipset list from scratch
        fi
    fi
}

# if ipset list NETFLIX is older than 24 hours, save the current ipset list to disk
check_ipset_restore_file_age () {
    IFACE="$1"
    if [ -s "/opt/tmp/${IFACE}_DNSMASQ" ]; then
        if [ "$(find /opt/tmp/${IFACE}_DNSMASQ -name ${IFACE}_DNSMASQ -mtime +1 -print /dev/null 2>&1)" = "/opt/tmp/${IFACE}_DNSMASQ" ] ; then
            ipset save ${IFACE}_DNSMASQ > /opt/tmp/${IFACE}_DNSMASQ
        fi
    fi
}

# If cronjob to back up the NETFLIX ipset list every 24 hours @ 2:00 AM does not exist, then create it
check_cron_job () {
    IFACE="$1"
    cru l | grep ${IFACE}_DNSMASQ_ipset_list
    if [ "$?" = "1" ]; then  # no cronjob entry found, create it
        cru a ${IFACE}_DNSMASQ "0 2 * * * ipset save ${IFACE}_DNSMASQ > /opt/tmp/OVPNC1_DNSMASQ"
    fi
}

# Route Netflix to WAN
create_routing_rules () {
    IFACE="$1"
    iptables -t mangle -D PREROUTING -i br0 -m set --match-set ${IFACE}_DNSMASQ dst -j MARK --set-mark "${FWMARK[$IFACE]}" > /dev/null 2>&1
    iptables -t mangle -A PREROUTING -i br0 -m set --match-set ${IFACE}_DNSMASQ dst -j MARK --set-mark "${FWMARK[$IFACE]}"
}

set_domain_array
set_fwmark_array
create_fwmarks
Chk_Entware
# initiate the loop
for IFACE in "${!DOMAINS[@]}"; do
  echo "Configuring $IFACE --- ${DOMAINS[$IFACE]}"
  check_dnsmasq $IFACE
  check_ipset_list $IFACE
  check_ipset_restore_file_age $IFACE
  check_cron_job $IFACE
  create_routing_rules $IFACE
done

logger -t "($(basename "$0"))" $$ Completed Script Execution
}
main
