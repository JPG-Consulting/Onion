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
    read -e -p "Enter MySQL root password: " -s MYSQL_ROOT_PASSWORD
    echo ""
    read -e -p "Retype MySQL root password: " -s password
    echo ""

    [ "$MYSQL_ROOT_PASSWORD" = "$password" ] && break;

    echo ""
    echo "Sorry, passwords do not match. Please try again."
    echo ""
done

MYSQL_DATABASE="psa"
MYSQL_USER="$MYSQL_DATABASE"
MYSQL_USER_PASSWORD="psapassword"

#----------------------------------------------------------#
#                      System update                       #
#----------------------------------------------------------#
echo "Performing server update..."

apt-get --yes -qq update && apt-get --yes -qq upgrade && apt-get --yes -qq dist-upgrade
if [ $? -ne 0 ]; then
    echo ""
    echo "Error: Unable to perform server update."
    echo ""
    exit 1
fi

#----------------------------------------------------------#
#                       MySQL Setup                        #
#----------------------------------------------------------#
echo "Setting MySQL server..."

if [ $(dpkg-query -W -f='${Status}' mysql-server | grep -c "install ok installed") -eq 0 ]; then
    debconf-set-selections <<< "mysql-server mysql-server/root_password password $MYSQL_ROOT_PASSWORD"
    debconf-set-selections <<< "mysql-server mysql-server/root_password_again password $MYSQL_ROOT_PASSWORD"

    apt-get --yes -qq install mysql-server
fi

# Reset the password
service mysql stop
mysqld_safe --skip-grant-tables &
sleep 3
mysql -u root -e "UPDATE user SET Password=PASSWORD('$MYSQL_ROOT_PASSWORD') WHERE user='root';" mysql
mysql -u root -e "FLUSH PRIVILEGES;" mysql

service mysql restart
sleep 3

mysql -u root -p$MYSQL_ROOT_PASSWORD -e "CREATE DATABASE IF NOT EXISTS $MYSQL_DATABASE;"
mysql -u root -e$MYSQL_ROOT_PASSWORD "GRANT ALL ON *.* TO '$MYSQL_USER'@'localhost' IDENTIFIED BY '$MYSQL_USER_PASSWORD';"
mysql -u root -e$MYSQL_ROOT_PASSWORD "FLUSH PRIVILEGES;"
