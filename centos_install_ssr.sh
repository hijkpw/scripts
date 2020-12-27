#!/bin/bash
# shadowsocksR/SSR CentOS 7/8一键安装教程
# Author: hijk<https://hijk.art>


RED="\033[31m"      # Error message
GREEN="\033[32m"    # Success message
YELLOW="\033[33m"   # Warning message
BLUE="\033[36m"     # Info message
PLAIN='\033[0m'

V6_PROXY=""
IP=`curl -sL -4 ip.sb`
if [[ "$?" != "0" ]]; then
    IP=`curl -sL -6 ip.sb`
    V6_PROXY="https://gh.hijk.art/"
fi

FILENAME="ShadowsocksR-v3.2.2"
URL="${V6_PROXY}https://github.com/shadowsocksrr/shadowsocksr/archive/3.2.2.tar.gz"
BASE=`pwd`

OS=`hostnamectl | grep -i system | cut -d: -f2`

CONFIG_FILE="/etc/shadowsocksR.json"

colorEcho() {
    echo -e "${1}${@:2}${PLAIN}"
}


checkSystem() {
    result=$(id | awk '{print $1}')
    if [ $result != "uid=0(root)" ]; then
        colorEcho $RED " 请以root身份执行该脚本"
        exit 1
    fi

    if [ ! -f /etc/centos-release ];then
        res=`which yum`
        if [ "$?" != "0" ]; then
            colorEcho $RED " 系统不是CentOS"
            exit 1
         fi
    else
        result=`cat /etc/centos-release|grep -oE "[0-9.]+"`
        main=${result%%.*}
        if [ $main -lt 7 ]; then
            colorEcho $RED " 不受支持的CentOS版本"
            exit 1
         fi
    fi
}

slogon() {
    clear
    echo "#############################################################"
    echo -e "#         ${RED}CentOS 7/8 ShadowsocksR/SSR 一键安装脚本${PLAIN}           #"
    echo -e "# ${GREEN}作者${PLAIN}: 网络跳越(hijk)                                      #"
    echo -e "# ${GREEN}网址${PLAIN}: https://hijk.art                                    #"
    echo -e "# ${GREEN}论坛${PLAIN}: https://hijk.club                                   #"
    echo -e "# ${GREEN}TG群${PLAIN}: https://t.me/hijkclub                               #"
    echo -e "# ${GREEN}Youtube频道${PLAIN}: https://youtube.com/channel/UCYTB--VsObzepVJtc9yvUxQ #"
    echo "#############################################################"
    echo ""
}

getData() {
    read -p " 请设置SSR的密码（不输入则随机生成）:" PASSWORD
    [ -z "$PASSWORD" ] && PASSWORD=`cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1`
    echo ""
    colorEcho $BLUE " 密码： $PASSWORD"
    echo ""
    
    while true
    do
        read -p " 请设置SSR的端口号[1-65535]:" PORT
        [ -z "$PORT" ] && PORT="12345"
        if [ "${PORT:0:1}" = "0" ]; then
            echo -e " ${RED}端口不能以0开头${PLAIN}"
            exit 1
        fi
        expr $PORT + 0 &>/dev/null
        if [ $? -eq 0 ]; then
            if [ $PORT -ge 1 ] && [ $PORT -le 65535 ]; then
                echo ""
                colorEcho $BLUE " 端口号： $PORT"
                echo ""
                break
            else
                colorEcho $RED " 输入错误，端口号为1-65535的数字"
            fi
        else
            colorEcho $RED " 输入错误，端口号为1-65535的数字"
        fi
    done


    colorEcho $BLUE " 请选择SSR的加密方式:" 
    echo "  1)aes-256-cfb"
    echo "  2)aes-192-cfb"
    echo "  3)aes-128-cfb"
    echo "  4)aes-256-ctr"
    echo "  5)aes-192-ctr"
    echo "  6)aes-128-ctr"
    echo "  7)aes-256-cfb8"
    echo "  8)aes-192-cfb8"
    echo "  9)aes-128-cfb8"
    echo "  10)camellia-128-cfb"
    echo "  11)camellia-192-cfb"
    echo "  12)camellia-256-cfb"
    echo "  13)chacha20-ietf"
    read -p " 请选择加密方式（默认aes-256-cfb）" answer
    if [ -z "$answer" ]; then
        METHOD="aes-256-cfb"
    else
        case $answer in
        1)
            METHOD="aes-256-cfb"
            ;;
        2)
            METHOD="aes-192-cfb"
            ;;
        3)
            METHOD="aes-128-cfb"
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
            METHOD="aes-256-cfb8"
            ;;
        8)
            METHOD="aes-192-cfb8"
            ;;
        9)
            METHOD="aes-128-cfb8"
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
        *)
            colorEcho $RED " 无效的选择，使用默认加密方式"
            METHOD="aes-256-cfb"
        esac
    fi
    echo ""
    colorEcho $BLUE " 加密方式： $METHOD"
    echo ""

    colorEcho $BLUE " 请选择SSR协议："
    echo "   1)origin"
    echo "   2)verify_deflate"
    echo "   3)auth_sha1_v4"
    echo "   4)auth_aes128_md5"
    echo "   5)auth_aes128_sha1"
    echo "   6)auth_chain_a"
    echo "   7)auth_chain_b"
    echo "   8)auth_chain_c"
    echo "   9)auth_chain_d"
    echo "   10)auth_chain_e"
    echo "   11)auth_chain_f"
    read -p " 请选择SSR协议（默认origin）" answer
    if [ -z "$answer" ]; then
        PROTOCOL="origin"
    else
        case $answer in
        1)
            PROTOCOL="origin"
            ;;
        2)
            PROTOCOL="verify_deflate"
            ;;
        3)
            PROTOCOL="auth_sha1_v4"
            ;;
        4)
            PROTOCOL="auth_aes128_md5"
            ;;
        5)
            PROTOCOL="auth_aes128_sha1"
            ;;
        6)
            PROTOCOL="auth_chain_a"
            ;;
        7)
            PROTOCOL="auth_chain_b"
            ;;
        8)
            PROTOCOL="auth_chain_c"
            ;;
        9)
            PROTOCOL="auth_chain_d"
            ;;
        10)
            PROTOCOL="auth_chain_e"
            ;;
        11)
            PROTOCOL="auth_chain_f"
            ;;
        *)
            colorEcho $RED " 无效的选择，使用默认协议"
            PROTOCOL="origin"
        esac
    fi
    echo ""
    colorEcho $BLUE " SSR协议： $PROTOCOL"
    echo ""


    colorEcho $BLUE " 请选择SSR混淆模式："
    echo "   1)plain"
    echo "   2)http_simple"
    echo "   3)http_post"
    echo "   4)tls1.2_ticket_auth"
    echo "   5)tls1.2_ticket_fastauth"
    read -p " 请选择混淆模式（默认plain）" answer
    if [ -z "$answer" ]; then
        OBFS="plain"
    else
        case $answer in
        1)
            OBFS="plain"
            ;;
        2)
            OBFS="http_simple"
            ;;
        3)
            OBFS="http_post"
            ;;
        4)
            OBFS="tls1.2_ticket_auth"
            ;;
        5)
            OBFS="tls1.2_ticket_fastauth"
            ;;
        *)
            colorEcho $RED " 无效的选择，使用默认混淆模式"
            OBFS="plain"
        esac
    fi
    echo ""
    colorEcho $BLUE " 混淆模式： $OBFS"
    echo ""
}

