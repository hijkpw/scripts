read -p "请输入隧道名称：" tunnelName
read -p "请输入隧道UUID：" tunnelUUID
read -p "请输入传输协议（默认http）：" tunnelProtocol
if [ -z $tunnelProtocol ]; then
    tunnelProtocol="http"
fi
read -p "请输入域名：" tunnelDomain
read -p "请输入反代端口：" tunnelPort
read -p "请输入配置文件名：" tunnelFileName
cat <<EOF > ~/$tunnelFileName.yml
tunnel: $tunnelName
credentials-file: /root/.cloudflared/$tunnelUUID.json
originRequest:
  connectTimeout: 30s
  noTLSVerify: true
ingress:
  - hostname: $tunnelDomain
    service: $tunnelProtocol://localhost:$tunnelPort
  - service: http_status:404
EOF