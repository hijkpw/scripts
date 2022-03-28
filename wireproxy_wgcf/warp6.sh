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
[[ -n $(type -P wireproxy) ]] && red "WireProxy-WARP代理模式已经安装，脚本即将退出" && rm -f warp4d.sh && exit 1

arch=`uname -m`
main=`uname  -r | awk -F . '{print $1}'`
minor=`uname -r | awk -F . '{print $2}'`
vpsvirt=`systemd-detect-virt`

check_tun(){
    TUN=$(cat /dev/net/tun 2>&1 | tr '[:upper:]' '[:lower:]')
    [[ ! $TUN =~ 'in bad state' ]] && [[ ! $TUN =~ '处于错误状态' ]] && [[ ! $TUN =~ 'Die Dateizugriffsnummer ist in schlechter Verfassung' ]] && red "检测到未开启TUN模块，请到VPS控制面板处开启" && exit 1
}

install_wgcf(){
    if [[ $arch == "amd64" || $arch == "x86_64" ]]; then
        wget -N https://cdn.jsdelivr.net/gh/Misaka-blog/Misaka-WARP-Script/wgcf_2.2.12_linux_amd64 -O /usr/local/bin/wgcf
        chmod +x /usr/local/bin/wgcf
    fi
    if [[ $arch == "armv8" || $arch == "arm64" || $arch == "aarch64" ]]; then
        wget -N https://cdn.jsdelivr.net/gh/Misaka-blog/Misaka-WARP-Script/wgcf_2.2.12_linux_arm64 -O /usr/local/bin/wgcf
        chmod +x /usr/local/bin/wgcf
    fi
    if [[ $arch == "s390x" ]]; then
        wget -N https://cdn.jsdelivr.net/gh/Misaka-blog/Misaka-WARP-Script/wgcf_2.2.12_linux_s390x -O /usr/local/bin/wgcf
        chmod +x /usr/local/bin/wgcf
    fi
}

register_wgcf(){
    rm -f wgcf-account.toml
    until [[ -a wgcf-account.toml ]]; do
        yes | wgcf register
        sleep 5
    done
    chmod +x wgcf-account.toml
}

generate_wgcf_config(){
    yellow "使用WARP免费版账户请按回车跳过 \n启用WARP+账户，请复制WARP+的许可证密钥(26个字符)后回车"
    read -p "按键许可证密钥(26个字符):" WPPlusKey
    if [[ -n $WPPlusKey ]]; then
        sed -i "s/license_key.*/license_key = \"$WPPlusKey\"/g" wgcf-account.toml
        wgcf update
        green "注册WARP+账户中，如上方显示：400 Bad Request，则使用WARP免费版账户" 
    fi
    wgcf generate
    chmod +x wgcf-profile.conf
}

make_wireproxy_file(){
    read -p "请输入将要设置的Socks5端口（默认40000）：" WireProxyPort
    [[ -z $WireProxyPort ]] && WireProxyPort=40000
    WgcfPrivateKey=$(grep PrivateKey wgcf-profile.conf | sed "s/PrivateKey = //g")
    WgcfPublicKey=$(grep PublicKey wgcf-profile.conf | sed "s/PublicKey = //g")
    cat <<EOF > ~/WireProxy_WARP.conf
SelfSecretKey = $WgcfPrivateKey
SelfEndpoint = 172.16.0.2
PeerPublicKey = $WgcfPublicKey
PeerEndpoint = [2606:4700:d0::a29f:c001]:2408
DNS = 1.1.1.1,8.8.8.8,8.8.4.4

[Socks5]
BindAddress = 127.0.0.1:$WireProxyPort
EOF
    green "WireProxy-WARP代理模式配置文件已生成成功！"
    yellow "已保存到 /root/WireProxy_WARP.conf"
    cat <<'TEXT' > /etc/systemd/system/wireproxy-warp.service
[Unit]
Description=CloudFlare WARP based for WireProxy, script by owo.misaka.rest
After=network.target
[Install]
WantedBy=multi-user.target
[Service]
Type=simple
WorkingDirectory=/root
ExecStart=/usr/local/bin/wireproxy /root/WireProxy_WARP.conf
Restart=always
TEXT
    green "Systemd 系统守护服务设置成功！"
    rm -f wgcf-profile.conf
    rm -f wgcf-account.toml
}

download_wireproxy(){
    if [[ $arch == "amd64" || $arch == "x86_64" ]]; then
        wget -N https://cdn.jsdelivr.net/gh/Misaka-blog/Misaka-WARP-Script/wireproxy-amd64 -O /usr/local/bin/wireproxy
        chmod +x /usr/local/bin/wireproxy
    fi
    if [[ $arch == "armv8" || $arch == "arm64" || $arch == "aarch64" ]]; then
        wget -N https://cdn.jsdelivr.net/gh/Misaka-blog/Misaka-WARP-Script/wireproxy-arm64 -O /usr/local/bin/wireproxy
        chmod +x /usr/local/bin/wireproxy
    fi
    if [[ $arch == "s390x" ]]; then
        wget -N https://cdn.jsdelivr.net/gh/Misaka-blog/Misaka-WARP-Script/wireproxy-s390x -O /usr/local/bin/wireproxy
        chmod +x /usr/local/bin/wireproxy
    fi
}

start_wireproxy_warp(){
    yellow "正在启动WireProxy-WARP代理模式"
    systemctl start wireproxy-warp
    socks5Status=$(curl -sx socks5h://localhost:$WireProxyPort https://www.cloudflare.com/cdn-cgi/trace -k --connect-timeout 8 | grep warp | cut -d= -f2)
    until [[ $socks5Status =~ on|plus ]]; do
        red "启动WireProxy-WARP代理模式失败，正在尝试重启"
        systemctl stop wireproxy-warp
        systemctl start wireproxy-warp
        socks5Status=$(curl -sx socks5h://localhost:$WireProxyPort https://www.cloudflare.com/cdn-cgi/trace -k --connect-timeout 8 | grep warp | cut -d= -f2)
        sleep 8
    done
    systemctl enable wireproxy-warp
    green "WireProxy-WARP代理模式已启动成功！"
    yellow "本地Socks5代理为： 127.0.0.1:$WireProxyPort"
}

install(){
    ${PACKAGE_UPDATE[int]}
    [[ -z $(type -P curl) ]] && ${PACKAGE_INSTALL[int]} curl
    [[ -z $(type -P sudo) ]] && ${PACKAGE_INSTALL[int]} sudo
    check_tun
    install_wgcf
    register_wgcf
    generate_wgcf_config
    make_wireproxy_file
    download_wireproxy
    start_wireproxy_warp
}

install