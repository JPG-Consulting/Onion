#!/bin/bash

GITHUB_RAW_URL="https://raw.githubusercontent.com/JPG-Consulting"
GITHUB_REPOSITORY="Onion"
GITHUB_REPOSITORY_BRANCH="test"

INSTALLER_TEMP_PATH='/tmp/onion-installer'

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

if [ ! -d "$INSTALLER_TEMP_PATH" ]; then
    rm -rf $INSTALLER_PATH
fi
mkdir -p $INSTALLER_TEMP_PATH

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

wget $GITHUB_RAW_URL/$GITHUB_REPOSITORY/$GITHUB_REPOSITORY_BRANCH/installer/database/mysql-structure.sql -O $INSTALLER_TEMP_PATH/mysql-structure.sql

mysql -u root -p$MYSQL_ROOT_PASSWORD $MYSQL_DATABASE < $INSTALLER_TEMP_PATH/mysql-structure.sql
if [ $? -ne 0 ]; then
    echo ""
    echo "Error: Unable to import database structure."
    echo ""
    exit 1
fi

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

# PHP 5.5
grep_output="$(grep '# PHP 5.5' /etc/apt/sources.list)"
if [ -z "$grep_output" ]; then
    echo "" >> /etc/apt/sources.list
    echo "# PHP 5.5 " >> /etc/apt/sources.list
    echo "deb http://packages.dotdeb.org wheezy-php55 all" >> /etc/apt/sources.list
    echo "deb-src http://packages.dotdeb.org wheezy-php55 all" >> /etc/apt/sources.list
fi

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

# Remove the default phpmyadmin config
if [ -f /etc/apache2/conf.d/phpmyadmin.conf ]; then
    rm -f /etc/apache2/conf.d/phpmyadmin.conf
fi

#----------------------------------------------------------#
#                     Onion Vhost Setup                    #
#----------------------------------------------------------#
# Create the default vhost directory and index file
if [ ! -d /var/www/vhosts/onion/public_html ]; then
    mkdir -p /var/www/vhosts/onion/public_html
    chmod 0755 /var/www/vhosts/onion
    chmod 0755 /var/www/vhosts/onion/public_html
fi

if [ ! -f /var/www/vhosts/onion/public_html/index.html ]; then
    echo "<html><body><h1>It works!</h1>" > /var/www/vhosts/onion/public_html/index.html
    echo "<p>This is the default web page for this server.</p>" >> /var/www/vhosts/onion/public_html/index.html
    echo "<p>The web server software is running but no content has been added, yet.</p>" >> /var/www/vhosts/onion/public_html/index.html
    echo "</body></html>" >> /var/www/vhosts/onion/public_html/index.html
    chmod 0644 /var/www/vhosts/onion/public_html/index.html
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

#----------------------------------------------------------#
#                      Dovecot setup                       #
#----------------------------------------------------------#
echo "Setting Dovecot..."

install_required_packages dovecot-imapd dovecot-pop3d dovecot-mysql dovecot-lmtpd

# Backups
if [ ! -f /etc/dovecot/dovecot.conf.orig ]; then
    cp /etc/dovecot/dovecot.conf /etc/dovecot/dovecot.conf.orig
fi
if [ ! -f /etc/dovecot/conf.d/auth-sql.conf.ext.orig ]; then
    cp /etc/dovecot/conf.d/auth-sql.conf.ext /etc/dovecot/conf.d/auth-sql.conf.ext.orig
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

# Download replacement configuration files
if [ ! -d "$INSTALLER_TEMP_PATH/etc/dovecot/conf.d" ]; then
    mkdir -p $INSTALLER_TEMP_PATH/etc/dovecot/conf.d
fi

