#!/bin/bash
# shadowsocks/ss Ubuntu一键安装脚本
# Author: hijk<https://hijk.art>

echo "#############################################################"
echo "#         Ubuntu TLS Shadowsocks/SS  一键安装脚本            #"
echo "# 网址: https://hijk.art                                  #"
echo "# 作者: hijk                                                #"
echo "#############################################################"
echo ""

red='\033[0;31m'
green="\033[0;32m"
plain='\033[0m'
BASE=`pwd`

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
    read -p "请设置SS的密码（不输入则随机生成）:" password
    [ -z "$password" ] && password=`cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1`
    echo ""
    echo "密码： $password"
    echo ""
    
    while true
    do
        read -p "请设置SS的端口号[1025-65535]:" port
        [ -z "$port" ] && port="12345"
        if [ "${port:0:1}" = "0" ]; then
            echo -e "${red}端口不能以0开头${plain}"
            exit 1
        fi
        expr $port + 0 &>/dev/null
        if [ $? -eq 0 ]; then
            if [ $port -ge 1025 ] && [ $port -le 65535 ]; then
                echo ""1234
                echo "端口号： $port"
                echo ""
                break
            else
                echo "输入错误，端口号为1025-65535的数字"
            fi
        else
            echo "输入错误，端口号为1025-65535的数字"
        fi
    done
    echo "请选择SS的加密方式:" 
    echo "1)aes-256-gcm"
    echo "2)aes-192-gcm"
    echo "3)aes-128-gcm"
    echo "4)aes-256-ctr"
    echo "5)aes-192-ctr"
    echo "6)aes-128-ctr"
    echo "7)aes-256-cfb"
    echo "8)aes-192-cfb"
    echo "9)aes-128-cfb"
    echo "10)camellia-128-cfb"
    echo "11)camellia-192-cfb"
    echo "12)camellia-256-cfb"
    echo "13)chacha20-ietf"
    echo "14)chacha20-ietf-poly1305"
    echo "15)xchacha20-ietf-poly1305"
    read -p "请选择（默认aes-256-gcm）" answer
    if [ -z "$answer" ]; then
        method="aes-256-gcm"
    else
        case $answer in
        1)
            method="aes-256-gcm"
            ;;
        2)
            method="aes-192-gcm"
            ;;
        3)
            method="aes-128-gcm"
            ;;
        4)
            method="aes-256-ctr"
            ;;
        5)
            method="aes-192-ctr"
            ;;
        6)
            method="aes-128-ctr"
            ;;
        7)
            method="aes-256-cfb"
            ;;
        8)
            method="aes-192-cfb"
            ;;
        9)
            method="aes-128-cfb"
            ;;
        10)
            method="camellia-128-cfb"
            ;;
        11)
            method="camellia-192-cfb"
            ;;
        12)
            method="camellia-256-cfb"
            ;;
        13)
            method="chacha20-ietf"
            ;;
        14)
            method="chacha20-ietf-poly1305"
            ;;
        15)
            method="xchacha20-ietf-poly1305"
            ;;
        *)
            echo "无效的选择，使用默认的aes-256-gcm"
            method="aes-256-gcm"
        esac
    fi
    echo ""
    echo "加密方式： $method"
    echo ""
}

function preinstall()
{
    sed -i 's/#ClientAliveInterval 0/ClientAliveInterval 60/' /etc/ssh/sshd_config
    systemctl restart sshd
    echo "更新系统..."
    apt update && apt upgrade -y
    
    echo "安装必要软件"
    apt install -y telnet wget vim net-tools unzip tar qrencode
    apt install -y make openssl libssl-dev gettext gcc autoconf libtool automake make asciidoc xmlto libudns-dev libev-dev libpcre3 libpcre3-dev libmbedtls-dev libsodium-dev libc-ares2 libc-ares-dev gcc g++
    apt install -y libsodium18
    if [ "$?" != "0" ]; then
        apt install -y libsodium23
    fi
    apt install -y libmbedtls10
    if [ "$?" != "0" ]; then
        apt install -y libmbedtls12
    fi
    apt autoremove -y
    res=`which wget`
    [ "$?" != "0" ] && apt install -y wget
    res=`which netstat`
    [ "$?" != "0" ] && apt install -y net-tools
}

