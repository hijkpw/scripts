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

CONFIG_FILE="/etc/v2ray/config.json"
OS=`hostnamectl | grep -i system | cut -d: -f2`

VLESS="false"
TLS="false"
WS="false"
XTLS="false"

checkSystem() {
    result=$(id | awk '{print $1}')
    if [[ $result != "uid=0(root)" ]]; then
        colorEcho $RED " 请以root身份执行该脚本"
        exit 1
    fi

    res=`which yum`
    if [[ "$?" != "0" ]]; then
        res=`which apt`
        if [[ "$?" != "0" ]]; then
            colorEcho $RED " 不受支持的Linux系统"
            exit 1
        fi
        PMT="apt"
        CMD_INSTALL="apt install -y "
        CMD_REMOVE="apt remove -y "
        CMD_UPGRADE="apt clean all && apt update && apt upgrade -y"
    else
        PMT="yum"
        CMD_INSTALL="yum install -y "
        CMD_REMOVE="yum remove -y "
        CMD_UPGRADE="yum clean all && yum update -y"
    fi
    res=`which systemctl`
    if [[ "$?" != "0" ]]; then
        colorEcho $RED " 系统版本过低，请升级到最新版本"
        exit 1
    fi
}

colorEcho() {
    echo -e "${1}${@:2}${PLAIN}"
}

configNeedNginx() {
    local ws=`grep wsSettings $CONFIG_FILE`
    if [[ -z "$ws" ]]; then
        echo no
        return
    fi
    echo yes
}

needNginx() {
    if [[ "$WS" = "false" ]]; then
        echo no
        return
    fi
    echo yes
}

status() {
    if [[ ! -f /usr/bin/v2ray/v2ray ]]; then
        echo 0
        return
    fi
    if [[ ! -f $CONFIG_FILE ]]; then
        echo 1
        return
    fi
    port=`grep port $CONFIG_FILE| head -n 1| cut -d: -f2| tr -d \",' '`
    res=`ss -ntlp| grep ${port} | grep -i v2ray`
    if [[ -z "$res" ]]; then
        echo 2
        return
    fi

    if [[ `configNeedNginx` != "yes" ]]; then
        echo 3
    else
        res=`ss -ntlp|grep -i nginx`
        if [[ -z "$res" ]]; then
            echo 4
        else
            echo 5
        fi
    fi
}

statusText() {
    res=`status`
    case $res in
        2)
            echo -e ${GREEN}已安装${PLAIN} ${RED}未运行${PLAIN}
            ;;
        3)
            echo -e ${GREEN}已安装${PLAIN} ${GREEN}V2ray正在运行${PLAIN}
            ;;
        4)
            echo -e ${GREEN}已安装${PLAIN} ${GREEN}V2ray正在运行${PLAIN}, ${RED}Nginx未运行${PLAIN}
            ;;
        5)
            echo -e ${GREEN}已安装${PLAIN} ${GREEN}V2ray正在运行, Nginx正在运行${PLAIN}
            ;;
        *)
            echo -e ${RED}未安装${PLAIN}
            ;;
    esac
}

normalizeVersion() {
    if [ -n "$1" ]; then
        case "$1" in
            v*)
                echo "$1"
            ;;
            *)
                echo "v$1"
            ;;
        esac
    else
        echo ""
    fi
}

# 1: new V2Ray. 0: no. 1: yes. 2: not installed. 3: check failed.
getVersion() {
    VER="$(/usr/bin/v2ray/v2ray -version 2>/dev/null)"
    RETVAL=$?
    CUR_VER="$(normalizeVersion "$(echo "$VER" | head -n 1 | cut -d " " -f2)")"
    TAG_URL="https://api.github.com/repos/v2fly/v2ray-core/releases/latest"
    NEW_VER="$(normalizeVersion "$(curl -s "${TAG_URL}" --connect-timeout 10| grep 'tag_name' | cut -d\" -f4)")"

    if [[ $? -ne 0 ]] || [[ $NEW_VER == "" ]]; then
        colorEcho $RED " 检查V2ray版本信息失败，请检查网络"
        return 3
    elif [[ $RETVAL -ne 0 ]];then
        return 2
    elif [[ $NEW_VER != $CUR_VER ]];then
        return 1
    fi
    return 0
}

archAffix(){
    case "$(uname -m)" in
        i686|i386)
            echo '32'
        ;;
        x86_64|amd64)
            echo '64'
        ;;
        *armv7*|armv6l)
            echo 'arm'
        ;;
        *armv8*|aarch64)
            echo 'arm64'
        ;;
        *mips64le*)
            echo 'mips64le'
        ;;
        *mips64*)
            echo 'mips64'
        ;;
        *mipsle*)
            echo 'mipsle'
        ;;
        *mips*)
            echo 'mips'
        ;;
        *s390x*)
            echo 's390x'
        ;;
        ppc64le)
            echo 'ppc64le'
        ;;
        ppc64)
            echo 'ppc64'
        ;;
        *)
            return 1
        ;;
    esac

	return 0
}

