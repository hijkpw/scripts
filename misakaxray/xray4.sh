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

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
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
[[ -z $(type -P curl) ]] && ${PACKAGE_UPDATE[int]} && ${PACKAGE_INSTALL[int]} curl

SITES=(
	http://www.zhuizishu.com/
	http://xs.56dyc.com/
	http://www.ddxsku.com/
	http://www.biqu6.com/
	https://www.wenshulou.cc/
	http://www.55shuba.com/
	http://www.39shubao.com/
	https://www.23xsw.cc/
	https://www.jueshitangmen.info/
	https://www.zhetian.org/
	http://www.bequgexs.com/
	http://www.tjwl.com/
)

CONFIG_FILE="/usr/local/etc/xray/config.json"

IP=$(curl -s4m8 ip.sb) || IP=$(curl -s6m8 ip.sb)

BT="false"
NGINX_CONF_PATH="/etc/nginx/conf.d/"
res=$(which bt 2>/dev/null)
[[ "$res" != "" ]] && BT="true" && NGINX_CONF_PATH="/www/server/panel/vhost/nginx/"

VLESS="false"
TROJAN="false"
TLS="false"
WS="false"
XTLS="false"
KCP="false"

checkCentOS8(){
    if [[ -n $(cat /etc/os-release | grep "CentOS Linux 8") ]]; then
        sed -i -e "s|releasever|releasever-stream|g" /etc/yum.repos.d/CentOS-*
        yum clean all && yum makecache
        dnf swap centos-linux-repos centos-stream-repos distro-sync -y
    fi
}

configNeedNginx() {
	local ws=$(grep wsSettings $CONFIG_FILE)
	[[ -z "$ws" ]] && echo no && return
	echo yes
}

needNginx() {
	[[ "$WS" == "false" ]] && echo no && return
	echo yes
}

status() {
	[[ ! -f /usr/local/bin/xray ]] && echo 0 && return
	[[ ! -f $CONFIG_FILE ]] && echo 1 && return
	port=$(grep port $CONFIG_FILE | head -n 1 | cut -d: -f2 | tr -d \",' ')
	res=$(ss -nutlp | grep ${port} | grep -i xray)
	[[ -z "$res" ]] && echo 2 && return

	if [[ $(configNeedNginx) != "yes" ]]; then
		echo 3
	else
		res=$(ss -nutlp | grep -i nginx)
		if [[ -z "$res" ]]; then
			echo 4
		else
			echo 5
		fi
	fi
}

statusText() {
	res=$(status)
	case $res in
		2) echo -e ${GREEN}已安装${PLAIN} ${RED}未运行${PLAIN} ;;
		3) echo -e ${GREEN}已安装${PLAIN} ${GREEN}Xray正在运行${PLAIN} ;;
		4) echo -e ${GREEN}已安装${PLAIN} ${GREEN}Xray正在运行${PLAIN}, ${RED}Nginx未运行${PLAIN} ;;
		5) echo -e ${GREEN}已安装${PLAIN} ${GREEN}Xray正在运行, Nginx正在运行${PLAIN} ;;
		*) echo -e ${RED}未安装${PLAIN} ;;
	esac
}

normalizeVersion() {
	latestXrayVer=v$(curl -Ls "https://data.jsdelivr.com/v1/package/resolve/gh/XTLS/Xray-core" | grep '"version":' | sed -E 's/.*"([^"]+)".*/\1/')
	if [ -n "$1" ]; then
		case "$1" in
			v*) echo "$1" ;;
			http*) echo $latestXrayVer ;;
			*) echo "v$1" ;;
		esac
	else
		echo ""
	fi
}

# 1: new Xray. 0: no. 1: yes. 2: not installed. 3: check failed.
getVersion() {
	VER=$(/usr/local/bin/xray version 2>/dev/null | head -n1 | awk '{print $2}')
	RETVAL=$?
	CUR_VER="$(normalizeVersion "$(echo "$VER" | head -n 1 | cut -d " " -f2)")"
	TAG_URL="https://data.jsdelivr.com/v1/package/resolve/gh/XTLS/Xray-core"
	NEW_VER="$(normalizeVersion "$(curl -s "${TAG_URL}" --connect-timeout 10 | grep 'version' | cut -d\" -f4)")"

	if [[ $? -ne 0 ]] || [[ $NEW_VER == "" ]]; then
		red "检测 Xray 版本失败，可能是超出 Github API 限制，请稍后再试"
		return 3
	elif [[ $RETVAL -ne 0 ]]; then
		return 2
	elif [[ $NEW_VER != $CUR_VER ]]; then
		return 1
	fi
	return 0
}

archAffix() {
	case "$(uname -m)" in
		i686 | i386) echo '32' ;;
		x86_64 | amd64) echo '64' ;;
		armv5tel) echo 'arm32-v5' ;;
		armv6l) echo 'arm32-v6' ;;
		armv7 | armv7l) echo 'arm32-v7a' ;;
		armv8 | aarch64) echo 'arm64-v8a' ;;
		mips64le) echo 'mips64le' ;;
		mips64) echo 'mips64' ;;
		mipsle) echo 'mips32le' ;;
		mips) echo 'mips32' ;;
		ppc64le) echo 'ppc64le' ;;
		ppc64) echo 'ppc64' ;;
		ppc64le) echo 'ppc64le' ;;
		riscv64) echo 'riscv64' ;;
		s390x) echo 's390x' ;;
		*) red " 不支持的CPU架构！" && exit 1 ;;
	esac

	return 0
}

