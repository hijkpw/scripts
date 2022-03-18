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

install(){
    if [[ $arch == "amd64" || $arch == "x86_64" ]]; then
        [[ $SYSTEM == "CentOS" ]] && [[ ! ${vsid} =~ 8 ]] && yellow "当前系统版本号：Centos $vsid \nWARP-Cli代理模式仅支持Centos 8系统"
        [[ $SYSTEM == "Debian" ]] && [[ ! ${vsid} =~ 9|10|11 ]] && yellow "当前系统版本号：Debian $vsid \nWARP-Cli代理模式仅支持Debian 9-11系统"
        [[ $SYSTEM == "Ubuntu" ]] && [[ ! ${vsid} =~ 16|20 ]] && yellow "当前系统版本号：Ubuntu $vsid \nWARP-Cli代理模式仅支持Ubuntu 16.04/20.04系统"
    else
        red "不支持的CPU架构！脚本即将退出"
    fi
}

install