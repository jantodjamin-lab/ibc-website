#!/bin/bash
# =========================================
# Fully Hardened WordPress Installer for Ubuntu LTS 22.04/24.04
# Dual-stack Apache (IPv4 + IPv6) + Mail support
# Includes: LAMP, WordPress, SSL, WP-CLI, Fail2Ban, hardening, sample content
# =========================================

# ===============================
# Variables (change before running)
# ===============================
ROOT_PASS="${ROOT_PASS:-rGi34RGfWB5FKDb5QMv7}"
DB_NAME="${DB_NAME:-wordpress}"
DB_USER="${DB_USER:-wpuser}"
DB_PASS="${DB_PASS:-E1RP4jBCfjd57JVeArzW}"
WP_DIR="${WP_DIR:-/var/www/html/wordpress}"
SERVER_NAME="${SERVER_NAME:-bonaireworship.com}"
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_PASS="${ADMIN_PASS:-JmYAJBrYe2en0Du9dXMt}"
ADMIN_EMAIL="${ADMIN_EMAIL:-janto@farawe.com}"

# ===============================
# Update system
# ===============================
echo "Updating system..."
apt update -y && apt upgrade -y

# ===============================
# Create non-root user
# ===============================
echo "Creating non-root user..."
adduser --disabled-password --gecos "" wpadmin
echo "wpadmin:$(openssl rand -base64 12)" | chpasswd
usermod -aG sudo wpadmin

# ===============================
# Configure firewall
# ===============================
echo "Configuring UFW firewall..."
ufw allow OpenSSH
ufw allow http
ufw allow https
ufw --force enable

# ===============================
# Install LAMP stack + Fail2Ban + Mail
# ===============================
echo "Installing Apache, MySQL, PHP, Fail2Ban, Mailutils..."
apt install -y apache2 mysql-server php php-mysql php-fpm php-xml php-json php-gd php-mbstring php-curl php-zip wget unzip fail2ban certbot python3-certbot-apache mailutils postfix
systemctl enable apache2 mysql fail2ban postfix
systemctl start apache2 mysql fail2ban postfix

# ===============================
# Configure Postfix (basic)
# ===============================
echo "Configuring Postfix..."
echo "$SERVER_NAME" | tee /etc/mailname
postconf -e "myhostname = $SERVER_NAME"
postconf -e "myorigin = /etc/mailname"
systemctl restart postfix

# ===============================
# Harden MySQL
# ===============================
echo "Hardening MySQL..."
mysql -u root <<MYSQL_SCRIPT
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${ROOT_PASS}';
DELETE FROM mysql.user WHERE User='';
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\_%';
FLUSH PRIVILEGES;
MYSQL_SCRIPT

# ===============================
# Create WordPress database/user
# ===============================
echo "Creating WordPress database and user..."
mysql -u root -p$ROOT_PASS -e "CREATE DATABASE IF NOT EXISTS $DB_NAME;"
mysql -u root -p$ROOT_PASS -e "CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
mysql -u root -p$ROOT_PASS -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';"
mysql -u root -p$ROOT_PASS -e "FLUSH PRIVILEGES;"