wget $GITHUB_RAW_URL/$GITHUB_REPOSITORY/$GITHUB_REPOSITORY_BRANCH/installer/files/etc/dovecot/dovecot.conf -O $INSTALLER_TEMP_PATH/etc/dovecot/dovecot.conf
wget $GITHUB_RAW_URL/$GITHUB_REPOSITORY/$GITHUB_REPOSITORY_BRANCH/installer/files/etc/dovecot/dovecot-sql.conf.ext -O $INSTALLER_TEMP_PATH/etc/dovecot/dovecot-sql.conf.ext
wget $GITHUB_RAW_URL/$GITHUB_REPOSITORY/$GITHUB_REPOSITORY_BRANCH/installer/files/etc/dovecot/conf.d/auth-sql.conf.ext -O $INSTALLER_TEMP_PATH/etc/dovecot/conf.d/auth-sql.conf.ext
wget $GITHUB_RAW_URL/$GITHUB_REPOSITORY/$GITHUB_REPOSITORY_BRANCH/installer/files/etc/dovecot/conf.d/10-auth.conf -O $INSTALLER_TEMP_PATH/etc/dovecot/conf.d/10-auth.conf
wget $GITHUB_RAW_URL/$GITHUB_REPOSITORY/$GITHUB_REPOSITORY_BRANCH/installer/files/etc/dovecot/conf.d/10-mail.conf -O $INSTALLER_TEMP_PATH/etc/dovecot/conf.d/10-mail.conf
wget $GITHUB_RAW_URL/$GITHUB_REPOSITORY/$GITHUB_REPOSITORY_BRANCH/installer/files/etc/dovecot/conf.d/10-master.conf -O $INSTALLER_TEMP_PATH/etc/dovecot/conf.d/10-master.conf
wget $GITHUB_RAW_URL/$GITHUB_REPOSITORY/$GITHUB_REPOSITORY_BRANCH/installer/files/etc/dovecot/conf.d/10-ssl.conf -O $INSTALLER_TEMP_PATH/etc/dovecot/conf.d/10-ssl.conf

# modify /etc/dovecot/dovecot-sql.conf.ext
sed -i "s/#connect =/connect = host=127.0.0.1 dbname=$MYSQL_DATABASE user=$MYSQL_USER password=$MYSQL_USER_PASSWORD/" $INSTALLER_TEMP_PATH/etc/dovecot/dovecot-sql.conf.ext

# Replace the files
rm -f /etc/dovecot/dovecot.conf
mv $INSTALLER_TEMP_PATH/etc/dovecot/dovecot.conf /etc/dovecot/dovecot.conf
rm -f /etc/dovecot/dovecot-sql.conf.ext
mv $INSTALLER_TEMP_PATH/etc/dovecot/dovecot-sql.conf.ext /etc/dovecot/dovecot-sql.conf.ext
rm -f /etc/dovecot/conf.d/auth-sql.conf.ext
mv $INSTALLER_TEMP_PATH/etc/dovecot/conf.d/auth-sql.conf.ext /etc/dovecot/conf.d/auth-sql.conf.ext
rm -f /etc/dovecot/conf.d/10-auth.conf
mv $INSTALLER_TEMP_PATH/etc/dovecot/conf.d/10-auth.conf /etc/dovecot/conf.d/10-auth.conf
rm -f /etc/dovecot/conf.d/10-mail.conf
mv $INSTALLER_TEMP_PATH/etc/dovecot/conf.d/10-mail.conf /etc/dovecot/conf.d/10-mail.conf
rm -f /etc/dovecot/conf.d/10-master.conf
mv $INSTALLER_TEMP_PATH/etc/dovecot/conf.d/10-master.conf /etc/dovecot/conf.d/10-master.conf
rm -f /etc/dovecot/conf.d/10-ssl.conf
mv $INSTALLER_TEMP_PATH/etc/dovecot/conf.d/10-ssl.conf /etc/dovecot/conf.d/10-ssl.conf

# Set file permissions
groupadd -g 5000 vmail
useradd -g vmail -u 5000 vmail -d /var/mail

mkdir -p /var/mail/vhosts/
chown -R vmail:vmail /var/mail

chown -R vmail:dovecot /etc/dovecot
chmod -R o-rwx /etc/dovecot

# Restart Dovecot
service dovecot restart

#----------------------------------------------------------#
#                      Postfix setup                       #
#----------------------------------------------------------#
echo "Setting Postfix..."

if [ $(dpkg-query -W -f='${Status}' postfix | grep -c "install ok installed") -eq 0 ]; then
    debconf-set-selections <<< "postfix	postfix/main_mailer_type select Internet Site"
    debconf-set-selections <<< "postfix postfix/mailname string $(hostname)"

    apt-get --yes -qq install postfix
