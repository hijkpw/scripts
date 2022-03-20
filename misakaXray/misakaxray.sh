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

checkip(){
    IP=$(curl -s4m8 ip.gs)
    WARPIPv4Status=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    if [[ -z $IP ]]; then
        yellow "检测到VPS是IPv6 Only的VPS，是否安装WARP？\n输入1安装WARP，输入2设置DNS64服务器"
        read -p "请输入选项：" warpdns64
        [[ $warpdns64 == 1 ]] && wget -N https://raw.githubusercontents.com/Misaka-blog/Misaka-WARP-Script/master/wgcf-warp/warp64.sh && bash warp64.sh
        [[ $warpdns64 == 2 ]] && echo -e "nameserver 2001:67c:2b0::4\nnameserver 2001:67c:2b0::6" >/etc/resolv.conf
        IP=$(curl -s6m8 ip.sb)
    fi    
    if [[ $WARPIPv4Status == "on" ]]; then
        IP=$(curl -s6m8 ip.sb)
    fi
}