getData() {
	if [[ "$TLS" == "true" || "$XTLS" == "true" ]]; then
		echo ""
		echo "Xray一键脚本，运行之前请确认如下条件已经具备："
		yellow " 1. 一个伪装域名"
		yellow " 2. 伪装域名DNS解析指向当前服务器ip（${IP}）"
		yellow " 3. 如果/root目录下有 xray.pem 和 xray.key 证书密钥文件，无需理会条件2"
		echo " "
		read -p "确认满足以上条件请按y，按其他键退出脚本：" answer
		[[ "${answer,,}" != "y" ]] && exit 1
		echo ""
		while true; do
			read -p "请输入伪装域名：" DOMAIN
			if [[ -z "${DOMAIN}" ]]; then
				red " 域名输入错误，请重新输入！"
			else
				break
			fi
		done
		DOMAIN=${DOMAIN,,}
		yellow "伪装域名(host)：$DOMAIN"
		echo ""
		if [[ -f ~/xray.pem && -f ~/xray.key ]]; then
			yellow "检测到自有证书，将使用自有证书部署"
			CERT_FILE="/usr/local/etc/xray/${DOMAIN}.pem"
			KEY_FILE="/usr/local/etc/xray/${DOMAIN}.key"
		else
			resolve=$(curl -sm8 ipget.net/?ip=${DOMAIN})
			if [[ $resolve != $IP ]]; then
				yellow "${DOMAIN} 解析结果：${resolve}"
				red "域名未解析到当前服务器IP(${IP})！"
				green "建议如下："
				yellow " 1. 请确保Cloudflare小云朵为关闭状态(仅限DNS)，其他域名解析网站设置同理"
				yellow " 2. 请检查DNS解析设置的IP是否为VPS的IP"
				yellow " 3. 脚本可能跟不上时代，建议截图发布到GitHub Issues或TG群询问"
				exit 1
			fi
		fi
	fi
	echo ""
	if [[ "$(needNginx)" == "no" ]]; then
		if [[ "$TLS" == "true" ]]; then
			read -p "请输入xray监听端口 [默认443]：" PORT
			[[ -z "${PORT}" ]] && PORT=443
		else
			read -p "请输入xray监听端口 [100-65535的一个数字]：" PORT
			[[ -z "${PORT}" ]] && PORT=$(shuf -i200-65000 -n1)
			if [[ "${PORT:0:1}" == "0" ]]; then
				red "端口不能以0开头"
				exit 1
			fi
		fi
		yellow "xray端口：$PORT"
	else
		read -p "请输入Nginx监听端口[100-65535的一个数字，默认443]：" PORT
		[[ -z "${PORT}" ]] && PORT=443
		[ "${PORT:0:1}" = "0" ] && red "端口不能以0开头" && exit 1
		yellow " Nginx端口：$PORT"
		XPORT=$(shuf -i10000-65000 -n1)
	fi
	if [[ "$KCP" == "true" ]]; then
		echo ""
		yellow "请选择伪装类型："
		echo "   1) 无"
		echo "   2) BT下载"
		echo "   3) 视频通话"
		echo "   4) 微信视频通话"
		echo "   5) dtls"
		echo "   6) wiregard"
		read -p "请选择伪装类型[默认：无]：" answer
		case $answer in
			2) HEADER_TYPE="utp" ;;
			3) HEADER_TYPE="srtp" ;;
			4) HEADER_TYPE="wechat-video" ;;
			5) HEADER_TYPE="dtls" ;;
			6) HEADER_TYPE="wireguard" ;;
			*) HEADER_TYPE="none" ;;
		esac
		yellow "伪装类型：$HEADER_TYPE"
		SEED=$(cat /proc/sys/kernel/random/uuid)
	fi
	if [[ "$TROJAN" == "true" ]]; then
		echo ""
		read -p "请设置trojan密码（不输则随机生成）:" PASSWORD
		[[ -z "$PASSWORD" ]] && PASSWORD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
		yellow " trojan密码：$PASSWORD"
	fi
	if [[ "$XTLS" == "true" ]]; then
		echo ""
		yellow "请选择流控模式:"
		echo -e "   1) xtls-rprx-direct [$RED推荐$PLAIN]"
		echo "   2) xtls-rprx-origin"
		read -p "请选择流控模式[默认:direct]" answer
		[[ -z "$answer" ]] && answer=1
		case $answer in
			1) FLOW="xtls-rprx-direct" ;;
			2) FLOW="xtls-rprx-origin" ;;
			*) red "无效选项，使用默认的xtls-rprx-direct" && FLOW="xtls-rprx-direct" ;;
		esac
		yellow "流控模式：$FLOW"
	fi
	if [[ "${WS}" == "true" ]]; then
		echo ""
		while true; do
			read -p "请输入伪装路径，以/开头(不懂请直接回车)：" WSPATH
			if [[ -z "${WSPATH}" ]]; then
				len=$(shuf -i5-12 -n1)
				ws=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w $len | head -n 1)
				WSPATH="/$ws"
				break
			elif [[ "${WSPATH:0:1}" != "/" ]]; then
				red "伪装路径必须以/开头！"
			elif [[ "${WSPATH}" == "/" ]]; then
				red "不能使用根路径！"
			else
				break
			fi
		done
		yellow "ws路径：$WSPATH"
	fi
	if [[ "$TLS" == "true" || "$XTLS" == "true" ]]; then
		echo ""
		yellow "请选择伪装站类型:"
		echo "   1) 静态网站(位于/usr/share/nginx/html)"
		echo "   2) 小说站(随机选择)"
		echo "   3) 高清壁纸站(https://bing.ioliu.cn)"
		echo "   4) 自定义反代站点(需以http或者https开头)"
		read -p "请选择伪装网站类型 [默认:高清壁纸站]：" answer
		if [[ -z "$answer" ]]; then
			PROXY_URL="https://bing.ioliu.cn"
		else
			case $answer in
				1) PROXY_URL="" ;;
				2)
					len=${#SITES[@]}
					((len--))
					while true; do
						index=$(shuf -i0-${len} -n1)
						PROXY_URL=${SITES[$index]}
						host=$(echo ${PROXY_URL} | cut -d/ -f3)
						ip=$(curl -sm8 ipget.net/?ip=${host})
						res=$(echo -n ${ip} | grep ${host})
						if [[ "${res}" == "" ]]; then
							echo "$ip $host" >>/etc/hosts
							break
						fi
					done
					;;
				3) PROXY_URL="https://bing.ioliu.cn" ;;
				4)
					read -p "请输入反代站点(以http或者https开头)：" PROXY_URL
					if [[ -z "$PROXY_URL" ]]; then
						red "请输入反代网站！"
						exit 1
					elif [[ "${PROXY_URL:0:4}" != "http" ]]; then
						red "反代网站必须以http或https开头！"
						exit 1
					fi
					;;
				*) red "请输入正确的选项！" && exit 1 ;;
			esac
		fi
		REMOTE_HOST=$(echo ${PROXY_URL} | cut -d/ -f3)
		yellow "伪装网站：$PROXY_URL"
		echo ""
		yellow "是否允许搜索引擎爬取网站？[默认：不允许]"
		echo "   y)允许，会有更多ip请求网站，但会消耗一些流量，vps流量充足情况下推荐使用"
		echo "   n)不允许，爬虫不会访问网站，访问ip比较单一，但能节省vps流量"
		read -p "请选择：[y/n]" answer
		if [[ -z "$answer" ]]; then
			ALLOW_SPIDER="n"
		elif [[ "${answer,,}" == "y" ]]; then
			ALLOW_SPIDER="y"
		else
			ALLOW_SPIDER="n"
		fi
		yellow "允许搜索引擎：$ALLOW_SPIDER"
	fi
	echo ""
	read -p "是否安装BBR(默认安装)?[y/n]:" NEED_BBR
	[[ -z "$NEED_BBR" ]] && NEED_BBR=y
	[[ "$NEED_BBR" == "Y" ]] && NEED_BBR=y
	yellow "安装BBR：$NEED_BBR"
}

installNginx() {
	echo ""
	yellow "正在安装nginx..."
	if [[ "$BT" == "false" ]]; then
		if [[ $SYSTEM == "CentOS" ]]; then
			${PACKAGE_INSTALL[int]} epel-release
			if [[ "$?" != "0" ]]; then
				echo '[nginx-stable]
name=nginx stable repo
baseurl=http://nginx.org/packages/centos/$releasever/$basearch/
gpgcheck=1
enabled=1
gpgkey=https://nginx.org/keys/nginx_signing.key
module_hotfixes=true' >/etc/yum.repos.d/nginx.repo
			fi
		fi
		${PACKAGE_INSTALL[int]} nginx
		if [[ "$?" != "0" ]]; then
			red "Nginx安装失败！"
			green "建议如下："
			yellow "1. 检查VPS系统的网络设置和软件源设置，强烈建议使用系统官方软件源！"
			yellow "2. 你可能用的是CentOS 8操作系统，请重置系统为CentOS 7后再安装本脚本"
			yellow "3. 脚本可能跟不上时代，建议截图发布到GitHub Issues或TG群询问"
			exit 1
		fi
		systemctl enable nginx
	else
		res=$(which nginx 2>/dev/null)
		if [[ "$?" != "0" ]]; then
			red "您安装了宝塔，请在宝塔后台安装nginx后再运行本脚本"
			exit 1
		fi
	fi
}

startNginx() {
	if [[ "$BT" == "false" ]]; then
		systemctl start nginx
	else
		nginx -c /www/server/nginx/conf/nginx.conf
	fi
}

stopNginx() {
	if [[ "$BT" == "false" ]]; then
		systemctl stop nginx
	else
		res=$(ps aux | grep -i nginx)
		if [[ "$res" != "" ]]; then
			nginx -s stop
		fi
	fi
}

