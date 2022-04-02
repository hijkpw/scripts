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

CONFIG_FILE="/usr/local/etc/xray/config.json"
BT="false"
NGINX_CONF_PATH="/etc/nginx/conf.d/"

VLESS="false"
TROJAN="false"
TLS="false"
WS="false"
XTLS="false"
KCP="false"

SITES=(
    "http://www.zhuizishu.com/"
    "http://xs.56dyc.com/"
    "http://www.ddxsku.com/"
    "http://www.biqu6.com/"
    "https://www.wenshulou.cc/"
    "http://www.55shuba.com/"
    "http://www.39shubao.com/"
    "https://www.23xsw.cc/"
    "https://www.jueshitangmen.info/"
    "https://www.zhetian.org/"
    "http://www.bequgexs.com/"
    "http://www.tjwl.com/"
)

res=`which bt 2>/dev/null`
if [[ $res != "" ]]; then
    BT="true"
    NGINX_CONF_PATH="/www/server/panel/vhost/nginx/"
fi

archAffix(){
    case "$(uname -m)" in
        i686|i386) echo '32' ;;
        x86_64|amd64) echo '64' ;;
        armv5tel) echo 'arm32-v5' ;;
        armv6l) echo 'arm32-v6' ;;
        armv7|armv7l) echo 'arm32-v7a' ;;
        armv8|aarch64) echo 'arm64-v8a' ;;
        mips64le) echo 'mips64le' ;;
        mips64) echo 'mips64' ;;
        mipsle) echo 'mips32le' ;;
        mips) echo 'mips32' ;;
        ppc64le) echo 'ppc64le' ;;
        ppc64) echo 'ppc64' ;;
        ppc64le) echo 'ppc64le' ;;
        riscv64) echo 'riscv64' ;;
        s390x) echo 's390x' ;;
        *) red "不支持的CPU架构！" && exit 1
        ;;
    esac
	return 0
}

getVersion() {
    VER=$(/usr/local/bin/xray version | head -n1 | awk '{print $2}')
    RETVAL=$?
    CUR_VER="$(normalizeVersion "$(echo "$VER" | head -n 1 | cut -d " " -f2)")"
    TAG_URL="https://api.github.com/repos/XTLS/Xray-core/releases/latest"
    NEW_VER="$(normalizeVersion "$(curl -s "${TAG_URL}" --connect-timeout 10 | grep 'tag_name' | cut -d\" -f4)")"

    if [[ $? -ne 0 ]] || [[ $NEW_VER == "" ]]; then
        red "检查Xray版本信息失败，请检查网络"
        return 3
    elif [[ $RETVAL -ne 0 ]];then
        return 2
    elif [[ $NEW_VER != $CUR_VER ]];then
        return 1
    fi

    return 0
}

