#!/bin/bash
# trojan WordPress一键安装脚本
# Author: hijk<https://hijk.art>


RED="\033[31m"      # Error message
GREEN="\033[32m"    # Success message
YELLOW="\033[33m"   # Warning message
BLUE="\033[36m"     # Info message
PLAIN='\033[0m'

CONFIG_FILE=/usr/local/etc/trojan/config.json

BT="false"
NGINX_CONF_PATH="/etc/nginx/conf.d/"
res=$(command -v bt)
if [[ "$res" != "" ]]; then
    BT="true"
    NGINX_CONF_PATH="/www/server/panel/vhost/nginx/"
fi

colorEcho() {
    echo -e "${1}${@:2}${PLAIN}"
}

checkSystem() {
    uid=$(id -u)
    if [[ $uid -ne 0 ]]; then
        colorEcho $RED " 请以root身份执行该脚本"
        exit 1
    fi

    res=$(command -v yum)
    if [[ "$res" = "" ]]; then
        res=$(command -v apt)
        if [[ "$res" = "" ]]; then
            colorEcho $RED " 不受支持的Linux系统"
            exit 1
        fi
        PMT="apt"
        CMD_INSTALL="apt install -y "
        CMD_REMOVE="apt remove -y "
        CMD_UPGRADE="apt update; apt upgrade -y; apt autoremove -y"
        PHP_SERVICE="php7.4-fpm"
    else
        PMT="yum"
        CMD_INSTALL="yum install -y "
        CMD_REMOVE="yum remove -y "
        CMD_UPGRADE="yum update -y"
        PHP_SERVICE="php-fpm"
        result=`grep -oE "[0-9.]+" /etc/centos-release`
        MAIN=${result%%.*}
    fi
    res=$(command -v systemctl)
    if [[ "$res" = "" ]]; then
        colorEcho $RED " 系统版本过低，请升级到最新版本"
        exit 1
    fi
}

checkTrojan() {
    if [ ! -f ${CONFIG_FILE} ]; then
        colorEcho $RED " 未安装trojan"
        exit 1
    fi
    DOMAIN=`grep sni $CONFIG_FILE | cut -d: -f2 | tr -d \",' '`
    NGINX_CONFIG_FILE="$NGINX_CONF_PATH${DOMAIN}.conf"
    if [[ ! -f $NGINX_CONFIG_FILE ]]; then
        colorEcho $RED " 未找到域名的nginx配置文件"
        exit 1
    fi
    PORT=`grep local_port $CONFIG_FILE | cut -d: -f2 | tr -d \",' '`
    [[ "$1" = "install" ]] && colorEcho $BLUE " 伪装域名：$DOMAIN"
    [[ "$1" = "install" ]] && colorEcho $BLUE " trojan监听端口：$PORT"
}

statusText() {
    res=$(command -v nginx)
    if [[ "$res" = "" ]]; then
        echo -e -n ${RED}Nginx未安装${PLAIN}
    else
        res=`ps aux | grep nginx | grep -v grep`
        [[ "$res" = "" ]] && echo -e -n ${RED}Nginx未运行${PLAIN} || echo -e -n ${GREEN}Nginx正在运行${PLAIN}
    fi
    echo -n ", "
    res=$(command -v php)
    if [[ "$res" = "" ]]; then
        echo -e -n ${RED}PHP未安装${PLAIN}
    else
        res=`ps aux | grep php | grep -v grep`
        [[ "$res" = "" ]] && echo -e -n ${RED}PHP未运行${PLAIN} || echo -e -n ${GREEN}PHP正在运行${PLAIN}
    fi
    echo -n ", "
    res=$(command -v mysql)
    if [[ "$res" = "" ]]; then
        echo -e -n ${RED}Mysql未安装${PLAIN}
    else
        res=`ps aux | grep mysql | grep -v grep`
        [[ "$res" = "" ]] && echo -e -n ${RED}Mysql未运行${PLAIN} || echo -e -n ${GREEN}Mysql正在运行${PLAIN}
    fi
}

