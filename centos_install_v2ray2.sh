#!/bin/bash
# v2ray centos系统一键安装脚本
# Author: hijk<https://www.hijk.pw>

echo "#############################################################"
echo "#         CentOS 7/8 v2ray 带伪装一键安装脚本                  #"
echo "# 网址: https://www.hijk.pw                                 #"
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
        echo "系统不是CentOS"
        exit 1
    fi
    
    result=`cat /etc/centos-release|grep -oE "[0-9.]+"`
    main=${result%%.*}
    if [ $main -lt 7 ]; then
        echo "不受支持的CentOS版本"
        exit 1
    fi
}

function getData()
{
    yum install -y bind-utils curl
    IP=`curl -s -4 icanhazip.com`
    echo " "
    echo " 本脚本为带伪装的一键脚本，运行之前请确认如下条件已经具备："
    echo -e "  ${red}1. 一个域名${plain}"
    echo -e "  ${red}2. 域名的某个主机名解析指向当前服务器ip（${IP}）${plain}"
    echo " "
    read -p "确认满足按y，按其他退出脚本：" answer
    if [ "${answer}" != "y" ]; then
        exit 0
    fi

    while true
    do
        read -p "请输入您的主机名：" domain
        if [ -z "${domain}" ]; then
            echo "主机名输入错误，请重新输入！"
        else
            break
        fi
    done
    
    res=`host ${domain}`
    res=`echo -n ${res} | grep ${IP}`
    if [ -z "${res}" ]; then
        echo "${domain} 未解析到当前服务器IP！"
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
}

function preinstall()
{
    sed -i 's/#ClientAliveInterval 0/ClientAliveInterval 60/' /etc/ssh/sshd_config
    systemctl restart sshd
    ret=`nginx -t`
    if [ "$?" != "0" ]; then
        echo "更新系统..."
        yum update -y
    fi
    echo "安装必要软件"
    yum install -y epel-release telnet wget vim net-tools ntpdate unzip

    if [ -s /etc/selinux/config ] && grep 'SELINUX=enforcing' /etc/selinux/config; then
        sed -i 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/selinux/config
        setenforce 0
    fi
}

