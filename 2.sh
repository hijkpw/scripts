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
[[ $EUID -ne 0 ]] && red "请在root用户下运行脚本" && exit 1

# 检测系统，本部分代码感谢fscarmen的指导
CMD=("$(grep -i pretty_name /etc/os-release 2>/dev/null | cut -d \" -f2)" "$(hostnamectl 2>/dev/null | grep -i system | cut -d : -f2)" "$(lsb_release -sd 2>/dev/null)" "$(grep -i description /etc/lsb-release 2>/dev/null | cut -d \" -f2)" "$(grep . /etc/redhat-release 2>/dev/null)" "$(grep . /etc/issue 2>/dev/null | cut -d \\ -f1 | sed '/^[ ]*$/d')")

for i in "${CMD[@]}"; do
    SYS="$i" && [[ -n $SYS ]] && break
done

for ((int = 0; int < ${#REGEX[@]}; int++)); do
    [[ $(echo "$SYS" | tr '[:upper:]' '[:lower:]') =~ ${REGEX[int]} ]] && SYSTEM="${RELEASE[int]}" && [[ -n $SYSTEM ]] && break
done

[[ -z $SYSTEM ]] && red "不支持当前VPS系统，请使用主流的操作系统" && exit 1

WgcfWarpCli=0 # 0为安装Wgcf、1为安装WARP Cli
WgcfMode=0 # 0为Wgcf单栈模式、1为Wgcf双栈模式

VIRT=$(systemd-detect-virt) # 判断VPS虚拟化架构
KernelVER1=$(uname  -r | awk -F . '{print $1 }') && KernelVER2=$(uname -r | awk -F . '{print $2}') # 判断VPS内核版本

# 修改相对应模式下的Wgcf配置文件内容
ud4='sed -i "5 s/^/PostUp = ip -4 rule add from $(ip route get 162.159.192.1 | grep -oP '"'src \K\S+') lookup main\n/"'" wgcf-profile.conf && sed -i "6 s/^/PostDown = ip -4 rule delete from $(ip route get 162.159.192.1 | grep -oP '"'src \K\S+') lookup main\n/"'" wgcf-profile.conf'
ud6='sed -i "7 s/^/PostUp = ip -6 rule add from $(ip route get 2606:4700:d0::a29f:c001 | grep -oP '"'src \K\S+') lookup main\n/"'" wgcf-profile.conf && sed -i "8 s/^/PostDown = ip -6 rule delete from $(ip route get 2606:4700:d0::a29f:c001 | grep -oP '"'src \K\S+') lookup main\n/"'" wgcf-profile.conf'
ud4ud6='sed -i "5 s/^/PostUp = ip -4 rule add from $(ip route get 162.159.192.1 | grep -oP '"'src \K\S+') lookup main\n/"'" wgcf-profile.conf && sed -i "6 s/^/PostDown = ip -4 rule delete from $(ip route get 162.159.192.1 | grep -oP '"'src \K\S+') lookup main\n/"'" wgcf-profile.conf && sed -i "7 s/^/PostUp = ip -6 rule add from $(ip route get 2606:4700:d0::a29f:c001 | grep -oP '"'src \K\S+') lookup main\n/"'" wgcf-profile.conf && sed -i "8 s/^/PostDown = ip -6 rule delete from $(ip route get 2606:4700:d0::a29f:c001 | grep -oP '"'src \K\S+') lookup main\n/"'" wgcf-profile.conf'
c1="sed -i '/0\.0\.0\.0\/0/d' wgcf-profile.conf"
c2="sed -i '/\:\:\/0/d' wgcf-profile.conf"
c3="sed -i 's/engage.cloudflareclient.com/162.159.193.10/g' wgcf-profile.conf"
c4="sed -i 's/engage.cloudflareclient.com/2606:4700:d0::a29f:c001/g' wgcf-profile.conf"
c5="sed -i 's/1.1.1.1/8.8.8.8,2001:4860:4860::8888/g' wgcf-profile.conf"
c6="sed -i 's/1.1.1.1/2001:4860:4860::8888,8.8.8.8/g' wgcf-profile.conf"

# 确定CPU架构
arch_affix() {
    case "$(uname -m)" in
        x86_64 | amd64) cpuArch='amd64' ;;
        armv8 | arm64 | aarch64) cpuArch='aarch64' ;;
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
    [[ $WARPIPv4Status == "on" ]] && WARPIPv4Status="WARP IPv4"
    [[ $WARPIPv4Status == "off" ]] && WARPIPv4Status="原生IPv4"
    [[ $WARPIPv6Status == "on" ]] && WARPIPv6Status="WARP IPv6"
    [[ $WARPIPv6Status == "off" ]] && WARPIPv6Status="原生IPv6"
    [[ -z $WARPIPv4Status ]] && WARPIPv4Status="无法检测IPv4状态"
    [[ -z $WARPIPv6Status ]] && WARPIPv6Status="无法检测IPv6状态"
    [[ ! -f /usr/local/bin/wgcf ]] && WgcfStatus="未安装"
    [[ -f /usr/local/bin/wgcf ]] && WgcfStatus="未启动" && [[ -n $(wg) ]] && WgcfStatus="已启动"
}

# 安装Wgcf组件——WireGuard
install_wireguard(){
    ${PACKAGE_UPDATE[int]} && ${PACKAGE_INSTALL[int]} curl wget sudo grep
    if [[ $RELEASE == "CentOS" ]]; then
        ${PACKAGE_INSTALL[int]} epel-release
        ${PACKAGE_INSTALL[int]} wireguard-tools net-tools iptables
        if [ "$KernelVER1" -lt 5 ]|| [ "$KernelVER2" -lt 6 ]; then
            if [[ ${VIRT} == "kvm" || ${VIRT} == "xen" || ${VIRT} == "microsoft" ]]; then
                vsid=`grep -i version_id /etc/os-release | cut -d \" -f2 | cut -d . -f1`
                curl -Lo /etc/yum.repos.d/wireguard.repo https://copr.fedorainfracloud.org/coprs/jdoss/wireguard/repo/epel-$vsid/jdoss-wireguard-epel-$vsid.repo
                yum -y install epel-release wireguard-dkms
            fi
        fi
    fi
    if [[ $RELEASE == "Debian" ]]; then
        ${PACKAGE_UPDATE[int]}
        ${PACKAGE_INSTALL[int]} lsb-release
        echo "deb http://deb.debian.org/debian $(lsb_release -sc)-backports main" > /etc/apt/sources.list.d/backports.list
        ${PACKAGE_UPDATE[int]}
        ${PACKAGE_INSTALL[int]} --no-install-recommends net-tools iproute2 openresolv dnsutils wireguard-tools iptables
        if [ "$KernelVER1" -lt 5 ]|| [ "$KernelVER2" -lt 6 ]; then
            if [[ ${VIRT} == "kvm" || ${VIRT} == "xen" || ${VIRT} == "microsoft" ]]; then
                ${PACKAGE_INSTALL[int]} --no-install-recommends linux-headers-$(uname -r)
                ${PACKAGE_INSTALL[int]} --no-install-recommends install wireguard-dkms
            fi
        fi
    fi
    if [[ $RELEASE == "Ubuntu" ]]; then
        ${PACKAGE_UPDATE[int]}
        ${PACKAGE_INSTALL[int]} --no-install-recommends net-tools iproute2 openresolv dnsutils wireguard-tools iptables
    fi
    if [[ $VIRT =~ lxc|openvz ]]; then
        [[ -e /usr/bin/wireguard-go ]] || wget -N https://raw.githubusercontents.com/Misaka-blog/Misaka-WARP/master/wireguard-go -O /usr/bin/wireguard-go && chmod +x /usr/bin/wireguard-go
    fi
}

# 下载并安装Wgcf
wgcf_install(){
    wget -N https://raw.githubusercontents.com/Misaka-blog/Misaka-WARP/master/wgcf_2.2.12_linux_$cpuArch -O /usr/local/bin/wgcf
    chmod +x /usr/local/bin/wgcf
}

# 注册WARP账号
wgcf_register(){
    while [[ ! -f wgcf-account.toml ]]; do
        yes | wgcf register
        sleep 5
    done
}

# 生成WireGuard配置文件
wgcf_generate(){
    yellow "使用WARP免费版账户请按回车跳过 \n如需启用WARP+账户，请复制WARP+的许可证秘钥(26个字符)后回车"
    read -p "WARP+许可证秘钥(26个字符):" WarpPlusID
    if [[ -n $WarpPlusID ]]; then
        sed -i "s/license_key.*/license_key = \"$WarpPlusID\"/g" wgcf-account.toml
        wgcf update
        green "正在启用WARP+账户中，如提示：400 Bad Request，则使用WARP免费账户" 
    fi
    while [[ ! -f wgcf-profile.conf ]]; do
        wgcf generate
    done
    MTUy=1500
    MTUc=10
    if [[ $WARPIPv4Status == "原生IPv6" && $WARPIPv4Status == "无法检测IPv4状态" ]]; then
        ping='ping6'
        IP1='2606:4700:4700::1111'
        IP2='2001:4860:4860::8888'
    else
        ping='ping'
        IP1='1.1.1.1'
        IP2='8.8.8.8'
    fi
    while true; do
        if ${ping} -c1 -W1 -s$((${MTUy} - 28)) -Mdo ${IP1} >/dev/null 2>&1 || ${ping} -c1 -W1 -s$((${MTUy} - 28)) -Mdo ${IP2} >/dev/null 2>&1; then
            MTUc=1
            MTUy=$((${MTUy} + ${MTUc}))
        else
            MTUy=$((${MTUy} - ${MTUc}))
            [[ ${MTUc} == 1 ]] && break
        fi
	[[ ${MTUy} -le 1360 ]] && MTUy='1360' && break
    done
    MTU=$((${MTUy} - 80))
    green "MTU最佳网络吞吐量值= $MTU 已设置完毕"
    sed -i "s/MTU.*/MTU = $MTU/g" wgcf-profile.conf
    if [[ $WgcfMode == 0 ]]; then
        if [[ $WARPIPv4Status == "原生IPv6" && $WARPIPv4Status == "无法检测IPv4状态" ]]; then
            echo ${c4} | sh
            echo ${c2} | sh
            echo ${c6} | sh
        fi
        if [[ $WARPIPv4Status == "原生IPv4" && $WARPIPv6Status == "无法检测IPv6状态" ]]; then
            echo ${c1} | sh
            echo ${c3} | sh
            echo ${c5} | sh
        fi
    fi
    if [[ $WgcfMode == 1 ]]; then
        if [[ $WARPIPv4Status == "原生IPv6" && $WARPIPv4Status == "无法检测IPv4状态" ]]; then
            echo ${ud6} | sh
            echo ${c4} | sh
            echo ${c5} | sh
        fi
        if [[ $WARPIPv4Status == "原生IPv4" && $WARPIPv6Status == "无法检测IPv6状态" ]]; then
            echo ${ud4} | sh
            echo ${c3} | sh
            echo ${c5} | sh
        fi
        if [[ $WARPIPv4Status == "原生IPv4" && $WARPIPv6Status == "原生IPv6" ]]; then
            echo ${ud4ud6} | sh
            echo ${c5} | sh
        fi
    fi
}

# 移动Wgcf配置文件到WireGuard文件夹
mv_wgcf_to_wireguard(){
    mkdir -p /etc/wireguard/
    mv -f wgcf-profile.conf /etc/wireguard/wgcf.conf
    mv -f wgcf-account.toml /etc/wireguard/wgcf-account.toml
}

# 启动Wgcf-WARP
start_wgcf_warp(){
    systemctl enable wg-quick@wgcf
    wg-quick down wgcf
    systemctl start wg-quick@wgcf
    checkstatus
}

# Wgcf-WARP临时开关
onoff_wgcf_warp(){
    if [ $WgcfStatus == "已启动" ]; then
        wg-quick down wgcf
        green "关闭WARP成功"
    fi
    if [ $WgcfStatus == "未启动" ]; then
        systemctl restart wg-quick@wgcf
        green "恢复WARP成功"
    fi
}

# 安装过程
install(){
    [[ $WARPIPv4Status == "WARP IPv4" ]] && exit 1
    [[ $WARPIPv6Status == "WARP IPv6" ]] && exit 1
    if [ $WgcfWarpCli == 0 ]; then
        install_wireguard
        wgcf_install
        wgcf_register
        wgcf_generate
        mv_wgcf_to_wireguard
        start_wgcf_warp
    fi
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
    if [[ $WARPIPv4Status == "无法检测IPv4状态" ]]; then
        green "1. 安装Wgcf IPv4 WARP"
        green "2. 安装Wgcf 双栈 WARP"
    fi
    if [[ $WARPIPv6Status == "无法检测IPv6状态" ]]; then
        green "1. 安装Wgcf IPv6 WARP"
        green "2. 安装Wgcf 双栈 WARP"
    fi
    if [[ $WARPIPv4Status == "原生IPv4" && $WARPIPv6Status == "原生IPv6" ]]; then
        green "1. 检测到双栈VPS、无法使用单栈WARP"
        green "2. 安装Wgcf 双栈 WARP"
    fi
    read -p "请输入选项：" menuNumberInput
    case "$menuNumberInput" in
        1 ) install ;;
        2 ) WgcfMode=1 && install ;;
        * ) exit 1 ;;
    esac
}

check_tun
arch_affix
menu
