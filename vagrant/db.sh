#!/bin/bash

set -e

echo "======================================"
echo " Installing MySQL Database Server"
echo "======================================"

apt-get update

DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server

systemctl enable mysql
systemctl start mysql


echo "======================================"
echo " Creating WordPress Database"
echo "======================================"

mysql <<EOF

CREATE DATABASE IF NOT EXISTS wordpress
CHARACTER SET utf8mb4
COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS 'wpuser'@'192.168.56.10'
IDENTIFIED BY 'WpDatabasePassword123!';

ALTER USER 'wpuser'@'192.168.56.10'
IDENTIFIED BY 'WpDatabasePassword123!';

GRANT ALL PRIVILEGES ON wordpress.*
TO 'wpuser'@'192.168.56.10';

FLUSH PRIVILEGES;

EOF


echo "======================================"
echo " Configuring MySQL Remote Access"
echo "======================================"

sed -i 's/^bind-address.*/bind-address = 0.0.0.0/' \
/etc/mysql/mysql.conf.d/mysqld.cnf

systemctl restart mysql


echo "======================================"
echo " Checking MySQL"
echo "======================================"

systemctl is-active mysql

ss -lntp | grep 3306 || true


echo "======================================"
echo " DATABASE SERVER READY"
echo "======================================"

echo "Database Server IP : 192.168.56.20"
echo "Database           : wordpress"
echo "User               : wpuser"
echo "Allowed Web IP     : 192.168.56.10"
echo "MySQL Port         : 3306"