getData() {
    IP=`curl -s -4 ip.sb`
    if [[ "$TLS" = "true" || "$XTLS" = "true" ]]; then
        echo " "
        echo " V2ray一键脚本，运行之前请确认如下条件已经具备："
        colorEcho ${YELLOW} "  1. 一个伪装域名"
        colorEcho ${YELLOW} "  2. 伪装域名DNS解析指向当前服务器ip（${IP}）"
        colorEcho ${BLUE} "  3. 如果/root目录下有 v2ray.pem 和 v2ray.key 证书密钥文件，无需理会条件2"
        echo " "
        read -p " 确认满足按y，按其他退出脚本：" answer
        if [[ "${answer,,}" != "y" ]]; then
            exit 0
        fi

        while true
        do
            read -p " 请输入伪装域名：" DOMAIN
            if [[ -z "${DOMAIN}" ]]; then
                colorEcho ${RED} " 域名输入错误，请重新输入！"
            else
                break
            fi
        done
        DOMAIN=${DOMAIN,,}
        colorEcho ${BLUE}  " 伪装域名(host)：$DOMAIN"
        echo ""

        if [[ -f ~/v2ray.pem && -f ~/v2ray.key ]]; then
            colorEcho ${BLUE}  " 检测到自有证书，将使用其部署"
            echo 
            CERT_FILE="/etc/v2ray/${DOMAIN}.pem"
            KEY_FILE="/etc/v2ray/${DOMAIN}.key"
        else
            resolve=`curl -s https://hijk.art/hostip.php?d=${DOMAIN}`
            res=`echo -n ${resolve} | grep ${IP}`
            if [[ -z "${res}" ]]; then
                colorEcho ${BLUE}  "${DOMAIN} 解析结果：${resolve}"
                colorEcho ${RED}  " 域名未解析到当前服务器IP(${IP})!"
                exit 1
            fi
        fi
    fi
    
    if [[ "$(needNginx)" = "no" ]]; then
        if [[ "$TLS" = "true" ]]; then
            read -p " 请输入v2ray监听端口[强烈建议443，默认443]：" PORT
            [[ -z "${PORT}" ]] && PORT=443
        else
            read -p " 请输入v2ray监听端口[100-65535的一个数字]：" PORT
            [[ -z "${PORT}" ]] && PORT=`shuf -i200-65000 -n1`
            if [[ "${PORT:0:1}" = "0" ]]; then
                colorEcho ${RED}  " 端口不能以0开头"
                exit 1
            fi
        fi
        colorEcho ${BLUE}  " v2ray端口：$PORT"
        echo ""
        echo
    else
        read -p "请输入Nginx监听端口[100-65535的一个数字，默认443]：" PORT
        [[ -z "${PORT}" ]] && PORT=443
        if [ "${PORT:0:1}" = "0" ]; then
            colorEcho ${BLUE}  " 端口不能以0开头"
            exit 1
        fi
        colorEcho ${BLUE}  " Nginx端口：$PORT"
        echo ""
        V2PORT=`shuf -i10000-65000 -n1`
    fi

    if [[ "${WS}" = "true" ]]; then
        while true
        do
            read -p " 请输入伪装路径，以/开头：" WSPATH
            if [[ -z "${WSPATH}" ]]; then
                colorEcho ${RED}  " 请输入伪装路径，以/开头！"
            elif [[ "${WSPATH:0:1}" != "/" ]]; then
                colorEcho ${RED}  " 伪装路径必须以/开头！"
            elif [[ "${WSPATH}" = "/" ]]; then
                colorEcho ${RED}   " 不能使用根路径！"
            else
                break
            fi
        done
        colorEcho ${BLUE}  " ws路径：$WSPATH"
        echo ""
        echo 
    fi

    read -p " 是否安装BBR(默认安装)?[y/n]:" NEED_BBR
    [[ -z "$NEED_BBR" ]] && NEED_BBR=y
    [[ "$NEED_BBR" = "Y" ]] && NEED_BBR=y
    
    colorEcho $BLUE " 请选择伪装站类型:" 
    echo "   1) 静态网站(位于/usr/share/nginx/html)"
    echo "   2) 小说站(随机选择)"
    echo "   3) 美女站(https://imeizi.me)"
    echo "   4) VPS优惠博客(https://vpsgongyi.com)"
    echo "   5) 自定义反代站点(需以http或者https开头)"
    read -p "  请选择伪装网站类型[默认:美女站]" answer
    if [[ -z "$answer" ]]; then
        PROXY_URL="https://imeizi.me"
    else
        case $answer in
        1)
            PROXY_URL=""
            ;;
        2)
            len=${#SITES[@]}
            ((len--))
            while true
            do
                index=`shuf -i0-${len} -n1`
                PROXY_URL=${SITES[$index]}
            done
            ;;
        3)
            PROXY_URL="https://imeizi.me"
            ;;
        4)
            PROXY_URL="https://vpsgongyi.com"
            ;;
        5)
            read -p " 请输入反代站点(以http或者https开头)：" PROXY_URL
            if [[ -z "$PROXY_URL" ]]; then
                colorEcho $RED " 请输入反代网站！"
                exit 1
            elif [[ "${PROXY_URL:0:4}" != "http" ]]; then
                colorEcho $RED " 反代网站必须以http或https开头！"
                exit 1
            fi
            ;;
        *)
            colorEcho $RED " 请输入正确的选项！"
            exit 1
        esac
    fi
}

