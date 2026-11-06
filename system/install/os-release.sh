#!/bin/sh
# Writes Memora's os-release (re-run by a pacman hook when 'filesystem' updates).
v="$(cat /usr/share/memora/version)"
rm -f /etc/os-release
cat > /etc/os-release <<EOR
NAME="Memora"
PRETTY_NAME="Memora $v"
ID=memora
ID_LIKE=arch
BUILD_ID=rolling
VERSION_ID=$v
ANSI_COLOR="1"
HOME_URL="https://github.com/Mihnea999/memora"
LOGO=memora
EOR
