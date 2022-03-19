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
RELEASE=("Debian" "Ubuntu" "CentOS" "CentOS")
PACKAGE_UPDATE=("apt -y update" "apt -y update" "yum -y update" "yum -y update")
PACKAGE_INSTALL=("apt -y install" "apt -y install" "yum -y install" "yum -y install")
PACKAGE_UNINSTALL=("apt -y autoremove" "apt -y autoremove" "yum -y autoremove" "yum -y autoremove")

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

# 判断VPS虚拟化架构
VIRT=$(systemd-detect-virt)

# 确定CPU架构
arch_affix() {
    case "$(uname -m)" in
        x86_64 | amd64) cpuArch='amd64' ;;
        armv8 | aarch64) cpuArch='aarch64' ;;
        s390x) cpuArch='s390x' ;;
        *) red "不支持的CPU架构！" && exit 1 ;;
    esac
}

# 检查TUN模块状态
check_tun(){
    TUN=$(cat /dev/net/tun 2>&1 | tr '[:upper:]' '[:lower:]')
    [[ ! $TUN =~ 'in bad state' ]] && [[ ! $TUN =~ '处于错误状态' ]] && [[ ! $TUN =~ 'Die Dateizugriffsnummer ist in schlechter Verfassung' ]] && red "检测到未开启TUN模块，请到VPS控制面板处开启" && exit 1
}

# 获取VPS IP特征及WARP状态
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

# 安装Wgcf组件之一——WireGuard
install_wireguard(){
    ${PACKAGE_UPDATE[int]} && ${PACKAGE_INSTALL[int]} curl wget sudo grep
    if [ $RELEASE == "CentOS" ]; then
        ${PACKAGE_INSTALL[int]} epel-release
        ${PACKAGE_INSTALL[int]} wireguard-tools net-tools iptables wireguard-dkms
    fi
    if [ $RELEASE == "Debian" ]; then
        ${PACKAGE_UPDATE[int]}
        ${PACKAGE_INSTALL[int]} lsb-release
        echo "deb http://deb.debian.org/debian $(lsb_release -sc)-backports main" > /etc/apt/sources.list.d/backports.list
        ${PACKAGE_UPDATE[int]}
        ${PACKAGE_INSTALL[int]} --no-install-recommends net-tools iproute2 openresolv dnsutils wireguard-tools iptables
    fi
    if [ $RELEASE == "Ubuntu" ]; then
        ${PACKAGE_UPDATE[int]}
        ${PACKAGE_INSTALL[int]} --no-install-recommends net-tools iproute2 openresolv dnsutils wireguard-tools iptables
    fi
}

# 注册WARP账号
wgcf_register(){
    while [[ ! -f wgcf-account.toml ]]; do
        yes | wgcf register
        sleep 5
	done
}

# 卸载WARP
uninstall(){
    wg-quick down wgcf >/dev/null 2>&1
    systemctl disable --now wg-quick@wgcf >/dev/null 2>&1
    rpm -e wireguard-tools 2>/dev/null
    [[ $(systemctl is-active systemd-resolved) != active ]] && systemctl enable --now systemd-resolved >/dev/null 2>&1
    rm -rf /usr/local/bin/wgcf /etc/wireguard /usr/bin/wireguard-go wgcf-account.toml wgcf-profile.conf /usr/bin/warp /etc/dnsmasq.d/warp.conf
    [[ -e /etc/gai.conf ]] && sed -i '/^precedence \:\:ffff\:0\:0/d;/^label 2002\:\:\/16/d' /etc/gai.conf
	sed -i "/250   warp/d" /etc/iproute2/rt_tables
    warp-cli --accept-tos disconnect >/dev/null 2>&1
    warp-cli --accept-tos disable-always-on >/dev/null 2>&1
    warp-cli --accept-tos delete >/dev/null 2>&1
    ${PACKAGE_UNINSTALL[int]} wireguard-tools wireguard-dkms ipset dnsmasq resolvconf mtr
    ${PACKAGE_UNINSTALL[int]} cloudflare-warp
    green "CloudFlare WARP 已卸载成功！"
}

# 菜单
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
    if [ $WARPIPv4Status == "无法检测IPv4状态" ]; then
        green "1. 安装Wgcf IPv4 WARP"
        green "2. 安装Wgcf 双栈 WARP"
    fi
    if [ $WARPIPv6Status == "无法检测IPv6状态" ]; then
        green "1. 安装Wgcf IPv6 WARP"
        green "2. 安装Wgcf 双栈 WARP"
    fi
    if [ $WARPIPv4Status == "原生IPv4" && $WARPIPv6Status == "原生IPv6" ]; then
        green "1. 检测到双栈VPS、无法使用单栈WARP"
        green "2. 安装Wgcf 双栈 WARP"
    fi
    read -p "请输入选项：" menuNumberInput
    case "$menuNumberInput" in
        * ) exit 1 ;;
    esac
}

check_tun
arch_affix
menu
