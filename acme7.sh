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
    if [[ -z $ipv4 ]]; then
        echo -e nameserver 2a01:4f8:c2c:123f::1 > /etc/resolv.conf
        yellow "检测到VPS为IPv6 Only，已自动设置为DNS64服务器"
    fi
}

back2menu() {
    green "所选操作执行完成"
    read -p "请输入“y”退出，或按任意键回到主菜单：" back2menuInput
    case "$back2menuInput" in
        y) exit 1 ;;
        *) menu ;;
    esac
}

checkwarp(){
    WARPv4Status=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    WARPv6Status=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    if [[ $WARPv4Status =~ on|plus || $WARPv6Status =~ on|plus ]]; then
        wg-quick down wgcf >/dev/null 2>&1
        yellow "检测到Wgcf-WARP已启动，为确保正常申请证书已暂时关闭"
    fi
}

install_acme(){
    ${PACKAGE_UPDATE[int]}
    [[ -z $(type -P curl) ]] && ${PACKAGE_INSTALL[int]} curl
    [[ -z $(type -P wget) ]] && ${PACKAGE_INSTALL[int]} wget
    [[ -z $(type -P socat) ]] && ${PACKAGE_INSTALL[int]} socat
    [[ -z $(type -P cron) && $SYSTEM =~ Debian|Ubuntu ]] && ${PACKAGE_INSTALL[int]} cron && systemctl start cron systemctl enable cron
    [[ -z $(type -P crond) && $SYSTEM == CentOS ]] && ${PACKAGE_INSTALL[int]} cronie && systemctl start crond && systemctl enable crond
    read -p "请输入注册邮箱（例：admin@misaka.rest，或留空自动生成）：" acmeEmail
    [[ -z $acmeEmail ]] && autoEmail=$(date +%s%N | md5sum | cut -c 1-32) && acmeEmail=$autoEmail@gmail.com
    curl https://get.acme.sh | sh -s email=$acmeEmail
    source ~/.bashrc
    bash ~/.acme.sh/acme.sh --upgrade --auto-upgrade
    if [[ -n $(~/.acme.sh/acme.sh -v 2>/dev/null) ]]; then
        green "Acme.sh证书申请脚本安装成功！"
    else
        red "抱歉，Acme.sh证书申请脚本安装失败"
        green "建议如下："
        yellow "1. 检查VPS的网络环境，如为IPv6 Only的VPS请自行添加WARP或DNS64以安装Acme.sh"
        yellow "2. GitHub上游可能出了一些问题，请过一会儿再试"
        yellow "3. 脚本可能跟不上时代，建议截图发布到GitHub Issues或TG群询问"
    fi
    back2menu
}

