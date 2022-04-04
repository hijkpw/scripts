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
[[ -z $(type -P curl) ]] && ${PACKAGE_UPDATE[int]} && ${PACKAGE_INSTALL[int]} curl

arch=$(uname -m)
wgcfcli=0 # 变量说明：0为Wgcf、1为WARP-Cli、2为WireProxy-WARP
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
    WARPSocks5Status=$(curl -sx socks5h://localhost:$WARPSocks5Port https://www.cloudflare.com/cdn-cgi/trace -k --connect-timeout 8 | grep warp | cut -d= -f2)
    WireProxyPort=$(grep BindAddress /root/WireProxy_WARP.conf 2>/dev/null | sed "s/BindAddress = 127.0.0.1://g")
    WireProxyStatus=$(curl -sx socks5h://localhost:$WireProxyPort https://www.cloudflare.com/cdn-cgi/trace -k --connect-timeout 8 | grep warp | cut -d= -f2)
    [[ $WARPIPv4Status =~ "on"|"plus" ]] && WARPIPv4Status="WARP IPv4"
    [[ $WARPIPv4Status == "off" ]] && WARPIPv4Status="原生IPv4"
    [[ $WARPIPv6Status =~ "on"|"plus" ]] && WARPIPv6Status="WARP IPv6"
    [[ $WARPIPv6Status == "off" ]] && WARPIPv6Status="原生IPv6"
    [[ -z $WARPIPv4Status ]] && WARPIPv4Status="无法检测IPv4状态"
    [[ -z $WARPIPv6Status ]] && WARPIPv6Status="无法检测IPv6状态"
    [[ -z $(type -P wg-quick) ]] && WgcfStatus="未安装"
    [[ -n $(type -P wg-quick) ]] && WgcfStatus="未启动" && [[ -n $(wg) ]] && WgcfStatus="已启动"
    [[ -z $WARPSocks5Port ]] && WARPSocks5Status="未安装"
    [[ $WARPSocks5Status == "off" ]] && WARPSocks5Status="未启动"
    [[ $WARPSocks5Status =~ "on"|"plus" ]] && WARPSocks5Status="已启动"
    [[ -z $WireProxyPort ]] && WireProxyStatus="未安装"
    [[ $WireProxyStatus == "off" ]] && WireProxyStatus="未启动"
    [[ $WireProxyStatus =~ "on"|"plus" ]] && WireProxyStatus="已启动"
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
        if [[ $WARPIPv4Status == "原生IPv4" && $WARPIPv6Status == "WARP IPv6" ]]; then
            wget -N https://raw.githubusercontents.com/Misaka-blog/Misaka-WARP-Script/master/warp-cli/warp-cli.sh && bash warp-cli.sh
        fi
    fi
    if [[ $wgcfcli == 2 ]]; then
        if [[ $WARPIPv4Status == "无法检测IPv4状态" && $WARPIPv6Status == "原生IPv6" || $WARPIPv4Status == "WARP IPv4" && $WARPIPv6Status == "原生IPv6" ]]; then
            wget -N https://raw.githubusercontents.com/Misaka-blog/Misaka-WARP-Script/master/wireproxy-warp/warp6.sh && bash warp6.sh
        else
            wget -N https://raw.githubusercontents.com/Misaka-blog/Misaka-WARP-Script/master/wireproxy-warp/warp4.sh && bash warp4.sh
        fi
    fi
}

wgcfswitch(){
    wget -N https://raw.githubusercontents.com/Misaka-blog/Misaka-WARP-Script/master/wgcf-warp/switchwarp.sh && bash switchwarp.sh
}

warpcliswitch(){
    wget -N https://raw.githubusercontents.com/Misaka-blog/Misaka-WARP-Script/master/warp-cli/switch.sh && bash switch.sh
}

changeport(){
    yellow "请选择需要更换端口的WARP客户端："
    green "1. WARP-Cli 代理模式"
    green "2. WireProxy-WARP 代理模式"
    read -p "请输入需要卸载的客户端 [1-2]：" changePortClient
    case "$changePortClient" in
        1 ) wget -N https://raw.githubusercontents.com/Misaka-blog/Misaka-WARP-Script/master/warp-cli/changeport.sh && bash changeport.sh ;;
        2 ) wget -N https://raw.githubusercontents.com/Misaka-blog/Misaka-WARP-Script/master/wireproxy-warp/changeport.sh && bash changeport.sh ;;
    esac
}

