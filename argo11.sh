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
PACKAGE_INSTALL=("apt -y install" "apt -y install" "yum -y install" "yum -y install" "apk add -f")
PACKAGE_REMOVE=("apt -y remove" "apt -y remove" "yum -y remove" "yum -y remove")

# 判断系统CPU架构
cpuArch=`uname -m`

# 判断cloudflared状态
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
    read -p "请输入“y”退出，或按任意键回到主菜单：" back2menuInput
    case "$back2menuInput" in
        y ) exit 1 ;;
        * ) menu ;;
    esac
}

checkStatus(){
	[[ -z $(cloudflared -help 2>/dev/null) ]] && cloudflaredStatus="未安装"
	[[ -n $(cloudflared -help 2>/dev/null) ]] && cloudflaredStatus="已安装"
	[[ -f /root/.cloudflared/cert.pem ]] && loginStatus="已登录"
	[[ ! -f /root/.cloudflared/cert.pem ]] && loginStatus="未登录"
}

installCloudFlared(){
    [ $cloudflaredStatus == "已安装" ] && red "检测到已安装CloudFlare Argo Tunnel，无需重复安装！！" && exit 1
	if [ ${RELEASE[int]} == "CentOS" ]; then
        [ $cpuArch == "amd64" ] && cpuArch="x86_64"
		wget -N https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$cpuArch.rpm
		rpm -i cloudflared-linux-$cpuArch.rpm
	else
		[ $cpuArch == "aarch64" ] && cpuArch="arm64"
		wget -N https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$cpuArch.deb
		dpkg -i cloudflared-linux-$cpuArch.deb
	fi
    back2menu
}

uninstallCloudFlared(){
    [ $cloudflaredStatus == "未安装" ] && red "检测到未安装CloudFlare Argo Tunnel客户端，无法执行操作！！！" && exit 1
    ${PACKAGE_REMOVE[int]} cloudflared
    rm -rf /root/.cloudflared
    yellow "CloudFlared 客户端已卸载成功"
}

loginCloudFlared(){
	[ $loginStatus == "已登录" ] && red "已登录CloudFlare Argo Tunnel客户端，无需重复登录！！！" && exit 1
	green "请访问下方提示的网址，登录自己的CloudFlare账号"
    green "然后授权自己的域名给CloudFlare Argo Tunnel即可"
    cloudflared tunnel login
    back2menu
}

makeTunnel(){
    read -p "请输入需要创建的隧道名称：" tunnelName
    cloudflared tunnel create $tunnelName
    read -p "请输入域名：" tunnelDomain
    cloudflared tunnel route dns $tunnelName $tunnelDomain
    cloudflared tunnel list
    read -p "请输入隧道UUID（复制ID里面的内容）：" tunnelUUID
    read -p "请输入传输协议（默认http）：" tunnelProtocol
    [ -z $tunnelProtocol ] && tunnelProtocol="http"
    read -p "请输入反代端口：" tunnelPort
    read -p "请输入将要保存的配置文件名：" tunnelFileName
    cat <<EOF > ~/$tunnelFileName.yml
tunnel: $tunnelName
credentials-file: /root/.cloudflared/$tunnelUUID.json
originRequest:
  connectTimeout: 30s
  noTLSVerify: true
ingress:
  - hostname: $tunnelDomain
    service: $tunnelProtocol://localhost:$tunnelPort
  - service: http_status:404
EOF
    back2menu
}

listTunnel(){
    [ $cloudflaredStatus == "未安装" ] && red "检测到未安装CloudFlare Argo Tunnel客户端，无法执行操作！！！" && exit 1
    [ $loginStatus == "未登录" ] && red "请登录CloudFlare Argo Tunnel客户端后再执行操作！！！" && exit 1
    cloudflared tunnel list
    back2menu
}

runTunnel(){
    [ $cloudflaredStatus == "未安装" ] && red "检测到未安装CloudFlare Argo Tunnel客户端，无法执行操作！！！" && exit 1
    [ $loginStatus == "未登录" ] && red "请登录CloudFlare Argo Tunnel客户端后再执行操作！！！" && exit 1
    read -p "请复制粘贴配置文件的位置（例：/root/tunnel.yml）：" ymlLocation
    read -p "请输入创建Screen会话的名字" screenName
    screen -USdm $screenName cloudflared tunnel --config $ymlLocation run
    green "隧道已运行成功，请等待1-3分钟启动并解析完毕"
    back2menu
}

deleteTunnel(){
    [ $cloudflaredStatus == "未安装" ] && red "检测到未安装CloudFlare Argo Tunnel客户端，无法执行操作！！！" && exit 1
    [ $loginStatus == "未登录" ] && red "请登录CloudFlare Argo Tunnel客户端后再执行操作！！！" && exit 1
    read -p "请输入需要删除的隧道名称：" tunnelName
    cloudflared tunnel delete $tunnelName
    back2menu
}

menu(){
    clear
    checkStatus
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
    echo "1. 安装CloudFlared客户端"
    echo "2. 登录CloudFlared客户端"
    echo "3. 配置Argo Tunnel隧道"
    echo "4. 列出Argo Tunnel隧道"
    echo "5. 运行Argo Tunnel隧道"
    echo "6. 删除Argo Tunnel隧道"
    echo "7. 卸载CloudFlared客户端"
    echo "9. 更新脚本"
    echo "0. 退出脚本"
    echo "          "
    read -p "请输入选项:" menuNumberInput
    case "$menuNumberInput" in
        1 ) installCloudFlared ;;
        2 ) loginCloudFlared ;;
        3 ) makeTunnel ;;
        4 ) listTunnel ;;
        5 ) runTunnel ;;
        6 ) deleteTunnel ;;
        7 ) uninstallCloudFlared ;;
        9 ) wget -N https://raw.githubusercontent.com/Misaka-blog/argo-tunnel-script/master/argo.sh && bash argo.sh ;;
        0 ) exit 1 ;;
    esac
}

archAffix
menu