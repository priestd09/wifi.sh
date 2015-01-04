#! /bin/bash

WPA_CONF=${WPA_CONF-/etc/wpa_supplicant.conf}

isroot () {
  # check that the script is running as root
  # this is required for controlling wifi device.

  if [ $UID -ne 0 ]; then
    echo 'Error: must run as root to access wifi devices' >&2
    exit 1
  fi
}

add () {
  # use wpa_passphrase command to add the new network to wpa_supplicant conf.
  # wpa_passphrase dumps the error message on stdout
  # because they do not understand unix.
  # detect this case and exit with a helpful error message.

  PASS=`wpa_passphrase "$1" "$2"` || {
    echo Error: $PASS 1>&2
    exit 1
  }
  echo "$PASS" >> $WPA_CONF
  exit 0
}

parse () {
  # parse the output of iw scan
  while read LINE;
  do
    LINE=${LINE# *}

    case "$LINE" in
      BSS*)
        if [ x"$BSS" != x ]; then
          printf '%-40s, %5s , %s\n' "$SSID" "$SIGNAL" "$ENC"
          SIGNAL=
          ENC=
        fi
        BSS=${LINE#BSS }
        BSS=${BSS%(*}
      ;;
      SSID*)
        SSID=${LINE#SSID: }
        if [ "$SSID" = "SSID:" ]; then
          SSID=$BSS
        fi
      ;;
      signal*)
        SIGNAL=${LINE#signal: }
        SIGNAL=${SIGNAL% dBm}
      ;;
      *)
        E=${LINE%%:*}
        E="$E"${LINE#*Version: }
        ENC="$ENC$E "
      ;;
    esac
  done
  printf '%-40s, %5s , %s\n' "$SSID" "$SIGNAL" "$ENC"
}

preparse () {
  grep -E '(^BSS)|SSID|signal|WPA|WPS|WEP|RSN'
}

_scanraw () {
  iw dev "$INTERFACE" scan | preparse
}

scanraw () {
  isroot
  get_interface
  _scanraw
  exit 0
}

scan () {
  isroot
  get_interface
  ip link set $INTERFACE up
  echo 'SSID                                    , SIGNAL , SECURITY'

  # to be honest, I can't figure out the correct parameters
  # to sort, but this seems to produce good output.
  _scanraw | parse | sort -k 3
  exit 0
}

parse_interface () {
  while read line;
  do
    iface=${line#*: }
    iface=${iface%%:*}
  done
  echo $iface
}

get_interface () {
  # Grab the most recently added interface with the prefix wl.
  # Your laptop may use a wifi chipset that has poor linux driver support.
  # (this is because of microsoft's consipracy against linux)
  # In this case, you may have more success using a usb wifi dongle.
  # If you are using a wifi dongle this should return the one
  # that you most recently plugged in.

  INTERFACE=${INTERFACE-$(ip -o link | grep '^[0-9]: wl' | parse_interface)}
  echo $INTERFACE
}

interface () {
  get_interface
  exit 0
}

dump () {
  cat $WPA_CONF
  exit 0
}

connect () {
  isroot
  dhcpcd #start dhcpcd if necessary
  get_interface
  # if there are two wpa_supplicants running, things break.
  killall wpa_supplicant
  wpa_supplicant -i $INTERFACE -c $WPA_CONF
  exit $?
}

open () {
  # because iw does not block, we need to start it,
  # and then start polling the status.
  # if the connection drops, reconnect automatically.

  isroot
  dhcpcd #start dhcpcd if necessary
  get_interface

  while true
  do
    # If the interface was down, put it back up.
    # (for example, if you had turned wifi off with a hardware switch)
    ip link set $INTERFACE up

    # ensure we are disconnected.
    # (otherwise, may get "operation already in progress")
    iw dev "$INTERFACE" disconnect

    # connect to an open wifi network.
    # 1: Unspecified failure probably means that the name you
    #    entered was not an open wifi network.

    iw dev "$INTERFACE" connect -w "$1"
    STATUS=

    # poll the status to check if we are still connected.
    # if we become disconnected, come back into the main loop and reconnect.

    while [ "$STATUS" != 'Not connected.' ]
    do
      sleep 1
      STATUS=$(iw dev "$INTERFACE" link)
      echo "$STATUS"
    done
  done
  exit $?
}

disconnect () {
  get_interface
  killall wpa_supplicant
  iw dev "$INTERFACE" disconnect
  exit 0
}

version () {
  v=$(grep version $(dirname $(realpath "$0"))/package.json)
  v=${v%'"'*}
  v=${v##*'"'}
  echo $v
  exit 0
}

[ "$1" = "-v" ] && version

if [ "$0" = "$BASH_SOURCE" ]; then

  "$@"
  echo 'USAGE scan|connect|add {network} {pass}|open {network}|dump|interface|version' >&2

fi
