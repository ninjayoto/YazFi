#!/bin/sh

####################################################################
######                    YazFi by jackyaz                    ######
######                          v2.0.0                        ######
######            https://github.com/jackyaz/YazFi/           ######
####################################################################

#shellcheck disable=SC2034
#shellcheck disable=SC1091
#shellcheck source=/dev/null

### Start of script variables ###
readonly YAZFI_NAME="YazFi"
readonly YAZFI_CONF="/jffs/configs/$YAZFI_NAME.config"
readonly YAZFI_VERSION="v2.0.0"
readonly YAZFI_REPO="https://raw.githubusercontent.com/jackyaz/YazFi/master/YazFi"
### End of script variables ###

### Start of output format variables ###
readonly CRIT="\\e[41m"
readonly ERR="\\e[31m"
readonly WARN="\\e[33m"
readonly PASS="\\e[32m"
### End of output format variables ###

### Start of router environment variables ###
readonly LAN="$(nvram get lan_ipaddr)"
readonly IFACELIST="wl0.1 wl0.2 wl0.3 wl1.1 wl1.2 wl1.3 wl2.1 wl2.2 wl2.3"
### End of router environment variables ###

### Start of path variables ###
readonly DNSCONF="/jffs/configs/dnsmasq.conf.add"
readonly TMPCONF="/jffs/configs/tmpdnsmasq.conf.add"
### End of path variables ###

### Start of firewall variables ###
readonly INPT="$YAZFI_NAME""INPUT"
readonly FWRD="$YAZFI_NAME""FORWARD"
readonly LGRJT="$YAZFI_NAME""Reject"
readonly CHAINS="$INPT $FWRD $LGRJT"
### End of firewall variables ###

### Start of VPN clientlist variables ###
VPN_IP_LIST_ORIG_1=""
VPN_IP_LIST_ORIG_2=""
VPN_IP_LIST_ORIG_3=""
VPN_IP_LIST_ORIG_4=""
VPN_IP_LIST_ORIG_5=""
VPN_IP_LIST_NEW_1=""
VPN_IP_LIST_NEW_2=""
VPN_IP_LIST_NEW_3=""
VPN_IP_LIST_NEW_4=""
VPN_IP_LIST_NEW_5=""
### End of VPN clientlist variables ###

# $1 = print to syslog, $2 = message to print, $3 = log level
Print_Output () {
	if [ "$1" = "true" ] ; then 
		logger -t "$YAZFI_NAME" "$2"
		printf "\\e[1m$3%s: $2\\e[0m\\n\\n" "$YAZFI_NAME"
	else
		printf "\\e[1m$3%s: $2\\e[0m\\n\\n" "$YAZFI_NAME"
	fi
}

Escape_Sed () {
	sed -e 's/</\\</g;s/>/\\>/g;s/ /\\ /g'
}

Get_Iface_Var () {
	echo "$1" | sed -e 's/\.//g'
}

Get_Guest_Name () {
	VPN_NVRAM=""
	
	if echo "$1" | grep -q "wl0" ; then
		VPN_NVRAM="2.4GHz Guest $(echo "$1" | cut -f2 -d".")"
	elif echo "$1" | grep "wl1" ; then
		VPN_NVRAM="5GHz1 Guest $(echo "$1" | cut -f2 -d".")"
	else
		VPN_NVRAM="5GHz2 Guest $(echo "$1" | cut -f2 -d".")"
	fi
	
	echo "$VPN_NVRAM"
}

Iface_Manage () {
	case $1 in
		create)
			ifconfig "$2" "$(eval echo '$'"$(Get_Iface_Var "$IFACE")"_IPADDR | cut -f1-3 -d".").1" netmask 255.255.255.0 # Assign the .1 address to the interface
		;;
		delete)
			ifconfig "$2" 0.0.0.0
		;;
		deleteall)
			for IFACE in $IFACELIST ; do
				Iface_Manage delete "$IFACE"
			done
		;;
	esac
}

Startup_Auto () {
	case $1 in
		create)
			if [ -f /jffs/scripts/firewall-start ] ; then
				STARTUPLINECOUNT=$(grep -c '# '"$YAZFI_NAME"' Guest Networks' /jffs/scripts/firewall-start)
				STARTUPLINECOUNTEX=$(grep -cx "/jffs/scripts/$YAZFI_NAME"' & # '"$YAZFI_NAME"' Guest Networks' /jffs/scripts/firewall-start)
				
				if [ "$STARTUPLINECOUNT" -gt 1 ] || { [ "$STARTUPLINECOUNTEX" -eq 0 ] && [ "$STARTUPLINECOUNT" -gt 0 ]; }; then
					Print_Output "true" "Purging duplicate/invalid entries for $YAZFI_NAME in firewall-start"
					sed -i -e '/# '"$YAZFI_NAME"' Guest Networks/d' /jffs/scripts/firewall-start
				fi
				
				if [ "$STARTUPLINECOUNTEX" -eq 0 ] ; then
					Print_Output "true" "Adding $YAZFI_NAME to firewall-start"
					echo "" >> /jffs/scripts/firewall-start
					echo "/jffs/scripts/$YAZFI_NAME"' & # '"$YAZFI_NAME"' Guest Networks' >> /jffs/scripts/firewall-start
				fi
			else
				Print_Output "true" "firewall-start doesn't exist, creating"
				echo "#!/bin/sh" > /jffs/scripts/firewall-start
				echo "" >> /jffs/scripts/firewall-start
				echo "/jffs/scripts/$YAZFI_NAME"' & # '"$YAZFI_NAME"' Guest Networks' >> /jffs/scripts/firewall-start
				chmod 0755 /jffs/scripts/firewall-start
			fi
		;;
		delete)
			if [ -f /jffs/scripts/firewall-start ] ; then
				STARTUPLINECOUNT=$(grep -c '# '"$YAZFI_NAME"' Guest Networks' /jffs/scripts/firewall-start)
				
				if [ "$STARTUPLINECOUNT" -gt 0 ] ; then
					sed -i -e '/# '"$YAZFI_NAME"' Guest Networks/d' /jffs/scripts/firewall-start
				fi
			fi
		;;
	esac
}

