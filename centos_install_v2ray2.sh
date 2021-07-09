#!/bin/bash
# v2ray centos系统一键安装脚本
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
#http://www.xiaoshuosk.com/
#https://www.quledu.net/
http://www.ddxsku.com/
http://www.biqu6.com/
https://www.wenshulou.cc/
#http://www.auutea.com/
http://www.55shuba.com/
http://www.39shubao.com/
https://www.23xsw.cc/
#https://www.huanbige.com/
https://www.jueshitangmen.info/
https://www.zhetian.org/
http://www.bequgexs.com/
http://www.tjwl.com/
)

CONFIG_FILE="/etc/v2ray/config.json"

OS=`hostnamectl | grep -i system | cut -d: -f2`

V6_PROXY=""
IP=`curl -sL -4 ip.sb`
if [[ "$?" != "0" ]]; then
    IP=`curl -sL -6 ip.sb`
    V6_PROXY="https://gh.hijk.art/"
fi

BT="false"
NGINX_CONF_PATH="/etc/nginx/conf.d/"

res=`which bt 2>/dev/null`
if [[ "$res" != "" ]]; then
    BT="true"
    NGINX_CONF_PATH="/www/server/panel/vhost/nginx/"
fi

checkSystem() {
    result=$(id | awk '{print $1}')
    if [[ $result != "uid=0(root)" ]]; then
        echo "请以root身份执行该脚本"
        exit 1
    fi

    if [[ ! -f /etc/centos-release ]];then
        res=`which yum`
        if [[ "$?" != "0" ]]; then
            echo "系统不是CentOS"
            exit 1
         fi
         res=`which systemctl`
         if [[ "$?" != "0" ]]; then
            echo "系统版本过低，请重装系统到高版本后再使用本脚本！"
            exit 1
         fi
    else
        result=`cat /etc/centos-release|grep -oE "[0-9.]+"`
        main=${result%%.*}
        if [[ $main -lt 7 ]]; then
            echo "不受支持的CentOS版本"
            exit 1
         fi
    fi
}

colorEcho() {
    echo -e "${1}${@:2}${PLAIN}"
}

slogon() {
    clear
    echo "#############################################################"
    echo -e "#         ${RED}CentOS 7/8 v2ray 带伪装一键安装脚本${PLAIN}                 #"
    echo -e "# ${GREEN}作者${PLAIN}: 网络跳越(hijk)                                      #"
    echo -e "# ${GREEN}网址${PLAIN}: https://hijk.art                                    #"
    echo -e "# ${GREEN}论坛${PLAIN}: https://hijk.club                                   #"
    echo -e "# ${GREEN}TG群${PLAIN}: https://t.me/hijkclub                               #"
    echo -e "# ${GREEN}Youtube频道${PLAIN}: https://youtube.com/channel/UCYTB--VsObzepVJtc9yvUxQ #"
    echo "#############################################################"
    echo ""
}

