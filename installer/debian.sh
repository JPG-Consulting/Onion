#!/bin/bash

GITHUB_RAW_URL="https://raw.githubusercontent.com/JPG-Consulting"
GITHUB_REPOSITORY="Onion"
GITHUB_REPOSITORY_BRANCH="test"

#----------------------------------------------------------#
#                General purpose functions                 #
#----------------------------------------------------------#

function install_required_packages()
{
    local all_packages=("$@")
    local packages=""

    for i in "${all_packages[@]}"; do
        if [ $(dpkg-query -W -f='${Status}' $i | grep -c "install ok installed") -eq 0 ]; then
            packages="$packages $i"
        fi
    done

    if [ -n "$packages" ]; then
        apt-get --yes -qq install $packages
        if [ $? -ne 0 ]; then
            echo "Error: can't install $packages"
            exit 1
        fi
    fi
}

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
# Kill the anonymous users
mysql -u root -e "DROP USER ''@'localhost';" mysql
# Because our hostname varies we'll use some Bash magic here.
mysql -u root -e "DROP USER ''@'$(hostname)';" mysql
# Kill off the demo database
mysql -u root -e "DROP DATABASE test;" mysql
mysql -u root -e "FLUSH PRIVILEGES;" mysql

service mysql restart
sleep 3

mysql -u root -p$MYSQL_ROOT_PASSWORD -e "CREATE DATABASE IF NOT EXISTS $MYSQL_DATABASE;"
mysql -u root -p$MYSQL_ROOT_PASSWORD -e "GRANT ALL ON *.* TO '$MYSQL_USER'@'localhost' IDENTIFIED BY '$MYSQL_USER_PASSWORD';"
mysql -u root -p$MYSQL_ROOT_PASSWORD -e "FLUSH PRIVILEGES;"

# Get the database structure backup
if [ -f /tmp/mysql-structure.sql ]; then
    rm -f /tmp/mysql-structure.sql
fi

wget $GITHUB_RAW_URL/$GITHUB_REPOSITORY/$GITHUB_REPOSITORY_BRANCH/installer/database/mysql-structure.sql -O /tmp/mysql-structure.sql

mysql -u root -p$MYSQL_ROOT_PASSWORD $MYSQL_DATABASE < /tmp/mysql-structure.sql
if [ $? -ne 0 ]; then
    rm -f /tmp/mysql-structure.sql
    echo ""
    echo "Error: Unable to import database structure."
    echo ""
    exit 1
fi

rm -f /tmp/mysql-structure.sql

#----------------------------------------------------------#
#                      Apache 2 Setup                      #
#----------------------------------------------------------#
echo "Setting Apache 2 server..."

install_required_packages apache2 apache2-suexec-custom libapache2-mod-fcgid openssl ssl-cert

# Create directory for vhosts
if [ ! -d /var/www/vhosts ]; then
    mkdir -p /var/www/vhosts
    chmod 0755 /var/www/vhosts
fi

# Create the default vhost directory and index file
if [ ! -d /var/www/vhosts/default ]; then
    mkdir -p /var/www/vhosts/default
    chmod 0755 /var/www/vhosts/default
fi

if [ ! -f /var/www/vhosts/default/index.html ]; then
    echo "<html><body><h1>It works!</h1>" > /var/www/vhosts/default/index.html
    echo "<p>This is the default web page for this server.</p>" >> /var/www/vhosts/default/index.html
    echo "<p>The web server software is running but no content has been added, yet.</p>" >> /var/www/vhosts/default/index.html
    echo "</body></html>" >> /var/www/vhosts/default/index.html
    chmod 0644 /var/www/vhosts/default/index.html
fi

if [ ! -d /var/www/vhosts/default/cgi-bin ]; then
    mkdir -p /var/www/vhosts/default/cgi-bin
    chmod 0755 /var/www/vhosts/default/cgi-bin
fi

