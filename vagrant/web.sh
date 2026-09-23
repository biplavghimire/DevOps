#!/usr/bin/env bash

set -e

echo "=========================================="
echo " Starting Web Server Setup"
echo "=========================================="

export DEBIAN_FRONTEND=noninteractive

# ==========================================================
# UPDATE UBUNTU
# ==========================================================

echo "[1/15] Updating Ubuntu..."

apt-get update

# ==========================================================
# INSTALL APACHE, PHP, MYSQL CLIENT AND TOOLS
# ==========================================================

echo "[2/15] Installing Apache2, PHP and required packages..."

apt-get install -y \
apache2 \
php \
libapache2-mod-php \
php-mysql \
php-curl \
php-gd \
php-mbstring \
php-xml \
php-zip \
php-intl \
php-soap \
mysql-client \
netcat-openbsd \
curl \
wget \
tar

# ==========================================================
# START APACHE
# ==========================================================

echo "[3/15] Starting Apache2..."

systemctl enable apache2
systemctl start apache2

# ==========================================================
# WAIT FOR DATABASE SERVER
# ==========================================================

echo "[4/15] Waiting for MySQL Database Server..."

DB_IP="192.168.56.20"
DB_PORT="3306"

for i in $(seq 1 60); do
    if nc -z "$DB_IP" "$DB_PORT"; then
        echo "MySQL is reachable at $DB_IP:$DB_PORT"
        break
    fi

    echo "Waiting for MySQL... attempt $i/60"
    sleep 2
done

if ! nc -z "$DB_IP" "$DB_PORT"; then
    echo "ERROR: Database server is not reachable."
    exit 1
fi

# ==========================================================
# DOWNLOAD WORDPRESS
# ==========================================================

echo "[5/15] Downloading WordPress..."

cd /tmp
rm -rf wordpress wordpress.tar.gz

curl -fsSL \
https://wordpress.org/latest.tar.gz \
-o wordpress.tar.gz

# ==========================================================
# EXTRACT WORDPRESS
# ==========================================================

echo "[6/15] Extracting WordPress..."

tar -xzf wordpress.tar.gz

# ==========================================================
# REMOVE DEFAULT APACHE PAGE
# ==========================================================

echo "[7/15] Preparing Apache document root..."

rm -rf /var/www/html/*

# ==========================================================
# COPY WORDPRESS
# ==========================================================

echo "[8/15] Installing WordPress..."

cp -a wordpress/. /var/www/html/

# ==========================================================
# CREATE WORDPRESS CONFIG
# ==========================================================

echo "[9/15] Creating wp-config.php..."

cd /var/www/html
cp wp-config-sample.php wp-config.php

sed -i "s/database_name_here/wordpress/" wp-config.php
sed -i "s/username_here/wpuser/" wp-config.php
sed -i "s/password_here/WpDatabasePassword123!/" wp-config.php
sed -i "s/define( 'DB_HOST', 'localhost' );/define( 'DB_HOST', '192.168.56.20' );/" wp-config.php

# ==========================================================
# GENERATE WORDPRESS SECURITY SALTS
# ==========================================================

echo "[10/15] Generating WordPress security salts..."

SALT=$(curl -fsSL \
https://api.wordpress.org/secret-key/1.1/salt/)

python3 - <<PY
from pathlib import Path

config = Path("/var/www/html/wp-config.php")
text = config.read_text()
start = text.find("define( 'AUTH_KEY'")
end_marker = "/* That's it, stop editing! Happy publishing. */"
end = text.find(end_marker)

if start != -1 and end != -1:
    new_text = (
        text[:start]
        + """$SALT

"""
        + text[end:]
    )
    config.write_text(new_text)
PY

# ==========================================================
# WORDPRESS DIRECTORY PERMISSIONS
# ==========================================================

echo "[11/15] Setting WordPress permissions..."

chown -R www-data:www-data /var/www/html

find /var/www/html \
-type d \
-exec chmod 755 {} \;

find /var/www/html \
-type f \
-exec chmod 644 {} \;

# ==========================================================
# ENABLE APACHE REWRITE
# ==========================================================

echo "[12/15] Enabling Apache rewrite..."

a2enmod rewrite

# ==========================================================
# CREATE APACHE VIRTUAL HOST
# ==========================================================

echo "[13/15] Creating Apache VirtualHost..."

cat > /etc/apache2/sites-available/wordpress.conf <<'EOF'
<VirtualHost *:80>
    ServerName 192.168.56.10
    DocumentRoot /var/www/html

    <Directory /var/www/html>
        AllowOverride All
        Require all granted
    </Directory>

    DirectoryIndex index.php index.html
    ErrorLog ${APACHE_LOG_DIR}/wordpress_error.log
    CustomLog ${APACHE_LOG_DIR}/wordpress_access.log combined
</VirtualHost>
EOF

# ==========================================================
# ENABLE WORDPRESS SITE
# ==========================================================

echo "[14/15] Enabling WordPress Apache site..."

a2dissite 000-default.conf || true
a2ensite wordpress.conf

# ==========================================================
# TEST APACHE CONFIGURATION
# ==========================================================

echo "[15/15] Testing Apache..."

apache2ctl configtest
systemctl restart apache2

# ==========================================================
# TEST DATABASE CONNECTION
# ==========================================================

echo ""
echo "Testing connection from Web Server to Database Server..."

MYSQL_PWD='WpDatabasePassword123!' \
mysql \
-h 192.168.56.20 \
-u wpuser \
-e "SELECT 1;" wordpress

echo ""
echo "=========================================="
echo " WEB SERVER SETUP COMPLETE"
echo "=========================================="
echo "Web Server IP : 192.168.56.10"
echo "Database IP   : 192.168.56.20"
echo "Website       : http://192.168.56.10"
echo ""
