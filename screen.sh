#!/usr/bin/env bash

green(){
    echo -e "\033[32m$1\033[0m";
}

red(){
    echo -e "\033[31m$1\033[0m";
}

yellow(){
    echo -e "\033[33m$1\033[0m";
}

white(){
    echo -e "\033[37m$1\033[0m"
}

blue(){
    echo -e "\033[36m$1\033[0m";
}

readp(){
    read -p "$(white "$1")" $2;
}

[[ $(type -P yum) ]] && yumapt='yum -y' || yumapt='apt -y'
[[ $(type -P screen) ]] || (yellow "screen未安装，正在安装中" && $yumapt install screen)	   

back(){
    echo "设置完成，请选择接下来的操作"
    echo "1. 回到主页"
    echo "2. 退出脚本"
    read -p "请输入选项:" backInput
    case "$backInput" in 
        1 ) menu ;;
        2 ) exit 0
    esac
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
    echo "1. 创建screen后台并设置名称"
    echo "2. 查看并进入指定screen后台"
    echo "3. 查看并删除指定screen后台"
    echo "4. 清除所有screen后台"
    echo "0. 退出脚本"
    read -p "请输入选项:" menuNumberInput
    case "$menuNumberInput" in 
        1 )
            readp "设置screen后台名称：" screen
            screen -S $screen
            back;;
        2 )
            names=`screen -ls | grep '(Detached)' | awk '{print $1}' | awk -F "." '{print $2}'`
            [[ -n $names ]] && green "$names" && readp "输入进入的screen后台名称：" screename && screen -r $screename || red "无执行内容"
            back;;
        3 )
            names=`screen -ls | grep '(Detached)' | awk '{print $1}' | awk -F "." '{print $2}'`
            [[ -n $names ]] && green "$names" && readp "输入删除的screen后台名称：" screename && screen -S $screename -X quit || red "无执行内容"
            back;;
        4 )
            names=`screen -ls | grep '(Detached)' | awk '{print $1}' | awk -F "." '{print $2}'`
            screen -wipe
            [[ -n $names ]] && screen -ls | grep '(Detached)' | cut -d. -f1 | awk '{print $1}' | xargs kill && green "所有screen后台清除完毕"|| red "无执行内容，无须清除"
            back;;
        0 ) exit 0
    esac
}

menu