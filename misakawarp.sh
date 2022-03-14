#!/bin/bash

# 控制台字体
red() {
    echo -e "\033[31m\033[01m$1\033[0m"
}

green() {
    echo -e "\033[32m\033[01m$1\033[0m"
}

yellow() {
    echo -e "\033[33m\033[01m$1\033[0m"
}

# 判断系统及定义系统安装依赖方式
REGEX=("debian" "ubuntu" "centos|red hat|kernel|oracle linux|alma|rocky" "'amazon linux'")
RELEASE=("Debian" "Ubuntu" "CentOS" "CentOS" "Alpine")
PACKAGE_UPDATE=("apt -y update" "apt -y update" "yum -y update" "yum -y update")
PACKAGE_INSTALL=("apt -y install" "apt -y install" "yum -y install" "yum -y install" "apk add -f")
PACKAGE_REMOVE=("apt -y remove" "apt -y remove" "yum -y remove" "yum -y remove")

# 判断是否为root用户
[[ $EUID -ne 0 ]] && yellow "请在root用户下运行脚本" && exit 1

# 检测系统，本部分代码感谢fscarmen的指导
CMD=("$(grep -i pretty_name /etc/os-release 2>/dev/null | cut -d \" -f2)" "$(hostnamectl 2>/dev/null | grep -i system | cut -d : -f2)" "$(lsb_release -sd 2>/dev/null)" "$(grep -i description /etc/lsb-release 2>/dev/null | cut -d \" -f2)" "$(grep . /etc/redhat-release 2>/dev/null)" "$(grep . /etc/issue 2>/dev/null | cut -d \\ -f1 | sed '/^[ ]*$/d')")

for i in "${CMD[@]}"; do
    SYS="$i" && [[ -n $SYS ]] && break
done

for ((int = 0; int < ${#REGEX[@]}; int++)); do
    [[ $(echo "$SYS" | tr '[:upper:]' '[:lower:]') =~ ${REGEX[int]} ]] && SYSTEM="${RELEASE[int]}" && [[ -n $SYSTEM ]] && break
done

[[ -z $SYSTEM ]] && red "不支持VPS的当前系统，请使用主流的操作系统" && exit 1

check_tun(){
    TUN=$(cat /dev/net/tun 2>&1 | tr '[:upper:]' '[:lower:]')
    [[ ! $TUN =~ 'in bad state' ]] && [[ ! $TUN =~ '处于错误状态' ]] && [[ ! $TUN =~ 'Die Dateizugriffsnummer ist in schlechter Verfassung' ]] && red "检测到未开启TUN模块，请到VPS控制面板处开启" && exit 1
}

get_status(){
    WARPIPv4Status=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    WARPIPv6Status=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    [ $WARPIPv4Status == "on" ] && WARPIPv4Status="WARP IPv4"
    [ $WARPIPv4Status == "off" ] && WARPIPv4Status="原生IPv4"
    [ $WARPIPv6Status == "on" ] && WARPIPv6Status="WARP IPv6"
    [ $WARPIPv6Status == "off" ] && WARPIPv6Status="原生IPv6"
    [ -z $WARPIPv4Status ] && WARPIPv4Status="无法检测IPv4状态"
    [ -z $WARPIPv6Status ] && WARPIPv6Status="无法检测IPv6状态"
    [[ ! -f /usr/local/bin/wgcf ]] && WgcfStatus="未安装"
    [[ -f /usr/local/bin/wgcf ]] && WgcfStatus="未启动" && [[ -n $(wg) ]] && WgcfStatus="已启动"
}

menu(){
    clear
    get_status
    red "=========================="
    red "    Misaka WARP Script    "
    red "   Site: owo.misaka.rest  "
    echo "                          "
    green "VPS IPv4状态：$WARPIPv4Status"
    green "VPS IPv6状态：$WARPIPv6Status"
    green "Wgcf状态：$WgcfStatus"
    red "=========================="
    echo "   "
    if [ $WARPIPv6Status == "无法检测IPv6状态" ]; then
        green "1. 安装Wgcf IPv4"
        green "2. 安装Wgcf 双栈"
    fi
}

check_tun
menu
