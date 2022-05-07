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

RED="\033[31m"      # Error message
GREEN="\033[32m"    # Success message
YELLOW="\033[33m"   # Warning message
BLUE="\033[36m"     # Info message
PLAIN='\033[0m'

# 判断系统及定义系统安装依赖方式
REGEX=("debian" "ubuntu" "centos|red hat|kernel|oracle linux|alma|rocky" "'amazon linux'")
RELEASE=("Debian" "Ubuntu" "CentOS" "CentOS")
PACKAGE_UPDATE=("apt -y update" "apt -y update" "yum -y update" "yum -y update")
PACKAGE_INSTALL=("apt -y install" "apt -y install" "yum -y install" "yum -y install")
PACKAGE_REMOVE=("apt -y remove" "apt -y remove" "yum -y remove" "yum -y remove")
PACKAGE_UNINSTALL=("apt -y autoremove" "apt -y autoremove" "yum -y autoremove" "yum -y autoremove")

[[ $EUID -ne 0 ]] && red "请在root用户下运行脚本" && exit 1

CMD=("$(grep -i pretty_name /etc/os-release 2>/dev/null | cut -d \" -f2)" "$(hostnamectl 2>/dev/null | grep -i system | cut -d : -f2)" "$(lsb_release -sd 2>/dev/null)" "$(grep -i description /etc/lsb-release 2>/dev/null | cut -d \" -f2)" "$(grep . /etc/redhat-release 2>/dev/null)" "$(grep . /etc/issue 2>/dev/null | cut -d \\ -f1 | sed '/^[ ]*$/d')") 

for i in "${CMD[@]}"; do
    SYS="$i" && [[ -n $SYS ]] && break
done

for ((int = 0; int < ${#REGEX[@]}; int++)); do
    [[ $(echo "$SYS" | tr '[:upper:]' '[:lower:]') =~ ${REGEX[int]} ]] && SYSTEM="${RELEASE[int]}" && [[ -n $SYSTEM ]] && break
done

IP=$(curl -s6m8 ip.sb) || IP=$(curl -s4m8 ip.sb)

if [[ -n $(echo $IP | grep ":") ]]; then
    IP="[$IP]"
fi

check_tun(){
    TUN=$(cat /dev/net/tun 2>&1 | tr '[:upper:]' '[:lower:]')
    if [[ ! $TUN =~ 'in bad state' ]] && [[ ! $TUN =~ '处于错误状态' ]] && [[ ! $TUN =~ 'Die Dateizugriffsnummer ist in schlechter Verfassung' ]]; then
        if [[ $vpsvirt == "openvz" ]]; then
            wget -N --no-check-certificate https://raw.githubusercontents.com/Misaka-blog/tun-script/master/tun.sh && bash tun.sh
        else
            red "检测到未开启TUN模块，请到VPS控制面板处开启" 
            exit 1
        fi
    fi
}

checkCentOS8(){
    if [[ -n $(cat /etc/os-release | grep "CentOS Linux 8") ]]; then
        yellow "检测到当前VPS系统为CentOS 8，是否升级为CentOS Stream 8以确保软件包正常安装？"
        read -p "请输入选项 [y/n]：" comfirmCentOSStream
        if [[ $comfirmCentOSStream == "y" ]]; then
            yellow "正在为你升级到CentOS Stream 8，大概需要10-30分钟的时间"
            sleep 1
            sed -i -e "s|releasever|releasever-stream|g" /etc/yum.repos.d/CentOS-*
            yum clean all && yum makecache
            dnf swap centos-linux-repos centos-stream-repos distro-sync -y
        else
            red "已取消升级过程，脚本即将退出！"
            exit 1
        fi
    fi
}

archAffix(){
    case "$(uname -m)" in
        i686 | i386) echo '386' ;;
        x86_64 | amd64) echo 'amd64' ;;
        armv5tel) echo 'arm-5' ;;
        armv7 | armv7l) echo 'arm-7' ;;
        armv8 | aarch64) echo 'arm64' ;;
        s390x) echo 's390x' ;;
        *) red " 不支持的CPU架构！" && exit 1 ;;
    esac
    return 0
}

install_base() {
    if [[ $SYSTEM != "CentOS" ]]; then
        ${PACKAGE_UPDATE[int]}
    fi
    ${PACKAGE_INSTALL[int]} wget curl sudo
}

downloadHysteria() {
    rm -rf /root/Hysteria
    mkdir /root/Hysteria
    last_version=$(curl -Ls "https://api.github.com/repos/HyNetwork/Hysteria/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    if [[ ! -n "$last_version" ]]; then
        red "检测 Hysteria 版本失败，可能是超出 Github API 限制，请稍后再试"
        exit 1
    fi
    yellow "检测到 Hysteria 最新版本：${last_version}，开始安装"
    wget -N --no-check-certificate https://github.com/HyNetwork/Hysteria/releases/download/${last_version}/Hysteria-tun-linux-$(archAffix) -O /root/Hysteria/hysteria
    if [[ $? -ne 0 ]]; then
        red "下载 Hysteria 失败，请确保你的服务器能够连接并下载 Github 的文件"
        exit 1
    fi
    chmod +x /root/Hysteria/hysteria
}

makeConfig() {
    cat <<EOF > /root/Hysteria/config.json
{
    "listen": ":$PORT",
    "cert": "cert.pem",
    "key": "key.pem",
    "obfs": "password"
}
EOF
    cat <<EOF > /root/server.json
{
    "listen": ":$PORT",
    "cert": "cert.pem",
    "key": "key.pem",
    "obfs": "password"
}
EOF
    cat <<EOF > /root/client.json
{
    "server": "$IP:$PORT",
    "obfs": "password",
    "insecure": true,
    "socks5": {
        "listen": "127.0.0.1:1080"
    },
    "http": {
        "listen": "127.0.0.1:1081"
    }
}
EOF
    cat <<'TEXT' > /etc/systemd/system/hysteria.service
[Unit]
Description=Hysiteria Server
After=network.target

[Install]
WantedBy=multi-user.target

[Service]
Type=simple
WorkingDirectory=/root/Hysteria
ExecStart=/root/Hysteria/hysteria server
Restart=always
TEXT
}

installHysteria() {
    checkCentOS8
    install_base
    downloadHysteria
    makeConfig
    systemctl enable hysteria
    systemctl start hysteria
}

menu() {
    clear
    echo "#############################################################"
    echo -e "#                 ${RED} Hysieria  一键安装脚本${PLAIN}                   #"
    echo -e "# ${GREEN}作者${PLAIN}: Misaka No                                           #"
    echo -e "# ${GREEN}网址${PLAIN}: https://owo.misaka.rest                             #"
    echo -e "# ${GREEN}论坛${PLAIN}: https://owo.misaka.rest                             #"
    echo -e "# ${GREEN}TG群${PLAIN}: https://t.me/misakanetcn                            #"
    echo "#############################################################"
    echo ""

    echo -e "  ${GREEN}1.${PLAIN}  安装Hysieria "
    echo -e "  ${GREEN}2.  ${RED}卸载Hysieria ${PLAIN}"
    echo " -------------"
    echo -e "  ${GREEN}3.${PLAIN}  启动Hysieria "
    echo -e "  ${GREEN}4.${PLAIN}  重启Hysieria "
    echo -e "  ${GREEN}5.${PLAIN}  停止Hysieria "
    echo " -------------"
    echo -e "  ${GREEN}0.${PLAIN} 退出"
    echo ""
    
    read -p " 请选择操作[0-5]：" answer
    case $answer in
        1) installHysteria ;;
    esac
}

menu