### Code for these functions inspired by https://github.com/Adamm00/IPSet_ASUS - credit to @Adamm ###
Check_Lock () {
	if [ -f "/tmp/$YAZFI_NAME.lock" ] ; then
		ageoflock=$(($(date +%s) - $(date +%s -r /tmp/$YAZFI_NAME.lock)))
		if [ "$ageoflock" -gt 120 ]; then
			Print_Output "true" "Stale lock file found (>120 seconds old) - purging lock" "$ERR"
			kill "$(sed -n '1p' /tmp/$YAZFI_NAME.lock)" >/dev/null 2>&1
			rm -f "/tmp/$YAZFI_NAME.lock"
			echo "$$" > "/tmp/$YAZFI_NAME.lock"
			return 0
		else
			Print_Output "true" "Lock file found (age: $ageoflock seconds) - stopping to prevent duplicate runs" "$ERR"
			exit 1
		fi
	else
		echo "$$" > "/tmp/$YAZFI_NAME.lock"
		return 0
	fi
}

Update_Version () {
	localver=$(grep "YAZFI_VERSION=" /jffs/scripts/$YAZFI_NAME | grep -m1 -oE 'v[0-9]{1,2}([.][0-9]{1,2})([.][0-9]{1,2})')
	/usr/sbin/curl -fsL --retry 3 "$YAZFI_REPO.sh" | grep -qF "jackyaz" || { Print_Output "true" "404 error detected - stopping update" "$ERR"; rm -f "/tmp/$YAZFI_NAME.lock" ; exit 1; }
	serverver=$(/usr/sbin/curl -fsL --retry 3 "$YAZFI_REPO.sh" | grep "YAZFI_VERSION=" | grep -m1 -oE 'v[0-9]{1,2}([.][0-9]{1,2})([.][0-9]{1,2})')
	if [ "$localver" != "$serverver" ] ; then
		Print_Output "true" "New version of $YAZFI_NAME available - updating to $serverver" "$PASS"
		/usr/sbin/curl -fsL --retry 3 "$YAZFI_REPO.sh" -o "/jffs/scripts/$YAZFI_NAME" && Print_Output "true" "YazFi successfully updated - restarting firewall to apply update"
		chmod 0755 "/jffs/scripts/$YAZFI_NAME"
		rm -f "/tmp/$YAZFI_NAME.lock"
		service restart_firewall >/dev/null 2>&1
	else
		Print_Output "true" "No new version - latest is $localver" "$WARN"
		rm -f "/tmp/$YAZFI_NAME.lock"
	fi
}
############################################################################

Validate_IFACE () {
	if ! ifconfig "$1" >/dev/null 2>&1 ; then
		Print_Output "false" "$1 - Interface not enabled/configured in Web GUI (Guest Network menu)" "$ERR"
		return 1
	else
		return 0
	fi
}

Validate_IP () {
	if expr "$2" : '[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$' >/dev/null ; then
		for i in 1 2 3 4; do
			if [ "$(echo "$2" | cut -d. -f$i)" -gt 255 ]; then
				Print_Output "false" "$1 - Octet $i ($(echo "$2" | cut -d. -f$i)) - is invalid, must be less than 255" "$ERR"
				return 1
			fi
		done
		
		if [ "$3" != "DNS" ] ; then
			if echo "$2" | grep -qE '(^10\.)|(^172\.1[6-9]\.)|(^172\.2[0-9]\.)|(^172\.3[0-1]\.)|(^192\.168\.)' ; then 
				return 0
			else
				Print_Output "false" "$1 - $2 - Non-routable IP address block used" "$ERR"
				return 1
			fi
		else
			return 0
		fi
		
	else
		Print_Output "false" "$1 - $2 - is not a valid IPv4 address, valid format is 1.2.3.4" "$ERR"
		return 1
	fi
}

Validate_Number () {
	if [ "$2" -eq "$2" ] 2>/dev/null; then
		return 0
	else
		formatted="$(echo "$1" | sed -e 's/|/ /g')"
		Print_Output "false" "$formatted - $2 is not a number" "$ERR"
		return 1
	fi
}

Validate_DHCP () {
	if ! Validate_Number "$1" "$2" ; then
		return 1
	elif ! Validate_Number "$1" "$3" ; then
		return 1
	fi
	
	if [ "$2" -gt "$3" ] || { [ "$2" -lt 2 ] || [ "$2" -gt 254 ]; } || { [ "$3" -lt 2 ] || [ "$3" -gt 254 ]; } ; then
		Print_Output "false" "$1 - $2 to $3 - both numbers must be between 2 and 254, $2 must be less than $3" "$ERR"
		return 1
	else
		return 0
	fi
}

Validate_VPNClientNo () {
	if ! Validate_Number "$1" "$2" ; then
		return 1
	fi
	
	if [ "$2" -lt 1 ] || [ "$2" -gt 5 ] ; then
		Print_Output "false" "$1 - $2 - must be between 1 and 5" "$ERR"
		return 1
	else
		return 0
	fi
}

