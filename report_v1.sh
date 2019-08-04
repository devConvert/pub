#!/bin/bash

echo start:$(date +"%s") > /root/report.txt

if [ -e /etc/ssl/server/domain.csr ]; then
	echo ssl_csr:$(openssl req -noout -modulus -in /etc/ssl/server/domain.csr | openssl md5 | cut -c10-) >> /root/report.txt
else
	echo ssl_csr:no >> /root/report.txt
fi

if [ -e /etc/ssl/server/domain.key ]; then
	echo ssl_key:$(openssl rsa -noout -modulus -in /etc/ssl/server/domain.key | openssl md5 | cut -c10-) >> /root/report.txt
else
	echo ssl_key:no >> /root/report.txt
fi

if [ -e /etc/ssl/server/domain.crt ]; then
	echo ssl_crt:$(openssl x509 -noout -modulus -in /etc/ssl/server/domain.crt | openssl md5 | cut -c10-) >> /root/report.txt
else
	echo ssl_crt:no >> /root/report.txt
fi

if [ -e /etc/nginx/conf.d/localhost_https.conf.disabled ]; then
	echo ssl_enabled_web_server:no >> /root/report.txt
else
	echo ssl_enabled_web_server:yes >> /root/report.txt
fi

if [ -e /etc/nginx/nginx.conf ]; then
	if [ $(sudo service nginx status | grep "active (running)" | wc -l) -eq 1 ]; then
		echo nginx:running >> /root/report.txt
	else
		echo nginx:shutdown >> /root/report.txt
	fi
else
	echo nginx:no >> /root/report.txt
fi

if [ -e /etc/php-fpm.conf ]; then
	if [ $(sudo service php-fpm status | grep "active (running)" | wc -l) -eq 1 ]; then
		echo php-fpm:running >> /root/report.txt
	else
		echo php-fpm:shutdown >> /root/report.txt
	fi
else
	echo php-fpm:no >> /root/report.txt
fi

if [ -e /usr/bin/php ]; then
	echo php:$(php -v | awk 'NR==1{print $2}') >> /root/report.txt
else
	echo php:no >> /root/report.txt
fi

if [ $(sudo sestatus | grep "permissive" | wc -l) -eq 1 ]; then
	echo php_write_files:yes >> /root/report.txt
else
	echo php_write_files:no >> /root/report.txt
fi

if [ -e /usr/bin/mysql ]; then
	if [ $(sudo service mysqld status | grep "active (running)" | wc -l) -eq 1 ]; then
		echo mysql:running >> /root/report.txt
	else
		echo mysql:shutdown >> /root/report.txt
	fi
else
	echo mysql:no >> /root/report.txt
fi

STATS="$(sar | base64)"
echo sar_b64:$STATS >> /root/report.txt

STATS="$(df | base64)"
echo df_b64:$STATS >> /root/report.txt

STATS="$(free | base64)"
echo free_b64:$STATS >> /root/report.txt

echo end:$(date +"%s") >> /root/report.txt

cat /root/report.txt
