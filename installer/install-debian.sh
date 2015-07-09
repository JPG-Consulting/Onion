#!/bin/bash

# Debian installer v.01

# First of all, we check if the user is root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root"
    exit 1
fi

# Check wget
if [ ! -e '/usr/bin/wget' ]; then
    apt-get -y install wget
    if [ $? -ne 0 ]; then
        echo "Error: can't install wget"
        exit 1
    fi
fi

# ProFTPd
apt-get --yes install proftpd-basic proftpd-mod-sql