installNginx() {
    if [[ "$PMT" = "yum" ]]; then
        $CMD_INSTALL epel-release 
    fi
    $CMD_INSTALL nginx
    systemctl enable nginx
}

getCert() {
    if [[ -z ${CERT_FILE+x} ]]; then
        systemctl stop nginx
        systemctl stop v2ray
        res=`netstat -ntlp| grep -E ':80|:443'`
        if [[ "${res}" != "" ]]; then
            colorEcho ${RED}  " 其他进程占用了80或443端口，请先关闭再运行一键脚本"
            echo " 端口占用信息如下："
            echo ${res}
            exit 1
        fi

        res=`which pip3`
        if [[ "$?" != "0" ]]; then
            $CMD_INSTALL python3 python3-setuptools python3-pip
        fi
        res=`which pip3`
        if [[ "$?" != "0" ]]; then
            colorEcho ${RED}  " $OS pip3安装失败，请到 https://hijk.art 反馈"
            exit 1
        fi
        pip3 install --upgrade pip
        pip3 install wheel
        res=`pip3 list | grep crypto | awk '{print $2}'`
        if [[ "$res" < "2.8" ]]; then
            pip3 uninstall -y cryptography
            pip3 install cryptography
        fi
        pip3 install certbot
        res=`which certbot`
        if [[ "$?" != "0" ]]; then
            export PATH=$PATH:/usr/local/bin
        fi
        certbot certonly --standalone --agree-tos --register-unsafely-without-email -d ${DOMAIN}
        if [[ "$?" != "0" ]]; then
            colorEcho ${RED}  " $OS 获取证书失败，请到 https://hijk.art 反馈"
            exit 1
        fi

        CERT_FILE="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
        KEY_FILE="/etc/letsencrypt/live/${DOMAIN}/privkey.pem"
    else
        mkdir -p /etc/v2ray
        cp ~/v2ray.pem /etc/v2ray/${DOMAIN}.pem
        cp ~/v2ray.key /etc/v2ray/${DOMAIN}.key
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

    if [[ "$PROXY_URL" = "" ]]; then
        action=""
    else
        if [[ "${PROXY_URL:0:5}" == "https" ]]; then
        action="proxy_ssl_server_name on;
        proxy_pass $PROXY_URL;"
        else
            action="proxy_pass $PROXY_URL;"
        fi
    fi

    if [[ "$TLS" = "true" || "$XTLS" = "true" ]]; then
        mkdir -p /etc/nginx/conf.d;
        # VMESS+WS+TLS
        # VLESS+WS+TLS
        if [[ "$WS" = "true" ]]; then
            cat > /etc/nginx/conf.d/${DOMAIN}.conf<<-EOF
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
    ssl_certificate $CERT_FILE;
    ssl_certificate_key $KEY_FILE;

    root /usr/share/nginx/html;
    location / {
        $action
    }
    location = /robots.txt {
    }

    location ${WSPATH} {
      proxy_redirect off;
      proxy_pass http://127.0.0.1:${V2PORT};
      proxy_http_version 1.1;
      proxy_set_header Upgrade \$http_upgrade;
      proxy_set_header Connection "upgrade";
      proxy_set_header Host \$host;
      # Show real IP in v2ray access.log
      proxy_set_header X-Real-IP \$remote_addr;
      proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF
        else
            # VLESS+TCP+TLS
            # VLESS+TCP+XTLS
            cat > /etc/nginx/conf.d/${DOMAIN}.conf<<-EOF
server {
    listen 80;
    server_name ${DOMAIN};
    root /usr/share/nginx/html;
    location / {
        $action
    }
    location = /robots.txt {
    }
}
EOF
        fi
    fi

    certbotpath=`which certbot`
    if [[ "$certbotpath" != "" ]]; then
        echo "0 3 1 */2 0 root systemctl stop nginx ; ${certbotpath} renew; systemctl restart nginx" >> /etc/crontab
    fi
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
            if [[ "$PORT" != "443" ]]; then
                firewall-cmd --permanent --add-port=${PORT}/tcp
            fi
            firewall-cmd --reload
        else
            nl=`iptables -nL | nl | grep FORWARD | awk '{print $1}'`
            if [[ "$nl" != "3" ]]; then
                iptables -I INPUT -p tcp --dport 80 -j ACCEPT
                iptables -I INPUT -p tcp --dport 443 -j ACCEPT
                if [[ "$PORT" != "443" ]]; then
                    iptables -I INPUT -p tcp --dport ${PORT} -j ACCEPT
                fi
            fi
        fi
    else
        res=`which iptables`
        if [[ $? -eq 0 ]]; then
            nl=`iptables -nL | nl | grep FORWARD | awk '{print $1}'`
            if [[ "$nl" != "3" ]]; then
                iptables -I INPUT -p tcp --dport 80 -j ACCEPT
                iptables -I INPUT -p tcp --dport 443 -j ACCEPT
                if [[ "$PORT" != "443" ]]; then
                    iptables -I INPUT -p tcp --dport ${PORT} -j ACCEPT
                fi
            fi
        else
            res=`which ufw`
            if [[ $? -eq 0 ]]; then
                res=`ufw status | grep -i inactive`
                if [[ "$res" = "" ]]; then
                    ufw allow http/tcp
                    ufw allow https/tcp
                    if [[ "$PORT" != "443" ]]; then
                        ufw allow ${PORT}/tcp
                    fi
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
        colorEcho $BLUE " BBR模块已安装"
        INSTALL_BBR=false
        echo "3" > /proc/sys/net/ipv4/tcp_fastopen
        echo "net.ipv4.tcp_fastopen = 3" >> /etc/sysctl.conf
        return
    fi
    res=`hostnamectl | grep -i openvz`
    if [[ "$res" != "" ]]; then
        colorEcho $BLUE " openvz机器，跳过安装"
        INSTALL_BBR=false
        return
    fi
    
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_fastopen = 3" >> /etc/sysctl.conf
    sysctl -p
    result=$(lsmod | grep bbr)
    if [[ "$result" != "" ]]; then
        colorEcho $GREEN " BBR模块已启用"
        INSTALL_BBR=false
        return
    fi

    colorEcho $BLUE " 安装BBR模块..."
    if [[ "$PMT" = "yum" ]]; then
        rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
        rpm -Uvh http://www.elrepo.org/elrepo-release-7.0-4.el7.elrepo.noarch.rpm
        yum --enablerepo=elrepo-kernel install kernel-ml -y
        grub2-set-default 0
    else
        $CMD_INSTALL --install-recommends linux-generic-hwe-16.04
        grub-set-default 0
    fi
    INSTALL_BBR=true
}

installV2ray() {
    rm -rf /tmp/v2ray
    mkdir -p /tmp/v2ray
    DOWNLOAD_LINK="https://github.com/v2fly/v2ray-core/releases/download/${NEW_VER}/v2ray-linux-$(archAffix).zip"
    colorEcho $BLUE " 下载V2Ray: ${DOWNLOAD_LINK}"
    curl -L -H "Cache-Control: no-cache" -o /tmp/v2ray/v2ray.zip ${DOWNLOAD_LINK}
    if [ $? != 0 ];then
        colorEcho $RED " 下载V2ray文件失败，请检查服务器网络设置"
        exit 1
    fi
    mkdir -p '/etc/v2ray' '/var/log/v2ray' && \
    unzip /tmp/v2ray/v2ray.zip -d /tmp/v2ray
    mkdir /usr/bin/v2ray
    cp /tmp/v2ray/v2ctl /usr/bin/v2ray/; cp /tmp/v2ray/v2ray /usr/bin/v2ray/; cp /tmp/v2ray/geo* /usr/bin/v2ray/;
    chmod +x '/usr/bin/v2ray/v2ray' '/usr/bin/v2ray/v2ctl' || {
        colorEcho $RED " V2ray安装失败"
        exit 1
    }

    if [[ ! -f /etc/systemd/system/v2ray.service ]]; then
        wget -O /etc/systemd/system/v2ray.service https://raw.githubusercontent.com/hijkpw/scripts/master/v2ray.service
        systemctl enable v2ray.service
    fi
}

configV2ray() {
    mkdir -p /etc/v2ray
    local uuid="$(cat '/proc/sys/kernel/random/uuid')"
    if [[ "$VLESS" = "false" ]]; then
        # VMESS
        if [[ "$TLS" = "false" ]]; then
            local alterid=`shuf -i50-80 -n1`
            cat > $CONFIG_FILE<<-EOF
{
  "inbounds": [{
    "port": $PORT,
    "protocol": "vmess",
    "settings": {
      "clients": [
        {
          "id": "$uuid",
          "level": 1,
          "alterId": $alterid
        }
      ]
    }
  }],
  "outbounds": [{
    "protocol": "freedom",
    "settings": {}
  },{
    "protocol": "blackhole",
    "settings": {},
    "tag": "blocked"
  }],
  "routing": {
    "rules": [
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "blocked"
      }
    ]
  }
}
EOF
        # VMESS+TCP+TLS
        elif [[ "$WS" = "false" ]]; then
            cat > $CONFIG_FILE<<-EOF
{
  "inbounds": [{
    "port": $PORT,
    "protocol": "vmess",
    "settings": {
      "clients": [
        {
          "id": "$uuid",
          "level": 1,
          "alterId": 0
        }
      ],
      "disableInsecureEncryption": false
    },
    "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
            "serverName": "$DOMAIN",
            "certificates": [
                {
                    "certificateFile": "$CERT_FILE",
                    "keyFile": "$KEY_FILE"
                }
            ]
        }
    }
  }],
  "outbounds": [{
    "protocol": "freedom",
    "settings": {}
  },{
    "protocol": "blackhole",
    "settings": {},
    "tag": "blocked"
  }],
  "routing": {
    "rules": [
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "blocked"
      }
    ]
  }
}
EOF
        # VMESS+WS+TLS
        else
            cat > $CONFIG_FILE<<-EOF
{
  "inbounds": [{
    "port": $V2PORT,
    "listen": "127.0.0.1",
    "protocol": "vmess",
    "settings": {
      "clients": [
        {
          "id": "$uuid",
          "level": 1,
          "alterId": 0
        }
      ],
      "disableInsecureEncryption": false
    },
    "streamSettings": {
        "network": "ws",
        "wsSettings": {
            "path": "$WSPATH",
            "headers": {
                "Host": "$DOMAIN"
            }
        }
    }
  }],
  "outbounds": [{
    "protocol": "freedom",
    "settings": {}
  },{
    "protocol": "blackhole",
    "settings": {},
    "tag": "blocked"
  }],
  "routing": {
    "rules": [
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "blocked"
      }
    ]
  }
}
EOF
        fi
    #VLESS
    else
        # VLESS+TCP
        if [[ "$WS" = "false" ]]; then
            # VLESS+TCP+TLS
            if [[ "$XTLS" = "false" ]]; then
                cat > $CONFIG_FILE<<-EOF
{
  "inbounds": [{
    "port": $PORT,
    "protocol": "vless",
    "settings": {
      "clients": [
        {
          "id": "$uuid",
          "level": 0
        }
      ],
      "decryption": "none",
      "fallbacks": [
          {
              "dest": 80
          }
      ]
    },
    "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
            "serverName": "$DOMAIN",
            "alpn": [
                "http/1.1"
            ],
            "certificates": [
                {
                    "certificateFile": "$CERT_FILE",
                    "keyFile": "$KEY_FILE"
                }
            ]
        }
    }
  }],
  "outbounds": [{
    "protocol": "freedom",
    "settings": {}
  },{
    "protocol": "blackhole",
    "settings": {},
    "tag": "blocked"
  }],
  "routing": {
    "rules": [
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "blocked"
      }
    ]
  }
}
EOF
            # VLESS+TCP+XTLS
            else
                cat > $CONFIG_FILE<<-EOF
{
  "inbounds": [{
    "port": $PORT,
    "protocol": "vless",
    "settings": {
      "clients": [
        {
          "id": "$uuid",
          "flow": "xtls-rprx-origin",
          "level": 0
        }
      ],
      "decryption": "none",
      "fallbacks": [
          {
              "dest": 80
          }
      ]
    },
    "streamSettings": {
        "network": "tcp",
        "security": "xtls",
        "xtlsSettings": {
            "serverName": "$DOMAIN",
            "alpn": [
                "http/1.1"
            ],
            "certificates": [
                {
                    "certificateFile": "$CERT_FILE",
                    "keyFile": "$KEY_FILE"
                }
            ]
        }
    }
  }],
  "outbounds": [{
    "protocol": "freedom",
    "settings": {}
  },{
    "protocol": "blackhole",
    "settings": {},
    "tag": "blocked"
  }],
  "routing": {
    "rules": [
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "blocked"
      }
    ]
  }
}
EOF
            fi
        # VLESS+WS+TLS
        else
            cat > $CONFIG_FILE<<-EOF
{
  "inbounds": [{
    "port": $V2PORT,
    "listen": "127.0.0.1",
    "protocol": "vless",
    "settings": {
        "clients": [
            {
                "id": "$uuid",
                "level": 0
            }
        ],
        "decryption": "none"
    },
    "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
            "path": "$WSPATH",
            "headers": {
                "Host": "$DOMAIN"
            }
        }
    }
  }],
  "outbounds": [{
    "protocol": "freedom",
    "settings": {}
  },{
    "protocol": "blackhole",
    "settings": {},
    "tag": "blocked"
  }],
  "routing": {
    "rules": [
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "blocked"
      }
    ]
  }
}
EOF
        fi
    fi
}