warpNetFilx(){
    yellow "请选择需要刷NetFilx IP的WARP客户端："
    green "1. Wgcf-WARP IPv4模式"
    green "2. Wgcf-WARP IPv6模式"
    green "3. WARP-Cli 代理模式"
    green "4. WireProxy-WARP 代理模式"
    read -p "请输入需要卸载的客户端 [1-3]：" uninstallClient
    case "$uninstallClient" in
        1 ) wget -N https://raw.githubusercontents.com/Misaka-blog/Misaka-WARP-Script/master/wgcf-warp/netfilx4.sh && bash netfilx4.sh ;;
        2 ) wget -N https://raw.githubusercontents.com/Misaka-blog/Misaka-WARP-Script/master/wgcf-warp/netfilx6.sh && bash netfilx6.sh ;;
        3 ) wget -N https://raw.githubusercontents.com/Misaka-blog/Misaka-WARP-Script/master/warp-cli/netfilxcli.sh && bash netfilxcli.sh ;;
        4 ) wget -N https://raw.githubusercontents.com/Misaka-blog/Misaka-WARP-Script/master/wireproxy-warp/netfilx-wireproxy.sh && bash netfilx-wireproxy.sh ;;
    esac
}

uninstall(){
    yellow "请选择需要卸载的WARP客户端："
    green "1. Wgcf-WARP"
    green "2. WARP-Cli 代理模式"
    green "3. WireProxy-WARP 代理模式"
    read -p "请输入需要卸载的客户端 [1-3]：" uninstallClient
    case "$uninstallClient" in
        1 ) wget -N https://raw.githubusercontents.com/Misaka-blog/Misaka-WARP-Script/master/wgcf-warp/uninstall.sh && bash uninstall.sh ;;
        2 ) wget -N https://raw.githubusercontents.com/Misaka-blog/Misaka-WARP-Script/master/warp-cli/uninstall.sh && bash uninstall.sh ;;
        3 ) wget -N https://raw.githubusercontents.com/Misaka-blog/Misaka-WARP-Script/master/wireproxy-warp/uninstall.sh && bash uninstall.sh ;;
    esac
}

