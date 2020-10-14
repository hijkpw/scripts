#!/bin/bash
# MTProto一键安装脚本
# Author: hijk<https://hijk.art>


red='\033[0;31m'
green="\033[0;32m"
plain='\033[0m'

export MTG_CONFIG="${MTG_CONFIG:-$HOME/.config/mtg}"
export MTG_ENV="$MTG_CONFIG/env"
export MTG_SECRET="$MTG_CONFIG/secret"
export MTG_CONTAINER="${MTG_CONTAINER:-mtg}"
export MTG_IMAGENAME="${MTG_IMAGENAME:-nineseconds/mtg:stable}"

DOCKER_CMD="$(command -v docker)"

function checkSystem()
{
    result=$(id | awk '{print $1}')
    if [ $result != "uid=0(root)" ]; then
        echo "请以root身份执行该脚本"
        exit 1
    fi

    res=`which yum`
    if [ "$?" != "0" ]; then
        res=`which apt`
        if [ "$?" != "0" ]; then
            echo "不受支持的Linux系统"
            exit 1
        fi
        res=`hostnamectl | grep -i ubuntu`
        if [ "${res}" != "" ]; then
            OS="ubuntu"
        else
            OS="debian"
        fi
        PMT="apt"
        CMD_INSTALL="apt install -y "
        CMD_REMOVE="apt remove -y "
    else
        OS="centos"
        PMT="yum"
        CMD_INSTALL="yum install -y "
        CMD_REMOVE="yum remove -y "
    fi
    res=`which systemctl`
    if [ "$?" != "0" ]; then
        echo "系统版本过低，请升级到最新版本"
        exit 1
    fi
}

status()
{
    if [ "$DOCKER_CMD" = "" ]; then
        echo 0
        return
    elif [ ! -f $MTG_ENV ]; then
        echo 1
        return
    fi
    port=`grep MTG_PORT $MTG_ENV|cut -d= -f2`
    if [ -z "$port" ]; then
        echo 2
        return
    fi
    res=`ss -ntlp| grep ${port} | grep docker`
    if [ -z "$res" ]; then
        echo 3
    else
        echo 4
    fi
}

statusText()
{
    res=`status`
    case $res in
        3)
            echo -e ${green}已安装${plain} ${red}未运行${plain}
            ;;
        4)
            echo -e ${green}已安装${plain} ${green}正在运行${plain}
            ;;
        *)
            echo -e ${red}未安装${plain}
            ;;
    esac
}

getData()
{
    IP=`curl -s -4 ip.sb`
    read -p "请输入MTProto端口[100-65535的一个数字]：" PORT
    [ -z "${PORT}" ] && {
        echo -e "${red}请输入MTProto端口！${plain}"
        exit 1
    }
    if [ "${PORT:0:1}" = "0" ]; then
        echo -e "${red}端口不能以0开头${plain}"
        exit 1
    fi
    MTG_PORT=$PORT
    mkdir -p $MTG_CONFIG
    echo "MTG_IMAGENAME=$MTG_IMAGENAME" > "$MTG_ENV"
    echo "MTG_PORT=$MTG_PORT" >> "$MTG_ENV"
    echo "MTG_CONTAINER=$MTG_CONTAINER" >> "$MTG_ENV"
}

installDocker()
{
    if [ "$DOCKER_CMD" != "" ]; then
        systemctl enable docker
        systemctl start docker
        selinux
        return
    fi

    $CMD_REMOVE docker docker-engine docker.io containerd runc
    if [ $PMT = "apt" ]; then
		apt-get install \
			apt-transport-https \
			ca-certificates \
			curl \
			gnupg-agent \
			software-properties-common
        curl -fsSL https://download.docker.com/linux/$OS/gpg | sudo apt-key add -
        add-apt-repository \
            "deb [arch=amd64] https://download.docker.com/linux/$OS \
            $(lsb_release -cs) \
            stable"
        apt update
    else
        wget -O /etc/yum.repos.d/docker-ce.repo https://download.docker.com/linux/centos/docker-ce.repo
    fi
    $CMD_INSTALL docker-ce docker-ce-cli containerd.io

    DOCKER_CMD="$(command -v docker)"
    if [ ! -x $DOCKER_CMD ]; then
        echo -e "${red}docker安装失败，请到https://hijk.art反馈${plain}"
        exit 1
    fi
    systemctl enable docker
    systemctl start docker

    selinux
}

pullImage()
{
    if [ "$DOCKER_CMD" = "" ]; then
        echo -e "${red}MTProto未安装，请先安装！${plain}"
        exit 1
    fi

    set -a
    source "$MTG_ENV"
    set +a

    $DOCKER_CMD pull "$MTG_IMAGENAME" > /dev/null
}

selinux()
{
    if [ -s /etc/selinux/config ] && grep 'SELINUX=enforcing' /etc/selinux/config; then
        sed -i 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/selinux/config
        setenforce 0
    fi
}

firewall()
{
    port=$1
    systemctl status firewalld > /dev/null 2>&1
    if [ $? -eq 0 ];then
        systemctl disable firewalld
        systemctl stop firewalld
    else
        nl=`iptables -nL | nl | grep FORWARD | awk '{print $1}'`
        if [ "$nl" != "3" ]; then
            iptables -P INPUT ACCEPT
            iptables -P FORWARD ACCEPT
            iptables -P OUTPUT ACCEPT
            iptables -F
        else
            res=`ufw status | grep -i inactive`
            if [ "$res" = "" ]; then
                ufw disable
            fi
        fi
    fi
}

