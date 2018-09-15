# installation path
instpath=$(realpath .)

# get platform
if [ -d "/system" ]; then
  device=0 # android
else
  device=1 # linux
fi

# determine shebang
if [ "$device" -eq 0 ]; then
  sh_loc=$(which sh)
  echo "creating scripts. run them using sh script.sh or move the created shortcuts to an executable location."
elif [ "$device" -eq 1 ]; then
  if [ -e "/usr/bin/env" ]; then
    sh_loc="/usr/bin/env bash"
  else
    sh_loc=$(which bash)
    if [ "$sh_loc" == "" ]; then
      sh_loc=$(which sh)
      echo "bash not found, falling back to POSIX shell"
    fi
  fi
fi

# create files
echo "#!$sh_loc" >"$instpath/"airba.sh
cat "$instpath/src/airba.sh" >>"$instpath/airba.sh"
chmod +x "$instpath/"airba.sh
echo "#!$sh_loc" >"$instpath/"crackdefault.sh
cat "$instpath/src/crackdefault.sh" >>"$instpath/crackdefault.sh"
chmod +x "$instpath/"crackdefault.sh

# create shortcuts that can be moved to a folder that is on $PATH
echo "#!$sh_loc" >"$instpath/"airbash
echo "cd $instpath" >>"$instpath/"airbash
if [ "$device" -eq 0 ]; then
  echo "sh airba.sh $@" >>"$instpath/"airbash
else
  echo "./airba.sh $@" >>"$instpath/"airbash
fi
chmod +x "$instpath/"airbash
echo "#!$sh_loc" >"$instpath/"crackdefault
echo "cd $instpath" >>"$instpath/"crackdefault
if [ "$device" -eq 0 ]; then
  echo "sh crackdefault.sh $@" >>"$instpath/"crackdefault
else
  echo "./crackdefault.sh $@" >>"$instpath/"crackdefault
fi
chmod +x "$instpath/"crackdefault

if [ ! -d "$instpath/.loc" ]; then
  # create static files
  mkdir "$instpath/.loc" # &>/dev/null
  echo "time,lat,lon,elevation,accuracy,bearing,speed" >"$instpath/.loc/default.txt"
  echo "2018-04-22T19:54:07Z,0.0,0.0,0.0,0.0,0.0,0.0" >>"$instpath/.loc/default.txt"
fi

# seed database
sqlite3 .db.sqlite3 "CREATE TABLE hs (id INTEGER PRIMARY KEY NOT NULL, lat VARCHAR(12), lon VARCHAR(12), bssid VARCHAR(17) UNIQUE, essid VARCHAR(255), psk VARCHAR(64), prcsd INT(1) DEFAULT NULL)"