preinstall() {
    colorEcho $BLUE " 更新系统..."
    yum clean all
    #yum update -y
    colorEcho $BLUE " 安装必要软件"
    yum install -y epel-release telnet curl wget vim net-tools libsodium openssl unzip tar qrencode
    res=`which wget`
    [ "$?" != "0" ] && yum install -y wget
    res=`which netstat`
    [ "$?" != "0" ] && yum install -y net-tools
    if [ $main -eq 8 ]; then
        ln -s /usr/bin/python3 /usr/bin/python
    fi

    if [ -s /etc/selinux/config ] && grep 'SELINUX=enforcing' /etc/selinux/config; then
        sed -i 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/selinux/config
        setenforce 0
    fi
}

installSSR() {
    if [ ! -d /usr/local/shadowsocks ]; then
        echo 下载安装文件
        if ! wget --no-check-certificate -O ${FILENAME}.tar.gz ${URL}; then
            echo -e " [${RED}Error${PLAIN}] 下载文件失败!"
            exit 1
        fi

        tar -zxf ${FILENAME}.tar.gz
        mv shadowsocksr-3.2.2/shadowsocks /usr/local
        if [ ! -f /usr/local/shadowsocks/server.py ]; then
            colorEcho $RED " $OS 安装失败，请到 https://hijk.art 网站反馈"
            cd ${BASE} && rm -rf shadowsocksr-3.2.2 ${FILENAME}.tar.gz
            exit 1
        fi
        cd ${BASE} && rm -rf shadowsocksr-3.2.2 ${FILENAME}.tar.gz
    fi

     cat > $CONFIG_FILE<<-EOF
{
    "server":"0.0.0.0",
    "server_ipv6":"::",
    "server_port":${PORT},
    "local_port":1080,
    "password":"${PASSWORD}",
    "timeout":600,
    "method":"${METHOD}",
    "protocol":"${PROTOCOL}",
    "protocol_param":"",
    "obfs":"${OBFS}",
    "obfs_param":"",
    "redirect":"",
    "dns_ipv6":false,
    "fast_open":false,
    "workers":1
}
EOF

cat > /usr/lib/systemd/system/shadowsocksR.service <<-EOF
[Unit]
Description=shadowsocksR
Documentation=https://hijk.art/
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
LimitNOFILE=32768
ExecStart=/usr/local/shadowsocks/server.py -c $CONFIG_FILE -d start
ExecReload=/bin/kill -s HUP \$MAINPID
ExecStop=/bin/kill -s TERM \$MAINPID

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable shadowsocksR && systemctl restart shadowsocksR
    sleep 3
    res=`netstat -nltp | grep ${PORT} | grep python`
    if [ "${res}" = "" ]; then
        colorEcho $RED " ssr启动失败，请检查端口是否被占用！"
        exit 1
    fi
}

