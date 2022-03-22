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

[[ -z $SYSTEM ]] && red "不支持当前VPS系统，请使用主流的操作系统" && exit 1

adddns64(){
    ipv4=$(curl -s4m8 https://ip.gs)
    ipv6=$(curl -s6m8 https://ip.gs)
    if [ -z $ipv4 ]; then
        echo -e nameserver 2a01:4f8:c2c:123f::1 > /etc/resolv.conf
    fi
}

checkwarp(){
    WARPv4Status=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    WARPv6Status=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    if [[ $WARPv4Status =~ on|plus || $WARPv6Status =~ on|plus ]]; then
        wg-quick down wgcf >/dev/null 2>&1
    fi
}

install_acme(){
    ${PACKAGE_UPDATE[int]}
    [[ -z $(type -P curl) ]] && ${PACKAGE_INSTALL[int]} curl
    [[ -z $(type -P wget) ]] && ${PACKAGE_INSTALL[int]} wget
    [[ -z $(type -P socat) ]] && ${PACKAGE_INSTALL[int]} socat
    read -p "请输入注册邮箱（例：admin@misaka.rest，或留空自动生成）：" acmeEmail
    [ -z $acmeEmail ] && autoEmail=$(date +%s%N | md5sum | cut -c 1-32) && acmeEmail=$autoEmail@gmail.com
    curl https://get.acme.sh | sh -s email=$acmeEmail
    source ~/.bashrc
    bash ~/.acme.sh/acme.sh --upgrade --auto-upgrade
}

getCert(){
    [[ -z $(~/.acme.sh/acme.sh -v) ]] && yellow "未安装acme.sh，无法执行操作" && exit 1
    checkwarp
    ipv4=$(curl -s4m8 https://ip.gs)
    ipv6=$(curl -s6m8 https://ip.gs)
    read -p "请输入解析完成的域名:" domain
    green "已输入的域名:$domain" && sleep 1
    domainIP=$(curl -s ipget.net/?ip="cloudflare.1.1.1.1.$domain")
    if [[ -n $(echo $domainIP | grep nginx) ]]; then
        domainIP=$(curl -s ipget.net/?ip="$domain")
        if [[ $domainIP == $ipv4 ]]; then
            yellow "当前二级域名解析到的IPV4：$domainIP" && sleep 1
            bash ~/.acme.sh/acme.sh --issue -d ${domain} --standalone -k ec-256 --server letsencrypt
        fi
        if [[ $domainIP == $ipv6 ]]; then
            yellow "当前二级域名解析到的IPV6：$domainIP" && sleep 1
            bash ~/.acme.sh/acme.sh --issue -d ${domain} --standalone -k ec-256 --server letsencrypt --listen-v6
        fi

        if [[ -n $(echo $domainIP | grep nginx) ]]; then
            yellow "域名解析无效，请检查二级域名是否填写正确或稍等几分钟等待解析完成再执行脚本"
        elif [[ -n $(echo $domainIP | grep ":") || -n $(echo $domainIP | grep ".") ]]; then
            if [[ $domainIP != $v4 ]] && [[ $domainIP != $v6 ]]; then
                red "当前二级域名解析的IP与当前VPS使用的IP不匹配"
                green "建议如下："
                yellow "1、请确保Cloudflare小黄云关闭状态(仅限DNS)，其他域名解析网站设置同理"
                yellow "2、请检查域名解析网站设置的IP是否正确"
            fi
        fi
    else
        green "经检测，当前为泛域名申请证书模式，目前脚本仅支持Cloudflare的DNS申请方式"
        readp "请复制Cloudflare的Global API Key:" GAK
        export CF_Key="$GAK"
        readp "请输入登录Cloudflare的注册邮箱地址:" CFemail
        export CF_Email="$CFemail"
        if [[ $domainIP == $ipv4 ]]; then
            yellow "当前泛域名解析到的IPV4：$domainIP" && sleep 1
            bash ~/.acme.sh/acme.sh --issue --dns dns_cf -d ${domain} -d *.${domain} -k ec-256 --server letsencrypt
        fi
        if [[ $domainIP == $ipv6 ]]; then
            yellow "当前泛域名解析到的IPV6：$domainIP" && sleep 1
            bash ~/.acme.sh/acme.sh --issue --dns dns_cf -d ${domain} -d *.${domain} -k ec-256 --server letsencrypt --listen-v6
        fi
    fi
    bash ~/.acme.sh/acme.sh --install-cert -d ${domain} --key-file /root/private.key --fullchain-file /root/cert.crt --ecc
}

checktls() {
    if [[ -f /root/cert.crt && -f /root/private.key ]]; then
        if [[ -s /root/cert.crt && -s /root/private.key ]]; then
            sed -i '/--cron/d' /etc/crontab >/dev/null 2>&1
            echo "0 0 * * * root bash /root/.acme.sh/acme.sh --cron -f >/dev/null 2>&1" >> /etc/crontab
            green "证书申请成功！证书（cert.crt）和私钥（private.key）已保存到 /root 文件夹"
            yellow "证书crt路径如下：/root/cert.crt"
            yellow "私钥key路径如下：/root/private.key"
            exit 1
        else
            red "抱歉，证书申请失败"
            green "建议如下："
            yellow "1. 检测防火墙是否打开，如打开请关闭防火墙或放行80端口"
            yellow "2. 检查80端口是否开放或占用"
            yellow "3. 域名触发Acme.sh官方风控，更换域名或等待7天后再尝试执行脚本"
            yellow "4. 脚本可能跟不上时代，建议截图发布到TG群询问"
            exit 1
        fi
    fi
}

certificate() {
	[[ -z $(~/.acme.sh/acme.sh -v 2>/dev/null) ]] && yellow "未安装acme.sh，无法执行操作" && exit 1
	bash ~/.acme.sh/acme.sh --list
	read -p "请输入要撤销的域名证书（复制Main_Domain下显示的域名）:" domain
	if [[ -n $(bash ~/.acme.sh/acme.sh --list | grep $domain) ]]; then
		bash ~/.acme.sh/acme.sh --revoke -d ${domain} --ecc
		bash ~/.acme.sh/acme.sh --remove -d ${domain} --ecc
		green "撤销并删除${domain}域名证书成功"
		exit 1
	else
		red "未找到你输入的${domain}域名证书，请自行检查！"
		exit 1
	fi
}

acmerenew() {
    [[ -z $(~/.acme.sh/acme.sh -v 2>/dev/null) ]] && yellow "未安装acme.sh，无法执行操作" && exit 1
    bash ~/.acme.sh/acme.sh --list
    read -p "请输入要续期的域名证书（复制Main_Domain下显示的域名）:" domain
    if [[ -n $(bash ~/.acme.sh/acme.sh --list | grep $domain) ]]; then
        checkwarp
        bash ~/.acme.sh/acme.sh --renew -d ${domain} --force --ecc
        checktls
        exit 1
    else
        red "未找到你输入的${domain}域名证书，请再次检查域名输入正确"
        exit 1
    fi
}

install(){
    checkwarp
    adddns64
    install_acme
    getCert
}

uninstall() {
	[[ -z $(~/.acme.sh/acme.sh -v 2>/dev/null) ]] && yellow "未安装acme.sh无法执行" && exit 1
    curl https://get.acme.sh | sh
	~/.acme.sh/acme.sh --uninstall
    sed -i '/--cron/d' /etc/crontab >/dev/null 2>&1
	rm -rf ~/.acme.sh
	rm -f acme1key.sh
}