getSingleCert(){
    [[ -z $(~/.acme.sh/acme.sh -v 2>/dev/null) ]] && red "未安装acme.sh，无法执行操作" && exit 1
    checkwarp
    # adddns64
    ipv4=$(curl -s4m8 https://ip.gs)
    ipv6=$(curl -s6m8 https://ip.gs)
    read -p "请输入解析完成的域名:" domain
    [[ -z $domain ]] && red "未输入域名，无法执行操作！" && exit 1
    green "已输入的域名：$domain" && sleep 1
    domainIP=$(curl -s ipget.net/?ip="cloudflare.1.1.1.1.$domain")
    if [[ -n $(echo $domainIP | grep nginx) ]]; then
        domainIP=$(curl -s ipget.net/?ip="$domain")
        if [[ $domainIP == $ipv6 ]]; then
            bash ~/.acme.sh/acme.sh --issue -d ${domain} --standalone -k ec-256 --server zerossl --listen-v6
        fi
        if [[ $domainIP == $ipv4 ]]; then
            bash ~/.acme.sh/acme.sh --issue -d ${domain} --standalone -k ec-256 --server zerossl
        fi

        if [[ -n $(echo $domainIP | grep nginx) ]]; then
            yellow "域名解析无效，请检查域名是否填写正确或稍等几分钟等待解析完成再执行脚本"
            exit 1
        elif [[ -n $(echo $domainIP | grep ":") || -n $(echo $domainIP | grep ".") ]]; then
            if [[ $domainIP != $ipv4 ]] && [[ $domainIP != $ipv6 ]]; then
                green "${domain} 解析结果：（$domainIP）"
                red "当前二级域名解析的IP与当前VPS使用的IP不匹配"
                green "建议如下："
                yellow "1. 请确保Cloudflare小云朵为关闭状态(仅限DNS)，其他域名解析网站设置同理"
                yellow "2. 请检查DNS解析设置的IP是否为VPS的IP"
                yellow "3. 脚本可能跟不上时代，建议截图发布到GitHub Issues或TG群询问"
                exit 1
            fi
        fi
    fi
    bash ~/.acme.sh/acme.sh --install-cert -d ${domain} --key-file /root/private.key --fullchain-file /root/cert.crt --ecc
    checktls
}

getDomainCert(){
    [[ -z $(~/.acme.sh/acme.sh -v 2>/dev/null) ]] && red "未安装acme.sh，无法执行操作" && exit 1
    checkwarp
    adddns64
    ipv4=$(curl -s4m8 https://ip.gs)
    ipv6=$(curl -s6m8 https://ip.gs)
    read -p "请输入需要申请证书的泛域名（输入格式：example.com）：" domain
    [[ -z $domain ]] && red "未输入域名，无法执行操作！" && exit 1
    read -p "请输入Cloudflare Global API Key：" GAK
    [[ -z $GAK ]] && red "未输入Cloudflare Global API Key，无法执行操作！" && exit 1
    export CF_Key="$GAK"
    read -p "请输入Cloudflare的登录邮箱：" CFemail
    [[ -z $domain ]] && red "未输入Cloudflare的登录邮箱，无法执行操作！" && exit 1
    export CF_Email="$CFemail"
    if [[ -z $ipv4 ]]; then
        bash ~/.acme.sh/acme.sh --issue --dns dns_cf -d "*.${domain}" -d "${domain}" -k ec-256 --server zerossl --listen-v6
    else
        bash ~/.acme.sh/acme.sh --issue --dns dns_cf -d "*.${domain}" -d "${domain}" -k ec-256 --server zerossl
    fi
    bash ~/.acme.sh/acme.sh --install-cert -d "*.${domain}" --key-file /root/private.key --fullchain-file /root/cert.crt --ecc
    checktls
}

getSingleDomainCert(){
    [[ -z $(~/.acme.sh/acme.sh -v 2>/dev/null) ]] && red "未安装acme.sh，无法执行操作" && exit 1
    checkwarp
    adddns64
    ipv4=$(curl -s4m8 https://ip.gs)
    ipv6=$(curl -s6m8 https://ip.gs)
    read -p "请输入需要申请证书的域名：" domain
    read -p "请复制Cloudflare的Global API Key：" GAK
    [[ -z $GAK ]] && red "未输入Cloudflare Global API Key，无法执行操作！" && exit 1
    export CF_Key="$GAK"
    read -p "请输入登录Cloudflare的注册邮箱地址：" CFemail
    [[ -z $domain ]] && red "未输入Cloudflare的登录邮箱，无法执行操作！" && exit 1
    export CF_Email="$CFemail"
    if [[ -z $ipv4 ]]; then
        bash ~/.acme.sh/acme.sh --issue --dns dns_cf -d "${domain}" -k ec-256 --server zerossl --listen-v6
    else
        bash ~/.acme.sh/acme.sh --issue --dns dns_cf -d "${domain}" -k ec-256 --server zerossl
    fi
    bash ~/.acme.sh/acme.sh --install-cert -d "${domain}" --key-file /root/private.key --fullchain-file /root/cert.crt --ecc
    checktls
}

checktls() {
    if [[ -f /root/cert.crt && -f /root/private.key ]]; then
        if [[ -s /root/cert.crt && -s /root/private.key ]]; then
            sed -i '/--cron/d' /etc/crontab >/dev/null 2>&1
            echo "0 0 * * * root bash /root/.acme.sh/acme.sh --cron -f >/dev/null 2>&1" >> /etc/crontab
            if [[ -n $(type -P wgcf) ]]; then
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
                systemctl enable wg-quick@wgcf >/dev/null 2>&1
                green "Wgcf-WARP 已启动成功"
            fi
            green "证书申请成功！脚本申请到的证书（cert.crt）和私钥（private.key）已保存到 /root 文件夹"
            yellow "证书crt路径如下：/root/cert.crt"
            yellow "私钥key路径如下：/root/private.key"
            back2menu
        else
            if [[ -n $(type -P wgcf) ]]; then
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
                systemctl enable wg-quick@wgcf >/dev/null 2>&1
                green "Wgcf-WARP 已启动成功"
            fi
            red "抱歉，证书申请失败"
            green "建议如下："
            yellow "1. 自行检测防火墙是否打开，如使用80端口申请模式时，请关闭防火墙或放行80端口"
            yellow "2. 在使用CF API申请模式时，如果使用Freenom域名，由于API限制，暂时不能使用此方式申请"
            yellow "3. 同一域名多次申请触发Acme.sh官方风控，请更换域名或等待7天后再尝试执行脚本"
            yellow "4. 脚本可能跟不上时代，建议截图发布到GitHub Issues或TG群询问"
            back2menu
        fi
    fi
}

revoke_cert() {
    [[ -z $(~/.acme.sh/acme.sh -v 2>/dev/null) ]] && yellow "未安装acme.sh，无法执行操作" && exit 1
    bash ~/.acme.sh/acme.sh --list
    read -p "请输入要撤销的域名证书（复制Main_Domain下显示的域名）:" domain
    [[ -z $domain ]] && red "未输入域名，无法执行操作！" && exit 1
    if [[ -n $(bash ~/.acme.sh/acme.sh --list | grep $domain) ]]; then
        bash ~/.acme.sh/acme.sh --revoke -d ${domain} --ecc
        bash ~/.acme.sh/acme.sh --remove -d ${domain} --ecc
        rm -rf ~/.acme.sh/${domain}_ecc
        green "撤销${domain}的域名证书成功"
        back2menu
    else
        red "未找到你输入的${domain}域名证书，请自行检查！"
        back2menu
    fi
}

renew_cert() {
    [[ -z $(~/.acme.sh/acme.sh -v 2>/dev/null) ]] && yellow "未安装acme.sh，无法执行操作" && exit 1
    bash ~/.acme.sh/acme.sh --list
    read -p "请输入要续期的域名证书（复制Main_Domain下显示的域名）:" domain
    [[ -z $domain ]] && red "未输入域名，无法执行操作！" && exit 1
    if [[ -n $(bash ~/.acme.sh/acme.sh --list | grep $domain) ]]; then
        checkwarp
        adddns64
        bash ~/.acme.sh/acme.sh --renew -d ${domain} --force --ecc
        checktls
        back2menu
    else
        red "未找到你输入的${domain}域名证书，请再次检查域名输入正确"
        back2menu
    fi
}

uninstall() {
    [[ -z $(~/.acme.sh/acme.sh -v 2>/dev/null) ]] && yellow "未安装acme.sh无法执行" && exit 1
    curl https://get.acme.sh | sh
    ~/.acme.sh/acme.sh --uninstall
    sed -i '/--cron/d' /etc/crontab >/dev/null 2>&1
    rm -rf ~/.acme.sh
    rm -f acme1key.sh
    back2menu
}

menu() {
    clear
    red "=================================="
    echo "                           "
    red "    Acme.sh 域名证书一键申请脚本     "
    red "          by 小御坂的破站           "
    echo "                           "
    red "  Site: https://owo.misaka.rest  "
    echo "                           "
    red "=================================="
    echo "                           "
    green "1. 安装Acme.sh域名证书申请脚本"
    green "2. 申请单域名证书（80端口申请）"
    green "3. 申请单域名证书（CF API申请）"
    green "4. 申请泛域名证书（CF API申请）"
    green "5. 撤销并删除已申请的证书"
    green "6. 手动续期域名证书"
    green "7. 卸载Acme.sh域名证书申请脚本"
    green "0. 退出"
    echo "         "
    read -p "请输入数字:" NumberInput
    case "$NumberInput" in
        1) install_acme ;;
        2) getSingleCert ;;
        3) getSingleDomainCert ;;
        4) getDomainCert ;;
        5) revoke_cert ;;
        6) renew_cert ;;
        7) uninstall ;;
        *) exit 1 ;;
    esac
}

menu
