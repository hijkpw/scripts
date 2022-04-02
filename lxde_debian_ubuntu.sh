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

[[ -z $SYSTEM || $SYSTEM == "CentOS" ]] && red "不支持当前VPS系统，请使用Debian / Ubuntu操作系统" && exit 1

install_lxde_vnc(){
    ${PACKAGE_UPDATE[int]}
    ${PACKAGE_INSTALL[int]} lxde tightvncserver
    wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
    chmod +x google-chrome-stable_current_amd64.deb
    ${PACKAGE_INSTALL[int]} ./google-chrome-stable_current_amd64.deb
}

set_vnc_pwd(){
    yellow "请根据下方提示，设置VNC Server的用户名密码"
    USER=root vncserver :1
}

show_vnc_address(){
    IP=$(curl -s4m8 https://ip.gs)
    [[ -z $IP ]] && IP=$(curl -s6m8 https://ip.gs)
    green "LXDE桌面安装成功！"
    yellow "VNC Viewer连接端口为："
    yellow "$IP:5901"
    exit 1
}

install_lxde_vnc
set_vnc_pwd
show_vnc_address