install() {
    $CMD_UPGRADE
    $CMD_INSTALL wget net-tools unzip vim
    res=`which unzip`
    if [[ $? -ne 0 ]]; then
        colorEcho $RED " unzip安装失败，请检查网络"
        exit 1
    fi

    getData

    colorEcho $BLUE " 安装nginx..."
    installNginx
    setFirewall
    if [[ "$TLS" = "true" || "$XTLS" = "true" ]]; then
        getCert
    fi
    configNginx

    colorEcho $BLUE " 安装V2ray..."
    getVersion
    RETVAL="$?"
    if [[ $RETVAL == 0 ]]; then
        colorEcho $BLUE " V2ray最新版 ${CUR_VER} 已经安装"
    elif [[ $RETVAL == 3 ]]; then
        exit 1
    else
        colorEcho $BLUE " 安装V2Ray ${NEW_VER} ，架构$(archAffix)"
        installV2ray
    fi

    configV2ray

    setSelinux
    installBBR

    start
    showInfo

    bbrReboot
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
        colorEcho $RED " V2ray未安装，请先安装！"
        return
    fi

    getVersion
    RETVAL="$?"
    if [[ $RETVAL == 0 ]]; then
        colorEcho $BLUE " V2ray最新版 ${CUR_VER} 已经安装"
    elif [[ $RETVAL == 3 ]]; then
        exit 1
    else
        colorEcho $BLUE " 安装V2Ray ${NEW_VER} ，架构$(archAffix)"
        installV2ray
        stop
        start

        colorEcho $GREEN " 最新版V2ray安装成功！"
    fi
}

