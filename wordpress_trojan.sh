#!/bin/bash
# centos7/8 trojan WordPress一键安装脚本
# Author: hijk<https://hijk.art>

echo "#############################################################"
echo "#             CentOS 7/8 WordPress一键安装脚本                #"
echo "# 网址: https://hijk.art                                  #"
echo "# 作者: hijk                                                #"
echo "#############################################################"
echo ""

red='\033[0;31m'
plain='\033[0m'

function checkSystem()
{
    result=$(id | awk '{print $1}')
    if [ $result != "uid=0(root)" ]; then
        echo "请以root身份执行该脚本"
        exit 1
    fi

    if [ ! -f /etc/centos-release ];then
        res=`which yum`
        if [ "$?" != "0" ]; then
            echo "系统不是CentOS"
            exit 1
         fi
    else
        result=`cat /etc/centos-release|grep -oE "[0-9.]+"`
        main=${result%%.*}
        if [ $main -lt 7 ]; then
            echo "不受支持的CentOS版本"
            exit 1
         fi
    fi
}

function checkTrojan()
{
    echo "该脚本仅适用于 https://hijk.art 网站的trojan一键脚本 安装wordpress用！"
    read -p "退出请按n，按其他键继续：" answer
    [ "$answer" = "n" ] && exit 0

    if [ ! -f /usr/local/etc/trojan/config.json ]; then
        echo "未安装trojan"
        exit 1
    fi
    CONFIG_FILE=/usr/local/etc/trojan/config.json
    domain=`grep -m1 cert $CONFIG_FILE | awk 'BEGIN { FS = "/" } ; { print $5 }'`
    if [ ! -f /etc/nginx/conf.d/${domain}.conf ]; then
        echo "未找到域名的nginx配置文件"
        exit 1
    fi
}

function installPHP()
{
    rpm -iUh https://rpms.remirepo.net/enterprise/remi-release-${main}.rpm
    if [ $main -eq 7 ]; then
	    sed -i '0,/enabled=0/{s/enabled=0/enabled=1/}' /etc/yum.repos.d/remi-php74.repo
    else
        sed -i '0,/enabled=0/{s/enabled=0/enabled=1/}' /etc/yum.repos.d/remi.repo
        dnf module install -y php:remi-7.4
    fi
    yum install -y php-cli php-fpm php-bcmath php-gd php-mbstring php-mysqlnd php-pdo php-opcache php-xml php-pecl-zip
    systemctl enable php-fpm.service
}

function installMysql()
{
    echo "# MariaDB 10.4 CentOS repository list
# http://downloads.mariadb.org/mariadb/repositories/
[mariadb]
name = MariaDB
baseurl = http://yum.mariadb.org/10.4/centos${main}-amd64
gpgkey=https://yum.mariadb.org/RPM-GPG-KEY-MariaDB
gpgcheck=1" > /etc/yum.repos.d/mariadb.repo
    if [ $main -eq 8 ]; then
        echo "module_hotfixes=1" >>  /etc/yum.repos.d/mariadb.repo
    fi

    yum remove -y MariaDB-server
    rm -rf /var/lib/mysql
    yum install -y MariaDB-server
    systemctl enable mariadb.service
}

function installWordPress()
{
    yum install -y wget
    mkdir -p /var/www;
    wget https://cn.wordpress.org/latest-zh_CN.tar.gz
    if [ ! -f latest-zh_CN.tar.gz ]; then
    	echo "下载WordPress失败，请稍后重试"
	exit 1
    fi
    tar -zxf latest-zh_CN.tar.gz
    rm -rf /var/www/${domain}
    mv wordpress /var/www/${domain}
    rm -rf latest-zh_CN.tar.gz
}