Validate_TrueFalse () {
	case "$2" in
		true|TRUE|false|FALSE)
			return 0
		;;
		*)
			Print_Output "false" "$1 - $2 - must be either true or false" "$ERR"
			return 1
		;;
	esac
}

Conf_Validate () {
	
	CONF_VALIDATED=true
	
	for IFACE in $IFACELIST ; do
		IFACETMP="$(Get_Iface_Var "$IFACE")"
		IPADDRTMP=""
		ENABLEDTMP=""
		REDIRECTTMP=""
		IFACE_PASS=true
		
		# Validate _ENABLED
		if [ -z "$(eval echo '$'"$IFACETMP""_ENABLED")" ] ; then
			ENABLEDTMP=false
			sed -i -e "s/""$IFACETMP""_ENABLED=/""$IFACETMP""_ENABLED=false/" "$YAZFI_CONF"
			Print_Output "false" "$IFACETMP""_ENABLED is blank, setting to false" "$WARN"
		elif ! Validate_TrueFalse "$IFACETMP""_ENABLED" "$(eval echo '$'"$IFACETMP""_ENABLED")" ; then
			ENABLEDTMP=false
			IFACE_PASS=false
		else
			ENABLEDTMP="$(eval echo '$'"$IFACETMP""_ENABLED")"
		fi
		
		if [ "$ENABLEDTMP" = "true" ] ; then
			
			# Validate interface is enabled in GUI
			if ! Validate_IFACE "$IFACE"; then
				IFACE_PASS=false
			fi
			
			# Only validate interfaces enabled in config file
			if [ "$(eval echo '$'"$IFACETMP""_ENABLED")" = "true" ] ; then
				
				# Validate _IPADDR
				if [ -z "$(eval echo '$'"$IFACETMP""_IPADDR")" ] ; then
					IPADDRTMP="$(echo "$LAN" | cut -f1-2 -d".").$(($(echo "$LAN" | cut -f3 -d".")+1))"
					
					COUNTER=1
					until [ "$(grep -o "$IPADDRTMP".0 $YAZFI_CONF | wc -l)" -eq 0 ] && [ "$(ifconfig -a | grep -o "$IPADDRTMP".1 | wc -l )" -eq 0 ] ; do
						IPADDRTMP="$(echo "$LAN" | cut -f1-2 -d".").$(($(echo "$LAN" | cut -f3 -d".")+COUNTER))"
						COUNTER=$((COUNTER + 1))
					done
					
					sed -i -e "s/""$IFACETMP""_IPADDR=/""$IFACETMP""_IPADDR=""$IPADDRTMP"".0/" "$YAZFI_CONF"
					Print_Output "false" "$IFACETMP""_IPADDR is blank, setting to next available subnet above primary LAN subnet" "$WARN"
				elif ! Validate_IP "$IFACETMP""_IPADDR" "$(eval echo '$'"$IFACETMP""_IPADDR")" ; then
					IFACE_PASS=false
				else
					
					IPADDRTMP="$(eval echo '$'"$IFACETMP""_IPADDR" | cut -f1-3 -d".")"
					
					# Set last octet to 0
					if [ "$(eval echo '$'"$IFACETMP""_IPADDR" | cut -f4 -d".")" -ne 0 ] ; then
						sed -i -e "s/""$IFACETMP""_IPADDR=$(eval echo '$'"$IFACETMP""_IPADDR")/""$IFACETMP""_IPADDR=""$IPADDRTMP"".0/" "$YAZFI_CONF"
						Print_Output "false" "$IFACETMP""_IPADDR setting last octet to 0" "$WARN"
					fi
					
					if [ "$(grep -o "$IPADDRTMP".0 $YAZFI_CONF | wc -l )" -gt 1 ] || [ "$(ifconfig -a | grep -o "$IPADDRTMP".1 | wc -l )" -gt 1 ]; then
						Print_Output "false" "$IFACETMP""_IPADDR ($(eval echo '$'"$IFACETMP""_IPADDR")) has been used for another interface already" "$ERR"
						IFACE_PASS=false
					fi
				fi
				
				#Validate _DHCPSTART and _DHCPEND
				if [ -z "$(eval echo '$'"$IFACETMP""_DHCPSTART")" ] ; then
					sed -i -e "s/""$IFACETMP""_DHCPSTART=/""$IFACETMP""_DHCPSTART=2/" "$YAZFI_CONF"
					Print_Output "false" "$IFACETMP""_DHCPSTART is blank, setting to 2" "$WARN"
				fi
				
				if [ -z "$(eval echo '$'"$IFACETMP""_DHCPEND")" ] ; then
					sed -i -e "s/""$IFACETMP""_DHCPEND=/""$IFACETMP""_DHCPEND=254/" "$YAZFI_CONF"
					Print_Output "false" "$IFACETMP""_DHCPEND is blank, setting to 254" "$WARN"
				fi
				
				if [ ! -z "$(eval echo '$'"$IFACETMP""_DHCPSTART")" ] && [ ! -z "$(eval echo '$'"$IFACETMP""_DHCPEND")" ] ; then
					if ! Validate_DHCP "$IFACETMP""_DHCPSTART|and|""$IFACETMP""_DHCPEND" "$(eval echo '$'"$IFACETMP""_DHCPSTART")" "$(eval echo '$'"$IFACETMP""_DHCPEND")" ; then
					IFACE_PASS=false
					fi
				fi
				
				# Validate _DNS1
				if [ -z "$(eval echo '$'"$IFACETMP""_DNS1")" ] ; then
					if [ ! -z "$(eval echo '$'"$IFACETMP""_IPADDR")" ] ; then
						sed -i -e "s/""$IFACETMP""_DNS1=/""$IFACETMP""_DNS1=$(eval echo '$'"$IFACETMP""_IPADDR" | cut -f1-3 -d".").1/" "$YAZFI_CONF"
						Print_Output "false" "$IFACETMP""_DNS1 is blank, setting to $(eval echo '$'"$IFACETMP""_IPADDR" | cut -f1-3 -d".").1" "$WARN"
					else
						sed -i -e "s/""$IFACETMP""_DNS1=/""$IFACETMP""_DNS1=$IPADDRTMP.1/" "$YAZFI_CONF"
						Print_Output "false" "$IFACETMP""_DNS1 is blank, setting to $IPADDRTMP.1" "$WARN"
					fi
				elif ! Validate_IP "$IFACETMP""_DNS1" "$(eval echo '$'"$IFACETMP""_DNS1")" "DNS"; then
					IFACE_PASS=false
				fi
				
				# Validate _DNS2
				if [ -z "$(eval echo '$'"$IFACETMP""_DNS2")" ] ; then
					if [ ! -z "$(eval echo '$'"$IFACETMP""_IPADDR")" ] ; then
						sed -i -e "s/""$IFACETMP""_DNS2=/""$IFACETMP""_DNS2=$(eval echo '$'"$IFACETMP""_IPADDR" | cut -f1-3 -d".").1/" "$YAZFI_CONF"
						Print_Output "false" "$IFACETMP""_DNS2 is blank, setting to $(eval echo '$'"$IFACETMP""_IPADDR" | cut -f1-3 -d".").1" "$WARN"
					else
						sed -i -e "s/""$IFACETMP""_DNS2=/""$IFACETMP""_DNS2=$IPADDRTMP.1/" "$YAZFI_CONF"
						Print_Output "false" "$IFACETMP""_DNS2 is blank, setting to $IPADDRTMP.1" "$WARN"
					fi
				elif ! Validate_IP "$IFACETMP""_DNS2" "$(eval echo '$'"$IFACETMP""_DNS2")" "DNS"; then
					IFACE_PASS=false
				fi
				
				# Validate _REDIRECTALLTOVPN
				if [ -z "$(eval echo '$'"$IFACETMP""_REDIRECTALLTOVPN")" ] ; then
					REDIRECTTMP=false
					sed -i -e "s/""$IFACETMP""_REDIRECTALLTOVPN=/""$IFACETMP""_REDIRECTALLTOVPN=false/" "$YAZFI_CONF"
					Print_Output "false" "$IFACETMP""_REDIRECTALLTOVPN is blank, setting to false" "$WARN"
				elif ! Validate_TrueFalse "$IFACETMP""_REDIRECTALLTOVPN" "$(eval echo '$'"$IFACETMP""_REDIRECTALLTOVPN")" ; then
					REDIRECTTMP=false
					IFACE_PASS=false
				else
					REDIRECTTMP="$(eval echo '$'"$IFACETMP""_REDIRECTALLTOVPN")"
				fi
				
				# Validate _VPNCLIENTNUMBER if _REDIRECTALLTOVPN is enabled
				if [ "$REDIRECTTMP" = "true" ] ; then
					if [ -z "$(eval echo '$'"$IFACETMP""_VPNCLIENTNUMBER")" ] ; then
						Print_Output "false" "$IFACETMP""_VPNCLIENTNUMBER is blank" "$ERR"
						IFACE_PASS=false
					elif ! Validate_VPNClientNo "$IFACETMP""_VPNCLIENTNUMBER" "$(eval echo '$'"$IFACETMP""_VPNCLIENTNUMBER")" ; then
						IFACE_PASS=false
					else
						#Validate VPN client is configured for policy routing
						if [ "$(nvram get vpn_client"$(eval echo '$'"$IFACETMP""_VPNCLIENTNUMBER")"_rgw)" -lt 2 ] ; then
							Print_Output "false" "VPN Client $(eval echo '$'"$IFACETMP""_VPNCLIENTNUMBER") is not configured for Policy Routing" "$ERR"
							IFACE_PASS=false
						fi
					fi
				fi
				
				# Print success message
				if [ "$IFACE_PASS" = true ] ; then
					Print_Output "false" "$IFACE passed validation" "$PASS"
				fi
			fi
		fi
		
		# Print failure message
		if [ "$IFACE_PASS" = false ] ; then
			Print_Output "false" "$IFACE failed validation" "$CRIT"
			CONF_VALIDATED=false
		fi
	done
	
	if [ "$CONF_VALIDATED" = true ] ; then
		return 0
	else
		rm -f "/tmp/$YAZFI_NAME.lock"
		return 1
	fi
	
}

