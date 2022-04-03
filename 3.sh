#!/usr/bin/env bash
#
# Description: Choose a faster mirror for Linux script
#
# Copyright (C) 2017 - 2018 Oldking <oooldking@gmail.com>
#
# URL: https://www.oldking.net/697.html
#

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
SKYBLUE='\033[0;36m'
PLAIN='\033[0m'

getAbout() {
	echo ""
	echo " ========================================================= "
	echo " \                 SuperUpdate.sh  Script                / "
	echo " \            Choose a faster mirror for Linux           / "
	echo " \                   Created by Oldking                  / "
	echo " ========================================================= "
	echo ""
	echo " Intro: https://www.oldking.net/697.html"
	echo " Copyright (C) 2018 Oldking oooldking@gmail.com"
	echo -e " Version: ${GREEN}1.0.3${PLAIN} (2 Nov 2018)"
	echo " Usage: wget -qO- git.io/superupdate.sh | bash"
	echo ""
}

getHelp() {
	echo " $(bash superupdate.sh)"
	ehco " - set sources from cdn-fastly "
	echo " $(bash superupdate.sh cn) "
	echo " - set sources from USTC "
	echo " $(bash superupdate.sh 163) "
	echo " - set sources from 163.com "
	echo " $(bash superupdate.sh aliyun) "
	echo " - set sources from aliyun.com "
	echo " $(bash superupdate.sh aws) "
	echo " - set sources from cdn-aws "
	echo " $(bash superupdate.sh restore) "
	echo " - restore sources from backup file "
}

updateInit() {
	[[ $EUID -ne 0 ]] && echo -e " ${RED}Error:${PLAIN} This script must be run as root!" && exit 1

	if [ -f /etc/redhat-release ]; then
		release="centos"
	elif cat /etc/issue | grep -Eqi "debian"; then
		release="debian"
	elif cat /etc/issue | grep -Eqi "ubuntu"; then
		release="ubuntu"
	elif cat /etc/issue | grep -Eqi "centos|red hat|redhat"; then
		release="centos"
	elif cat /proc/version | grep -Eqi "debian"; then
		release="debian"
	elif cat /proc/version | grep -Eqi "ubuntu"; then
		release="ubuntu"
	elif cat /proc/version | grep -Eqi "centos|red hat|redhat"; then
		release="centos"
	fi

	if [ $release == "debian" ]; then
		debianVersion=$(awk -F'[= "]' '/VERSION_ID/{print $3}' /etc/os-release)
	elif [ $release == "ubuntu" ]; then
		ubuntuVersion=$(awk -F'[= "]' '/VERSION_ID/{print $3}' /etc/os-release)
	elif [ $release == "centos" ]; then
		os_release=$(grep "CentOS" /etc/redhat-release 2>/dev/null)
		if echo "$os_release" | grep "release 5" >/dev/null 2>&1; then
			centosVersion=5
		elif echo "$os_release" | grep "release 6" >/dev/null 2>&1; then
			centosVersion=6
		elif echo "$os_release" | grep "release 7" >/dev/null 2>&1; then
			centosVersion=7
		else
			centosVersion=""
		fi
	else
		echo -e " ${RED}Error:${PLAIN} This script can not be run in your system now!" && exit 1
	fi
}

setDebian() {
	if [[ -f /etc/apt/sources.list.bak ]]; then
		echo -e " ${GREEN}sources.list.bak exists${PLAIN}"
	else
		mv /etc/apt/sources.list{,.bak}
	fi

	[ -f /etc/apt/sources.list ] && rm /etc/apt/sources.list

	echo "deb http://cdn-fastly.deb.debian.org/debian/ jessie main non-free contrib" >>/etc/apt/sources.list
	echo "deb http://cdn-fastly.deb.debian.org/debian/ jessie-updates main non-free contrib" >>/etc/apt/sources.list
	echo "deb http://cdn-fastly.deb.debian.org/debian/ jessie-backports main non-free contrib" >>/etc/apt/sources.list
	echo "deb-src http://cdn-fastly.deb.debian.org/debian/ jessie main non-free contrib" >>/etc/apt/sources.list
	echo "deb-src http://cdn-fastly.deb.debian.org/debian/ jessie-updates main non-free contrib" >>/etc/apt/sources.list
	echo "deb-src http://cdn-fastly.deb.debian.org/debian/ jessie-backports main non-free contrib" >>/etc/apt/sources.list
	echo "deb http://cdn-fastly.deb.debian.org/debian-security/ jessie/updates main non-free contrib" >>/etc/apt/sources.list
	echo "deb-src http://cdn-fastly.deb.debian.org/debian-security/ jessie/updates main non-free contrib" >>/etc/apt/sources.list

	[ "$debianVersion" == '7' ] && sed -i 's/jessie/wheezy/'g /etc/apt/sources.list
	[ "$debianVersion" == '8' ] && echo -n ""
	[ "$debianVersion" == '9' ] && sed -i 's/jessie/stretch/'g /etc/apt/sources.list
}

