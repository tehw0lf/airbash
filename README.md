# airba.sh

Airbash is a POSIX-compliant, fully automated WPA PSK handshake capture script aimed at penetration testing.
It is compatible with Bash and Android Shell (tested on Kali Linux and Cyanogenmod 10.2) and uses [aircrack-ng](https://aircrack-ng.org) to scan for clients that are currently connected to access points (AP).
Those clients are then deauthenticated in order to capture the handshake when attempting to reconnect to the AP.
Verification of a captured handshake is done using aircrack-ng. If one or more handshakes are captured, they are entered into an SQLite3 database, along with the time of capture and current GPS data (if properly configured).

After capture, the database can be tested for vulnerable router models using `crackdefault.sh`.
It will search for entries that match the implemented modules, which currently include algorithms to compute default keys for
Speedport 500-700 series, Thomson/SpeedTouch and UPC 7 digits (UPC1234567) routers.

## Requirements

WiFi interface in monitor mode
aircrack-ng
SQLite3
openssl for compilation of modules (optional)
[wlanhc2hcx](https://github.com/ZerBea/hcxtools/blob/master/wlanhc2hcx.c) from [hcxtools](https://github.com/ZerBea/hcxtools)

In order to log GPS coordinates of handshakes, configure your coordinate logging software to log to .loc/*.txt (the filename can be chosen as desired). Airbash will always use the output of `cat "$path$loc"*.txt 2>/dev/null | awk 'NR==0; END{print}'`, which equals to reading all .txt files in .loc/ and picking the second line. The reason for this way of implementation is the functionality of [GPSLogger](https://play.google.com/store/apps/details?id=com.mendhak.gpslogger&hl=en), which was used on the development device.

## Calculating default keys

After capturing a new handshake, the database can be queried for vulnerable router models. If a module applies,
the default keys for this router series are calculated and used as input for aircrack-ng to try and recover
the passphrase.

## Compiling Modules

The modules for calculating [Thomson/SpeedTouch](https://packetstormsecurity.com/files/84788/STKeys-Thomson-WPA-Key-Recovery-Tool-1.0.html) and [UPC1234567](https://haxx.in/) (7 random digits) default keys are included in `src/`

Credits for the code go to the authors Kevin Devine and <peter@haxx.in>.

```bash
On Linux:
gcc -fomit-frame-pointer -O3 -funroll-all-loops -o modules/st modules/stkeys.c -lcrypto
gcc -O2 -o modules/upckeys modules/upc_keys.c -lcrypto
```

If on Android, you may need to copy the binaries to /system/xbin/ or to another directory where binary execution is allowed.

## Usage

Running `install.sh` will create the database, prepare the folder structure and create shortlinks to both scripts which can be moved to a directory that is on $PATH to allow execution from any location.

After installation, you may need to manually adjust `INTERFACE` on line 46 in `airba.sh`. This will later be determined automatically, but for now the default is set to `wlan0`, to allow out of the box compatibility with [bcmon](https://code.google.com/archive/p/bcmon/) on Android.

`./airba.sh` starts the script, automatically scanning and attacking targets that are not found in the database.
`./crackdefault.sh` attempts to break known default key algorithms.

To view the database contents, run `sqlite3 .db.sqlite3 "SELECT * FROM hs"` in the main directory.

## Update (Linux only ... for now):

Airbash can be updated by executing `update.sh`. This will clone the master branch into /tmp/ and overwrite the local files.

## Output

`_n`: number of access points found

`__c/m`: represents client number and maximum number of clients found, respectively

`-`: access point is blacklisted

`x`: access point already in database

`?`: access point out of range (not visible to airodump anymore)

## The Database

The database contains a table called `hs` with seven columns.

`id`: incrementing counter of table entries

`lat` and `lon`: GPS coordinates of the handshake (if available)

`bssid`: MAC address of the access point

`essid`: Name identifier

`psk`: WPA Passphrase, if known

`prcsd`: Flag that gets set by crackdefault.sh to prevent duplicate calculation of default keys if a custom passphrase was used.

Currently, the SQLite3 database is not password-protected.

## Contributing

Contributions are very welcome, especially additional modules to be able to crack more default keys. A template module is [included](https://github.com/tehw0lf/airbash/blob/master/modules/template.sh) in modules/. `crackdefault.sh` contains a template elif statement to include the new module.

If you want to contribute, make sure your code is licensed under the MIT License (like this project).
When contributing shell code, please make sure it is POSIX-compliant.
Other than that, just open up an issue briefly describing the changes and create a pull request!