# 菜单
menu(){
    clear
    get_status
    red "==============================="
    red "      Misaka WARP Script       "
    red " Site: https://owo.misaka.rest "
    echo "                          "
    yellow "VPS IPv4状态：$WARPIPv4Status"
    yellow "VPS IPv6状态：$WARPIPv6Status"
    if [[ $WARPSocks5Status == "已启动" ]]; then
        yellow "WARP-Cli Socks5代理：127.0.0.1:$WARPSocks5Port"
    fi
    if [[ $WireProxyStatus == "已启动" ]]; then
        yellow "WireProxy Socks5代理：127.0.0.1:$WireProxyPort"
    fi
    yellow "Wgcf状态：$WgcfStatus"
    yellow "WARP-Cli状态：$WARPSocks5Status"
    yellow "WireProxy-WARP状态：$WireProxyStatus"
    red "================================"
    echo "   "
    if [[ $WARPIPv6Status == "原生IPv6" && $WARPIPv4Status == "无法检测IPv4状态" ]]; then
        green "1. 安装Wgcf IPv4 WARP"
        green "2. 安装Wgcf 双栈 WARP"
        green "3. IPv6 Only VPS无法安装WARP-Cli代理模式"
        if [[ $WireProxyStatus == "未启动" || $WireProxyStatus == "已启动" ]]; then
            green "4. 已安装WireProxy-WARP代理模式"
        else
            green "4. 安装WireProxy-WARP代理模式"
        fi
    fi
    if [[ $WARPIPv4Status == "原生IPv4" && $WARPIPv6Status == "无法检测IPv6状态" ]]; then
        green "1. 安装Wgcf IPv6 WARP"
        green "2. 安装Wgcf 双栈 WARP"
        if [[ $arch == "amd64" || $arch == "x86_64" ]]; then
            if [[ $WARPSocks5Status == "未启动" || $WARPSocks5Status == "已启动" ]]; then
                green "3. 已安装WARP-Cli代理模式"
            else
                green "3. 安装WARP-Cli代理模式"
            fi
        else
            green "3. 非AMD64 CPU架构的VPS，无法安装WARP-Cli代理模式"
        fi
        if [[ $WireProxyStatus == "未启动" || $WireProxyStatus == "已启动" ]]; then
            green "4. 已安装WireProxy-WARP代理模式"
        else
            green "4. 安装WireProxy-WARP代理模式"
        fi
    fi
    if [[ $WARPIPv4Status == "原生IPv4" && $WARPIPv6Status == "原生IPv6" ]]; then
        green "1. 检测到双栈VPS、无法使用Wgcf 单栈 WARP"
        green "2. 安装Wgcf 双栈 WARP"
        if [[ $arch == "amd64" || $arch == "x86_64" ]]; then
            if [[ $WARPSocks5Status == "未启动" || $WARPSocks5Status == "已启动" ]]; then
                green "3. 已安装WARP-Cli代理模式"
            else
                green "3. 安装WARP-Cli代理模式"
            fi
        else
            green "3. 非AMD64 CPU架构的VPS，无法安装WARP-Cli代理模式"
        fi
        if [[ $WireProxyStatus == "未启动" || $WireProxyStatus == "已启动" ]]; then
            green "4. 已安装WireProxy-WARP代理模式"
        else
            green "4. 安装WireProxy-WARP代理模式"
        fi
    fi
    if [[ $WARPIPv4Status == "WARP IPv4" && $WARPIPv6Status == "WARP IPv6" ]]; then
        green "1. 已经安装Wgcf WARP、请先卸载再更改代理模式"
        green "2. 已经安装Wgcf WARP、请先卸载再更改代理模式"
        green "3. 由于启动了双栈Wgcf-WARP模式，脚本无法判断是否允许安装WARP-Cli代理模式"
        if [[ $WireProxyStatus == "未启动" || $WireProxyStatus == "已启动" ]]; then
            green "4. 已安装WireProxy-WARP代理模式"
        else
            green "4. 安装WireProxy-WARP代理模式"
        fi
    fi
    if [[ $WARPIPv4Status == "WARP IPv4" && $WARPIPv6Status == "原生IPv6" ]]; then
        green "1. 已经安装Wgcf WARP、请先卸载再更改代理模式"
        green "2. 已经安装Wgcf WARP、请先卸载再更改代理模式"
        green "3. IPv6 Only VPS无法安装WARP-Cli代理模式"
        if [[ $WireProxyStatus == "未启动" || $WireProxyStatus == "已启动" ]]; then
            green "4. 已安装WireProxy-WARP代理模式"
        else
            green "4. 安装WireProxy-WARP代理模式"
        fi
    fi
    if [[ $WARPIPv4Status == "原生IPv4" && $WARPIPv6Status == "WARP IPv6" ]]; then
        green "1. 已经安装Wgcf WARP、请先卸载再更改代理模式"
        green "2. 已经安装Wgcf WARP、请先卸载再更改代理模式"
        if [[ $arch == "amd64" || $arch == "x86_64" ]]; then
            if [[ $WARPSocks5Status == "未启动" || $WARPSocks5Status == "已启动" ]]; then
                green "3. 已安装WARP-Cli代理模式"
            else
                green "3. 安装WARP-Cli代理模式"
            fi
        else
            green "3. 非AMD64 CPU架构的VPS，无法安装WARP-Cli代理模式"
        fi
        if [[ $WireProxyStatus == "未启动" || $WireProxyStatus == "已启动" ]]; then
            green "4. 已安装WireProxy-WARP代理模式"
        else
            green "4. 安装WireProxy-WARP代理模式"
        fi
    fi
    green "5. Wgcf-WARP 临时开关"
    green "6. WARP-Cli代理模式临时开关"
    green "7. WARP代理模式更改Socks5端口"
    green "8. WARP刷NetFilx IP"
    green "9. 卸载WARP"
    green "0. 退出菜单"
    read -p "请输入选项 [0-9]：" menuNumberInput
    case "$menuNumberInput" in
        1 ) install ;;
        2 ) wgcfmode=1 && install ;;
        3 ) wgcfcli=1 && install ;;
        4 ) wgcfcli=2 && install ;;
        5 ) wgcfswitch ;;
        6 ) warpcliswitch ;;
        7 ) changeport ;;
        8 ) wireproxychangeport ;;
        9 ) uninstall ;;
        * ) exit 1 ;;
    esac
}

check_tun
menu