installPHP() {
    [[ "$PMT" = "apt" ]] && $PMT update
    $CMD_INSTALL curl wget ca-certificates
    if [[ "$PMT" = "yum" ]]; then 
        $CMD_INSTALL epel-release
        if [[ $MAIN -eq 7 ]]; then
            rpm -iUh https://rpms.remirepo.net/enterprise/remi-release-7.rpm
            sed -i '0,/enabled=0/{s/enabled=0/enabled=1/}' /etc/yum.repos.d/remi-php74.repo
        else
            dnf install https://rpms.remirepo.net/enterprise/remi-release-8.rpm
            sed -i '0,/enabled=0/{s/enabled=0/enabled=1/}' /etc/yum.repos.d/remi.repo
            dnf module install -y php:remi-7.4
        fi
        $CMD_INSTALL php-cli php-fpm php-bcmath php-gd php-mbstring php-mysqlnd php-pdo php-opcache php-xml php-pecl-zip  php-pecl-imagick
    else
        $CMD_INSTALL lsb-release gnupg2
        wget -q https://packages.sury.org/php/apt.gpg -O- | apt-key add -
        echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/php7.list
        $PMT update
        $CMD_INSTALL php7.4-cli php7.4-fpm php7.4-bcmath php7.4-gd php7.4-mbstring php7.4-mysql php7.4-opcache php7.4-xml php7.4-zip php7.4-json php7.4-imagick
        update-alternatives --set php /usr/bin/php7.4
    fi
    systemctl enable $PHP_SERVICE
}

installMysql() {
    if [[ "$PMT" = "yum" ]]; then 
        yum remove -y MariaDB-server
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
    else
        $PMT update
        $CMD_INSTALL mariadb-server
    fi
    systemctl enable mariadb.service
}

