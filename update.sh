#!/usr/bin/env bash
# installation path
instpath=$(realpath .)

# get platform - there is no git on android
if [ ! -d "/system" ]; then
  tmp="/tmp/airbash"

  # download latest version
  rm -rf "$tmp/"
  git clone https://github.com/tehw0lf/airbash "$tmp/"
  cp -R "$tmp/." "$instpath/" 2>/dev/null # suppress git overwrite errors
  echo "installing update... INTERFACE will be reset to wlan0"
  sh "$instpath/"install.sh
fi