setUbuntu() {
	if [[ -f /etc/apt/sources.list.bak ]]; then
		echo -e " ${GREEN}sources.list.bak exists${PLAIN}"
	else
		mv /etc/apt/sources.list{,.bak}
	fi

	[ -f /etc/apt/sources.list ] && rm /etc/apt/sources.list

	echo "deb http://mirrors.aliyun.com/ubuntu/ xenial main restricted universe multiverse" >>/etc/apt/sources.list
	echo "deb http://mirrors.aliyun.com/ubuntu/ xenial-security main restricted universe multiverse" >>/etc/apt/sources.list
	echo "deb http://mirrors.aliyun.com/ubuntu/ xenial-updates main restricted universe multiverse" >>/etc/apt/sources.list
	echo "deb http://mirrors.aliyun.com/ubuntu/ xenial-backports main restricted universe multiverse" >>/etc/apt/sources.list
	echo "deb-src http://mirrors.aliyun.com/ubuntu/ xenial main restricted universe multiverse" >>/etc/apt/sources.list
	echo "deb-src http://mirrors.aliyun.com/ubuntu/ xenial-security main restricted universe multiverse" >>/etc/apt/sources.list
	echo "deb-src http://mirrors.aliyun.com/ubuntu/ xenial-updates main restricted universe multiverse" >>/etc/apt/sources.list
	echo "deb-src http://mirrors.aliyun.com/ubuntu/ xenial-backports main restricted universe multiverse" >>/etc/apt/sources.list

	[ "$ubuntuVersion" == '14.04' ] && sed -i 's/xenial/trusty/'g /etc/apt/sources.list
	[ "$ubuntuVersion" == '16.06' ] && echo -n ""
	[ "$ubuntuVersion" == '18.04' ] && sed -i 's/xenial/bionic/'g /etc/apt/sources.list
}

setCentos() {
	if [ -f /etc/yum.repos.d/CentOS-Base.repo.bak ]; then
		echo -e " ${GREEN}CentOS-Base.repo.bak exists${PLAIN}"
	else
		mv /etc/yum.repos.d/CentOS-Base.repo{,.bak}
	fi

	[ -f /etc/yum.repos.d/CentOS-Base.repo ] && rm /etc/yum.repos.d/CentOS-Base.repo

	[ "$centosVersion" == '5' ] && wget -O /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-5.repo
	[ "$centosVersion" == '6' ] && wget -O /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-6.repo
	[ "$centosVersion" == '7' ] && wget -O /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-7.repo
}

setAWS() {
	sed -i 's/cdn-fastly.deb.debian.org/cdn-aws.deb.debian.org/'g /etc/apt/sources.list
}

setCn() {
	sed -i 's/cdn-fastly.deb.debian.org/mirrors.ustc.edu.cn/'g /etc/apt/sources.list
}

set163() {
	sed -i 's/cdn-fastly.deb.debian.org/mirrors.163.com/'g /etc/apt/sources.list
}

setAliyun() {
	sed -i 's/cdn-fastly.deb.debian.org/mirrors.aliyun.com/'g /etc/apt/sources.list
}

restore() {
	if [ -f /etc/apt/sources.list.bak ]; then
		rm /etc/apt/sources.list
		mv /etc/apt/sources.list.bak /etc/apt/sources.list
	elif [ -f /etc/yum.repos.d/CentOS-Base.repo.bak ]; then
		rm /etc/yum.repos.d/CentOS-Base.repo
		mv /etc/yum.repos.d/CentOS-Base.repo.bak /etc/yum.repos.d/CentOS-Base.repo
	fi
}

setSources() {
	getAbout
	updateInit
	case "$release" in
	debian)
		case $para in
		'fastly' | '-fastly' | '--fastly')
			setDebian
			;;
		'cn' | '-cn' | '--cn')
			setDebian
			setCn
			;;
		'163' | '-163' | '--163')
			setDebian
			set163
			;;
		'aliyun' | '-aliyun' | '--aliyun')
			setDebian
			setAliyun
			;;
		'aws' | '-aws' | '--aws')
			setDebian
			setAWS
			;;
		'restore' | '-restore' | '--restore')
			restore
			;;
		*)
			setDebian
			;;
		esac
		apt-get update
		;;
	ubuntu)
		case $para in
		'restore' | '-restore' | '--restore')
			restore
			;;
		*)
			setUbuntu
			;;
		esac
		apt-get update
		;;
	centos)
		case $para in
		'restore' | '-restore' | '--restore')
			restore
			;;
		*)
			setCentos
			;;
		esac
		yum makecache
		;;
	esac
}

para=$1
setSources
echo -e "${GREEN}Done${PLAIN}"