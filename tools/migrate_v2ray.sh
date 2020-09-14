#!/bin/bash
export LC_ALL=C
export LANG=en_US
export LANGUAGE=en_US.UTF-8

branch="dev"

if [[ $(/usr/bin/id -u) -ne 0 ]]; then
  sudoCmd="sudo"
else
  sudoCmd=""
fi

read_json() {
  # jq [key] [path-to-file]
  ${sudoCmd} jq --raw-output $2 $1 2>/dev/null | tr -d '\n'
} ## read_json [path-to-file] [key]

if [[ $(read_json /usr/local/etc/v2script/config.json '.v2ray.installed') == "true" ]] && [ -d "/usr/bin/v2ray" ]; then
  echo -e "\033[0;33mMigrating v2ray to new path\033[0m"

  # stop v2ray service
  ${sudoCmd} systemctl stop v2ray 2>/dev/null
  ${sudoCmd} systemctl disable v2ray 2>/dev/null

  # remove v2ray installed with old script
  curl -sL https://install.direct/go.sh | ${sudoCmd} bash -s -- --remove

  # remove log folder and domainsocket folder
  ${sudoCmd} rm -rf /var/log/v2ray
  ${sudoCmd} rm -rf /tmp/v2ray-ds

  # move config folder
  ${sudoCmd} mv /etc/v2ray/ /usr/local/etc/

  # remove cronatab with old path of geo*.dat
  ${sudoCmd} crontab -l | grep -v '/usr/bin/v2ray/geoip.dat' | ${sudoCmd} crontab -
  ${sudoCmd} crontab -l | grep -v '/usr/bin/v2ray/geosite.dat' | ${sudoCmd} crontab -

  # install v2ray fhs
  curl -sL https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh | ${sudoCmd} bash

  # update geoip.dat, geosite.dat
  ${sudoCmd} mkdir -p /usr/local/lib/v2ray
  ${sudoCmd} wget -q https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/geoip.dat -O /usr/local/lib/v2ray/geoip.dat
  ${sudoCmd} wget -q https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/geosite.dat -O /usr/local/lib/v2ray/geosite.dat

  # rebuild v2ray.service
  ds_service=$(mktemp)
  cat > ${ds_service} <<-EOF
[Unit]
Description=V2Ray - A unified platform for anti-censorship
Documentation=https://v2ray.com https://guide.v2fly.org
After=network.target nss-lookup.target
Wants=network-online.target

[Service]
# If the version of systemd is 240 or above, then uncommenting Type=exec and commenting out Type=simple
#Type=exec
Type=simple
# Runs as root or add CAP_NET_BIND_SERVICE ability can bind 1 to 1024 port.
# This service runs as root. You may consider to run it as another user for security concerns.
# By uncommenting User=v2ray and commenting out User=root, the service will run as user v2ray.
# More discussion at https://github.com/v2ray/v2ray-core/issues/1011
#User=root
User=v2ray
CapabilityBoundingSet=CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=yes
Environment=V2RAY_LOCATION_ASSET=/usr/local/lib/v2ray/

ExecStartPre=$(which mkdir) -p /tmp/v2ray-ds
ExecStartPre=$(which rm) -rf /tmp/v2ray-ds/*.sock

ExecStart=/usr/local/bin/v2ray -config /usr/local/etc/v2ray/config.json

ExecStartPost=$(which sleep) 1
ExecStartPost=$(which chmod) 666 /tmp/v2ray-ds/v2ray.sock

Restart=on-failure
#Restart=always
#RestartSec=10
# Don't restart in the case of configuration error
RestartPreventExitStatus=23

[Install]
WantedBy=multi-user.target
EOF
  ${sudoCmd} mv ${ds_service} /etc/systemd/system/v2ray.service

  # set crontab to auto update geoip.dat and geosite.dat
  (crontab -l 2>/dev/null; echo "0 7 * * * wget -q https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/geoip.dat -O /usr/local/lib/v2ray/geoip.dat >/dev/null >/dev/null") | ${sudoCmd} crontab -
  (crontab -l 2>/dev/null; echo "0 7 * * * wget -q https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/geosite.dat -O /usr/local/lib/v2ray/geosite.dat >/dev/null >/dev/null") | ${sudoCmd} crontab -

  ${sudoCmd} systemctl daemon-reload
  ${sudoCmd} systemctl enable v2ray 2>/dev/null
  ${sudoCmd} systemctl restart v2ray 2>/dev/null
  ${sudoCmd} systemctl daemon-reload
  ${sudoCmd} systemctl reset-failed
fi