installWordPress() {
    mkdir -p /var/www
    wget https://cn.wordpress.org/latest-zh_CN.tar.gz
    if [[ ! -f latest-zh_CN.tar.gz ]]; then
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
    #sed -i "1a \$_SERVER['HTTPS']='on';" index.php
    perl -i -pe'
  BEGIN {
    @chars = ("a" .. "z", "A" .. "Z", 0 .. 9);
    push @chars, split //, "!@#$%^&*()-_ []{}<>~\`+=,.;:/?|";
    sub salt { join "", map $chars[ rand @chars ], 1 .. 64 }
  }
  s/put your unique phrase here/salt()/ge
' wp-config.php
    if [[ "$PMT" = "yum" ]]; then
        user="apache"
        # config nginx
        [[ $MAIN -eq 7 ]] && upstream="127.0.0.1:9000" || upstream="php-fpm"
    else
        user="www-data"
        upstream="unix:/run/php/php7.4-fpm.sock"
    fi
    chown -R $user:$user /var/www/${DOMAIN}
    # config nginx
    cat > $NGINX_CONFIG_FILE<<-EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};
    return 301 https://\$server_name:${PORT}\$request_uri;
}
server {
    listen 8080;
    listen 81 http2;
    server_name ${DOMAIN};
    
    charset utf-8;
    
    set \$host_path "/var/www/${DOMAIN}";
    access_log  /var/log/nginx/${DOMAIN}.access.log  main buffer=32k flush=30s;
    error_log /var/log/nginx/${DOMAIN}.error.log;
    root   \$host_path;
    location / {
        index  index.php index.html;
        try_files \$uri \$uri/ /index.php?\$args;
    }
    location ~ \.php\$ {
        try_files \$uri =404;
        fastcgi_index index.php;
        fastcgi_pass $upstream;
        include fastcgi_params;
        fastcgi_param  SCRIPT_FILENAME  \$document_root\$fastcgi_script_name;
	    fastcgi_param  SERVER_PORT	${PORT};
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
    systemctl restart $PHP_SERVICE mariadb nginx trojan
}

install() {
    checkTrojan "install"
    installPHP
    installMysql
    installWordPress
    colorEcho $BLUE " WordPress安装成功！"

    config
    # restart service
    systemctl restart $PHP_SERVICE mariadb nginx

    sleep 2
    statusText
    echo ""
    
    showInfo
}

uninstall() {
    echo ""
    colorEcho $RED " 该操作会删除所有WordPress文件，清空数据库！"
    read -p " 确认卸载WordPress？[y/n]" answer
    [[ "$answer" != "y" && "$answer" != "Y" ]] && exit 0

    checkTrojan
    systemctl stop mariadb
    systemctl disable mariadb
    if [[ "$PMT" = "yum" ]]; then
        $CMD_REMOVE MariaDB-server
    else
        apt-get purge -y mariadb-*
    fi
    rm -rf /var/lib/mysql

    systemctl stop $PHP_SERVICE
    systemctl disable $PHP_SERVICE

    rm -rf /var/www/${DOMAIN}

    colorEcho $GREEN " 卸载成功！"
}

showInfo() {
    checkTrojan

    if [[ -z ${DBNAME+x} ]]; then
        wpconfig="/var/www/${DOMAIN}/wp-config.php"
        DBUSER=`grep DB_USER $wpconfig | cut -d, -f2 | cut -d\) -f1 | tr -d \",\'' '`
        DBNAME=`grep DB_NAME $wpconfig | cut -d, -f2 | cut -d\) -f1 | tr -d \",\'' '`
        DBPASS=`grep DB_PASSWORD $wpconfig | cut -d, -f2 | cut -d\) -f1 | tr -d \",\'' '`
    fi
    if [[ "$PORT" = "443" ]]; then
        url="https://$DOMAIN"
    else
        url="https://$DOMAIN:$PORT"
    fi
    colorEcho $BLUE " WordPress配置信息："
    echo "==============================="
    echo -e "   ${BLUE}WordPress安装路径：${PLAIN}${RED}/var/www/${DOMAIN}${PLAIN}"
    echo -e "   ${BLUE}WordPress数据库：${PLAIN}${RED}${DBNAME}${PLAIN}"
    echo -e "   ${BLUE}WordPress数据库用户名：${PLAIN}${RED}${DBUSER}${PLAIN}"
    echo -e "   ${BLUE}WordPress数据库密码：${PLAIN}${RED}${DBPASS}${PLAIN}"
    echo -e "   ${BLUE}WordPress网址：${PLAIN}${RED}$url${PLAIN}"
    echo "==============================="
}

help() {
    echo ""
    colorEcho $BLUE "  Nginx操作："
    colorEcho $GREEN "    启动: systemctl start nginx"
    colorEcho $GREEN "    停止：systemctl stop nginx"
    colorEcho $GREEN "    重启：systemctl restart nginx"
    echo " -------------"
    colorEcho $BLUE "  PHP操作："
    colorEcho $GREEN "    启动: systemctl start $PHP_SERVICE"
    colorEcho $GREEN "    停止：systemctl stop $PHP_SERVICE"
    colorEcho $GREEN "    重启：systemctl restart $PHP_SERVICE"
    echo " -------------"
    colorEcho $BLUE "  Mysql操作："
    colorEcho $GREEN "    启动: systemctl start mariadb"
    colorEcho $GREEN "    停止：systemctl stop mariadb"
    colorEcho $GREEN "    重启：systemctl restart mariadb"
}

menu() {
    clear
    echo "#############################################################"
    echo -e "#                ${RED}WordPress一键安装脚本${PLAIN}                  #"
    echo -e "# ${GREEN}作者${PLAIN}: 网络跳越(hijk)                                      #"
    echo -e "# ${GREEN}网址${PLAIN}: https://hijk.art                                    #"
    echo -e "# ${GREEN}论坛${PLAIN}: https://hijk.club                                   #"
    echo -e "# ${GREEN}TG群${PLAIN}: https://t.me/hijkclub                               #"
    echo -e "# ${GREEN}Youtube频道${PLAIN}: https://youtube.com/channel/UCYTB--VsObzepVJtc9yvUxQ #"
    echo "#############################################################"
    echo 
    colorEcho $YELLOW " 该脚本仅适用于 https://hijk.art 网站上的trojan一键脚本安装wordpress用！"
    echo 
    echo -e "  ${GREEN}1.${PLAIN} 安装WordPress" 
    echo -e "  ${GREEN}2.${PLAIN} 卸载WordPress"
    echo -e "  ${GREEN}3.${PLAIN} 查看WordPress配置"
    echo -e "  ${GREEN}4.${PLAIN} 查看操作帮助"
    echo " -------------"
    echo -e "  ${GREEN}0.${PLAIN} 退出"
    echo -n " 当前状态："
    statusText
    echo 

    echo ""
    read -p " 请选择操作[0-17]：" answer
    case $answer in
        0)
            exit 0
            ;;
        1)
            install
            ;;
        2)
            uninstall
            ;;
        3)
            showInfo
            ;;
        4)
            help
            ;;
        *)
            colorEcho $RED " 请选择正确的操作！"
            exit 1
            ;;
    esac
}

checkSystem

menu