getData() {
    echo " "
    echo " 本脚本为带伪装的一键脚本，运行之前请确认如下条件已经具备："
    colorEcho ${YELLOW} "  1. 一个伪装域名"
    colorEcho ${YELLOW} "  2. 伪装域名DNS解析指向当前服务器ip（${IP}）"
    colorEcho ${BLUE} "  3. 如果/root目录下有 v2ray.pem 和 v2ray.key 证书密钥文件，无需理会条件2"
    echo " "
    read -p " 确认满足按y，按其他退出脚本：" answer
    if [[ "${answer}" != "y" ]]; then
        exit 0
    fi

    echo ""
    while true
    do
        read -p " 请输入伪装域名：" DOMAIN
        if [[ -z "${DOMAIN}" ]]; then
            colorEcho $RED " 域名输入错误，请重新输入！"
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
        resolve=`curl -sL https://hijk.art/hostip.php?d=${DOMAIN}`
        res=`echo -n ${resolve} | grep ${IP}`
        if [[ -z "${res}" ]]; then
            colorEcho ${BLUE}  "${DOMAIN} 解析结果：${resolve}"
            colorEcho ${RED}  " 域名未解析到当前服务器IP(${IP})!"
            exit 1
        fi
    fi

    echo ""
    while true
    do
        read -p " 请输入伪装路径，以/开头(不懂请直接回车)：" WSPATH
        if [[ -z "${WSPATH}" ]]; then
            len=`shuf -i5-12 -n1`
            ws=`cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w $len | head -n 1`
            WSPATH="/$ws"
            break
        elif [[ "${WSPATH:0:1}" != "/" ]]; then
            colorEcho ${RED}  " 伪装路径必须以/开头！"
        elif [[ "${WSPATH}" = "/" ]]; then
            colorEcho ${RED}   " 不能使用根路径！"
        else
            break
        fi
    done
    colorEcho ${BLUE}  " 伪装路径：$WSPATH"

    echo ""
    read -p " 请输入Nginx端口[100-65535的一个数字，默认443]：" PORT
    [[ -z "${PORT}" ]] && PORT=443
    if [[ "${PORT:0:1}" = "0" ]]; then
        echo -e " ${RED}端口不能以0开头${PLAIN}"
        exit 1
    fi
    colorEcho ${BLUE}  " Nginx端口：$PORT"

    echo ""
    colorEcho $BLUE " 请选择伪装站类型:" 
    echo "   1) 静态网站(位于/usr/share/nginx/html)"
    echo "   2) 小说站(随机选择)"
    echo "   3) 美女站(https://imeizi.me)"
    echo "   4) 高清壁纸站(https://bing.imeizi.me)"
    echo "   5) 自定义反代站点(需以http或者https开头)"
    read -p "  请选择伪装网站类型[默认:高清壁纸站]" answer
    if [[ -z "$answer" ]]; then
        PROXY_URL="https://bing.imeizi.me"
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
                host=`echo ${PROXY_URL} | cut -d/ -f3`
                ip=`curl -sL https://hijk.art/hostip.php?d=${host}`
                res=`echo -n ${ip} | grep ${host}`
                if [[ "${res}" = "" ]]; then
                    echo "$ip $host" >> /etc/hosts
                    break
                fi
            done
            ;;
        3)
            PROXY_URL="https://imeizi.me"
            ;;
        4)
            PROXY_URL="https://bing.imeizi.me"
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
    REMOTE_HOST=`echo ${PROXY_URL} | cut -d/ -f3`
    echo ""
    colorEcho $BLUE " 伪装网站：$PROXY_URL"

    echo ""
    colorEcho $BLUE "  是否允许搜索引擎爬取网站？[默认：不允许]"
    echo "    y)允许，会有更多ip请求网站，但会消耗一些流量，vps流量充足情况下推荐使用"
    echo "    n)不允许，爬虫不会访问网站，访问ip比较单一，但能节省vps流量"
    read -p "  请选择：[y/n]" answer
    if [[ -z "$answer" ]]; then
        ALLOW_SPIDER="n"
    elif [[ "${answer,,}" = "y" ]]; then
        ALLOW_SPIDER="y"
    else
        ALLOW_SPIDER="n"
    fi
    echo ""
    colorEcho $BLUE " 允许搜索引擎：$ALLOW_SPIDER"

    echo ""
    read -p " 是否安装BBR（安装请按y，不安装请输n，默认安装）:" NEED_BBR
    [[ -z "$NEED_BBR" ]] && NEED_BBR=y
    [[ "$NEED_BBR" = "Y" ]] && NEED_BBR=y
    colorEcho $BLUE " 安装BBR：$NEED_BBR"
}

preinstall() {
    colorEcho $BLUE " 更新系统..."
    yum clean all
    #yum update -y
    colorEcho $BLUE " 安装必要软件"
    yum install -y epel-release telnet wget vim net-tools ntpdate unzip
    res=`which wget`
    [[ "$?" != "0" ]] && yum install -y wget
    res=`which netstat`
    [[ "$?" != "0" ]] && yum install -y net-tools

    if [[ -s /etc/selinux/config ]] && grep 'SELINUX=enforcing' /etc/selinux/config; then
        sed -i 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/selinux/config
        setenforce 0
    fi
}

