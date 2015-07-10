#!/bin/bash

# Debian installer v.01

#----------------------------------------------------------#
#                  Variables&Functions                     #
#----------------------------------------------------------#
RGITHOST='https://raw.githubusercontent.com/JPG-Consulting/Onion/'
GITVERSION='test';

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
            apt-get --yes install $packages
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

export DEBIAN_FRONTEND=noninteractive

# Check wget
if [ ! -e '/usr/bin/wget' ]; then
    apt-get -y install wget
    if [ $? -ne 0 ]; then
        echo "Error: can't install wget"
        exit 1
    fi
fi

#----------------------------------------------------------#
#                   Update the server                      #
#----------------------------------------------------------#
if prompt_yn "Update the server?" "Y"; then
    apt-get --yes update && apt-get --yes upgrade && apt-get --yes dist-upgrade
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
        apt-get --yes install fail2ban;
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

echo "CREATE DATABASE $system_database;" > /tmp/system.create.sql
echo "GRANT SELECT, INSERT, UPDATE, DELETE ON $system_database.* TO '$system_user'@'localhost' IDENTIFIED BY '$system_passwd';" >> /tmp/system.create.sql
echo "FLUSH PRIVILEGES;" >> /tmp/system.create.sql
echo "USE DATABASE $system_database;" >> /tmp/system.create.sql
# Create the domains table
echo "  CREATE TABLE `clients` (" >> /tmp/system.create.sql
echo "  `id` int(10) unsigned NOT NULL auto_increment," >> /tmp/system.create.sql
echo "  `cr_date` date default NULL," >> /tmp/system.create.sql
echo "  `cname` varchar(255) character set utf8 default NULL," >> /tmp/system.create.sql
echo "  `pname` varchar(255) character set utf8 NOT NULL default ''," >> /tmp/system.create.sql
echo "  `login` varchar(20) character set utf8 NOT NULL default ''," >> /tmp/system.create.sql
echo "  `account_id` int(10) unsigned NOT NULL default '0'," >> /tmp/system.create.sql
echo "  `status` bigint(20) unsigned NOT NULL default '0'," >> /tmp/system.create.sql
echo "  `phone` varchar(255) character set ascii collate ascii_bin default NULL," >> /tmp/system.create.sql
echo "  `fax` varchar(255) character set ascii collate ascii_bin default NULL," >> /tmp/system.create.sql
echo "  `email` varchar(255) character set utf8 default NULL," >> /tmp/system.create.sql
echo "  `address` varchar(255) character set utf8 default NULL," >> /tmp/system.create.sql
echo "  `city` varchar(255) character set utf8 default NULL," >> /tmp/system.create.sql
echo "  `state` varchar(255) character set utf8 default NULL," >> /tmp/system.create.sql
echo "  `pcode` varchar(10) character set ascii collate ascii_bin default NULL," >> /tmp/system.create.sql
echo "  `country` char(2) character set ascii collate ascii_bin default NULL," >> /tmp/system.create.sql
echo "  `locale` varchar(17) character set ascii collate ascii_bin NOT NULL default 'en-US'," >> /tmp/system.create.sql
echo "  `limits_id` int(10) unsigned default NULL," >> /tmp/system.create.sql
echo "  `params_id` int(10) unsigned default NULL," >> /tmp/system.create.sql
echo "  `perm_id` int(10) unsigned default NULL," >> /tmp/system.create.sql
echo "  `pool_id` int(10) unsigned default NULL," >> /tmp/system.create.sql
echo "  `logo_id` int(10) unsigned default NULL," >> /tmp/system.create.sql
echo "  `tmpl_id` int(10) unsigned default NULL," >> /tmp/system.create.sql
echo "  `sapp_pool_id` int(10) unsigned default NULL," >> /tmp/system.create.sql
echo "  `guid` varchar(36) character set ascii collate ascii_bin NOT NULL default '00000000-0000-0000-0000-000000000000'," >> /tmp/system.create.sql
echo "  PRIMARY KEY  (`id`)," >> /tmp/system.create.sql
echo "  UNIQUE KEY `login` (`login`)," >> /tmp/system.create.sql
echo "  KEY `account_id` (`account_id`)," >> /tmp/system.create.sql
echo "  KEY `limits_id` (`limits_id`)," >> /tmp/system.create.sql
echo "  KEY `params_id` (`params_id`)," >> /tmp/system.create.sql
echo "  KEY `perm_id` (`perm_id`)," >> /tmp/system.create.sql
echo "  KEY `pool_id` (`pool_id`)," >> /tmp/system.create.sql
echo "  KEY `logo_id` (`logo_id`)," >> /tmp/system.create.sql
echo "  KEY `tmpl_id` (`tmpl_id`)," >> /tmp/system.create.sql
echo "  KEY `sapp_pool_id` (`sapp_pool_id`)," >> /tmp/system.create.sql
echo "  KEY `pname` (`pname`)" >> /tmp/system.create.sql
echo ") ENGINE=InnoDB CHARSET=utf8;" >> /tmp/system.create.sql
echo "" >> /tmp/system.create.sql
echo "CREATE TABLE `domains` (" >> /tmp/system.create.sql
echo "    `id` int(10) unsigned NOT NULL auto_increment," >> /tmp/system.create.sql
echo "    `cr_date` date default NULL," >> /tmp/system.create.sql
echo "    `name` varchar(255) character set ascii NOT NULL default ''," >> /tmp/system.create.sql
echo "    `displayName` varchar(255) character set utf8 NOT NULL default ''," >> /tmp/system.create.sql
echo "    `dns_zone_id` int(10) unsigned NOT NULL default '0'," >> /tmp/system.create.sql
echo "    `status` bigint(20) unsigned NOT NULL default '0'," >> /tmp/system.create.sql
echo "    `htype` enum('none','vrt_hst','std_fwd','frm_fwd') NOT NULL default 'none'," >> /tmp/system.create.sql
echo "    `real_size` bigint(20) unsigned default '0'," >> /tmp/system.create.sql
echo "    `client_id` int(10) unsigned NOT NULL default '0'," >> /tmp/system.create.sql
echo "    `cert_rep_id` int(10) unsigned default NULL," >> /tmp/system.create.sql
echo "    `limits_id` int(10) unsigned default NULL," >> /tmp/system.create.sql
echo "    `params_id` int(10) unsigned default NULL," >> /tmp/system.create.sql
echo "    `guid` varchar(36) character set ascii collate ascii_bin NOT NULL default '00000000-0000-0000-0000-000000000000'," >> /tmp/system.create.sql
echo "    PRIMARY KEY  (`id`)," >> /tmp/system.create.sql
echo "    UNIQUE KEY `name` (`name`)," >> /tmp/system.create.sql
echo "    KEY `cl_id` (`cl_id`)," >> /tmp/system.create.sql
echo "    KEY `cert_rep_id` (`cert_rep_id`)," >> /tmp/system.create.sql
echo "    KEY `limits_id` (`limits_id`)," >> /tmp/system.create.sql
echo "    KEY `params_id` (`params_id`)," >> /tmp/system.create.sql
echo "    KEY `displayName` (`displayName`)" >> /tmp/system.create.sql
echo ") ENGINE=InnoDB CHARSET=utf8;" >> /tmp/system.create.sql
        
