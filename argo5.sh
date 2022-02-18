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

# 判断系统及定义系统安装依赖方式
REGEX=("debian" "ubuntu" "centos|red hat|kernel|oracle linux|alma|rocky" "'amazon linux'")
RELEASE=("Debian" "Ubuntu" "CentOS" "CentOS" "Alpine")
PACKAGE_UPDATE=("apt -y update" "apt -y update" "yum -y update" "yum -y update")
PACKAGE_REMOVE=("apt -y remove" "apt -y remove" "yum -y remove" "yum -y remove")

# 判断系统CPU架构
cpuArch=`uname -m`
cloudflaredStatus="未安装"
loginStatus="未登录"

# 判断是否为root用户
[[ $EUID -ne 0 ]] && yellow "请在root用户下运行脚本" && exit 1

# 检测系统，本部分代码感谢fscarmen的指导
CMD=("$(grep -i pretty_name /etc/os-release 2>/dev/null | cut -d \" -f2)" "$(hostnamectl 2>/dev/null | grep -i system | cut -d : -f2)" "$(lsb_release -sd 2>/dev/null)" "$(grep -i description /etc/lsb-release 2>/dev/null | cut -d \" -f2)" "$(grep . /etc/redhat-release 2>/dev/null)" "$(grep . /etc/issue 2>/dev/null | cut -d \\ -f1 | sed '/^[ ]*$/d')")

for i in "${CMD[@]}"; do
    SYS="$i" && [[ -n $SYS ]] && break
done

for ((int=0; int<${#REGEX[@]}; int++)); do
    [[ $(echo "$SYS" | tr '[:upper:]' '[:lower:]') =~ ${REGEX[int]} ]] && SYSTEM="${RELEASE[int]}" && [[ -n $SYSTEM ]] && break
done

[[ -z $SYSTEM ]] && red "不支持VPS的当前系统，请使用主流的操作系统" && exit 1

## 统计脚本运行次数
COUNT=$(curl -sm1 "https://hits.seeyoufarm.com/api/count/incr/badge.svg?url=https%3A%2F%2Fcdn.jsdelivr.net%2Fgh%2FMisaka-blog%2Fargo-tunnel-script%40master%2Fargo.sh&count_bg=%2379C83D&title_bg=%23555555&icon=&icon_color=%23E7E7E7&title=hits&edge_flat=false" 2>&1) &&
TODAY=$(expr "$COUNT" : '.*\s\([0-9]\{1,\}\)\s/.*')
TOTAL=$(expr "$COUNT" : '.*/\s\([0-9]\{1,\}\)\s.*')

archAffix() {
	case "$cpuArch" in
		i686 | i386) cpuArch='386' ;;
		x86_64 | amd64) cpuArch='amd64' ;;
		armv5tel | arm6l | armv7 | armv7l ) cpuArch='arm' ;;
		armv8 | aarch64) cpuArch='aarch64' ;;
		*) red "不支持的CPU架构！" && exit 1;;
	esac
}

back2menu(){
    green "所选操作执行完成"
    read -p "请输入“y”回到主菜单，或按任意键退出脚本：" back2menuInput
    case "$back2menuInput" in
        y ) menu
    esac
}

checkStatus(){
	[[ -z $(cloudflared -help 2>/dev/null) ]] && cloudflaredStatus="未安装"
	[[ -n $(cloudflared -help 2>/dev/null) ]] && cloudflaredStatus="已安装"
	[[ -f /root/.cloudflared/cert.pem ]] && loginStatus="已登录"
	[[ ! -f /root/.cloudflared/cert.pem ]] && loginStatus="未登录"
}

installCloudFlared(){
	if [ $RELEASE == "CentOS" ]; then
		wget -N https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$cpuArch.rpm
		rpm -i cloudflared-linux-$cpuArch.rpm
	else
		[ $cpuArch == "aarch64" ] && cpuArch="arm64"
		wget -N https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$cpuArch.deb
		dpkg -i cloudflared-linux-$cpuArch.deb
	fi
}

loginCloudFlared(){
	[ $loginStatus == "已登录" ] && red "已登录CloudFlare Argo Tunnel客户端，无需重复登录！！！" && exit 0
	green "请访问下方提示的网址，登录自己的CloudFlare账号"
    green "然后授权自己的域名给CloudFlare Argo Tunnel即可"
    cloudflared tunnel login
    back2menu
}

menu(){
    clear
    red "=================================="
    echo "                           "
    red "  CloudFlare Argo Tunnel一键脚本   "
    red "          by 小御坂的破站           "
    echo "                           "
    red "  Site: https://owo.misaka.rest  "
    echo "                           "
    red "=================================="
    echo "            "
    yellow "今日运行次数：$TODAY   总共运行次数：$TOTAL"
	echo "            "
	green "CloudFlared 客户端状态：$cloudflaredStatus"
	green "账户登录状态：$loginStatus"
    echo "            "
    echo "1. 安装CloudFlare Argo Tunnel客户端"
    echo "2. 体验CloudFlare Argo Tunnel HTTP隧道"
    echo "3. 体验CloudFlare Argo Tunnel TCP隧道"
    echo "4. 登录CloudFlare Argo Tunnel客户端"
    echo "5. 创建、删除、配置和列出隧道"
    echo "6. 运行HTTP隧道"
    echo "7. 运行TCP隧道"
    echo "8. 运行任意隧道（使用yml配置文件）"
    echo "9. 卸载CloudFlare Argo Tunnel客户端"
    echo "10. 更新脚本"
    echo "0. 退出脚本"
    read -p "请输入选项:" menuNumberInput
    case "$menuNumberInput" in
        1 ) install ;;
        2 ) tryHTTPTunnel ;;
        3 ) tryTCPTunnel ;;
        4 ) cfargoLogin ;;
        5 ) tunnelSelection ;;
        6 ) runHTTPTunnel ;;
        7 ) runTCPTunnel ;;
        8 ) runTunnelUseYml ;;
        9 ) ${PACKAGE_REMOVE[int]} cloudflared ;;
        10 ) wget -N https://raw.githubusercontents.com/Misaka-blog/argo-tunnel-script/master/argo.sh && bash argo.sh ;;
        0 ) exit 1
    esac
}

menu