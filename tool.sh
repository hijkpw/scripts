#!/bin/bash

# 全局变量
ver="2.1.5"
changeLog="新增放开VPS所有网络端口选项"
arch=$(uname -m)
virt=$(systemd-detect-virt)
kernelVer=$(uname -r)
TUN=$(cat /dev/net/tun 2>&1 | tr '[:upper:]' '[:lower:]')
REGEX=("debian" "ubuntu" "centos|red hat|kernel|oracle linux|alma|rocky" "'amazon linux'" "alpine")
RELEASE=("Debian" "Ubuntu" "CentOS" "CentOS" "Alpine")
PACKAGE_UPDATE=("apt -y update" "apt -y update" "yum -y update" "yum -y update" "apk update -f")
PACKAGE_INSTALL=("apt -y install" "apt -y install" "yum -y install" "yum -y install" "apk add -f")
CMD=("$(grep -i pretty_name /etc/os-release 2>/dev/null | cut -d \" -f2)" "$(hostnamectl 2>/dev/null | grep -i system | cut -d : -f2)" "$(lsb_release -sd 2>/dev/null)" "$(grep -i description /etc/lsb-release 2>/dev/null | cut -d \" -f2)" "$(grep . /etc/redhat-release 2>/dev/null)" "$(grep . /etc/issue 2>/dev/null | cut -d \\ -f1 | sed '/^[ ]*$/d')")

# 控制台字体
green() {
	echo -e "\033[32m\033[01m$1\033[0m"
}

red() {
	echo -e "\033[31m\033[01m$1\033[0m"
}

yellow() {
	echo -e "\033[33m\033[01m$1\033[0m"
}

# 必须以root运行脚本
[[ $(id -u) != 0 ]] && red "请使用“sudo -i”登录root用户后执行工具箱脚本！！！" && exit 1

# 判断系统，此部分代码感谢fscarmen的技术指导
for i in "${CMD[@]}"; do
	SYS="$i" && [[ -n $SYS ]] && break
done

