#!/bin/bash

# 控制台字体
red(){
    echo -e "\033[31m\033[01m$1\033[0m";
}

green(){
    echo -e "\033[32m\033[01m$1\033[0m";
}

yellow(){
    echo -e "\033[33m\033[01m$1\033[0m";
}

REGEX=("debian" "ubuntu" "centos|red hat|kernel|oracle linux|alma|rocky" "'amazon linux'" "alpine")
RELEASE=("Debian" "Ubuntu" "CentOS" "CentOS" "Alpine")
PACKAGE_UPDATE=("apt -y update" "apt -y update" "yum -y update" "yum -y update" "apk update -f")
PACKAGE_INSTALL=("apt -y install" "apt -y install" "yum -y install" "yum -y install" "apk add -f")

[[ $EUID -ne 0 ]] && yellow "请在root用户下运行脚本" && exit 1

CMD=("$(grep -i pretty_name /etc/os-release 2>/dev/null | cut -d \" -f2)" "$(hostnamectl 2>/dev/null | grep -i system | cut -d : -f2)" "$(lsb_release -sd 2>/dev/null)" "$(grep -i description /etc/lsb-release 2>/dev/null | cut -d \" -f2)" "$(grep . /etc/redhat-release 2>/dev/null)" "$(grep . /etc/issue 2>/dev/null | cut -d \\ -f1 | sed '/^[ ]*$/d')")

for i in "${CMD[@]}"; do
	SYS="$i" && [[ -n $SYS ]] && break
done

for ((int = 0; int < ${#REGEX[@]}; int++)); do
	[[ $(echo "$SYS" | tr '[:upper:]' '[:lower:]') =~ ${REGEX[int]} ]] && SYSTEM="${RELEASE[int]}" && [[ -n $SYSTEM ]] && break
done

[[ -z $SYSTEM ]] && red "不支持VPS的当前系统，请使用主流操作系统" && exit 1

cpuArch=`uname -m`

archAffix() {
	case "$cpuArch" in
		i686 | i386) cpuArch='386' ;;
		x86_64 | amd64) cpuArch='amd64' ;;
		armv5tel | arm6l | armv7 | armv7l ) cpuArch='arm' ;;
		armv8 | aarch64) cpuArch='arm64' ;;
		*) red "不支持的CPU架构！" && exit 1;;
	esac
}

back2menu(){
    green "所选操作执行完成"
    read -p "请输入“y”退出，或按任意键回到主菜单：" back2menuInput
    case "$back2menuInput" in
        y ) exit 1 ;;
        * ) menu ;;
    esac
}

download_ngrok(){
    wget https://bin.equinox.io/c/4VmDzA7iaHb/ngrok-stable-linux-$cpuArch.tgz
    tar -xzvf ~/ngrok-stable-linux-$cpuArch.tgz
    back2menu
}

ngrok_authtoken(){
    read -p "请输入Ngrok官方网站的Authtoken：" authtoken
    ~/ngrok authtoken $authtoken
    back2menu
}

select_region(){
    echo "(us) 美国"
    echo "(eu) 德国"
    echo "(ap) 新加坡"
    echo "(au) 澳大利亚悉尼"
    echo "(sa) 南美洲"
    echo "(jp) 日本东京"
    echo "(in) 印度孟买"
}

menu() {
	clear
	red "=================================="
	echo "                           "
	red "      Ngrok 内网穿透一键脚本       "
	red "          by 小御坂的破站           "
	echo "                           "
	red "  Site: https://owo.misaka.rest  "
	echo "                           "
	red "=================================="
	echo "                           "
	green "1. 下载Ngrok程序包"
	green "2. 授权Ngrok账号"
	green "3. 启用隧道"
	green "4. 卸载Ngrok程序包"
	green "5. 更新脚本"
	green "0. 退出"
	echo "         "
	read -p "请输入数字:" NumberInput
	case "$NumberInput" in
		1) download_ngrok ;;
		2) ngrok_authtoken ;;
		3) acmerenew ;;
		4) uninstall ;;
		5) upgrade ;;
		*) exit 1 ;;
	esac
}

archAffix
menu
