# Two-VM WordPress Lab with Ubuntu and VirtualBox

This tutorial deploys WordPress on two local Ubuntu virtual machines:

```text
WEB SERVER: 192.168.56.10
├── Apache2
├── PHP
└── WordPress
       │
       │ MySQL connection over TCP 3306
       ▼
DATABASE SERVER: 192.168.56.20
└── MySQL
    └── wordpress
```

The web server is the only VM that serves HTTP. The database server is not exposed to the host or the public network; MySQL accepts connections only from the web server.

## Prerequisites

Install the following on your host computer:

- VirtualBox
- Vagrant
- At least 4 GB RAM available for the VMs
- An internet connection for downloading Ubuntu packages and WordPress

The commands below assume Ubuntu 22.04 or Ubuntu 24.04 VMs and a host-only VirtualBox network named `vboxnet0` using `192.168.56.0/24`. If your host-only adapter uses another subnet, replace the addresses consistently everywhere.

## 1. Create the two Ubuntu VMs

You can create two VMs manually in VirtualBox, or use the following Vagrantfile. Vagrant is recommended because it makes the lab repeatable.

Create a directory and save this as `Vagrantfile`:

```ruby
Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu/jammy64"

  config.vm.define "web" do |web|
    web.vm.hostname = "wordpress-web"
    web.vm.network "private_network", ip: "192.168.56.10"
    web.vm.provider "virtualbox" do |vb|
      vb.name = "wordpress-web"
      vb.memory = 2048
      vb.cpus = 2
    end
  end

  config.vm.define "db" do |db|
    db.vm.hostname = "wordpress-db"
    db.vm.network "private_network", ip: "192.168.56.20"
    db.vm.provider "virtualbox" do |vb|
      vb.name = "wordpress-db"
      vb.memory = 2048
      vb.cpus = 2
    end
  end
end
```

Start both machines:

```bash
vagrant up
vagrant status
```

The default Vagrant NAT adapter provides internet access for package installation. The private adapter provides communication between the two VMs and the host at the fixed addresses above.

Connect to a VM with:

```bash
vagrant ssh web
vagrant ssh db
```

If you created the machines manually, configure each VM with two adapters:

1. **NAT** for internet access.
2. **Host-only Adapter** attached to `vboxnet0`.

Assign `192.168.56.10/24` to the web VM and `192.168.56.20/24` to the database VM. Do not assign the same IP to both machines.

## 2. Configure the database server

Connect to the database VM:

```bash
vagrant ssh db
```

Install MySQL:

```bash
sudo apt update
sudo apt install -y mysql-server
```

By default, MySQL may listen only on localhost. Change it to listen on the database VM's private address:

```bash
sudo sed -i 's/^bind-address.*/bind-address = 192.168.56.20/' /etc/mysql/mysql.conf.d/mysqld.cnf
sudo systemctl restart mysql
sudo systemctl enable mysql
```

Create the WordPress database and a user that can connect only from the web server. Replace the example password with a strong password and remember it for `wp-config.php`:

```bash
sudo mysql <<'SQL'
CREATE DATABASE wordpress DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'wpuser'@'192.168.56.10' IDENTIFIED BY 'ChangeThisToAStrongPassword!';
GRANT ALL PRIVILEGES ON wordpress.* TO 'wpuser'@'192.168.56.10';
FLUSH PRIVILEGES;
SQL
```

Allow TCP port 3306 only from the web VM. If UFW is enabled, run:

```bash
sudo ufw allow from 192.168.56.10 to any port 3306 proto tcp
sudo ufw enable
sudo ufw status
```

Verify that MySQL is listening on the private address:

```bash
sudo ss -lntp | grep 3306
```

## 3. Test the database connection from the web server

Connect to the web VM:

```bash
vagrant ssh web
```

Install the MySQL client and test the private-network connection:

```bash
sudo apt update
sudo apt install -y mysql-client
mysql -h 192.168.56.20 -u wpuser -p wordpress
```

Enter the password created on the database server. At the MySQL prompt, run `SHOW TABLES;`; it should work even though the database is currently empty. Leave MySQL with `exit`.

If the connection fails, check the VM addresses, the database `bind-address`, the UFW rule, and the MySQL user host (`'wpuser'@'192.168.56.10'`).

## 4. Install Apache, PHP, and WordPress on the web server

Install Apache, PHP, and the extensions required by WordPress:

