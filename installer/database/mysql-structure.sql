--
-- Estructura de tabla para la tabla `accounts`
--

CREATE TABLE IF NOT EXISTS `accounts` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `type` varchar(32) CHARACTER SET ascii NOT NULL DEFAULT 'plain',
  `password` text CHARACTER SET ascii COLLATE ascii_bin,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB  DEFAULT CHARSET=utf8 AUTO_INCREMENT=3 ;

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `domains`
--

CREATE TABLE IF NOT EXISTS `domains` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(255) CHARACTER SET ascii NOT NULL DEFAULT '',
  `active` tinyint(1) NOT NULL DEFAULT '1',
  `created` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  PRIMARY KEY (`id`),
  UNIQUE KEY `name` (`name`)
) ENGINE=InnoDB  DEFAULT CHARSET=utf8 AUTO_INCREMENT=3 ;

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `ftp_groups`
--

CREATE TABLE IF NOT EXISTS `ftp_groups'  (
  `groupname` varchar(16) NOT NULL default '',
  `gid` smallint(6) NOT NULL default '2001',
  `members` varchar(16) NOT NULL default '',
  KEY `groupname` (`groupname`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
-- --------------------------------------------------------
--
-- Estructura de tabla para la tabla `ftp_users`
--
CREATE TABLE IF NOT EXISTS ftp_users (
  `id` int(10) unsigned NOT NULL auto_increment,
  `userid` varchar(32) NOT NULL default '',
  `passwd` varchar(32) NOT NULL default '',
  `uid` smallint(6) NOT NULL default '2001',
  `gid` smallint(6) NOT NULL default '2001',
  `homedir` varchar(255) NOT NULL default '',
  `shell` varchar(16) NOT NULL default '/sbin/nologin',
  count int(11) NOT NULL default '0',
  `accessed` datetime NOT NULL default '0000-00-00 00:00:00',
  `modified` datetime NOT NULL default '0000-00-00 00:00:00',
  PRIMARY KEY (`id`),
  UNIQUE KEY userid (`userid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
-- --------------------------------------------------------
--
-- Estructura de tabla para la tabla `mail`
--
CREATE TABLE IF NOT EXISTS `mail` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `mail_name` varchar(245) CHARACTER SET ascii NOT NULL DEFAULT '',
  `account_id` int(10) unsigned NOT NULL DEFAULT '0',
  `domain_id` int(10) unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  UNIQUE KEY `domain_id` (`domain_id`,`mail_name`),
  KEY `account_id` (`account_id`)
) ENGINE=InnoDB  DEFAULT CHARSET=utf8 AUTO_INCREMENT=7 ;
-- --------------------------------------------------------
--
-- Estructura de tabla para la tabla `mail_aliases`
--
CREATE TABLE IF NOT EXISTS `mail_aliases` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `mail_id` int(10) unsigned NOT NULL DEFAULT '0',
  `alias` varchar(245) CHARACTER SET ascii NOT NULL DEFAULT '',
  PRIMARY KEY (`id`),
  UNIQUE KEY `mn_id` (`mail_id`,`alias`)
) ENGINE=InnoDB  DEFAULT CHARSET=utf8 AUTO_INCREMENT=3 ;
-- --------------------------------------------------------
--
-- Estructura de tabla para la tabla `sys_users`
--
CREATE TABLE IF NOT EXISTS `sys_users` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `login` varchar(20) CHARACTER SET ascii NOT NULL DEFAULT '',
  `password` varchar(255) NOT NULL,
  `account_id` int(10) unsigned NOT NULL DEFAULT '0',
  `home` varchar(255) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT '',
  `shell` varchar(255) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT '',
  `quota` bigint(20) unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  UNIQUE KEY `login` (`login`),
  KEY `account_id` (`account_id`)
) ENGINE=InnoDB  DEFAULT CHARSET=utf8 AUTO_INCREMENT=2 ;
--
-- Restricciones para tablas volcadas
--
--
-- Filtros para la tabla `mail`
--
ALTER TABLE `mail`
  ADD CONSTRAINT `mail_ibfk_1` FOREIGN KEY (`domain_id`) REFERENCES `domains` (`id`) ON DELETE CASCADE;
--
-- Filtros para la tabla `mail_aliases`
--
ALTER TABLE `mail_aliases`
  ADD CONSTRAINT `mail_aliases_ibfk_1` FOREIGN KEY (`mail_id`) REFERENCES `mail` (`id`) ON DELETE CASCADE;