for ((int = 0; int < ${#REGEX[@]}; int++)); do
	[[ $(echo "$SYS" | tr '[:upper:]' '[:lower:]') =~ ${REGEX[int]} ]] && SYSTEM="${RELEASE[int]}" && [[ -n $SYSTEM ]] && break
done

[[ -z $SYSTEM ]] && red "不支持VPS的当前系统，请使用主流操作系统" && exit 1

# 更新系统及安装依赖，此部分代码感谢fscarmen的技术指导
${PACKAGE_UPDATE[int]}
${PACKAGE_INSTALL[int]} curl wget sudo

# 获取IP地址及其信息
IP4=$(curl -s4m2 https://ip.gs/json)
IP6=$(curl -s6m2 https://ip.gs/json)
WAN4=$(expr "$IP4" : '.*ip\":\"\([^"]*\).*')
WAN6=$(expr "$IP6" : '.*ip\":\"\([^"]*\).*')
COUNTRY4=$(expr "$IP4" : '.*country\":\"\([^"]*\).*')
COUNTRY6=$(expr "$IP6" : '.*country\":\"\([^"]*\).*')
ASNORG4=$(expr "$IP4" : '.*asn_org\":\"\([^"]*\).*')
ASNORG6=$(expr "$IP6" : '.*asn_org\":\"\([^"]*\).*')

# 判断IP地址状态
IP4="$WAN4 （$COUNTRY4 $ASNORG4）"
IP6="$WAN6 （$COUNTRY6 $ASNORG6）"
if [ -z $WAN4 ]; then
	IP4="当前VPS未检测到IPv4地址"
fi
if [ -z $WAN6 ]; then
	IP6="当前VPS未检测到IPv6地址"
fi

# 获取脚本运行次数
COUNT=$(curl -sm2 "https://hits.seeyoufarm.com/api/count/incr/badge.svg?url=https%3A%2F%2Fcdn.jsdelivr.net%2Fgh%2FMisaka-blog%2FMisakaLinuxToolbox%40master%2FMisakaToolbox.sh&count_bg=%2379C83D&title_bg=%23555555&icon=&icon_color=%23E7E7E7&title=hits&edge_flat=false" 2>&1) &&
TODAY=$(expr "$COUNT" : '.*\s\([0-9]\{1,\}\)\s/.*')
TOTAL=$(expr "$COUNT" : '.*/\s\([0-9]\{1,\}\)\s.*')

#第一页
oraclefirewall() {
	if [ $SYSTEM = "CentOS" ]; then
		systemctl stop oracle-cloud-agent
		systemctl disable oracle-cloud-agent
		systemctl stop oracle-cloud-agent-updater
		systemctl disable oracle-cloud-agent-updater
		systemctl stop firewalld.service
		systemctl disable firewalld.service
		yellow "Oracle Cloud原生系统防火墙禁用成功"
	else
		iptables -P INPUT ACCEPT
		iptables -P FORWARD ACCEPT
		iptables -P OUTPUT ACCEPT
		iptables -F
		apt-get purge netfilter-persistent -y
		yellow "Oracle Cloud原生系统防火墙禁用成功"
	fi
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

euservDig9() {
	echo -e "search blue.kundencontroller.de\noptions rotate\nnameserver 2a02:180:6:5::1c\nnameserver 2a02:180:6:5::4\nnameserver 2a02:180:6:5::1e\nnameserver 2a02:180:6:5::1d" >/etc/resolv.conf
}

rootLogin() {
	read -p "请输入需要设置的root密码:" password
	echo root:$password | sudo chpasswd root
	sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config
	sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/g' /etc/ssh/sshd_config
	sudo service sshd restart
	green "用户名：root"
	green "密码：$password"
	yellow "请妥善保管好登录信息！然后重启VPS确保设置已保存！"
}

screenManager() {
	wget -N https://cdn.jsdelivr.net/gh/Misaka-blog/screenManager@master/screen.sh && chmod -R 777 screen.sh && bash screen.sh
}

bbr() {
	if [ ${virt} == "kvm" ]; then
		wget -N --no-check-certificate "https://raw.githubusercontents.com/chiakge/Linux-NetSpeed/master/tcp.sh" && chmod +x tcp.sh && ./tcp.sh
	fi
	if [ ${virt} == "zvm" ]; then
		wget -N --no-check-certificate "https://raw.githubusercontents.com/chiakge/Linux-NetSpeed/master/tcp.sh" && chmod +x tcp.sh && ./tcp.sh
	fi
	if [ ${virt} == "openvz" ]; then
		[[ ! $TUN =~ 'in bad state' ]] && [[ ! $TUN =~ '处于错误状态' ]] && [[ ! $TUN =~ 'Die Dateizugriffsnummer ist in schlechter Verfassung' ]] && red "未开启TUN，请去VPS后台开启" && exit 1
		wget --no-cache -O lkl-haproxy.sh https://raw.githubusercontents.com/mzz2017/lkl-haproxy/master/lkl-haproxy.sh && bash lkl-haproxy.sh
	fi
	if [ ${virt} == "lxc" ]; then
		red "抱歉，你的VPS暂时不支持bbr加速脚本"
	fi
}

warp() {
	echo "                            "
	green "请选择你接下来使用的脚本"
	echo "                            "
	echo "1. 【推荐】 fscarmen"
	echo "2. fscarmen-docker"
	echo "3. fscarmen warp解锁奈飞流媒体脚本"
	echo "4. kkkyg（甬哥）"
	echo "5. P3TERX"
	echo "                            "
	echo "0. 返回主菜单"
	read -p "请输入选项:" warpNumberInput
	case "$warpNumberInput" in
        1) wget -N https://cdn.jsdelivr.net/gh/fscarmen/warp/menu.sh && bash menu.sh ;;
        2) wget -N https://cdn.jsdelivr.net/gh/fscarmen/warp/docker.sh && bash docker.sh ;;
        3) bash <(curl -sSL https://raw.githubusercontent.com/fscarmen/warp_unlock/main/unlock.sh) ;;
        4) wget -N https://cdn.jsdelivr.net/gh/kkkyg/CFwarp/CFwarp.sh && bash CFwarp.sh ;;
        5) bash <(curl -fsSL git.io/warp.sh) ;;
        0) menu ;;
	esac
}

dockerInstall() {
	curl -fsSL https://get.docker.com | bash -s docker --mirror Aliyun
}

acmesh() {
	wget -N https://cdn.jsdelivr.net/gh/Misaka-blog/acme-1key@master/acme1key.sh && chmod -R 777 acme1key.sh && bash acme1key.sh
}

dns64server() {
	echo -e "nameserver 2001:67c:2b0::4\nnameserver 2001:67c:2b0::6" >/etc/resolv.conf
	yellow "设置DNS64服务器完成"
}

cfArgoTunnel() {
	wget -N https://cdn.jsdelivr.net/gh/Misaka-blog/argo-tunnel-script@master/argo.sh && bash argo.sh
}

# 第二页
bt() {
	if [ $SYSTEM = "CentOS" ]; then
		yum install -y wget && wget -O install.sh http://www.aapanel.com/script/install_6.0_en.sh && bash install.sh forum
	elif [ $SYSTEM = "Debian" ]; then
		wget -O install.sh http://www.aapanel.com/script/install-ubuntu_6.0_en.sh && bash install.sh forum
	else
		wget -O install.sh http://www.aapanel.com/script/install-ubuntu_6.0_en.sh && sudo bash install.sh forum
	fi
}

xui() {
	bash <(curl -Ls https://raw.githubusercontents.com/vaxilu/x-ui/master/install.sh)
}

aria2() {
	${PACKAGE_INSTALL[int]} ca-certificates
	wget -N git.io/aria2.sh && chmod +x aria2.sh && bash aria2.sh
}

cyberpanel() {
	sh <(curl https://cyberpanel.net/install.sh || wget -O - https://cyberpanel.net/install.sh)
}

qlPanel() {
	[[ -z $(docker -v 2>/dev/null) ]] && curl -fsSL https://get.docker.com | bash -s docker --mirror Aliyun
	read -p "请输入将要安装的青龙面板容器名称：" qlPanelName
	read -p "请输入外网访问端口：" qlHTTPPort
	docker run -dit --name $qlPanelName --hostname $qlPanelName --restart always -p $qlHTTPPort:5700 -v $PWD/QL/config:/ql/config -v $PWD/QL/log:/ql/log -v $PWD/QL/db:/ql/db -v $PWD/QL/scripts:/ql/scripts -v $PWD/QL/jbot:/ql/jbot whyour/qinglong:latest
	yellow "青龙面板安装成功！！！"
	green "IPv4访问地址为：http://$WAN4:$qlHTTPPort"
	green "IPv6访问地址为：http://[$WAN6]:$qlHTTPPort"
	yellow "请稍等1-3分钟，等待青龙面板容器启动"
}

trojanpanel() {
	source <(curl -sL https://git.io/trojan-install)
}

# 第三页
macka() {
	wget -P /root -N --no-check-certificate "https://raw.githubusercontents.com/mack-a/v2ray-agent/master/install.sh" && chmod 700 /root/install.sh && /root/install.sh
}

boy233() {
	bash <(curl -s -L https://git.io/v2ray.sh)
}

misakaXray() {
	bash <(curl -sL https://cdn.jsdelivr.net/gh/Misaka-blog/Xray-script@master/xray.sh)
}

tgMTProxy() {
	mkdir /home/mtproxy && cd /home/mtproxy
	curl -s -o mtproxy.sh https://raw.githubusercontents.com/sunpma/mtp/master/mtproxy.sh && chmod +x mtproxy.sh && bash mtproxy.sh
	bash mtproxy.sh start
}

shadowsocks() {
	wget --no-check-certificate -O shadowsocks-all.sh https://raw.githubusercontents.com/teddysun/shadowsocks_install/master/shadowsocks-all.sh
	chmod +x shadowsocks-all.sh
	./shadowsocks-all.sh 2>&1 | tee shadowsocks-all.log
}

# 第四页
vpsBench() {
	echo "                            "
	green "请选择你接下来使用的脚本"
	echo "                            "
	echo "1. 使用misakabench"
	echo "2. 使用bench.sh"
	echo "3. 使用superbench"
	echo "4. 使用lemonbench"
	echo "                            "
	echo "0. 返回主菜单"
	read -p "请输入选项:" page3NumberInput
	case "$page3NumberInput" in
        1) bash <(curl -Lso- https://cdn.jsdelivr.net/gh/Misaka-blog/misakabench@master/misakabench.sh) ;;
        2) wget -qO- bench.sh | bash ;;
        3) wget -qO- --no-check-certificate https://raw.githubusercontents.com/oooldking/script/master/superbench.sh | bash ;;
        4) curl -fsL https://ilemonra.in/LemonBenchIntl | bash -s fast ;;
        0) menu ;;
	esac
}

mediaUnblockTest() {
	bash <(curl -L -s https://raw.githubusercontents.com/lmc999/RegionRestrictionCheck/main/check.sh)
}

speedTest() {
	bash <(curl -Lso- https://git.io/superspeed)
}

# 第五页
nezha() {
	curl -L https://raw.githubusercontents.com/naiba/nezha/master/script/install.sh -o nezha.sh
    chmod +x nezha.sh
	sudo ./nezha.sh
}

serverstatus() {
	wget -N https://raw.githubusercontents.com/cokemine/ServerStatus-Hotaru/master/status.sh
	echo "                            "
	green "请选择你需要安装探针的客户端类型"
	echo "                            "
	echo "1. 服务端"
	echo "2. 监控端"
	echo "0. 返回主页"
	echo "                            "
	read -p "请输入选项:" menuNumberInput1
	case "$menuNumberInput1" in
        1) bash status.sh s ;;
        2) bash status.sh c ;;
        0) menu ;;
	esac
}

# 菜单
menu() {
	clear
	red "=================================="
	echo "                           "
	red "       Misaka Linux Toolbox        "
	red "          by 小御坂的破站           "
	echo "                           "
	red "  Site: https://owo.misaka.rest  "
	echo "                           "
	red "=================================="
	echo "                            "
	green "当前工具箱版本：v$ver"
	green "更新日志：$changeLog"
	green "今日运行次数：$TODAY 总共运行次数：$TOTAL"
	echo "                            "
	red "检测到VPS信息如下："
	yellow "处理器架构：$arch"
	yellow "虚拟化架构：$virt"
	yellow "操作系统：$CMD"
	yellow "内核版本：$kernelVer"
	yellow "IPv4地址：$IP4"
	yellow "IPv6地址：$IP6"
	echo "                            "
	green "下面是脚本分类，请选择对应的分类后进入到相对应的菜单中"
	echo "                            "
	echo "1. 系统相关"
	echo "2. 面板相关"
	echo "3. 节点相关"
	echo "4. VPS测试"
	echo "5. VPS探针"
	[ ${virt} == "kvm" ] && echo "6. VPS DD系统"
	echo "                            "
	echo "9. 更新脚本"
	echo "0. 退出脚本"
	echo "                            "
	read -p "请输入选项:" menuNumberInput
	case "$menuNumberInput" in
        1) page1 ;;
        2) page2 ;;
        3) page3 ;;
        4) page4 ;;
        5) page5 ;;
        6) wget --no-check-certificate -qO ~/Network-Reinstall-System-Modify.sh 'https://www.cxthhhhh.com/CXT-Library/Network-Reinstall-System-Modify/Network-Reinstall-System-Modify.sh' && chmod a+x ~/Network-Reinstall-System-Modify.sh && bash ~/Network-Reinstall-System-Modify.sh -UI_Options ;;
        9) wget -N https://gitlab.com/misakano7545/MisakaLinuxToolbox/-/raw/master/MisakaToolbox.sh && chmod -R 777 MisakaToolbox.sh && bash MisakaToolbox.sh ;;
        0) exit 0 ;;
	esac
}