uninstall() {
    read -p " 确定卸载V2ray？[y/n]：" answer
    if [[ "${answer,,}" = "y" ]]; then
        stop
        systemctl disable v2ray
        if [[ "$(configNeedNginx)" = "yes" ]]; then
            domain=`grep Host $CONFIG_FILE | cut -d: -f2 | tr -d \",' '`
            if [[ "$domain" = "" ]]; then
                domain=`grep serverName $CONFIG_FILE | cut -d: -f2 | tr -d \",' '`
            fi
        fi
        

        rm -rf /etc/v2ray
        rm -rf /usr/bin/v2ray

        systemctl disable nginx
        $CMD_REMOVE nginx
        rm -rf /etc/nginx/nginx.conf
        if [[ -f /etc/nginx/nginx.conf.bak ]]; then
            mv /etc/nginx/nginx.conf.bak /etc/nginx/nginx.conf
        fi
        if [[ "$domain" != "" ]]; then
            rm -rf /etc/nginx/conf.d/${domain}.conf
        fi
        colorEcho $GREEN " V2ray卸载成功"
    fi
}

run() {
    res=`status`
    if [[ $res -lt 2 ]]; then
        colorEcho $RED " V2ray未安装，请先安装！"
        return
    fi

    res=`ss -ntlp| grep v2ray`
    if [[ "$res" != "" ]]; then
        return
    fi

    start
    showInfo
}

