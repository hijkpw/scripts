#!/bin/bash
# trojan一键安装脚本
# Author: hijk<https://hijk.art>

echo "#############################################################"
echo "#                      trojan一键安装脚本                    #"
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

    res=`which yum`
    if [ "$?" != "0" ]; then
        res=`which apt`
        if [ "$?" != "0" ]; then
            echo "不受支持的Linux系统"
            exit 1
         fi
         OS=ubuntu
         pm=apt
    else
        OS=centos
        pm=yum
    fi
    res=`which systemctl`
    if [ "$?" != "0" ]; then
        echo "系统版本过低，请升级到最新版本"
        exit 1
    fi
}

function getData()
{
    IP=`curl -s -4 icanhazip.com`
    echo " "
    echo " 本脚本为trojan一键脚本，运行之前请确认如下条件已经具备："
    echo -e "  ${red}1. 一个域名${plain}"
    echo -e "  ${red}2. 域名的某个主机名解析指向当前服务器ip（${IP}）${plain}"
    echo " "
    read -p "确认满足按y，按其他退出脚本：" answer
    if [ "${answer}" != "y" ] && [ "${answer}" != "Y" ]; then
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
    
    domain=${domain,,}
    resolve=`curl -s https://hijk.art/hostip.php?d=${domain}`
    res=`echo -n ${resolve} | grep ${IP}`
    if [ -z "${res}" ]; then
        echo "${domain} 解析结果：${resolve}"
        echo -e "${red}主机未解析到当前服务器IP(${IP})!${plain}"
        exit 1
    fi

    read -p "请设置trojan密码（不输入则随机生成）:" password
    [ -z "$password" ] && password=`cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1`
    
    read -p "请输入trojan端口[100-65535的一个数字，默认443]：" port
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
    index=`shuf -i0-${len} -n1`
    site=${sites[$index]}
    host=`echo ${site} | cut -d/ -f3`
    protocol=`echo ${site} | cut -d/ -f1`
    [ "$protocol" != "http:" ] && remotePort=80 || remotePort=443
}

function preinstall()
{
    echo "更新系统..."
    if [ "$pm" = "yum" ]; then
        yum update -y
    else
        apt update && apt -y upgrade
    fi
    echo "安装必要软件"
    if [ "$pm" = "yum" ]; then
        yum install -y epel-release telnet wget vim unzip tar
        res=`which wget`
        [ "$?" != "0" ] && yum install -y wget
        yum install -y net-tools
        yum install -y ntpdate
        res=`which netstat`
        [ "$?" != "0" ] && yum install -y net-tools
    else
        apt install -y telnet wget vim unzip gcc g++ tar
        res=`which wget`
        [ "$?" != "0" ] && apt install -y wget
        apt install -y net-tools
        apt install -y ntpdate
        res=`which netstat`
        [ "$?" != "0" ] && apt install -y net-tools
        apt autoremove -y
    fi

    if [ -s /etc/selinux/config ] && grep 'SELINUX=enforcing' /etc/selinux/config; then
        sed -i 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/selinux/config
        setenforce 0
    fi
}

function installTrojan()
{
    echo 安装trojan...
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/trojan-gfw/trojan-quickstart/master/trojan-quickstart.sh)"

    CONFIG_FILE=/usr/local/etc/trojan/config.json
    if [ ! -f $CONFIG_FILE ]; then
        echo "安装失败，请到 https://hijk.art 反馈"
        exit 1
    fi

    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
    ntpdate -u time.nist.gov

    sed -i -e "s/local_port\":\s*[0-9]*/local_port\": ${port}/" $CONFIG_FILE
    sed -i -e "s/remote_addr\":\s*\".*\",/remote_addr\": \"$host\",/" $CONFIG_FILE
    sed -i -e "s/remote_port\":\s*[0-9]*/remote_port\": $remotePort/" $CONFIG_FILE
    sed -i -e "s/cert\":\s*\".*\",/cert\": \"\/etc\/letsencrypt\/live\/${domain}\/fullchain.pem\",/" $CONFIG_FILE
    sed -i -e "s/key\":\s*\".*\",/key\": \"\/etc\/letsencrypt\/live\/${domain}\/privkey.pem\",/" $CONFIG_FILE
    line1=`grep -n 'password' $CONFIG_FILE  | head -n1 | cut -d: -f1`
    line11=`expr $line1 + 1`
    line2=`grep -n '],' $CONFIG_FILE  | head -n1 | cut -d: -f1`
    line22=`expr $line2 - 1`
    sed -i "${line11},${line22}d" $CONFIG_FILE
    sed -i "${line1}a\        \"$password\"" $CONFIG_FILE

    systemctl enable trojan && systemctl restart trojan
    sleep 3
    res=`netstat -nltp | grep ${port} | grep trojan`
    if [ "${res}" = "" ]; then
        echo "trojan启动失败，请检查端口是否被占用！"
        exit 1
    fi
    echo "trojan安装成功！"
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
        if [ "$pm" = "yum" ]; then
            yum install -y python3 python3-pip
        else
            apt install -y python3-pip python3-setuptools python3-dev
        fi
    fi
    res=`which pip3`
    if [ "$?" != "0" ]; then
        echo -e " pip3安装失败，请到 ${red}https://hijk.art${plain} 反馈"
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
    mkdir -p /usr/share/nginx/html;
    echo 'User-Agent: *' > /usr/share/nginx/html/robots.txt
    echo 'Disallow: /' >> /usr/share/nginx/html/robots.txt
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
    cat > /etc/nginx/conf.d/${domain}.conf<<-EOF
