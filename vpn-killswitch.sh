#!/bin/bash

VPN_IFACE="tun0"
NAT_IFACE="vm0" # Modified /etc/systemd/network to always assign predictable interface names
NAT_IP="10.7.94.7"
WIN_VM="10.7.94.8"
HOST_NAT="10.7.94.1"
BRIDGED_ETH_IFACE="hos0" # Will need adjust the following 2 vars to account for traveling/Wifi. Using dynDNS when remote anyway
NASBOX="192.168.7.70"

check_root() {
  if [ "$EUID" -ne 0 ]; then
    printf "%s\n" "Run $(basename "$0") with sudo" \
      "to change UFW rules."
    exit 1
  fi
}

parse_server_info() {
  if [[ "$1" =~ ^\-{1,2}on?$ ]]; then    # We don't need to run this function if they are just wiping the rules
    local conf_path="${2:-/etc/openvpn}" # Allow user to provide custom location
    local pattern="[[:digit:]]+\.[[:digit:]]+\.[[:digit:]]+\.[[:digit:]]+"
    local find_cmd="find \"$conf_path\" -maxdepth 1 -type f \( -name '*.conf' -o -name '*.ovpn' \) -print0 \
  | xargs -0 -I{} grep -Em 1 \"^#?remote(\s)\b$pattern\s[0-9]{3,4}\b\" {} "

    if [ "$(eval "$find_cmd" | awk '{print $2, $3}' | wc -l)" -eq 0 ]; then
      printf "%s\n" "Required server info not found in configuration under ${conf_path}." \
        "Please point script to the location of your provider's config file."
      exit 99
    else
      SERVER_IP="$(eval "$find_cmd" | awk '{print $2}')"
      SERVER_PORT="$(eval "$find_cmd" | awk '{print $3}')"
      case "$SERVER_PORT" in
      443) SERVER_PROTO=tcp ;;
      1194 | 1195) SERVER_PROTO=udp ;;
      esac
      printf "%s\n" "Your VPN server IP is ${SERVER_IP}" \
        "Your VPN server port is ${SERVER_PORT}" \
        "Transport protocol is ${SERVER_PROTO}"
    fi
  fi
}

check_reset() {
  TUN_ACTIVE=$(ifconfig -a | grep -ow "$VPN_IFACE")
  if [[ "$1" =~ ^\-{1,2}w(ipe)?$ ]] && [ -z "$TUN_ACTIVE" ]; then # User wishes to restore FW
    return 7
  elif [[ "$1" =~ ^\-{1,2}w(ipe)?$ ]] && [ -n "$TUN_ACTIVE" ]; then # User wishes to restore FW, but VPN is currently up
    echo "You should disconnect the VPN prior to disengaging the killswitch."
    exit 99
  elif [[ "$1" =~ ^\-{1,2}on?$ ]] && [ -z "$TUN_ACTIVE" ]; then # Don't apply killswitch rules until the interface is confirmed UP
    printf "%b\n" "\n\nVPN is not currently running" \
      "Nothing to do."
    exit 99
  fi
}

apply_ufw_rules() {
  {
    sudo ufw --force reset
    sudo ufw default deny incoming
    sudo ufw default deny outgoing
    sudo ufw allow in on "$NAT_IFACE" from "$WIN_VM" to "$NAT_IP" port 22 proto tcp
    sudo ufw allow in on "$NAT_IFACE" from "$HOST_NAT"
    sudo ufw allow out on "$NAT_IFACE" to "$WIN_VM" port 22 proto tcp
    sudo ufw allow out on "$NAT_IFACE" to "$HOST_NAT"
    sudo ufw allow out on "$BRIDGED_ETH_IFACE" to "$NASBOX"
    sudo ufw allow out to "$SERVER_IP" port "$SERVER_PORT" proto "$SERVER_PROTO"
    sudo ufw allow out on "$VPN_IFACE" from any to any
    sudo ufw enable
  } >/dev/null 2>&1

}

display_rules() {
  printf "%b\n" "\n***CURRENT FIREWALL POLICY FOR MACHINE: $(echo "$(hostname)" | tr '[:lower:]' '[:upper:]')***\n"
  sudo ufw status numbered | sed --regexp-extended 's!^Status:\s\w+$!!'
}

if [ "$#" -lt 1 ]; then
  echo "USAGE: $(basename "$0") --[on|wipe] <openvpn-file path>"
  exit 1
fi
check_root
parse_server_info "$@"
check_reset "$@"
if [ $? -eq 7 ]; then # Return code confirms we're good to go - user manually disconnected and wishes to restore UFW
  echo "Resetting UFW to defaults..."
  sudo ufw --force reset >/dev/null 2>&1
  display_rules
  exit 0
fi
apply_ufw_rules # If/else didn't catch any condition, so VPN interface is up and user passed -o / --on switch to script
display_rules