```bash
sudo apt install -y apache2 php libapache2-mod-php php-mysql php-curl \
  php-gd php-mbstring php-xml php-xmlrpc php-soap php-intl php-zip unzip curl
sudo systemctl enable --now apache2
```

Download and install WordPress:

```bash
cd /tmp
curl -O https://wordpress.org/latest.tar.gz
tar -xzf latest.tar.gz
sudo rm -rf /var/www/wordpress
sudo mv wordpress /var/www/wordpress
sudo chown -R www-data:www-data /var/www/wordpress
sudo find /var/www/wordpress -type d -exec chmod 755 {} \;
sudo find /var/www/wordpress -type f -exec chmod 644 {} \;
```

Create an Apache virtual host. This example serves WordPress at the web VM's IP address:

```bash
sudo tee /etc/apache2/sites-available/wordpress.conf >/dev/null <<'APACHE'
<VirtualHost *:80>
    ServerName 192.168.56.10
    DocumentRoot /var/www/wordpress

    <Directory /var/www/wordpress>
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog ${APACHE_LOG_DIR}/wordpress_error.log
    CustomLog ${APACHE_LOG_DIR}/wordpress_access.log combined
</VirtualHost>
APACHE

sudo a2dissite 000-default.conf
sudo a2enmod rewrite
sudo a2ensite wordpress.conf
sudo apache2ctl configtest
sudo systemctl reload apache2
```

If UFW is enabled on the web VM, permit HTTP traffic:

```bash
sudo ufw allow 80/tcp
sudo ufw enable
```

## 5. Complete the WordPress setup

From the host computer, open:

<http://192.168.56.10>

Select a language and enter these database settings:

| WordPress field | Value |
|---|---|
| Database Name | `wordpress` |
| Username | `wpuser` |
| Password | The password created on the database VM |
| Database Host | `192.168.56.20` |
| Table Prefix | `wp_` |

Continue the installer, choose a site title, create the administrator account, and log in at:

<http://192.168.56.10/wp-admin>

WordPress will write the database connection settings to `/var/www/wordpress/wp-config.php`. Protect the file after installation:

```bash
sudo chown www-data:www-data /var/www/wordpress/wp-config.php
sudo chmod 640 /var/www/wordpress/wp-config.php
```

## 6. Optional local hostname

To use a friendly local name instead of the IP address, add this line to the **host computer's** hosts file:

```text
192.168.56.10 wordpress.local
```

The hosts file is `/etc/hosts` on Linux and macOS, and `C:\Windows\System32\drivers\etc\hosts` on Windows. Then open:

<http://wordpress.local>

If you use the hostname in Apache, set `ServerName wordpress.local` and reload Apache. Do not put the database IP in the browser; `192.168.56.20` is only for the web server's MySQL connection.

## 7. Verify the architecture

On the web VM, verify Apache and PHP:

```bash
systemctl is-active apache2
php -v
curl -I http://192.168.56.10
```

On the database VM, verify MySQL:

```bash
systemctl is-active mysql
sudo ss -lntp | grep 3306
```

From the web VM, verify that port 3306 is reachable:

```bash
nc -vz 192.168.56.20 3306
```

The expected traffic flow is:

```text
Browser -> 192.168.56.10:80 -> Apache/PHP/WordPress
                                      |
                                      +-> 192.168.56.20:3306 -> MySQL/wordpress
```

## Troubleshooting

### “Error establishing a database connection”

Check the following:

```bash
# On the web VM
mysql -h 192.168.56.20 -u wpuser -p wordpress

# On the database VM
sudo systemctl status mysql
sudo journalctl -u mysql --no-pager -n 50
grep bind-address /etc/mysql/mysql.conf.d/mysqld.cnf
```

Ensure that the database user is created as `wpuser` from `192.168.56.10`, not only as `wpuser` from `localhost`.

### Apache shows a blank page or HTTP 500

Inspect the Apache and PHP logs:

```bash
sudo tail -f /var/log/apache2/wordpress_error.log
sudo apache2ctl configtest
```

### The browser cannot reach the site

Confirm that the web VM is running, that its private IP is `192.168.56.10`, and that port 80 is allowed:

```bash
ip addr
sudo ufw status
curl http://192.168.56.10
```

## Stopping and removing the lab

To stop the Vagrant VMs while keeping their disks:

```bash
vagrant halt
```

To remove the VMs and all data stored inside them:

```bash
vagrant destroy
```
