#!/bin/bash
# shadowsocks/ss Ubuntu一键安装脚本
# Author: hijk<https://hijk.art>

RED="\033[31m"      # Error message
GREEN="\033[32m"    # Success message
YELLOW="\033[33m"   # Warning message
BLUE="\033[36m"     # Info message
PLAIN='\033[0m'

BASE=`pwd`
OS=`hostnamectl | grep -i system | cut -d: -f2`

V6_PROXY=""
IP=`curl -sL -4 ip.sb`
if [[ "$?" != "0" ]]; then
    IP=`curl -sL -6 ip.sb`
    V6_PROXY="https://gh.hijk.art/"
fi

CONFIG_FILE="/etc/shadowsocks-libev/config.json"

colorEcho() {
    echo -e "${1}${@:2}${PLAIN}"
}

checkSystem() {
    result=$(id | awk '{print $1}')
    if [ $result != "uid=0(root)" ]; then
        colorEcho $RED " 请以root身份执行该脚本"
        exit 1
    fi

    res=`lsb_release -d | grep -i ubuntu`
    if [ "$?" != "0" ]; then
        res=`which apt`
        if [ "$?" != "0" ]; then
            colorEcho $RED " 系统不是Ubuntu"
            exit 1
        fi
    else
        result=`lsb_release -d | grep -oE "[0-9.]+"`
        main=${result%%.*}
        if [ $main -lt 16 ]; then
            colorEcho $RED " 不受支持的Ubuntu版本"
            exit 1
        fi
     fi
}

slogon() {
    clear
    echo "#############################################################"
    echo -e "#         ${RED}Ubuntu LTS Shadowsocks/SS  一键安装脚本${PLAIN}            #"
    echo -e "# ${GREEN}作者${PLAIN}: 网络跳越(hijk)                                      #"
    echo -e "# ${GREEN}网址${PLAIN}: https://hijk.art                                    #"
    echo -e "# ${GREEN}论坛${PLAIN}: https://hijk.club                                   #"
    echo -e "# ${GREEN}TG群${PLAIN}: https://t.me/hijkclub                               #"
    echo -e "# ${GREEN}Youtube频道${PLAIN}: https://youtube.com/channel/UCYTB--VsObzepVJtc9yvUxQ #"
    echo "#############################################################"
    echo ""
}

getData() {
    read -p " 请设置SS的密码（不输入则随机生成）:" PASSWORD
    [ -z "$PASSWORD" ] && PASSWORD=`cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1`
    echo ""
    colorEcho $BLUE " 密码： $PASSWORD"
    echo ""
    
    while true
    do
        read -p " 请设置SS的端口号[1025-65535]:" PORT
        [ -z "$PORT" ] && PORT="12345"
        if [ "${PORT:0:1}" = "0" ]; then
            echo -e "${RED}端口不能以0开头${PLAIN}"
            exit 1
        fi
        expr $PORT + 0 &>/dev/null
        if [ $? -eq 0 ]; then
            if [ $PORT -ge 1025 ] && [ $PORT -le 65535 ]; then
                echo ""
                colorEcho $BLUE " 端口号： $PORT"
                echo ""
                break
            else
                colorEcho $RED " 输入错误，端口号为1025-65535的数字"
            fi
        else
            colorEcho $RED " 输入错误，端口号为1025-65535的数字"
        fi
    done
    colorEcho $BLUE " 请选择SS的加密方式:" 
    echo "   1)aes-256-gcm"
    echo "   2)aes-192-gcm"
    echo "   3)aes-128-gcm"
    echo "   4)aes-256-ctr"
    echo "   5)aes-192-ctr"
    echo "   6)aes-128-ctr"
    echo "   7)aes-256-cfb"
    echo "   8)aes-192-cfb"
    echo "   9)aes-128-cfb"
    echo "   10)camellia-128-cfb"
    echo "   11)camellia-192-cfb"
    echo "   12)camellia-256-cfb"
    echo "   13)chacha20-ietf"
    echo "   14)chacha20-ietf-poly1305"
    echo "   15)xchacha20-ietf-poly1305"
    read -p " 请选择加密方式（默认aes-256-gcm）" answer
    if [ -z "$answer" ]; then
        METHOD="aes-256-gcm"
    else
        case $answer in
        1)
            METHOD="aes-256-gcm"
            ;;
        2)
            METHOD="aes-192-gcm"
            ;;
        3)
            METHOD="aes-128-gcm"
            ;;
        4)
            METHOD="aes-256-ctr"
            ;;
        5)
            METHOD="aes-192-ctr"
            ;;
        6)
            METHOD="aes-128-ctr"
            ;;
        7)
            METHOD="aes-256-cfb"
            ;;
        8)
            METHOD="aes-192-cfb"
            ;;
        9)
            METHOD="aes-128-cfb"
            ;;
        10)
            METHOD="camellia-128-cfb"
            ;;
        11)
            METHOD="camellia-192-cfb"
            ;;
        12)
            METHOD="camellia-256-cfb"
            ;;
        13)
            METHOD="chacha20-ietf"
            ;;
        14)
            METHOD="chacha20-ietf-poly1305"
            ;;
        15)
            METHOD="xchacha20-ietf-poly1305"
            ;;
        *)
            colorEcho $RED " 无效的选择，使用默认的aes-256-gcm"
            METHOD="aes-256-gcm"
        esac
    fi
    echo ""
    colorEcho $BLUE " 加密方式： $METHOD"
    echo ""
}