Conf_Download () {
	Print_Output "false" "Downloading a blank configuration file to $1"
	sleep 1
	/usr/sbin/curl -s --retry 3 "$YAZFI_REPO.config" -o "$1"
	chmod 0644 "$1"
	dos2unix "$1"
	Print_Output "false" "Please edit $1 with your desired settings. For a sample configuration file, see $YAZFI_REPO.config.sample"
	sleep 1
	Print_Output "false" "Please run \\n\\n/jffs/scripts/$YAZFI_NAME\\n\\nin your SSH client/terminal when you have finished editing the configuration file"
	rm -f "/tmp/$YAZFI_NAME.lock"
}

Conf_Exists () {
	if [ -f "$YAZFI_CONF" ] ; then
		dos2unix "$YAZFI_CONF"
		chmod 0644 "$YAZFI_CONF"
		sed -i -e 's/"//g' "$YAZFI_CONF"
		. "$YAZFI_CONF"
		return 0
	else
		return 1
	fi
}

Firewall_Chains() {
	FWRDSTART="$(($(iptables -nvL FORWARD --line | grep -E "ACCEPT     all.*state RELATED,ESTABLISHED" | awk '{print $1}') + 1))"
	
	case $1 in
		create)
			for CHAIN in $CHAINS ; do
				if ! iptables -n -L "$CHAIN" >/dev/null 2>&1 ; then
					iptables -N "$CHAIN"
					case $CHAIN in
						$INPT)
							iptables -I INPUT -j "$CHAIN"
						;;
						$FWRD)
							iptables -I FORWARD "$FWRDSTART" -j "$CHAIN"
						;;
						$LGRJT)
							iptables -I "$LGRJT" -j REJECT
							
							# Optional rule to log all rejected packets to syslog
							#iptables -I $LGRJT -m state --state NEW -j LOG --log-prefix "REJECT " --log-tcp-sequence --log-tcp-options --log-ip-options
					esac
				fi
			done
		;;
		deleteall)
			for CHAIN in $CHAINS ; do
				if iptables -n -L "$CHAIN" >/dev/null 2>&1 ; then
					case $CHAIN in
						$INPT)
							iptables -D INPUT -j "$CHAIN"
						;;
						$FWRD)
							iptables -D FORWARD "$FWRDSTART"
						;;
						$LGRJT)
							iptables -D "$LGRJT" -j REJECT
					esac
					
					iptables -F "$CHAIN"
					iptables -X "$CHAIN"
				fi
			done
		;;
	esac
}