start() {
    systemctl restart nginx
    systemctl restart v2ray
    sleep 3
}

stop() {
    systemctl stop nginx
    systemctl stop v2ray
}


restart() {
    res=`status`
    if [[ $res -lt 2 ]]; then
        colorEcho $RED " V2ray未安装，请先安装！"
        return
    fi

    stop
    start
}


showInfo() {
    res=`status`
    if [[ $res -lt 2 ]]; then
        colorEcho $RED " V2ray未安装，请先安装！"
        return
    fi

    vless="false"
    tls="false"
    ws="false"
    xtls="false"

    ip=`curl -s -4 ip.sb`
    uid=`grep id $CONFIG_FILE | head -n1| cut -d: -f2 | tr -d \",' '`
    alterid=`grep alterId $CONFIG_FILE  | cut -d: -f2 | tr -d \",' '`
    network=`grep network $CONFIG_FILE  | tail -n1| cut -d: -f2 | tr -d \",' '`
    [[ -z "$network" ]] && network="tcp"
    domain=`grep serverName $CONFIG_FILE | cut -d: -f2 | tr -d \",' '`
    if [[ "$domain" = "" ]]; then
        domain=`grep Host $CONFIG_FILE | cut -d: -f2 | tr -d \",' '`
        if [[ "$domain" != "" ]]; then
            ws="true"
            tls="true"
            wspath=`grep path $CONFIG_FILE | cut -d: -f2 | tr -d \",' '`
        fi
    else
        tls="true"
    fi
    if [[ "$ws" = "true" ]]; then
        port=`cat /etc/nginx/conf.d/${domain}.conf | grep -i ssl | head -n1 | awk '{print $2}'`
    else
        port=`grep port $CONFIG_FILE | cut -d: -f2 | tr -d \",' '`
    fi

    vmess=`grep vmess $CONFIG_FILE`
    if [[ "$vmess" = "" ]]; then
        vless="true"
        tls="true"
        encryption="none"
        xtls=`grep xtlsSettings $CONFIG_FILE`
        if [[ "$xtls" != "" ]]; then
            xtls="true"
            flow="xtls-rprx-origin"
        else
            flow="无"
        fi
    fi
    
    echo 
    colorEcho $BLUE " V2ray配置信息："
    echo -n -e " ${BLUE}运行状态：${PLAIN}"
    statusText
    echo


    if [[ "$vless" = "false" ]]; then
        echo -e " ${BLUE}协议: ${PLAIN} ${RED}VMess${PLAIN}"
        if [[ "$tls" = "false" ]]; then
            raw="{
  \"v\":\"2\",
  \"ps\":\"\",
  \"add\":\"$ip\",
  \"port\":\"${port}\",
  \"id\":\"${uid}\",
  \"aid\":\"$alterid\",
  \"net\":\"tcp\",
  \"type\":\"none\",
  \"host\":\"\",
  \"path\":\"\",
  \"tls\":\"\"
}"
            link=`echo -n ${raw} | base64 -w 0`
            link="vmess://${link}"

            echo -e " ${BLUE}IP(address): ${PLAIN} ${RED}${ip}${PLAIN}"
            echo -e " ${BLUE}端口(port)：${PLAIN}${RED}${port}${PLAIN}"
            echo -e " ${BLUE}id(uuid)：${PLAIN}${RED}${uid}${PLAIN}"
            echo -e " ${BLUE}额外id(alterid)：${PLAIN} ${RED}${alterid}${PLAIN}"
            echo -e " ${BLUE}加密方式(security)：${PLAIN} ${RED}auto${PLAIN}"
            echo -e " ${BLUE}传输协议(network)：${PLAIN} ${RED}${network}${PLAIN}" 
            echo  
            echo -e " ${BLUE}vmess链接:${PLAIN} $RED$link$PLAIN"
        elif [[ "$ws" = "false" ]]; then
            raw="{
  \"v\":\"2\",
  \"ps\":\"\",
  \"add\":\"$ip\",
  \"port\":\"${port}\",
  \"id\":\"${uid}\",
  \"aid\":\"$alterid\",
  \"net\":\"${network}\",
  \"type\":\"none\",
  \"host\":\"${domain}\",
  \"path\":\"\",
  \"tls\":\"tls\"
}"
            link=`echo -n ${raw} | base64 -w 0`
            link="vmess://${link}"
            echo -e " ${BLUE}IP(address): ${PLAIN} ${RED}${ip}${PLAIN}"
            echo -e " ${BLUE}端口(port)：${PLAIN}${RED}${port}${PLAIN}"
            echo -e " ${BLUE}id(uuid)：${PLAIN}${RED}${uid}${PLAIN}"
            echo -e " ${BLUE}额外id(alterid)：${PLAIN} ${RED}${alterid}${PLAIN}"
            echo -e " ${BLUE}加密方式(security)：${PLAIN} ${RED}none${PLAIN}"
            echo -e " ${BLUE}传输协议(network)：${PLAIN} ${RED}${network}${PLAIN}" 
            echo -e " ${BLUE}伪装域名/主机名(host)：${PLAIN}${RED}${domain}${PLAIN}"
            echo -e " ${BLUE}底层安全传输(tls)：${PLAIN}${RED}TLS${PLAIN}"
            echo  
            echo -e " ${BLUE}vmess链接: ${PLAIN}$RED$link$PLAIN"
        else
            raw="{
  \"v\":\"2\",
  \"ps\":\"\",
  \"add\":\"$ip\",
  \"port\":\"${port}\",
  \"id\":\"${uid}\",
  \"aid\":\"$alterid\",
  \"net\":\"${network}\",
  \"type\":\"none\",
  \"host\":\"${domain}\",
  \"path\":\"${wspath}\",
  \"tls\":\"tls\"
}"
            link=`echo -n ${raw} | base64 -w 0`
            link="vmess://${link}"

            echo -e " ${BLUE}IP(address): ${PLAIN} ${RED}${ip}${PLAIN}"
            echo -e " ${BLUE}端口(port)：${PLAIN}${RED}${port}${PLAIN}"
            echo -e " ${BLUE}id(uuid)：${PLAIN}${RED}${uid}${PLAIN}"
            echo -e " ${BLUE}额外id(alterid)：${PLAIN} ${RED}${alterid}${PLAIN}"
            echo -e " ${BLUE}加密方式(security)：${PLAIN} ${RED}none${PLAIN}"
            echo -e " ${BLUE}传输协议(network)：${PLAIN} ${RED}${network}${PLAIN}" 
            echo -e " ${BLUE}伪装类型(type)：${PLAIN}${RED}none{$PLAIN}"
            echo -e " ${BLUE}伪装域名/主机名(host)：${PLAIN}${RED}${domain}${PLAIN}"
            echo -e " ${BLUE}路径(path)：${PLAIN}${RED}${wspath}${PLAIN}"
            echo -e " ${BLUE}底层安全传输(tls)：${PLAIN}${RED}TLS${PLAIN}"
            echo  
            echo -e " ${BLUE}vmess链接:${PLAIN} $RED$link$PLAIN"
        fi
    else
        echo -e " ${BLUE}协议: ${PLAIN} ${RED}VLESS${PLAIN}"
        if [[ "$xtls" = "true" ]]; then
            echo -e " ${BLUE}IP(address): ${PLAIN} ${RED}${ip}${PLAIN}"
            echo -e " ${BLUE}端口(port)：${PLAIN}${RED}${port}${PLAIN}"
            echo -e " ${BLUE}id(uuid)：${PLAIN}${RED}${uid}${PLAIN}"
            echo -e " ${BLUE}流控(flow)：${PLAIN}$RED$flow${PLAIN}"
            echo -e " ${BLUE}加密(encryption)：${PLAIN} ${RED}none${PLAIN}"
            echo -e " ${BLUE}传输协议(network)：${PLAIN} ${RED}${network}${PLAIN}" 
            echo -e " ${BLUE}伪装类型(type)：${PLAIN}${RED}none$PLAIN"
            echo -e " ${BLUE}伪装域名/主机名(host)：${PLAIN}${RED}${domain}${PLAIN}"
            echo -e " ${BLUE}底层安全传输(tls)：${PLAIN}${RED}XTLS${PLAIN}"
            echo  
        elif [[ "$ws" = "false" ]]; then
            echo -e " ${BLUE}IP(address):  ${PLAIN}${RED}${ip}${PLAIN}"
            echo -e " ${BLUE}端口(port)：${PLAIN}${RED}${port}${PLAIN}"
            echo -e " ${BLUE}id(uuid)：${PLAIN}${RED}${uid}${PLAIN}"
            echo -e " ${BLUE}流控(flow)：${PLAIN}$RED$flow${PLAIN}"
            echo -e " ${BLUE}加密(encryption)：${PLAIN} ${RED}none${PLAIN}"
            echo -e " ${BLUE}传输协议(network)：${PLAIN} ${RED}${network}${PLAIN}" 
            echo -e " ${BLUE}伪装类型(type)：${PLAIN}${RED}none{$PLAIN}"
            echo -e " ${BLUE}伪装域名/主机名(host)：${PLAIN}${RED}${domain}${PLAIN}"
            echo -e " ${BLUE}底层安全传输(tls)：${PLAIN}${RED}TLS${PLAIN}"
            echo  
        else
            echo -e " ${BLUE}IP(address): ${PLAIN} ${RED}${ip}${PLAIN}"
            echo -e " ${BLUE}端口(port)：${PLAIN}${RED}${port}${PLAIN}"
            echo -e " ${BLUE}id(uuid)：${PLAIN}${RED}${uid}${PLAIN}"
            echo -e " ${BLUE}流控(flow)：${PLAIN}$RED$flow${PLAIN}"
            echo -e " ${BLUE}加密(encryption)：${PLAIN} ${RED}none${PLAIN}"
            echo -e " ${BLUE}传输协议(network)：${PLAIN} ${RED}${network}${PLAIN}" 
            echo -e " ${BLUE}伪装类型(type)：${PLAIN}${RED}none{$PLAIN}"
            echo -e " ${BLUE}伪装域名/主机名(host)：${PLAIN}${RED}${domain}${PLAIN}"
            echo -e " ${BLUE}路径(path)：${PLAIN}${RED}${wspath}${PLAIN}"
            echo -e " ${BLUE}底层安全传输(tls)：${PLAIN}${RED}TLS${PLAIN}"
            echo  
        fi
    fi
    echo ""
}

