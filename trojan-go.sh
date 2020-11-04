#!/bin/bash
# MTProto一键安装脚本
# Author: hijk<https://hijk.art>


RED="\033[31m"      # Error message
GREEN="\033[32m"    # Success message
YELLOW="\033[33m"   # Warning message
BLUE="\033[36m"     # Info message
PLAIN='\033[0m'

# 以下网站是随机从Google上找到的无广告小说网站，不喜欢请改成其他网址，以http或https开头
# 搭建好后无法打开伪装域名，可能是反代小说网站挂了，请在网站留言，或者Github发issue，以便替换新的网站
SITES=(
http://www.zhuizishu.com/
http://xs.56dyc.com/
http://www.xiaoshuosk.com/
https://www.quledu.net/
http://www.ddxsku.com/
http://www.biqu6.com/
https://www.wenshulou.cc/
http://www.auutea.com/
http://www.55shuba.com/
http://www.39shubao.com/
https://www.23xsw.cc/
)

ZIP_FILE="trojan-go"
CONFIG_FILE="/etc/trojan-go/config.json"

WS="false"

checkSystem() {
    result=$(id | awk '{print $1}')
    if [[ $result != "uid=0(root)" ]]; then
        echo -e " ${RED}请以root身份执行该脚本${PLAIN}"
        exit 1
    fi

    res=`which yum`
    if [[ "$?" != "0" ]]; then
        res=`which apt`
        if [[ "$?" != "0" ]]; then
            echo -e " ${RED}不受支持的Linux系统${PLAIN}"
            exit 1
        fi
        res=`hostnamectl | grep -i ubuntu`
        if [[ "${res}" != "" ]]; then
            OS="ubuntu"
        else
            OS="debian"
        fi
        PMT="apt"
        CMD_INSTALL="apt install -y "
        CMD_REMOVE="apt remove -y "
        CMD_UPGRADE="apt update; apt upgrade -y"
    else
        OS="centos"
        PMT="yum"
        CMD_INSTALL="yum install -y "
        CMD_REMOVE="yum remove -y "
        CMD_UPGRADE="yum update -y"
    fi
    res=`which systemctl`
    if [[ "$?" != "0" ]]; then
        echo -e " ${RED}系统版本过低，请升级到最新版本${PLAIN}"
        exit 1
    fi
}

status() {
    trojan_cmd="$(command -v trojan-go)"
    if [[ "$trojan_cmd" = "" ]]; then
        echo 0
        return
    fi
    if [[ ! -f $CONFIG_FILE ]]; then
        echo 1
        return
    fi
    port=`grep local_port $CONFIG_FILE|cut -d: -f2| tr -d \",' '`
    res=`ss -ntlp| grep ${port} | grep trojan-go`
    if [[ -z "$res" ]]; then
        echo 2
    else
        echo 3
    fi
}

statusText() {
    res=`status`
    case $res in
        2)
            echo -e ${GREEN}已安装${PLAIN} ${RED}未运行${PLAIN}
            ;;
        3)
            echo -e ${GREEN}已安装${PLAIN} ${GREEN}正在运行${PLAIN}
            ;;
        *)
            echo -e ${RED}未安装${PLAIN}
            ;;
    esac
}

getVersion() {
    VERSION=$(curl -fsSL https://api.github.com/repos/p4gefau1t/trojan-go/releases | grep tag_name | sed -E 's/.*"v(.*)".*/\1/'| head -n1)
    if [[ ${VERSION:0:1} != "v" ]];then
        VERSION="v${VERSION}"
    fi
}

archAffix() {
    case "${1:-"$(uname -m)"}" in
        i686|i386)
            echo '386'
        ;;
        x86_64|amd64)
            echo 'amd64'
        ;;
        *armv7*|armv6l)
            echo 'armv7'
        ;;
        *armv8*|aarch64)
            echo 'armv8'
        ;;
        *armv6*)
            echo 'armv6'
        ;;
        *arm*)
            echo 'arm'
        ;;
        *mips64le*)
            echo 'mips64le'
        ;;
        *mips64*)
            echo 'mips64'
        ;;
        *mipsle*)
            echo 'mipsle-softfloat'
        ;;
        *mips*)
            echo 'mips-softfloat'
        ;;
        *)
            return 1
        ;;
    esac

	return 0
}

