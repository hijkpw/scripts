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

arch=`uname -m`
vsid=`grep -i version_id /etc/os-release | cut -d \" -f2 | cut -d . -f1`

check_tun(){
    TUN=$(cat /dev/net/tun 2>&1 | tr '[:upper:]' '[:lower:]')
    [[ ! $TUN =~ 'in bad state' ]] && [[ ! $TUN =~ '处于错误状态' ]] && [[ ! $TUN =~ 'Die Dateizugriffsnummer ist in schlechter Verfassung' ]] && red "检测到未开启TUN模块，请到VPS控制面板处开启" && exit 1
}

install_warpcli_centos(){
    ${PACKAGE_INSTALL[int]} epel-release
    ${PACKAGE_INSTALL[int]} net-tools
    rpm -ivh http://pkg.cloudflareclient.com/cloudflare-release-el$vsid.rpm
    ${PACKAGE_INSTALL[int]} cloudflare-warp
}

install_warpcli_debian(){
    ${PACKAGE_INSTALL[int]} lsb-release
    [[ -z $(type -P gpg 2>/dev/null) ]] && ${PACKAGE_INSTALL[int]} gnupg
    [[ -z $(apt list 2>/dev/null | grep apt-transport-https | grep installed) ]] && ${PACKAGE_INSTALL[int]} apt-transport-https
    curl https://pkg.cloudflareclient.com/pubkey.gpg | apt-key add -
    echo "deb http://pkg.cloudflareclient.com/ $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/cloudflare-client.list
    ${PACKAGE_UPDATE[int]}
    ${PACKAGE_INSTALL[int]} cloudflare-warp
}

install_warpcli_ubuntu(){
    ${PACKAGE_INSTALL[int]} lsb-release
    curl https://pkg.cloudflareclient.com/pubkey.gpg | apt-key add -
    echo "deb http://pkg.cloudflareclient.com/ $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/cloudflare-client.list
    ${PACKAGE_UPDATE[int]}
    ${PACKAGE_INSTALL[int]} cloudflare-warp
}

register_warpcli(){
    warp-cli --accept-tos register >/dev/null 2>&1
    yellow "使用WARP免费版账户请按回车跳过 \n启用WARP+账户，请复制WARP+的许可证密钥(26个字符)后回车"
    read -p "按键许可证密钥(26个字符):" WPPlusKey
    if [[ -n $WPPlusKey ]]; then
        warp-cli --accept-tos set-license "$LICENSE" >/dev/null 2>&1 && sleep 1
        if [[ $(warp-cli --accept-tos account) =~ Limited ]]; then
            green "WARP+账户启用成功"
        else
            red "WARP+账户启用失败，即将使用WARP免费版账户"
        fi
    fi
    warp-cli --accept-tos set-mode proxy >/dev/null 2>&1
}

set_proxy_port(){
    read -p "请输入WARP Cli使用的代理端口（默认40000）：" WARPCliPort
    [[ -z $WARPCliPort ]] && WARPCliPort=40000
    warp-cli --accept-tos set-proxy-port "$WARPCliPort" >/dev/null 2>&1
}

start_warpcli(){
    yellow "正在启动Warp-Cli代理模式"
    warp-cli --accept-tos connect >/dev/null 2>&1
    socks5Status=$(curl -sx socks5h://localhost:$WARPCliPort https://www.cloudflare.com/cdn-cgi/trace -k --connect-timeout 2 | grep warp | cut -d= -f2)
    until [[ $socks5Status =~ on|plus ]]; do
        red "启动Warp-Cli代理模式失败，正在尝试重启"
        warp-cli --accept-tos disconnect >/dev/null 2>&1
        warp-cli --accept-tos connect >/dev/null 2>&1
        socks5Status=$(curl -sx socks5h://localhost:$WARPCliPort https://www.cloudflare.com/cdn-cgi/trace -k --connect-timeout 2 | grep warp | cut -d= -f2)
        sleep 5
    done
    warp-cli --accept-tos enable-always-on >/dev/null 2>&1
    green "WARP-Cli代理模式已启动成功！"
    yellow "本地Socks5代理为：localhost:$WARPCliPort"
    rm -f warp-cli.sh
}

install(){
    [[ -z $(curl -s4m8 ip.gs ) ]] && red "WARP-Cli代理模式不支持IPv6 Only的VPS，脚本退出" && exit 1
    if [[ $arch == "amd64" || $arch == "x86_64" ]]; then
        [[ $SYSTEM == "CentOS" ]] && [[ ! ${vsid} =~ 8 ]] && yellow "当前系统版本：Centos $vsid \nWARP-Cli代理模式仅支持Centos 8系统"
        [[ $SYSTEM == "Debian" ]] && [[ ! ${vsid} =~ 9|10|11 ]] && yellow "当前系统版本：Debian $vsid \nWARP-Cli代理模式仅支持Debian 9-11系统"
        [[ $SYSTEM == "Ubuntu" ]] && [[ ! ${vsid} =~ 16|20 ]] && yellow "当前系统版本：Ubuntu $vsid \nWARP-Cli代理模式仅支持Ubuntu 16.04/20.04系统"
        [[ $(warp-cli --accept-tos status 2>/dev/null) =~ 'Connected' ]] && red "WARP-Cli代理模式正在运行中"
        ${PACKAGE_UPDATE[int]}
        [[ -z $(type -P curl) ]] && ${PACKAGE_INSTALL[int]} curl
        [[ -z $(type -P sudo) ]] && ${PACKAGE_INSTALL[int]} sudo
        [[ $SYSTEM == "CentOS" ]] && install_warpcli_centos
        [[ $SYSTEM == "Debian" ]] && install_warpcli_debian
        [[ $SYSTEM == "Ubuntu" ]] && install_warpcli_ubuntu
        register_warpcli
        set_proxy_port
        start_warpcli
    else
        red "不支持的CPU架构！脚本即将退出"
    fi
}

check_tun
install