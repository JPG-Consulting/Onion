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

# now execute sql as root in database!
echo "Please indicate your MySQL root password"
mysql -u root -p < /tmp/proftpd.create.sql
 
rm -f /tmp/proftpd.create.sql

service proftpd restart