Firewall_Rules () {
	ACTIONS=""
	IFACE="$2"
	
	case $1 in
		create)
			ACTIONS="-D -I"
		;;
		delete)
			ACTIONS="-D"
		;;
	esac
	
	for ACTION in $ACTIONS ; do
		
		### Start of bridge rules ###
		
		# Un-bridge all frames entering br0 for IPv4, IPv6 and ARP to be processed by iptables
		ebtables -t broute "$ACTION" BROUTING -p ipv4 -i "$IFACE" -j DROP
		ebtables -t broute "$ACTION" BROUTING -p ipv6 -i "$IFACE" -j DROP
		ebtables -t broute "$ACTION" BROUTING -p arp -i "$IFACE" -j DROP
		
		ebtables "$ACTION" FORWARD -i "$IFACE" -j DROP
		ebtables "$ACTION" FORWARD -o "$IFACE" -j DROP
		
		ebtables -t broute -D BROUTING -p IPv4 -i "$IFACE" --ip-dst "$LAN"/24 --ip-proto tcp -j DROP
		### End of bridge rules ###
		
		### Start of IP firewall rules ###
		iptables "$ACTION" "$FWRD" -i "$IFACE" -m state --state NEW -j ACCEPT
		
		iptables "$ACTION" "$FWRD" -i "$IFACE" -o br0 -m state --state NEW -j "$LGRJT"
		iptables "$ACTION" "$FWRD" -i br0 -o "$IFACE" -m state --state NEW -j "$LGRJT"
		
		for IFACE_GUEST in $IFACELIST ; do
			IFACETMP_GUEST="$(Get_Iface_Var "$IFACE_GUEST")"
			if [ "$(eval echo '$'"$IFACETMP"_GUEST_ENABLED)" = "true" ] ; then
				iptables "$ACTION" "$FWRD" -i "$IFACE" -o "$IFACE_GUEST" -m state --state NEW -j "$LGRJT"
			fi
		done
		
		iptables "$ACTION" "$INPT" -i "$IFACE" -m state --state NEW -j "$LGRJT"
		iptables "$ACTION" "$INPT" -i "$IFACE" -p udp -m multiport --dports 67,123 -j ACCEPT
		
		if [ "$(eval echo '$'"$(Get_Iface_Var "$IFACE")""_DNS1")" = "$(eval echo '$'"$(Get_Iface_Var "$IFACE")""_IPADDR" | cut -f1-3 -d".").1" ] || [ "$(eval echo '$'"$(Get_Iface_Var "$IFACE")""_DNS2")" = "$(eval echo '$'"$(Get_Iface_Var "$IFACE")""_IPADDR" | cut -f1-3 -d".").1" ] ; then
			if ifconfig "br0:pixelserv" | grep -q "inet addr:" >/dev/null 2>&1 ; then
				modprobe xt_comment
				IP_PXLSRV=$(ifconfig br0:pixelserv | grep "inet addr:" | cut -d: -f2 | awk '{print $1}')
				iptables "$ACTION" "$INPT" -i "$IFACE" -d "$IP_PXLSRV" -p tcp -m multiport --dports 80,443 -m state --state NEW -m comment --comment "PixelServ" -j ACCEPT
			else
				RULES=$(iptables -nvL $INPT --line-number | grep "PixelServ" | awk '{print $1}' | awk '{for(i=NF;i>0;--i)printf "%s%s",$i,(i>1?OFS:ORS)}')
				for RULENO in $RULES ; do
					iptables -D "$INPT" "$RULENO"
				done
			fi
			
			for PROTO in tcp udp ; do
				iptables "$ACTION" "$INPT" -i "$IFACE" -p "$PROTO" --dport 53 -j ACCEPT
			done
		else
			RULES=$(iptables -nvL $INPT --line-number | grep "dpt:53" | awk '{print $1}' | awk '{for(i=NF;i>0;--i)printf "%s%s",$i,(i>1?OFS:ORS)}')
			for RULENO in $RULES ; do
				iptables -D "$INPT" "$RULENO"
			done
		fi
		
		### End of IP firewall rules ###
		
		# COUNTER=1
		# until [ $COUNTER -gt 5 ] ; do
			# if ifconfig "tun1$COUNTER" >/dev/null 2>&1 ; then
				# ip route del $IPADDR.0/24 dev $IFACE proto kernel table ovpnc$COUNTER src $IPADDR.1
				# ip route add $IPADDR.0/24 dev $IFACE proto kernel table ovpnc$COUNTER src $IPADDR.1
				# iptables -t nat -D POSTROUTING -s $IPADDR.0/24 -o tun1$COUNTER -j MASQUERADE
				# iptables -t nat -I POSTROUTING -s $IPADDR.0/24 -o tun1$COUNTER -j MASQUERADE
			# fi
			
			# let COUNTER+=1
		# done
		
	done
}