page1() {
	echo "                            "
	green "请选择你接下来的操作"
	echo "                            "
	echo "1. Oracle Cloud原生系统关闭防火墙"
	echo "2. 开启VPS中所有的网络端口"
	echo "3. 德鸡DiG9正常访问网络解决方案"
	echo "4. 修改登录方式为 root + 密码 登录"
	echo "5. Screen 后台任务管理"
	echo "6. 开启BBR加速"
	echo "7. 设置DNS64服务器"
	echo "8. 安装WARP"
	echo "9. 安装docker"
	echo "10. Acme.sh 证书申请脚本"
	echo "11. CloudFlare Argo Tunnel一键脚本"
	echo "                            "
	echo "0. 返回主菜单"
	read -p "请输入选项:" page1NumberInput
	case "$page1NumberInput" in
        1) oraclefirewall ;;
        2) open_ports ;;
        3) euservDig9 ;;
        4) rootLogin ;;
        5) screenManager ;;
        6) bbr ;;
        7) dns64server ;;
        8) warp ;;
        9) dockerInstall ;;
        10) acmesh ;;
        11) cfArgoTunnel ;;
        0) menu ;;
	esac
}

page2() {
	echo "                            "
	green "请选择你准备安装的面板"
	echo "                            "
	echo "1. 安装宝塔面板"
	echo "2. 安装x-ui面板"
	echo "3. 安装aria2面板"
	echo "4. 安装CyberPanel面板"
	echo "5. 安装青龙面板"
	echo "6. 安装Trojan面板"
	echo "7. 安装V2ray.Fun面板"
	echo "                            "
	echo "0. 返回主菜单"
	read -p "请输入选项:" page2NumberInput
	case "$page2NumberInput" in
        1) bt ;;
        2) xui ;;
        3) aria2 ;;
        4) cyberpanel ;;
        5) qlPanel ;;
        6) trojanpanel ;;
        7) wget -N --no-check-certificate https://raw.githubusercontents.com/FunctionClub/V2ray.Fun/master/install.sh && bash install.sh ;;
        0) menu ;;
	esac
}