function installSS()
{
    echo 安装SS...

    res=`which ss-server`
    if [ "$?" != "0" ]; then
        if ! wget 'https://github.com/shadowsocks/shadowsocks-libev/releases/download/v3.3.4/shadowsocks-libev-3.3.4.tar.gz' -O shadowsocks-libev-3.3.4.tar.gz; then
            echo "下载文件失败！"
            exit 1
        fi
        tar zxf shadowsocks-libev-3.3.4.tar.gz
        cd shadowsocks-libev-3.3.4
        ./configure
        make && make install
        if [ $? -ne 0 ]; then
            echo
            echo -e "[${red}错误${plain}] Shadowsocks-libev 安装失败！ 请打开 https://hijk.art 反馈"
            cd ${BASE} && rm -rf shadowsocks-libev-3.3.4*
            exit 1
        fi
        cd ${BASE} && rm -rf shadowsocks-libev-3.3.4*
    else
        echo "SS 已安装"
    fi


    echo "3" > /proc/sys/net/ipv4/tcp_fastopen
    echo "net.ipv4.tcp_fastopen = 3" >> /etc/sysctl.conf
    if [ ! -d /etc/shadowsocks-libev ];then
        mkdir /etc/shadowsocks-libev
    fi
    cat > /etc/shadowsocks-libev/config.json<<-EOF
{
    "server":"0.0.0.0",
    "server_port":${port},
    "local_port":1080,
    "password":"${password}",
    "timeout":600,
    "method":"${method}",
    "nameserver":"8.8.8.8",
    "mode":"tcp_and_udp",
    "fast_open":false
}
EOF
 cat > /lib/systemd/system/shadowsocks-libev.service <<-EOF
[Unit]
Description=shadowsocks
Documentation=https://hijk.art/
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
PIDFile=/var/run/shadowsocks-libev.pid
LimitNOFILE=32768
ExecStart=/usr/local/bin/ss-server -c /etc/shadowsocks-libev/config.json -f /var/run/shadowsocks-libev.pid
ExecReload=/bin/kill -s HUP \$MAINPID
ExecStop=/bin/kill -s TERM \$MAINPID

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable shadowsocks-libev
    systemctl restart shadowsocks-libev
    sleep 3
    res=`netstat -nltp | grep ${port} | grep 'ss-server'`
    if [ "${res}" = "" ]; then
        echo "ss启动失败，请检查端口是否被占用！"
        exit 1
    fi
}

function setFirewall()
{
    res=`ufw status | grep -i inactive`
    if [ "$res" = "" ];then
        ufw allow ${port}/tcp
        ufw allow ${port}/udp
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
    apt install -y qrencode
    ip=`curl -s -4 icanhazip.com`
    port=`cat /etc/shadowsocks-libev/config.json | grep server_port | cut -d: -f2 | tr -d \",' '`
    res=`netstat -nltp | grep ${port} | grep 'ss-server'`
    [ -z "$res" ] && status="${red}已停止${plain}" || status="${green}正在运行${plain}"
    password=`cat /etc/shadowsocks-libev/config.json | grep password | cut -d: -f2 | tr -d \",' '`
    method=`cat /etc/shadowsocks-libev/config.json | grep method | cut -d: -f2 | tr -d \",' '`
    
    res=`echo -n ${method}:${password}@${ip}:${port} | base64 -w 0`
    link="ss://${res}"

    echo ============================================
    echo -e " ss运行状态：${status}"
    echo -e " ss配置文件：${red}/etc/shadowsocks-libev/config.json${plain}"
    echo ""
    echo -e "${red}ss配置信息：${plain}"
    echo -e " IP(address):  ${red}${ip}${plain}"
    echo -e " 端口(port)：${red}${port}${plain}"
    echo -e " 密码(password)：${red}${password}${plain}"
    echo -e " 加密方式(method)： ${red}${method}${plain}"
    echo
    echo " ss链接： ${link}"
    qrencode -o - -t utf8 ${link}
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
    installSS
    setFirewall

    info
    bbrReboot
}

function uninstall()
{
    read -p "您确定真的要卸载SS吗？(y/n)" answer
    [ -z ${answer} ] && answer="n"

    if [ "${answer}" == "y" ] || [ "${answer}" == "Y" ]; then
        systemctl stop shadowsocks-libev && systemctl disable shadowsocks-libev
        rm -rf /lib/systemd/system/shadowsocks-libev.service
        cd /usr/local/bin && rm -rf ss-local ss-manager ss-nat ss-redir ss-server ss-tunnel
        rm -rf /usr/lib64/libshadowsocks-libev*
        rm -rf /usr/share/doc/shadowsocks-libev
        rm -rf /usr/share/man/man1/ss-*.1.gz
        rm -rf /usr/share/man/man8/shadowsocks-libev.8.gz
        echo "SS卸载完成"
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
