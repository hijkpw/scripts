#!/bin/bash
# v2ray Ubuntu系统一键安装脚本
# Author: hijk<https://hijk.pp.a>

echo "#############################################################"
echo "#         Ubuntu 16.04 TLS v2ray 带伪装一键安装脚本           #"
echo "# 网址: https://hijk.art                                  #"
echo "# 作者: hijk                                                #"
echo "#############################################################"
echo ""

red='\033[0;31m'
green="\033[0;32m"
plain='\033[0m'

sites=(
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

function checkSystem()
{
    result=$(id | awk '{print $1}')
    if [ $result != "uid=0(root)" ]; then
        echo "请以root身份执行该脚本"
        exit 1
    fi

    res=`lsb_release -d | grep -i ubuntu`
    if [ "$?" != "0" ]; then
        res=`which apt`
        if [ "$?" != "0" ]; then
            echo "系统不是Ubuntu"
            exit 1
        fi
        res=`which systemctl`
         if [ "$?" != "0" ]; then
            echo "系统版本过低，请重装系统到高版本后再使用本脚本！"
            exit 1
         fi
    else
        result=`lsb_release -d | grep -oE "[0-9.]+"`
        main=${result%%.*}
        if [ $main -lt 16 ]; then
            echo "不受支持的Ubuntu版本"
            exit 1
        fi
     fi
}

function getData()
{
    IP=`curl -s -4 icanhazip.com`
    echo " "
    echo " 本脚本为带伪装的一键脚本，运行之前请确认如下条件已经具备："
    echo -e "  ${red}1. 一个域名${plain}"
    echo -e "  ${red}2. 域名的某个主机名解析指向当前服务器ip（${IP}）${plain}"
    echo " "
    read -p "确认满足按y，按其他退出脚本：" answer
    [ "${answer}" != "y" ] && exit 0

    while true
    do
        read -p "请输入您的主机名：" domain
        if [ -z "${domain}" ]; then
            echo "主机名输入错误，请重新输入！"
        else
            break
        fi
    done
    
    domain=${domain,,}
    resolve=`curl -s https://hijk.art/hostip.php?d=${domain}`
    res=`echo -n ${resolve} | grep ${IP}`
    if [ -z "${res}" ]; then
        echo "${domain} 解析结果：${resolve}"
        echo -e "${red}主机未解析到当前服务器IP(${IP})!${plain}"
        exit 1
    fi

    while true
    do
        read -p "请输入伪装路径，以/开头：" path
        if [ -z "${path}" ]; then
            echo "请输入伪装路径，以/开头！"
        elif [ "${path:0:1}" != "/" ]; then
            echo "伪装路径必须以/开头！"
        elif [ "${path}" = "/" ]; then
            echo  "不能使用根路径！"
        else
            break
        fi
    done
    
    read -p "请输入Nginx端口[100-65535的一个数字，默认443]：" port
    [ -z "${port}" ] && port=443
    if [ "${port:0:1}" = "0" ]; then
        echo -e "${red}端口不能以0开头${plain}"
        exit 1
    fi
    
    read -p "是否安装BBR（安装请按y，不安装请输n，不输则默认安装）:" needBBR
    [ -z "$needBBR" ] && needBBR=y
    [ "$needBBR" = "Y" ] && needBBR=y

    len=${#sites[@]}
    ((len--))
    while true
    do
        index=`shuf -i0-${len} -n1`
        site=${sites[$index]}
        host=`echo ${site} | cut -d/ -f3`
        ip=`curl -s https://hijk.art/hostip.php?d=${host} | grep -oE "[1-9][0-9.]+[0-9]"`
        if [ "$ip" != "" ]; then
            echo "${ip}  ${host}" >> /etc/hosts
            break
        fi
    done
}

function preinstall()
{
    sed -i 's/#ClientAliveInterval 0/ClientAliveInterval 60/' /etc/ssh/sshd_config
    systemctl restart sshd
    ret=`nginx -t`
    if [ "$?" != "0" ]; then
        echo "更新系统..."
        apt update && apt -y upgrade
    fi
    echo "安装必要软件"
    apt install -y telnet wget vim net-tools ntpdate unzip gcc g++
    apt autoremove -y
    res=`which wget`
    [ "$?" != "0" ] && apt install -y wget
    res=`which netstat`
    [ "$?" != "0" ] && apt install -y net-tools
}

function installV2ray()
{
    echo 安装v2ray...
    bash <(curl -sL https://raw.githubusercontent.com/hijkpw/scripts/master/goV2.sh)

    if [ ! -f /etc/v2ray/config.json ]; then
        echo "安装失败，请到 https://hijk.art 网站反馈"
        exit 1
    fi

    logsetting=`cat /etc/v2ray/config.json|grep loglevel`
    if [ "${logsetting}" = "" ]; then
        sed -i '1a\  "log": {\n    "loglevel": "info",\n    "access": "/var/log/v2ray/access.log",\n    "error": "/var/log/v2ray/error.log"\n  },' /etc/v2ray/config.json
    fi
    alterid=0
    sed -i -e "s/alterId\":.*[0-9]*/alterId\": ${alterid}/" /etc/v2ray/config.json
    uid=`cat /etc/v2ray/config.json | grep id | cut -d: -f2 | tr -d \",' '`
    v2port=`cat /etc/v2ray/config.json | grep port | cut -d: -f2 | tr -d \",' '`
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
    ntpdate -u time.nist.gov
    res=`cat /etc/v2ray/config.json | grep streamSettings`
    if [ "$res" = "" ]; then
        line=`grep -n '}]' /etc/v2ray/config.json  | head -n1 | cut -d: -f1`
        line=`expr ${line} - 1`
        sed -i "${line}s/}/},/" /etc/v2ray/config.json
        sed -i "${line}a\    \"streamSettings\": {\n      \"network\": \"ws\",\n      \"wsSettings\": {\n        \"path\": \"${path}\",\n        \"headers\": {\n          \"Host\": \"${domain}\"\n        }\n      }\n    },\n    \"listen\": \"127.0.0.1\"" /etc/v2ray/config.json
    else
        sed -i -e "s/path\":.*/path\": \"\\${path}\",/" /etc/v2ray/config.json
    fi
    echo "0 3 */3 * * root echo '' > /var/log/v2ray/access.log; echo ''>/var/log/v2ray/error.log" >> /etc/crontab
    systemctl enable v2ray
    systemctl restart v2ray
    sleep 3
    res=`netstat -ntlp| grep ${v2port} | grep v2ray`
    if [ "${res}" = "" ]; then
        sed -i '/Capabili/d' /etc/systemd/system/v2ray.service
        sed -i '/AmbientCapabilities/d' /etc/systemd/system/v2ray.service
        sed -i '/Capabili/d' /etc/systemd/system/multi-user.target.wants/v2ray.service
        sed -i '/AmbientCapabilities/d' /etc/systemd/system/multi-user.target.wants/v2ray.service
        systemctl daemon-reload
        systemctl restart v2ray
        sleep 3
        res=`netstat -ntlp| grep ${v2port} | grep v2ray`
        if [ "${res}" = "" ]; then
            echo "端口号：${port}，伪装路径：${path}， v2启动失败，请检查端口是否被占用或伪装路径是否有特殊字符！！"
            exit 1
         fi
    fi
    echo "v2ray安装成功！"
}

function installNginx()
{
    apt install -y nginx
    systemctl stop nginx
    res=`netstat -ntlp| grep -E ':80 |:443 '`
    if [ "${res}" != "" ]; then
        echo " 其他进程占用了80或443端口，请先关闭再运行一键脚本"
        echo " 端口占用信息如下："
        echo ${res}
        exit 1
    fi
    res=`which pip3`
    if [ "$?" != "0" ]; then
        apt install -y python3-pip python3-setuptools python3-dev
    fi
    res=`which pip3`
    if [ "$?" != "0" ]; then
        echo -e " pip3安装失败，请到 ${red}https://hijk.pp.a${plain} 反馈"
        exit 1
    fi
    pip3 install --upgrade pip
    pip3 install wheel
    res=`pip3 list | grep crypto | awk '{print $2}'`
    if [[ "$res" < "2.8" ]]; then
        pip3 uninstall -y cryptography
        cd /usr/lib/python3/dist-packages
        rm -r cryptoggraphy cryptography-2.1.4.egg-info
        cd -
        pip3 install cryptography
    fi
    pip3 install certbot
    res=`which certbot`
    if [ "$?" != "0" ]; then
        export PATH=$PATH:/usr/local/bin
    fi
    certbot certonly --standalone --agree-tos --register-unsafely-without-email -d ${domain}
    if [ "$?" != "0" ]; then
        echo -e " 获取证书失败，请到 ${red}https://hijk.art${plain} 反馈"
        exit 1
    fi

    if [ ! -f /etc/nginx/nginx.conf.bak ]; then
        mv /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak
    fi
    echo 'User-Agent: *' > /usr/share/nginx/html/robots.txt
    echo 'Disallow: /' >> /usr/share/nginx/html/robots.txt
    cat > /etc/nginx/nginx.conf<<-EOF
user www-data;
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

    mkdir -p /etc/nginx/conf.d;
    cat > /etc/nginx/conf.d/${domain}.conf<<-EOF
server {
    listen 80;
    server_name ${domain};
    rewrite ^(.*) https://\$server_name:${port}\$1 permanent;
}

server {
    listen       ${port} ssl http2;
    server_name ${domain};
    charset utf-8;

    # ssl配置
    ssl_protocols TLSv1.1 TLSv1.2;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE:ECDH:AES:HIGH:!NULL:!aNULL:!MD5:!ADH:!RC4;
    ssl_ecdh_curve secp384r1;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_session_tickets off;
    ssl_certificate /etc/letsencrypt/live/${domain}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${domain}/privkey.pem;

    access_log  /var/log/nginx/${domain}.access.log;
    error_log /var/log/nginx/${domain}.error.log;

    root /usr/share/nginx/html;
    location / {
        proxy_pass $site;
    }
    location = /robots.txt {
    }

    location ${path} {
      proxy_redirect off;
      proxy_pass http://127.0.0.1:${v2port};
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
    sed -i '/certbot/d' /etc/crontab
    certbotpath=`which certbot`
    echo "0 3 1 */2 0 root systemctl stop nginx; ${certbotpath} renew; systemctl restart nginx" >> /etc/crontab
    systemctl enable nginx && systemctl restart nginx
    sleep 3
    res=`netstat -nltp | grep ${port} | grep nginx`
    if [ "${res}" = "" ]; then
        echo -e "nginx启动失败！ 请到 ${red}https://hijk.art${plain} 反馈"
        exit 1
    fi
}

function setFirewall()
{
    res=`ufw status | grep -i inactive`
    if [ "$res" = "" ];then
        ufw allow http/tcp
        ufw allow https/tcp
        ufw allow ${port}/tcp
    fi
}

function installBBR()
{
    if [ "$needBBR" != "y" ]; then
        bbr=true
        return
    fi
    result=$(lsmod | grep bbr)
    if [ "$result" != "" ]; then
        echo BBR模块已安装
        bbr=true
        echo "3" > /proc/sys/net/ipv4/tcp_fastopen
        echo "net.ipv4.tcp_fastopen = 3" >> /etc/sysctl.conf
        return;
    fi
    
    res=`hostnamectl | grep -i openvz`
    if [ "$res" != "" ]; then
        echo openvz机器，跳过安装
        bbr=true
        return
    fi

    echo 安装BBR模块...
    apt install -y --install-recommends linux-generic-hwe-16.04
    grub-set-default 0
    echo "tcp_bbr" >> /etc/modules-load.d/modules.conf
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    echo "3" > /proc/sys/net/ipv4/tcp_fastopen
    echo "net.ipv4.tcp_fastopen = 3" >> /etc/sysctl.conf
    bbr=false
}

function info()
{
    if [ ! -f /etc/v2ray/config.json ]; then
        echo "v2ray未安装"
        exit 1
    fi
    
    ip=`curl -s -4 icanhazip.com`
    res=`netstat -nltp | grep v2ray`
    [ -z "$res" ] && v2status="${red}已停止${plain}" || v2status="${green}正在运行${plain}"
    
    uid=`cat /etc/v2ray/config.json | grep id | cut -d: -f2 | tr -d \",' '`
    alterid=`cat /etc/v2ray/config.json | grep alterId | cut -d: -f2 | tr -d \",' '`
    network=`cat /etc/v2ray/config.json | grep network | cut -d: -f2 | tr -d \",' '`
    domain=`cat /etc/v2ray/config.json | grep Host | cut -d: -f2 | tr -d \",' '`
    if [ -z "$domain" ]; then
        echo "不是伪装版本的v2ray"
        exit 1
    fi
    path=`cat /etc/v2ray/config.json | grep path | cut -d: -f2 | tr -d \",' '`
    port=`cat /etc/nginx/conf.d/${domain}.conf | grep -i ssl | head -n1 | awk '{print $2}'`
    security="auto"
    res=`netstat -nltp | grep ${port} | grep nginx`
    [ -z "$res" ] && ngstatus="${red}已停止${plain}" || ngstatus="${green}正在运行${plain}"
    
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
  \"path\":\"${path}\",
  \"tls\":\"tls\"
}"
    link=`echo -n ${raw} | base64 -w 0`
    link="vmess://${link}"

    
    echo ============================================
    echo -e " v2ray运行状态：${v2status}"
    echo -e " v2ray配置文件：${red}/etc/v2ray/config.json${plain}"
    echo -e " nginx运行状态：${ngstatus}"
    echo -e " nginx配置文件：${red}${confpath}${domain}.conf${plain}"
    echo ""
    echo -e "${red}v2ray配置信息：${plain}               "
    echo -e " IP(address):  ${red}${ip}${plain}"
    echo -e " 端口(port)：${red}${port}${plain}"
    echo -e " id(uuid)：${red}${uid}${plain}"
    echo -e " 额外id(alterid)： ${red}${alterid}${plain}"
    echo -e " 加密方式(security)： ${red}$security${plain}"
    echo -e " 传输协议(network)： ${red}${network}${plain}" 
    echo -e " 主机名(host)：${red}${domain}${plain}"
    echo -e " 路径(path)：${red}${path}${plain}"
    echo -e " 安全传输(security)：${red}TLS${plain}"
    echo  
    echo "vmess链接: $link"
}

function bbrReboot()
{
    if [ "${bbr}" == "false" ]; then
        echo  
        echo  为使BBR模块生效，系统将在30秒后重启
        echo  
        echo -e "您可以按 ctrl + c 取消重启，稍后输入 ${red}reboot${plain} 重启系统"
        sleep 30
        reboot
    fi
}


function install()
{
    echo -n "系统版本:  "
    lsb_release -a

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

function uninstall()
{
    read -p "您确定真的要卸载v2ray吗？(y/n)" answer
    [ -z ${answer} ] && answer="n"

    if [ "${answer}" == "y" ] || [ "${answer}" == "Y" ]; then
        systemctl stop v2ray
        systemctl disable v2ray
        domain=`cat /etc/v2ray/config.json | grep Host | cut -d: -f2 | tr -d \",' '`
        rm -rf /etc/v2ray/*
        rm -rf /usr/bin/v2ray/*
        rm -rf /var/log/v2ray/*
        rm -rf /etc/systemd/system/v2ray.service
        rm -rf /etc/systemd/system/multi-user.target.wants/v2ray.service

        apt remove -y nginx
        apt autoremove -y
        if [ -d /usr/share/nginx/html.bak ]; then
            rm -rf /usr/share/nginx/html
            mv /usr/share/nginx/html.bak /usr/share/nginx/html
        fi
        rm -rf /etc/nginx/conf.d/${domain}.conf
        echo -e " ${red}卸载成功${plain}"
    fi
}

action=$1
[ -z $1 ] && action=install
case "$action" in
    install|uninstall|info)
        ${action}
        ;;
    *)
        echo "参数错误"
        echo "用法: `basename $0` [install|uninstall|info]"
        ;;
esac