Routing_RPDB () {
	
	case $1 in
		create)
			ip route del "$(eval echo '$'"$(Get_Iface_Var "$2")""_IPADDR" | cut -f1-3 -d".")".0/24 dev "$2" proto kernel table ovpnc"$3" src "$(eval echo '$'"$(Get_Iface_Var "$2")""_IPADDR" | cut -f1-3 -d".")".1
			ip route add "$(eval echo '$'"$(Get_Iface_Var "$2")""_IPADDR" | cut -f1-3 -d".")".0/24 dev "$2" proto kernel table ovpnc"$3" src "$(eval echo '$'"$(Get_Iface_Var "$2")""_IPADDR" | cut -f1-3 -d".")".1
		;;
		delete)
			COUNTER=1
			until [ $COUNTER -gt 5 ] ; do
				ip route del "$(ip route show table ovpnc"$COUNTER" | grep "$2" | grep -Po '(\d{1,3}.){4}(\d{1,2})')" dev "$2" proto kernel table ovpnc"$COUNTER" src "$(ip route show table ovpnc"$COUNTER" | grep "$2" | grep -Po '(?<=src )(\d{1,3}.){4}')" 2>/dev/null
				COUNTER=$((COUNTER + 1))
			done
		;;
		deleteall)
			for IFACE in $IFACELIST ; do
				Routing_RPDB delete "$IFACE" 2>/dev/null
			done
		;;
	esac
	
	ip route flush cache
}

Routing_FWNAT () {
	
	case $1 in
		create)
			for ACTION in -D -I ; do
				modprobe xt_comment
				iptables -t nat "$ACTION" POSTROUTING -s "$(eval echo '$'"$(Get_Iface_Var "$2")""_IPADDR" | cut -f1-3 -d".")".0/24 -o tun1"$3" -m comment --comment "$(Get_Guest_Name "$2")" -j MASQUERADE
				iptables "$ACTION" "$FWRD" -i "$2" -o tun1"$3" -m state --state NEW -j ACCEPT
				iptables "$ACTION" "$FWRD" -i tun1"$3" -o "$2" -m state --state NEW -j ACCEPT
			done
		;;
		delete)
			RULES=$(iptables -t nat -nvL POSTROUTING --line-number | grep "$(Get_Guest_Name "$2")" | awk '{print $1}' | awk '{for(i=NF;i>0;--i)printf "%s%s",$i,(i>1?OFS:ORS)}')
			for RULENO in $RULES ; do
				iptables -t nat -D POSTROUTING "$RULENO"
			done
			
			RULES=$(iptables -nvL $FWRD --line-number | grep "$2" | grep "tun1" | awk '{print $1}' | awk '{for(i=NF;i>0;--i)printf "%s%s",$i,(i>1?OFS:ORS)}')
			for RULENO in $RULES ; do
				iptables -D "$FWRD" "$RULENO"
			done
		;;
		deleteall)
			for IFACE in $IFACELIST ; do
				Routing_FWNAT delete "$IFACE" 2>/dev/null
			done
		;;
	esac
}

