# installation path
installation_path=$(realpath .)

# get platform
if [ -d "/system" ]; then
  device=0 # android
else
  device=1 # linux
fi

# determine shebang
if [ "$device" -eq 0 ]; then
  sh_location=$(which sh)
  echo "creating scripts. run them using sh script.sh or move the created shortcuts to an executable location."
elif [ "$device" -eq 1 ]; then
  if [ -e "/usr/bin/env" ]; then
    sh_location="/usr/bin/env bash"
  else
    sh_location=$(which bash)
    if [ "$sh_location" == "" ]; then
      sh_location=$(which sh)
      echo "bash not found, falling back to POSIX shell"
    fi
  fi
fi

# create files
echo "#!$sh_location" >"$installation_path/"airba.sh
cat "$installation_path/src/airba.sh" >>"$installation_path/airba.sh"
chmod +x "$installation_path/"airba.sh
echo "#!$sh_location" >"$installation_path/"crackdefault.sh
cat "$installation_path/src/crackdefault.sh" >>"$installation_path/crackdefault.sh"
chmod +x "$installation_path/"crackdefault.sh

# create shortcuts that can be moved to a folder that is on $PATH
echo "#!$sh_location" >"$installation_path/"airbash
echo "cd $installation_path" >>"$installation_path/"airbash
if [ "$device" -eq 0 ]; then
  echo "sh airba.sh $@" >>"$installation_path/"airbash
else
  echo "./airba.sh $@" >>"$installation_path/"airbash
fi
chmod +x "$installation_path/"airbash
echo "#!$sh_location" >"$installation_path/"crackdefault
echo "cd $installation_path" >>"$installation_path/"crackdefault
if [ "$device" -eq 0 ]; then
  echo "sh crackdefault.sh $@" >>"$installation_path/"crackdefault
else
  echo "./crackdefault.sh $@" >>"$installation_path/"crackdefault
fi
chmod +x "$installation_path/"crackdefault

if [ ! -d "$installation_path/.location" ]; then
  # create static location file
  mkdir "$installation_path/.location"
  echo "time,lat,lon,elevation,accuracy,bearing,speed" >"$installation_path/.location/default.txt"
  echo "2018-04-22T19:54:07Z,0.0,0.0,0.0,0.0,0.0,0.0" >>"$installation_path/.location/default.txt"
fi

# seed database
sqlite3 "$installation_path/.database.sqlite3" "CREATE TABLE captures (id INTEGER PRIMARY KEY NOT NULL, latitude VARCHAR(12), longitude VARCHAR(12), bssid VARCHAR(17) UNIQUE, essid VARCHAR(255), pmkid VARCHAR(255), psk VARCHAR(64), processed INT(1) DEFAULT NULL)"
