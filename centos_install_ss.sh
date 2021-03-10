#!/bin/bash
# shadowsocks/ss CentOS一键安装脚本
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
    if [[ "$result" != "uid=0(root)" ]]; then
        colorEcho $RED " 请以root身份执行该脚本"
        exit 1
    fi

    if [[ ! -f /etc/centos-release ]]; then
        res=`which yum`
        if [ "$?" != "0" ]; then
            colorEcho $RED " 系统不是CentOS"
            exit 1
         fi
    else
        result=`cat /etc/centos-release|grep -oE "[0-9.]+"`
        main=${result%%.*}
        if [[ $main -lt 7 ]]; then
            colorEcho $RED " 不受支持的CentOS版本"
            exit 1
         fi
    fi
}

slogon() {
    clear
    echo "#############################################################"
    echo -e "#         ${RED}CentOS 7/8 Shadowsocks/SS 一键安装脚本${PLAIN}             #"
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
    [[ -z "$PASSWORD" ]] && PASSWORD=`cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1`
    echo ""
    colorEcho $BLUE " 密码： $PASSWORD"
    echo ""
    
    while true
    do
        read -p " 请设置SS的端口号[1025-65535]:" PORT
        [[ -z "$PORT" ]] && PORT="12345"
        if [[ "${PORT:0:1}" = "0" ]]; then
            echo -e " ${RED}端口不能以0开头${PLAIN}"
            exit 1
        fi
        expr $PORT + 0 &>/dev/null
        if [[ $? -eq 0 ]]; then
            if [[ $PORT -ge 1025 ]] && [[ $PORT -le 65535 ]]; then
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
    colorEcho $RED " 请选择加密方式:" 
    echo "  1)aes-256-gcm"
    echo "  2)aes-192-gcm"
    echo "  3)aes-128-gcm"
    echo "  4)aes-256-ctr"
    echo "  5)aes-192-ctr"
    echo "  6)aes-128-ctr"
    echo "  7)aes-256-cfb"
    echo "  8)aes-192-cfb"
    echo "  9)aes-128-cfb"
    echo "  10)camellia-128-cfb"
    echo "  11)camellia-192-cfb"
    echo "  12)camellia-256-cfb"
    echo "  13)chacha20-ietf"
    echo "  14)chacha20-ietf-poly1305"
    echo "  15)xchacha20-ietf-poly1305"
    read -p " 请选择（默认aes-256-gcm）" answer
    if [[ -z "$answer" ]]; then
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
    colorEcho $BLUE "加密方式： $METHOD"
    echo ""
}

preinstall() {
    yum clean all
    #yum update -y
    
    colorEcho $BULE " 安装必要软件"
    yum install -y epel-release telnet wget vim net-tools unzip tar qrencode
    yum install -y openssl openssl-devel gettext gcc autoconf libtool automake make asciidoc xmlto udns-devel libev-devel pcre pcre-devel mbedtls mbedtls-devel libsodium libsodium-devel c-ares c-ares-devel
    res=`which wget`
    [[ "$?" != "0" ]] && yum install -y wget
    res=`which netstat`
    [[ "$?" != "0" ]] && yum install -y net-tools


    if [[ -s /etc/selinux/config ]] && grep 'SELINUX=enforcing' /etc/selinux/config; then
        sed -i 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/selinux/config
        setenforce 0
    fi
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
    ssPath=`which ss-server`
    if [[ "$?" != "0" ]]; then
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
 cat > /usr/lib/systemd/system/shadowsocks-libev.service <<-EOF
[Unit]
Description=shadowsocks
Documentation=https://hijk.art/
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
PIDFile=/var/run/shadowsocks-libev.pid
LimitNOFILE=32768
ExecStart=$ssPath -c $CONFIG_FILE -f /var/run/shadowsocks-libev.pid
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
    if [[ "${res}" = "" ]]; then
        colorEcho $RED " ss启动失败，请检查端口是否被占用！"
        exit 1
    fi
}

setFirewall() {
    systemctl status firewalld > /dev/null 2>&1
    if [[ $? -eq 0 ]];then
        firewall-cmd --permanent --add-port=${PORT}/tcp
        firewall-cmd --permanent --add-port=${PORT}/udp
        firewall-cmd --reload
    else
        nl=`iptables -nL | nl | grep FORWARD | awk '{print $1}'`
        if [[ "$nl" != "3" ]]; then
            iptables -I INPUT -p tcp --dport ${PORT} -j ACCEPT
            iptables -I INPUT -p udp --dport ${PORT} -j ACCEPT
        fi
    fi
}

info() {
    port=`grep server_port $CONFIG_FILE| cut -d: -f2 | tr -d \",' '`
    res=`netstat -nltp | grep ${port} | grep 'ss-server'`
    [[ -z "$res" ]] && status="${RED}已停止${PLAIN}" || status="${GREEN}正在运行${PLAIN}"
    password=`grep password $CONFIG_FILE| cut -d: -f2 | tr -d \",' '`
    method=`grep method $CONFIG_FILE| cut -d: -f2 | tr -d \",' '`
    
    res=`echo -n "${method}:${password}@${IP}:${port}" | base64 -w 0`
    link="ss://${res}"

    echo ============================================
    echo -e " ${BLUE}ss运行状态${PLAIN}：${status}"
    echo -e " ${BLUE}ss配置文件：${PLAIN}${RED}$CONFIG_FILE${PLAIN}"
    echo ""
    echo -e " ${RED}ss配置信息：${PLAIN}"
    echo -e "  ${BLUE}IP(address):${PLAIN}  ${RED}${IP}${PLAIN}"
    echo -e "  ${BLUE}端口(port)：${PLAIN}${RED}${port}${PLAIN}"
    echo -e "  ${BLUE}密码(password)：${PLAIN}${RED}${password}${PLAIN}"
    echo -e "  ${BLUE}加密方式(method)：${PLAIN} ${RED}${method}${PLAIN}"
    echo
    echo -e " ${BLUE}ss链接${PLAIN}： ${link}"
    qrencode -o - -t utf8 ${link}
}

install() {
    echo -n -e " ${BLUE}系统版本:$PLAIN "
    cat /etc/centos-release
    checkSystem
    getData
    preinstall
    installSS
    setFirewall

    info
}

uninstall() {
    echo ""
    read -p " 确定卸载SS吗？(y/n)" answer
    [[ -z ${answer} ]] && answer="n"

    if [[ "${answer}" == "y" ]] || [[ "${answer}" == "Y" ]]; then
        systemctl stop shadowsocks-libev && systemctl disable shadowsocks-libev
        rm -rf /usr/lib/systemd/system/shadowsocks-libev.service
        cd /usr/local/bin && rm -rf ss-local ss-manager ss-nat ss-redir ss-server ss-tunnel
        rm -rf /usr/lib64/libshadowsocks-libev*
        rm -rf /usr/share/doc/shadowsocks-libev
        rm -rf /usr/share/man/man1/ss-*.1.gz
        rm -rf /usr/share/man/man8/shadowsocks-libev.8.gz
        colorEcho $GREEN " SS卸载成功"
    fi
}

checkSystem

slogon

action=$1
[[ -z $1 ]] && action=install
case "$action" in
    install|uninstall|info)
        ${action}
        ;;
    *)
        echo " 参数错误"
        echo "  用法: `basename $0` [install|uninstall|info]"
        ;;
esac