fi

if [ $(dpkg-query -W -f='${Status}' postfix-mysql | grep -c "install ok installed") -eq 0 ]; then
    apt-get --yes -qq install postfix-mysql
fi

# Backups
if [ ! -f /etc/postfix/main.cf.orig ]; then
    cp /etc/postfix/main.cf /etc/postfix/main.cf.orig
fi

postconf -e "myhostname = $(hostname)"
postconf -e "mydestination = localhost"
postconf -e "virtual_transport = lmtp:unix:private/dovecot-lmtp"
postconf -e "virtual_mailbox_domains = mysql:/etc/postfix/mysql/virtual-mailbox-domains.cf"
postconf -e "virtual_mailbox_maps = mysql:/etc/postfix/mysql/virtual-mailbox-maps.cf"
#postconf -e "virtual_alias_maps = mysql:/etc/postfix/mysql/virtual-alias-maps.cf"
postconf -e "virtual_alias_maps = proxy:mysql:/etc/postfix/mysql/virtual-alias-maps-redirect.cf, mysql:/etc/postfix/mysql/virtual-alias-maps.cf"
 
postconf -e "smtpd_tls_cert_file=/etc/ssl/certs/ssl-cert-snakeoil.pem"
postconf -e "smtpd_tls_key_file=/etc/ssl/private/ssl-cert-snakeoil.key"
postconf -e "smtpd_use_tls=yes"
postconf -e "smtpd_tls_auth_only = yes"
postconf -# "smtpd_tls_session_cache_database"
postconf -# "smtp_tls_session_cache_database"

postconf -e "smtpd_sasl_type = dovecot"
postconf -e "smtpd_sasl_path = private/auth"
postconf -e "smtpd_sasl_auth_enable = yes"
postconf -e "smtpd_recipient_restrictions = permit_sasl_authenticated, permit_mynetworks, reject_unauth_destination"
                               
# Create mysql config files
if [ ! -d /etc/postfix/mysql ]; then
    mkdir /etc/postfix/mysql
fi

echo "user = $MYSQL_USER" > /etc/postfix/mysql/virtual-mailbox-domains.cf
echo "password = $MYSQL_USER_PASSWORD" >> /etc/postfix/mysql/virtual-mailbox-domains.cf
echo "hosts = 127.0.0.1" >> /etc/postfix/mysql/virtual-mailbox-domains.cf
echo "dbname = $MYSQL_DATABASE" >> /etc/postfix/mysql/virtual-mailbox-domains.cf
echo "query = SELECT 1 FROM domains WHERE name='%s' AND active=1" >> /etc/postfix/mysql/virtual-mailbox-domains.cf

echo "user = $MYSQL_USER" > /etc/postfix/mysql/virtual-mailbox-maps.cf
echo "password = $MYSQL_USER_PASSWORD" >> /etc/postfix/mysql/virtual-mailbox-maps.cf
echo "hosts = 127.0.0.1" >> /etc/postfix/mysql/virtual-mailbox-maps.cf
echo "dbname = $MYSQL_DATABASE" >> /etc/postfix/mysql/virtual-mailbox-maps.cf
echo "query = SELECT 1 FROM mail INNER JOIN domains ON mail.domain_id=domains.id WHERE mail.mail_name='%u' AND domains.name='%d'" >> /etc/postfix/mysql/virtual-mailbox-maps.cf

echo "user = $MYSQL_USER" > /etc/postfix/mysql/virtual-alias-maps.cf
echo "password = $MYSQL_USER_PASSWORD" >> /etc/postfix/mysql/virtual-alias-maps.cf
echo "hosts = 127.0.0.1" >> /etc/postfix/mysql/virtual-alias-maps.cf
echo "dbname = $MYSQL_DATABASE" >> /etc/postfix/mysql/virtual-alias-maps.cf
echo "query = SELECT CONCAT(mail_aliases.alias, '@', domains.name) FROM mail_aliases INNER JOIN mail ON mail_aliases.mail_id = mail.id INNER JOIN domains ON mail.domain_id = domains.id WHERE mail_aliases.alias = '%u' AND domains.name = '%d'" >> /etc/postfix/mysql/virtual-alias-maps.cf

