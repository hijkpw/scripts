#!/bin/bash
# MTProto一键安装脚本
# Author: hijk<https://hijk.art>

RED="\033[31m"      # Error message
GREEN="\033[32m"    # Success message
YELLOW="\033[33m"   # Warning message
BLUE="\033[36m"     # Info message
PLAIN='\033[0m'

export MTG_CONFIG="${MTG_CONFIG:-$HOME/.config/mtg}"
export MTG_ENV="$MTG_CONFIG/env"
export MTG_SECRET="$MTG_CONFIG/secret"
export MTG_CONTAINER="${MTG_CONTAINER:-mtg}"
export MTG_IMAGENAME="${MTG_IMAGENAME:-nineseconds/mtg:1}"

DOCKER_CMD="$(command -v docker)"
OSNAME=`hostnamectl | grep -i system | cut -d: -f2`

IP=`curl -sL -4 ip.sb`

colorEcho() {
    echo -e "${1}${@:2}${PLAIN}"
}

checkSystem() {
    result=$(id | awk '{print $1}')
    if [[ $result != "uid=0(root)" ]]; then
        colorEcho $RED " 请以root身份执行该脚本"
        exit 1
    fi

    res=`which yum`
    if [[ "$?" != "0" ]]; then
        res=`which apt`
        if [ "$?" != "0" ]; then
            colorEcho $RED " 不受支持的Linux系统"
            exit 1
        fi
        res=`hostnamectl | grep -i ubuntu`
        if [[ "${res}" != "" ]]; then
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
    if [[ "$?" != "0" ]]; then
        colorEcho $RED " 系统版本过低，请升级到最新版本"
        exit 1
    fi
}

status() {
    if [[ "$DOCKER_CMD" = "" ]]; then
        echo 0
        return
    elif [[ ! -f $MTG_ENV ]]; then
        echo 1
        return
    fi
    port=`grep MTG_PORT $MTG_ENV|cut -d= -f2`
    if [[ -z "$port" ]]; then
        echo 2
        return
    fi
    res=`ss -ntlp| grep ${port} | grep docker`
    if [[ -z "$res" ]]; then
        echo 3
    else
        echo 4
    fi
}

statusText() {
    res=`status`
    case $res in
        3)
            echo -e ${GREEN}已安装${PLAIN} ${RED}未运行${PLAIN}
            ;;
        4)
            echo -e ${GREEN}已安装${PLAIN} ${GREEN}正在运行${PLAIN}
            ;;
        *)
            echo -e ${RED}未安装${PLAIN}
            ;;
    esac
}

getData() {
    read -p " 请输入MTProto端口[100-65535的一个数字]：" PORT
    [[ -z "${PORT}" ]] && {
        echo -e " ${RED}请输入MTProto端口！${PLAIN}"
        exit 1
    }
    if [[ "${PORT:0:1}" = "0" ]]; then
        echo -e " ${RED}端口不能以0开头${PLAIN}"
        exit 1
    fi
    MTG_PORT=$PORT
    mkdir -p $MTG_CONFIG
    echo "MTG_IMAGENAME=$MTG_IMAGENAME" > "$MTG_ENV"
    echo "MTG_PORT=$MTG_PORT" >> "$MTG_ENV"
    echo "MTG_CONTAINER=$MTG_CONTAINER" >> "$MTG_ENV"
}

installDocker() {
    if [[ "$DOCKER_CMD" != "" ]]; then
        systemctl enable docker
        systemctl start docker
        selinux
        return
    fi

    #$CMD_REMOVE docker docker-engine docker.io containerd runc
    $PMT clean all
    $CMD_INSTALL wget curl
    if [[ $PMT = "apt" ]]; then
        apt clean all
		apt-get -y install \
			apt-transport-https \
			ca-certificates \
			curl \
			gnupg-agent \
			software-properties-common
        curl -fsSL https://download.docker.com/linux/$OS/gpg | apt-key add -
        add-apt-repository \
            "deb [arch=amd64] https://download.docker.com/linux/$OS \
            $(lsb_release -cs) \
            stable"
        apt update
    else
        wget -O /etc/yum.repos.d/docker-ce.repo https://download.docker.com/linux/centos/docker-ce.repo
        yum clean all
    fi
    $CMD_INSTALL docker-ce docker-ce-cli containerd.io

    DOCKER_CMD="$(command -v docker)"
    if [[ "$DOCKER_CMD" = "" ]]; then
        echo -e " ${RED}$OSNAME docker安装失败，请到https://hijk.art反馈${PLAIN}"
        exit 1
    fi
    systemctl enable docker
    systemctl start docker

    selinux
}

pullImage() {
    if [[ "$DOCKER_CMD" = "" ]]; then
        echo -e " ${RED}MTProto未安装，请先安装！${PLAIN}"
        exit 1
    fi

    set -a
    source "$MTG_ENV"
    set +a

    $DOCKER_CMD pull "$MTG_IMAGENAME" > /dev/null
}

selinux() {
    if [[ -s /etc/selinux/config ]] && grep 'SELINUX=enforcing' /etc/selinux/config; then
        sed -i 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/selinux/config
        setenforce 0
    fi
}

firewall() {
    port=$1
    systemctl status firewalld > /dev/null 2>&1
    if [[ $? -eq 0 ]];then
        firewall-cmd --permanent --add-port=$port/tcp
        firewall-cmd --reload
    else
        nl=`iptables -nL | nl | grep FORWARD | awk '{print $1}'`
        if [ "$nl" != "3" ]; then
            iptables -I INPUT -p tcp --dport=$port -j ACCEPT
        else
            res=`ufw status | grep -i inactive`
            if [ "$res" = "" ]; then
                ufw allow $port/tcp
            fi
        fi
    fi
}