Routing_NVRAM() {
	
	case $1 in
		initialise)
			COUNTER=1
			until [ $COUNTER -gt 5 ] ; do
				eval "VPN_IP_LIST_ORIG_"$COUNTER="$(echo "$(nvram get "vpn_client""$COUNTER""_clientlist")""$(nvram get "vpn_client""$COUNTER""_clientlist1")""$(nvram get "vpn_client""$COUNTER""_clientlist2")""$(nvram get "vpn_client""$COUNTER""_clientlist3")""$(nvram get "vpn_client""$COUNTER""_clientlist4")""$(nvram get "vpn_client""$COUNTER""_clientlist5")" | Escape_Sed)"
				eval "VPN_IP_LIST_NEW_"$COUNTER="$(eval echo '$'"VPN_IP_LIST_ORIG_"$COUNTER | Escape_Sed)"
				COUNTER=$((COUNTER + 1))
			done
		;;
		create)
			VPN_NVRAM="$(Get_Guest_Name "$2")"
			VPN_IFACE_NVRAM="<$VPN_NVRAM>$(eval echo '$'"$(Get_Iface_Var "$2")""_IPADDR" | cut -f1-3 -d".").0/24>0.0.0.0>VPN"
			VPN_IFACE_NVRAM_SAFE="$(echo "$VPN_IFACE_NVRAM" | sed -e 's/\//\\\//g;s/\./\\./g;s/ /\\ /g')"
			
			# Check if guest network has already been added to policy routing for VPN client. If not, append to list.
			if ! eval echo '$'"VPN_IP_LIST_ORIG_""$3" | grep -q "$VPN_IFACE_NVRAM" ; then
				eval "VPN_IP_LIST_NEW_""$3"="$(echo "$(eval echo '$'"VPN_IP_LIST_NEW_""$3")""$VPN_IFACE_NVRAM" | Escape_Sed)"
			fi
			
			# Remove guest interface from any other VPN clients (i.e. config has changed from client 2 to client 1)
			COUNTER=1
			until [ $COUNTER -gt 5 ] ; do
				if [ $COUNTER -eq "$3" ] ; then
					COUNTER=$((COUNTER + 1))
					continue
				fi
				eval "VPN_IP_LIST_NEW_"$COUNTER="$(eval echo '$'"VPN_IP_LIST_NEW_""$COUNTER" | sed -e "s/$VPN_IFACE_NVRAM_SAFE//g" | Escape_Sed)"
				COUNTER=$((COUNTER + 1))
			done
		;;
		delete)
			COUNTER=1
			until [ $COUNTER -gt 5 ] ; do
				VPN_NVRAM="$(Get_Guest_Name $2)"
				eval "VPN_IP_LIST_NEW_"$COUNTER=$(echo $(eval echo '$'"VPN_IP_LIST_NEW_"$COUNTER) | sed -e "s/$(echo '<'$VPN_NVRAM |  sed -e 's/\//\\\//g' | sed -e 's/ /\\ /g').*>VPN//g" | Escape_Sed)
				let COUNTER+=1
			done
		;;
		deleteall)
			Routing_NVRAM initialise 2>/dev/null
			
			for IFACE in $IFACELIST ; do
				Routing_NVRAM delete $IFACE 2>/dev/null
			done
			
			Routing_NVRAM save 2>/dev/null
		;;
		save)
			COUNTER=1
			until [ $COUNTER -gt 5 ] ; do
				if [ "$(eval echo '$'"VPN_IP_LIST_ORIG_"$COUNTER)" != "$(eval echo '$'"VPN_IP_LIST_NEW_"$COUNTER)" ] ; then
					Print_Output "true" "VPN Client $COUNTER client list has changed, restarting VPN Client $COUNTER"
					
					if [ $(uname -m) = "aarch64" ] ; then 
						fullstring="$(eval echo '$'"VPN_IP_LIST_NEW_"$COUNTER)"
						nvram set "vpn_client"$COUNTER"_clientlist"="${fullstring:0:255}"
						nvram set "vpn_client"$COUNTER"_clientlist1"="${fullstring:255:255}"
						nvram set "vpn_client"$COUNTER"_clientlist2"="${fullstring:510:255}"
						nvram set "vpn_client"$COUNTER"_clientlist3"="${fullstring:765:255}"
						nvram set "vpn_client"$COUNTER"_clientlist4"="${fullstring:1020:255}"
						nvram set "vpn_client"$COUNTER"_clientlist5"="${fullstring:1275:255}"
					else
						nvram set "vpn_client"$COUNTER"_clientlist"="$(eval echo '$'"VPN_IP_LIST_NEW_"$COUNTER)"
					fi
					nvram commit
					service restart_vpnclient$COUNTER >/dev/null 2>&1
				fi
				let COUNTER+=1
			done
		;;
	esac
}

DHCP_Conf() {
	
	
	case $1 in
		initialise)
			if [ -f $DNSCONF ] ; then
				cp $DNSCONF $TMPCONF
			else
				touch $TMPCONF
			fi
		;;
		create)
			CONFSTRING="interface=$2||||dhcp-range=$2,$(echo $(eval echo '$'$(Get_Iface_Var "$2")"_IPADDR") | cut -f1-3 -d".").$(eval echo '$'$(Get_Iface_Var "$2")"_DHCPSTART"),$(echo $(eval echo '$'$(Get_Iface_Var "$2")"_IPADDR") | cut -f1-3 -d".").$(eval echo '$'$(Get_Iface_Var "$2")"_DHCPEND"),255.255.255.0,43200s||||dhcp-option=$2,3,$(echo $(eval echo '$'$(Get_Iface_Var "$2")"_IPADDR") | cut -f1-3 -d".").1||||dhcp-option=$2,6,$(eval echo '$'$(Get_Iface_Var "$2")"_DNS1"),$(eval echo '$'$(Get_Iface_Var "$2")"_DNS2")"
			BEGIN="### Start of script-generated configuration for interface $2 ###"
			END="### End of script-generated configuration for interface $2 ###"
			if grep -q "### Start of script-generated configuration for interface $2 ###" $TMPCONF; then
				sed -i -e '/'"$BEGIN"'/,/'"$END"'/c\'"$BEGIN"'||||'"$CONFSTRING"'||||'"$END" $TMPCONF
			else
				echo -e "\n\n$BEGIN\n$CONFSTRING\n$END" >> $TMPCONF
			fi
		;;
		delete)
			BEGIN="### Start of script-generated configuration for interface $2 ###"
			if grep -q "### Start of script-generated configuration for interface $2 ###" $TMPCONF; then
				sed -i -e '/'"$BEGIN"'/,+5d' $TMPCONF
			fi
		;;
		deleteall)
			DHCP_Conf initialise 2>/dev/null
			for IFACE in $IFACELIST ; do
				BEGIN="### Start of script-generated configuration for interface $IFACE ###"
				if grep -q "### Start of script-generated configuration for interface $IFACE ###" $TMPCONF; then
					sed -i -e '/'"$BEGIN"'/,+5d' $TMPCONF
				fi
			done
			DHCP_Conf save 2/dev/null
		;;
		save)
			sed -i -e 's/||||/\n/g' $TMPCONF
			
			if ! diff -q $DNSCONF $TMPCONF >/dev/null 2>&1; then
				cp $TMPCONF $DNSCONF
				service restart_dnsmasq >/dev/null 2>&1
				Print_Output "true" "DHCP configuration updated"
			fi
			
			rm -f $TMPCONF
	esac
	
}

