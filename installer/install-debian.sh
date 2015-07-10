#!/bin/bash

# Debian installer v.01

#----------------------------------------------------------#
#                  Variables&Functions                     #
#----------------------------------------------------------#
RGITHOST='https://raw.githubusercontent.com/JPG-Consulting/Onion/'
GITVERSION='test';

COMPANY_COUNTRY_CODE='ES'
COMPANY_STATE_OR_PROVINCE='Vizcaya'
COMPANY_LOCALITY=''
COMPANY_NAME='JPG-Consulting'
COMPANY_CERT_OU_NAME=''
COMPANY_CERT_COMMON_NAME=$(hostname --fqdn)
COMPANY_EMAIL=''

function new_password_prompt()
{
    local  __resultvar=$1
    local passwd=''
    local passwd2=''
    
    while true; do
        read -e -p "New password: " -s passwd
        read -e -p "Retype new password: " -s passwd2
        [ "$passwd" = "$passwd2" ] && break
        echo "Passwords do not match. Please try again."
    done
    
    if [[ "$__resultvar" ]]; then
        eval $__resultvar="'$passwd'"
    else
        echo "$passwd"
    fi
}

function install_missing_packages()
{
        local all_packages=("$@")
        local packages=""

        for i in "${all_packages[@]}"; do
                if [ $(dpkg-query -W -f='${Status}' $i | grep -c "install ok installed") -eq 0$
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

function is_installed()
{
    local INSTALLED_STATUS="ii "
    local DPKGQUERY=$(dpkg-query -W -f='${db:Status-Abbrev}' $1 2>/dev/null)
    if [[ $DPKGQUERY == $INSTALLED_STATUS ]]
    then
        return 1
    else
        return 0
    fi
}

# Function: prompt_yn
# -------------------
# Prompts for a y/n input. Returns 0 if the input is y, 1 if n.
# $1 is prompt
# $2 is default (Y|N)
function prompt_yn()
{
    local response=''
    local prompt="$1"
    local default="$( echo "$2" | tr '[A-Z]' '[a-z]' )"
    
    if [ "$default" = 'y' ]; then
        prompt="$prompt [Y/n] "
    else
        prompt="$prompt [y/N] "
    fi
    
    echo -n "$prompt"
    
    while true; do
        read -s -n 1 response
        if [ -z "$response" ]; then
            response="$default"
        fi
        
        response="$( echo $response | tr '[A-Z]' '[a-z]' )"
        if [ "$response" = 'y' ]; then
            echo "y"
            return 0
        elif [ "$response" = 'n' ]; then
            echo "n"
            return 1
        fi
    done
}

# First of all, we check if the user is root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root"
    exit 1
fi

# Ask for some company information
while true; do
    read -e -p "Country Name (2 letter code) [$COMPANY_COUNTRY_CODE]: " input_var
    if [ -n "$input_var" ]; then
        COMPANY_COUNTRY_CODE="$input_var"
    fi

    read -e -p "State or Province Name (full name) [$COMPANY_STATE_OR_PROVINCE]: " input_var
    if [ -n "$input_var" ]; then
        COMPANY_STATE_OR_PROVINCE="$input_var"
    fi
    
    read -e -p "Locality Name (eg, city) [$COMPANY_LOCALITY]: " input_var
    if [ -n "$input_var" ]; then
        COMPANY_LOCALITY="$input_var"
    fi
    
    read -e -p "Organization Name (eg, company) [$COMPANY_NAME]: " input_var
    if [ -n "$input_var" ]; then
        COMPANY_NAME="$input_var"
    fi
    
    read -e -p "Organizational Unit Name (eg, section) [$COMPANY_CERT_OU_NAME]: " input_var
    if [ -n "$input_var" ]; then
        COMPANY_CERT_OU_NAME="$input_var"
    fi
    
    read -e -p "Common Name (eg, YOUR name) [$COMPANY_CERT_COMMON_NAME]: " input_var
    if [ -n "$input_var" ]; then
        COMPANY_CERT_COMMON_NAME="$input_var"
    fi
    
    read -e -p "Email Address [$COMPANY_EMAIL]: " input_var
    if [ -n "$input_var" ]; then
        COMPANY_EMAIL="$input_var"
    fi
    
    if prompt_yn "Is the information correct?" "Y"; then
        break
    fi
done

export DEBIAN_FRONTEND=noninteractive

# Check wget
if [ ! -e '/usr/bin/wget' ]; then
    apt-get --yes -qq install wget
    if [ $? -ne 0 ]; then
        echo "Error: can't install wget"
        exit 1
    fi
fi

#----------------------------------------------------------#
#                   Update the server                      #
#----------------------------------------------------------#
if prompt_yn "Update the server?" "Y"; then
    apt-get --yes -qq update && apt-get --yes -qq upgrade && apt-get --yes -qq dist-upgrade
fi

#----------------------------------------------------------#
#                   Change root password                   #
#----------------------------------------------------------#
if prompt_yn "Do you want to change the root password?" "Y"; then
    passwd root
fi

#----------------------------------------------------------#
#                     Fail2ban Setup                       #
#----------------------------------------------------------#
if [ $(dpkg-query -W -f='${Status}' fail2ban 2>/dev/null | grep -c "ok installed") -eq 0 ]; then
    if prompt_yn "Install fail2ban?" "Y"; then
        apt-get --yes -qq install fail2ban;
        if [ $? -ne 0 ]; then
            echo "Error: can't install fail2ban"
            exit 1
        fi
    fi
fi

#----------------------------------------------------------#
#                      MySQL Setup                         #
#----------------------------------------------------------#
while true; do
    read -e -p "MySQL Password for root: " -s mysql_root_passwd
    read -e -p "MySQL Password for root (again): " -s mysql_root_passwd2
    [ "$mysql_root_passwd" = "$mysql_root_passwd2" ] && break
    echo "Passwords do not match. Please try again."
done

sudo debconf-set-selections <<< 'mysql-server mysql-server/root_password password $mysql_root_passwd'
sudo debconf-set-selections <<< 'mysql-server mysql-server/root_password_again password $mysql_root_passwd'

install_missing_packages mysql-server

# stop mysql server
service mysql stop
# Start mysql without grant tables
mysqld_safe --skip-grant-tables &
# Update root with new password
mysql -e "UPDATE mysql.user SET Password=PASSWORD('$mysql_root_passwd') WHERE User='root'"
# Kill the anonymous users
mysql -e "DROP USER ''@'localhost'"
# Because our hostname varies we'll use some Bash magic here.
mysql -e "DROP USER ''@'$(hostname)'"
# Kill off the demo database
mysql -e "DROP DATABASE test"
# Make our changes take effect
mysql -e "FLUSH PRIVILEGES"
# Any subsequent tries to run queries this way will get access denied because lack of usr/pwd param

# stop mysqld_safe an start the mysql service
service mysql restart

read -e -p "System DataBase name? [psa] : " system_database
if [[ "$system_database" == "" ]]; then
    system_database="psa"
fi

read -e -p "System Database Username? [psa] : " system_user
if [[ "$system_user" == "" ]]; then
    system_user="psa"
fi

while true; do
    read -e -p "System Database User password for $system_user ? : " -s system_passwd
    if [[ "$system_passwd" != "" ]]; then
        break
    fi
done

mysql -u root -p $system_passwd -e "CREATE DATABASE IF NOT EXISTS $system_database"
mysql -u root -p $system_passwd -e "GRANT SELECT, INSERT, UPDATE, DELETE ON $system_database.* TO '$system_user'@'localhost' IDENTIFIED BY '$system_passwd'"
mysql -u root -p $system_passwd -e "FLUSH PRIVILEGES"

# Download and import MySQL data structure
wget $RGITHOST/$GITVERSION/installer/system/tmp/mysql.create.sql -O /tmp/mysql.create.sql
mysql -u $system_user -p $system_passwd -h localhost $system_database < /tmp/mysql.create.sql
rm -f /tmp/mysql.create.sql

#----------------------------------------------------------#
#                      Apache Setup                        #
#----------------------------------------------------------#
install_missing_packages apache2 apache2-suexec-custom libapache2-mod-fcgid openssl ssl-cert

# Create directory for vhosts
if [ ! -d /var/www/vhosts/default/htdocs ]; then
    mkdir -p /var/www/vhosts/default/htdocs
fi

if [ ! -f /var/www/vhosts/default/htdocs/index.html ]; then
    echo "<html><body><h1>It works!</h1>" > /var/www/vhosts/default/htdocs/index.html
    echo "<p>This is the default web page for this server.</p>" >> /var/www/vhosts/default/htdocs/index.html
    echo "<p>The web server software is running but no content has been added, yet.</p>" >> /var/www/vhosts/default/htdocs/index.html
    echo "</body></html>" >> /var/www/vhosts/default/htdocs/index.html
fi

if [ ! -d /var/www/vhosts/default/htsdocs ]; then
    mkdir -p /var/www/vhosts/default/htsdocs
fi

if [ ! -f /var/www/vhosts/default/htsdocs/index.html ]; then
    echo "<html><body><h1>It works!</h1>" > /var/www/vhosts/default/htsdocs/index.html
    echo "<p>This is the default web page for this server.</p>" >> /var/www/vhosts/default/htsdocs/index.html
    echo "<p>The web server software is running but no content has been added, yet.</p>" >> /var/www/vhosts/default/htsdocs/index.html
    echo "</body></html>" >> /var/www/vhosts/default/htsdocs/index.html
fi

if [ ! -d /var/www/vhosts/onion/htdocs ]; then
    mkdir -p /var/www/vhosts/onion/htdocs
fi

if [ ! -d /var/www/vhosts/onion/htsdocs ]; then
    mkdir -p /var/www/vhosts/onion/htdocs
fi

echo "/var/www/vhosts/onion/htsdocs" > /etc/apache2/suexec/www-data
echo "public_html/cgi-bin" >> /etc/apache2/suexec/www-data


wget $RGITHOST/$GITVERSION/installer/system/etc/apache2/sites-available/default -O /etc/apache2/sites-available/default
wget $RGITHOST/$GITVERSION/installer/system/etc/apache2/sites-available/default-ssl -O /etc/apache2/sites-available/default-ssl
wget $RGITHOST/$GITVERSION/installer/system/etc/apache2/sites-enabled/000-default -O /etc/apache2/sites-enabled/000-default

wget $RGITHOST/$GITVERSION/installer/system/etc/apache2/sites-available/onion-ssl -O /etc/apache2/sites-available/onion-ssl
wget $RGITHOST/$GITVERSION/installer/system/etc/apache2/sites-enabled/000-onion -O /etc/apache2/sites-enabled/000-onion

#----------------------------------------------------------#
#                       PHP5 Setup                         #
#----------------------------------------------------------#
install_missing_packages php5 libapache2-mod-php5 php5-cli php5-common php5-cgi php5-mysql php5-curl php5-gd php5-mcrypt php5-memcache php5-memcached php5-intl


#----------------------------------------------------------#
#                    PHPMyAdmin Setup                      #
#----------------------------------------------------------#
debconf-set-selections <<< 'phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2'
debconf-set-selections <<< 'phpmyadmin phpmyadmin/dbconfig-install boolean true'
debconf-set-selections <<< 'phpmyadmin phpmyadmin/app-password-confirm password $mysql_root_passwd'
debconf-set-selections <<< 'phpmyadmin phpmyadmin/mysql/admin-pass password $mysql_root_passwd'
debconf-set-selections <<< 'phpmyadmin phpmyadmin/mysql/app-pass password $mysql_root_passwd'

install_missing_packages phpmyadmin

if [ -f /etc/apache2/conf.d/phpmyadmin.conf ]; then
    rm -f /etc/apache2/conf.d/phpmyadmin.conf ]
fi 

wget $RGITHOST/$GITVERSION/installer/system/etc/apache2/sites-available/phpmyadmin -O /etc/apache2/sites-available/phpmyadmin
wget $RGITHOST/$GITVERSION/installer/system/etc/apache2/sites-enabled/phpmyadmin -O /etc/apache2/sites-enabled/phpmyadmin

# Restart apache service
service apache2 restart

#----------------------------------------------------------#
#                     Postfix Setup                        #
#----------------------------------------------------------#
debconf-set-selections <<< "postfix	postfix/main_mailer_type select Internet Site";
debconf-set-selections <<< "postfix postfix/mailname string $(hostname)";

install_missing_packages postfix postfix-mysql

# Backups
if [ ! -f /etc/postfix/main.cf.orig ]; then
    cp /etc/postfix/main.cf /etc/postfix/main.cf.orig
fi

wget $RGITHOST/$GITVERSION/installer/system/etc/postfix/main.cf -O /etc/postfix/main.cf
sed -i "s/#myhostname =/myhostname = $(hostname)" /etc/postfix/main.cf

# Create mysql config files
if [ ! -d /etc/postfix/mysql ]; then
    mkdir /etc/postfix/mysql
fi

echo "user = $system_user" > /etc/postfix/mysql/virtual-mailbox-domains.cf
echo "password = $system_passwd" >> /etc/postfix/mysql/virtual-mailbox-domains.cf
echo "hosts = 127.0.0.1" >> /etc/postfix/mysql/virtual-mailbox-domains.cf
echo "dbname = $system_database" >> /etc/postfix/mysql/virtual-mailbox-domains.cf
echo "query = SELECT 1 FROM domains WHERE name='%s' AND active=1" >> /etc/postfix/mysql/virtual-mailbox-domains.cf

echo "user = $system_user" > /etc/postfix/mysql/virtual-mailbox-maps.cf
echo "password = $system_passwd" >> /etc/postfix/mysql/virtual-mailbox-maps.cf
echo "hosts = 127.0.0.1" >> /etc/postfix/mysql/virtual-mailbox-maps.cf
echo "dbname = $system_database" >> /etc/postfix/mysql/virtual-mailbox-maps.cf
echo "query = SELECT 1 FROM mail INNER JOIN domains ON mail.domain_id=domains.id WHERE mail.mail_name='%u' AND domains.name='%d'" >> /etc/postfix/mysql/virtual-mailbox-maps.cf

echo "user = $system_user" > /etc/postfix/mysql/virtual-alias-maps.cf
echo "password = $system_passwd" >> /etc/postfix/mysql/virtual-alias-maps.cf
echo "hosts = 127.0.0.1" >> /etc/postfix/mysql/virtual-alias-maps.cf
echo "dbname = $system_database" >> /etc/postfix/mysql/virtual-alias-maps.cf
echo "query = SELECT CONCAT(mail_aliases.alias, '@', domains.name) FROM mail_aliases INNER JOIN mail ON mail_aliases.mail_id = mail.id INNER JOIN domains ON mail.domain_id = domains.id WHERE mail_aliases.alias = '%u' AND domains.name = '%d'" >> /etc/postfix/mysql/virtual-alias-maps.cf

#----------------------------------------------------------#
#                     Dovecot Setup                        #
#----------------------------------------------------------#
install_missing_packages dovecot-imapd dovecot-pop3d dovecot-mysql dovecot-lmtpd

# Backups
if [ ! -f /etc/dovecot/dovecot.conf.orig ]; then
    cp /etc/dovecot/dovecot.conf /etc/dovecot/dovecot.conf.orig
fi
if [ ! -f /etc/dovecot/conf.d/10-mail.conf.orig ]; then
    cp /etc/dovecot/conf.d/10-mail.conf /etc/dovecot/conf.d/10-mail.conf.orig
fi
if [ ! -f /etc/dovecot/conf.d/10-auth.conf.orig ]; then
    cp /etc/dovecot/conf.d/10-auth.conf /etc/dovecot/conf.d/10-auth.conf.orig
fi
if [ ! -f /etc/dovecot/dovecot-sql.conf.ext.orig ]; then
    cp /etc/dovecot/dovecot-sql.conf.ext /etc/dovecot/dovecot-sql.conf.ext.orig
fi
if [ ! -f /etc/dovecot/conf.d/10-master.conf.orig ]; then
    cp /etc/dovecot/conf.d/10-master.conf /etc/dovecot/conf.d/10-master.conf.orig
fi
if [ ! -f /etc/dovecot/conf.d/10-ssl.conf.orig ]; then
    cp /etc/dovecot/conf.d/10-ssl.conf /etc/dovecot/conf.d/10-ssl.conf.orig
fi

wget $RGITHOST/$GITVERSION/installer/system/etc/dovecot/dovecot.conf -O /etc/dovecot/dovecot.conf
wget $RGITHOST/$GITVERSION/installer/system/etc/dovecot/dovecot-sql.conf.ext -O /etc/dovecot/dovecot-sql.conf.ext
wget $RGITHOST/$GITVERSION/installer/system/etc/dovecot/conf.d/10-auth.conf -O /etc/dovecot/conf.d/10-auth.conf
wget $RGITHOST/$GITVERSION/installer/system/etc/dovecot/conf.d/10-mail.conf -O /etc/dovecot/conf.d/10-mail.conf
wget $RGITHOST/$GITVERSION/installer/system/etc/dovecot/conf.d/10-master.conf -O /etc/dovecot/conf.d/10-master.conf
wget $RGITHOST/$GITVERSION/installer/system/etc/dovecot/conf.d/10-ssl.conf -O /etc/dovecot/conf.d/10-ssl.conf

# modify /etc/dovecot/dovecot-sql.conf.ext
sed -i "s/#connect =/connect = host=127.0.0.1 dbname=$system_database user=$system_user password=$system_passwd/" /etc/dovecot/dovecot-sql.conf.ext

# Certificate (TODO: Auto the fields of the certificate )
if [ ! -f /etc/ssl/certs/dovecot.pem ]; then
    openssl req -new -x509 -days 3650 -nodes -out /etc/ssl/certs/dovecot.pem -keyout /etc/ssl/private/dovecot.pem
    chmod o= /etc/ssl/private/dovecot.pem
elif [ ! -f /etc/ssl/private/dovecot.pem ]; then
    openssl req -new -x509 -days 3650 -nodes -out /etc/ssl/certs/dovecot.pem -keyout /etc/ssl/private/dovecot.pem
    chmod o= /etc/ssl/private/dovecot.pem
fi

# Set file permissions
groupadd -g 5000 vmail
useradd -g vmail -u 5000 vmail -d /var/mail

mkdir -p /var/mail/vhosts/
chown -R vmail:vmail /var/mail

chown -R vmail:dovecot /etc/dovecot
chmod -R o-rwx /etc/dovecot

# Restart dovecot service
service dovecot restart

#----------------------------------------------------------#
#                     ProFTPd Setup                        #
#----------------------------------------------------------#
