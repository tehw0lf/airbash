#!/usr/bin/env bash
# seed database
sqlite3 .db.sqlite3 "CREATE TABLE hs (id INTEGER PRIMARY KEY NOT NULL, lat VARCHAR(12), lon VARCHAR(12), bssid VARCHAR(17) UNIQUE, essid VARCHAR(255), psk VARCHAR(64), prcsd INT(1) DEFAULT NULL)"