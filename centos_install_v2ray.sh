#!/bin/bash
# v2ray centos系统一键安装教程
# Author: hijk<https://www.hijk.pw>

echo "#############################################################"
echo "#         CentOS 7/8 v2ray 一键安装脚本                     #"
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

function preinstall()
{
    sed -i 's/#ClientAliveInterval 0/ClientAliveInterval 60/' /etc/ssh/sshd_config
    systemctl restart sshd
    ret=`nginx -t`
    if [ "$ret" <> "0" ]; then
        echo "更新系统..."
        yum update -y
    fi
    echo "安装必要软件"
    yum install -y epel-release telnet wget vim net-tools ntpdate unzip
    yum install -y nginx
    res=`cat /usr/share/nginx/html/index.html| grep Flatfy`
    if [ "${res}" = "" ]; then
        wget 'https://github.com/hijkpw/scripts/raw/master/Flatfy%20V3.zip' -O theme.zip
        unzip theme.zip
        rm -rf __MACOSX/
        mv /usr/share/nginx/html/index.html /usr/share/nginx/html/index.html.bak
        mv Flatfy\ V3/* /usr/share/nginx/html/
        rm -rf theme.zip Flatfy\ V3
    fi
    systemctl enable nginx && systemctl start nginx

    if [ -s /etc/selinux/config ] && grep 'SELINUX=enforcing' /etc/selinux/config; then
        sed -i 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/selinux/config
        setenforce 0
    fi
}

function _install()
{
    echo 安装v2ray...
    bash <(curl -L -s https://install.direct/go.sh)

    while true
    do
        read -p "请输入v2ray的端口[1-65535]:" port
        [ -z "$port" ] && port="21568"
        expr $port + 0 &>/dev/null
        if [ $? -eq 0 ]; then
            if [ $port -ge 1 ] && [ $port -le 65535 ]; then
                echo ""
                echo "端口号： $port"
                echo ""
                break
            else
                echo "输入错误，端口号为1-65535的数字"
            fi
        else
            echo "输入错误，端口号为1-65535的数字"
        fi
    done

    if [ ! -f /etc/v2ray/config.json ]; then
        echo "安装失败，请到 https://www.hijk.pw 网站反馈"
        exit 1
    fi

    sed -i -e "s/port\":.*[0-9]*,/port\": ${port},/" /etc/v2ray/config.json
    logsetting=`cat /etc/v2ray/config.json|grep loglevel`
    if [ "${logsetting}" = "" ]; then
        sed -i '1a\  "log":\n  {\n    "loglevel": "info",\n    "access": "/var/log/v2ray/access.log",\n    "error": "/var/log/v2ray/error.log"\n  },' /etc/v2ray/config.json
    fi
    alterid=`shuf -i50-90 -n1`
    sed -i -e "s/alterId\":.*[0-9]*/alterId\": ${alterid}/" /etc/v2ray/config.json
    uid=`cat /etc/v2ray/config.json | grep id | cut -d: -f2 | tr -d \",' '`
    rm -f /etc/localtime
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
    ntpdate -u time.nist.gov
    systemctl enable v2ray && systemctl restart v2ray
    echo "安装成功！"
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
    echo -e " IP:  ${red}`curl -s -4 icanhazip.com`${plain}"
    echo -e " 端口：${red}${port}${plain}"
    echo -e " id：${red}${uid}${plain}"
    echo -e " 额外id： ${red}${alterid}${plain}"
    echo -e " 加密方式： ${red}auto${plain}"
    echo -e " 传输协议： ${red}tcp${plain}"
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
        echo  您可以按ctrl + c取消重启，稍后输入restart重启系统
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
    preinstall
    installBBR
    _install
    setFirewall

    showTip
}

install
