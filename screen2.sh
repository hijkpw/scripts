#!/usr/bin/env bash

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

[[ -z $(type -P screen) ]] && ${PACKAGE_UPDATE[int]} && ${PACKAGE_INSTALL[int]} screen

back2menu2() {
    green "所选操作执行完成"
    read -p "请输入“y”退出，或按任意键回到主菜单：" back2menuInput
    case "$back2menuInput" in
        y) exit 1 ;;
        *) menu ;;
    esac
}

createScreen(){
    read -p "设置screen后台名称：" screenName
    screen -S $screenName
    back2menu
}

enterScreen(){
    names=`screen -ls | grep '(Detached)' | awk '{print $1}' | awk -F "." '{print $2}'`
    [[ -n $names ]] && green "$names"
    read -p "输入进入的screen后台名称：" screenName
    screen -r $screenName || red "无执行内容"
}

deleteScreen(){
    names=`screen -ls | grep '(Detached)' | awk '{print $1}' | awk -F "." '{print $2}'`
    [[ -n $names ]] && green "$names"
    read -p "输入删除的screen后台名称：" screenName
    screen -S $screenName -X quit || red "无执行内容"
}

killAllScreen(){
    names=`screen -ls | grep '(Detached)' | awk '{print $1}' | awk -F "." '{print $2}'`
    screen -wipe
    [[ -n $names ]] && screen -ls | grep '(Detached)' | cut -d. -f1 | awk '{print $1}' | xargs kill
    green "所有screen后台清除完毕" || red "无执行内容，无须清除"
}

menu(){
    clear
    red "=================================="
    echo "                           "
    red "       Screen 后台运行管理脚本       "
    red "          by 小御坂的破站           "
    echo "                           "
    red "  Site: https://owo.misaka.rest  "
    echo "                           "
    red "=================================="
    echo "          "
    green "1. 创建screen后台并设置名称"
    green "2. 查看并进入指定screen后台"
    green "3. 查看并删除指定screen后台"
    green "4. 清除所有screen后台"
    green "0. 退出脚本"
    read -p "请输入选项:" menuNumberInput
    case "$menuNumberInput" in 
        1 ) createScreen ;;
        2 ) enterScreen ;;
        3 ) deleteScreen ;;
        4 ) killAllScreen ;;
        0 ) exit 1 ;;
    esac
}

menu