getCert() {
	mkdir -p /usr/local/etc/xray
	if [[ -z ${CERT_FILE+x} ]]; then
		stopNginx
		systemctl stop xray
		res=$(netstat -ntlp | grep -E ':80 |:443 ')
		if [[ "${res}" != "" ]]; then
			red "其他进程占用了80或443端口，请先关闭再运行一键脚本"
			echo " 端口占用信息如下："
			echo ${res}
			exit 1
		fi
		${PACKAGE_INSTALL[int]} socat openssl
		if [[ $SYSTEM == "CentOS" ]]; then
			${PACKAGE_INSTALL[int]} cronie
			systemctl start crond
			systemctl enable crond
		else
			${PACKAGE_INSTALL[int]} cron
			systemctl start cron
			systemctl enable cron
		fi
		curl -sL https://get.acme.sh | sh -s email=hijk.pw@protonmail.sh
		source ~/.bashrc
		~/.acme.sh/acme.sh --upgrade --auto-upgrade
		~/.acme.sh/acme.sh --set-default-ca --server zerossl
		if [[ $BT == "false" ]]; then
			if [[ -n $(curl -sm8 ip.sb | grep ":") ]]; then
				~/.acme.sh/acme.sh --issue -d $DOMAIN --keylength ec-256 --pre-hook "systemctl stop nginx" --post-hook "systemctl restart nginx" --standalone --listen-v6
			else
				~/.acme.sh/acme.sh --issue -d $DOMAIN --keylength ec-256 --pre-hook "systemctl stop nginx" --post-hook "systemctl restart nginx" --standalone
			fi
		else
			if [[ -n $(curl -sm8 ip.sb | grep ":") ]]; then
				~/.acme.sh/acme.sh --issue -d $DOMAIN --keylength ec-256 --pre-hook "nginx -s stop || { echo -n ''; }" --post-hook "nginx -c /www/server/nginx/conf/nginx.conf || { echo -n ''; }" --standalone --listen-v6
			else
				~/.acme.sh/acme.sh --issue -d $DOMAIN --keylength ec-256 --pre-hook "nginx -s stop || { echo -n ''; }" --post-hook "nginx -c /www/server/nginx/conf/nginx.conf || { echo -n ''; }" --standalone
			fi
		fi
		[[ -f ~/.acme.sh/${DOMAIN}_ecc/ca.cer ]] || {
			red "抱歉，证书申请失败"
			green "建议如下："
			yellow " 1. 自行检测防火墙是否打开，如防火墙正在开启，请关闭防火墙或放行80端口"
			yellow " 2. 同一域名多次申请触发Acme.sh官方风控，请更换域名或等待7天后再尝试执行脚本"
			yellow " 3. 脚本可能跟不上时代，建议截图发布到GitHub Issues或TG群询问"
			exit 1
		}
		CERT_FILE="/usr/local/etc/xray/${DOMAIN}.pem"
		KEY_FILE="/usr/local/etc/xray/${DOMAIN}.key"
		~/.acme.sh/acme.sh --install-cert -d $DOMAIN --ecc \
		--key-file $KEY_FILE \
		--fullchain-file $CERT_FILE \
		--reloadcmd "service nginx force-reload"
		[[ -f $CERT_FILE && -f $KEY_FILE ]] || {
			red "抱歉，证书申请失败"
			green "建议如下："
			yellow " 1. 自行检测防火墙是否打开，如防火墙正在开启，请关闭防火墙或放行80端口"
			yellow " 2. 同一域名多次申请触发Acme.sh官方风控，请更换域名或等待7天后再尝试执行脚本"
			yellow " 3. 脚本可能跟不上时代，建议截图发布到GitHub Issues或TG群询问"
			exit 1
		}
	else
		cp ~/xray.pem /usr/local/etc/xray/${DOMAIN}.pem
		cp ~/xray.key /usr/local/etc/xray/${DOMAIN}.key
	fi
}