getCert() {
    mkdir -p /etc/v2ray
    if [[ -z ${CERT_FILE+x} ]]; then
        stopNginx
        systemctl stop v2ray
        res=`netstat -ntlp| grep -E ':80 |:443 '`
        if [[ "${res}" != "" ]]; then
            colorEcho ${RED}  " 其他进程占用了80或443端口，请先关闭再运行一键脚本"
            echo " 端口占用信息如下："
            echo ${res}
            exit 1
        fi

        yum install -y socat openssl cronie
        systemctl enable crond
        systemctl start crond
        curl -sL https://get.acme.sh | sh -s email=hijk.pw@protonmail.ch
        source ~/.bashrc
        ~/.acme.sh/acme.sh  --upgrade  --auto-upgrade
        ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
        if [[ "$BT" = "false" ]]; then
            ~/.acme.sh/acme.sh   --issue -d $DOMAIN --keylength ec-256 --pre-hook "systemctl stop nginx" --post-hook "systemctl restart nginx"  --standalone
        else
            ~/.acme.sh/acme.sh   --issue -d $DOMAIN --keylength ec-256 --pre-hook "nginx -s stop || { echo -n ''; }" --post-hook "nginx -c /www/server/nginx/conf/nginx.conf || { echo -n ''; }"  --standalone
        fi
        [[ -f ~/.acme.sh/${DOMAIN}_ecc/ca.cer ]] || {
            colorEcho $RED " 获取证书失败，请复制上面的红色文字到 https://hijk.art 反馈"
            exit 1
        }
        CERT_FILE="/etc/v2ray/${DOMAIN}.pem"
        KEY_FILE="/etc/v2ray/${DOMAIN}.key"
        ~/.acme.sh/acme.sh  --install-cert -d $DOMAIN --ecc \
            --key-file       $KEY_FILE  \
            --fullchain-file $CERT_FILE \
            --reloadcmd     "service nginx force-reload"
        [[ -f $CERT_FILE && -f $KEY_FILE ]] || {
            colorEcho $RED " 获取证书失败，请到 https://hijk.art 反馈"
            exit 1
        }
    else
        cp ~/v2ray.pem /etc/v2ray/${DOMAIN}.pem
        cp ~/v2ray.key /etc/v2ray/${DOMAIN}.key
    fi
}

