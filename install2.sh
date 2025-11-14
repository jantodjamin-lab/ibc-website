#!/bin/bash

set -e

# ==================================
# WordPress Auto Installer (Apache + MariaDB + SSL)
# GitHub-Ready Version (Linux LF format)
# ==================================

DOMAIN="bonaireworship.com"
DB_NAME="wordpress"
DB_USER="wp_user"
DB_PASS="$(openssl rand -base64 16)"
WP_DIR="/var/www/html/wordpress"
EMAIL="janto@farawe.com"

echo "============================"
echo " Updating system"
echo "============================"
sudo apt update -y
sudo apt upgrade -y

echo "============================"
echo " Installing Apache, PHP, MariaDB"
echo "============================"
sudo apt install -y apache2 mariadb-server mariadb-client
sudo apt install -y php php-mysql php-gd php-xml php-mbstring php-curl php-zip php-intl php-soap php-imagick unzip wget

echo "============================"
echo " Enabling Apache modules"
echo "============================"
sudo a2enmod rewrite headers ssl
sudo systemctl restart apache2

echo "============================"
echo " Securing MariaDB"
echo "============================"
sudo mysql -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME};"
sudo mysql -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';"
sudo mysql -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';"
sudo mysql -e "FLUSH PRIVILEGES;"

echo "============================"
echo " Creating WordPress directory"
echo "============================"
sudo mkdir -p "$WP_DIR"
sudo chown -R www-data:www-data /var/www/html

echo "============================"
echo " Installing WP-CLI"
echo "============================"
curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x wp-cli.phar
sudo mv wp-cli.phar /usr/local/bin/wp

echo "============================"
echo " Fixing WP-CLI permissions"
echo "============================"
sudo mkdir -p /var/www/.wp-cli/cache
sudo chown -R www-data:www-data /var/www/.wp-cli

echo "============================"
echo " Downloading WordPress core"
echo "============================"
sudo -u www-data wp core download --path="$WP_DIR"

echo "============================"
echo " Creating wp-config.php"
echo "============================"
sudo -u www-data wp config create \
  --path="$WP_DIR" \
  --dbname="$DB_NAME" \
  --dbuser="$DB_USER" \
  --dbpass="$DB_PASS" \
  --dbhost="localhost"

echo "============================"
echo " Running WordPress install"
echo "============================"
sudo -u www-data wp core install \
  --path="$WP_DIR" \
  --url="https://${DOMAIN}" \
  --title="WordPress Site" \
  --admin_user="admin" \
  --admin_pass="AdminPass123!" \
  --admin_email="$EMAIL"

echo "============================"
echo " Setting up Apache VirtualHost"
echo "============================"

VHOST_FILE="/etc/apache2/sites-available/wordpress.conf"

sudo bash -c "cat > $VHOST_FILE" <<EOF
<VirtualHost *:80>
    ServerName $DOMAIN
    DocumentRoot $WP_DIR

    <Directory $WP_DIR>
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/wordpress-error.log
    CustomLog \${APACHE_LOG_DIR}/wordpress-access.log combined
</VirtualHost>

<VirtualHost [::]:80>
    ServerName $DOMAIN
    DocumentRoot $WP_DIR

    <Directory $WP_DIR>
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/wordpress-error.log
    CustomLog \${APACHE_LOG_DIR}/wordpress-access.log combined
</VirtualHost>
EOF

sudo a2ensite wordpress.conf
sudo systemctl reload apache2

echo "============================"
echo " Installing Certbot (SSL)"
echo "============================"
sudo apt install -y certbot python3-certbot-apache

sudo certbot --apache -d "$DOMAIN" -m "$EMAIL" --agree-tos --redirect --non-interactive

echo "============================"
echo " Hardening permissions"
echo "============================"
sudo chown -R www-data:www-data "$WP_DIR"

echo "============================"
echo " Installation complete!"
echo "============================"
echo "Database:"
echo " DB Name: $DB_NAME"
echo " DB User: $DB_USER"
echo " DB Pass: $DB_PASS"
echo "WordPress admin login: https://$DOMAIN/wp-admin/"