getData() {
    can_change=$1
    if [[ "$can_change" != "yes" ]]; then
        IP=`curl -s -4 ip.sb`
        echo " "
        echo " trojan-go一键脚本，运行之前请确认如下条件已经具备："
        echo -e "  ${RED}1. 一个伪装域名${PLAIN}"
        echo -e "  ${RED}2. 伪装域名DNS解析指向当前服务器ip（${IP}）${PLAIN}"
        echo -e "  3. 如果/root目录下有 ${GREEN}trojan-go.pem${PLAIN} 和 ${GREEN}trojan-go.key${PLAIN} 证书密钥文件，无需理会条件2"
        echo " "
        read -p " 确认满足按y，按其他退出脚本：" answer
        if [[ "${answer,,}" != "y" ]]; then
            exit 0
        fi

        while true
        do
            read -p " 请输入伪装域名：" DOMAIN
            if [[ -z "${DOMAIN}" ]]; then
                echo -e " ${RED}伪装域名输入错误，请重新输入！${PLAIN}"
            else
                break
            fi
        done
        echo -e " 伪装域名(host)：${RED}$DOMAIN${PLAIN}"
        echo ""
        
        DOMAIN=${DOMAIN,,}
        if [[ -f ~/trojan-go.pem && -f ~/trojan-go.key ]]; then
            echo -e "${GREEN} 检测到自有证书，将使用其部署${PLAIN}"
            echo 
            CERT_FILE="/etc/trojan-go/${DOMAIN}.pem"
            KEY_FILE="/etc/trojan-go/${DOMAIN}.key"
        else
            resolve=`curl -s https://hijk.art/hostip.php?d=${DOMAIN}`
            res=`echo -n ${resolve} | grep ${IP}`
            if [[ -z "${res}" ]]; then
                echo " ${DOMAIN} 解析结果：${resolve}"
                echo -e " ${RED}伪装域名未解析到当前服务器IP(${IP})!${PLAIN}"
                exit 1
            fi
        fi
    else
        DOMAIN=`grep sni $CONFIG_FILE | cut -d\" -f4`
        CERT_FILE=`grep cert $CONFIG_FILE | cut -d\" -f4`
        KEY_FILE=`grep key $CONFIG_FILE | cut -d\" -f4`
        read -p " 是否转换成WS版本？[y/n]" answer
        if [[ "${answer,,}" = "y" ]]; then
            WS="true"
        fi
    fi

    read -p " 请设置trojan密码（不输则随机生成）:" PASSWORD
    [[ -z "$PASSWORD" ]] && PASSWORD=`cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1`
    echo -e " trojan密码：$RED$PASSWORD${PLAIN}"
    while true
    do
        read -p " 是否需要再设置一组密码？[y/n]" answer
        if [[ ${answer,,} = "n" ]]; then
            break
        fi
        read -p " 请设置trojan密码（不输则随机生成）:" pass
        [[ -z "$pass" ]] && pass=`cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1`
        echo -e " trojan密码：$RED$pass${PLAIN}"
        PASSWORD="${PASSWORD}\",\"$pass"
        echo 
    done
    
    read -p " 请输入trojan端口[100-65535的一个数字，默认443]：" PORT
    [[ -z "${PORT}" ]] && PORT=443
    if [[ "${PORT:0:1}" = "0" ]]; then
        echo -e "${RED}端口不能以0开头${PLAIN}"
        exit 1
    fi
    echo -e " trojan端口：$RED$PORT${PLAIN}"
    echo 

    if [[ ${WS} = "true" ]]; then
        while true
        do
            read -p " 请输入伪装路径，以/开头：" WSPATH
            if [[ -z "${WSPATH}" ]]; then
                echo " 请输入伪装路径，以/开头！"
            elif [[ "${WSPATH:0:1}" != "/" ]]; then
                echo " 伪装路径必须以/开头！"
            elif [[ "${WSPATH}" = "/" ]]; then
                echo  " 不能使用根路径！"
            else
                break
            fi
        done
        echo -e " ws路径：$RED$WSPATH${PLAIN}"
        echo 
    fi

    read -p " 是否安装BBR(默认安装)?[y/n]:" NEED_BBR
    [[ -z "$NEED_BBR" ]] && NEED_BBR=y
    [[ "$NEED_BBR" = "Y" ]] && NEED_BBR=y
    
    len=${#SITES[@]}
    ((len--))
    index=`shuf -i0-${len} -n1`
    site=${SITES[$index]}
    REMOTE_HOST=`echo ${site} | cut -d/ -f3`
    REMOTE_HOST=`curl -s https://hijk.art/hostip.php?d=${REMOTE_HOST}`
    protocol=`echo ${site} | cut -d/ -f1`
    [[ "$protocol" != "http:" ]] && REMOTE_PORT=80 || REMOTE_PORT=443
}

installNginx() {
    if [[ "$PMT" = "yum" ]]; then
        $CMD_INSTALL epel-release 
    fi
    $CMD_INSTALL nginx
    systemctl enable nginx
    systemctl stop nginx
    res=`netstat -ntlp| grep -E ':80|:443'`
    if [[ "${res}" != "" ]]; then
        echo -e "${RED} 其他进程占用了80或443端口，请先关闭再运行一键脚本${PLAIN}"
        echo " 端口占用信息如下："
        echo ${res}
        exit 1
    fi
}

getCert() {
    if [[ -z ${CERT_FILE+x} ]]; then
        res=`which pip3`
        if [[ "$?" != "0" ]]; then
            $CMD_INSTALL python3 python3-pip
        fi
        res=`which pip3`
        if [[ "$?" != "0" ]]; then
            echo -e " pip3安装失败，请到 ${RED}https://hijk.art${PLAIN} 反馈"
            exit 1
        fi
        pip3 install --upgrade pip
        pip3 install wheel
        res=`pip3 list | grep crypto | awk '{print $2}'`
        if [[ "$res" < "2.8" ]]; then
            pip3 uninstall -y cryptography
            cd /usr/lib/python3/dist-packages
            rm -r cryptoggraphy cryptography-2.1.4.egg-info
            pip3 install cryptography
            cd -
        fi
        pip3 install certbot
        res=`which certbot`
        if [[ "$?" != "0" ]]; then
            export PATH=$PATH:/usr/local/bin
        fi
        certbot certonly --standalone --agree-tos --register-unsafely-without-email -d ${DOMAIN}
        if [[ "$?" != "0" ]]; then
            echo -e " 获取证书失败，请到 ${RED}https://hijk.art${PLAIN} 反馈"
            exit 1
        fi

        CERT_FILE="/etc/letsencrypt/archive/${DOMAIN}/fullchain1.pem"
        KEY_FILE="/etc/letsencrypt/archive/${DOMAIN}/privkey1.pem"
    fi
}

configNginx() {
    if [[ ! -f /etc/nginx/nginx.conf.bak ]]; then
        mv /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak
    fi
    res=`id nginx`
    if [[ "$?" != "0" ]]; then
        user="www-data"
    else
        user="nginx"
    fi
    mkdir -p /usr/share/nginx/html;
    echo 'User-Agent: *' > /usr/share/nginx/html/robots.txt
    echo 'Disallow: /' >> /usr/share/nginx/html/robots.txt
    cat > /etc/nginx/nginx.conf<<-EOF
user $user;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;

# Load dynamic modules. See /usr/share/doc/nginx/README.dynamic.
include /usr/share/nginx/modules/*.conf;

events {
    worker_connections 1024;
}

http {
    log_format  main  '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                      '\$status \$body_bytes_sent "\$http_referer" '
                      '"\$http_user_agent" "\$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log  main;
    server_tokens off;

    sendfile            on;
    tcp_nopush          on;
    tcp_nodelay         on;
    keepalive_timeout   65;
    types_hash_max_size 2048;
    gzip                on;

    include             /etc/nginx/mime.types;
    default_type        application/octet-stream;

    # Load modular configuration files from the /etc/nginx/conf.d directory.
    # See http://nginx.org/en/docs/ngx_core_module.html#include
    # for more information.
    include /etc/nginx/conf.d/*.conf;
}
EOF

    mkdir -p /etc/nginx/conf.d;
    cat > /etc/nginx/conf.d/${DOMAIN}.conf<<-EOF
server {
    listen 80;
    server_name ${DOMAIN};
    root /usr/share/nginx/html;
    location / {
        return 301 https://\$server_name:${PORT}\$request_uri;
    }
    
    location = /robots.txt {
    }
}
EOF

    certbotpath=`which certbot`
    echo "0 3 1 */2 0 root systemctl stop nginx ; ${certbotpath} renew; systemctl restart nginx" >> /etc/crontab
    systemctl enable nginx
}

downloadFile() {
    SUFFIX=`archAffix`
    DOWNLOAD_URL="https://github.com/p4gefau1t/trojan-go/releases/download/${VERSION}/trojan-go-linux-${SUFFIX}.zip"
    wget -O /tmp/${ZIP_FILE}.zip $DOWNLOAD_URL
    if [[ ! -f /tmp/${ZIP_FILE}.zip ]]; then
        echo -e "{$RED} trojan-go安装文件下载失败，请检查网络或重试${PLAIN}"
        exit 1
    fi
}

installTrojan() {
    rm -rf /tmp/${ZIP_FILE}
    unzip /tmp/${ZIP_FILE}.zip  -d /tmp/${ZIP_FILE}
    cp /tmp/${ZIP_FILE}/trojan-go /usr/bin
    cp /tmp/${ZIP_FILE}/example/trojan-go.service /etc/systemd/system/
    sed -i '/User=nobody/d' /etc/systemd/system/trojan-go.service
    systemctl daemon-reload

    systemctl enable trojan-go
    rm -rf /tmp/${ZIP_FILE}
}

configTrojan() {
    rm -rf /etc/trojan-go
    mkdir -p /etc/trojan-go
    if [[ -f ~/trojan-go.pem ]]; then
        cp ~/trojan-go.pem /etc/trojan-go/${DOMAIN}.pem
        cp ~/trojan-go.key /etc/trojan-go/${DOMAIN}.key
    fi
    cat > $CONFIG_FILE <<-EOF
{
    "run_type": "server",
    "local_addr": "0.0.0.0",
    "local_port": ${PORT},
    "remote_addr": "$REMOTE_HOST",
    "remote_port": $REMOTE_PORT,
    "password": [
        "$PASSWORD"
    ],
    "ssl": {
        "cert": "${CERT_FILE}",
        "key": "${KEY_FILE}",
        "sni": "${DOMAIN}",
        "alpn": [
            "http/1.1"
        ],
        "session_ticket": true,
        "reuse_session": true,
        "fallback_addr": "$REMOTE_HOST",
        "fallback_port": $REMOTE_PORT
    },
    "tcp": {
        "no_delay": true,
        "keep_alive": true,
        "prefer_ipv4": false
    },
    "mux": {
        "enabled": false,
        "concurrency": 8,
        "idle_timeout": 60
    },
    "websocket": {
        "enabled": ${WS},
        "path": "${WSPATH}",
        "host": "${DOMAIN}"
    },
    "mysql": {
      "enabled": false,
      "server_addr": "localhost",
      "server_port": 3306,
      "database": "",
      "username": "",
      "password": "",
      "check_rate": 60
    }
}
EOF
}

setSelinux() {
    if [[ -s /etc/selinux/config ]] && grep 'SELINUX=enforcing' /etc/selinux/config; then
        sed -i 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/selinux/config
        setenforce 0
    fi
}

setFirewall() {
    res=`which firewall-cmd`
    if [[ $? -eq 0 ]]; then
        systemctl status firewalld > /dev/null 2>&1
        if [[ $? -eq 0 ]];then
            firewall-cmd --permanent --add-service=http
            firewall-cmd --permanent --add-service=https
            firewall-cmd --permanent --add-port=${PORT}/tcp
            firewall-cmd --reload
        else
            nl=`iptables -nL | nl | grep FORWARD | awk '{print $1}'`
            if [[ "$nl" != "3" ]]; then
                iptables -I INPUT -p tcp --dport 80 -j ACCEPT
                iptables -A INPUT -p tcp --dport 443 -j ACCEPT
                iptables -A INPUT -p tcp --dport ${PORT} -j ACCEPT
            fi
        fi
    else
        res=`which iptables`
        if [[ $? -eq 0 ]]; then
            nl=`iptables -nL | nl | grep FORWARD | awk '{print $1}'`
            if [[ "$nl" != "3" ]]; then
                iptables -I INPUT -p tcp --dport 80 -j ACCEPT
                iptables -A INPUT -p tcp --dport 443 -j ACCEPT
                iptables -A INPUT -p tcp --dport ${PORT} -j ACCEPT
            fi
        else
            res=`which ufw`
            if [[ $? -eq 0 ]]; then
                res=`ufw status | grep -i inactive`
                if [[ "$res" = "" ]]; then
                    ufw allow http/tcp
                    ufw allow https/tcp
                    ufw allow ${PORT}/tcp
                fi
            fi
        fi
    fi
}

installBBR() {
    if [[ "$NEED_BBR" != "y" ]]; then
        INSTALL_BBR=false
        return
    fi
    result=$(lsmod | grep bbr)
    if [[ "$result" != "" ]]; then
        echo " BBR模块已安装"
        INSTALL_BBR=false
        echo "3" > /proc/sys/net/ipv4/tcp_fastopen
        echo "net.ipv4.tcp_fastopen = 3" >> /etc/sysctl.conf
        return
    fi
    res=`hostnamectl | grep -i openvz`
    if [[ "$res" != "" ]]; then
        echo  " openvz机器，跳过安装"
        INSTALL_BBR=false
        return
    fi
    
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_fastopen = 3" >> /etc/sysctl.conf
    sysctl -p
    result=$(lsmod | grep bbr)
    if [[ "$result" != "" ]]; then
        echo " BBR模块已启用"
        INSTALL_BBR=false
        return
    fi

    echo " 安装BBR模块..."
    if [[ "$PMT" = "yum" ]]; then
        rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
        rpm -Uvh http://www.elrepo.org/elrepo-release-7.0-4.el7.elrepo.noarch.rpm
        yum --enablerepo=elrepo-kernel install kernel-ml -y
        grub2-set-default 0
    else
        apt install -y --install-recommends linux-generic-hwe-16.04
        grub-set-default 0
    fi
    echo "tcp_bbr" >> /etc/modules-load.d/modules.conf
    INSTALL_BBR=true
}

install() {
    $CMD_UPGRADE
    $CMD_INSTALL wget net-tools unzip vim
    res=`which unzip`
    if [[ $? -ne 0 ]]; then
        echo -e " ${RED}unzip安装失败，请检查网络${PLAIN}"
        exit 1
    fi

    getData

    echo " 安装nginx..."
    installNginx
    setFirewall
    getCert
    configNginx

    echo " 安装trojan-go..."
    getVersion
    downloadFile
    installTrojan
    configTrojan

    setSelinux
    installBBR

    start
    showInfo
}

bbrReboot() {
    if [[ "${INSTALL_BBR}" == "true" ]]; then
        echo  
        echo " 为使BBR模块生效，系统将在30秒后重启"
        echo  
        echo -e " 您可以按 ctrl + c 取消重启，稍后输入 ${RED}reboot${PLAIN} 重启系统"
        sleep 30
        reboot
    fi
}

update() {
    res=`status`
    if [[ $res -lt 2 ]]; then
        echo -e " ${RED}trojan-go未安装，请先安装！${PLAIN}"
        return
    fi

    echo " 安装最新版trojan-go"
    getVersion
    downloadFile
    installTrojan

    stop
    start
    showInfo
}

uninstall() {
    read -p " 确定卸载trojan-go？[y/n]：" answer
    if [[ "${answer,,}" = "y" ]]; then
        stop
        domain=`grep sni $CONFIG_FILE | cut -d\" -f4`

        rm -rf /etc/trojan-go
        rm -rf /usr/bin/trojan-go
        systemctl disable trojan-go

        systemctl disable nginx
        $CMD_REMOVE nginx
        rm -rf /etc/nginx/nginx.conf
        if [[ -f /etc/nginx/nginx.conf.bak ]]; then
            mv /etc/nginx/nginx.conf.bak /etc/nginx/nginx.conf
        fi

        rm -rf /etc/nginx/conf.d/${domain}.conf
        echo -e " ${GREEN}trojan-go卸载成功${PLAIN}"
    fi
}

run() {
    res=`status`
    if [[ $res -lt 2 ]]; then
        echo -e "${RED}trojan-go未安装，请先安装！${PLAIN}"
        return
    fi

    res=`ss -ntlp| grep trojan-go`
    if [[ "$res" != "" ]]; then
        return
    fi

    start
    showInfo
}

start() {
    systemctl restart nginx
    systemctl restart trojan-go
    sleep 3
}

stop() {
    systemctl stop nginx
    systemctl stop trojan-go
}


restart() {
    res=`status`
    if [[ $res -lt 2 ]]; then
        echo -e " ${RED}trojan-go未安装，请先安装！${PLAIN}"
        return
    fi

    stop
    start
}

reconfig() {
    res=`status`
    if [[ $res -lt 2 ]]; then
        echo -e " ${RED}trojan-go未安装，请先安装！${PLAIN}"
        return
    fi

    line1=`grep -n 'websocket' $CONFIG_FILE  | head -n1 | cut -d: -f1`
    line11=`expr $line1 + 1`
    WS=`sed -n "${line11}p" $CONFIG_FILE | cut -d: -f2 | tr -d \",' '`
    getData true
    configTrojan
    setFirewall
    stop
    start
    showInfo

    bbrReboot
}


showInfo() {
    res=`status`
    if [[ $res -lt 2 ]]; then
        echo -e " ${RED}trojan-go未安装，请先安装！${PLAIN}"
        return
    fi

    ip=`curl -s -4 ip.sb`
    domain=`grep sni $CONFIG_FILE | cut -d\" -f4`
    port=`grep local_port $CONFIG_FILE | cut -d: -f2 | tr -d \",' '`
    line1=`grep -n 'password' $CONFIG_FILE  | head -n1 | cut -d: -f1`
    line11=`expr $line1 + 1`
    password=`sed -n "${line11}p" $CONFIG_FILE | tr -d \"' '`
    line1=`grep -n 'websocket' $CONFIG_FILE  | head -n1 | cut -d: -f1`
    line11=`expr $line1 + 1`
    ws=`sed -n "${line11}p" $CONFIG_FILE | cut -d: -f2 | tr -d \",' '`
    echo 
    echo -e "  ${RED}trojan-go配置信息：${PLAIN}"
    echo 
    echo -n "  当前状态："
    statusText
    echo -e "  IP：${RED}$ip${PLAIN}"
    echo -e "  伪装域名/主机名(host)：${RED}$domain${PLAIN}"
    echo -e "  端口(port)：${RED}$port${PLAIN}"
    echo -e "  密码(password)：${RED}$password${PLAIN}"
    if [[ $ws = "true" ]]; then
        echo -e "  websocket：${RED}true${PLAIN}"
        wspath=`grep path $CONFIG_FILE | cut -d: -f2 | tr -d \",' '`
        echo -e "  ws路径(ws path)：${RED}${wspath}${PLAIN}"
    fi
    echo ""
}

showLog() {
    res=`status`
    if [[ $res -lt 2 ]]; then
        echo -e "${RED}trojan-go未安装，请先安装！${PLAIN}"
        return
    fi

    journalctl -xen -u trojan-go --no-pager
}

menu() {
    clear
    echo "#############################################################"
    echo -e "#                    ${RED}trojan-go一键安装脚本${PLAIN}                  #"
    echo -e "# ${GREEN}作者${PLAIN}: 网络跳越(hijk)                                      #"
    echo -e "# ${GREEN}网址${PLAIN}: https://hijk.art                                    #"
    echo -e "# ${GREEN}论坛${PLAIN}: https://hijk.club                                   #"
    echo -e "# ${GREEN}TG群${PLAIN}: https://t.me/hijkclub                               #"
    echo -e "# ${GREEN}Youtube频道${PLAIN}: https://youtube.com/channel/UCYTB--VsObzepVJtc9yvUxQ #"
    echo "#############################################################"
    echo ""

    echo -e "  ${GREEN}1.${PLAIN}  安装trojan-go"
    echo -e "  ${GREEN}2.${PLAIN}  安装trojan-go+WS"
    echo -e "  ${GREEN}3.${PLAIN}  更新trojan-go"
    echo -e "  ${GREEN}4.${PLAIN}  卸载trojan-go"
    echo " -------------"
    echo -e "  ${GREEN}5.${PLAIN}  启动trojan-go"
    echo -e "  ${GREEN}6.${PLAIN}  重启trojan-go"
    echo -e "  ${GREEN}7.${PLAIN}  停止trojan-go"
    echo " -------------"
    echo -e "  ${GREEN}8.${PLAIN}  查看trojan-go信息"
    echo -e "  ${GREEN}9.${PLAIN}  修改trojan-go配置"
    echo -e "  ${GREEN}10.${PLAIN} 查看trojan-go日志"
    echo " -------------"
    echo -e "  ${GREEN}0.${PLAIN} 退出"
    echo 
    echo -n " 当前状态："
    statusText
    echo 

    read -p " 请选择操作[0-10]：" answer
    case $answer in
        0)
            exit 0
            ;;
        1)
            install
            ;;
        2)
            WS="true"
            install
            ;;
        3)
            update
            ;;
        4)
            uninstall
            ;;
        5)
            run
            ;;
        6)
            restart
            ;;
        7)
            stop
            ;;
        8)
            showInfo
            ;;
        9)
            reconfig
            ;;
        10)
            showLog
            ;;
        *)
            echo -e "$RED 请选择正确的操作！${PLAIN}"
            exit 1
            ;;
    esac
}

checkSystem

menu
