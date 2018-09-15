# airbash module template
# generate keys

MODULE_BIN=$(pathttobin)
$("$MODULE_BIN cli command for 2.4 ghz" >>"$path"wltmplatetmp)
$("$MODULE_BIN cli command for 5 ghz if available" >>"$path"wltmplatetmp)

# clean program output if necessary
for j in $("applying awk filter" "$path"wltmplatetmp 2>/dev/null); do
  echo "$j" >>"$path"wltmplate
done

# test keys
psk=$("$AIRCRACK_BIN" "$path$hs$bssid"*.cap -w "$path"wltmplate 2>/dev/null | grep FOUND | grep -oE 'charset&length' | sort -u)
sqlite3 "$path$db" "UPDATE hs SET prcsd=1 WHERE bssid='$bssid';" 2>/dev/null
rm -f "$path"wl* 2>/dev/null

# insert to db if key recovery successful
if [ ${#psk} -gt 7 ]; then
  echo "Key $psk found for BSSID $bssid"
  sqlite3 "$path$db" "UPDATE hs SET psk='$psk' WHERE bssid='$bssid';" 2>/dev/null
  echo "$psk" >>"$path$wl"known
  mv "$path$hs$bssid"* "$path$hs".cracked/ 2>/dev/null
  continue
fi
