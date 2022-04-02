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

REGEX=("debian" "ubuntu" "centos|red hat|kernel|oracle linux|alma|rocky" "'amazon linux'")
RELEASE=("Debian" "Ubuntu" "CentOS" "CentOS")
PACKAGE_UPDATE=("apt -y update" "apt -y update" "yum -y update" "yum -y update")
PACKAGE_INSTALL=("apt -y install" "apt -y install" "yum -y install" "yum -y install")
PACKAGE_UNINSTALL=("apt -y autoremove" "apt -y autoremove" "yum -y autoremove" "yum -y autoremove")

[[ $EUID -ne 0 ]] && red "请在root用户下运行脚本" && exit 1

CMD=("$(grep -i pretty_name /etc/os-release 2>/dev/null | cut -d \" -f2)" "$(hostnamectl 2>/dev/null | grep -i system | cut -d : -f2)" "$(lsb_release -sd 2>/dev/null)" "$(grep -i description /etc/lsb-release 2>/dev/null | cut -d \" -f2)" "$(grep . /etc/redhat-release 2>/dev/null)" "$(grep . /etc/issue 2>/dev/null | cut -d \\ -f1 | sed '/^[ ]*$/d')")

for i in "${CMD[@]}"; do
    SYS="$i" && [[ -n $SYS ]] && break
done

for ((int = 0; int < ${#REGEX[@]}; int++)); do
    [[ $(echo "$SYS" | tr '[:upper:]' '[:lower:]') =~ ${REGEX[int]} ]] && SYSTEM="${RELEASE[int]}" && [[ -n $SYSTEM ]] && break
done

[[ -z $SYSTEM ]] && red "不支持当前VPS系统，请使用主流的操作系统" && exit 1

CONFIG_FILE="/usr/local/etc/xray/config.json"
BT="false"
NGINX_CONF_PATH="/etc/nginx/conf.d/"
VLESS="false"
TROJAN="false"
TLS="false"
WS="false"
XTLS="false"
KCP="false"
SITES=(
    "http://www.zhuizishu.com/"
    "http://xs.56dyc.com/"
    "http://www.ddxsku.com/"
    "http://www.biqu6.com/"
    "https://www.wenshulou.cc/"
    "http://www.55shuba.com/"
    "http://www.39shubao.com/"
    "https://www.23xsw.cc/"
    "https://www.jueshitangmen.info/"
    "https://www.zhetian.org/"
    "http://www.bequgexs.com/"
    "http://www.tjwl.com/"
)

res=`which bt 2>/dev/null`
if [[ $res != "" ]]; then
    BT="true"
    NGINX_CONF_PATH="/www/server/panel/vhost/nginx/"
fi