preinstall() {
    colorEcho $BLUE " 更新系统..."
    apt clean all
    apt update
    #apt upgrade -y
    
    colorEcho $BLUE " 安装必要软件"
    apt install -y telnet wget vim net-tools unzip tar qrencode
    apt install -y make openssl libssl-dev gettext gcc autoconf libtool automake make asciidoc xmlto libudns-dev libev-dev libpcre3 libpcre3-dev libmbedtls-dev libsodium-dev libc-ares2 libc-ares-dev g++
    apt install -y libsodium*
    apt autoremove -y
    res=`which wget`
    [ "$?" != "0" ] && apt install -y wget
    res=`which netstat`
    [ "$?" != "0" ] && apt install -y net-tools
}

normalizeVersion() {
    if [ -n "$1" ]; then
        case "$1" in
            v*)
                echo "${1:1}"
            ;;
            *)
                echo "$1"
            ;;
        esac
    else
        echo ""
    fi
}

installNewVer() {
    new_ver=$1
    if ! wget "${V6_PROXY}https://github.com/shadowsocks/shadowsocks-libev/releases/download/v${new_ver}/shadowsocks-libev-${new_ver}.tar.gz" -O shadowsocks-libev.tar.gz; then
        colorEcho $RED " 下载安装文件失败！"
        exit 1
    fi
    tar zxf shadowsocks-libev.tar.gz
    cd shadowsocks-libev-${new_ver}
    ./configure
    make && make install
    if [[ $? -ne 0 ]]; then
        echo
        echo -e " [${RED}错误${PLAIN}]: $OS Shadowsocks-libev 安装失败！ 请打开 https://hijk.art 反馈"
        cd ${BASE} && rm -rf shadowsocks-libev*
        exit 1
    fi
    cd ${BASE} && rm -rf shadowsocks-libev*
}

