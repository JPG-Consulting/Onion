USE psa;

CREATE TABLE ftp_groups (
    groupname varchar(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL default '',
    gid smallint(6) NOT NULL default '2001',
    members varchar(16) NOT NULL default '',
    KEY groupname (groupname)
) ENGINE=InnoDB COMMENT='ProFTP group table' CHARSET=utf8;
 
CREATE TABLE ftp_users (
    id int(10) unsigned NOT NULL auto_increment,
    userid varchar(32) CHARACTER SET ascii NOT NULL default '',
    passwd varchar(32) NOT NULL default '',
    uid smallint(6) NOT NULL default '2001',
    gid smallint(6) NOT NULL default '2001',
    homedir varchar(255) CHARACTER SET ascii COLLATE ascii_bin NOT NULL default '',
    shell varchar(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL default '/sbin/nologin',
    count int(11) NOT NULL default '0',
    accessed datetime NOT NULL default '0000-00-00 00:00:00',
    modified datetime NOT NULL default '0000-00-00 00:00:00',
    PRIMARY KEY (id),
    UNIQUE KEY userid (userid)
) ENGINE=InnoDB COMMENT="ProFTP user table" CHARSET=utf8;