configNginx() {
	mkdir -p /usr/share/nginx/html
	if [[ "$ALLOW_SPIDER" == "n" ]]; then
		echo 'User-Agent: *' >/usr/share/nginx/html/robots.txt
		echo 'Disallow: /' >>/usr/share/nginx/html/robots.txt
		ROBOT_CONFIG="    location = /robots.txt {}"
	else
		ROBOT_CONFIG=""
	fi

	if [[ "$BT" == "false" ]]; then
		if [[ ! -f /etc/nginx/nginx.conf.bak ]]; then
			mv /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak
		fi
		res=$(id nginx 2>/dev/null)
		if [[ "$?" != "0" ]]; then
			user="www-data"
		else
			user="nginx"
		fi
		cat >/etc/nginx/nginx.conf <<-EOF
			user $user;
			worker_processes auto;
			error_log /var/log/nginx/error.log;
			pid /run/nginx.pid;
			
			# Load dynamic modules. See /usr/share/doc/nginx/README.dynamic.
			include /usr/share/nginx/modules/*.conf;
			
			events {
			    worker_connections 1024;
			}
			
			http {
			    log_format  main  '\$remote_addr - \$remote_user [\$time_local] "\$request" '
			                      '\$status \$body_bytes_sent "\$http_referer" '
			                      '"\$http_user_agent" "\$http_x_forwarded_for"';
			
			    access_log  /var/log/nginx/access.log  main;
			    server_tokens off;
			
			    sendfile            on;
			    tcp_nopush          on;
			    tcp_nodelay         on;
			    keepalive_timeout   65;
			    types_hash_max_size 2048;
			    gzip                on;
			
			    include             /etc/nginx/mime.types;
			    default_type        application/octet-stream;
			
			    # Load modular configuration files from the /etc/nginx/conf.d directory.
			    # See http://nginx.org/en/docs/ngx_core_module.html#include
			    # for more information.
			    include /etc/nginx/conf.d/*.conf;
			}
		EOF
	fi

	if [[ "$PROXY_URL" == "" ]]; then
		action=""
	else
		action="proxy_ssl_server_name on;
        proxy_pass $PROXY_URL;
        proxy_set_header Accept-Encoding '';
        sub_filter \"$REMOTE_HOST\" \"$DOMAIN\";
        sub_filter_once off;"
	fi

	if [[ "$TLS" == "true" || "$XTLS" == "true" ]]; then
		mkdir -p ${NGINX_CONF_PATH}
		# VMESS+WS+TLS
		# VLESS+WS+TLS
		if [[ "$WS" == "true" ]]; then
			cat >${NGINX_CONF_PATH}${DOMAIN}.conf <<-EOF
				server {
				    listen 80;
				    listen [::]:80;
				    server_name ${DOMAIN};
				    return 301 https://\$server_name:${PORT}\$request_uri;
				}
				
				server {
				    listen       ${PORT} ssl http2;
				    listen       [::]:${PORT} ssl http2;
				    server_name ${DOMAIN};
				    charset utf-8;
				
				    # ssl配置
				    ssl_protocols TLSv1.1 TLSv1.2;
				    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE:ECDH:AES:HIGH:!NULL:!aNULL:!MD5:!ADH:!RC4;
				    ssl_ecdh_curve secp384r1;
				    ssl_prefer_server_ciphers on;
				    ssl_session_cache shared:SSL:10m;
				    ssl_session_timeout 10m;
				    ssl_session_tickets off;
				    ssl_certificate $CERT_FILE;
				    ssl_certificate_key $KEY_FILE;
				
				    root /usr/share/nginx/html;
				    location / {
				        $action
				    }
				    $ROBOT_CONFIG
				
				    location ${WSPATH} {
				      proxy_redirect off;
				      proxy_pass http://127.0.0.1:${XPORT};
				      proxy_http_version 1.1;
				      proxy_set_header Upgrade \$http_upgrade;
				      proxy_set_header Connection "upgrade";
				      proxy_set_header Host \$host;
				      proxy_set_header X-Real-IP \$remote_addr;
				      proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
				    }
				}
			EOF
		else
			# VLESS+TCP+TLS
			# VLESS+TCP+XTLS
			# trojan
			cat >${NGINX_CONF_PATH}${DOMAIN}.conf <<-EOF
				server {
				    listen 80;
				    listen [::]:80;
				    listen 81 http2;
				    server_name ${DOMAIN};
				    root /usr/share/nginx/html;
				    location / {
				        $action
				    }
				    $ROBOT_CONFIG
				}
			EOF
		fi
	fi
}

setSelinux() {
	if [[ -s /etc/selinux/config ]] && grep 'SELINUX=enforcing' /etc/selinux/config; then
		sed -i 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/selinux/config
		setenforce 0
	fi
}

setFirewall() {
	res=$(which firewall-cmd 2>/dev/null)
	if [[ $? -eq 0 ]]; then
		systemctl status firewalld >/dev/null 2>&1
		if [[ $? -eq 0 ]]; then
			firewall-cmd --permanent --add-service=http
			firewall-cmd --permanent --add-service=https
			if [[ "$PORT" != "443" ]]; then
				firewall-cmd --permanent --add-port=${PORT}/tcp
				firewall-cmd --permanent --add-port=${PORT}/udp
			fi
			firewall-cmd --reload
		else
			nl=$(iptables -nL | nl | grep FORWARD | awk '{print $1}')
			if [[ "$nl" != "3" ]]; then
				iptables -I INPUT -p tcp --dport 80 -j ACCEPT
				iptables -I INPUT -p tcp --dport 443 -j ACCEPT
				if [[ "$PORT" != "443" ]]; then
					iptables -I INPUT -p tcp --dport ${PORT} -j ACCEPT
					iptables -I INPUT -p udp --dport ${PORT} -j ACCEPT
				fi
			fi
		fi
	else
		res=$(which iptables 2>/dev/null)
		if [[ $? -eq 0 ]]; then
			nl=$(iptables -nL | nl | grep FORWARD | awk '{print $1}')
			if [[ "$nl" != "3" ]]; then
				iptables -I INPUT -p tcp --dport 80 -j ACCEPT
				iptables -I INPUT -p tcp --dport 443 -j ACCEPT
				if [[ "$PORT" != "443" ]]; then
					iptables -I INPUT -p tcp --dport ${PORT} -j ACCEPT
					iptables -I INPUT -p udp --dport ${PORT} -j ACCEPT
				fi
			fi
		else
			res=$(which ufw 2>/dev/null)
			if [[ $? -eq 0 ]]; then
				res=$(ufw status | grep -i inactive)
				if [[ "$res" == "" ]]; then
					ufw allow http/tcp
					ufw allow https/tcp
					if [[ "$PORT" != "443" ]]; then
						ufw allow ${PORT}/tcp
						ufw allow ${PORT}/udp
					fi
				fi
			fi
		fi
	fi
}

installBBR() {
	if [[ "$NEED_BBR" != "y" ]]; then
		INSTALL_BBR=false
		return
	fi
	result=$(lsmod | grep bbr)
	if [[ "$result" != "" ]]; then
		yellow " BBR模块已安装"
		INSTALL_BBR=false
		return
	fi
	res=$(systemd-detect-virt)
	if [[ $res =~ lxc|openvz ]]; then
		yellow " 由于你的VPS为OpenVZ或LXC架构的VPS，跳过安装"
		INSTALL_BBR=false
		return
	fi
	echo "net.core.default_qdisc=fq" >>/etc/sysctl.conf
	echo "net.ipv4.tcp_congestion_control=bbr" >>/etc/sysctl.conf
	sysctl -p
	result=$(lsmod | grep bbr)
	if [[ "$result" != "" ]]; then
		green " BBR模块已启用"
		INSTALL_BBR=false
		return
	fi
	yellow " 安装BBR模块..."
	if [[ $SYSTEM == "CentOS" ]]; then
		if [[ "$V6_PROXY" == "" ]]; then
			rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
			rpm -Uvh http://www.elrepo.org/elrepo-release-7.0-4.el7.elrepo.noarch.rpm
			${PACKAGE_INSTALL[int]} --enablerepo=elrepo-kernel kernel-ml
			${PACKAGE_UNINSTALL[int]} kernel-3.*
			grub2-set-default 0
			echo "tcp_bbr" >>/etc/modules-load.d/modules.conf
			INSTALL_BBR=true
		fi
	else
		${PACKAGE_INSTALL[int]} --install-recommends linux-generic-hwe-16.04
		grub-set-default 0
		echo "tcp_bbr" >>/etc/modules-load.d/modules.conf
		INSTALL_BBR=true
	fi
}

installXray() {
	rm -rf /tmp/xray
	mkdir -p /tmp/xray
	DOWNLOAD_LINK="https://github.com/XTLS/Xray-core/releases/download/${NEW_VER}/Xray-linux-$(archAffix).zip"
	yellow "正在下载Xray文件"
	curl -L -H "Cache-Control: no-cache" -o /tmp/xray/xray.zip ${DOWNLOAD_LINK}
	if [ $? != 0 ]; then
		red "下载Xray文件失败，请检查服务器网络设置"
		exit 1
	fi
	systemctl stop xray
	mkdir -p /usr/local/etc/xray /usr/local/share/xray && \
	unzip /tmp/xray/xray.zip -d /tmp/xray
	cp /tmp/xray/xray /usr/local/bin
	cp /tmp/xray/geo* /usr/local/share/xray
	chmod +x /usr/local/bin/xray || {
		red "Xray安装失败"
		exit 1
	}

	cat >/etc/systemd/system/xray.service <<-EOF
		[Unit]
		Description=Xray Service by Misaka-blog
		Documentation=https://github.com/Misaka-blog
		After=network.target nss-lookup.target
		
		[Service]
		User=root
		#User=nobody
		#CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
		#AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
		NoNewPrivileges=true
		ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
		Restart=on-failure
		RestartPreventExitStatus=23
		
		[Install]
		WantedBy=multi-user.target
	EOF
	systemctl daemon-reload
	systemctl enable xray.service
}

trojanConfig() {
	cat >$CONFIG_FILE <<-EOF
		{
		  "inbounds": [{
		    "port": $PORT,
		    "protocol": "trojan",
		    "settings": {
		      "clients": [
		        {
		          "password": "$PASSWORD"
		        }
		      ],
		      "fallbacks": [
		        {
		              "alpn": "http/1.1",
		              "dest": 80
		          },
		          {
		              "alpn": "h2",
		              "dest": 81
		          }
		      ]
		    },
		    "streamSettings": {
		        "network": "tcp",
		        "security": "tls",
		        "tlsSettings": {
		            "serverName": "$DOMAIN",
		            "alpn": ["http/1.1", "h2"],
		            "certificates": [
		                {
		                    "certificateFile": "$CERT_FILE",
		                    "keyFile": "$KEY_FILE"
		                }
		            ]
		        }
		    }
		  }],
		  "outbounds": [{
		    "protocol": "freedom",
		    "settings": {}
		  },{
		    "protocol": "blackhole",
		    "settings": {},
		    "tag": "blocked"
		  }]
		}
	EOF
}

trojanXTLSConfig() {
	cat >$CONFIG_FILE <<-EOF
		{
		  "inbounds": [{
		    "port": $PORT,
		    "protocol": "trojan",
		    "settings": {
		      "clients": [
		        {
		          "password": "$PASSWORD",
		          "flow": "$FLOW"
		        }
		      ],
		      "fallbacks": [
		        {
		              "alpn": "http/1.1",
		              "dest": 80
		          },
		          {
		              "alpn": "h2",
		              "dest": 81
		          }
		      ]
		    },
		    "streamSettings": {
		        "network": "tcp",
		        "security": "xtls",
		        "xtlsSettings": {
		            "serverName": "$DOMAIN",
		            "alpn": ["http/1.1", "h2"],
		            "certificates": [
		                {
		                    "certificateFile": "$CERT_FILE",
		                    "keyFile": "$KEY_FILE"
		                }
		            ]
		        }
		    }
		  }],
		  "outbounds": [{
		    "protocol": "freedom",
		    "settings": {}
		  },{
		    "protocol": "blackhole",
		    "settings": {},
		    "tag": "blocked"
		  }]
		}
	EOF
}

vmessConfig() {
	local uuid="$(cat '/proc/sys/kernel/random/uuid')"
	cat >$CONFIG_FILE <<-EOF
		{
		  "inbounds": [{
		    "port": $PORT,
		    "protocol": "vmess",
		    "settings": {
		      "clients": [
		        {
		          "id": "$uuid",
		          "level": 1,
		          "alterId": 0
		        }
		      ]
		    }
		  }],
		  "outbounds": [{
		    "protocol": "freedom",
		    "settings": {}
		  },{
		    "protocol": "blackhole",
		    "settings": {},
		    "tag": "blocked"
		  }]
		}
	EOF
}

vmessKCPConfig() {
	local uuid="$(cat '/proc/sys/kernel/random/uuid')"
	cat >$CONFIG_FILE <<-EOF
		{
		  "inbounds": [{
		    "port": $PORT,
		    "protocol": "vmess",
		    "settings": {
		      "clients": [
		        {
		          "id": "$uuid",
		          "level": 1,
		          "alterId": 0
		        }
		      ]
		    },
		    "streamSettings": {
		        "network": "mkcp",
		        "kcpSettings": {
		            "uplinkCapacity": 100,
		            "downlinkCapacity": 100,
		            "congestion": true,
		            "header": {
		                "type": "$HEADER_TYPE"
		            },
		            "seed": "$SEED"
		        }
		    }
		  }],
		  "outbounds": [{
		    "protocol": "freedom",
		    "settings": {}
		  },{
		    "protocol": "blackhole",
		    "settings": {},
		    "tag": "blocked"
		  }]
		}
	EOF
}

vmessTLSConfig() {
	local uuid="$(cat '/proc/sys/kernel/random/uuid')"
	cat >$CONFIG_FILE <<-EOF
		{
		  "inbounds": [{
		    "port": $PORT,
		    "protocol": "vmess",
		    "settings": {
		      "clients": [
		        {
		          "id": "$uuid",
		          "level": 1,
		          "alterId": 0
		        }
		      ],
		      "disableInsecureEncryption": false
		    },
		    "streamSettings": {
		        "network": "tcp",
		        "security": "tls",
		        "tlsSettings": {
		            "serverName": "$DOMAIN",
		            "alpn": ["http/1.1", "h2"],
		            "certificates": [
		                {
		                    "certificateFile": "$CERT_FILE",
		                    "keyFile": "$KEY_FILE"
		                }
		            ]
		        }
		    }
		  }],
		  "outbounds": [{
		    "protocol": "freedom",
		    "settings": {}
		  },{
		    "protocol": "blackhole",
		    "settings": {},
		    "tag": "blocked"
		  }]
		}
	EOF
}

vmessWSConfig() {
	local uuid="$(cat '/proc/sys/kernel/random/uuid')"
	cat >$CONFIG_FILE <<-EOF
		{
		  "inbounds": [{
		    "port": $XPORT,
		    "listen": "127.0.0.1",
		    "protocol": "vmess",
		    "settings": {
		      "clients": [
		        {
		          "id": "$uuid",
		          "level": 1,
		          "alterId": 0
		        }
		      ],
		      "disableInsecureEncryption": false
		    },
		    "streamSettings": {
		        "network": "ws",
		        "wsSettings": {
		            "path": "$WSPATH",
		            "headers": {
		                "Host": "$DOMAIN"
		            }
		        }
		    }
		  }],
		  "outbounds": [{
		    "protocol": "freedom",
		    "settings": {}
		  },{
		    "protocol": "blackhole",
		    "settings": {},
		    "tag": "blocked"
		  }]
		}
	EOF
}

vlessTLSConfig() {
	local uuid="$(cat '/proc/sys/kernel/random/uuid')"
	cat >$CONFIG_FILE <<-EOF
		{
		  "inbounds": [{
		    "port": $PORT,
		    "protocol": "vless",
		    "settings": {
		      "clients": [
		        {
		          "id": "$uuid",
		          "level": 0
		        }
		      ],
		      "decryption": "none",
		      "fallbacks": [
		          {
		              "alpn": "http/1.1",
		              "dest": 80
		          },
		          {
		              "alpn": "h2",
		              "dest": 81
		          }
		      ]
		    },
		    "streamSettings": {
		        "network": "tcp",
		        "security": "tls",
		        "tlsSettings": {
		            "serverName": "$DOMAIN",
		            "alpn": ["http/1.1", "h2"],
		            "certificates": [
		                {
		                    "certificateFile": "$CERT_FILE",
		                    "keyFile": "$KEY_FILE"
		                }
		            ]
		        }
		    }
		  }],
		  "outbounds": [{
		    "protocol": "freedom",
		    "settings": {}
		  },{
		    "protocol": "blackhole",
		    "settings": {},
		    "tag": "blocked"
		  }]
		}
	EOF
}

vlessXTLSConfig() {
	local uuid="$(cat '/proc/sys/kernel/random/uuid')"
	cat >$CONFIG_FILE <<-EOF
		{
		  "inbounds": [{
		    "port": $PORT,
		    "protocol": "vless",
		    "settings": {
		      "clients": [
		        {
		          "id": "$uuid",
		          "flow": "$FLOW",
		          "level": 0
		        }
		      ],
		      "decryption": "none",
		      "fallbacks": [
		          {
		              "alpn": "http/1.1",
		              "dest": 80
		          },
		          {
		              "alpn": "h2",
		              "dest": 81
		          }
		      ]
		    },
		    "streamSettings": {
		        "network": "tcp",
		        "security": "xtls",
		        "xtlsSettings": {
		            "serverName": "$DOMAIN",
		            "alpn": ["http/1.1", "h2"],
		            "certificates": [
		                {
		                    "certificateFile": "$CERT_FILE",
		                    "keyFile": "$KEY_FILE"
		                }
		            ]
		        }
		    }
		  }],
		  "outbounds": [{
		    "protocol": "freedom",
		    "settings": {}
		  },{
		    "protocol": "blackhole",
		    "settings": {},
		    "tag": "blocked"
		  }]
		}
	EOF
}

vlessWSConfig() {
	local uuid="$(cat '/proc/sys/kernel/random/uuid')"
	cat >$CONFIG_FILE <<-EOF
		{
		  "inbounds": [{
		    "port": $XPORT,
		    "listen": "127.0.0.1",
		    "protocol": "vless",
		    "settings": {
		        "clients": [
		            {
		                "id": "$uuid",
		                "level": 0
		            }
		        ],
		        "decryption": "none"
		    },
		    "streamSettings": {
		        "network": "ws",
		        "security": "none",
		        "wsSettings": {
		            "path": "$WSPATH",
		            "headers": {
		                "Host": "$DOMAIN"
		            }
		        }
		    }
		  }],
		  "outbounds": [{
		    "protocol": "freedom",
		    "settings": {}
		  },{
		    "protocol": "blackhole",
		    "settings": {},
		    "tag": "blocked"
		  }]
		}
	EOF
}

vlessKCPConfig() {
	local uuid="$(cat '/proc/sys/kernel/random/uuid')"
	cat >$CONFIG_FILE <<-EOF
		{
		  "inbounds": [{
		    "port": $PORT,
		    "protocol": "vless",
		    "settings": {
		      "clients": [
		        {
		          "id": "$uuid",
		          "level": 0
		        }
		      ],
		      "decryption": "none"
		    },
		    "streamSettings": {
		        "streamSettings": {
		            "network": "mkcp",
		            "kcpSettings": {
		                "uplinkCapacity": 100,
		                "downlinkCapacity": 100,
		                "congestion": true,
		                "header": {
		                    "type": "$HEADER_TYPE"
		                },
		                "seed": "$SEED"
		            }
		        }
		    }
		  }],
		  "outbounds": [{
		    "protocol": "freedom",
		    "settings": {}
		  },{
		    "protocol": "blackhole",
		    "settings": {},
		    "tag": "blocked"
		  }]
		}
	EOF
}

configXray() {
	mkdir -p /usr/local/xray
	if [[ "$TROJAN" == "true" ]]; then
		if [[ "$XTLS" == "true" ]]; then
			trojanXTLSConfig
		else
			trojanConfig
		fi
		return 0
	fi
	if [[ "$VLESS" == "false" ]]; then
		# VMESS + kcp
		if [[ "$KCP" == "true" ]]; then
			vmessKCPConfig
			return 0
		fi
		# VMESS
		if [[ "$TLS" == "false" ]]; then
			vmessConfig
		elif [[ "$WS" == "false" ]]; then
			# VMESS+TCP+TLS
			vmessTLSConfig
		# VMESS+WS+TLS
		else
			vmessWSConfig
		fi
	#VLESS
	else
		if [[ "$KCP" == "true" ]]; then
			vlessKCPConfig
			return 0
		fi
		# VLESS+TCP
		if [[ "$WS" == "false" ]]; then
			# VLESS+TCP+TLS
			if [[ "$XTLS" == "false" ]]; then
				vlessTLSConfig
			# VLESS+TCP+XTLS
			else
				vlessXTLSConfig
			fi
		# VLESS+WS+TLS
		else
			vlessWSConfig
		fi
	fi
}

install() {
	getData
	${PACKAGE_UPDATE[int]}
	${PACKAGE_INSTALL[int]} wget curl sudo vim unzip tar gcc openssl net-tools
	if [[ $SYSTEM != "CentOS" ]]; then
		${PACKAGE_INSTALL[int]} libssl-dev g++
	fi
	[[ -z $(type -P unzip) ]] && red "unzip安装失败，请检查网络" && exit 1
	installNginx
	setFirewall
	[[ $TLS == "true" || $XTLS == "true" ]] && getCert
	configNginx
	yellow "安装Xray..."
	getVersion
	RETVAL="$?"
	if [[ $RETVAL == 0 ]]; then
		yellow "Xray最新版 ${CUR_VER} 已经安装"
	elif [[ $RETVAL == 3 ]]; then
		exit 1
	else
		yellow "安装Xray ${NEW_VER} ，架构$(archAffix)"
		installXray
	fi
	configXray
	setSelinux
	installBBR
	start
	showInfo
	bbrReboot
}

bbrReboot() {
	if [[ "${INSTALL_BBR}" == "true" ]]; then
		echo
		echo "为使BBR模块生效，系统将在30秒后重启"
		echo
		echo -e "您可以按 ctrl + c 取消重启，稍后输入 ${RED}reboot${PLAIN} 重启系统"
		sleep 30
		reboot
	fi
}

update() {
	res=$(status)
	[[ $res -lt 2 ]] && red "Xray未安装，请先安装！" && return
	getVersion
	RETVAL="$?"
	if [[ $RETVAL == 0 ]]; then
		yellow "Xray最新版 ${CUR_VER} 已经安装"
	elif [[ $RETVAL == 3 ]]; then
		exit 1
	else
		yellow "安装Xray ${NEW_VER} ，架构$(archAffix)"
		installXray
		stop
		start
		green "最新版Xray安装成功！"
	fi
}

uninstall() {
	res=$(status)
	if [[ $res -lt 2 ]]; then
		red "Xray未安装，请先安装！"
		return
	fi
	echo ""
	read -p "确定卸载Xray？[y/n]：" answer
	if [[ "${answer,,}" == "y" ]]; then
		domain=$(grep Host $CONFIG_FILE | cut -d: -f2 | tr -d \",' ')
		if [[ "$domain" == "" ]]; then
			domain=$(grep serverName $CONFIG_FILE | cut -d: -f2 | tr -d \",' ')
		fi
		stop
		systemctl disable xray
		rm -rf /etc/systemd/system/xray.service
		rm -rf /usr/local/bin/xray
		rm -rf /usr/local/etc/xray
		if [[ "$BT" == "false" ]]; then
			systemctl disable nginx
			${PACKAGE_UNINSTALL[int]} nginx
			if [[ "$PMT" == "apt" ]]; then
				${PACKAGE_UNINSTALL[int]} nginx-common
			fi
			rm -rf /etc/nginx/nginx.conf
			if [[ -f /etc/nginx/nginx.conf.bak ]]; then
				mv /etc/nginx/nginx.conf.bak /etc/nginx/nginx.conf
			fi
		fi
		if [[ "$domain" != "" ]]; then
			rm -rf ${NGINX_CONF_PATH}${domain}.conf
		fi
		[[ -f ~/.acme.sh/acme.sh ]] && ~/.acme.sh/acme.sh --uninstall
		green "Xray卸载成功"
	fi
}

start() {
	res=$(status)
	if [[ $res -lt 2 ]]; then
		red "Xray未安装，请先安装！"
		return
	fi
	stopNginx
	startNginx
	systemctl restart xray
	sleep 2
	port=$(grep port $CONFIG_FILE | head -n 1 | cut -d: -f2 | tr -d \",' ')
	res=$(ss -nutlp | grep ${port} | grep -i xray)
	if [[ "$res" == "" ]]; then
		red "Xray启动失败，请检查日志或查看端口是否被占用！"
	else
		yellow "Xray启动成功"
	fi
}

stop() {
	stopNginx
	systemctl stop xray
	yellow "Xray停止成功"
}

restart() {
	res=$(status)
	if [[ $res -lt 2 ]]; then
		red "Xray未安装，请先安装！"
		return
	fi
	stop
	start
}

getConfigFileInfo() {
	vless="false"
	tls="false"
	ws="false"
	xtls="false"
	trojan="false"
	protocol="VMess"
	kcp="false"
	uid=$(grep id $CONFIG_FILE | head -n1 | cut -d: -f2 | tr -d \",' ')
	alterid=$(grep alterId $CONFIG_FILE | cut -d: -f2 | tr -d \",' ')
	network=$(grep network $CONFIG_FILE | tail -n1 | cut -d: -f2 | tr -d \",' ')
	[[ -z "$network" ]] && network="tcp"
	domain=$(grep serverName $CONFIG_FILE | cut -d: -f2 | tr -d \",' ')
	if [[ "$domain" == "" ]]; then
		domain=$(grep Host $CONFIG_FILE | cut -d: -f2 | tr -d \",' ')
		if [[ "$domain" != "" ]]; then
			ws="true"
			tls="true"
			wspath=$(grep path $CONFIG_FILE | cut -d: -f2 | tr -d \",' ')
		fi
	else
		tls="true"
	fi
	if [[ "$ws" == "true" ]]; then
		port=$(grep -i ssl $NGINX_CONF_PATH${domain}.conf | head -n1 | awk '{print $2}')
	else
		port=$(grep port $CONFIG_FILE | cut -d: -f2 | tr -d \",' ')
	fi
	res=$(grep -i kcp $CONFIG_FILE)
	if [[ "$res" != "" ]]; then
		kcp="true"
		type=$(grep header -A 3 $CONFIG_FILE | grep 'type' | cut -d: -f2 | tr -d \",' ')
		seed=$(grep seed $CONFIG_FILE | cut -d: -f2 | tr -d \",' ')
	fi
	vmess=$(grep vmess $CONFIG_FILE)
	if [[ "$vmess" == "" ]]; then
		trojan=$(grep trojan $CONFIG_FILE)
		if [[ "$trojan" == "" ]]; then
			vless="true"
			protocol="VLESS"
		else
			trojan="true"
			password=$(grep password $CONFIG_FILE | cut -d: -f2 | tr -d \",' ')
			protocol="trojan"
		fi
		tls="true"
		encryption="none"
		xtls=$(grep xtlsSettings $CONFIG_FILE)
		if [[ "$xtls" != "" ]]; then
			xtls="true"
			flow=$(grep flow $CONFIG_FILE | cut -d: -f2 | tr -d \",' ')
		else
			flow="无"
		fi
	fi
}

outputVmess() {
	raw="{
  \"v\":\"2\",
  \"ps\":\"\",
  \"add\":\"$IP\",
  \"port\":\"${port}\",
  \"id\":\"${uid}\",
  \"aid\":\"$alterid\",
  \"net\":\"tcp\",
  \"type\":\"none\",
  \"host\":\"\",
  \"path\":\"\",
  \"tls\":\"\"
}"
	link=$(echo -n ${raw} | base64 -w 0)
	link="vmess://${link}"

	echo -e "   ${BLUE}IP(address): ${PLAIN} ${RED}${IP}${PLAIN}"
	echo -e "   ${BLUE}端口(port)：${PLAIN}${RED}${port}${PLAIN}"
	echo -e "   ${BLUE}id(uuid)：${PLAIN}${RED}${uid}${PLAIN}"
	echo -e "   ${BLUE}额外id(alterid)：${PLAIN} ${RED}${alterid}${PLAIN}"
	echo -e "   ${BLUE}加密方式(security)：${PLAIN} ${RED}auto${PLAIN}"
	echo -e "   ${BLUE}传输协议(network)：${PLAIN} ${RED}${network}${PLAIN}"
	echo -e "   ${BLUE}vmess链接:${PLAIN} $RED$link$PLAIN"
}

outputVmessKCP() {
	echo -e "   ${BLUE}IP(address): ${PLAIN} ${RED}${IP}${PLAIN}"
	echo -e "   ${BLUE}端口(port)：${PLAIN}${RED}${port}${PLAIN}"
	echo -e "   ${BLUE}id(uuid)：${PLAIN}${RED}${uid}${PLAIN}"
	echo -e "   ${BLUE}额外id(alterid)：${PLAIN} ${RED}${alterid}${PLAIN}"
	echo -e "   ${BLUE}加密方式(security)：${PLAIN} ${RED}auto${PLAIN}"
	echo -e "   ${BLUE}传输协议(network)：${PLAIN} ${RED}${network}${PLAIN}"
	echo -e "   ${BLUE}伪装类型(type)：${PLAIN} ${RED}${type}${PLAIN}"
	echo -e "   ${BLUE}mkcp seed：${PLAIN} ${RED}${seed}${PLAIN}"
}

outputTrojan() {
	if [[ "$xtls" == "true" ]]; then
		link="trojan://${password}@${domain}:${port}#"
		echo -e "   ${BLUE}IP/域名(address): ${PLAIN} ${RED}${domain}${PLAIN}"
		echo -e "   ${BLUE}端口(port)：${PLAIN}${RED}${port}${PLAIN}"
		echo -e "   ${BLUE}密码(password)：${PLAIN}${RED}${password}${PLAIN}"
		echo -e "   ${BLUE}流控(flow)：${PLAIN}$RED$flow${PLAIN}"
		echo -e "   ${BLUE}加密(encryption)：${PLAIN} ${RED}none${PLAIN}"
		echo -e "   ${BLUE}传输协议(network)：${PLAIN} ${RED}${network}${PLAIN}"
		echo -e "   ${BLUE}底层安全传输(tls)：${PLAIN}${RED}XTLS${PLAIN}"
		echo -e "   ${BLUE}Trojan链接:${PLAIN} $RED$link$PLAIN"
	else
		link="trojan://${password}@${domain}:${port}#"
		echo -e "   ${BLUE}IP/域名(address): ${PLAIN} ${RED}${domain}${PLAIN}"
		echo -e "   ${BLUE}端口(port)：${PLAIN}${RED}${port}${PLAIN}"
		echo -e "   ${BLUE}密码(password)：${PLAIN}${RED}${password}${PLAIN}"
		echo -e "   ${BLUE}传输协议(network)：${PLAIN} ${RED}${network}${PLAIN}"
		echo -e "   ${BLUE}底层安全传输(tls)：${PLAIN}${RED}TLS${PLAIN}"
		echo -e "   ${BLUE}Trojan链接:${PLAIN} $RED$link$PLAIN"
	fi
}

outputVmessTLS() {
	raw="{
  \"v\":\"2\",
  \"ps\":\"\",
  \"add\":\"$IP\",
  \"port\":\"${port}\",
  \"id\":\"${uid}\",
  \"aid\":\"$alterid\",
  \"net\":\"${network}\",
  \"type\":\"none\",
  \"host\":\"${domain}\",
  \"path\":\"\",
  \"tls\":\"tls\"
}"
	link=$(echo -n ${raw} | base64 -w 0)
	link="vmess://${link}"
	echo -e "   ${BLUE}IP(address): ${PLAIN} ${RED}${IP}${PLAIN}"
	echo -e "   ${BLUE}端口(port)：${PLAIN}${RED}${port}${PLAIN}"
	echo -e "   ${BLUE}id(uuid)：${PLAIN}${RED}${uid}${PLAIN}"
	echo -e "   ${BLUE}额外id(alterid)：${PLAIN} ${RED}${alterid}${PLAIN}"
	echo -e "   ${BLUE}加密方式(security)：${PLAIN} ${RED}none${PLAIN}"
	echo -e "   ${BLUE}传输协议(network)：${PLAIN} ${RED}${network}${PLAIN}"
	echo -e "   ${BLUE}伪装域名/主机名(host)/SNI/peer名称：${PLAIN}${RED}${domain}${PLAIN}"
	echo -e "   ${BLUE}底层安全传输(tls)：${PLAIN}${RED}TLS${PLAIN}"
	echo -e "   ${BLUE}vmess链接: ${PLAIN}$RED$link$PLAIN"
}

outputVmessWS() {
	raw="{
  \"v\":\"2\",
  \"ps\":\"\",
  \"add\":\"$IP\",
  \"port\":\"${port}\",
  \"id\":\"${uid}\",
  \"aid\":\"$alterid\",
  \"net\":\"${network}\",
  \"type\":\"none\",
  \"host\":\"${domain}\",
  \"path\":\"${wspath}\",
  \"tls\":\"tls\"
}"
	link=$(echo -n ${raw} | base64 -w 0)
	link="vmess://${link}"

	echo -e "   ${BLUE}IP(address): ${PLAIN} ${RED}${IP}${PLAIN}"
	echo -e "   ${BLUE}端口(port)：${PLAIN}${RED}${port}${PLAIN}"
	echo -e "   ${BLUE}id(uuid)：${PLAIN}${RED}${uid}${PLAIN}"
	echo -e "   ${BLUE}额外id(alterid)：${PLAIN} ${RED}${alterid}${PLAIN}"
	echo -e "   ${BLUE}加密方式(security)：${PLAIN} ${RED}none${PLAIN}"
	echo -e "   ${BLUE}传输协议(network)：${PLAIN} ${RED}${network}${PLAIN}"
	echo -e "   ${BLUE}伪装类型(type)：${PLAIN}${RED}none$PLAIN"
	echo -e "   ${BLUE}伪装域名/主机名(host)/SNI/peer名称：${PLAIN}${RED}${domain}${PLAIN}"
	echo -e "   ${BLUE}路径(path)：${PLAIN}${RED}${wspath}${PLAIN}"
	echo -e "   ${BLUE}底层安全传输(tls)：${PLAIN}${RED}TLS${PLAIN}"
	echo -e "   ${BLUE}vmess链接:${PLAIN} $RED$link$PLAIN"
}

showInfo() {
	res=$(status)
	if [[ $res -lt 2 ]]; then
		red "Xray未安装，请先安装！"
		return
	fi

	echo ""
	yellow " Xray配置文件: ${CONFIG_FILE}"
	yellow " Xray配置信息："

	getConfigFileInfo

	echo -e "   ${BLUE}协议: ${PLAIN} ${RED}${protocol}${PLAIN}"
	if [[ "$trojan" == "true" ]]; then
		outputTrojan
		return 0
	fi
	if [[ "$vless" == "false" ]]; then
		if [[ "$kcp" == "true" ]]; then
			outputVmessKCP
			return 0
		fi
		if [[ "$tls" == "false" ]]; then
			outputVmess
		elif [[ "$ws" == "false" ]]; then
			outputVmessTLS
		else
			outputVmessWS
		fi
	else
		if [[ "$kcp" == "true" ]]; then
			echo -e "   ${BLUE}IP(address): ${PLAIN} ${RED}${IP}${PLAIN}"
			echo -e "   ${BLUE}端口(port)：${PLAIN}${RED}${port}${PLAIN}"
			echo -e "   ${BLUE}id(uuid)：${PLAIN}${RED}${uid}${PLAIN}"
			echo -e "   ${BLUE}加密(encryption)：${PLAIN} ${RED}none${PLAIN}"
			echo -e "   ${BLUE}传输协议(network)：${PLAIN} ${RED}${network}${PLAIN}"
			echo -e "   ${BLUE}伪装类型(type)：${PLAIN} ${RED}${type}${PLAIN}"
			echo -e "   ${BLUE}mkcp seed：${PLAIN} ${RED}${seed}${PLAIN}"
			return 0
		fi
		if [[ "$xtls" == "true" ]]; then
			echo -e " ${BLUE}IP(address): ${PLAIN} ${RED}${IP}${PLAIN}"
			echo -e " ${BLUE}端口(port)：${PLAIN}${RED}${port}${PLAIN}"
			echo -e " ${BLUE}id(uuid)：${PLAIN}${RED}${uid}${PLAIN}"
			echo -e " ${BLUE}流控(flow)：${PLAIN}$RED$flow${PLAIN}"
			echo -e " ${BLUE}加密(encryption)：${PLAIN} ${RED}none${PLAIN}"
			echo -e " ${BLUE}传输协议(network)：${PLAIN} ${RED}${network}${PLAIN}"
			echo -e " ${BLUE}伪装类型(type)：${PLAIN}${RED}none$PLAIN"
			echo -e " ${BLUE}伪装域名/主机名(host)/SNI/peer名称：${PLAIN}${RED}${domain}${PLAIN}"
			echo -e " ${BLUE}底层安全传输(tls)：${PLAIN}${RED}XTLS${PLAIN}"
		elif [[ "$ws" == "false" ]]; then
			echo -e " ${BLUE}IP(address):  ${PLAIN}${RED}${IP}${PLAIN}"
			echo -e " ${BLUE}端口(port)：${PLAIN}${RED}${port}${PLAIN}"
			echo -e " ${BLUE}id(uuid)：${PLAIN}${RED}${uid}${PLAIN}"
			echo -e " ${BLUE}流控(flow)：${PLAIN}$RED$flow${PLAIN}"
			echo -e " ${BLUE}加密(encryption)：${PLAIN} ${RED}none${PLAIN}"
			echo -e " ${BLUE}传输协议(network)：${PLAIN} ${RED}${network}${PLAIN}"
			echo -e " ${BLUE}伪装类型(type)：${PLAIN}${RED}none$PLAIN"
			echo -e " ${BLUE}伪装域名/主机名(host)/SNI/peer名称：${PLAIN}${RED}${domain}${PLAIN}"
			echo -e " ${BLUE}底层安全传输(tls)：${PLAIN}${RED}TLS${PLAIN}"
		else
			echo -e " ${BLUE}IP(address): ${PLAIN} ${RED}${IP}${PLAIN}"
			echo -e " ${BLUE}端口(port)：${PLAIN}${RED}${port}${PLAIN}"
			echo -e " ${BLUE}id(uuid)：${PLAIN}${RED}${uid}${PLAIN}"
			echo -e " ${BLUE}流控(flow)：${PLAIN}$RED$flow${PLAIN}"
			echo -e " ${BLUE}加密(encryption)：${PLAIN} ${RED}none${PLAIN}"
			echo -e " ${BLUE}传输协议(network)：${PLAIN} ${RED}${network}${PLAIN}"
			echo -e " ${BLUE}伪装类型(type)：${PLAIN}${RED}none$PLAIN"
			echo -e " ${BLUE}伪装域名/主机名(host)/SNI/peer名称：${PLAIN}${RED}${domain}${PLAIN}"
			echo -e " ${BLUE}路径(path)：${PLAIN}${RED}${wspath}${PLAIN}"
			echo -e " ${BLUE}底层安全传输(tls)：${PLAIN}${RED}TLS${PLAIN}"
		fi
	fi
}

showLog() {
	res=$(status)
	[[ $res -lt 2 ]] && red "Xray未安装，请先安装！" && exit 1
	journalctl -xen -u xray --no-pager
}

warpmenu(){
	wget -N https://raw.githubusercontents.com/Misaka-blog/Misaka-WARP-Script/master/misakawarp.sh && bash misakawarp.sh
}

setdns64(){
	if [[ -n $(curl -s6m8 https://ip.gs) ]]; then
		echo -e nameserver 2a01:4f8:c2c:123f::1 > /etc/resolv.conf
	fi
}

system_optimize(){
	if [ ! -f "/etc/sysctl.conf" ]; then
		touch /etc/sysctl.conf
	fi
	sed -i '/net.ipv4.tcp_retries2/d' /etc/sysctl.conf
	sed -i '/net.ipv4.tcp_slow_start_after_idle/d' /etc/sysctl.conf
	sed -i '/net.ipv4.tcp_fastopen/d' /etc/sysctl.conf
	sed -i '/fs.file-max/d' /etc/sysctl.conf
	sed -i '/fs.inotify.max_user_instances/d' /etc/sysctl.conf
	sed -i '/net.ipv4.tcp_syncookies/d' /etc/sysctl.conf
	sed -i '/net.ipv4.tcp_fin_timeout/d' /etc/sysctl.conf
	sed -i '/net.ipv4.tcp_tw_reuse/d' /etc/sysctl.conf
	sed -i '/net.ipv4.tcp_max_syn_backlog/d' /etc/sysctl.conf
	sed -i '/net.ipv4.ip_local_port_range/d' /etc/sysctl.conf
	sed -i '/net.ipv4.tcp_max_tw_buckets/d' /etc/sysctl.conf
	sed -i '/net.ipv4.route.gc_timeout/d' /etc/sysctl.conf
	sed -i '/net.ipv4.tcp_synack_retries/d' /etc/sysctl.conf
	sed -i '/net.ipv4.tcp_syn_retries/d' /etc/sysctl.conf
	sed -i '/net.core.somaxconn/d' /etc/sysctl.conf
	sed -i '/net.core.netdev_max_backlog/d' /etc/sysctl.conf
	sed -i '/net.ipv4.tcp_timestamps/d' /etc/sysctl.conf
	sed -i '/net.ipv4.tcp_max_orphans/d' /etc/sysctl.conf
	sed -i '/net.ipv4.ip_forward/d' /etc/sysctl.conf

	echo "net.ipv4.tcp_retries2 = 8
	net.ipv4.tcp_slow_start_after_idle = 0
	fs.file-max = 1000000
	fs.inotify.max_user_instances = 8192
	net.ipv4.tcp_syncookies = 1
	net.ipv4.tcp_fin_timeout = 30
	net.ipv4.tcp_tw_reuse = 1
	net.ipv4.ip_local_port_range = 1024 65000
	net.ipv4.tcp_max_syn_backlog = 16384
	net.ipv4.tcp_max_tw_buckets = 6000
	net.ipv4.route.gc_timeout = 100
	net.ipv4.tcp_syn_retries = 1
	net.ipv4.tcp_synack_retries = 1
	net.core.somaxconn = 32768
	net.core.netdev_max_backlog = 32768
	net.ipv4.tcp_timestamps = 0
	net.ipv4.tcp_max_orphans = 32768
	# forward ipv4
	#net.ipv4.ip_forward = 1" >>/etc/sysctl.conf
	sysctl -p
	echo "*               soft    nofile           1000000
	*               hard    nofile          1000000" >/etc/security/limits.conf
	echo "ulimit -SHn 1000000" >>/etc/profile
	read -p "需要重启VPS，系统优化配置才能生效，是否现在重启？ [Y/n] :" yn
	[[ -z $yn ]] && yn="y"
	if [[ $yn == [Yy] ]]; then
		yellow "VPS 重启中..."
		reboot
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

menu() {
	clear
	echo "#############################################################"
	echo -e "#                     ${RED}Xray一键安装脚本${PLAIN}                      #"
	echo -e "# ${GREEN}作者${PLAIN}: 网络跳越(hijk) & MisakaNo                           #"
	echo -e "# ${GREEN}博客${PLAIN}: https://owo.misaka.rest                             #"
	echo -e "# ${GREEN}TG群${PLAIN}: https://t.me/misakanetcn                            #"
	echo "#############################################################"
	echo -e "  "
	echo -e "  ${GREEN}1.${PLAIN}   安装Xray-VMESS${PLAIN}${RED}(不推荐)${PLAIN}"
	echo -e "  ${GREEN}2.${PLAIN}   安装Xray-${BLUE}VMESS+mKCP${PLAIN}"
	echo -e "  ${GREEN}3.${PLAIN}   安装Xray-VMESS+TCP+TLS"
	echo -e "  ${GREEN}4.${PLAIN}   安装Xray-${BLUE}VMESS+WS+TLS${PLAIN}${RED}(推荐)(可过支持WebSocket的CDN)${PLAIN}"
	echo -e "  ${GREEN}5.${PLAIN}   安装Xray-${BLUE}VLESS+mKCP${PLAIN}"
	echo -e "  ${GREEN}6.${PLAIN}   安装Xray-VLESS+TCP+TLS"
	echo -e "  ${GREEN}7.${PLAIN}   安装Xray-${BLUE}VLESS+WS+TLS${PLAIN}${RED}(推荐)(可过支持WebSocket的CDN)${PLAIN}"
	echo -e "  ${GREEN}8.${PLAIN}   安装Xray-${BLUE}VLESS+TCP+XTLS"
	echo -e "  ${GREEN}9.${PLAIN}   安装${BLUE}Trojan"
	echo -e "  ${GREEN}10.${PLAIN}  安装${BLUE}Trojan+XTLS"
	echo " -------------"
	echo -e "  ${GREEN}11.${PLAIN}  更新Xray"
	echo -e "  ${GREEN}12.  ${RED}卸载Xray${PLAIN}"
	echo " -------------"
	echo -e "  ${GREEN}13.${PLAIN}  启动Xray"
	echo -e "  ${GREEN}14.${PLAIN}  重启Xray"
	echo -e "  ${GREEN}15.${PLAIN}  停止Xray"
	echo " -------------"
	echo -e "  ${GREEN}16.${PLAIN}  查看Xray配置"
	echo -e "  ${GREEN}17.${PLAIN}  查看Xray日志"
	echo " -------------"
	echo -e "  ${GREEN}18.${PLAIN}  安装并管理WARP"
	echo -e "  ${GREEN}19.${PLAIN}  设置DNS64服务器"
	echo -e "  ${GREEN}20.${PLAIN}  VPS系统优化"
	echo -e "  ${GREEN}21.${PLAIN}  放开VPS的所有端口"
	echo " -------------"
	echo -e "  ${GREEN}0.${PLAIN}   退出"
	echo -n " 当前Xray状态："
	statusText
	echo

	read -p "请选择操作[0-21]：" answer
	case $answer in
		0) exit 1 ;;
		1) install ;;
		2) KCP="true" && install ;;
		3) TLS="true" && install ;;
		4) TLS="true" && WS="true" && install ;;
		5) VLESS="true" && KCP="true" && install ;;
		6) VLESS="true" && TLS="true" && install ;;
		7) VLESS="true" && TLS="true" && WS="true" && install ;;
		8) VLESS="true" && TLS="true" && XTLS="true" && install ;;
		9) TROJAN="true" && TLS="true" && install ;;
		10) TROJAN="true" && TLS="true" && XTLS="true" && install ;;
		11) update ;;
		12) uninstall ;;
		13) start ;;
		14) restart ;;
		15) stop ;;
		16) showInfo ;;
		17) showLog ;;
		18) warpmenu ;;
		19) setdns64 ;;
		20) system_optimize ;;
		21) open_ports ;;
		*) red "请选择正确的操作！" && exit 1 ;;
	esac
}

action=$1
[[ -z $1 ]] && action=menu

case "$action" in
	menu | update | uninstall | start | restart | stop | showInfo | showLog) ${action} ;;
	*) echo " 参数错误" && echo " 用法: $(basename $0) [menu|update|uninstall|start|restart|stop|showInfo|showLog]" ;;
esac