function installV2ray()
{
    echo 安装v2ray...
    bash <(curl -L -s https://install.direct/go.sh)

    if [ ! -f /etc/v2ray/config.json ]; then
        echo "安装失败，请到 https://www.hijk.pw 网站反馈"
        exit 1
    fi

    logsetting=`cat /etc/v2ray/config.json|grep loglevel`
    if [ "${logsetting}" = "" ]; then
        sed -i '1a\  "log": {\n    "loglevel": "info",\n    "access": "/var/log/v2ray/access.log",\n    "error": "/var/log/v2ray/error.log"\n  },' /etc/v2ray/config.json
    fi
    alterid=`shuf -i50-90 -n1`
    sed -i -e "s/alterId\":.*[0-9]*/alterId\": ${alterid}/" /etc/v2ray/config.json
    uid=`cat /etc/v2ray/config.json | grep id | cut -d: -f2 | tr -d \",' '`
    port=`cat /etc/v2ray/config.json | grep port | cut -d: -f2 | tr -d \",' '`
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
    ntpdate -u time.nist.gov
    res=`cat /etc/v2ray/config.json | grep streamSettings`
    if [ "$res" = "" ]; then
        line=`grep -n '}]' /etc/v2ray/config.json  | head -n1 | cut -d: -f1`
        line=`expr ${line} - 1`
        sed -i "${line}s/}/},/" /etc/v2ray/config.json
        sed -i "${line}a\    \"streamSettings\": {\n      \"network\": \"ws\",\n      \"wsSettings\": {\n        \"path\": \"${path}\"\n      }\n    },\n    \"listen\": \"127.0.0.1\"" /etc/v2ray/config.json
    else
        sed -i -e "s/path\":.*/path\": \"\\${path}\"/" /etc/v2ray/config.json
    fi
    systemctl enable v2ray && systemctl restart v2ray
    echo "安装成功！"
}

function installNginx()
{
    yum install -y nginx
    systemctl stop nginx
    res=`netstat -ntlp| grep -E ':80|:443'`
    if [ "${res}" != "" ]; then
        echo " 其他进程占用了80或443端口，请先关闭再运行一键脚本"
        echo " 端口占用信息如下："
        echo ${res}
        exit 1
    fi
    res=`which pip3`
    if [ "$?" != "0" ]; then
        yum install -y python36
    fi
    res=`which pip3`
    if [ "$?" != "0" ]; then
        echo -e " pip3安装失败，请到 ${red}https://www.hijk.pw${plain} 反馈"
        exit 1
    fi
    pip3 install certbot
    res=`which certbot`
    if [ "$?" != "0" ]; then
        export PATH=$PATH:/usr/local/bin
    fi
    certbot certonly --standalone --agree-tos --register-unsafely-without-email -d ${domain}
    if [ "$?" != "0" ]; then
        echo -e " 获取证书失败，请到 ${red}https://www.hijk.pw${plain} 反馈"
        exit 1
    fi

    res=`cat /usr/share/nginx/html/index.html| grep Flatfy`
    if [ "${res}" = "" ]; then
        mkdir -p /usr/share/nginx/html.bak
        mv /usr/share/nginx/html/* /usr/share/nginx/html.bak
        wget 'https://github.com/hijkpw/scripts/raw/master/Flatfy%20V3.zip' -O theme.zip
        unzip theme.zip
        rm -rf __MACOSX/
        mv Flatfy\ V3/* /usr/share/nginx/html/
        rm -rf theme.zip Flatfy\ V3
    fi
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
    listen 80 default_server;
    server_name ${domain};
    rewrite ^(.*) https://\$server_name\$1 permanent;
}

server {
    listen       443 ssl http2;
    server_name ${domain};
    charset utf-8;

    # ssl配置
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-SHA384;
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
        index index.html;
    }

    location ${path} {
      proxy_redirect off;
      proxy_pass http://127.0.0.1:${port};
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
    res=`cat /etc/crontab | grep certbot`
    if [ "${res}" = "" ]; then
        echo '0 3 1 */2 0 root systemctl stop nginx && certbot renew && systemctl start nginx' >> /etc/crontab
    fi
    systemctl enable nginx && systemctl restart nginx
}

function setFirewall()
{
    systemctl status firewalld > /dev/null 2>&1
    if [ $? -eq 0 ];then
        firewall-cmd --permanent --add-service=http
        firewall-cmd --permanent --add-service=https
        firewall-cmd --reload
    fi
}

function installBBR()
{
    result=$(lsmod | grep bbr)
    if [ "$result" != "" ]; then
        echo BBR模块已安装
        bbr=true
        echo "3" > /proc/sys/net/ipv4/tcp_fastopen
        echo "net.ipv4.tcp_fastopen = 3" >> /etc/sysctl.conf
        return;
    fi

    echo 安装BBR模块...
    rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
    rpm -Uvh http://www.elrepo.org/elrepo-release-7.0-4.el7.elrepo.noarch.rpm
    yum --enablerepo=elrepo-kernel install kernel-ml -y
    grub2-set-default 0
    echo "tcp_bbr" >> /etc/modules-load.d/modules.conf
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    echo "3" > /proc/sys/net/ipv4/tcp_fastopen
    echo "net.ipv4.tcp_fastopen = 3" >> /etc/sysctl.conf
    bbr=false
}

function showTip()
{
    echo ============================================
    echo -e "        ${red}v2ray安装成功！${plain}               "
    echo ""
    echo -e " IP(address):  ${red}${IP}${plain}"
    echo -e " 端口(port)：${red}443${plain}"
    echo -e " id：${red}${uid}${plain}"
    echo -e " 额外id（alterid）： ${red}${alterid}${plain}"
    echo -e " 加密方式(security)： ${red}auto${plain}"
    echo -e " 传输协议(network)： ${red}ws${plain}"
    echo -e " 主机名(host)：${red}${domain}${plain}"
    echo -e " 路径(path)：${red}${path}${plain}"
    echo    
    echo -e "v2ray配置文件：${red}/etc/v2ray/config.json${plain}，请按照自己需要进行修改"         
    echo  
    echo  如果连接不成功，请注意查看安全组/防火墙是否已放行端口
    echo 
    echo -e "如有其他问题，请到 ${red}https://www.hijk.pw${plain} 留言反馈"

    if [ "${bbr}" == "false" ]; then
        echo  
        echo  为使BBR模块生效，系统将在30秒后重启
        echo  
        echo  您可以按ctrl + c取消重启，稍后输入reboot重启系统
    fi
    echo ============================================

    if [ "${bbr}" == "false" ]; then
        sleep 30
        reboot
    fi
}

function install()
{
    checkSystem
    getData
    preinstall
    installBBR
    installV2ray
    setFirewall
    installNginx
    showTip
}

function uninstall()
{
    read -p "您确定真的要卸载v2ray吗？(y/n)" answer
    [ -z ${answer} ] && answer="n"

    if [ "${answer}" == "y" ] || [ "${answer}" == "Y" ]; then
        systemctl stop v2ray
        systemctl disable v2ray
        rm -rf /etc/v2ray/*
        rm -rf /usr/bin/v2ray/*
        rm -rf /var/log/v2ray/*
        rm -rf /etc/systemd/system/v2ray.service

        yum remove -y nginx
        if [ -d /usr/share/nginx/html.bak ]; then
            rm -rf /usr/share/nginx/html
            mv /usr/share/nginx/html.bak /usr/share/nginx/html
        fi
        echo -e " ${red}卸载成功${plain}"
    fi
}

echo -n "系统版本:  "
cat /etc/centos-release


action=$1
[ -z $1 ] && action=install
case "$action" in
    install|uninstall)
        ${action}
        ;;
    *)
        echo "参数错误"
        echo "用法: `basename $0` [install|uninstall]"
        ;;
esac