# now execute sql as root in database!
mysql -u root -p $mysql_root_passwd < /tmp/system.create.sql
rm -f /tmp/system.create.sql

#----------------------------------------------------------#
#                      Apache Setup                        #
#----------------------------------------------------------#
install_missing_packages apache2 openssl ssl-cert

# Create directory for vhosts
if [ ! -d /var/www/default/htdocs ]; then
    mkdir -p /var/www/default/htdocs
fi

if [ ! -f /var/www/default/htdocs/index.html ]; then
    echo "<html><body><h1>It works!</h1>" > /var/www/default/htdocs/index.html
    echo "<p>This is the default web page for this server.</p>" >> /var/www/default/htdocs/index.html
    echo "<p>The web server software is running but no content has been added, yet.</p>" >> /var/www/default/htdocs/index.html
    echo "</body></html>" >> /var/www/default/htdocs/index.html
fi

if [ ! -d /var/www/default/htsdocs ]; then
    mkdir -p /var/www/default/htsdocs
fi

if [ ! -f /var/www/default/htsdocs/index.html ]; then
    echo "<html><body><h1>It works!</h1>" > /var/www/default/htsdocs/index.html
    echo "<p>This is the default web page for this server.</p>" >> /var/www/default/htsdocs/index.html
    echo "<p>The web server software is running but no content has been added, yet.</p>" >> /var/www/default/htsdocs/index.html
    echo "</body></html>" >> /var/www/default/htsdocs/index.html
fi

wget $RGITHOST/$GITVERSION/installer/system/etc/apache2/sites-available/default -O /etc/apache2/sites-available/default
wget $RGITHOST/$GITVERSION/installer/system/etc/apache2/sites-available/default-ssl -O /etc/apache2/sites-available/default-ssl
wget $RGITHOST/$GITVERSION/installer/system/etc/apache2/sites-enabled/000-default -O /etc/apache2/sites-enabled/000-default

#----------------------------------------------------------#
#                       PHP5 Setup                         #
#----------------------------------------------------------#
install_missing_packages php5 libapache2-mod-php5 php5-cli php5-common php5-cgi php5-mysql php5-curl

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

