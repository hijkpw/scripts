#!/bin/bash
# v2ray centos7/8 WordPress一键安装脚本
# Author: hijk<https://hijk.art>

RED="\033[31m"      # Error message
GREEN="\033[32m"    # Success message
YELLOW="\033[33m"   # Warning message
BLUE="\033[36m"     # Info message
PLAIN='\033[0m'

colorEcho() {
    echo -e "${1}${@:2}${PLAIN}"
}

V2_CONFIG_FILE="/etc/v2ray/config.json"

checkSystem() {
    result=$(id | awk '{print $1}')
    if [ $result != "uid=0(root)" ]; then
        colorEcho $RED " 请以root身份执行该脚本"
        exit 1
    fi

    if [ ! -f /etc/centos-release ];then
        res=`which yum`
        if [ "$?" != "0" ]; then
            colorEcho $RED " 系统不是CentOS"
            exit 1
         fi
    else
        result=`cat /etc/centos-release|grep -oE "[0-9.]+"`
        MAIN=${result%%.*}
        if [ $MAIN -lt 7 ]; then
            colorEcho $RED " 不受支持的CentOS版本"
            exit 1
         fi
    fi
}

slogon() {
    clear
    echo "#############################################################"
    echo -e "#             ${RED}CentOS 7/8 WordPress一键安装脚本${PLAIN}                #"
    echo -e "# ${GREEN}作者${PLAIN}: 网络跳越(hijk)                                      #"
    echo -e "# ${GREEN}网址${PLAIN}: https://hijk.art                                    #"
    echo -e "# ${GREEN}论坛${PLAIN}: https://hijk.club                                   #"
    echo -e "# ${GREEN}TG群${PLAIN}: https://t.me/hijkclub                               #"
    echo -e "# ${GREEN}Youtube频道${PLAIN}: https://youtube.com/channel/UCYTB--VsObzepVJtc9yvUxQ #"
    echo "#############################################################"
    echo ""
}

checkV2() {
    colorEcho $YELLOW " 该脚本仅适用于 https://hijk.art 网站的v2ray带伪装一键脚本 安装wordpress用！"
    read -p " 退出请按n，按其他键继续：" answer
    [ "$answer" = "n" ] && exit 0

    if [ ! -f $V2_CONFIG_FILE ]; then
        colorEcho $RED " 未安装v2ray"
        exit 1
    fi
    DOMAIN=`grep Host $V2_CONFIG_FILE | cut -d: -f2 | tr -d \",' '`
    if [ "$DOMAIN" = "" ]; then
        colorEcho $RED " 未检测到配置了ws协议的v2ray"
        exit 1
    fi
    NGINX_CONFIG_FILE="/etc/nginx/conf.d/${DOMAIN}.conf"
    if [ ! -f $NGINX_CONFIG_FILE ]; then
        colorEcho $RED " 未找到域名的nginx配置文件"
        exit 1
    fi
    V2PORT=`grep port $V2_CONFIG_FILE | cut -d: -f2 | tr -d \",' '`
    WSPATH=`grep path $V2_CONFIG_FILE | cut -d: -f2 | tr -d \",' '`
    PORT=`grep -i ssl $NGINX_CONFIG_FILE | grep listen | head -n1 | awk '{print $2}'`
    CERT_FILE=`grep ssl_certificate $NGINX_CONFIG_FILE | grep -v _key`
    KEY_FILE=`grep ssl_certificate_key $NGINX_CONFIG_FILE`
}

