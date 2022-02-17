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
ARCH=`uname -m`

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

[ $ARCH == "s390x" ] && red "不支持VPS的当前系统架构，请换用主流的VPS架构" && exit 1
[ $ARCH = "x86_64" ] && ARCH="amd64"

## 统计脚本运行次数
COUNT=$(curl -sm1 "https://hits.seeyoufarm.com/api/count/incr/badge.svg?url=https%3A%2F%2Fcdn.jsdelivr.net%2Fgh%2FMisaka-blog%2Fargo-tunnel-script%40master%2Fargo.sh&count_bg=%2379C83D&title_bg=%23555555&icon=&icon_color=%23E7E7E7&title=hits&edge_flat=false" 2>&1) &&
TODAY=$(expr "$COUNT" : '.*\s\([0-9]\{1,\}\)\s/.*')
TOTAL=$(expr "$COUNT" : '.*/\s\([0-9]\{1,\}\)\s.*')

install(){
    [[ -n $(cloudflared -help) ]] && red "检测到已安装CloudFlare Argo Tunnel，无需重复安装！！" && exit 1
    ${PACKAGE_UPDATE[int]}
    if [ $RELEASE == "CentOS" ]; then
        wget -N https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCH}.rpm
        rpm -i cloudflared-linux-${ARCH}.rpm
    else
        wget -N https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCH}.deb
        dpkg -i cloudflared-linux-${ARCH}.deb
    fi
}

tryHTTPTunnel(){
    [[ -z $(cloudflared -help) ]] && red "检测到未安装CloudFlare Argo Tunnel客户端，无法执行操作！！！" && exit 1
    read -p "请输入你需要穿透的http端口号（默认80）：" httpPort
    [ -z $httpPort ] && httpPort=80
    cloudflared tunnel --url http://127.0.0.1:$httpPort
}

tryTCPTunnel(){
    [[ -z $(cloudflared -help) ]] && red "检测到未安装CloudFlare Argo Tunnel客户端，无法执行操作！！！" && exit 1
    read -p "请输入你需要穿透的tcp端口号（默认80）：" tcpPort
    [ -z $tcpPort ] && tcpPort=80
    cloudflared tunnel --url tcp://127.0.0.1:$tcpPort
}

cfargoLogin(){
    [[ -z $(cloudflared -help) ]] && red "检测到未安装CloudFlare Argo Tunnel客户端，无法执行操作！！！" && exit 1
    [[ -f /root/.cloudflared/cert.pem ]] && red "已登录CloudFlare Argo Tunnel客户端，无需重复登录！！！" && exit 1
    green "请访问下方提示的网址，登录自己的CloudFlare账号"
    green "然后授权自己的域名给CloudFlare Argo Tunnel即可"
    cloudflared tunnel login
}

createTunnel(){
    read -p "请输入需要创建的隧道名称：" tunnelName
    cloudflared tunnel create $tunnelName
}

deleteTunnel(){
    read -p "请输入需要删除的隧道名称：" tunnelName
    cloudflared tunnel delete $tunnelName
}

tunnelFile(){
    read -p "请输入隧道名称：" tunnelName
    read -p "请输入隧道UUID：" tunnelUUID
    read -p "请输入传输协议（默认http）：" tunnelProtocol
    [ -z $tunnelProtocol ] &&tunnelProtocol="http"
    read -p "请输入域名：" tunnelDomain
    read -p "请输入反代端口：" tunnelPort
    read -p "请输入配置文件名：" tunnelFileName
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
}

tunnelConfig(){
    read -p "请输入需要配置的隧道名称：" tunnelName
    read -p "请输入需要配置的域名：" tunnelDomain
    cloudflared tunnel route dns $tunnelName $tunnelDomain
}

tunnelSelection(){
    [[ -z $(cloudflared -help) ]] && red "检测到未安装CloudFlare Argo Tunnel客户端，无法执行操作！！！" && exit 1
    [ ! -f /root/.cloudflared/cert.pem ] && red "请登录CloudFlare Argo Tunnel客户端后再执行操作！！！" && exit 1
    echo "1. 创建隧道"
    echo "2. 删除隧道"
    echo "3. 配置隧道"
    echo "4. 创建隧道配置yml文件"
    echo "5. 列出隧道"
    read -p "请输入选项:" tunnelNumberInput
    case "$tunnelNumberInput" in
        1 ) createTunnel ;;
        2 ) deleteTunnel ;;
        3 ) tunnelConfig ;;
        4 ) tunnelFile ;;
        5 ) cloudflared tunnel list ;;
        0 ) exit 1
    esac
}

runHTTPTunnel(){
    [[ -z $(cloudflared -help) ]] && red "检测到未安装CloudFlare Argo Tunnel客户端，无法执行操作！！！" && exit 1
    [ ! -f /root/.cloudflared/cert.pem ] && red "请登录CloudFlare Argo Tunnel客户端后再执行操作！！！" && exit 1
    read -p "请输入需要运行的隧道名称：" tunnelName
    read -p "请输入你需要穿透的http端口号（默认80）：" httpPort
    [ -z $httpPort ] && httpPort=80
    cloudflared tunnel run --url http://127.0.0.1:$httpPort $tunnelName
}

runTCPTunnel(){
    [[ -z $(cloudflared -help) ]] && red "检测到未安装CloudFlare Argo Tunnel客户端，无法执行操作！！！" && exit 1
    [ ! -f /root/.cloudflared/cert.pem ] && red "请登录CloudFlare Argo Tunnel客户端后再执行操作！！！" && exit 1
    read -p "请输入需要运行的隧道名称：" tunnelName
    read -p "请输入你需要穿透的tcp端口号（默认80）：" tcpPort
    [ -z $tcpPort ] && tcpPort=80
    cloudflared tunnel run --url tcp://127.0.0.1:$tcpPort $tunnelName
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
    echo "1. 安装CloudFlare Argo Tunnel客户端"
    echo "2. 体验CloudFlare Argo Tunnel HTTP隧道"
    echo "3. 体验CloudFlare Argo Tunnel TCP隧道"
    echo "4. 登录CloudFlare Argo Tunnel客户端"
    echo "5. 创建、删除、配置和列出隧道"
    echo "6. 运行HTTP隧道"
    echo "7. 运行TCP隧道"
    echo "8. 卸载CloudFlare Argo Tunnel客户端"
    echo "9. 更新脚本"
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
        8 ) ${PACKAGE_REMOVE[int]} cloudflared ;;
        9 ) wget -N https://raw.githubusercontents.com/Misaka-blog/argo-tunnel-script/master/argo.sh && bash argo.sh ;;
        0 ) exit 1
    esac
}

menu