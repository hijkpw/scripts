#! /bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

Green="\033[32m"
Font="\033[0m"
Blue="\033[33m"

rootness(){
    if [[ $EUID -ne 0 ]]; then
       echo "Error:This script must be run as root!" 1>&2
       exit 1
    fi
}

checkos(){
    if [[ -f /etc/redhat-release ]];then
        OS=CentOS
    elif cat /etc/issue | grep -q -E -i "debian";then
        OS=Debian
    elif cat /etc/issue | grep -q -E -i "ubuntu";then
        OS=Ubuntu
    elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat";then
        OS=CentOS
    elif cat /proc/version | grep -q -E -i "debian";then
        OS=Debian
    elif cat /proc/version | grep -q -E -i "ubuntu";then
        OS=Ubuntu
    elif cat /proc/version | grep -q -E -i "centos|red hat|redhat";then
        OS=CentOS
    else
        echo "Not supported OS, Please reinstall OS and try again."
        exit 1
    fi
}

disable_selinux(){
    if [ -s /etc/selinux/config ] && grep 'SELINUX=enforcing' /etc/selinux/config; then
        sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
        setenforce 0
    fi
}

disable_iptables(){
    systemctl stop firewalld.service >/dev/null 2>&1
    systemctl disable firewalld.service >/dev/null 2>&1
    service iptables stop >/dev/null 2>&1
    chkconfig iptables off >/dev/null 2>&1
}

get_ip(){
    ip=`curl http://whatismyip.akamai.com`
}

config_socat(){
    echo -e "${Green}请输入Socat配置信息！${Font}"
    read -p "请输入本地端口:" port1
    read -p "请输入远程端口:" port2
    read -p "请输入远程IP:" socatip
}

start_socat(){
    echo -e "${Green}正在配置Socat...${Font}"
    nohup socat TCP4-LISTEN:${port1},reuseaddr,fork TCP4:${socatip}:${port2} >> /root/socat.log 2>&1 &
    nohup socat -T 600 UDP4-LISTEN:${port1},reuseaddr,fork UDP4:${socatip}:${port2} >> /root/socat.log 2>&1 &
    if [ "${OS}" == 'CentOS' ];then
        sed -i '/exit/d' /etc/rc.d/rc.local
        echo "nohup socat TCP4-LISTEN:${port1},reuseaddr,fork TCP4:${socatip}:${port2} >> /root/socat.log 2>&1 &
        nohup socat -T 600 UDP4-LISTEN:${port1},reuseaddr,fork UDP4:${socatip}:${port2}  >> /root/socat.log 2>&1 &
        " >> /etc/rc.d/rc.local
        chmod +x /etc/rc.d/rc.local
    elif [ -s /etc/rc.local ]; then
        sed -i '/exit/d' /etc/rc.local
        echo "nohup socat TCP4-LISTEN:${port1},reuseaddr,fork TCP4:${socatip}:${port2} >> /root/socat.log 2>&1 &
        nohup socat -T 600 UDP4-LISTEN:${port1},reuseaddr,fork UDP4:${socatip}:${port2}  >> /root/socat.log 2>&1 &
        " >> /etc/rc.local
        chmod +x /etc/rc.local
    else
echo -e "${Green}检测到系统无rc.local自启，正在为其配置... ${Font} "
echo "[Unit]
Description=/etc/rc.local
ConditionPathExists=/etc/rc.local
 
[Service]
Type=forking
ExecStart=/etc/rc.local start
TimeoutSec=0
StandardOutput=tty
RemainAfterExit=yes
SysVStartPriority=99
 
[Install]
WantedBy=multi-user.target
" > /etc/systemd/system/rc-local.service
echo "#!/bin/sh -e
#
# rc.local
#
# This script is executed at the end of each multiuser runlevel.
# Make sure that the script will "exit 0" on success or any other
# value on error.
#
# In order to enable or disable this script just change the execution
# bits.
#
# By default this script does nothing.
" > /etc/rc.local
echo "nohup socat TCP4-LISTEN:${port1},reuseaddr,fork TCP4:${socatip}:${port2} >> /root/socat.log 2>&1 &
nohup socat -T 600 UDP4-LISTEN:${port1},reuseaddr,fork UDP4:${socatip}:${port2}  >> /root/socat.log 2>&1 &
" >> /etc/rc.local
chmod +x /etc/rc.local
systemctl enable rc-local >/dev/null 2>&1
systemctl start rc-local >/dev/null 2>&1
    fi
    get_ip
    sleep 3
    echo
    echo -e "${Green}Socat安装并配置成功!${Font}"
    echo -e "${Blue}你的本地端口为:${port1}${Font}"
    echo -e "${Blue}你的远程端口为:${port2}${Font}"
    echo -e "${Blue}你的本地服务器IP为:${ip}${Font}"
    exit 0
}

install_socat(){
    echo -e "${Green}即将安装Socat...${Font}"
    if [ "${OS}" == 'CentOS' ];then
        yum install -y socat
    else
        apt-get -y update
        apt-get install -y socat
    fi
    if [ -s /usr/bin/socat ]; then
    echo -e "${Green}Socat安装完成！${Font}"
    fi
}

status_socat(){
    if [ -s /usr/bin/socat ]; then
    echo -e "${Green}检测到Socat已存在，并跳过安装步骤！${Font}"
        main_x
    else
        main_y
    fi
}

main_x(){
checkos
rootness
disable_selinux
disable_iptables
config_socat
start_socat
}

main_y(){
checkos
rootness
disable_selinux
disable_iptables
install_socat
config_socat
start_socat
}

status_socat