installV2ray() {
    colorEcho $BLUE " 安装v2ray..."
    bash <(curl -sL ${V6_PROXY}https://raw.githubusercontent.com/hijkpw/scripts/master/goV2.sh)

    if [[ ! -f $CONFIG_FILE ]]; then
        colorEcho $RED " $OS 安装V2ray失败，请到 https://hijk.art 网站反馈"
        exit 1
    fi

    alterid=0
    sed -i -e "s/alterId\":.*[0-9]*/alterId\": ${alterid}/" $CONFIG_FILE
    uid=`grep id $CONFIG_FILE| cut -d: -f2 | tr -d \",' '`
    V2PORT=`grep port $CONFIG_FILE| cut -d: -f2 | tr -d \",' '`
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
    ntpdate -u time.nist.gov

    res=`grep streamSettings $CONFIG_FILE`
    if [[ "$res" = "" ]]; then
        line=`grep -n '}]' $CONFIG_FILE  | head -n1 | cut -d: -f1`
        line=`expr ${line} - 1`
        sed -i "${line}s/}/},/" $CONFIG_FILE
        sed -i "${line}a\    \"streamSettings\": {\n      \"network\": \"ws\",\n      \"wsSettings\": {\n        \"path\": \"${WSPATH}\",\n        \"headers\": {\n          \"Host\": \"${DOMAIN}\"\n        }\n      }\n    },\n    \"listen\": \"127.0.0.1\"" $CONFIG_FILE
    else
        sed -i -e "s/path\":.*/path\": \"\\${WSPATH}\",/" $CONFIG_FILE
    fi

    systemctl enable v2ray
    systemctl restart v2ray
    sleep 3
    res=`ss -ntlp| grep ${V2PORT} | grep v2ray`
    if [[ "${res}" = "" ]]; then
        colorEcho $RED " $OS 端口号：${PORT}，伪装路径：${WSPATH}， v2启动失败，请检查端口是否被占用或伪装路径是否有特殊字符！！"
        exit 1
    fi
    colorEcho $GREEN " v2ray安装成功！"
}

installNginx() {
    if [[ "$BT" = "false" ]]; then
        yum install -y nginx
        res=$(command -v nginx)
        if [[ "$res" = "" ]]; then
            colorEcho $RED " Nginx安装失败，请到 https://hijk.art 反馈"
            exit 1
        fi
        systemctl enable nginx
    else
        res=$(command -v nginx)
        if [[ "$res" = "" ]]; then
            colorEcho $RED " 您安装了宝塔，请在宝塔后台安装nginx后再运行本脚本"
            exit 1
        fi
    fi
    
    getCert

    if [[ "$BT" = "false" ]]; then
        if [ ! -f /etc/nginx/nginx.conf.bak ]; then
            mv /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak
        fi
        cat > /etc/nginx/nginx.conf<<-EOF
user nginx;
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

    gzip                on;
    sendfile            on;
    tcp_nopush          on;
    tcp_nodelay         on;
    keepalive_timeout   65;
    types_hash_max_size 2048;

    include             /etc/nginx/mime.types;
    default_type        application/octet-stream;

    # Load modular configuration files from the /etc/nginx/conf.d directory.
    # See http://nginx.org/en/docs/ngx_core_module.html#include
    # for more information.
    include /etc/nginx/conf.d/*.conf;
}
EOF

        mkdir -p /etc/nginx/conf.d
    fi
    
    mkdir -p /usr/share/nginx/html
    if [[ "$ALLOW_SPIDER" = "n" ]]; then
        echo 'User-Agent: *' > /usr/share/nginx/html/robots.txt
        echo 'Disallow: /' >> /usr/share/nginx/html/robots.txt
    fi
    if [[ "$PROXY_URL" = "" ]]; then
        action=""
    else
        action="proxy_ssl_server_name on;
        proxy_pass $PROXY_URL;
        proxy_set_header Accept-Encoding '';
        sub_filter \"$REMOTE_HOST\" \"$DOMAIN\";
        sub_filter_once off;"
    fi
    cat > ${NGINX_CONF_PATH}${DOMAIN}.conf<<-EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};
    return 301 https://\$server_name:${PORT}\$request_uri;
}

server {
    listen       ${PORT} ssl http2;
    listen       [::]:${PORT} ssl http2;
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
    
    # placeholder
    # placeholder

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

    startNginx
    systemctl start v2ray
    
    sleep 3
    res=`netstat -nltp | grep ${PORT} | grep nginx`
    if [[ "${res}" = "" ]]; then
        nginx -t
        echo -e " nginx启动失败！ 请到 ${RED}https://hijk.art${PLAIN} 反馈"
        exit 1
    fi
}

startNginx() {
    if [[ "$BT" = "false" ]]; then
        systemctl start nginx
    else
        nginx -c /www/server/nginx/conf/nginx.conf
    fi
}

stopNginx() {
    if [[ "$BT" = "false" ]]; then
        systemctl stop nginx
    else
        res=`ps aux | grep -i nginx`
        if [[ "$res" != "" ]]; then
            nginx -s stop
        fi
    fi
}

function setFirewall()
{
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
}

installBBR() {
    if [[ "$NEED_BBR" != "y" ]]; then
        INSTALL_BBR=false
        return
    fi
    result=$(lsmod | grep bbr)
    if [[ "$result" != "" ]]; then
        colorEcho $YELLOW " BBR模块已安装"
        INSTALL_BBR=false
        return;
    fi
    res=`hostnamectl | grep -i openvz`
    if [[ "$res" != "" ]]; then
        colorEcho $YELLOW " openvz机器，跳过安装"
        INSTALL_BBR=false
        return
    fi
    
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p
    result=$(lsmod | grep bbr)
    if [[ "$result" != "" ]]; then
        colorEcho $GREEN " BBR模块已启用"
        INSTALL_BBR=false
        return
    fi

    colorEcho $BLUE " 安装BBR模块..."
    if [[ "$V6_PROXY" = "" ]]; then
        rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
        rpm -Uvh http://www.elrepo.org/elrepo-release-7.0-4.el7.elrepo.noarch.rpm
        yum --enablerepo=elrepo-kernel install kernel-ml -y
        grub2-set-default 0
        echo "tcp_bbr" >> /etc/modules-load.d/modules.conf
        INSTALL_BBR=true
    fi
}

info() {
    if [[ ! -f $CONFIG_FILE ]]; then
        echo -e " ${RED}未安装v2ray!${PLAIN}"
        exit 1
    fi

    res=`netstat -nltp | grep v2ray`
    [[ -z "$res" ]] && v2status="${RED}已停止${PLAIN}" || v2status="${GREEN}正在运行${PLAIN}"
    
    uid=`grep id $CONFIG_FILE| cut -d: -f2 | tr -d \",' '`
    alterid=`grep alterId $CONFIG_FILE| cut -d: -f2 | tr -d \",' '`
    network=`grep network $CONFIG_FILE| cut -d: -f2 | tr -d \",' '`
    domain=`grep Host $CONFIG_FILE| cut -d: -f2 | tr -d \",' '`
    if [[ -z "$domain" ]]; then
        colorEcho $RED " 不是伪装版本的v2ray"
        exit 1
    fi
    path=`grep path $CONFIG_FILE| cut -d: -f2 | tr -d \",' '`
    port=`cat ${NGINX_CONF_PATH}${domain}.conf | grep -i ssl | head -n1 | awk '{print $2}'`
    security="none"
    
    res=`netstat -nltp | grep ${port} | grep nginx`
    [[ -z "$res" ]] && ngstatus="${RED}已停止${PLAIN}" || ngstatus="${GREEN}正在运行${PLAIN}"
    
    raw="{
  \"v\":\"2\",
  \"ps\":\"\",
  \"add\":\"$IP\",
  \"port\":\"${port}\",
  \"id\":\"${uid}\",
  \"aid\":\"$alterid\",
  \"net\":\"${network}\",
  \"type\":\"none\",
  \"host\":\"${domain}\",
  \"path\":\"${path}\",
  \"tls\":\"tls\"
}"
    link=`echo -n ${raw} | base64 -w 0`
    link="vmess://${link}"

    
    echo ============================================
    echo -e " ${BLUE}v2ray运行状态：${PLAIN}${v2status}"
    echo -e " ${BLUE}v2ray配置文件：${PLAIN}${RED}$CONFIG_FILE${PLAIN}"
    echo -e " ${BLUE}nginx运行状态：${PLAIN}${ngstatus}"
    echo -e " ${BLUE}nginx配置文件：${PLAIN}${RED}${NGINX_CONF_PATH}${domain}.conf${PLAIN}"
    echo ""
    echo -e " ${RED}v2ray配置信息：${PLAIN}               "
    echo -e "   ${BLUE}IP(address): ${PLAIN} ${RED}${IP}${PLAIN}"
    echo -e "   ${BLUE}端口(port)：${PLAIN}${RED}${port}${PLAIN}"
    echo -e "   ${BLUE}id(uuid)：${PLAIN}${RED}${uid}${PLAIN}"
    echo -e "   ${BLUE}额外id(alterid)：${PLAIN} ${RED}${alterid}${PLAIN}"
    echo -e "   ${BLUE}加密方式(security)：${PLAIN} ${RED}$security${PLAIN}"
    echo -e "   ${BLUE}传输协议(network)：${PLAIN} ${RED}${network}${PLAIN}" 
    echo -e "   ${BLUE}伪装类型(type)：${PLAIN}${RED}none${PLAIN}"
    echo -e "   ${BLUE}伪装域名/主机名(host)/SNI/peer名称：${PLAIN}${RED}${domain}${PLAIN}"
    echo -e "   ${BLUE}路径(path)：${PLAIN}${RED}${path}${PLAIN}"
    echo -e "   ${BLUE}底层安全传输(tls)：${PLAIN}${RED}TLS${PLAIN}"
    echo  
    echo -e " ${BLUE}vmess链接:${PLAIN} $link"
}

bbrReboot() {
    if [[ "${INSTALL_BBR}" == "true" ]]; then
        echo  
        colorEcho $BLUE " 为使BBR模块生效，系统将在30秒后重启"
        echo  
        echo -e " 您可以按 ctrl + c 取消重启，稍后输入 ${RED}reboot${PLAIN} 重启系统"
        sleep 30
        reboot
    fi
}


install() {
    checkSystem
    getData
    preinstall
    installBBR
    installV2ray
    setFirewall
    installNginx
    
    info
    bbrReboot
}

uninstall() {
    echo ""
    read -p " 确定卸载v2ray吗？(y/n)" answer
    [[ -z ${answer} ]] && answer="n"

    if [[ "${answer}" == "y" ]] || [[ "${answer}" == "Y" ]]; then
        systemctl stop v2ray
        systemctl disable v2ray
        domain=`grep Host $CONFIG_FILE| cut -d: -f2 | tr -d \",' '`
        rm -rf /etc/v2ray/*
        rm -rf /usr/bin/v2ray/*
        rm -rf /var/log/v2ray/*
        rm -rf /etc/systemd/system/v2ray.service

        yum remove -y nginx
        if [[ -d /usr/share/nginx/html.bak ]]; then
            rm -rf /usr/share/nginx/html
            mv /usr/share/nginx/html.bak /usr/share/nginx/html
        fi
        rm -rf /etc/nginx/conf.d/${domain}.conf
        ~/.acme.sh/acme.sh --uninstall
        echo -e " ${RED}卸载成功${PLAIN}"
    fi
}

slogon

action=$1
[[ -z $1 ]] && action=install
case "$action" in
    install|uninstall|info)
        ${action}
        ;;
    *)
        echo " 参数错误"
        echo " 用法: `basename $0` [install|uninstall|info]"
        ;;
esac