# Create mails table
echo "USE DATABASE $system_database;" > /tmp/postfix.create.sql
echo "CREATE TABLE `mail` (" >> /tmp/postfix.create.sql
echo "    `id` int(10) unsigned NOT NULL auto_increment," >> /tmp/postfix.create.sql
echo "    `mail_name` varchar(245) character set ascii NOT NULL default ''," >> /tmp/postfix.create.sql
echo "    `perm_id` int(10) unsigned NOT NULL default '0'," >> /tmp/postfix.create.sql
echo "    `postbox` enum('false','true') NOT NULL default 'false'," >> /tmp/postfix.create.sql
echo "    `account_id` int(10) unsigned NOT NULL default '0'," >> /tmp/postfix.create.sql
echo "    `redirect` enum('false','true') NOT NULL default 'false'," >> /tmp/postfix.create.sql
echo "    `redir_addr` varchar(255) character set utf8 default NULL," >> /tmp/postfix.create.sql
echo "    `mail_group` enum('false','true') NOT NULL default 'false'," >> /tmp/postfix.create.sql
echo "    `autoresponder` enum('false','true') NOT NULL default 'false'," >> /tmp/postfix.create.sql
echo "    `spamfilter` enum('false','true') NOT NULL default 'false'," >> /tmp/postfix.create.sql
echo "    `virusfilter` enum('none','incoming','outgoing','any') NOT NULL default 'none'," >> /tmp/postfix.create.sql
echo "    `mbox_quota` bigint(20) NOT NULL default '-1'," >> /tmp/postfix.create.sql
echo "    `domain_id` int(10) unsigned NOT NULL default '0'," >> /tmp/postfix.create.sql
echo "    PRIMARY KEY  (`id`)," >> /tmp/postfix.create.sql
echo "    UNIQUE KEY `domain_id` (`domain_id`,`mail_name`)," >> /tmp/postfix.create.sql
echo "    KEY `account_id` (`account_id`)," >> /tmp/postfix.create.sql
echo "    KEY `perm_id` (`perm_id`)" >> /tmp/postfix.create.sql
echo ") ENGINE=InnoDB CHARSET=utf8;" >> /tmp/postfix.create.sql
echo "" >> /tmp/postfix.create.sql
echo "CREATE TABLE `mail_aliases` (" >> /tmp/postfix.create.sql
echo "    `id` int(10) unsigned NOT NULL auto_increment," >> /tmp/postfix.create.sql
echo "    `mail_id` int(10) unsigned NOT NULL default '0'," >> /tmp/postfix.create.sql
echo "    `alias` varchar(245) character set ascii NOT NULL default ''," >> /tmp/postfix.create.sql
echo "    PRIMARY KEY  (`id`)," >> /tmp/postfix.create.sql
echo "    UNIQUE KEY `mail_id` (`mail_id`,`alias`)" >> /tmp/postfix.create.sql
echo ") ENGINE=InnoDB CHARSET=utf8;" >> /tmp/postfix.create.sql

# now execute sql as root in database!
mysql -u root -p $mysql_root_passwd < /tmp/postfix.create.sql
rm -f /tmp/postfix.create.sql

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
install_missing_packages proftpd-basic proftpd-mod-sql

proftpd_default_uid=$(id -u www-data)
proftpd_default_gid=$(id -g www-data)

echo "USE $system_database;" >> /tmp/proftpd.create.sql
echo "" >> /tmp/proftpd.create.sql
echo "CREATE TABLE ftp_groups (" >> /tmp/proftpd.create.sql
echo "    groupname varchar(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL default ''," >> /tmp/proftpd.create.sql
echo "    gid smallint(6) NOT NULL default '$proftpd_default_gid'," >> /tmp/proftpd.create.sql
echo "    members varchar(16) NOT NULL default ''," >> /tmp/proftpd.create.sql
echo "    KEY groupname (groupname)" >> /tmp/proftpd.create.sql
echo ") ENGINE=InnoDB COMMENT='ProFTP group table' CHARSET=utf8;" >> /tmp/proftpd.create.sql
echo "" >> /tmp/proftpd.create.sql 
echo "CREATE TABLE ftp_users (" >> /tmp/proftpd.create.sql
echo "    id int(10) unsigned NOT NULL auto_increment," >> /tmp/proftpd.create.sql
echo "    userid varchar(32) CHARACTER SET ascii NOT NULL default ''," >> /tmp/proftpd.create.sql
echo "    passwd varchar(32) NOT NULL default ''," >> /tmp/proftpd.create.sql
echo "    uid smallint(6) NOT NULL default '$proftpd_default_uid'," >> /tmp/proftpd.create.sql
echo "    gid smallint(6) NOT NULL default '$proftpd_default_gid'," >> /tmp/proftpd.create.sql
echo "    homedir varchar(255) CHARACTER SET ascii COLLATE ascii_bin NOT NULL default ''," >> /tmp/proftpd.create.sql
echo "    shell varchar(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL default '/sbin/nologin'," >> /tmp/proftpd.create.sql
echo "    count int(11) NOT NULL default '0'," >> /tmp/proftpd.create.sql
echo "    accessed datetime NOT NULL default '0000-00-00 00:00:00'," >> /tmp/proftpd.create.sql
echo "    modified datetime NOT NULL default '0000-00-00 00:00:00'," >> /tmp/proftpd.create.sql
echo "    PRIMARY KEY (id)," >> /tmp/proftpd.create.sql
echo "    UNIQUE KEY userid (userid)" >> /tmp/proftpd.create.sql
echo ") ENGINE=InnoDB COMMENT="ProFTP user table" CHARSET=utf8;" >> /tmp/proftpd.create.sql
echo "" >> /tmp/proftpd.create.sql
echo "INSERT INTO `ftpgroup` (`groupname`, `gid`, `members`) VALUES ('www-data', $proftpd_default_gid, 'www-data');" >> /tmp/proftpd.create.sql

