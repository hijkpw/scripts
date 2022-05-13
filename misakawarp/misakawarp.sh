#!/bin/bash

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
PLAIN='\033[0m'

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
PACKAGE_UPDATE=("apt-get -y update" "apt-get -y update" "yum -y update" "yum -y update")
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
    if [[ -z $IPv4Status ]] && [[ $IPv6Status =~ "on"|"plus" ]]; then
        VPSIP=0
    fi
    if [[ $IPv4Status =~ "on"|"plus" ]] && [[ $IPv6Status == "off" ]]; then
        VPSIP=0
    fi
    if [[ $IPv4Status == "off" ]] && [[ -z $IPv6Status ]]; then
        VPSIP=1
    fi
    if [[ $IPv4Status =~ "on"|"plus" ]] && [[ -z $IPv6Status ]]; then
        VPSIP=1
    fi
    if [[ $IPv4Status == "off" ]] && [[ $IPv6Status =~ "on"|"plus" ]]; then
        VPSIP=1
    fi
    if [[ $IPv4Status == "off" ]] && [[ $IPv6Status == "off" ]]; then
        VPSIP=2
    fi
    if [[ $IPv4Status =~ "on"|"plus" ]] && [[ $IPv6Status =~ "on"|"plus" ]]; then
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

wgcf44(){
    sed -i '/\:\:\/0/d' wgcf-profile.conf
    sed -i "7 s/^/PostUp = ip -4 rule add from $(ip route get 114.114.114.114 | grep -oP 'src \K\S+') lookup main\n/" wgcf-profile.conf
    sed -i "8 s/^/PostDown = ip -4 rule delete from $(ip route get 114.114.114.114 | grep -oP 'src \K\S+') lookup main\n/" wgcf-profile.conf
    sed -i 's/engage.cloudflareclient.com/162.159.193.10/g' wgcf-profile.conf
    sed -i 's/1.1.1.1/1.1.1.1,8.8.8.8,8.8.4.4,2606:4700:4700::1001,2606:4700:4700::1111,2001:4860:4860::8888,2001:4860:4860::8844/g' wgcf-profile.conf
    
    if [[ ! -d "/etc/wireguard" ]]; then
        mkdir /etc/wireguard
    fi
    mv -f wgcf-profile.conf /etc/wireguard/wgcf.conf
    mv -f wgcf-account.toml /etc/wireguard/wgcf-account.toml
    
    yellow "正在启动 Wgcf-WARP"
    wg-quick up wgcf >/dev/null 2>&1
    WgcfWARPStatus=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    until [[ $WgcfWARPStatus =~ "on"|"plus" ]]; do
        red "无法启动Wgcf-WARP，正在尝试重启"
        wg-quick down wgcf >/dev/null 2>&1
        wg-quick up wgcf >/dev/null 2>&1
        WgcfWARPStatus=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
        sleep 8
    done
    systemctl enable wg-quick@wgcf >/dev/null 2>&1
    WgcfIPv4=$(curl -s4m8 https://ip.gs -k)
    green "Wgcf-WARP 已启动成功"
    yellow "Wgcf-WARP的IPv4 IP为：$WgcfIPv4"
}

wgcf46(){
    sed -i '/0\.\0\/0/d' wgcf-profile.conf
    sed -i "7 s/^/PostUp = ip -4 rule add from $(ip route get 114.114.114.114 | grep -oP 'src \K\S+') lookup main\n/" wgcf-profile.conf
    sed -i "8 s/^/PostDown = ip -4 rule delete from $(ip route get 114.114.114.114 | grep -oP 'src \K\S+') lookup main\n/" wgcf-profile.conf
    sed -i 's/engage.cloudflareclient.com/162.159.193.10/g' wgcf-profile.conf
    sed -i 's/1.1.1.1/1.1.1.1,8.8.8.8,8.8.4.4,2606:4700:4700::1001,2606:4700:4700::1111,2001:4860:4860::8888,2001:4860:4860::8844/g' wgcf-profile.conf
    
    if [[ ! -d "/etc/wireguard" ]]; then
        mkdir /etc/wireguard
    fi
    mv -f wgcf-profile.conf /etc/wireguard/wgcf.conf
    mv -f wgcf-account.toml /etc/wireguard/wgcf-account.toml
    
    yellow "正在启动 Wgcf-WARP"
    wg-quick up wgcf >/dev/null 2>&1
    WgcfWARPStatus=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    until [[ $WgcfWARPStatus =~ "on"|"plus" ]]; do
        red "无法启动Wgcf-WARP，正在尝试重启"
        wg-quick down wgcf >/dev/null 2>&1
        wg-quick up wgcf >/dev/null 2>&1
        WgcfWARPStatus=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
        sleep 8
    done
    systemctl enable wg-quick@wgcf >/dev/null 2>&1
    WgcfIPv6=$(curl -s6m8 https://ip.gs -k)
    green "Wgcf-WARP 已启动成功"
    yellow "Wgcf-WARP的IPv6 IP为：$WgcfIPv6"
}

wgcf4d(){
    sed -i "7 s/^/PostUp = ip -4 rule add from $(ip route get 114.114.114.114 | grep -oP 'src \K\S+') lookup main\n/" wgcf-profile.conf
    sed -i "8 s/^/PostDown = ip -4 rule delete from $(ip route get 114.114.114.114 | grep -oP 'src \K\S+') lookup main\n/" wgcf-profile.conf
    sed -i 's/engage.cloudflareclient.com/162.159.193.10/g' wgcf-profile.conf
    sed -i 's/1.1.1.1/1.1.1.1,8.8.8.8,8.8.4.4,2606:4700:4700::1001,2606:4700:4700::1111,2001:4860:4860::8888,2001:4860:4860::8844/g' wgcf-profile.conf
    
    if [[ ! -d "/etc/wireguard" ]]; then
        mkdir /etc/wireguard
    fi
    mv -f wgcf-profile.conf /etc/wireguard/wgcf.conf
    mv -f wgcf-account.toml /etc/wireguard/wgcf-account.toml
    
    yellow "正在启动 Wgcf-WARP"
    wg-quick up wgcf >/dev/null 2>&1
    WgcfWARP4Status=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    WgcfWARP6Status=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    until [[ $WgcfWARP4Status =~ on|plus ]] && [[ $WgcfWARP6Status =~ on|plus ]]; do
        red "无法启动Wgcf-WARP，正在尝试重启"
        wg-quick down wgcf >/dev/null 2>&1
        wg-quick up wgcf >/dev/null 2>&1
        WgcfWARP4Status=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
        WgcfWARP6Status=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
        sleep 8
    done
    systemctl enable wg-quick@wgcf >/dev/null 2>&1
    WgcfIPv4=$(curl -s4m8 https://ip.gs -k)
    WgcfIPv6=$(curl -s6m8 https://ip.gs -k)
    green "Wgcf-WARP 已启动成功"
    yellow "Wgcf-WARP的IPv4 IP为：$WgcfIPv4"
    yellow "Wgcf-WARP的IPv6 IP为：$WgcfIPv6"
}

wgcf64(){
    sed -i '/\:\:\/0/d' wgcf-profile.conf
    sed -i "7 s/^/PostUp = ip -6 rule add from $(ip route get 2400:3200::1 | grep -oP 'src \K\S+') lookup main\n/" wgcf-profile.conf
    sed -i "8 s/^/PostDown = ip -6 rule delete from $(ip route get 2400:3200::1 | grep -oP 'src \K\S+') lookup main\n/" wgcf-profile.conf
    sed -i 's/engage.cloudflareclient.com/[2606:4700:d0::a29f:c001]/g' wgcf-profile.conf
    sed -i 's/1.1.1.1/2606:4700:4700::1001,2606:4700:4700::1111,2001:4860:4860::8888,2001:4860:4860::8844,1.1.1.1,8.8.8.8,8.8.4.4/g' wgcf-profile.conf
    
    if [[ ! -d "/etc/wireguard" ]]; then
        mkdir /etc/wireguard
    fi
    mv -f wgcf-profile.conf /etc/wireguard/wgcf.conf
    mv -f wgcf-account.toml /etc/wireguard/wgcf-account.toml
    
    yellow "正在启动 Wgcf-WARP"
    wg-quick up wgcf >/dev/null 2>&1
    WgcfWARPStatus=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    until [[ $WgcfWARPStatus =~ on|plus ]]; do
        red "无法启动Wgcf-WARP，正在尝试重启"
        wg-quick down wgcf >/dev/null 2>&1
        wg-quick up wgcf >/dev/null 2>&1
        WgcfWARPStatus=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
        sleep 8
    done
    systemctl enable wg-quick@wgcf >/dev/null 2>&1
    WgcfIPv4=$(curl -s4m8 https://ip.gs -k)
    green "Wgcf-WARP 已启动成功"
    yellow "Wgcf-WARP的IPv4 IP为：$WgcfIPv4"
}

wgcf66(){
    sed -i '/0\.\0\/0/d' wgcf-profile.conf
    sed -i "7 s/^/PostUp = ip -6 rule add from $(ip route get 2400:3200::1 | grep -oP 'src \K\S+') lookup main\n/" wgcf-profile.conf
    sed -i "8 s/^/PostDown = ip -6 rule delete from $(ip route get 2400:3200::1 | grep -oP 'src \K\S+') lookup main\n/" wgcf-profile.conf
    sed -i 's/engage.cloudflareclient.com/[2606:4700:d0::a29f:c001]/g' wgcf-profile.conf
    sed -i 's/1.1.1.1/2606:4700:4700::1001,2606:4700:4700::1111,2001:4860:4860::8888,2001:4860:4860::8844,1.1.1.1,8.8.8.8,8.8.4.4/g' wgcf-profile.conf
    
    if [[ ! -d "/etc/wireguard" ]]; then
        mkdir /etc/wireguard
    fi
    mv -f wgcf-profile.conf /etc/wireguard/wgcf.conf
    mv -f wgcf-account.toml /etc/wireguard/wgcf-account.toml
    
    yellow "正在启动 Wgcf-WARP"
    wg-quick up wgcf >/dev/null 2>&1
    WgcfWARPStatus=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    until [[ $WgcfWARPStatus =~ on|plus ]]; do
        red "无法启动Wgcf-WARP，正在尝试重启"
        wg-quick down wgcf >/dev/null 2>&1
        wg-quick up wgcf >/dev/null 2>&1
        WgcfWARPStatus=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
        sleep 8
    done
    systemctl enable wg-quick@wgcf >/dev/null 2>&1
    WgcfIPv6=$(curl -s6m8 https://ip.gs -k)
    green "Wgcf-WARP 已启动成功"
    yellow "Wgcf-WARP的IPv6 IP为：$WgcfIPv6"
}

wgcf6d(){
    sed -i "7 s/^/PostUp = ip -6 rule add from $(ip route get 2400:3200::1 | grep -oP 'src \K\S+') lookup main\n/" wgcf-profile.conf
    sed -i "8 s/^/PostDown = ip -6 rule delete from $(ip route get 2400:3200::1 | grep -oP 'src \K\S+') lookup main\n/" wgcf-profile.conf
    sed -i 's/engage.cloudflareclient.com/[2606:4700:d0::a29f:c001]/g' wgcf-profile.conf
    sed -i 's/1.1.1.1/2606:4700:4700::1001,2606:4700:4700::1111,2001:4860:4860::8888,2001:4860:4860::8844,1.1.1.1,8.8.8.8,8.8.4.4/g' wgcf-profile.conf
    
    if [[ ! -d "/etc/wireguard" ]]; then
        mkdir /etc/wireguard
    fi
    mv -f wgcf-profile.conf /etc/wireguard/wgcf.conf
    mv -f wgcf-account.toml /etc/wireguard/wgcf-account.toml

    yellow "正在启动 Wgcf-WARP"
    wg-quick up wgcf >/dev/null 2>&1
    WgcfWARP4Status=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    WgcfWARP6Status=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    until [[ $WgcfWARP4Status =~ on|plus ]] && [[ $WgcfWARP6Status =~ on|plus ]]; do
        red "无法启动Wgcf-WARP，正在尝试重启"
        wg-quick down wgcf >/dev/null 2>&1
        wg-quick up wgcf >/dev/null 2>&1
        WgcfWARP4Status=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
        WgcfWARP6Status=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
        sleep 8
    done
    systemctl enable wg-quick@wgcf >/dev/null 2>&1
    WgcfIPv4=$(curl -s4m8 https://ip.gs -k)
    WgcfIPv6=$(curl -s6m8 https://ip.gs -k)
    green "Wgcf-WARP 已启动成功"
    yellow "Wgcf-WARP的IPv4 IP为：$WgcfIPv4"
    yellow "Wgcf-WARP的IPv6 IP为：$WgcfIPv6"
}

wgcfd4(){
    sed -i '/\:\:\/0/d' wgcf-profile.conf
    sed -i "7 s/^/PostUp = ip -4 rule add from $(ip route get 114.114.114.114 | grep -oP 'src \K\S+') lookup main\n/" wgcf-profile.conf
    sed -i "8 s/^/PostDown = ip -4 rule delete from $(ip route get 114.114.114.114 | grep -oP 'src \K\S+') lookup main\n/" wgcf-profile.conf
    sed -i "9 s/^/PostUp = ip -6 rule add from $(ip route get 2400:3200::1 | grep -oP 'src \K\S+') lookup main\n/" wgcf-profile.conf
    sed -i "10 s/^/PostDown = ip -6 rule delete from $(ip route get 2400:3200::1 | grep -oP 'src \K\S+') lookup main\n/" wgcf-profile.conf
    sed -i 's/1.1.1.1/1.1.1.1,8.8.8.8,8.8.4.4,2606:4700:4700::1001,2606:4700:4700::1111,2001:4860:4860::8888,2001:4860:4860::8844/g' wgcf-profile.conf
    
    if [[ ! -d "/etc/wireguard" ]]; then
        mkdir /etc/wireguard
    fi
    mv -f wgcf-profile.conf /etc/wireguard/wgcf.conf
    mv -f wgcf-account.toml /etc/wireguard/wgcf-account.toml
    
    yellow "正在启动 Wgcf-WARP"
    wg-quick up wgcf >/dev/null 2>&1
    WgcfWARPStatus=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    until [[ $WgcfWARPStatus =~ on|plus ]]; do
        red "无法启动Wgcf-WARP，正在尝试重启"
        wg-quick down wgcf >/dev/null 2>&1
        wg-quick up wgcf >/dev/null 2>&1
        WgcfWARPStatus=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
        sleep 8
    done
    systemctl enable wg-quick@wgcf >/dev/null 2>&1
    WgcfIPv4=$(curl -s4m8 https://ip.gs -k)
    green "Wgcf-WARP 已启动成功"
    yellow "Wgcf-WARP的IPv4 IP为：$WgcfIPv4"
}

wgcfd6(){
    sed -i '/0\.\0\/0/d' wgcf-profile.conf
    sed -i "7 s/^/PostUp = ip -4 rule add from $(ip route get 114.114.114.114 | grep -oP 'src \K\S+') lookup main\n/" wgcf-profile.conf
    sed -i "8 s/^/PostDown = ip -4 rule delete from $(ip route get 114.114.114.114 | grep -oP 'src \K\S+') lookup main\n/" wgcf-profile.conf
    sed -i "9 s/^/PostUp = ip -6 rule add from $(ip route get 2400:3200::1 | grep -oP 'src \K\S+') lookup main\n/" wgcf-profile.conf
    sed -i "10 s/^/PostDown = ip -6 rule delete from $(ip route get 2400:3200::1 | grep -oP 'src \K\S+') lookup main\n/" wgcf-profile.conf
    sed -i 's/1.1.1.1/1.1.1.1,8.8.8.8,8.8.4.4,2606:4700:4700::1001,2606:4700:4700::1111,2001:4860:4860::8888,2001:4860:4860::8844/g' wgcf-profile.conf
    
    if [[ ! -d "/etc/wireguard" ]]; then
        mkdir /etc/wireguard
    fi
    mv -f wgcf-profile.conf /etc/wireguard/wgcf.conf
    mv -f wgcf-account.toml /etc/wireguard/wgcf-account.toml
    
    yellow "正在启动 Wgcf-WARP"
    wg-quick up wgcf >/dev/null 2>&1
    WgcfWARPStatus=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    until [[ $WgcfWARPStatus =~ on|plus ]]; do
        red "无法启动Wgcf-WARP，正在尝试重启"
        wg-quick down wgcf >/dev/null 2>&1
        wg-quick up wgcf >/dev/null 2>&1
        WgcfWARPStatus=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
        sleep 8
    done
    systemctl enable wg-quick@wgcf >/dev/null 2>&1
    WgcfIPv6=$(curl -s6m8 https://ip.gs -k)
    green "Wgcf-WARP 已启动成功"
    yellow "Wgcf-WARP的IPv6 IP为：$WgcfIPv6"
}

wgcfd(){
    sed -i "7 s/^/PostUp = ip -4 rule add from $(ip route get 114.114.114.114 | grep -oP 'src \K\S+') lookup main\n/" wgcf-profile.conf
    sed -i "8 s/^/PostDown = ip -4 rule delete from $(ip route get 114.114.114.114 | grep -oP 'src \K\S+') lookup main\n/" wgcf-profile.conf
    sed -i "9 s/^/PostUp = ip -6 rule add from $(ip route get 2400:3200::1 | grep -oP 'src \K\S+') lookup main\n/" wgcf-profile.conf
    sed -i "10 s/^/PostDown = ip -6 rule delete from $(ip route get 2400:3200::1 | grep -oP 'src \K\S+') lookup main\n/" wgcf-profile.conf
    sed -i 's/1.1.1.1/1.1.1.1,8.8.8.8,8.8.4.4,2606:4700:4700::1001,2606:4700:4700::1111,2001:4860:4860::8888,2001:4860:4860::8844/g' wgcf-profile.conf
    
    if [[ ! -d "/etc/wireguard" ]]; then
        mkdir /etc/wireguard
    fi
    mv -f wgcf-profile.conf /etc/wireguard/wgcf.conf
    mv -f wgcf-account.toml /etc/wireguard/wgcf-account.toml
    
    yellow "正在启动 Wgcf-WARP"
    wg-quick up wgcf >/dev/null 2>&1
    WgcfWARP4Status=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    WgcfWARP6Status=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    until [[ $WgcfWARP4Status =~ on|plus ]] && [[ $WgcfWARP6Status =~ on|plus ]]; do
        red "无法启动Wgcf-WARP，正在尝试重启"
        wg-quick down wgcf >/dev/null 2>&1
        wg-quick up wgcf >/dev/null 2>&1
        WgcfWARP4Status=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
        WgcfWARP6Status=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
        sleep 8
    done
    systemctl enable wg-quick@wgcf >/dev/null 2>&1
    WgcfIPv4=$(curl -s4m8 https://ip.gs -k)
    WgcfIPv6=$(curl -s6m8 https://ip.gs -k)
    green "Wgcf-WARP 已启动成功"
    yellow "Wgcf-WARP的IPv4 IP为：$WgcfIPv4"
    yellow "Wgcf-WARP的IPv6 IP为：$WgcfIPv6"
}

install_wgcf(){
    check_tun
    vpsvirt=$(systemd-detect-virt)
    main=`uname  -r | awk -F . '{print $1}'`
    minor=`uname -r | awk -F . '{print $2}'`
    if [[ $SYSTEM == "CentOS" ]]; then        
        ${PACKAGE_INSTALL[int]} epel-release
        ${PACKAGE_INSTALL[int]} sudo curl wget net-tools wireguard-tools iptables
        if [ "$main" -lt 5 ] || [ "$minor" -lt 6 ]; then 
            if [[ ${vpsvirt} == "kvm" || ${vpsvirt} == "xen" || ${vpsvirt} == "microsoft" ]]; then
                vsid=`grep -i version_id /etc/os-release | cut -d \" -f2 | cut -d . -f1`
                curl -Lo /etc/yum.repos.d/wireguard.repo https://copr.fedorainfracloud.org/coprs/jdoss/wireguard/repo/epel-$vsid/jdoss-wireguard-epel-$vsid.repo
                ${PACKAGE_INSTALL[int]} wireguard-dkms
            fi
        fi
    fi
    if [[ $SYSTEM == "Debian" ]]; then
        ${PACKAGE_UPDATE[int]}
        ${PACKAGE_INSTALL[int]} sudo wget curl lsb-release
        echo "deb http://deb.debian.org/debian $(lsb_release -sc)-backports main" | tee /etc/apt/sources.list.d/backports.list
        ${PACKAGE_UPDATE[int]}
        ${PACKAGE_INSTALL[int]} --no-install-recommends net-tools iproute2 openresolv dnsutils wireguard-tools iptables
        if [ "$main" -lt 5 ] || [ "$minor" -lt 6 ]; then
            if [[ ${vpsvirt} == "kvm" || ${vpsvirt} == "xen" || ${vpsvirt} == "microsoft" ]]; then
                ${PACKAGE_INSTALL[int]} --no-install-recommends linux-headers-$(uname -r)
                ${PACKAGE_INSTALL[int]} --no-install-recommends wireguard-dkms
            fi
        fi
    fi
    if [[ $SYSTEM == "Ubuntu" ]]; then
        ${PACKAGE_UPDATE[int]}
        ${PACKAGE_INSTALL[int]} sudo curl wget
        ${PACKAGE_INSTALL[int]} --no-install-recommends net-tools iproute2 openresolv dnsutils wireguard-tools iptables
    fi

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
    wget -N --no-check-certificate https://github.com/ViRb3/wgcf/releases/latest/download/wgcf_"$wgcf_last_version"_linux_$(archAffix) -O /usr/local/bin/wgcf || wget -N --no-check-certificate https://cdn.jsdelivr.net/gh/Misaka-blog/Misaka-WARP-Script/files/wgcf_2.2.14_linux_$(archAffix) -O /usr/local/bin/wgcf
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

    v66=`curl -s6m8 https://ip.gs -k`
    v44=`curl -s4m8 https://ip.gs -k`
    MTUy=1500
    MTUc=10
    if [[ -n ${v66} && -z ${v44} ]]; then
        ping='ping6'
        IP1='2606:4700:4700::1001'
        IP2='2001:4860:4860::8888'
    else
        ping='ping'
        IP1='1.1.1.1'
        IP2='8.8.8.8'
    fi
    while true; do
        if ${ping} -c1 -W1 -s$((${MTUy} - 28)) -Mdo ${IP1} >/dev/null 2>&1 || ${ping} -c1 -W1 -s$((${MTUy} - 28)) -Mdo ${IP2} >/dev/null 2>&1; then
            MTUc=1
            MTUy=$((${MTUy} + ${MTUc}))
        else
            MTUy=$((${MTUy} - ${MTUc}))
            if [[ ${MTUc} = 1 ]]; then
                break
            fi
        fi
        if [[ ${MTUy} -le 1360 ]]; then
            MTUy='1360'
            break
        fi
    done
    MTU=$((${MTUy} - 80))
    green "MTU 最佳值=$MTU 已设置完毕"
    sed -i "s/MTU.*/MTU = $MTU/g" wgcf-profile.conf

    if [[ $VPSIP == 0 ]]; then
        if [[ $wgcfmode == 0 ]]; then
            wgcf64
        fi
        if [[ $wgcfmode == 1 ]]; then
            wgcf66
        fi
        if [[ $wgcfmode == 2 ]]; then
            wgcf6d
        fi
    elif [[ $VPSIP == 1 ]]; then
        if [[ $wgcfmode == 0 ]]; then
            wgcf44
        fi
        if [[ $wgcfmode == 1 ]]; then
            wgcf46
        fi
        if [[ $wgcfmode == 2 ]]; then
            wgcf4d
        fi
    elif [[ $VPSIP == 2 ]]; then
        if [[ $wgcfmode == 0 ]]; then
            wgcfd4
        fi
        if [[ $wgcfmode == 1 ]]; then
            wgcfd6
        fi
        if [[ $wgcfmode == 2 ]]; then
            wgcfd
        fi
    fi
}

uninstall_wgcf(){
    wg-quick down wgcf 2>/dev/null
    systemctl disable wg-quick@wgcf 2>/dev/null
    ${PACKAGE_UNINSTALL[int]} wireguard-tools wireguard-dkms 2>/dev/null
    [[ -z $(type -P wireproxy) ]] && rm -f /usr/local/bin/wgcf 
    rm -f /etc/wireguard/wgcf.conf
    rm -f /etc/wireguard/wgcf-account.toml
    rm -f /usr/bin/wireguard-go
    if [[ -e /etc/gai.conf ]]; then
        sed -i '/^precedence[ ]*::ffff:0:0\/96[ ]*100/d' /etc/gai.conf
    fi
    green "Wgcf-WARP 已彻底卸载成功！"
}

install_warpcli(){
    check_tun
    if [[ $(archAffix) != "amd64" ]]; then
        red "不支持的CPU架构，请使用amd64架构的VPS"
        exit 1
    fi

    vsid=`grep -i version_id /etc/os-release | cut -d \" -f2 | cut -d . -f1`
    [[ $SYSTEM == "CentOS" ]] && [[ ! ${vsid} =~ 8 ]] && yellow "当前系统版本：Centos $vsid \nWARP-Cli代理模式仅支持Centos 8系统"
    [[ $SYSTEM == "Debian" ]] && [[ ! ${vsid} =~ 9|10|11 ]] && yellow "当前系统版本：Debian $vsid \nWARP-Cli代理模式仅支持Debian 9-11系统"
    [[ $SYSTEM == "Ubuntu" ]] && [[ ! ${vsid} =~ 16|18|20|22 ]] && yellow "当前系统版本：Ubuntu $vsid \nWARP-Cli代理模式仅支持Ubuntu 16.04/18.04/20.04/22.04系统"

    if [[ $SYSTEM == "CentOS" ]]; then
        ${PACKAGE_INSTALL[int]} epel-release
        ${PACKAGE_INSTALL[int]} net-tools
        rpm -ivh http://pkg.cloudflareclient.com/cloudflare-release-el$vsid.rpm
        ${PACKAGE_INSTALL[int]} cloudflare-warp
    fi
    if [[ $SYSTEM == "Debian" ]]; then
        ${PACKAGE_UPDATE[int]}
        ${PACKAGE_INSTALL[int]} lsb-release
        [[ -z $(type -P gpg 2>/dev/null) ]] && ${PACKAGE_INSTALL[int]} gnupg
        [[ -z $(apt list 2>/dev/null | grep apt-transport-https | grep installed) ]] && ${PACKAGE_INSTALL[int]} apt-transport-https
        curl https://pkg.cloudflareclient.com/pubkey.gpg | apt-key add -
        echo "deb http://pkg.cloudflareclient.com/ $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/cloudflare-client.list
        ${PACKAGE_UPDATE[int]}
        ${PACKAGE_INSTALL[int]} cloudflare-warp
    fi
    if [[ $SYSTEM == "Ubuntu" ]]; then
        ${PACKAGE_UPDATE[int]}
        ${PACKAGE_INSTALL[int]} lsb-release
        curl https://pkg.cloudflareclient.com/pubkey.gpg | apt-key add -
        echo "deb http://pkg.cloudflareclient.com/ $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/cloudflare-client.list
        ${PACKAGE_UPDATE[int]}
        ${PACKAGE_INSTALL[int]} cloudflare-warp
    fi

    warp-cli --accept-tos register >/dev/null 2>&1
    yellow "使用WARP免费版账户请按回车跳过 \n启用WARP+账户，请复制WARP+的许可证密钥(26个字符)后回车"
    read -p "按键许可证密钥(26个字符):" WPPlusKey
    if [[ -n $WPPlusKey ]]; then
        warp-cli --accept-tos set-license "$LICENSE" >/dev/null 2>&1 && sleep 1
        if [[ $(warp-cli --accept-tos account) =~ Limited ]]; then
            green "WARP+账户启用成功"
        else
            red "WARP+账户启用失败，即将使用WARP免费版账户"
        fi
    fi
    warp-cli --accept-tos set-mode proxy >/dev/null 2>&1

    read -p "请输入WARP Cli使用的代理端口（默认40000）：" WARPCliPort
    [[ -z $WARPCliPort ]] && WARPCliPort=40000
    warp-cli --accept-tos set-proxy-port "$WARPCliPort" >/dev/null 2>&1

    yellow "正在启动Warp-Cli代理模式"
    warp-cli --accept-tos connect >/dev/null 2>&1
    socks5Status=$(curl -sx socks5h://localhost:$WARPCliPort https://www.cloudflare.com/cdn-cgi/trace -k --connect-timeout 2 | grep warp | cut -d= -f2)
    until [[ $socks5Status =~ on|plus ]]; do
        red "启动Warp-Cli代理模式失败，正在尝试重启"
        warp-cli --accept-tos disconnect >/dev/null 2>&1
        warp-cli --accept-tos connect >/dev/null 2>&1
        socks5Status=$(curl -sx socks5h://localhost:$WARPCliPort https://www.cloudflare.com/cdn-cgi/trace -k --connect-timeout 2 | grep warp | cut -d= -f2)
        sleep 8
    done
    warp-cli --accept-tos enable-always-on >/dev/null 2>&1
    socks5IP=$(curl -sx socks5h://localhost:$WARPCliPort ip.gs -k --connect-timeout 8)
    green "WARP-Cli代理模式已启动成功！"
    yellow "本地Socks5代理为： 127.0.0.1:$WARPCliPort"
    yellow "WARP-Cli代理模式的IP为：$socks5IP"
}

uninstall_warpcli(){
    warp-cli --accept-tos disconnect >/dev/null 2>&1
    warp-cli --accept-tos disable-always-on >/dev/null 2>&1
    warp-cli --accept-tos delete >/dev/null 2>&1
    ${PACKAGE_UNINSTALL[int]} cloudflare-warp 2>/dev/null
    systemctl disable --now warp-svc >/dev/null 2>&1
    green "WARP-Cli代理模式已彻底卸载成功！"
}

menu(){
    check_status
    if [[ $VPSIP == 0 ]]; then
        menu0
    elif [[ $VPSIP == 1 ]]; then
        menu1
    elif [[ $VPSIP == 2 ]]; then
        menu2
    fi
}

menu0(){
    clear
    echo "#############################################################"
    echo -e "#                  ${RED} WARP  一键安装脚本${PLAIN}                      #"
    echo -e "# ${GREEN}作者${PLAIN}: Misaka No                                           #"
    echo -e "# ${GREEN}网址${PLAIN}: https://owo.misaka.rest                             #"
    echo -e "# ${GREEN}论坛${PLAIN}: https://vpsgo.co                                    #"
    echo -e "# ${GREEN}TG群${PLAIN}: https://t.me/misakanetcn                            #"
    echo "#############################################################"
    echo -e ""
    echo -e " ${GREEN}1.${PLAIN} 安装 Wgcf-WARP 单栈模式 ${YELLOW}(WARP IPv4 + 原生IPv6)${PLAIN}"
    echo -e " ${GREEN}2.${PLAIN} 安装 Wgcf-WARP 单栈模式 ${YELLOW}(WARP IPv6)${PLAIN}"
    echo -e " ${GREEN}3.${PLAIN} 安装 Wgcf-WARP 双栈模式 ${YELLOW}(WARP IPV4 + WARP IPv6)${PLAIN}"
    echo -e " ${GREEN}4.${PLAIN} ${RED}卸载 Wgcf-WARP${PLAIN}"
    echo -e " ${GREEN}0.${PLAIN} 退出脚本"
    echo -e ""
    echo -e "VPS IP特征：${RED}纯IPv6的VPS${PLAIN}"
    echo -e ""
    read -p " 请输入选项 [0-]:" menu0Input
    case "$menu0Input" in
        1 ) wgcfmode=0 && install_wgcf ;;
        2 ) wgcfmode=1 && install_wgcf ;;
        3 ) wgcfmode=2 && install_wgcf ;;
        4 ) uninstall_wgcf ;;
    esac
}

menu1(){
    clear
    echo "#############################################################"
    echo -e "#                  ${RED} WARP  一键安装脚本${PLAIN}                      #"
    echo -e "# ${GREEN}作者${PLAIN}: Misaka No                                           #"
    echo -e "# ${GREEN}网址${PLAIN}: https://owo.misaka.rest                             #"
    echo -e "# ${GREEN}论坛${PLAIN}: https://vpsgo.co                                    #"
    echo -e "# ${GREEN}TG群${PLAIN}: https://t.me/misakanetcn                            #"
    echo "#############################################################"
    echo -e " ${GREEN}1.${PLAIN} 安装 Wgcf-WARP 单栈模式 ${YELLOW}(WARP IPv4)${PLAIN}"
    echo -e " ${GREEN}2.${PLAIN} 安装 Wgcf-WARP 单栈模式 ${YELLOW}(原生 IPv4 + WARP IPv6)${PLAIN}"
    echo -e " ${GREEN}3.${PLAIN} 安装 Wgcf-WARP 双栈模式 ${YELLOW}(WARP IPV4 + WARP IPv6)${PLAIN}"
    echo -e " ${GREEN}4.${PLAIN} ${RED}卸载 Wgcf-WARP${PLAIN}"
    echo -e " ${GREEN}0.${PLAIN} 退出脚本"
    echo -e ""
    echo -e "VPS IP特征：${RED}纯IPv4的VPS${PLAIN}"
    echo -e ""
    read -p " 请输入选项 [0-]:" menu1Input
    case "$menu1Input" in
        1 ) wgcfmode=0 && install_wgcf ;;
        2 ) wgcfmode=1 && install_wgcf ;;
        3 ) wgcfmode=2 && install_wgcf ;;
        4 ) uninstall_wgcf ;;
    esac
}

menu2(){
    clear
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
    echo -e " ${GREEN}4.${PLAIN} ${RED}卸载 Wgcf-WARP${PLAIN}"
    echo -e " ${GREEN}0.${PLAIN} 退出脚本"
    echo -e ""
    echo -e "VPS IP特征：${RED}原生IP双栈的VPS${PLAIN}"
    echo -e ""
    read -p " 请输入选项 [0-]:" menu2Input
    case "$menu2Input" in
        1 ) wgcfmode=0 && install_wgcf ;;
        2 ) wgcfmode=1 && install_wgcf ;;
        3 ) wgcfmode=2 && install_wgcf ;;
        4 ) uninstall_wgcf ;;
    esac
}

if [[ $# > 0 ]]; then
    echo ""
else
    menu
fi