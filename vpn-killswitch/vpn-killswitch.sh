#!/bin/bash

VPN_IFACE="tun0"
UFW_RULE_FILE="${PWD}/ufw-rules.sh"
#NAMESERVER_PATTERN="^#?nameserver\s1\.(0|1)\.(0|1)\.(0|1)$"
NS_PRIMARY="nameserver 1.1.1.1"
NS_SECONDARY="nameserver 1.0.0.1"
NAMESERVER_FILE="/etc/resolv.conf"

display_help() {
  printf "%b\n" "USAGE: $(basename "$0") --[on|wipe] <openvpn-file path>\n" \
    "A simple solution to prevent IP/DNS leaks when running a VPN on an operating system that" \
    "doesn't provide an app natively.\n" \
    "For added portability, the script will read your preferred firewall rules and any host variables from a file." \
    "Simply create a file named 'ufw-rules.sh'. Place this in the same directory as the script.\nSee EXAMPLE SYNTAX for details.\n" \
    "EXAMPLE SYNTAX\n" \
    "# Create a firewall rule:\n" \
    "\tsudo ufw allow out on 10.7.94.1 to 10.7.94.8 port 22 proto tcp\n" \
    "# Turn on the killswitch with your provider config located in a custom directory:\n" \
    "\tsudo ./vpn-killswitch.sh --on /home/<my-vpnconf-dir>\n" \
    "# Restore firewall to defaults with a single argument\n(NOTE: the script will check to ensure you have safely disconnected from your VPN first):\n" \
    "\tsudo ./vpn-killswitch.sh -w"
  exit 1

}

check_root() {
  if [ "$EUID" -ne 0 ]; then
    printf "%s\n" "Run $(basename "$0") with sudo" \
      "to change UFW rules."
    exit 1
  fi
}

parse_server_info() {
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
}

check_tun_up() {
  TUN_ACTIVE=$(ifconfig -a | grep -ow "$VPN_IFACE")
  if [ -z "$1" ] && [ -z "$TUN_ACTIVE" ]; then # Wipe was requested and VPN is safely disconnected
    echo "Resetting UFW to defaults..."
    sudo ufw --force reset >/dev/null 2>&1
    display_rules
  elif [ -z "$1" ] && [ -n "$TUN_ACTIVE" ]; then # User wishes to restore FW ('wipe'), but VPN is currently up
    echo "You should disconnect the VPN prior to disengaging the killswitch."
    exit 99
  elif [ -n "$1" ] && [ -z "$TUN_ACTIVE" ]; then # User passed '--on' arg. But don't apply killswitch rules until they connect to VPN
    printf "%b\n" "\n\nVPN is not currently running" \
      "Nothing to do."
    exit 99
  fi
}

apply_ufw_rules() {
  if [ -f "$UFW_RULE_FILE" ]; then
    OLD_IFS=$IFS
    IFS=$'\n'
    source "$UFW_RULE_FILE"
    for rule in "${RULE_ARR[@]}"; do
      eval "$(echo "$rule" | sed 's!\"!!g')" >/dev/null 2>&1
    done
    IFS=$OLD_IFS
  else
    printf "%b\n" "Can not read your list of firewall rules\n" \
      "Ensure you've placed a file named 'ufw-rules.txt' in the script directory"
    exit 1
  fi
}

display_rules() {
  printf "%b\n" "\n***CURRENT FIREWALL POLICY FOR MACHINE: $(echo "$(hostname)" | tr '[:lower:]' '[:upper:]')***\n"
  sudo ufw status numbered | sed --regexp-extended 's!^Status:\s\w+$!!'
}

check_resolv_conf() {
  if [ -n "$1" ]; then # We started the killswitch so we want to ensure the only 2 DNS entries are those pushed from server
    grep -Eq "${NS_PRIMARY}|${NS_SECONDARY}" "$NAMESERVER_FILE"
    if [ "$?" -eq 0 ]; then
      printf "%b\n" "MODIFYING DNS ENTRIES...\n\n"
      sudo sed -e "s!$NS_PRIMARY!#$NS_PRIMARY!" -e "s!$NS_SECONDARY!#$NS_SECONDARY!" --in-place "$NAMESERVER_FILE"
      cat "$NAMESERVER_FILE"
    else
      printf "%b\n" "Using primary and secondary DNS from VPN provider\n" \
        "No additional entries detected"
    fi
  elif [ -z "$1" ]; then # Restoring everything back to default & ISP default route
    grep -Eq "${NS_PRIMARY}|${NS_SECONDARY}" "$NAMESERVER_FILE"
    if [ "$?" -eq 0 ]; then
      sudo sed -e "s!#$NS_PRIMARY!$NS_PRIMARY!" -e "s!#$NS_SECONDARY!$NS_SECONDARY!" --in-place "$NAMESERVER_FILE"
      printf "%b\n" "Original contents of $NAMESERVER_FILE restored:\n\n"
      cat "$NAMESERVER_FILE"
    fi
  fi
}

### BEGIN MAIN ###

if [ "$#" -lt 1 ]; then
  echo "USAGE: $(basename "$0") -[h|o|w] --[help|on|wipe] <openvpn-file path>"
  exit 1
fi

case "$1" in

-h | --help)
  display_help
  ;;

-o | --on)
  check_root
  parse_server_info "$@"
  check_tun_up "$@" # Passing pos params. Function will force If/else to test 3rd condition only. See comments in check_tun_up
  apply_ufw_rules
  display_rules
  check_resolv_conf "$@"
  ;;

-w | --wipe)
  check_root
  check_tun_up # Not passing pos params. Function will force If/else to test first 2 conditions only. See comments in check_tun_up
  check_resolv_conf
  ;;

*)
  printf "%s\n" "Bad option: $1" \
    "USAGE: $(basename "$0") -[h|o|w] --[help|on|wipe] <openvpn-file path>"
  exit 1
  ;;

esac
