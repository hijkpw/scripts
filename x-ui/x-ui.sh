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

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'

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

os_version=$(grep -i version_id /etc/os-release | cut -d \" -f2 | cut -d . -f1)

if [[ $SYSTEM == "CentOS" ]]; then
    if [[ ${os_version} -le 6 ]]; then
        red "请使用 CentOS 7 或更高版本的系统！\n" && exit 1
    fi
elif [[ $SYSTEM == "Ubuntu" ]]; then
    if [[ ${os_version} -lt 16 ]]; then
        red "请使用 Ubuntu 16 或更高版本的系统！\n" && exit 1
    fi
elif [[ $SYSTEM == "Debian" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        red "请使用 Debian 8 或更高版本的系统！\n" && exit 1
    fi
fi

confirm() {
    if [[ $# > 1 ]]; then
        echo && read -p "$1 [默认$2]: " temp
        if [[ x"${temp}" == x"" ]]; then
            temp=$2
        fi
    else
        read -p "$1 [y/n]: " temp
    fi
    if [[ x"${temp}" == x"y" || x"${temp}" == x"Y" ]]; then
        return 0
    else
        return 1
    fi
}

confirm_restart() {
    confirm "是否重启X-ui面板，重启面板也会重启xray" "y"
    if [[ $? == 0 ]]; then
        restart
    else
        show_menu
    fi
}

before_show_menu() {
    echo && echo -n -e "${YELLOW}按回车键返回主菜单: ${PLAIN}" && read temp
    show_menu
}

install() {
    bash <(curl -Ls https://raw.githubusercontents.com/Misaka-blog/x-ui/master/install.sh)
    if [[ $? == 0 ]]; then
        if [[ $# == 0 ]]; then
            start
        else
            start 0
        fi
    fi
}

update() {
    confirm "本功能会强制重装当前最新版X-ui面板，数据不会丢失，是否继续?" "n"
    if [[ $? != 0 ]]; then
        red "已取消"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 0
    fi
    bash <(curl -Ls https://raw.githubusercontents.com/Misaka-blog/x-ui/master/install.sh)
    if [[ $? == 0 ]]; then
        green "更新完成，已自动重启面板 "
        exit 0
    fi
}

uninstall() {
    confirm "确定要卸载X-ui面板吗，xray 也会卸载?" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    systemctl stop x-ui
    systemctl disable x-ui
    rm /etc/systemd/system/x-ui.service -f
    systemctl daemon-reload
    systemctl reset-failed
    rm /etc/x-ui/ -rf
    rm /usr/local/x-ui/ -rf

    echo ""
    echo -e "卸载X-ui面板成功"
    echo ""
    rm /usr/bin/x-ui -f

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

reset_user() {
    confirm "确定要将面板用户名和密码重置为 admin 吗" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    /usr/local/x-ui/x-ui setting -username admin -password admin
    echo -e "面板用户名和密码已重置为 ${GREEN}admin${PLAIN}，现在请重启面板"
    confirm_restart
}

reset_config() {
    confirm "确定要重置所有设置吗，账号数据不会丢失，用户名和密码不会改变" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    /usr/local/x-ui/x-ui setting -reset
    echo -e "所有面板设置已重置为默认值，请重启面板并使用默认的 ${GREEN}54321${PLAIN} 端口访问面板"
    confirm_restart
}

set_port() {
    echo && echo -n -e "输入端口号[1-65535]: " && read port
    if [[ -z "${port}" ]]; then
        yellow "已取消"
        before_show_menu
    else
        /usr/local/x-ui/x-ui setting -port ${port}
        echo -e "设置端口完毕，请重启面板并使用新设置的端口 ${GREEN}${port}${PLAIN} 访问面板"
        confirm_restart
    fi
}

start() {
    check_status
    if [[ $? == 0 ]]; then
        echo ""
        green "X-ui面板已运行，无需再次启动，如需重启请选择重启"
    else
        systemctl start x-ui
        sleep 2
        check_status
        if [[ $? == 0 ]]; then
            green "X-ui 面板启动成功"
        else
            red "X-ui 面板启动失败，可能是因为启动时间超过了两秒，请稍后查看日志信息"
        fi
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

stop() {
    check_status
    if [[ $? == 1 ]]; then
        echo ""
        green "X-ui 面板已停止，无需再次停止"
    else
        systemctl stop x-ui
        sleep 2
        check_status
        if [[ $? == 1 ]]; then
            green "X-ui 与 xray 停止成功"
        else
            red "X-ui 面板停止失败，可能是因为停止时间超过了两秒，请稍后查看日志信息"
        fi
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

restart() {
    systemctl restart x-ui
    sleep 2
    check_status
    if [[ $? == 0 ]]; then
        green "X-ui 与 xray 重启成功"
    else
        red "X-ui 面板重启失败，可能是因为启动时间超过了两秒，请稍后查看日志信息"
    fi
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

status() {
    systemctl status x-ui -l
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

enable_xui() {
    systemctl enable x-ui
    if [[ $? == 0 ]]; then
        green "X-ui 设置开机自启成功"
    else
        red "X-ui 设置开机自启失败"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

disable_xui() {
    systemctl disable x-ui
    if [[ $? == 0 ]]; then
        green "X-ui 取消开机自启成功"
    else
        red "X-ui 取消开机自启失败"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

show_log() {
    journalctl -u x-ui.service -e --no-pager -f
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

migrate_v2_ui() {
    /usr/local/x-ui/x-ui v2-ui

    before_show_menu
}

install_bbr() {
    # temporary workaround for installing bbr
    bash <(curl -L -s https://raw.githubusercontents.com/teddysun/across/master/bbr.sh)
    echo ""
    before_show_menu
}

update_shell() {
    wget -O /usr/bin/x-ui -N --no-check-certificate https://github.com/Misaka-blog/x-ui/raw/master/x-ui.sh
    if [[ $? != 0 ]]; then
        echo ""
        red "下载脚本失败，请检查本机能否连接 Github"
        before_show_menu
    else
        chmod +x /usr/bin/x-ui
        green "升级脚本成功，请重新运行脚本" && exit 0
    fi
}

# 0: running, 1: not running, 2: not installed
check_status() {
    if [[ ! -f /etc/systemd/system/x-ui.service ]]; then
        return 2
    fi
    temp=$(systemctl status x-ui | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
    if [[ x"${temp}" == x"running" ]]; then
        return 0
    else
        return 1
    fi
}

check_enabled() {
    temp=$(systemctl is-enabled x-ui)
    if [[ x"${temp}" == x"enabled" ]]; then
        return 0
    else
        return 1
    fi
}

check_uninstall() {
    check_status
    if [[ $? != 2 ]]; then
        echo ""
        red "X-ui 面板已安装，请不要重复安装"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

check_install() {
    check_status
    if [[ $? == 2 ]]; then
        echo ""
        red "请先安装 X-ui 面板"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

show_status() {
    check_status
    case $? in
    0)
        echo -e "面板状态: ${GREEN}已运行${PLAIN}"
        show_enable_status
        ;;
    1)
        echo -e "面板状态: ${YELLOW}未运行${PLAIN}"
        show_enable_status
        ;;
    2)
        echo -e "面板状态: ${RED}未安装${PLAIN}"
        ;;
    esac
    show_xray_status
}

show_enable_status() {
    check_enabled
    if [[ $? == 0 ]]; then
        echo -e "是否开机自启: ${GREEN}是${PLAIN}"
    else
        echo -e "是否开机自启: ${RED}否${PLAIN}"
    fi
}

check_xray_status() {
    count=$(ps -ef | grep "xray-linux" | grep -v "grep" | wc -l)
    if [[ count -ne 0 ]]; then
        return 0
    else
        return 1
    fi
}

show_xray_status() {
    check_xray_status
    if [[ $? == 0 ]]; then
        echo -e "xray 状态: ${GREEN}运行${PLAIN}"
    else
        echo -e "xray 状态: ${RED}未运行${PLAIN}"
    fi
}

set_telegram_bot() {
    echo -E ""
    yellow "设置Telegram Bot需要知晓Bot的Token与ChatId"
    yellow "使用方法请参考博客https://coderfan.net"
    read -P "我已确认以上内容[y/n]" confirmTGBot
    if [ $confirmTGBot == "n" ]; then
        show_menu
    else
        read -p "请输入Telegram Bot Token:" TG_BOT_TOKEN
        yellow "你设置的Telegram Bot Token:$TG_BOT_TOKEN"
        read -p "请输入Telegram Bot Chat Id:" TG_BOT_CHATID
        yellow "你设置的Telegram Bot Chat Id:$TG_BOT_CHATID"
        read -p "请输入Telegram Bot运行周期:" TG_BOT_RUNTIME
        yellow "你设置的Telegram Bot运行周期:$TG_BOT_RUNTIME"
        info=$(/usr/local/x-ui/x-ui setting -tgbottoken ${TG_BOT_TOKEN} -tgbotchatid ${TG_BOT_CHATID} -tgbotRuntime "$TG_BOT_RUNTIME")
        if [ $? != 0 ]; then
            yellow "$info"
            red "设置Telegram Bot失败"
            exit 1
        else
            green "设置Telegram Bot成功"
            show_menu
        fi
    fi
}

enable_telegram_bot() {
    echo -E ""
    yellow "该功能会开启Telegram Bot通知"
    yellow "通知内容包括:"
    green "1.流量使用情况"
    green "2.节点到期提醒,待实现(规划中)"
    green "3.面板登录提醒,待完善(规划中)"
    read -p "我已确认以上内容[y/n]" confirmTGBot
    if [ $confirmTGBot == "y" ]; then
        info=$(/usr/local/x-ui/x-ui setting -enabletgbot=true)
        if [ $? == 0 ]; then
            green "开启成功,重启X-UI生效,重启中...."
            restart
        else
            red "开启失败,即将退出..."
            exit 1
        fi
    else
        show_menu
    fi
}

disable_telegram_bot() {
    read -P "确认是否关闭Telegram Bot[y/n]" confirmTGBot
    if [ $confirmTGBot == "y" ]; then
        info=$(/usr/local/x-ui/x-ui setting -enabletgbot=false)
        if [ $? == 0 ]; then
            green "关闭成功,重启X-UI生效,重启中...."
            restart
        else
            red "关闭失败,请检查日志..."
            exit 1
        fi
    else
        show_menu
    fi
}

ssl_cert_issue() {
    wget -N https://raw.githubusercontents.com/Misaka-blog/acme-1key/master/acme1key.sh && bash acme1key.sh
}

open_ports(){
    systemctl stop firewalld.service
    systemctl disable firewalld.service
    setenforce 0
    ufw disable
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT
    iptables -t nat -F
    iptables -t mangle -F 
    iptables -F
    iptables -X
    netfilter-persistent save
    yellow "VPS中的所有网络端口已开启"
}

show_usage() {
    echo "x-ui 管理脚本使用方法: "
    echo "------------------------------------------"
    echo "x-ui              - 显示管理菜单 (功能更多)"
    echo "x-ui start        - 启动 x-ui 面板"
    echo "x-ui stop         - 停止 x-ui 面板"
    echo "x-ui restart      - 重启 x-ui 面板"
    echo "x-ui status       - 查看 x-ui 状态"
    echo "x-ui enable       - 设置 x-ui 开机自启"
    echo "x-ui disable      - 取消 x-ui 开机自启"
    echo "x-ui log          - 查看 x-ui 日志"
    echo "x-ui v2-ui        - 迁移本机器的 v2-ui 账号数据至 x-ui"
    echo "x-ui update       - 更新 x-ui 面板"
    echo "x-ui install      - 安装 x-ui 面板"
    echo "x-ui uninstall    - 卸载 x-ui 面板"
    echo "------------------------------------------"
}

show_menu() {
    echo -e "
  ${GREEN}x-ui 面板管理脚本${PLAIN}
  ${GREEN}0.${PLAIN} 退出脚本
————————————————
  ${GREEN}1.${PLAIN} 安装 x-ui
  ${GREEN}2.${PLAIN} 更新 x-ui
  ${GREEN}3.${PLAIN} 卸载 x-ui
————————————————
  ${GREEN}4.${PLAIN} 重置用户名密码
  ${GREEN}5.${PLAIN} 重置面板设置
  ${GREEN}6.${PLAIN} 设置面板端口
————————————————
  ${GREEN}7.${PLAIN} 启动 x-ui
  ${GREEN}8.${PLAIN} 停止 x-ui
  ${GREEN}9.${PLAIN} 重启 x-ui
 ${GREEN}10.${PLAIN} 查看 x-ui 状态
 ${GREEN}11.${PLAIN} 查看 x-ui 日志
————————————————
 ${GREEN}12.${PLAIN} 设置 x-ui 开机自启
 ${GREEN}13.${PLAIN} 取消 x-ui 开机自启
————————————————
 ${GREEN}14.${PLAIN} 一键安装 bbr (最新内核)
 ${GREEN}15.${PLAIN} 一键申请SSL证书(acme申请)
 ${GREEN}16.${PLAIN} VPS防火墙放开所有网络端口
 ${green}17.${plain} 开启Telegram通知(TgBot)
 ${green}18.${plain} 关闭Telegram通知(TgBot)
 ${green}19.${plain} 设置TelegramBot
 "
    show_status
    echo && read -p "请输入选择 [0-19]: " num

    case "${num}" in
        0) exit 0 ;;
        1) check_uninstall && install ;;
        2) check_install && update ;;
        3) check_install && uninstall ;;
        4) check_install && reset_user ;;
        5) check_install && reset_config ;;
        6) check_install && set_port ;;
        7) check_install && start ;;
        8) check_install && stop ;;
        9) check_install && restart ;;
        10) check_install && status ;;
        11) check_install && show_log ;;
        12) check_install && enable_xui ;;
        13) check_install && disable_xui ;;
        14) install_bbr ;;
        15) ssl_cert_issue ;;
        16) open_ports ;;
        17) enable_telegram_bot ;;
        18) disable_telegram_bot ;;
        19) set_telegram_bot ;;
        *) red "请输入正确的数字 [0-15]" ;;
    esac
}

if [[ $# > 0 ]]; then
    case $1 in
    "start") check_install 0 && start 0 ;;
    "stop") check_install 0 && stop 0 ;;
    "restart") check_install 0 && restart 0 ;;
    "status") check_install 0 && status 0 ;;
    "enable") check_install 0 && enable_xui 0 ;;
    "disable") check_install 0 && disable_xui 0 ;;
    "log") check_install 0 && show_log 0 ;;
    "v2-ui") check_install 0 && migrate_v2_ui 0 ;;
    "update") check_install 0 && update 0 ;;
    "install") check_uninstall 0 && install 0 ;;
    "uninstall") check_install 0 && uninstall 0 ;;
    *) show_usage ;;
    esac
else
    show_menu
fi