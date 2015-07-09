#!/bin/bash

# Debian installer v.01

#----------------------------------------------------------#
#                  Variables&Functions                     #
#----------------------------------------------------------#
RAWGITHOST='https://raw.githubusercontent.com/JPG-Consulting/Onion/test'

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

#----------------------------------------------------------#
#                     ProFTPd Setup                        #
#----------------------------------------------------------#
apt-get --yes install proftpd-basic proftpd-mod-sql

proftpd_default_uid=$(id -u www-data)
proftpd_default_gid=$(id -g www-data)

echo "USE psa;" >> /tmp/proftpd.create.sql
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

# now execute sql as root in database!
echo "Please indicate your MySQL root password"
mysql -u root -p < /tmp/proftpd.create.sql
 
rm -f /tmp/proftpd.create.sql

service proftpd restart


