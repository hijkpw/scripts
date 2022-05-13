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

[[ $EUID -ne 0 ]] && red "注意：请在root用户下运行脚本" && exit 1

archAffix(){
    case "$(uname -m)" in
        x86_64|amd64) echo 'amd64' ;;
        *armv8*|aarch64) echo 'arm64' ;;
        *s390x*) echo 's390x' ;;
        *) red " 不支持的CPU架构！" && exit 1 ;;
    esac
}

check_status(){
    IPv4Status=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    IPv6Status=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    # VPSIP变量说明：0为纯IPv6 VPS、1为纯IPv4 VPS、2为原生双栈VPS
    if [[ -z $IPv4Status ]] && [[ $IPv6Status == "off" ]]; then
        VPSIP=0
    fi
    if [[ $IPv4Status == "off" ]] && [[ -z $IPv6Status ]]; then
        VPSIP=1
    fi
    if [[ $IPv4Status == "off" ]] && [[ $IPv6Status == "off" ]]; then
        VPSIP=2
    fi
}

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

wgcf4d(){
    sed -i "7 s/^/PostUp = ip -4 rule add from $(ip route get 114.114.114.114 | grep -oP 'src \K\S+') lookup main\n/" wgcf-profile.conf
    sed -i "8 s/^/PostDown = ip -4 rule delete from $(ip route get 114.114.114.114 | grep -oP 'src \K\S+') lookup main\n/" wgcf-profile.conf
    sed -i 's/engage.cloudflareclient.com/162.159.193.10/g' wgcf-profile.conf
    sed -i 's/1.1.1.1/1.1.1.1,8.8.8.8,8.8.4.4,2606:4700:4700::1001,2606:4700:4700::1111,2001:4860:4860::8888,2001:4860:4860::8844/g' wgcf-profile.conf
}

wgcf46(){
    sed -i '/0\.\0\/0/d' wgcf-profile.conf
    sed -i 's/engage.cloudflareclient.com/162.159.193.10/g' wgcf-profile.conf
    sed -i 's/1.1.1.1/1.1.1.1,8.8.8.8,8.8.4.4,2606:4700:4700::1001,2606:4700:4700::1111,2001:4860:4860::8888,2001:4860:4860::8844/g' wgcf-profile.conf
}

warp64(){
    sed -i '/\:\:\/0/d' wgcf-profile.conf
    sed -i 's/engage.cloudflareclient.com/[2606:4700:d0::a29f:c001]/g' wgcf-profile.conf
    sed -i 's/1.1.1.1/2606:4700:4700::1001,2606:4700:4700::1111,2001:4860:4860::8888,2001:4860:4860::8844,1.1.1.1,8.8.8.8,8.8.4.4/g' wgcf-profile.conf
}

warp6d(){
    sed -i "7 s/^/PostUp = ip -6 rule add from $(ip route get 2400:3200::1 | grep -oP 'src \K\S+') lookup main\n/" wgcf-profile.conf
    sed -i "8 s/^/PostDown = ip -6 rule delete from $(ip route get 2400:3200::1 | grep -oP 'src \K\S+') lookup main\n/" wgcf-profile.conf
    sed -i 's/engage.cloudflareclient.com/[2606:4700:d0::a29f:c001]/g' wgcf-profile.conf
    sed -i 's/1.1.1.1/2606:4700:4700::1001,2606:4700:4700::1111,2001:4860:4860::8888,2001:4860:4860::8844,1.1.1.1,8.8.8.8,8.8.4.4/g' wgcf-profile.conf
}

warpd(){
    sed -i "7 s/^/PostUp = ip -4 rule add from $(ip route get 114.114.114.114 | grep -oP 'src \K\S+') lookup main\n/" wgcf-profile.conf
    sed -i "8 s/^/PostDown = ip -4 rule delete from $(ip route get 114.114.114.114 | grep -oP 'src \K\S+') lookup main\n/" wgcf-profile.conf
    sed -i "9 s/^/PostUp = ip -6 rule add from $(ip route get 2400:3200::1 | grep -oP 'src \K\S+') lookup main\n/" wgcf-profile.conf
    sed -i "10 s/^/PostDown = ip -6 rule delete from $(ip route get 2400:3200::1 | grep -oP 'src \K\S+') lookup main\n/" wgcf-profile.conf
    sed -i 's/1.1.1.1/1.1.1.1,8.8.8.8,8.8.4.4,2606:4700:4700::1001,2606:4700:4700::1111,2001:4860:4860::8888,2001:4860:4860::8844/g' wgcf-profile.conf
}

