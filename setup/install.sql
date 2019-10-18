-- Setup script for the database.

-- User table

CREATE TABLE IF NOT EXISTS `user` (
	`id`	INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT UNIQUE,
	`username`	INTEGER NOT NULL UNIQUE,
	`password`	TEXT
);

INSERT INTO `user` (username,password) VALUES ('rolf','$rpbkdf2$0$AAAnEA==$Wih697v+F5NJGvnRIldzLw==$Bqx2PYzgR5Dg+wBELKRsmt/HaV9LZXQ4QcYK70HNbsU=$');
INSERT INTO `user` (username,password) VALUES ('doro','$rpbkdf2$0$AAAnEA==$O/nqIkH/YIm/EzV8CfMIPA==$rN7hmPd3gmanCApEXQtsCd4SqA6+EKAu6HGqyvFJp50=$');

CREATE TABLE IF NOT EXISTS `game` (
	`id`	INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT UNIQUE,
	`owner`	INTEGER,
	`description`	TEXT NOT NULL,
	FOREIGN KEY(`owner`) REFERENCES `user`(`id`)
);

CREATE TABLE IF NOT EXISTS `game_data` (
	`id`	INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT UNIQUE,
	`game`	INTEGER NOT NULL,
	`data`	TEXT NOT NULL,
	FOREIGN KEY(`game`) REFERENCES `game`(`id`)
);