showLog() {
    res=`status`
    if [[ $res -lt 2 ]]; then
        colorEcho $RED " V2ray未安装，请先安装！"
        return
    fi

    journalctl -xen -u v2ray --no-pager
}

menu() {
    clear
    echo "#############################################################"
    colorEcho $RED "#                    v2ray一键安装脚本                      #"
    echo -e "# ${GREEN}作者${PLAIN}: 网络跳越(hijk)                                      #"
    echo -e "# ${GREEN}网址${PLAIN}: https://hijk.art                                    #"
    echo -e "# ${GREEN}论坛${PLAIN}: https://hijk.club                                   #"
    echo -e "# ${GREEN}TG群${PLAIN}: https://t.me/hijkclub                               #"
    echo -e "# ${GREEN}Youtube频道${PLAIN}: https://youtube.com/channel/UCYTB--VsObzepVJtc9yvUxQ #"
    echo "#############################################################"
    echo ""

    echo -e "  ${GREEN}1.${PLAIN}   安装V2ray-VMESS"
    echo -e "  ${GREEN}2.${PLAIN}   安装V2ray-VMESS+TCP+TLS"
    echo -e "  ${GREEN}3.${PLAIN}   安装V2ray-VMESS+WS+TLS${RED}(推荐)${PLAIN}"
    echo -e "  ${GREEN}4.${PLAIN}   安装V2ray-VLESS+TCP+TLS"
    echo -e "  ${GREEN}5.${PLAIN}   安装V2ray-VLESS+WS+TLS${RED}(可过cdn)${PLAIN}"
    echo -e "  ${GREEN}6.${PLAIN}   安装V2ray-VLESS+TCP+XTLS${RED}(推荐)${PLAIN}"
    echo -e "  ${GREEN}7.${PLAIN}   安装trojan"
    echo -e "  ${GREEN}8.${PLAIN}   安装trojan+XTLS${RED}(推荐)${PLAIN}"
    echo " -------------"
    echo -e "  ${GREEN}10.${PLAIN}  更新V2ray"
    echo -e "  ${GREEN}11.${PLAIN}  卸载V2ray"
    echo " -------------"
    echo -e "  ${GREEN}13.${PLAIN}  启动V2ray"
    echo -e "  ${GREEN}14.${PLAIN}  重启V2ray"
    echo -e "  ${GREEN}15.${PLAIN}  停止V2ray"
    echo " -------------"
    echo -e "  ${GREEN}16.${PLAIN}  查看V2ray信息"
    echo -e "  ${GREEN}17.${PLAIN}  查看V2ray日志"
    echo " -------------"
    echo -e "  ${GREEN}0.${PLAIN} 退出"
    echo 
    echo -n " 当前状态："
    statusText
    echo 

    read -p " 请选择操作[0-9]：" answer
    case $answer in
        0)
            exit 0
            ;;
        1)
            install
            ;;
        2)
            TLS="true"
            install
            ;;
        3)
            TLS="true"
            WS="true"
            install
            ;;
        4)
            VLESS="true"
            TLS="true"
            install
            ;;
        5)
            VLESS="true"
            TLS="true"
            WS="true"
            install
            ;;
        6)
            VLESS="true"
            TLS="true"
            XTLS="true"
            install
            ;;
        7)
            colorEcho $RED " 尚未支持trojan，请过一段时间重试"
            ;;
        8)
            colorEcho $RED " 尚未支持trojan+XTLS，请过一段时间重试"
            ;;
        10)
            update
            ;;
        11)
            uninstall
            ;;
        13)
            start
            ;;
        14)
            restart
            ;;
        15)
            stop
            ;;
        16)
            showInfo
            ;;
        17)
            showLog
            ;;
        *)
            colorEcho $RED " 请选择正确的操作！"
            exit 1
            ;;
    esac
}

checkSystem

menu