# Make changes to the default site
if [ -f /etc/apache2/sites-available/default ]; then
    sed -i -e "s/^\s*DocumentRoot \/var\/www\s*$/DocumentRoot \/var\/www\/vhosts\/default/" /etc/apache2/sites-available/default
    sed -i -e "s/^\s*<Directory \/var\/www\/>\s*$/<Directory \/var\/www\/vhosts\/default\/>/" /etc/apache2/sites-available/default
fi

if [ -f /etc/apache2/sites-enabled/000-default ]; then
    sed -i -e "s/^\s*DocumentRoot \/var\/www\s*$/DocumentRoot \/var\/www\/vhosts\/default/" /etc/apache2/sites-enabled/000-default
    sed -i -e "s/^\s*<Directory \/var\/www\/>\s*$/<Directory \/var\/www\/vhosts\/default\/>/" /etc/apache2/sites-enabled/000-default
fi

# Enable SSL
a2enmod ssl

# NOTE: Do not restart apache2 yet!
#       We should install PHP and PHPAdmin before that.

#----------------------------------------------------------#
#                        PHP Setup                         #
#----------------------------------------------------------#
echo "Setting PHP5..."

install_required_packages php5 libapache2-mod-php5 php5-cli php5-common php5-cgi php5-mysql php5-curl php5-gd php5-mcrypt php5-memcache php5-memcached php5-intl

#----------------------------------------------------------#
#                     PHPMyAdmin Setup                     #
#----------------------------------------------------------#
if [ $(dpkg-query -W -f='${Status}' phpmyadmin | grep -c "install ok installed") -eq 0 ]; then
    debconf-set-selections <<< "phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2"
    debconf-set-selections <<< "phpmyadmin phpmyadmin/dbconfig-install boolean true"
    debconf-set-selections <<< "phpmyadmin phpmyadmin/app-password-confirm password $MYSQL_ROOT_PASSWORD"
    debconf-set-selections <<< "phpmyadmin phpmyadmin/mysql/admin-pass password $MYSQL_ROOT_PASSWORD"
    debconf-set-selections <<< "phpmyadmin phpmyadmin/mysql/app-pass password $MYSQL_ROOT_PASSWORD"

    apt-get --yes -qq install phpmyadmin
fi

#----------------------------------------------------------#
#                     Onion Vhost Setup                    #
#----------------------------------------------------------#
# Create the default vhost directory and index file
if [ ! -d /var/www/vhosts/onion ]; then
    mkdir -p /var/www/vhosts/onion
    chmod 0755 /var/www/vhosts/onion
fi

if [ ! -f /var/www/vhosts/onion/index.html ]; then
    echo "<html><body><h1>It works!</h1>" > /var/www/vhosts/onion/index.html
    echo "<p>This is the default web page for this server.</p>" >> /var/www/vhosts/onion/index.html
    echo "<p>The web server software is running but no content has been added, yet.</p>" >> /var/www/vhosts/onion/index.html
    echo "</body></html>" >> /var/www/vhosts/onion/index.html
    chmod 0644 /var/www/vhosts/onion/index.html
fi

if [ ! -f /etc/apache2/ports.conf.orig ]; then
    mv /etc/apache2/ports.conf /etc/apache2/ports.conf.orig
else
    rm -f /etc/apache2/ports.conf
fi

wget $GITHUB_RAW_URL/$GITHUB_REPOSITORY/$GITHUB_REPOSITORY_BRANCH/installer/files/etc/apache2/ports.conf -O /etc/apache2/ports.conf
chmod 0644 /etc/apache2/ports.conf

wget $GITHUB_RAW_URL/$GITHUB_REPOSITORY/$GITHUB_REPOSITORY_BRANCH/installer/files/etc/apache2/sites-available/onion -O /etc/apache2/sites-available/onion
chmod 0777 /etc/apache2/sites-available/onion

a2ensite onion

#----------------------------------------------
# restart apache
service apache2 restart