installSS() {
    colorEcho $BLUE " 安装SS..."

    tag_url="${V6_PROXY}https://api.github.com/repos/shadowsocks/shadowsocks-libev/releases/latest"
    new_ver="$(normalizeVersion "$(curl -s "${tag_url}" --connect-timeout 10| grep 'tag_name' | cut -d\" -f4)")"
    export PATH=/usr/local/bin:$PATH
    res=`which ss-server`
    if [ "$?" != "0" ]; then
        installNewVer $new_ver
    else
        ver=`ss-server -h | grep shadowsocks-libev | grep -oE '[0-9+\.]+'`
        if [[ $ver != $new_ver ]]; then
            installNewVer $new_ver
        else
            colorEcho $YELLOW " 已安装最新版SS"
        fi
    fi

    interface="0.0.0.0"
    if [[ "$V6_PROXY" != "" ]]; then
        interface="::"
    fi
    mkdir -p /etc/shadowsocks-libev
    ssPath=`which ss-server`
    cat > $CONFIG_FILE<<-EOF
{
    "server":"$interface",
    "server_port":${PORT},
    "local_port":1080,
    "password":"${PASSWORD}",
    "timeout":600,
    "method":"${METHOD}",
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
ExecStart=/usr/local/bin/ss-server -c $CONFIG_FILE -f /var/run/shadowsocks-libev.pid
ExecReload=/bin/kill -s HUP \$MAINPID
ExecStop=/bin/kill -s TERM \$MAINPID

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable shadowsocks-libev
    systemctl restart shadowsocks-libev
    sleep 3
    res=`netstat -nltp | grep ${PORT} | grep 'ss-server'`
    if [ "${res}" = "" ]; then
        colorEcho $RED " ss启动失败，请检查端口是否被占用！"
        exit 1
    fi
}

setFirewall() {
    res=`ufw status | grep -i inactive`
    if [ "$res" = "" ];then
        ufw allow ${PORT}/tcp
        ufw allow ${PORT}/udp
    fi
}

installBBR() {
    result=$(lsmod | grep bbr)
    if [ "$result" != "" ]; then
        colorEcho $BLUE " BBR模块已安装"
        INSTALL_BBR=false
        return;
    fi

    res=`hostnamectl | grep -i openvz`
    if [ "$res" != "" ]; then
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
    apt install -y --install-recommends linux-generic-hwe-16.04
    grub-set-default 0
    echo "tcp_bbr" >> /etc/modules-load.d/modules.conf
    INSTALL_BBR=true
}

info() {
    port=`grep server_port $CONFIG_FILE| cut -d: -f2 | tr -d \",' '`
    res=`netstat -nltp | grep ${port} | grep 'ss-server'`
    [ -z "$res" ] && status="${RED}已停止${PLAIN}" || status="${GREEN}正在运行${PLAIN}"
    password=`grep password $CONFIG_FILE| cut -d: -f2 | tr -d \",' '`
    method=`grep method $CONFIG_FILE| cut -d: -f2 | tr -d \",' '`
    
    res=`echo -n ${method}:${password}@${IP}:${port} | base64 -w 0`
    link="ss://${res}"

    echo ============================================
    echo -e " ${BLUE}ss运行状态：${PLAIN}${status}"
    echo -e " ${BLUE}ss配置文件：${PLAIN}${RED}$CONFIG_FILE${PLAIN}"
    echo ""
    echo -e " ${RED}ss配置信息：${PLAIN}"
    echo -e "   ${BLUE}IP(address): ${PLAIN} ${RED}${IP}${PLAIN}"
    echo -e "   ${BLUE}端口(port)：${PLAIN}${RED}${port}${PLAIN}"
    echo -e "   ${BLUE}密码(password)：${PLAIN}${RED}${password}${PLAIN}"
    echo -e "   ${BLUE}加密方式(method)：${PLAIN} ${RED}${method}${PLAIN}"
    echo
    echo -e " ${BLUE}ss链接：${PLAIN} ${link}"
    qrencode -o - -t utf8 ${link}
}

bbrReboot() {
    if [ "${INSTALL_BBR}" == "true" ]; then
        echo  
        colorEcho $BLUE " 为使BBR模块生效，系统将在30秒后重启"
        echo  
        echo -e " 您可以按 ctrl + c 取消重启，稍后输入 ${RED}reboot${PLAIN} 重启系统"
        sleep 30
        reboot
    fi
}

install() {
    echo -n " 系统版本:  "
    lsb_release -a

    checkSystem
    getData
    preinstall
    installSS
    setFirewall

    info
    bbrReboot
}

uninstall() {
    read -p " 确定卸载SS吗？(y/n)" answer
    [ -z ${answer} ] && answer="n"

    if [ "${answer}" == "y" ] || [ "${answer}" == "Y" ]; then
        systemctl stop shadowsocks-libev && systemctl disable shadowsocks-libev
        rm -rf /lib/systemd/system/shadowsocks-libev.service
        cd /usr/local/bin && rm -rf ss-local ss-manager ss-nat ss-redir ss-server ss-tunnel
        rm -rf /usr/lib64/libshadowsocks-libev*
        rm -rf /usr/share/doc/shadowsocks-libev
        rm -rf /usr/share/man/man1/ss-*.1.gz
        rm -rf /usr/share/man/man8/shadowsocks-libev.8.gz
        colorEcho $GREEN " SS卸载完成"
    fi
}

slogon

action=$1
[ -z $1 ] && action=install
case "$action" in
    install|uninstall|info)
        ${action}
        ;;
    *)
        echo " 参数错误"
        echo " 用法: `basename $0` [install|uninstall|info]"
        ;;
esac
