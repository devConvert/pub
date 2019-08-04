#!/bin/bash

NGINX_PASS=$1
IS_MYSQL=$2
MYSQL_PASS=$3
IS_WORDPRESS=$4


# enable nginx to write files
sudo setenforce 0

# set up public html dir and dir for ssl files
sudo mkdir /var/www
sudo mkdir /var/www/html
sudo mkdir /etc/ssl
sudo mkdir /etc/ssl/server

# enable epel
sudo yum install -y epel-release

# update latest yum
sudo rpm -Uvh https://mirror.webtatic.com/yum/el7/webtatic-release.rpm

# install php on nginx
sudo yum install -y git vim htop nginx php70w php70w-bcmath php70w-cli php70w-common php70w-fpm php70w-mbstring php70w-mcrypt php70w-mysql php70w-xml unzip wget p7zip sysstat

sudo rm /etc/nginx/nginx.conf
sudo rm /etc/nginx/conf.d/localhost_https.conf.disabled

# configure nginx conf file
sudo cat >>/etc/nginx/nginx.conf<<EOF
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /var/run/nginx.pid;

include /usr/share/nginx/modules/*.conf;

events {
    worker_connections 1024;
}

http {

    sendfile            on;
    tcp_nopush          on;
    tcp_nodelay         on;
    keepalive_timeout   65;
    types_hash_max_size 2048;

    include             /etc/nginx/mime.types;
    default_type        application/octet-stream;

    include /etc/nginx/conf.d/*.conf;

    index   index.html index.htm;

    server {
        listen       80 default_server;
        listen       [::]:80 default_server;
        server_name  localhost;
        root         /var/www/html;

        include /etc/nginx/default.d/*.conf;

        location / {
            root     /var/www/html;
            index    index.php index.htm index.html;
            # try_files $uri $uri/ /index.php?$args;
        }

        location ~ \.php$ {
            fastcgi_pass    unix:/var/run/php-fpm/php-fpm.sock;
            fastcgi_index   index.php;
            fastcgi_param   SCRIPT_FILENAME  /var/www/html\$fastcgi_script_name;
            include         fastcgi_params;
        }

        error_page 404 /404.html;
            location = /40x.html {
        }

        error_page 500 502 503 504 /50x.html;
            location = /50x.html {
        }

    }

}
EOF

sudo cat >>/etc/nginx/conf.d/localhost_https.conf.disabled<<EOF
server {

	listen       443 ssl http2 default_server;
	listen       [::]:443 ssl http2 default_server;
	server_name  localhost;
	root         /var/www/html;

	ssl    on;
	ssl_certificate    /etc/ssl/server/domain.crt;
	ssl_certificate_key    /etc/ssl/server/domain.key;

	location / {
			root     /var/www/html;
			index    index.php index.htm index.html;
			# try_files $uri $uri/ /index.php?$args;
	}

	location ~ \.php$ {
		fastcgi_pass    unix:/var/run/php-fpm/php-fpm.sock;
		fastcgi_index   index.php;
		fastcgi_param   SCRIPT_FILENAME  /var/www/html\$fastcgi_script_name;
		include         fastcgi_params;
	}

	error_page 404 /404.html;
		location = /40x.html {
	}

	error_page 500 502 503 504 /50x.html;
		location = /50x.html {
	}

}
EOF

sudo chmod 644 /etc/nginx/nginx.conf
sudo chmod 644 /etc/nginx/conf.d/localhost_https.conf.disabled

# configure php-fpm conf file
sudo sed -i 's/user \= apache/user \= nginx/g' /etc/php-fpm.d/www.conf
sudo sed -i 's/group \= apache/group \= nginx/g' /etc/php-fpm.d/www.conf
sudo sed -i 's/listen \= 127.0.0.1:9000/listen \= \/var\/run\/php-fpm\/php-fpm.sock/g' /etc/php-fpm.d/www.conf
sudo sed -i 's/;listen.owner \= nobody/listen.owner \= nginx/g' /etc/php-fpm.d/www.conf
sudo sed -i 's/;listen.group \= nobody/listen.group \= nginx/g' /etc/php-fpm.d/www.conf
sudo sed -i 's/;listen.mode \= 0660/listen.mode \= 0664/g' /etc/php-fpm.d/www.conf

# set up creds
#sudo groupadd devgroup
#sudo usermod -a -G devgroup nginx
sudo chmod 775 /var/www/html
sudo chown nginx:nginx /var/lib/php/session

# open http/https ports on firewall
sudo firewall-cmd --add-service=http --permanent
sudo firewall-cmd --add-service=https --permanent
sudo firewall-cmd --reload

# start the webserver
sudo service nginx start
sudo service php-fpm start 
sudo service sysstat restart

# start service on reboot
sudo chkconfig nginx on
sudo chkconfig php-fpm on
sudo chkconfig sysstat on

# setup ssh login for the nginx user (starting the nginx service have already created the user/group)
sudo service nginx stop
sudo service php-fpm stop

cat >/root/nginx_crypt.pl<<EOF
#!/usr/bin/perl
use strict;
use warnings;
open(my \$fh, '>', '/root/nginx_enc_pass');
print \$fh crypt("$NGINX_PASS", "123abc");
close \$fh;
EOF

sudo chmod +x /root/nginx_crypt.pl
/root/nginx_crypt.pl
sudo rm /root/nginx_crypt.pl

sudo usermod -s /bin/bash -d /var/www -p $(cat /root/nginx_enc_pass) nginx
sudo rm /root/nginx_enc_pass
echo 'AllowUsers root nginx' >> /etc/ssh/sshd_config
sudo service sshd reload

sudo service nginx start
sudo service php-fpm start

if [ $IS_MYSQL = "Yes" ]; then

	sudo rpm -ivh https://dev.mysql.com/get/mysql57-community-release-el7-10.noarch.rpm
	sudo yum install -y mysql-community-server
	sudo mysqld --initialize
	sudo chown mysql:mysql -R /var/lib/mysql

	sudo service mysqld start

	mysql -u root -p$(sudo awk '/A tempo/{print $11}' /var/log/mysqld.log | awk  'END{print $0}') -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$MYSQL_PASS'" --connect-expired-password
	mysql -u root -p$MYSQL_PASS -e "update mysql.user set host='%' where host='localhost' and user='root'"
	mysql -u root -p$MYSQL_PASS -e "create schema wordpress"
	mysql -u root -p$MYSQL_PASS -e "flush privileges"

	sudo firewall-cmd --add-service=mysql --permanent
	sudo firewall-cmd --reload

	sudo service mysqld stop
	sudo service mysqld start
	
	sudo chkconfig mysqld on

fi

if [ $IS_WORDPRESS = "Yes" ]; then

	sudo wget https://wordpress.org/latest.zip -P /var/www/html
	sudo unzip /var/www/html/latest.zip -d /var/www/html
	sudo rm /var/www/html/latest.zip
	sudo cp -a /var/www/html/wordpress/* /var/www/html
	sudo rm -R /var/www/html/wordpress

	sudo cat >>/var/www/html/wp-config.php<<EOF
<?php
define('DB_NAME', 'wordpress');
define('DB_USER', 'root');
define('DB_PASSWORD', '$MYSQL_PASS');
define('DB_HOST', 'localhost');
define('DB_CHARSET', 'utf8mb4');
define('DB_COLLATE', '');
define('AUTH_KEY',         '11111111111111111111111111111111111111111111111111111111111111111111');
define('SECURE_AUTH_KEY',  '22222222222222222222222222222222222222222222222222222222222222222222');
define('LOGGED_IN_KEY',    '33333333333333333333333333333333333333333333333333333333333333333333');
define('NONCE_KEY',        '44444444444444444444444444444444444444444444444444444444444444444444');
define('AUTH_SALT',        '55555555555555555555555555555555555555555555555555555555555555555555');
define('SECURE_AUTH_SALT', '66666666666666666666666666666666666666666666666666666666666666666666');
define('LOGGED_IN_SALT',   '77777777777777777777777777777777777777777777777777777777777777777777');
define('NONCE_SALT',       '88888888888888888888888888888888888888888888888888888888888888888888');
\$table_prefix  = 'wp_';
define('WP_DEBUG', false);
if ( !defined('ABSPATH') )
		define('ABSPATH', dirname(__FILE__) . '/');
require_once(ABSPATH . 'wp-settings.php');
EOF

	sudo sed -i 's/# try_files \$uri/try_files \$uri/g' /etc/nginx/nginx.conf
	sudo sed -i 's/# try_files \$uri/try_files \$uri/g' /etc/nginx/conf.d/localhost_https.conf.disabled
	
	sudo service nginx reload

fi

# fix nginx creds
sudo chown -R nginx:nginx /var/www/html

# report v1
sudo wget https://raw.githubusercontent.com/devConvert/pub/master/report_v1.sh -O /root/report_v1.sh -q
sudo chmod u+x /root/report_v1.sh
sudo ln -sf /root/report_v1.sh /root/report.sh

# update os to latest kernel
sudo yum update -y

# enable nginx to write files
sudo setenforce 0

# notify we finished init
curl http://crm.convertial.com/ws/1/machine/init_machine_finish
