-- Setup script for the database.

-- User table

CREATE TABLE IF NOT EXISTS `user` (
	`id`	INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT UNIQUE,
	`username`	INTEGER NOT NULL UNIQUE,
	`password`	TEXT
);

INSERT INTO `user` (id, username,password) VALUES ('rolf','$rpbkdf2$0$AAAnEA==$Wih697v+F5NJGvnRIldzLw==$Bqx2PYzgR5Dg+wBELKRsmt/HaV9LZXQ4QcYK70HNbsU=$');
INSERT INTO `user` (id, username,password) VALUES ('doro','$rpbkdf2$0$AAAnEA==$O/nqIkH/YIm/EzV8CfMIPA==$rN7hmPd3gmanCApEXQtsCd4SqA6+EKAu6HGqyvFJp50=$');

CREATE TABLE IF NOT EXISTS `game` (
	`id`	INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT UNIQUE,
	`description`	TEXT NOT NULL
);

-- We create three example games
INSERT INTO `game` (id, description) VALUES (1, `A shared game`);
INSERT INTO `game` (id, description) VALUES (2, `Rolf's game`);
INSERT INTO `game` (id, description) VALUES (3, `Doro's game`);

CREATE TABLE IF NOT EXISTS `game_data` (
	`id`	INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT UNIQUE,
	`game`	INTEGER NOT NULL,
	`data`	TEXT NOT NULL,
	FOREIGN KEY(`game`) REFERENCES `game`(`id`)
);

CREATE TABLE IF NOT EXISTS `game_member` (
    `user`  INTEGER NOT NULL,
    `game`  INTEGER NOT NULL,
    `role`  INTEGER NOT NULL,
	`accepted`	INTEGER NOT NULL DEFAULT 0,
    UNIQUE(`user`,`game`)
);

-- Both players join game 1, rolf is player 1, doro is player 2
INSERT INTO `game_member` (user, game, role, accepted) VALUES (1, 1, 1, 1);
INSERT INTO `game_member` (user, game, role, accepted) VALUES (2, 1, 2, 1);

-- Only rolf joins game 2, he is player 1
INSERT INTO `game_member` (user, game, role, accepted) VALUES (1, 2, 1, 1);

-- Only doro joins game 3, she is player 1
INSERT INTO `game_member` (user, game, role, accepted) VALUES (2, 3, 1, 1);