page3() {
	echo "                            "
	green "请选择你接下来使用的脚本"
	echo "                            "
	echo "1. 使用Mack-a的脚本"
	echo "2. 使用233boy的脚本"
	echo "3. 使用Misaka Xray的脚本"
	echo "4. 搭建Telegram MTProxy代理"
	echo "5. 使用Teddysun脚本搭建ShadowSocks"
	echo "                            "
	echo "0. 返回主菜单"
	read -p "请输入选项:" page3NumberInput
	case "$page3NumberInput" in
        1) macka ;;
        2) boy233 ;;
        3) misakaXray ;;
        4) tgMTProxy ;;
        5) shadowsocks ;;
        0) menu ;;
	esac
}

page4() {
	echo "                            "
	green "请选择你接下来的操作"
	echo "                            "
	echo "1. VPS测试"
	echo "2. 流媒体检测"
	echo "3. VPS三网测速"
	echo "                            "
	echo "0. 返回主菜单"
	read -p "请输入选项:" page4NumberInput
	case "$page4NumberInput" in
        1) vpsBench ;;
        2) mediaUnblockTest ;;
        3) speedTest ;;
        0) menu ;;
	esac
}

page5() {
	echo "                            "
	green "请选择你需要的探针"
	echo "                            "
	echo "1. 哪吒面板"
	echo "2. 可乐ServerStatus-Horatu"
	echo "                            "
	echo "0. 返回主菜单"
	read -p "请输入选项:" page5NumberInput
	case "$page5NumberInput" in
        1) nezha ;;
        2) serverstatus ;;
        0) menu ;;
	esac
}

menu