install_wgcf(){
    check_tun
    if [[ $SYSTEM == "CentOS" ]]; then
        main=`uname  -r | awk -F . '{print $1}'`
        minor=`uname -r | awk -F . '{print $2}'`
        ${PACKAGE_INSTALL[int]} epel-release
        ${PACKAGE_INSTALL[int]} sudo curl wget net-tools wireguard-tools iptables
        if [ "$main" -lt 5 ] || [ "$minor" -lt 6 ]; then 
            if [[ ${vpsvirt} == "kvm" || ${vpsvirt} == "xen" || ${vpsvirt} == "microsoft" ]]; then
                vsid=`grep -i version_id /etc/os-release | cut -d \" -f2 | cut -d . -f1`
                curl -Lo /etc/yum.repos.d/wireguard.repo https://copr.fedorainfracloud.org/coprs/jdoss/wireguard/repo/epel-$vsid/jdoss-wireguard-epel-$vsid.repo
                yum -y install epel-release wireguard-dkms
            fi
        fi
    elif [[ $SYSTEM == "Debian" ]]; then
        main=`uname  -r | awk -F . '{print $1}'`
        minor=`uname -r | awk -F . '{print $2}'`
        ${PACKAGE_UPDATE[int]}
        ${PACKAGE_INSTALL[int]} sudo wget curllsb-release
        echo "deb http://deb.debian.org/debian $(lsb_release -sc)-backports main" | tee /etc/apt/sources.list.d/backports.list
        ${PACKAGE_UPDATE[int]}
        ${PACKAGE_INSTALL[int]} --no-install-recommends net-tools iproute2 openresolv dnsutils wireguard-tools iptables
        if [ "$main" -lt 5 ] || [ "$minor" -lt 6 ]; then
            if [[ ${vpsvirt} == "kvm" || ${vpsvirt} == "xen" || ${vpsvirt} == "microsoft" ]]; then
                ${PACKAGE_INSTALL[int]} --no-install-recommends linux-headers-$(uname -r)
                ${PACKAGE_INSTALL[int]} --no-install-recommends wireguard-dkms
            fi
        fi
    else
        ${PACKAGE_UPDATE[int]}
        ${PACKAGE_INSTALL[int]} sudo curl wget
        ${PACKAGE_INSTALL[int]} --no-install-recommends net-tools iproute2 openresolv dnsutils wireguard-tools iptables
    fi
    vpsvirt=$(systemd-detect-virt)
    if [[ $vpsvirt =~ lxc|openvz ]]; then
        wget -N --no-check-certificate https://cdn.jsdelivr.net/gh/Misaka-blog/Misaka-WARP-Script/files/wireguard-go -O /usr/bin/wireguard-go
        chmod +x /usr/bin/wireguard-go
    fi
    if [[ $vpsvirt == zvm ]]; then
        wget -N --no-check-certificate https://cdn.jsdelivr.net/gh/Misaka-blog/Misaka-WARP-Script/files/wireguard-go-s390x -O /usr/bin/wireguard-go
        chmod +x /usr/bin/wireguard-go
    fi
    wgcf_last_version=$(curl -Ls "https://api.github.com/repos/ViRb3/wgcf/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' | sed "s/v//g")
    if [[ -z $wgcf_last_version ]]; then
        wgcf_last_version="2.2.14"
    fi
    wget -N --no-check-certificate https://github.com/ViRb3/wgcf/releases/download/latest/wgcf_"$last_version"_linux_$(archAffix) -O /usr/local/bin/wgcf || wget -N --no-check-certificate https://cdn.jsdelivr.net/gh/Misaka-blog/Misaka-WARP-Script/files/wgcf_2.2.14_linux_$(archAffix) -O /usr/local/bin/wgcf
    chmod +x /usr/local/bin/wgcf
    until [[ -a wgcf-account.toml ]]; do
        yellow "正在向CloudFlare WARP申请账号，如提示429 Too Many Requests错误请耐心等待即可"
        yes | wgcf register
        sleep 5
    done
    chmod +x wgcf-account.toml
    yellow "使用WARP免费版账户请按回车跳过 \n启用WARP+账户，请复制WARP+的许可证密钥(26个字符)后回车"
    read -p "按键许可证密钥(26个字符):" WPPlusKey
    if [[ -n $WPPlusKey ]]; then
        sed -i "s/license_key.*/license_key = \"$WPPlusKey\"/g" wgcf-account.toml
        read -p "请输入自定义设备名，如未输入则使用默认随机设备名：" WPPlusName
        green "注册WARP+账户中，如下方显示：400 Bad Request，则使用WARP免费版账户" 
        if [[ -n $WPPlusName ]]; then
            wgcf update --name $(echo $WPPlusName | sed s/[[:space:]]/_/g)
        else
            wgcf update
        fi
    fi
    wgcf generate
    chmod +x wgcf-profile.conf

}

menu0(){
    echo "#############################################################"
    echo -e "#                  ${RED} WARP  一键安装脚本${PLAIN}                      #"
    echo -e "# ${GREEN}作者${PLAIN}: Misaka No                                           #"
    echo -e "# ${GREEN}网址${PLAIN}: https://owo.misaka.rest                             #"
    echo -e "# ${GREEN}论坛${PLAIN}: https://vpsgo.co                                    #"
    echo -e "# ${GREEN}TG群${PLAIN}: https://t.me/misakanetcn                            #"
    echo "#############################################################"
    echo -e ""
    echo -e " ${GREEN}1.${PLAIN} 安装 Wgcf-WARP 单栈模式 ${YELLOW}(WARP IPv4 + 原生IPv6)${PLAIN}"
    echo -e " ${GREEN}2.${PLAIN} 安装 Wgcf-WARP 双栈模式 ${YELLOW}(WARP IPV4 + WARP IPv6)${PLAIN}"
}

menu1(){
    echo "#############################################################"
    echo -e "#                  ${RED} WARP  一键安装脚本${PLAIN}                      #"
    echo -e "# ${GREEN}作者${PLAIN}: Misaka No                                           #"
    echo -e "# ${GREEN}网址${PLAIN}: https://owo.misaka.rest                             #"
    echo -e "# ${GREEN}论坛${PLAIN}: https://vpsgo.co                                    #"
    echo -e "# ${GREEN}TG群${PLAIN}: https://t.me/misakanetcn                            #"
    echo "#############################################################"
    echo -e " ${GREEN}1.${PLAIN} 安装 Wgcf-WARP 单栈模式 ${YELLOW}(原生 IPv4 + WARP IPv6)${PLAIN}"
    echo -e " ${GREEN}2.${PLAIN} 安装 Wgcf-WARP 双栈模式 ${YELLOW}(WARP IPV4 + WARP IPv6)${PLAIN}"
}

menu2(){
    echo "#############################################################"
    echo -e "#                  ${RED} WARP  一键安装脚本${PLAIN}                      #"
    echo -e "# ${GREEN}作者${PLAIN}: Misaka No                                           #"
    echo -e "# ${GREEN}网址${PLAIN}: https://owo.misaka.rest                             #"
    echo -e "# ${GREEN}论坛${PLAIN}: https://vpsgo.co                                    #"
    echo -e "# ${GREEN}TG群${PLAIN}: https://t.me/misakanetcn                            #"
    echo "#############################################################"
    echo -e " ${GREEN}1.${PLAIN} 安装 Wgcf-WARP 单栈模式 ${YELLOW}(原生 IPv4 + WARP IPv6)${PLAIN}"
    echo -e " ${GREEN}2.${PLAIN} 安装 Wgcf-WARP 单栈模式 ${YELLOW}(WARP IPv4 + 原生IPv6)${PLAIN}"
    echo -e " ${GREEN}3.${PLAIN} 安装 Wgcf-WARP 双栈模式 ${YELLOW}(WARP IPV4 + WARP IPv6)${PLAIN}"
}