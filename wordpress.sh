#!/bin/bash
# v2ray centos7/8 WordPress一键安装脚本
# Author: hijk<https://hijk.art>

echo "#############################################################"
echo "#             CentOS 7/8 WordPress一键安装脚本                #"
echo "# 网址: https://hijk.art                                  #"
echo "# 作者: hijk                                                #"
echo "#############################################################"
echo ""

red='\033[0;31m'
green="\033[0;32m"
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

function checkV2()
{
    echo "该脚本仅适用于 https://hijk.art 网站的v2ray带伪装一键脚本 安装wordpress用！"
    read -p "退出请按n，按其他键继续：" answer
    [ "$answer" = "n" ] && exit 0

    if [ ! -f /etc/v2ray/config.json ]; then
        echo "未安装v2ray"
        exit 1
    fi
    domain=`cat /etc/v2ray/config.json | grep Host | cut -d: -f2 | tr -d \",' '`
    if [ "$domain" = "" ]; then
        echo "未检测到配置了ws协议的v2ray"
        exit 1
    fi
    if [ ! -f /etc/nginx/conf.d/${domain}.conf ]; then
        echo "未找到域名的nginx配置文件"
        exit 1
    fi
}

function installPHP()
{
    yum install -y epel-release
    if [ $main -eq 7 ]; then
        rpm -iUh https://rpms.remirepo.net/enterprise/remi-release-7.rpm
	    sed -i '0,/enabled=0/{s/enabled=0/enabled=1/}' /etc/yum.repos.d/remi-php74.repo
    else
        rpm -iUh https://rpms.remirepo.net/enterprise/remi-release-8.rpm
        sed -i '0,/enabled=0/{s/enabled=0/enabled=1/}' /etc/yum.repos.d/remi.repo
        dnf module install -y php:remi-7.4
    fi
    yum install -y php-cli php-fpm php-bcmath php-gd php-mbstring php-mysqlnd php-pdo php-opcache php-xml php-pecl-zip
    systemctl enable php-fpm.service
}

function installMysql()
{
    yum remove -y MariaDB-server
    rm -rf /var/lib/mysql
    if [ ! -f /etc/yum.repos.d/mariadb.repo ]; then
    	if [ $main -eq 7 ]; then
    	echo '# MariaDB 10.4 CentOS repository list - created 2019-11-23 15:00 UTC
# http://downloads.mariadb.org/mariadb/repositories/
[mariadb]
name = MariaDB
baseurl = http://yum.mariadb.org/10.4/centos7-amd64
gpgkey=https://yum.mariadb.org/RPM-GPG-KEY-MariaDB
gpgcheck=1' >> /etc/yum.repos.d/mariadb.repo
	else
echo '# MariaDB 10.4 CentOS repository list - created 2020-03-11 16:29 UTC
# http://downloads.mariadb.org/mariadb/repositories/
[mariadb]
name = MariaDB
baseurl = http://yum.mariadb.org/10.4/centos8-amd64
module_hotfixes=1
gpgkey=https://yum.mariadb.org/RPM-GPG-KEY-MariaDB
gpgcheck=1' >>  /etc/yum.repos.d/mariadb.repo
	fi
    fi
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
    rm -rf /var/www/$domain
    mv wordpress /var/www/$domain
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

    # config wordpress
    cd /var/www/$domain
    cp wp-config-sample.php wp-config.php
    sed -i "s/database_name_here/$dbname/g" wp-config.php
    sed -i "s/username_here/$dbuser/g" wp-config.php
    sed -i "s/password_here/$dbpass/g" wp-config.php
    sed -i "s/utf8/utf8mb4/g" wp-config.php
    perl -i -pe'
  BEGIN {
    @chars = ("a" .. "z", "A" .. "Z", 0 .. 9);
    push @chars, split //, "!@#$%^&*()-_ []{}<>~\`+=,.;:/?|";
    sub salt { join "", map $chars[ rand @chars ], 1 .. 64 }
  }
  s/put your unique phrase here/salt()/ge
' wp-config.php
    chown -R apache:apache /var/www/${domain}

    # config nginx
    sed -i '26,29d' /etc/nginx/conf.d/${domain}.conf
    sed -i '$d' /etc/nginx/conf.d/${domain}.conf
    if [ $main -eq 7 ]; then
        upstream="127.0.0.1:9000"
    else
        upstream="php-fpm"
    fi
    echo "  set \$host_path "/var/www/${domain}";
    root   \$host_path;
    location / {
        index  index.php index.html;
        try_files \$uri \$uri/ /index.php?\$args;
    }
    location ~ ^/\.user\.ini {
            deny all;
    }

    location ~ \.php$ {
        try_files \$uri =404;
        fastcgi_index index.php;
        fastcgi_pass   $upstream;
        include fastcgi_params;
        fastcgi_param  SCRIPT_FILENAME  \$document_root\$fastcgi_script_name;
    }
}" >> /etc/nginx/conf.d/${domain}.conf

    # restart service
    systemctl restart php-fpm mariadb nginx
}

function info()
{
    echo "WordPress安装成功！"
    echo "==============================="
    echo -e "WordPress安装路径：${red}/var/www/${domain}${plain}"
    echo -e "WordPress数据库：${red}${dbname}${plain}"
    echo -e "WordPress数据库用户名：${red}${dbuser}${plain}"
    echo -e "WordPress数据库密码：${red}${dbpass}${plain}"
    echo -e "博客访问地址：${red}https://${domain}${plain}"
    echo "==============================="
}

function main()
{
    checkSystem
    checkV2
    installPHP
    installMysql
    installWordPress

    config

    info
}

main
