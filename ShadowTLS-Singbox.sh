#!/bin/bash
# https://github.com/GFW4Fun/

echo "Enter the option number and press enter"
select opt in install update_config update_sing_box uninstall quit
do
  case $opt in
    install)
      echo "Enter your VPS IP and press enter"
      read -r -e VPS_IP
      echo "Enter a domain and press enter"
      echo "Domain should be a popular non-blocked website like apple.com"
      echo "and that should also support TLS 1.3"
      read -r -e SITE
      echo "Enter port number 1-65535 Or type random for random port then press enter"
      read -r -e PORT
      if (( "$PORT" < 1 || "$PORT" > 65535)); then
        if [ "$PORT" != "random" ]
        then
          echo "Invalid port number"
          exit
        else
          PORT=$((1024 + $RANDOM))
        fi
      fi

      #generate passwords
      SHADOWSOCKS_PASSWORD=$(openssl rand -base64 16)
      SHADOWTLS_PASSWORD=$(openssl rand -base64 24)

      mkdir -p $HOME/sing-box
      #get latest version
      LATEST_URL=$(curl -Ls -o /dev/null -w %{url_effective} https://github.com/SagerNet/sing-box/releases/latest)
      LATEST_VERSION="$(echo $LATEST_URL |grep -o -E '/.?[0-9|\.]+$'| grep -o -E '[0-9|\.]+')"
      LINK="https://github.com/SagerNet/sing-box/releases/download/v${LATEST_VERSION}/sing-box-${LATEST_VERSION}-linux-amd64.tar.gz"
	  wget "$LINK"
      tar -xf "sing-box-${LATEST_VERSION}-linux-amd64.tar.gz"
      cp "sing-box-${LATEST_VERSION}-linux-amd64/sing-box" "${HOME}/sing-box"
      rm -rf "sing-box-${LATEST_VERSION}-linux-amd64.tar.gz" "sing-box-${LATEST_VERSION}-linux-amd64"

      cat << EOF > "${HOME}/sing-box/config.json"
{
	"log": {
		"disabled": true
	},
	"dns": {
		"servers": [
			{
				"address": "tls://8.8.8.8"
			}
		]
	},
	"inbounds": [
		{
			"type": "shadowtls",
			"listen": "::",
			"listen_port": ${PORT},
			"version": 3,
			"users": [
				{
					"name": "sekai",
					"password": "${SHADOWTLS_PASSWORD}"
				}
			],
			"handshake": {
				"server": "${SITE}",
				"server_port": 443
			},
      "strict_mode": true,
			"detour": "shadowsocks-in"
		},
		{
			"type": "shadowsocks",
			"tag": "shadowsocks-in",
			"listen": "127.0.0.1",
			"network": "tcp",
			"method": "2022-blake3-aes-128-gcm",
			"password": "${SHADOWSOCKS_PASSWORD}"
		}
	],
 "outbounds": [
        {
            "tag": "direct",
            "type": "direct"
        },
        {
            "tag": "block",
            "type": "block"
        },
        {
            "tag": "dns-out",
            "type": "dns"
        }
	],
 "route": {
        "auto_detect_interface": true,
        "final": "direct",
        "geoip": {
            "download_detour": "direct",
            "download_url": "https://github.com/malikshi/sing-box-geo/releases/latest/download/geoip.db",
            "path": "/root/sing-box/geoip.db"
        },
        "geosite": {
            "download_detour": "direct",
            "download_url": "https://github.com/malikshi/sing-box-geo/releases/latest/download/geosite.db",
            "path": "/root/sing-box/geosite.db"
        },
        "rules": [
            {
                "outbound": "dns-out",
                "protocol": "dns"
            },
            {
                "domain_suffix": [
                    ".cn",
                    ".ir",
                    ".cu",
                    ".vn",
                    ".zw",
                    ".by"
                ],
                "geoip": [
                    "cn",
                    "ir",
                    "cu",
                    "vn",
                    "zw",
                    "by"
                ],
                "geosite": [
                    "oisd-full",
                    "rule-ads",
                    "rule-malicious"
                ],
                "outbound": "block"
            }
        ]
    }

}
EOF
      cat << EOF > "/etc/systemd/system/sing-box.service"
[Unit]
Description=sing-box service
Documentation=https://sing-box.sagernet.org
After=network.target nss-lookup.target

[Service]
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_SYS_PTRACE CAP_DAC_READ_SEARCH
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_SYS_PTRACE CAP_DAC_READ_SEARCH
ExecStart=${HOME}/sing-box/sing-box run -c ${HOME}/sing-box/config.json
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=10s
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF
      systemctl daemon-reload
      systemctl enable sing-box.service
      systemctl start sing-box.service

      cat << EOF > "${HOME}/sing-box/restart-sing-box.sh"
#!/bin/bash
systemctl restart sing-box.service
rm "\$HOME/sing-box/geoip.db" "\$HOME/sing-box/geosite.db"
EOF
      chmod +x "${HOME}/sing-box/restart-sing-box.sh"
      #restart sing-box.service every 2 days
      #to fix possible over consuming memory at 3:00 am
      (crontab -l 2>/dev/null; echo "0 3 */2 * * ${HOME}/sing-box/restart-sing-box.sh") | crontab -

			echo "Done!"
			echo "Copy this content for client config.json file"
      cat << EOF
{
  "dns": {
    "rules": [],
    "servers": [
      {
        "address": "tls://8.8.8.8",
        "tag": "dns-remote",
        "detour": "ss",
        "strategy": "ipv4_only"
      }
    ]
  },
  "inbounds": [
    {
      "type": "tun",
      "interface_name": "ipv4-tun",
      "inet4_address": "172.19.0.1/28",
      "mtu": 1500,
      "stack": "gvisor",
      "endpoint_independent_nat": true,
      "auto_route": true,
      "strict_route": true,
      "sniff": true
    }
  ],
  "outbounds": [
    {
      "type": "shadowsocks",
      "tag": "ss",
      "method": "2022-blake3-aes-128-gcm",
      "password": "${SHADOWSOCKS_PASSWORD}",
      "detour": "shadowtls-out",
      "udp_over_tcp": {
        "enabled": true,
        "version": 2
      }
    },
    {
      "type": "shadowtls",
      "tag": "shadowtls-out",
      "server": "${VPS_IP}",
      "server_port": ${PORT},
      "version": 3,
      "password": "${SHADOWTLS_PASSWORD}",
      "tls": {
        "enabled": true,
        "server_name": "${SITE}",
        "utls": {
          "enabled": true,
          "fingerprint": "firefox"
        }
      }
    },
       {
            "tag": "direct",
            "type": "direct"
        },
        {
            "tag": "block",
            "type": "block"
        },
        {
            "tag": "dns-out",
            "type": "dns"
        }
  ],
    "route": {
        "auto_detect_interface": true,
        "final": "ss",
		"geoip": {
            "download_detour": "direct",
            "download_url": "https://github.com/malikshi/sing-box-geo/releases/latest/download/geoip.db",
            "path": "geoip.db"
        },
        "rules": [
            {
                "outbound": "dns-out",
                "protocol": "dns"
            },
            {
                "domain_suffix": [
                    ".cn",
                    ".ru",
                    ".ir",
                    ".cu",
                    ".vn",
                    ".zw",
                    ".by"
                ],
                "geoip": [
                    "cn",
                    "ru",
                    "ir",
                    "cu",
                    "vn",
                    "zw",
                    "by",
                    "private"
                ],
                "outbound": "direct"
            }
        ]
    }
}
EOF
      break;;
    update_config)
      echo "Enter your VPS IP and press enter"
      read -r -e VPS_IP
      echo "Enter domain and press enter"
      read -r -e SITE
      echo "Enter port number 1-65535 Or type random for random port then press enter"
      read -r -e PORT
      if (( "$PORT" < 1 || "$PORT" > 65535)); then
        if [ "$PORT" != "random" ]
        then
          echo "Invalid port number"
          exit
        else
          PORT=$((1024 + $RANDOM))
        fi
      fi
      SHADOWSOCKS_PASSWORD=$(openssl rand -base64 24)
      SHADOWTLS_PASSWORD=$(openssl rand -base64 24)
      cat << EOF > "${HOME}/sing-box/config.json"
{
	"log": {
		"disabled": true
	},
	"dns": {
		"servers": [
			{
				"address": "tls://8.8.8.8"
			}
		]
	},
	"inbounds": [
		{
			"type": "shadowtls",
			"listen": "::",
			"listen_port": ${PORT},
			"version": 3,
			"users": [
				{
					"name": "sekai",
					"password": "${SHADOWTLS_PASSWORD}"
				}
			],
			"handshake": {
				"server": "${SITE}",
				"server_port": 443
			},
      "strict_mode": true,
			"detour": "shadowsocks-in"
		},
		{
			"type": "shadowsocks",
			"tag": "shadowsocks-in",
			"listen": "127.0.0.1",
			"network": "tcp",
			"method": "2022-blake3-aes-128-gcm",
			"password": "${SHADOWSOCKS_PASSWORD}"
		}
	],
 "outbounds": [
        {
            "tag": "direct",
            "type": "direct"
        },
        {
            "tag": "block",
            "type": "block"
        },
        {
            "tag": "dns-out",
            "type": "dns"
        }
	],
 "route": {
        "auto_detect_interface": true,
        "final": "direct",
        "geoip": {
            "download_detour": "direct",
            "download_url": "https://github.com/malikshi/sing-box-geo/releases/latest/download/geoip.db",
            "path": "/root/sing-box/geoip.db"
        },
        "geosite": {
            "download_detour": "direct",
            "download_url": "https://github.com/malikshi/sing-box-geo/releases/latest/download/geosite.db",
            "path": "/root/sing-box/geosite.db"
        },
        "rules": [
            {
                "outbound": "dns-out",
                "protocol": "dns"
            },
            {
                "domain_suffix": [
                    ".cn",
                    ".ru",
                    ".ir",
                    ".cu",
                    ".vn",
                    ".zw",
                    ".by"
                ],
                "geoip": [
                    "cn",
                    "ru",
                    "ir",
                    "cu",
                    "vn",
                    "zw",
                    "by"
                ],
                "geosite": [
                    "oisd-full",
                    "rule-ads",
                    "rule-malicious"
                ],
                "outbound": "block"
            }
        ]
    }

}
EOF
      systemctl restart sing-box.service
			echo "Updated!"
			echo "Copy this content for client config.json file"
      cat << EOF
{
  "dns": {
    "rules": [],
    "servers": [
      {
        "address": "tls://8.8.8.8",
        "tag": "dns-remote",
        "detour": "ss",
        "strategy": "ipv4_only"
      }
    ]
  },
  "inbounds": [
    {
      "type": "tun",
      "interface_name": "ipv4-tun",
      "inet4_address": "172.19.0.1/28",
      "mtu": 1500,
      "stack": "gvisor",
      "endpoint_independent_nat": true,
      "auto_route": true,
      "strict_route": true,
      "sniff": true
    }
  ],
  "outbounds": [
    {
      "type": "shadowsocks",
      "tag": "ss",
      "method": "2022-blake3-aes-128-gcm",
      "password": "${SHADOWSOCKS_PASSWORD}",
      "detour": "shadowtls-out",
      "udp_over_tcp": {
        "enabled": true,
        "version": 2
      }
    },
    {
      "type": "shadowtls",
      "tag": "shadowtls-out",
      "server": "${VPS_IP}",
      "server_port": ${PORT},
      "version": 3,
      "password": "${SHADOWTLS_PASSWORD}",
      "tls": {
        "enabled": true,
        "server_name": "${SITE}",
        "utls": {
          "enabled": true,
          "fingerprint": "firefox"
        }
      }
    },
        {
            "tag": "direct",
            "type": "direct"
        },
        {
            "tag": "block",
            "type": "block"
        },
        {
            "tag": "dns-out",
            "type": "dns"
        }
  ],
    "route": {
        "auto_detect_interface": true,
        "final": "ss",
		"geoip": {
            "download_detour": "direct",
            "download_url": "https://github.com/malikshi/sing-box-geo/releases/latest/download/geoip.db",
            "path": "geoip.db"
        },
        "rules": [
            {
                "outbound": "dns-out",
                "protocol": "dns"
            },
            {
                "domain_suffix": [
                    ".cn",
                    ".ru",
                    ".ir",
                    ".cu",
                    ".vn",
                    ".zw",
                    ".by"
                ],
                "geoip": [
                    "cn",
                    "ru",
                    "ir",
                    "cu",
                    "vn",
                    "zw",
                    "by",
                    "private"
                ],
                "outbound": "direct"
            }
        ]
    }
}
EOF
      break;;
    update_sing_box)
      systemctl stop sing-box.service

      #get latest version
      LATEST_URL=$(curl -Ls -o /dev/null -w %{url_effective} https://github.com/SagerNet/sing-box/releases/latest)
      LATEST_VERSION="$(echo $LATEST_URL |grep -o -E '/.?[0-9|\.]+$'| grep -o -E '[0-9|\.]+')"
      LINK="https://github.com/SagerNet/sing-box/releases/download/v${LATEST_VERSION}/sing-box-${LATEST_VERSION}-linux-amd64.tar.gz"
      wget "$LINK"
      tar -xf "sing-box-${LATEST_VERSION}-linux-amd64.tar.gz"
      cp "sing-box-${LATEST_VERSION}-linux-amd64/sing-box" "${HOME}/sing-box"
      rm -rf "sing-box-${LATEST_VERSION}-linux-amd64.tar.gz" "sing-box-${LATEST_VERSION}-linux-amd64"

      systemctl start sing-box.service
      echo "Latest version installed!" 
      break;;
    uninstall)
      systemctl disable sing-box.service
      systemctl stop sing-box.service
      rm "/etc/systemd/system/sing-box.service"
      systemctl daemon-reload
      crontab -l | grep -v "restart-sing-box.sh" | crontab -
      rm -rf "${HOME}/sing-box"
      echo "Uninstalled!" 
      break;;
    quit)
      break;;
    *)
      echo "Invalid option"
      break;;
  esac
done