server {
    listen 80;
    server_name ${domain};
    root /usr/share/nginx/html;
    location / {
        return 301 https://\$server_name:${port}\$request_uri;
    }
    
    location = /robots.txt {
    }
}
EOF
    sed -i '/certbot/d' /etc/crontab
    certbotpath=`which certbot`
    echo "0 3 1 */2 0 root systemctl stop nginx ; ${certbotpath} renew ; systemctl restart nginx" >> /etc/crontab
    systemctl enable nginx && systemctl restart nginx
}

function setFirewall()
{
    systemctl status firewalld > /dev/null 2>&1
    if [ $? -eq 0 ];then
        firewall-cmd --permanent --add-service=http
        firewall-cmd --permanent --add-service=https
        firewall-cmd --permanent --add-port=${port}/tcp
        firewall-cmd --reload
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
        echo "openvz机器，跳过安装"
        bbr=true
        return
    fi
    
    if [ $main -eq 8 ]; then
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_fastopen = 3" >> /etc/sysctl.conf
        sysctl -p
        bbr=true
        return
    fi

    echo 安装BBR模块...
    if [ "$pm" = "yum" ]; then
        rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
        rpm -Uvh http://www.elrepo.org/elrepo-release-7.0-4.el7.elrepo.noarch.rpm
        yum --enablerepo=elrepo-kernel install kernel-ml -y
        grub2-set-default 0
    else
        apt install -y --install-recommends linux-generic-hwe-16.04
        grub-set-default 0
    fi
    echo "tcp_bbr" >> /etc/modules-load.d/modules.conf
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    echo "3" > /proc/sys/net/ipv4/tcp_fastopen
    echo "net.ipv4.tcp_fastopen = 3" >> /etc/sysctl.conf
    bbr=false
}

function info()
{
    res=`netstat -nltp | grep trojan`
    [ -z "$res" ] && status="${red}已停止${plain}" || status="${green}正在运行${plain}"
    
    CONFIG_FILE=/usr/local/etc/trojan/config.json
    ip=`cat $CONFIG_FILE | grep -m1 cert | cut -d/ -f5`
    port=`cat $CONFIG_FILE | grep local_port | cut -d: -f2 | tr -d \",' '`
    line1=`grep -n 'password' $CONFIG_FILE  | head -n1 | cut -d: -f1`
    line11=`expr $line1 + 1`
    password=`sed -n "${line11}p" $CONFIG_FILE | tr -d \",' '`
    
    res=`netstat -nltp | grep ${port} | grep nginx`
    [ -z "$res" ] && ngstatus="${red}已停止${plain}" || ngstatus="${green}正在运行${plain}"
    
    echo ============================================
    echo -e " trojan运行状态：${status}"
    echo -e " trojan配置文件：${red}$CONFIG_FILE${plain}"
    echo ""
    echo -e "${red}trojan配置信息：${plain}               "
    echo -e " IP(address):  ${red}${ip}${plain}"
    echo -e " 端口(port)：${red}${port}${plain}"
    echo -e " 密码(password)：${red}$password${plain}"
    echo  
    echo ============================================
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
    cat /etc/centos-release

    checkSystem
    getData
    preinstall
    installBBR
    setFirewall
    installNginx
    removeTrojan
    installTrojan
    
    info
    bbrReboot
}

function removeTrojan()
{
    rm -rf /usr/local/bin/trojan
    rm -rf /usr/local/etc/trojan
    rm -rf /usr/share/nginx/html/trojan
    rm -rf /etc/systemd/system/trojan.service
}

function uninstall()
{
    read -p "您确定真的要卸载trojan吗？(y/n)" answer
    [ -z ${answer} ] && answer="n"

    if [ "${answer}" == "y" ] || [ "${answer}" == "Y" ]; then
        systemctl stop trojan
        systemctl disable trojan
        CONFIG_FILE=/usr/local/etc/trojan/config.json
        domain=`cat $CONFIG_FILE | grep cert | cut -d/ -f5`
        removeTrojan

        yum remove -y nginx
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