function config()
{
    # config mariadb
    systemctl start mariadb
    dbname="wordpress"
    dbuser="wordpress"
    dbpass=`cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1`
    mysql -uroot <<EOF
DELETE FROM mysql.user WHERE User='';
CREATE DATABASE $dbname default charset utf8mb4;
CREATE USER ${dbuser}@'%' IDENTIFIED BY '${dbpass}';
GRANT ALL PRIVILEGES ON ${dbname}.* to ${dbuser}@'%';
FLUSH PRIVILEGES;
EOF

    #config php
    sed -i 's/expose_php = On/expose_php = Off/' /etc/php.ini
    line=`cat -n /etc/php.ini | grep 'date.timezone' | tail -n1 | awk '{print $1}'`
    sed -i "${line}a date.timezone = Asia/Shanghai" /etc/php.ini
    sed -i 's/;opcache.revalidate_freq=2/opcache.revalidate_freq=30/' /etc/php.d/10-opcache.ini
    if [ $main -eq 7 ]; then
        sed -i 's/listen = 127.0.0.1:9000/listen = \/run\/php-fpm\/www.sock/' /etc/php-fpm.d/www.conf
    fi
    line=`cat -n /etc/php-fpm.d/www.conf | grep 'listen.mode' | tail -n1 | awk '{print $1}'`
    sed -i "${line}a listen.mode=0666" /etc/php-fpm.d/www.conf

    port=`cat $CONFIG_FILE | grep local_port | cut -d: -f2 | tr -d \",' '`
    # config wordpress
    cd /var/www/$domain
    cp wp-config-sample.php wp-config.php
    sed -i "s/database_name_here/$dbname/g" wp-config.php
    sed -i "s/username_here/$dbuser/g" wp-config.php
    sed -i "s/password_here/$dbpass/g" wp-config.php
    sed -i "s/utf8/utf8mb4/g" wp-config.php
    #sed -i "1a \$_SERVER['HTTPS']='on';" index.php
    perl -i -pe'
  BEGIN {
    @chars = ("a" .. "z", "A" .. "Z", 0 .. 9);
    push @chars, split //, "!@#$%^&*()-_ []{}<>~\`+=,.;:/?|";
    sub salt { join "", map $chars[ rand @chars ], 1 .. 64 }
  }
  s/put your unique phrase here/salt()/ge
' wp-config.php
    #sed -i "23a define( 'WP_HOME', 'https://${domain}:${port}' );" wp-config.php
    #sed -i "24a define( 'WP_SITEURL', 'https://${domain}:${port}' );" wp-config.php

    chown -R apache:apache /var/www/$domain

    # config nginx
    cat > /etc/nginx/conf.d/${domain}.conf<<-EOF
server {
    listen 80;
    server_name ${domain};
    return 301 https://\$server_name:${port}\$request_uri;
}
server {
    listen 8080;
    server_name ${domain};
    
    charset utf-8;
    
    set \$host_path "/var/www/${domain}";
    access_log  /var/log/nginx/${domain}.access.log  main buffer=32k flush=30s;
    error_log /var/log/nginx/${domain}.error.log;
    root   \$host_path;
    location / {
        index  index.php index.html;
        try_files \$uri \$uri/ /index.php?\$args;
    }
    location ~ \.php\$ {
        try_files \$uri =404;
        fastcgi_index index.php;
        fastcgi_pass unix:/run/php-fpm/www.sock;
        include fastcgi_params;
        fastcgi_param  SCRIPT_FILENAME  \$document_root\$fastcgi_script_name;
	fastcgi_param  SERVER_PORT	${port};
	fastcgi_param  HTTPS		"on";
    }
    location ~ \.(js|css|png|jpg|jpeg|gif|ico|swf|webp|pdf|txt|doc|docx|xls|xlsx|ppt|pptx|mov|fla|zip|rar)\$ {
        expires max;
        access_log off;
        try_files \$uri =404;
    }
}
EOF

    # config trojan
    sed -i -e "s/remote_addr\":\s*\".*\",/remote_addr\": \"127.0.0.1\",/" $CONFIG_FILE
    sed -i -e "s/remote_port\":\s*[0-9]*/remote_port\": 8080/" $CONFIG_FILE

    # restart service
    systemctl restart php-fpm mariadb nginx trojan
}

function info()
{
    echo "WordPress安装成功！"
    echo "==============================="
    echo -e "WordPress安装路径：${red}/var/www/${domain}${plain}"
    echo -e "WordPress数据库：${red}${dbname}${plain}"
    echo -e "WordPress数据库用户名：${red}${dbuser}${plain}"
    echo -e "WordPress数据库密码：${red}${dbpass}${plain}"
    echo -e "博客访问地址：${red}https://${domain}:${port}${plain}"
    echo "==============================="
}

function main()
{
    checkSystem
    checkTrojan
    installPHP
    installMysql
    installWordPress

    config

    info
}

main
