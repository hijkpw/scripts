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
[[ -z $(type -P wireproxy) ]] && red "WireProxy-WARP代理模式未安装，脚本即将退出！" && rm -f wireproxy-netfilx.sh && exit 1

WireProxyPort=$(grep BindAddress /root/WireProxy_WARP.conf 2>/dev/null | sed "s/BindAddress = 127.0.0.1://g")

check(){
    NetfilxStatus=$(curl -sx socks5h://localhost:$WireProxyPort -fsL --write-out %{http_code} --output /dev/null --max-time 10 "https://www.netflix.com/title/81215567" 2>&1)
    if [[ $NetfilxStatus == "200" ]]; then
        success
    fi
    if [[ $NetfilxStatus =~ "403"|"404" ]]; then
        failed  
    fi
    if [[ -z $NetfilxStatus ]] || [[ $NetfilxStatus == "000" ]]; then
        retry
    fi
}

retry(){
    systemctl stop wireproxy-warp
    systemctl start wireproxy-warp
    check
}

success(){
    WireProxyIP=$(curl -sx socks5h://localhost:$WireProxyPort https://ip.gs -k --connect-timeout 8)
    green "当前WireProxy-WARP的IP：$WireProxyIP 已解锁Netfilx"
    yellow "等待1小时后，脚本将会自动重新检查Netfilx解锁状态"
    sleep 1h
    check
}

failed(){
    WireProxyIP=$(curl -sx socks5h://localhost:$WireProxyPort https://ip.gs -k --connect-timeout 8)
    red "当前WireProxy-WARP的IP：$WireProxyIP 未解锁Netfilx，脚本将在15秒后重新测试Netfilx解锁情况"
    sleep 15
    systemctl stop wireproxy-warp
    systemctl start wireproxy-warp
    check
}

check