# ===============================
# Download and copy WordPress
# ===============================
echo "Downloading WordPress..."
cd /tmp
wget -q https://wordpress.org/latest.tar.gz
tar -xzf latest.tar.gz
mkdir -p $WP_DIR
cp -r wordpress/* $WP_DIR/

# Set permissions
chown -R www-data:www-data $WP_DIR
find $WP_DIR/ -type d -exec chmod 755 {} \;
find $WP_DIR/ -type f -exec chmod 644 {} \;
chmod -R 775 $WP_DIR/wp-content/uploads
chmod -R 775 $WP_DIR/wp-content/cache
chmod -R 755 $WP_DIR/wp-content/plugins

# ===============================
# Configure Apache for dual-stack
# ===============================
echo "Configuring Apache for IPv4 + IPv6..."
cat > /etc/apache2/ports.conf <<EOL
Listen 80
Listen [::]:80
Listen 443
Listen [::]:443
EOL

cat > /etc/apache2/sites-available/wordpress.conf <<EOL
<VirtualHost *:80>
    ServerAdmin admin@$SERVER_NAME
    DocumentRoot $WP_DIR
    ServerName $SERVER_NAME
    <Directory $WP_DIR/>
        AllowOverride All
        Require all granted
    </Directory>
    ErrorLog /var/log/apache2/wordpress-error.log
    CustomLog /var/log/apache2/wordpress-access.log combined
</VirtualHost>

<VirtualHost [::]:80>
    ServerAdmin admin@$SERVER_NAME
    DocumentRoot $WP_DIR
    ServerName $SERVER_NAME
    <Directory $WP_DIR/>
        AllowOverride All
        Require all granted
    </Directory>
    ErrorLog /var/log/apache2/wordpress-error.log
    CustomLog /var/log/apache2/wordpress-access.log combined
</VirtualHost>
EOL

a2dissite 000-default.conf
a2ensite wordpress.conf
a2enmod rewrite ssl headers
echo "ServerName $SERVER_NAME" | tee /etc/apache2/conf-available/servername.conf
a2enconf servername
systemctl restart apache2

# ===============================
# Configure wp-config.php and insert salts
# ===============================
cp $WP_DIR/wp-config-sample.php $WP_DIR/wp-config.php
sed -i "s/database_name_here/$DB_NAME/" $WP_DIR/wp-config.php
sed -i "s/username_here/$DB_USER/" $WP_DIR/wp-config.php
sed -i "s/password_here/$DB_PASS/" $WP_DIR/wp-config.php

SALT=$(curl -s https://api.wordpress.org/secret-key/1.1/salt/)
sed -i "/AUTH_KEY/d;/SECURE_AUTH_KEY/d;/LOGGED_IN_KEY/d;/NONCE_KEY/d;/AUTH_SALT/d;/SECURE_AUTH_SALT/d;/LOGGED_IN_SALT/d;/NONCE_SALT/d" $WP_DIR/wp-config.php
printf "%s\n" "$SALT" >> $WP_DIR/wp-config.php
chown -R www-data:www-data $WP_DIR

# ===============================
# Install WP-CLI
# ===============================
cd /usr/local/bin
curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x wp-cli.phar
mv wp-cli.phar /usr/local/bin/wp

# ===============================
# Install WordPress via WP-CLI
# ===============================
cd $WP_DIR
sudo -u www-data wp core install \
  --url="http://$SERVER_NAME" \
  --title="Lyrics Site" \
  --admin_user="$ADMIN_USER" \
  --admin_password="$ADMIN_PASS" \
  --admin_email="$ADMIN_EMAIL" \
  --skip-email

# ===============================
# Activate theme, create sample post
# ===============================
sudo -u www-data wp theme install twentytwentyone --activate
sudo -u www-data wp option update blogdescription "Lyrics and Poetry Collection"
sudo -u www-data wp rewrite structure '/%postname%/' --hard

CATEGORY_ID=$(sudo -u www-data wp term create category "Lyrics" --porcelain)
sudo -u www-data wp post create --post_type=post \
  --post_status=publish \
  --post_title="Sample Lyrics" \
  --post_content="This is a sample lyrics post. Replace this with your own song lyrics." \
  --post_category="$CATEGORY_ID" --porcelain

# ===============================
# Setup HTTPS with Certbot
# ===============================
certbot --apache --non-interactive --agree-tos --redirect -m $ADMIN_EMAIL -d $SERVER_NAME
systemctl enable certbot.timer
systemctl start certbot.timer

# ===============================
# Fail2Ban WordPress
# ===============================
cat > /etc/fail2ban/jail.d/wordpress.conf <<EOL
[wordpress]
enabled = true
filter = wordpress
port = http,https
logpath = /var/log/apache2/access.log
maxretry = 5
bantime = 3600
EOL

cat > /etc/fail2ban/filter.d/wordpress.conf <<EOL
[Definition]
failregex = <HOST> -.* "POST /wp-login.php" .* (200|302|403)
ignoreregex =
EOL

systemctl restart fail2ban

# ===============================
# Complete
# ===============================
echo "✅ WordPress installation complete with Mail support!"
echo "Visit: http://$SERVER_NAME or https://$SERVER_NAME"
echo "Admin login: http://$SERVER_NAME/wp-admin/ | User: $ADMIN_USER | Pass: $ADMIN_PASS"
