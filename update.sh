# installation path
instpath=`pwd`

# set platform specific variables
if [ -d "/system" ]; then  # android
    tmp="upgrade"
    mkdir "$instpath/$tmp"
else  # linux
    tmp="/tmp"
fi

# download latest version
rm -rf "$tmp/airbash"
git clone https://github.com/tehw0lf/airbash "$tmp/"
mv "$tmp/airbash" "$instpath"
echo "installing update\nINTERFACE will be reset to wlan0"
sh "$instpath/"install.sh
