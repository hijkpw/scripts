#!/bin/bash 
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
PACKAGE_REMOVE=("apt -y remove" "apt -y remove" "yum -y remove" "yum -y remove")
PACKAGE_UNINSTALL=("apt -y autoremove" "apt -y autoremove" "yum -y autoremove" "yum -y autoremove")

CMD=("$(grep -i pretty_name /etc/os-release 2>/dev/null | cut -d \" -f2)" "$(hostnamectl 2>/dev/null | grep -i system | cut -d : -f2)" "$(lsb_release -sd 2>/dev/null)" "$(grep -i description /etc/lsb-release 2>/dev/null | cut -d \" -f2)" "$(grep . /etc/redhat-release 2>/dev/null)" "$(grep . /etc/issue 2>/dev/null | cut -d \\ -f1 | sed '/^[ ]*$/d')") 

for i in "${CMD[@]}"; do
    SYS="$i" && [[ -n $SYS ]] && break
done

for ((int = 0; int < ${#REGEX[@]}; int++)); do
    [[ $(echo "$SYS" | tr '[:upper:]' '[:lower:]') =~ ${REGEX[int]} ]] && SYSTEM="${RELEASE[int]}" && [[ -n $SYSTEM ]] && break
done

[[ -z $SYSTEM ]] && red "不支持当前VPS的系统，请使用主流操作系统" && exit 1

arch=$(uname -m)
wgcfcli=0 # 变量说明：0为Wgcf、1为WARP-Cli
wgcfmode=0 # 变量说明：0为Wgcf单栈模式、1为双栈模式

# 检查TUN模块状态
check_tun(){
    TUN=$(cat /dev/net/tun 2>&1 | tr '[:upper:]' '[:lower:]')
    [[ ! $TUN =~ 'in bad state' ]] && [[ ! $TUN =~ '处于错误状态' ]] && [[ ! $TUN =~ 'Die Dateizugriffsnummer ist in schlechter Verfassung' ]] && red "检测到未开启TUN模块，请到VPS控制面板处开启" && exit 1
}

# 获取VPS IP特征及WARP状态
get_status(){
    WARPIPv4Status=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    WARPIPv6Status=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    WARPSocks5Port=$(warp-cli --accept-tos settings 2>/dev/null | grep 'WarpProxy on port' | awk -F "port " '{print $2}')
    WARPSocks5Status=$(curl -sx socks5h://localhost:$WARPSocks5Port https://www.cloudflare.com/cdn-cgi/trace -k --connect-timeout 2 | grep warp | cut -d= -f2)
    [[ $WARPIPv4Status =~ "on"|"plus" ]] && WARPIPv4Status="WARP IPv4"
    [[ $WARPIPv4Status == "off" ]] && WARPIPv4Status="原生IPv4"
    [[ $WARPIPv6Status =~ "on"|"plus" ]] && WARPIPv6Status="WARP IPv6"
    [[ $WARPIPv6Status == "off" ]] && WARPIPv6Status="原生IPv6"
    [[ -z $WARPIPv4Status ]] && WARPIPv4Status="无法检测IPv4状态"
    [[ -z $WARPIPv6Status ]] && WARPIPv6Status="无法检测IPv6状态"
    [[ ! -f /usr/local/bin/wgcf ]] && WgcfStatus="未安装"
    [[ -f /usr/local/bin/wgcf ]] && WgcfStatus="未启动" && [[ -n $(wg) ]] && WgcfStatus="已启动"
    [[ -z $WARPSocks5Port ]] && WARPSocks5Status="未安装"
    [[ $WARPSocks5Status == "off" ]] && WARPSocks5Status="未启动"
    [[ $WARPSocks5Status =~ "on"|"plus" ]] && WARPSocks5Status="已启动"
}

install(){
    if [[ $wgcfcli == 0 ]]; then
        if [[ $wgcfmode == 0 ]]; then
            if [[ $WARPIPv6Status == "原生IPv6" && $WARPIPv4Status == "无法检测IPv4状态" ]]; then
                wget -N https://raw.githubusercontents.com/Misaka-blog/Misaka-WARP-Script/master/wgcf-warp/warp64.sh && bash warp64.sh
            fi
            if [[ $WARPIPv4Status == "原生IPv4" && $WARPIPv6Status == "无法检测IPv6状态" ]]; then
                wget -N https://raw.githubusercontents.com/Misaka-blog/Misaka-WARP-Script/master/wgcf-warp/warp46.sh && bash warp46.sh
            fi
            if [[ $WARPIPv4Status == "原生IPv4" && $WARPIPv6Status == "原生IPv6" ]]; then
                exit 1
            fi
        fi
        if [[ $wgcfmode == 1 ]]; then
            if [[ $WARPIPv6Status == "原生IPv6" && $WARPIPv4Status == "无法检测IPv4状态" ]]; then
                wget -N https://raw.githubusercontents.com/Misaka-blog/Misaka-WARP-Script/master/wgcf-warp/warp6d.sh && bash warp6d.sh
            fi
            if [[ $WARPIPv4Status == "原生IPv4" && $WARPIPv6Status == "无法检测IPv6状态" ]]; then
                wget -N https://raw.githubusercontents.com/Misaka-blog/Misaka-WARP-Script/master/wgcf-warp/warp4d.sh && bash warp4d.sh
            fi
            if [[ $WARPIPv4Status == "原生IPv4" && $WARPIPv6Status == "原生IPv6" ]]; then
                wget -N https://raw.githubusercontents.com/Misaka-blog/Misaka-WARP-Script/master/wgcf-warp/warpd.sh && bash warpd.sh
            fi
        fi
    fi
    if [[ $wgcfcli == 1 ]]; then
        if [[ $WARPIPv4Status == "原生IPv4" && $WARPIPv6Status == "无法检测IPv6状态" ]]; then
            wget -N https://raw.githubusercontents.com/Misaka-blog/Misaka-WARP-Script/master/warp-cli/warp-cli.sh && bash warp-cli.sh
        fi
        if [[ $WARPIPv4Status == "原生IPv4" && $WARPIPv6Status == "原生IPv6" ]]; then
            wget -N https://raw.githubusercontents.com/Misaka-blog/Misaka-WARP-Script/master/warp-cli/warp-cli.sh && bash warp-cli.sh
        fi
    fi
}

wgcfswitch(){
    wget -N https://raw.githubusercontents.com/Misaka-blog/Misaka-WARP-Script/master/wgcf-warp/switchwarp.sh && bash switchwarp.sh
}

warpcliswitch(){
    wget -N https://raw.githubusercontents.com/Misaka-blog/Misaka-WARP-Script/master/warp-cli/switch.sh && bash switch.sh
}

warpcliport(){
    wget -N https://raw.githubusercontents.com/Misaka-blog/Misaka-WARP-Script/master/warp-cli/changeport.sh && bash changeport.sh
}

uninstall(){
    [[ -n $(type -P wgcf) ]] && wget -N https://raw.githubusercontents.com/Misaka-blog/Misaka-WARP-Script/master/wgcf-warp/uninstall.sh && bash uninstall.sh
    [[ -n $(type -P warp-cli) ]] && wget -N https://raw.githubusercontents.com/Misaka-blog/Misaka-WARP-Script/master/warp-cli/uninstall.sh && bash uninstall.sh
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
    if [[ $WARPSocks5Status == "已启动" ]]; then
        green "VPS Socks5代理：127.0.0.1:$WARPSocks5Port"
    fi
    green "Wgcf状态：$WgcfStatus"
    green "WARP-Cli状态：$WARPSocks5Status"
    red "=========================="
    echo "   "
    if [[ $WARPIPv6Status == "原生IPv6" && $WARPIPv4Status == "无法检测IPv4状态" ]]; then
        green "1. 安装Wgcf IPv6 WARP"
        green "2. 安装Wgcf 双栈 WARP"
        green "3. IPv6 Only VPS无法安装WARP-Cli代理模式"
    fi
    if [[ $WARPIPv4Status == "原生IPv4" && $WARPIPv6Status == "无法检测IPv6状态" ]]; then
        green "1. 安装Wgcf IPv4 WARP"
        green "2. 安装Wgcf 双栈 WARP"
        if [[ $arch == "amd64" || $arch == "x86_64" ]]; then
            green "3. 安装WARP-Cli代理模式"
        else
            green "3. 非AMD64 CPU架构的VPS，无法安装WARP-Cli代理模式"
        fi
    fi
    if [[ $WARPIPv4Status == "原生IPv4" && $WARPIPv6Status == "原生IPv6" ]]; then
        green "1. 检测到双栈VPS、无法使用Wgcf 单栈 WARP"
        green "2. 安装Wgcf 双栈 WARP"
        if [[ $arch == "amd64" || $arch == "x86_64" ]]; then
            green "3. 安装WARP-Cli代理模式"
        else
            green "3. 非AMD64 CPU架构的VPS，无法安装WARP-Cli代理模式"
        fi
    fi
    if [[ $WARPIPv4Status == "WARP IPv4" && $WARPIPv6Status == "WARP IPv6" ]]; then
        green "1. 已经安装Wgcf WARP、请先卸载再更改代理模式"
        green "2. 已经安装Wgcf WARP、请先卸载再更改代理模式"
        if [[ $arch == "amd64" || $arch == "x86_64" ]]; then
            green "3. 安装WARP-Cli代理模式"
        else
            green "3. 非AMD64 CPU架构的VPS，无法安装WARP-Cli代理模式"
        fi
    fi
    if [[ $WARPIPv4Status == "WARP IPv4" && $WARPIPv6Status == "原生IPv6" ]]; then
        green "1. 已经安装Wgcf WARP、请先卸载再更改代理模式"
        green "2. 已经安装Wgcf WARP、请先卸载再更改代理模式"
        green "3. IPv6 Only VPS无法安装WARP-Cli代理模式"
    fi
    if [[ $WARPIPv4Status == "原生IPv4" && $WARPIPv6Status == "WARP IPv6" ]]; then
        green "1. 已经安装Wgcf WARP、请先卸载再更改代理模式"
        green "2. 已经安装Wgcf WARP、请先卸载再更改代理模式"
        if [[ $arch == "amd64" || $arch == "x86_64" ]]; then
            green "3. 安装WARP-Cli代理模式"
        else
            green "3. 非AMD64 CPU架构的VPS，无法安装WARP-Cli代理模式"
        fi
    fi
    green "4. Wgcf-WARP 临时开关"
    green "5. WARP-Cli代理模式临时开关"
    green "6. WARP-Cli代理模式更换Socks5端口"
    green "7. 卸载WARP"
    read -p "请输入选项：" menuNumberInput
    case "$menuNumberInput" in
        1 ) install ;;
        2 ) wgcfmode=1 && install ;;
        3 ) wgcfcli=1 && install ;;
        4 ) wgcfswitch ;;
        5 ) warpcliswitch ;;
        6 ) warpcliport ;;
        7 ) uninstall ;;
        * ) exit 1 ;;
    esac
}

check_tun
menu