installPHP() {
    yum install -y epel-release
    if [ $MAIN -eq 7 ]; then
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

installMysql() {
    yum remove -y MariaDB-server
    rm -rf /var/lib/mysql
    if [ ! -f /etc/yum.repos.d/mariadb.repo ]; then
    	if [ $MAIN -eq 7 ]; then
    	    echo '# MariaDB 10.5 CentOS repository list - created 2019-11-23 15:00 UTC
# http://downloads.mariadb.org/mariadb/repositories/
[mariadb]
name = MariaDB
baseurl = http://yum.mariadb.org/10.5/centos7-amd64
gpgkey=https://yum.mariadb.org/RPM-GPG-KEY-MariaDB
gpgcheck=1' >> /etc/yum.repos.d/mariadb.repo
	    else
            echo '# MariaDB 10.5 CentOS repository list - created 2020-03-11 16:29 UTC
# http://downloads.mariadb.org/mariadb/repositories/
[mariadb]
name = MariaDB
baseurl = http://yum.mariadb.org/10.5/centos8-amd64
module_hotfixes=1
gpgkey=https://yum.mariadb.org/RPM-GPG-KEY-MariaDB
gpgcheck=1' >>  /etc/yum.repos.d/mariadb.repo
	    fi
    fi
    yum install -y MariaDB-server
    systemctl enable mariadb.service
}

installWordPress() {
    yum install -y wget
    mkdir -p /var/www;
    wget https://cn.wordpress.org/latest-zh_CN.tar.gz
    if [ ! -f latest-zh_CN.tar.gz ]; then
    	colorEcho $RED " 下载WordPress失败，请稍后重试"
	    exit 1
    fi
    tar -zxf latest-zh_CN.tar.gz
    rm -rf /var/www/$DOMAIN
    mv wordpress /var/www/$DOMAIN
    rm -rf latest-zh_CN.tar.gz
}

config() {
    # config mariadb
    systemctl start mariadb
    DBNAME="wordpress"
    DBUSER="wordpress"
    DBPASS=`cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1`
    mysql -uroot <<EOF
DELETE FROM mysql.user WHERE User='';
CREATE DATABASE $DBNAME default charset utf8mb4;
CREATE USER ${DBUSER}@'%' IDENTIFIED BY '${DBPASS}';
GRANT ALL PRIVILEGES ON ${DBNAME}.* to ${DBUSER}@'%';
FLUSH PRIVILEGES;
EOF

    # config wordpress
    cd /var/www/$DOMAIN
    cp wp-config-sample.php wp-config.php
    sed -i "s/database_name_here/$DBNAME/g" wp-config.php
    sed -i "s/username_here/$DBUSER/g" wp-config.php
    sed -i "s/password_here/$DBPASS/g" wp-config.php
    sed -i "s/utf8/utf8mb4/g" wp-config.php
    perl -i -pe'
  BEGIN {
    @chars = ("a" .. "z", "A" .. "Z", 0 .. 9);
    push @chars, split //, "!@#$%^&*()-_ []{}<>~\`+=,.;:/?|";
    sub salt { join "", map $chars[ rand @chars ], 1 .. 64 }
  }
  s/put your unique phrase here/salt()/ge
' wp-config.php
    chown -R apache:apache /var/www/${DOMAIN}

    # config nginx
    if [ $MAIN -eq 7 ]; then
        upstream="127.0.0.1:9000"
    else
        upstream="php-fpm"
    fi

    cat > $NGINX_CONFIG_FILE<<-EOF
server {
    listen 80;
    server_name ${DOMAIN};
    return 301 https://\$server_name:${PORT}\$request_uri;
}

server {
    listen       ${PORT} ssl http2;
    server_name ${DOMAIN};
    charset utf-8;

    # ssl配置
    ssl_protocols TLSv1.1 TLSv1.2;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE:ECDH:AES:HIGH:!NULL:!aNULL:!MD5:!ADH:!RC4;
    ssl_ecdh_curve secp384r1;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_session_tickets off;
    $CERT_FILE
    $KEY_FILE

    set \$host_path "/var/www/${DOMAIN}";
    access_log  /var/log/nginx/${DOMAIN}.access.log  main buffer=32k flush=30s;
    error_log /var/log/nginx/${DOMAIN}.error.log;
    root   \$host_path;
    location / {
        index  index.php;
        try_files \$uri \$uri/ /index.php?\$args;
    }
    location ~ \.php\$ {
        try_files \$uri =404;
        fastcgi_index index.php;
        fastcgi_pass $upstream;
        include fastcgi_params;
        fastcgi_param  SCRIPT_FILENAME  \$document_root\$fastcgi_script_name;
    }

    location ${WSPATH} {
      proxy_redirect off;
      proxy_pass http://127.0.0.1:${V2PORT};
      proxy_http_version 1.1;
      proxy_set_header Upgrade \$http_upgrade;
      proxy_set_header Connection "upgrade";
      proxy_set_header Host \$host;
      proxy_set_header X-Real-IP \$remote_addr;
      proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    location ~ \.(js|css|png|jpg|jpeg|gif|ico|swf|webp|pdf|txt|doc|docx|xls|xlsx|ppt|pptx|mov|fla|zip|rar)\$ {
        expires max;
        access_log off;
        try_files \$uri =404;
    }
}
EOF

    # restart service
    systemctl restart php-fpm mariadb nginx
}

info() {
    colorEcho $BLUE " WordPress安装成功！"
    echo "==============================="
    echo -e "   ${BLUE}WordPress安装路径：${PLAIN}${RED}/var/www/${DOMAIN}${PLAIN}"
    echo -e "   ${BLUE}WordPress数据库：${PLAIN}${RED}${DBNAME}${PLAIN}"
    echo -e "   ${BLUE}WordPress数据库用户名：${PLAIN}${RED}${DBUSER}${PLAIN}"
    echo -e "   ${BLUE}WordPress数据库密码：${PLAIN}${RED}${DBPASS}${PLAIN}"
    echo -e "   ${BLUE}博客访问地址：${PLAIN}${RED}https://${DOMAIN}${PLAIN}"
    echo "==============================="
}

main() {
    slogon
    checkSystem
    checkV2
    installPHP
    installMysql
    installWordPress

    config

    info
}

main