echo "user = $MYSQL_USER" > /etc/postfix/mysql/virtual-alias-maps-redirect.cf
echo "password = $MYSQL_USER_PASSWORD" >> /etc/postfix/mysql/virtual-alias-maps-redirect.cf
echo "hosts = 127.0.0.1" >> /etc/postfix/mysql/virtual-alias-maps-redirect.cf
echo "dbname = $MYSQL_DATABASE" >> /etc/postfix/mysql/virtual-alias-maps-redirect.cf
echo "query = SELECT mail_redirects.address FROM mail_redirects INNER JOIN mail ON mail_redirects.mail_id = mail.id INNER JOIN domains ON mail.domain_id = domains.id WHERE mail.mail_name = '%u' AND domains.name = '%d'" >> /etc/postfix/mysql/virtual-alias-maps-redirect.cf

# Restart postfix
service postfix restart

#----------------------------------------------------------#
#                     ProFTPd Setup                        #
#----------------------------------------------------------#
if [ $(dpkg-query -W -f='${Status}' proftpd-basic | grep -c "install ok installed") -eq 0 ]; then
    debconf-set-selections <<< "proftpd-basic   shared/proftpd/inetd_or_standalone      select  standalone"
    apt-get --yes -qq install proftpd-basic
fi

if [ $(dpkg-query -W -f='${Status}' proftpd-mod-mysql | grep -c "install ok installed") -eq 0 ]; then
    apt-get --yes -qq install proftpd-mod-mysql
fi

# Backup files
if [ ! -f /etc/proftpd/modules.conf.orig ]; then
    cp /etc/proftpd/modules.conf /etc/proftpd/modules.conf.orig
fi
if [ ! -f /etc/proftpd/proftpd.conf.orig ]; then
    cp /etc/proftpd/proftpd.conf /etc/proftpd/proftpd.conf.orig
fi
if [ ! -f /etc/proftpd/sql.conf.orig ]; then
    cp /etc/proftpd/sql.conf /etc/proftpd/sql.conf.orig
fi

# Download replacement configuration files
if [ ! -d "$INSTALLER_TEMP_PATH/etc/proftpd" ]; then
    mkdir -p $INSTALLER_TEMP_PATH/etc/proftpd
fi

wget $GITHUB_RAW_URL/$GITHUB_REPOSITORY/$GITHUB_REPOSITORY_BRANCH/installer/files/etc/proftpd/proftpd.conf -O $INSTALLER_TEMP_PATH/etc/proftpd/proftpd.conf
wget $GITHUB_RAW_URL/$GITHUB_REPOSITORY/$GITHUB_REPOSITORY_BRANCH/installer/files/etc/proftpd/modules.conf -O $INSTALLER_TEMP_PATH/etc/proftpd/modules.conf
wget $GITHUB_RAW_URL/$GITHUB_REPOSITORY/$GITHUB_REPOSITORY_BRANCH/installer/files/etc/proftpd/sql.conf -O $INSTALLER_TEMP_PATH/etc/proftpd/sql.conf

# modify /etc/proftpd/sql.conf
sed -i "s/#SQLConnectInfo proftpd@sql.example.com proftpd_user proftpd_password/SQLConnectInfo $MYSQL_DATABASE@localhost $MYSQL_USER $MYSQL_USER_PASSWORD/" $INSTALLER_TEMP_PATH/etc/proftpd/sql.conf

# Replace original files
rm -f /etc/proftpd/proftpd.conf
mv $INSTALLER_TEMP_PATH/etc/proftpd/proftpd.conf /etc/proftpd/proftpd.conf
rm -f /etc/proftpd/modules.conf
mv $INSTALLER_TEMP_PATH/etc/proftpd/modules.conf /etc/proftpd/modules.conf
rm -f /etc/proftpd/sql.conf
mv $INSTALLER_TEMP_PATH/etc/proftpd/sql.conf /etc/proftpd/sql.conf


# Restart ProFTPd
service proftpd restart