start()
{
    set -a
    source "$MTG_ENV"
    set +a

    if [ ! -f "$MTG_SECRET" ]; then
        $DOCKER_CMD run \
                --rm \
                "$MTG_IMAGENAME" \
            generate-secret tls -c "$(openssl rand -hex 16).com" \
        > "$MTG_SECRET"
    fi

    $DOCKER_CMD ps --filter "Name=$MTG_CONTAINER" -aq | xargs -r $DOCKER_CMD rm -fv > /dev/null
    $DOCKER_CMD run \
            -d \
            --restart=unless-stopped \
            --name "$MTG_CONTAINER" \
            --ulimit nofile=51200:51200 \
            -p "$MTG_PORT:3128" \
        "$MTG_IMAGENAME" run "$(cat "$MTG_SECRET")" > /dev/null

    sleep 3
    res=`ss -ntlp| grep ${MTG_PORT} | grep docker`
    if [ "$res" = "" ]; then
        docker logs $MTG_CONTAINER | tail
        echo -e "${red}启动docker镜像失败，请到 https://hijk.art 反馈${plain}"
        exit 1
    fi
}

stop()
{
    res=`status`
    if [ $res -lt 3 ]; then
        echo -e "${red}MTProto未安装，请先安装！${plain}"
        return
    fi

    set -a
    source "$MTG_ENV"
    set +a

    $DOCKER_CMD stop $MTG_CONTAINER >> /dev/null
}

showInfo()
{
    res=`status`
    if [ $res -lt 3 ]; then
        echo -e "${red}MTProto未安装，请先安装！${plain}"
        return
    fi

    IP=`curl -s -4 ip.sb`
    SECRET=$(cat "$MTG_SECRET")
    set -a
    source "$MTG_ENV"
    set +a

    echo 
    echo -e "  ${red}MTProto代理信息：${plain}"
    echo 
    echo -e "  IP：${red}$IP${plain}"
    echo -e "  端口：${red}$MTG_PORT${plain}"
    echo -e "  密钥：${red}$SECRET${plain}"
    echo ""
    echo -e "  如需获取tg://proxy形式的链接，请打开telegrame关注${green}@MTProxybot${plain}生成"
    echo ""
}

install()
{
    getData
    installDocker
    pullImage
    start
    firewall $MTG_PORT
    showInfo
}

update()
{
    res=`status`
    if [ $res -lt 2 ]; then
        echo -e "${red}MTProto未安装，请先安装！${plain}"
        return
    fi

    pullImage
    stop
    start
    showInfo
}

uninstall()
{
    stop
    rm -rf $MTG_CONFIG
    docker system prune -a
    systemctl stop docker
    systemctl disable docker
    $CMD_REMOVE docker-ce docker-ce-cli containerd.io
}

run()
{
    res=`status`
    if [ $res -lt 3 ]; then
        echo -e "${red}MTProto未安装，请先安装！${plain}"
        return
    fi

    set -a
    source "$MTG_ENV"
    set +a
    res=`ss -ntlp| grep ${MTG_PORT} | grep docker`
    if [ "$res" != "" ]; then
        return
    fi

    start
    showInfo
}

restart()
{
    res=`status`
    if [ $res -lt 3 ]; then
        echo -e "${red}MTProto未安装，请先安装！${plain}"
        return
    fi

    stop
    start
}

reconfig()
{
    res=`status`
    if [ $res -lt 2 ]; then
        echo -e "${red}MTProto未安装，请先安装！${plain}"
        return
    fi

    getData
    stop
    start
    firewall $MTG_PORT
    showInfo
}

showLog()
{
    res=`status`
    if [ $res -lt 3 ]; then
        echo -e "${red}MTProto未安装，请先安装！${plain}"
        return
    fi

    set -a
    source "$MTG_ENV"
    set +a

    $DOCKER_CMD logs $MTG_CONTAINER | tail -f
}

function menu()
{
    clear
    echo "#############################################################"
    echo -e "#                    ${red}MTProto一键安装脚本${plain}                    #"
    echo -e "# ${green}作者${plain}: 网络跳越(hijk)                                      #"
    echo -e "# ${green}网址${plain}: https://hijk.art                                    #"
    echo -e "# ${green}论坛${plain}: https://hijk.club                                   #"
    echo -e "# ${green}TG群${plain}: https://t.me/hijkclub                               #"
    echo -e "# ${green}Youtube频道${plain}: https://youtube.com/channel/UCYTB--VsObzepVJtc9yvUxQ #"
    echo "#############################################################"
    echo ""

    echo -e "  ${green}1.${plain} 安装MTProto代理"
    echo -e "  ${green}2.${plain} 更新MTProto代理"
    echo -e "  ${green}3.${plain} 卸载MTProto代理"
    echo " -------------"
    echo -e "  ${green}4.${plain} 启动MTProto代理"
    echo -e "  ${green}5.${plain} 重启MTProto代理"
    echo -e "  ${green}6.${plain} 停止MTProto代理"
    echo " -------------"
    echo -e "  ${green}7.${plain} 查看MTProto信息"
    echo -e "  ${green}8.${plain} 修改MTProto配置"
    echo -e "  ${green}9.${plain} 查看MTProto日志"
    echo " -------------"
    echo -e "  ${green}0.${plain} 退出"
    echo 
    echo -n " 当前状态："
    statusText
    echo 

    read -p "请选择操作[0-9]：" answer
    case $answer in
        0)
            exit 0
            ;;
        1)
            install
            ;;
        2)
            update
            ;;
        3)
            uninstall
            ;;
        4)
            run
            ;;
        5)
            restart
            ;;
        6)
            stop
            ;;
        7)
            showInfo
            ;;
        8)
            reconfig
            ;;
        9)
            showLog
            ;;
        *)
            echo -e $red 请选择正确的操作！${plain}
            exit 1
            ;;
    esac
}

checkSystem

menu