setFirewall() {
    systemctl status firewalld > /dev/null 2>&1
    if [[ $? -eq 0 ]];then
        firewall-cmd --permanent --add-service=http
        firewall-cmd --permanent --add-port=${PORT}/tcp
        firewall-cmd --permanent --add-port=${PORT}/udp
        firewall-cmd --reload
    else
        nl=`iptables -nL | nl | grep FORWARD | awk '{print $1}'`
        if [[ "$nl" != "3" ]]; then
            iptables -I INPUT -p tcp --dport 80 -j ACCEPT
            iptables -I INPUT -p tcp --dport ${PORT} -j ACCEPT
            iptables -I INPUT -p udp --dport ${PORT} -j ACCEPT
        fi
    fi
}

installBBR() {
    result=$(lsmod | grep bbr)
    if [ "$result" != "" ]; then
        colorEcho $GREEN " BBR模块已安装"
        INSTALL_BBR=false
        return
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
    rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
    rpm -Uvh http://www.elrepo.org/elrepo-release-7.0-4.el7.elrepo.noarch.rpm
    yum --enablerepo=elrepo-kernel install kernel-ml -y
    yum remove kernel-3.* -y
    grub2-set-default 0
    echo "tcp_bbr" >> /etc/modules-load.d/modules.conf
    INSTALL_BBR=true
}

info() {
    port=`grep server_port $CONFIG_FILE| cut -d: -f2 | tr -d \",' '`
    res=`netstat -nltp | grep ${port} | grep python`
    [ -z "$res" ] && status="${RED}已停止${PLAIN}" || status="${GREEN}正在运行${PLAIN}"
    password=`grep password $CONFIG_FILE| cut -d: -f2 | tr -d \",' '`
    method=`grep method $CONFIG_FILE| cut -d: -f2 | tr -d \",' '`
    protocol=`grep protocol $CONFIG_FILE| cut -d: -f2 | tr -d \",' '`
    obfs=`grep obfs $CONFIG_FILE| cut -d: -f2 | tr -d \",' '`
    
    p1=`echo -n ${password} | base64 -w 0`
    p1=`echo -n ${p1} | tr -d =`
    res=`echo -n "${IP}:${port}:${protocol}:${method}:${obfs}:${p1}/?remarks=&protoparam=&obfsparam=" | base64 -w 0`
    res=`echo -n ${res} | tr -d =`
    link="ssr://${res}"

    echo ""
    echo ============================================
    echo -e " ${BLUE}ssr运行状态：${PLAIN}${status}"
    echo -e " ${BLUE}ssr配置文件：${PLAIN}${RED}$CONFIG_FILE${PLAIN}"
    echo ""
    echo -e " ${RED}ssr配置信息：${PLAIN}"
    echo -e "   ${BLUE}IP(address):${PLAIN}  ${RED}${IP}${PLAIN}"
    echo -e "   ${BLUE}端口(port)：${PLAIN}${RED}${port}${PLAIN}"
    echo -e "   ${BLUE}密码(password)：${PLAIN}${RED}${password}${PLAIN}"
    echo -e "   ${BLUE}加密方式(method)：${PLAIN} ${RED}${method}${PLAIN}"
    echo -e "   ${BLUE}协议(protocol)：${PLAIN} ${RED}${protocol}${PLAIN}"
    echo -e "   ${BLUE}混淆(obfuscation)：${PLAIN} ${RED}${obfs}${PLAIN}"
    echo
    echo -e " ${BLUE}ssr链接:${PLAIN} $link"
    qrencode -o - -t utf8 $link
}

bbrReboot() {
    if [ "${INSTALL_BBR}" == "true" ]; then
        echo  
        echo  为使BBR模块生效，系统将在30秒后重启
        echo  
        echo -e " 您可以按 ctrl + c 取消重启，稍后输入 ${RED}reboot${PLAIN} 重启系统"
        sleep 30
        reboot
    fi
}


install() {
    echo -n "系统版本:  "
    cat /etc/centos-release
    checkSystem
    getData
    preinstall
    installBBR
    installSSR
    setFirewall

    info
    
    bbrReboot
}

uninstall() {
    echo ""
    read -p " 确定卸载SSR吗？(y/n)" answer
    [ -z ${answer} ] && answer="n"

    if [ "${answer}" == "y" ] || [ "${answer}" == "Y" ]; then
        rm -f $CONFIG_FILE
        rm -f /var/log/shadowsocks.log
        rm -rf /usr/local/shadowsocks
        systemctl disable shadowsocksR && systemctl stop shadowsocksR && rm -rf /usr/lib/systemd/system/shadowsocksR.service
    fi
    echo -e " ${RED}卸载成功${PLAIN}"
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
        echo " 用法: `basename $0` [install|uninstall]"
        ;;
esac
