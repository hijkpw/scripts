#!/bin/bash
# shadowsocks/ss CentOS 7/8一键安装脚本
# Author: hijk<https://www.hijk.pw>

echo "#############################################################"
echo "#         CentOS 7/8 Shadowsocks/SS 一键安装脚本             #"
echo "# 网址: https://www.hijk.pw                                 #"
echo "# 作者: hijk                                                #"
echo "#############################################################"
echo ""

red='\033[0;31m'
plain='\033[0m'

function checkSystem()
{
    result=$(id | awk '{print $1}')
    if [ $result != "uid=0(root)" ]; then
        echo "请以root身份执行该脚本"
        exit 1
    fi

    if [ ! -f /etc/centos-release ];then
        echo "系统不是CentOS"
        exit 1
    fi
    
    result=`cat /etc/centos-release|grep -oE "[0-9.]+"`
    main=${result%%.*}
    if [ $main -lt 7 ]; then
        echo "不受支持的CentOS版本"
        exit 1
    fi
}

checkSystem

action=$1
[ -z $1 ] && action=install
case "$action" in
    install|uninstall|info)
        if [ $main -eq 7 ]; then
            wget -O ss.sh https://raw.githubusercontent.com/hijkpw/scripts/master/centos7_install_ss.sh
        else
            wget -O ss.sh https://raw.githubusercontent.com/hijkpw/scripts/master/centos8_install_ss.sh
        fi
        bash ss.sh $action
        rm -rf ss.sh
        ;;
    *)
        echo "参数错误"
        echo "用法: `basename $0` [install|uninstall|info]"
        ;;
esac