getData() {
    if [[ "$TLS" = "true" || "$XTLS" = "true" ]]; then
        echo ""
        echo " Xray一键脚本，运行之前请确认如下条件已经具备："
        colorEcho ${YELLOW} "  1. 一个伪装域名"
        colorEcho ${YELLOW} "  2. 伪装域名DNS解析指向当前服务器ip（${IP}）"
        colorEcho ${BLUE} "  3. 如果/root目录下有 xray.pem 和 xray.key 证书密钥文件，无需理会条件2"
        echo " "
        read -p " 确认满足按y，按其他退出脚本：" answer
        if [[ "${answer,,}" != "y" ]]; then
            exit 0
        fi

        echo ""
        while true
        do
            read -p " 请输入伪装域名：" DOMAIN
            if [[ -z "${DOMAIN}" ]]; then
                colorEcho ${RED} " 域名输入错误，请重新输入！"
            else
                break
            fi
        done
        DOMAIN=${DOMAIN,,}
        colorEcho ${BLUE}  " 伪装域名(host)：$DOMAIN"

        echo ""
        if [[ -f ~/xray.pem && -f ~/xray.key ]]; then
            colorEcho ${BLUE}  " 检测到自有证书，将使用其部署"
            CERT_FILE="/usr/local/etc/xray/${DOMAIN}.pem"
            KEY_FILE="/usr/local/etc/xray/${DOMAIN}.key"
        else
            resolve=`curl -sL https://hijk.art/hostip.php?d=${DOMAIN}`
            res=`echo -n ${resolve} | grep ${IP}`
            if [[ -z "${res}" ]]; then
                colorEcho ${BLUE}  "${DOMAIN} 解析结果：${resolve}"
                colorEcho ${RED}  " 域名未解析到当前服务器IP(${IP})!"
                exit 1
            fi
        fi
    fi

    echo ""
    if [[ "$(needNginx)" = "no" ]]; then
        if [[ "$TLS" = "true" ]]; then
            read -p " 请输入xray监听端口[强烈建议443，默认443]：" PORT
            [[ -z "${PORT}" ]] && PORT=443
        else
            read -p " 请输入xray监听端口[100-65535的一个数字]：" PORT
            [[ -z "${PORT}" ]] && PORT=`shuf -i200-65000 -n1`
            if [[ "${PORT:0:1}" = "0" ]]; then
                colorEcho ${RED}  " 端口不能以0开头"
                exit 1
            fi
        fi
        colorEcho ${BLUE}  " xray端口：$PORT"
    else
        read -p " 请输入Nginx监听端口[100-65535的一个数字，默认443]：" PORT
        [[ -z "${PORT}" ]] && PORT=443
        if [ "${PORT:0:1}" = "0" ]; then
            colorEcho ${BLUE}  " 端口不能以0开头"
            exit 1
        fi
        colorEcho ${BLUE}  " Nginx端口：$PORT"
        XPORT=`shuf -i10000-65000 -n1`
    fi

    if [[ "$KCP" = "true" ]]; then
        echo ""
        colorEcho $BLUE " 请选择伪装类型："
        echo "   1) 无"
        echo "   2) BT下载"
        echo "   3) 视频通话"
        echo "   4) 微信视频通话"
        echo "   5) dtls"
        echo "   6) wiregard"
        read -p "  请选择伪装类型[默认：无]：" answer
        case $answer in
            2)
                HEADER_TYPE="utp"
                ;;
            3)
                HEADER_TYPE="srtp"
                ;;
            4)
                HEADER_TYPE="wechat-video"
                ;;
            5)
                HEADER_TYPE="dtls"
                ;;
            6)
                HEADER_TYPE="wireguard"
                ;;
            *)
                HEADER_TYPE="none"
                ;;
        esac
        colorEcho $BLUE " 伪装类型：$HEADER_TYPE"
        SEED=`cat /proc/sys/kernel/random/uuid`
    fi

    if [[ "$TROJAN" = "true" ]]; then
        echo ""
        read -p " 请设置trojan密码（不输则随机生成）:" PASSWORD
        [[ -z "$PASSWORD" ]] && PASSWORD=`cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1`
        colorEcho $BLUE " trojan密码：$PASSWORD"
    fi

    if [[ "$XTLS" = "true" ]]; then
        echo ""
        colorEcho $BLUE " 请选择流控模式:" 
        echo -e "   1) xtls-rprx-direct [$RED推荐$PLAIN]"
        echo "   2) xtls-rprx-origin"
        read -p "  请选择流控模式[默认:direct]" answer
        [[ -z "$answer" ]] && answer=1
        case $answer in
            1)
                FLOW="xtls-rprx-direct"
                ;;
            2)
                FLOW="xtls-rprx-origin"
                ;;
            *)
                colorEcho $RED " 无效选项，使用默认的xtls-rprx-direct"
                FLOW="xtls-rprx-direct"
                ;;
        esac
        colorEcho $BLUE " 流控模式：$FLOW"
    fi

    if [[ "${WS}" = "true" ]]; then
        echo ""
        while true
        do
            read -p " 请输入伪装路径，以/开头(不懂请直接回车)：" WSPATH
            if [[ -z "${WSPATH}" ]]; then
                len=`shuf -i5-12 -n1`
                ws=`cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w $len | head -n 1`
                WSPATH="/$ws"
                break
            elif [[ "${WSPATH:0:1}" != "/" ]]; then
                colorEcho ${RED}  " 伪装路径必须以/开头！"
            elif [[ "${WSPATH}" = "/" ]]; then
                colorEcho ${RED}   " 不能使用根路径！"
            else
                break
            fi
        done
        colorEcho ${BLUE}  " ws路径：$WSPATH"
    fi

    if [[ "$TLS" = "true" || "$XTLS" = "true" ]]; then
        echo ""
        colorEcho $BLUE " 请选择伪装站类型:"
        echo "   1) 静态网站(位于/usr/share/nginx/html)"
        echo "   2) 小说站(随机选择)"
        echo "   3) 美女站(https://imeizi.me)"
        echo "   4) 高清壁纸站(https://bing.imeizi.me)"
        echo "   5) 自定义反代站点(需以http或者https开头)"
        read -p "  请选择伪装网站类型[默认:高清壁纸站]" answer
        if [[ -z "$answer" ]]; then
            PROXY_URL="https://bing.imeizi.me"
        else
            case $answer in
            1)
                PROXY_URL=""
                ;;
            2)
                len=${#SITES[@]}
                ((len--))
                while true
                do
                    index=`shuf -i0-${len} -n1`
                    PROXY_URL=${SITES[$index]}
                    host=`echo ${PROXY_URL} | cut -d/ -f3`
                    ip=`curl -sL https://hijk.art/hostip.php?d=${host}`
                    res=`echo -n ${ip} | grep ${host}`
                    if [[ "${res}" = "" ]]; then
                        echo "$ip $host" >> /etc/hosts
                        break
                    fi
                done
                ;;
            3)
                PROXY_URL="https://imeizi.me"
                ;;
            4)
                PROXY_URL="https://bing.imeizi.me"
                ;;
            5)
                read -p " 请输入反代站点(以http或者https开头)：" PROXY_URL
                if [[ -z "$PROXY_URL" ]]; then
                    colorEcho $RED " 请输入反代网站！"
                    exit 1
                elif [[ "${PROXY_URL:0:4}" != "http" ]]; then
                    colorEcho $RED " 反代网站必须以http或https开头！"
                    exit 1
                fi
                ;;
            *)
                colorEcho $RED " 请输入正确的选项！"
                exit 1
            esac
        fi
        REMOTE_HOST=`echo ${PROXY_URL} | cut -d/ -f3`
        colorEcho $BLUE " 伪装网站：$PROXY_URL"

        echo ""
        colorEcho $BLUE "  是否允许搜索引擎爬取网站？[默认：不允许]"
        echo "    y)允许，会有更多ip请求网站，但会消耗一些流量，vps流量充足情况下推荐使用"
        echo "    n)不允许，爬虫不会访问网站，访问ip比较单一，但能节省vps流量"
        read -p "  请选择：[y/n]" answer
        if [[ -z "$answer" ]]; then
            ALLOW_SPIDER="n"
        elif [[ "${answer,,}" = "y" ]]; then
            ALLOW_SPIDER="y"
        else
            ALLOW_SPIDER="n"
        fi
        colorEcho $BLUE " 允许搜索引擎：$ALLOW_SPIDER"
    fi

    echo ""
    read -p " 是否安装BBR(默认安装)?[y/n]:" NEED_BBR
    [[ -z "$NEED_BBR" ]] && NEED_BBR=y
    [[ "$NEED_BBR" = "Y" ]] && NEED_BBR=y
    colorEcho $BLUE " 安装BBR：$NEED_BBR"
}