# now execute sql as root in database!
mysql -u root -p $mysql_root_passwd < /tmp/proftpd.create.sql
rm -f /tmp/proftpd.create.sql

# Creating sql.conf file
echo "#" > /etc/proftpd/sql.conf
echo "# Proftpd sample configuration for SQL-based authentication." >> /etc/proftpd/sql.conf
echo "#" >> /etc/proftpd/sql.conf
echo "# (This is not to be used if you prefer a PAM-based SQL authentication)" >> /etc/proftpd/sql.conf
echo "#" >> /etc/proftpd/sql.conf
echo "<IfModule mod_sql.c>" >> /etc/proftpd/sql.conf
echo "#" >> /etc/proftpd/sql.conf
echo "# Choose a SQL backend among MySQL or PostgreSQL." >> /etc/proftpd/sql.conf
echo "# Both modules are loaded in default configuration, so you have to specify the backend" >> /etc/proftpd/sql.conf
echo "# or comment out the unused module in /etc/proftpd/modules.conf." >> /etc/proftpd/sql.conf
echo "# Use 'mysql' or 'postgres' as possible values." >> /etc/proftpd/sql.conf
echo "#" >> /etc/proftpd/sql.conf
echo "SQLBackend mysql" >> /etc/proftpd/sql.conf
echo "#" >> /etc/proftpd/sql.conf
echo "#SQLEngine on" >> /etc/proftpd/sql.conf
echo "#SQLAuthenticate on" >> /etc/proftpd/sql.conf
echo "#" >> /etc/proftpd/sql.conf
echo "# Use both a crypted or plaintext password" >> /etc/proftpd/sql.conf
echo "SQLAuthTypes Crypt Plaintext" >> /etc/proftpd/sql.conf
echo "#" >> /etc/proftpd/sql.conf
echo "# Use a backend-crypted or a crypted password" >> /etc/proftpd/sql.conf
echo "#SQLAuthTypes Backend Crypt" >> /etc/proftpd/sql.conf
echo "#" >> /etc/proftpd/sql.conf
echo "# Connection" >> /etc/proftpd/sql.conf
# TODO: Modify this line!!!
echo "#SQLConnectInfo proftpd@sql.example.com proftpd_user proftpd_password" >> /etc/proftpd/sql.conf
echo "#" >> /etc/proftpd/sql.conf
echo "# Describes both users/groups tables" >> /etc/proftpd/sql.conf
echo "#" >> /etc/proftpd/sql.conf
echo "SQLUserInfo ftp_users userid passwd uid gid homedir shell" >> /etc/proftpd/sql.conf
echo "SQLGroupInfo ftp_groups groupname gid members" >> /etc/proftpd/sql.conf
echo "#" >> /etc/proftpd/sql.conf
echo "# Update count every time user logs in" >> /etc/proftpd/sql.conf
echo "#" >> /etc/proftpd/sql.conf
echo "SQLLog PASS updatecount" >> /etc/proftpd/sql.conf
echo "SQLNamedQuery updatecount UPDATE \"count=count+1, accessed=now() WHERE userid='%u'\" ftpuser" >> /etc/proftpd/sql.conf
echo "# Update modified everytime user uploads or deletes a file >> /etc/proftpd/sql.conf
echo "SQLLog STOR,DELE modified" >> /etc/proftpd/sql.conf
echo "SQLNamedQuery modified UPDATE \"modified=now() WHERE userid='%u'\" ftpuser" >> /etc/proftpd/sql.conf
echo "#" >> /etc/proftpd/sql.conf
echo "# Security" >> /etc/proftpd/sql.conf
echo "#" >> /etc/proftpd/sql.conf
echo "RootLogin off" >> /etc/proftpd/sql.conf
echo "RequireValidShell off" >> /etc/proftpd/sql.conf
echo "</IfModule>" >> /etc/proftpd/sql.conf

# restart proftpd
service proftpd restart