start() {
    res=`status`
    if [[ $res -lt 3 ]]; then
        echo -e " ${RED}MTProto未安装，请先安装！${PLAIN}"
        return
    fi

    set -a
    source "$MTG_ENV"
    set +a

    if [[ ! -f "$MTG_SECRET" ]]; then
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
    if [[ "$res" = "" ]]; then
        docker logs $MTG_CONTAINER | tail
        echo -e " ${RED}$OSNAME 启动docker镜像失败，请到 https://hijk.art 反馈${PLAIN}"
        exit 1
    else
        colorEcho $BLUE " MTProto启动成功！"
    fi
}

stop() {
    res=`status`
    if [[ $res -lt 3 ]]; then
        echo -e " ${RED}MTProto未安装，请先安装！${PLAIN}"
        return
    fi

    set -a
    source "$MTG_ENV"
    set +a

    $DOCKER_CMD stop $MTG_CONTAINER >> /dev/null
    colorEcho $BLUE " MTProto停止成功！"
}

showInfo() {
    res=`status`
    if [[ $res -lt 3 ]]; then
        echo -e " ${RED}MTProto未安装，请先安装！${PLAIN}"
        return
    fi

    SECRET=$(cat "$MTG_SECRET")
    set -a
    source "$MTG_ENV"
    set +a

    echo 
    echo -e " ${RED}MTProto代理信息：${PLAIN}"
    echo 
    echo -n -e "  ${BLUE}当前状态：${PLAIN}"
    statusText
    echo -e "  ${BLUE}IP：${PLAIN}${RED}$IP${PLAIN}"
    echo -e "  ${BLUE}端口：${PLAIN}${RED}$MTG_PORT${PLAIN}"
    echo -e "  ${BLUE}密钥：${PLAIN}${RED}$SECRET${PLAIN}"
    echo ""
    echo -e "  如需获取tg://proxy形式的链接，请打开telegrame关注${GREEN}@MTProxybot${PLAIN}生成"
    echo ""
}

install() {
    getData
    installDocker
    pullImage
    start
    firewall $MTG_PORT
    showInfo
}

update() {
    res=`status`
    if [[ $res -lt 2 ]]; then
        echo -e " ${RED}MTProto未安装，请先安装！${PLAIN}"
        return
    fi

    pullImage
    stop
    start
    showInfo
}

uninstall() {
    echo ""
    read -p " 确定卸载MTProto？[y/n]：" answer
    if [[ "$answer" = "y" ]] || [[ "$answer" = "Y" ]]; then
        stop
        rm -rf $MTG_CONFIG
        docker system prune -af
        systemctl stop docker
        systemctl disable docker
        $CMD_REMOVE docker-ce docker-ce-cli containerd.io
        colorEcho $GREEN " 卸载成功"
    fi
}

restart() {
    res=`status`
    if [[ $res -lt 3 ]]; then
        echo -e " ${RED}MTProto未安装，请先安装！${PLAIN}"
        return
    fi

    stop
    start
}

reconfig()
{
    res=`status`
    if [[ $res -lt 2 ]]; then
        echo -e " ${RED}MTProto未安装，请先安装！${PLAIN}"
        return
    fi

    getData
    stop
    start
    firewall $MTG_PORT
    showInfo
}

showLog() {
    res=`status`
    if [[ $res -lt 3 ]]; then
        echo -e " ${RED}MTProto未安装，请先安装！${PLAIN}"
        return
    fi

    set -a
    source "$MTG_ENV"
    set +a

    $DOCKER_CMD logs $MTG_CONTAINER | tail
}

menu() {
    clear
    echo "#############################################################"
    echo -e "#                    ${RED}MTProto一键安装脚本${PLAIN}                    #"
    echo -e "# ${GREEN}作者${PLAIN}: 网络跳越(hijk)                                      #"
    echo -e "# ${GREEN}网址${PLAIN}: https://hijk.art                                    #"
    echo -e "# ${GREEN}论坛${PLAIN}: https://hijk.club                                   #"
    echo -e "# ${GREEN}TG群${PLAIN}: https://t.me/hijkclub                               #"
    echo -e "# ${GREEN}Youtube频道${PLAIN}: https://youtube.com/channel/UCYTB--VsObzepVJtc9yvUxQ #"
    echo "#############################################################"
    echo ""

    echo -e "  ${GREEN}1.${PLAIN} 安装MTProto代理"
    echo -e "  ${GREEN}2.${PLAIN} 更新MTProto代理"
    echo -e "  ${GREEN}3.${PLAIN} 卸载MTProto代理"
    echo " -------------"
    echo -e "  ${GREEN}4.${PLAIN} 启动MTProto代理"
    echo -e "  ${GREEN}5.${PLAIN} 重启MTProto代理"
    echo -e "  ${GREEN}6.${PLAIN} 停止MTProto代理"
    echo " -------------"
    echo -e "  ${GREEN}7.${PLAIN} 查看MTProto信息"
    echo -e "  ${GREEN}8.${PLAIN} 修改MTProto配置"
    echo -e "  ${GREEN}9.${PLAIN} 查看MTProto日志"
    echo " -------------"
    echo -e "  ${GREEN}0.${PLAIN} 退出"
    echo 
    echo -n " 当前状态："
    statusText
    echo 

    read -p " 请选择操作[0-9]：" answer
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
            start
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
            echo -e " ${RED}请选择正确的操作！${PLAIN}"
            exit 1
            ;;
    esac
}

checkSystem

menu
