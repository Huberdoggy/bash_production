**USAGE: vpn-killswitch.sh -[h|o|w] --[help|on|wipe] <openvpn-file path>**

A simple solution to prevent IP/DNS leaks when running a VPN on an operating system that
doesn't provide an app natively.

For added portability, the script will read your preferred firewall rules and any host variables from a file.
Simply create a file named 'ufw-rules.sh'. Place this in the same directory as the script.

The only requirement is that you place your rules in an array named RULE_ARR,
since the script will look to source that. See EXAMPLE SYNTAX for details.

**EXAMPLE SYNTAX**

\# Create a firewall rule:

        RULE_ARR=\(
                sudo ufw allow out on 10.7.94.1 to 10.7.94.8 port 22 proto tcp
                \)

\# Turn on the killswitch with your provider config located in a custom directory:

        sudo ./vpn-killswitch.sh --on /home/<my-vpnconf-dir>

\# Restore firewall to defaults with a single argument
\(NOTE: the script will check to ensure you have safely disconnected from your VPN first\):

        sudo ./vpn-killswitch.sh -w