#!/bin/bash

rm -f wgcf-account.toml
until [[ -a wgcf-account.toml ]]; do
    yes | wgcf register
    sleep 5
done
chmod +x wgcf-account.toml
wgcf generate
chmod +x wgcf-profile.conf
WgcfPrivateKey=$(cat /etc/wireguard/wgcf.conf | grep PrivateKey | cut -d= -f2)
WgcfPublicKey=$(cat /etc/wireguard/wgcf.conf | grep PublicKey | cut -d= -f2)
WgcfEndPointIP=$(cat /etc/wireguard/wgcf.conf | grep Endpoint | cut -d= -f2)

cat <<EOF > ~/WireProxy_WARP.conf
SelfSecretKey = $WgcfPrivateKey
SelfEndpoint = 172.16.0.2
PeerPublicKey = $WgcfPublicKey
PeerEndpoint = $WgcfEndPointIP
DNS = 1.1.1.1,8.8.8.8,8.8.4.4

[Socks5]
BindAddress = 127.0.0.1:25344
EOF