#!/bin/bash
# shadowsocks/ss CentOS一键安装教程
# Author: hijk<https://www.hijk.pw>

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
    if [ "$main" != "7" ]; then
        echo "不受支持的CentOS版本"
        exit 1
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
        expr $port + 0 &>/dev/null
        if [ $? -eq 0 ]; then
            if [ $port -ge 1025 ] && [ $port -le 65535 ]; then
                echo ""
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
    read -p "请选择（默认aes-256-cfb）" answer
    if [ -z "$answer" ]; then
        method="aes-256-cfb"
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
            echo "无效的选择，使用默认的aes-256-cfb"
            method="aes-256-cfb"
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
    ret=`nginx -t`
    if [ "$?" != "0" ]; then
        echo "更新系统..."
        yum update -y
    fi
    
    echo "安装必要软件"
    yum install -y epel-release telnet wget vim net-tools unzip
    yum install -y nginx
    systemctl enable nginx && systemctl restart nginx

    if [ -s /etc/selinux/config ] && grep 'SELINUX=enforcing' /etc/selinux/config; then
        sed -i 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/selinux/config
        setenforce 0
    fi
}

function installSS()
{
    echo 安装SS...
    wget -O /etc/yum.repos.d/librehat-shadowsocks-epel-7.repo 'https://copr.fedorainfracloud.org/coprs/librehat/shadowsocks/repo/epel-7/librehat-shadowsocks-epel-7.repo' >> /dev/null 2>&1
    yum install -y shadowsocks-libev

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
    systemctl enable shadowsocks-libev
    systemctl restart shadowsocks-libev
}

function setFirewall()
{
    systemctl status firewalld > /dev/null 2>&1
    if [ $? -eq 0 ];then
        firewall-cmd --permanent --add-port=${port}/tcp
        firewall-cmd --permanent --add-port=${port}/udp
        firewall-cmd --permanent --add-service=http
        firewall-cmd --reload
    fi
}

function installBBR()
{
    result=$(lsmod | grep bbr)
    if [ "$result" != "" ]; then
        echo BBR模块已安装
        echo "3" > /proc/sys/net/ipv4/tcp_fastopen
        echo "net.ipv4.tcp_fastopen = 3" >> /etc/sysctl.conf
        bbr=true
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
    echo -e "          ${red}SS安装成功！${plain}               "
    echo ""
    echo -e " IP(address):  ${red}`curl -s -4 icanhazip.com`${plain}"
    echo -e " 端口(port)：${red}${port}${plain}"
    echo -e " 密码(password)：${red}${password}${plain}"
    echo -e " 加密方式(method)： ${red}${method}${plain}"
    echo    
    echo -e "SS配置文件：${red}/etc/shadowsocks-libev/config.json${plain}，请按照自己需要进行修改"         
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

echo -n "系统版本:  "
cat /etc/centos-release

function install()
{
    checkSystem
    getData
    preinstall
    installBBR
    installSS
    setFirewall

    showTip
}

function uninstall()
{
    read -p "您确定真的要卸载SS吗？(y/n)" answer
    [ -z ${answer} ] && answer="n"

    if [ "${answer}" == "y" ] || [ "${answer}" == "Y" ]; then
        yum remove shadowsocks-libev
        echo "SS卸载完成"
    fi
}

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
