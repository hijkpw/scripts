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

[[ -z $SYSTEM ]] && red "不支持当前VPS的系统，请使用主流操作系统" && exit 1
[[ -z $(type -P wg-quick) ]] && red "未安装Wgcf-WARP，脚本即将退出" && rm -f switch.sh && exit 1

WgcfWARP4Status=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
WgcfWARP6Status=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)

downwpfree(){
    cd /etc/wireguard
    rm -f wgcf-account.toml
    until [[ -a wgcf-account.toml ]]; do
        yes | wgcf register
        sleep 5
    done
    chmod +x wgcf-account.toml
    wgcf generate
    chmod +x wgcf-profile.conf
    if [[ $WgcfWARP4Status =~ on|plus ]] || [[ $WgcfWARP6Status =~ on|plus ]]; then
        wg-quick down wgcf >/dev/null 2>&1
    fi
    wpfreepublickey=$(grep PublicKey wgcf-profile.conf | sed "s/PublicKey = //g")
    wpfreeprivatekey=$(grep PrivateKey wgcf-profile.conf | sed "s/PrivateKey = //g")
    sed -i "s#PublicKey.*#PublicKey = $wpfreepublickey#g" /etc/wireguard/wgcf.conf;
    sed -i "s#PrivateKey.*#PrivateKey = $wpfreeprivatekey#g" /etc/wireguard/wgcf.conf;
    rm -f wgcf-profile.conf
    yellow "正在启动 Wgcf-WARP"
    wg-quick up wgcf >/dev/null 2>&1
    WgcfWARP4Status=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    WgcfWARP6Status=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    until [[ $WgcfWARP4Status =~ on|plus ]] || [[ $WgcfWARP6Status =~ on|plus ]]; do
        red "无法启动Wgcf-WARP，正在尝试重启"
        wg-quick down wgcf >/dev/null 2>&1
        wg-quick up wgcf >/dev/null 2>&1
        WgcfWARP4Status=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
        WgcfWARP6Status=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
        sleep 8
    done
    green "Wgcf-WARP 已启动成功"
    systemctl enable wg-quick@wgcf >/dev/null 2>&1
}

upwpplus(){
    cd /etc/wireguard
    if [[ ! -f wgcf-account.toml ]]; then
        until [[ -a wgcf-account.toml ]]; do
            yes | wgcf register
            sleep 5
        done
    fi
    chmod +x wgcf-account.toml
    yellow "使用WARP+账户，请复制WARP+的许可证密钥(26个字符)后回车"
    read -p "按键许可证密钥(26个字符):" WPPlusKey
    [[ -z $WPPlusKey ]] && red "未输入许可证密钥，取消升级WARP+账户，脚本即将退出！" && exit 1
    sed -i "s/license_key.*/license_key = \"$WPPlusKey\"/g" wgcf-account.toml
    read -p "请输入自定义设备名，如未输入则使用默认随机设备名：" WPPlusName
    green "注册WARP+账户中，如下方显示：400 Bad Request，则使用WARP免费版账户" 
    if [[ -n $WPPlusName ]]; then
        wgcf update --name $(echo $WPPlusName | sed s/[[:space:]]/_/g)
    else
        wgcf update
    fi
    wgcf generate
    chmod +x wgcf-profile.conf
    if [[ $WgcfWARP4Status =~ on|plus ]] || [[ $WgcfWARP6Status =~ on|plus ]]; then
        wg-quick down wgcf >/dev/null 2>&1
    fi
    wppluspublickey=$(grep PublicKey wgcf-profile.conf | sed "s/PublicKey = //g")
    wpplusprivatekey=$(grep PrivateKey wgcf-profile.conf | sed "s/PrivateKey = //g")
    sed -i "s#PublicKey.*#PublicKey = $wppluspublickey#g" /etc/wireguard/wgcf.conf;
    sed -i "s#PrivateKey.*#PrivateKey = $wpplusprivatekey#g" /etc/wireguard/wgcf.conf;
    rm -f wgcf-profile.conf
    yellow "正在启动 Wgcf-WARP"
    wg-quick up wgcf >/dev/null 2>&1
    WgcfWARP4Status=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    WgcfWARP6Status=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    until [[ $WgcfWARP4Status =~ on|plus ]] || [[ $WgcfWARP6Status =~ on|plus ]]; do
        red "无法启动Wgcf-WARP，正在尝试重启"
        wg-quick down wgcf >/dev/null 2>&1
        wg-quick up wgcf >/dev/null 2>&1
        WgcfWARP4Status=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
        WgcfWARP6Status=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
        sleep 8
    done
    green "Wgcf-WARP 已启动成功"
    systemctl enable wg-quick@wgcf >/dev/null 2>&1
}

upgradeTeam(){
    read -p "请输入WARP Teams PublicKey：" wpteampublickey
    read -p "请输入WARP Teams PrivateKey：" wpteamprivatekey
    read -p "请输入WARP Teams IPv4地址：" wpteamv4address
    read -p "请输入WARP Teams IPv6地址：" wpteamv6address
    read -p "请输入WARP Teams EndPoint：" wpteamendpoint
    echo ""
    yellow "请确认WARP Teams信息是否正确："
    green "PublicKey: $wpteampublickey"
    green "PrivateKey: $wpteamprivatekey"
    green "IPv4 地址: $wpteamv4address"
    green "IPv6 地址: $wpteamv6address"
    green "EndPoint: $wpteamendpoint"
    read -p "确认请输入y，其他按键退出升级过程：" wpteamconfirm
    if [ $wpteamconfirm == "y" ]; then
        if [[ $WgcfWARP4Status =~ on|plus ]] || [[ $WgcfWARP6Status =~ on|plus ]]; then
            wg-quick down wgcf >/dev/null 2>&1
        fi
        sed -i "s#PublicKey.*#PublicKey = $wpteampublickey#g" /etc/wireguard/wgcf.conf;
        sed -i "s#PrivateKey.*#PrivateKey = $wpteamprivatekey#g" /etc/wireguard/wgcf.conf;
        sed -i "s#Address.*32#Address = $wpteamv4address/32#g" /etc/wireguard/wgcf.conf;
        sed -i "s#Address.*128#Address = $wpteamv6address/128#g" /etc/wireguard/wgcf.conf;
        sed -i "s#EndPoint.*#Address = $wpteamendpoint#g" /etc/wireguard/wgcf.conf;
        yellow "正在启动 Wgcf-WARP"
        wg-quick up wgcf >/dev/null 2>&1
        WgcfWARP4Status=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
        WgcfWARP6Status=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
        until [[ $WgcfWARP4Status =~ on|plus ]] || [[ $WgcfWARP6Status =~ on|plus ]]; do
            red "无法启动Wgcf-WARP，正在尝试重启"
            wg-quick down wgcf >/dev/null 2>&1
            wg-quick up wgcf >/dev/null 2>&1
            WgcfWARP4Status=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
            WgcfWARP6Status=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
            sleep 8
        done
        green "Wgcf-WARP 已启动成功"
        systemctl enable wg-quick@wgcf >/dev/null 2>&1
    fi
}

menu(){
    yellow "请输入你想要切换的Wgcf-WARP账号类型："
    green "1. WARP 免费版账户"
    green "2. WARP+"
    green "3. WARP Teams"
    read -p "请输入选项 [1-3]：" menuNumberInput
    case "$menuNumberInput" in
        1 ) downwpfree ;;
        2 ) upwpplus ;;
        3 ) upgradeTeam ;;
        * ) red "输入无效！脚本即将退出" && exit 1 ;;
    esac
}

menu