Config_Networks () {
	
	if ! Conf_Exists ; then
		Conf_Download $YAZFI_CONF
		exit 1
	fi
	
	if ! Conf_Validate ; then
		exit 1
	fi
	
	. $YAZFI_CONF
	
	Startup_Auto create 2>/dev/null
	
	DHCP_Conf initialise 2>/dev/null
	
	Routing_NVRAM initialise 2>/dev/null
	Firewall_Chains create 2>/dev/null
	
	for IFACE in $IFACELIST ; do
		VPNCLIENTNO=$(eval echo '$'$(Get_Iface_Var "$IFACE")"_VPNCLIENTNUMBER")
		
		if [ "$(eval echo '$'$(Get_Iface_Var "$IFACE")"_ENABLED")" = "true" ] ; then
			Iface_Manage create $IFACE 2>/dev/null
			
			Firewall_Rules create $IFACE 2>/dev/null
			
			if [ "$(eval echo '$'$(Get_Iface_Var "$IFACE")"_REDIRECTALLTOVPN")" = "true" ] ; then
				Print_Output "true" "$IFACE (SSID: $(nvram get $IFACE"_ssid")) - VPN redirection enabled, sending all interface internet traffic over VPN Client $VPNCLIENTNO"
				
				Routing_NVRAM create $IFACE $VPNCLIENTNO 2>/dev/null
				
				Routing_RPDB create $IFACE $VPNCLIENTNO 2>/dev/null
				
				Routing_FWNAT create $IFACE $VPNCLIENTNO 2>/dev/null
			else
				Print_Output "true" "$IFACE (SSID: $(nvram get $IFACE"_ssid")) - sending all interface internet traffic over WAN interface"
				
				# Remove guest interface from VPN client routing table
				Routing_RPDB delete $IFACE 2>/dev/null
				
				# Remove guest interface VPN NAT rules and interface access
				Routing_FWNAT delete $IFACE 2>/dev/null
				
				# Remove guest interface from all policy routing
				Routing_NVRAM delete $IFACE 2>/dev/null
			fi
			
			DHCP_Conf create $IFACE 2>/dev/null
			
			sleep 1
		else
			Iface_Manage delete $IFACE 2>/dev/null
			
			# Remove dnsmasq entries for this interface
			DHCP_Conf delete $IFACE 2>/dev/null
			
			# Remove guest interface from all policy routing
			Routing_NVRAM delete $IFACE 2>/dev/null
			
			# Remove guest interface from VPN client routing table
			Routing_RPDB delete $IFACE 2>/dev/null
			
			# Remove guest interface VPN NAT rules and interface access
			Routing_FWNAT delete $IFACE 2>/dev/null
			
		fi
	done
	
	Routing_NVRAM save 2>/dev/null
	
	DHCP_Conf save 2/dev/null
	
	rm -f /tmp/$YAZFI_NAME.lock
	
	Print_Output "true" "YazFi $YAZFI_VERSION completed successfully" "$PASS"
}

if [ -z "$1" ]; then
	Check_Lock
	Print_Output "true" "YazFi $YAZFI_VERSION starting up"
	Config_Networks
	exit 0
fi

case "$1" in
	install)
		Check_Lock
		Print_Output "true" "Welcome to YazFi $YAZFI_VERSION, a script by JackYaz"
		sleep 1
		
		if ! Conf_Exists ; then
			Conf_Download "$YAZFI_CONF"
		else
			Print_Output "false" "Existing $YAZFI_CONF found. This will be kept by $YAZFI_NAME. Downloading a blank file for comparison (e.g. new settings)"
			Conf_Download $YAZFI_CONF".blank"
			Config_Networks
		fi
		
		exit 0
	;;
	update)
		Check_Lock
		Print_Output "true" "Welcome to YazFi $YAZFI_VERSION, a script by JackYaz"
		sleep 1
		Update_Version
		exit 0
	;;
	uninstall)
		Startup_Auto delete 2>/dev/null
		Routing_NVRAM deleteall 2>/dev/null
		Routing_FWNAT deleteall 2>/dev/null
		Routing_RPDB deleteall 2>/dev/null
		Firewall_Chains deleteall 2>/dev/null
		Iface_Manage deleteall 2>/dev/null
		DHCP_Conf deleteall 2>/dev/null
		exit 0
	;;
	status)
		. "$YAZFI_CONF"
		for IFACE in $IFACELIST ; do
			if [ "$(eval echo '$'"$(Get_Iface_Var "$IFACE")""_ENABLED")" = "true" ] ; then
				macinfo="$(wl -i "$IFACE" assoclist)"
				if [ "$macinfo" != "" ] ; then
					macaddr="${macinfo#* }"
					arpinfo="$(arp -a | grep -iF "$macaddr" | awk '{print $1 " " $2}')"
					printf "%s %s\\n" "$macaddr" "$arpinfo"
				fi
			fi
		done
	;;
	*)
		echo "Command not recognised, please try again"
		exit 1
	;;
esac
