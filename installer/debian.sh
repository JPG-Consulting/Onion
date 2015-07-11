#!/bin/bash

#----------------------------------------------------------#
#                General purpose functions                 #
#----------------------------------------------------------#

function prompt_yesno()
{
    local prompt=$1
    local default=$2
    local answer='';

    case $default in
        'y') prompt="$prompt [Y/n] ";;
        'n') prompt="$prompt [y/N] ";;
        *) prompt="$prompt [y/n] ";;
    esac

    echo -n "$prompt"

    while [[ $answer == "" ]]
    do
        read -s -n 1 answer
        if [ -z "$response" ]; then
                answer="$default"
        fi
        answer="$( echo $answer | tr '[A-Z]' '[a-z]' )"

        if [ "$answer" == "y" ]; then
            echo "y"
            return 0
        elif [ "$answer" == "n" ]; then
            echo "n"
            return 1
        fi
    done
}

#----------------------------------------------------------#
#                     Main  Entry Point                    #
#----------------------------------------------------------#

echo ""
echo "================================================="
echo "= Starting Auto Installer for Onion on Debian 7 ="
echo "================================================="
echo ""

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root."
    echo ""
    exit 1
fi

#----------------------------------------------------------#
#                     Global Variables                     #
#----------------------------------------------------------#
while true
do
    read -e -p "Enter MySQL root password: " -s MYSQL_ROOT_PASSWD
    echo ""
    read -e -p "Retype MySQL root password: " -s password
    echo ""

    [ "$MYSQL_ROOT_PASSWD" = "$password" ] && break;

    echo ""
    echo "Sorry, passwords do not match. Please try again."
    echo ""
done

#----------------------------------------------------------#
#                      System update                       #
#----------------------------------------------------------#
echo ""
echo "Performing server update..."
echo ""

apt-get --yes -qq update && apt-get --yes -qq upgrade && apt-get --yes -qq dist-upgrade
