---
title: "Home Automation at School"
date: "2021-04-21"
author: "William Floyd"
featured_image: "media/20200813_023018.jpg"
categories: [
    "Software"
]
tags: [
    "School",
    "Home Assistant",
    "Home Automation",
    "ESPHome",
    "IOT"
]
---

I love home automation - I've spent far longer writing automation routines and hacking together my own devices and programs than I have ever saved by doing so, and that's perfectly fine.
One unique aspect of my setup, however, is that I cannot control the network I must use - in my Uni dorm, I am not allowed to run my own router, and so all IoT devices must connect to the school wireless network.
There abound dozens of Google Home devices, Chromecasts, and so on, all accessible on the same network - but not from the wired connection that my server/desktop uses.

Here then is my solution: MQTT everything I can.
From my lights, so light sensor, to coffee maker to desktop software, I bounce it through a MQTT server hosted on a VPS.
I use Home Assistant, so automatic discovery is easy on most things, especially ESPHome.
In fact, I disabled direct Home Assistant connectivity entirely on these devices, which works well enough for me to live with.

# But how to flash?

Given that my Home Assistant instance isn't even on the same network as the IoT devices, how do I update the firmware?
Using my laptop, I can connect to the wireless network that they reside on, and using IP address sensors reported by these devices, flash them directly without needing local discovery.
In fact, I can easily automate this for myself using a couple scripts and a minimal number of hard-coded values:

`hassio.sh`
```bash
#!/bin/bash

export HASS_SERVER=https://<server_url>:443
export HASS_TOKEN='<HA_Token>'

hass-cli ${@}

exit

```

`lamps.sh`
```bash
#!/bin/bash

declare -A aa

aa["gosund_lb1_1.yaml"]="sensor.desk_lamp_ip_address"
aa["gosund_lb1_2.yaml"]="sensor.bed_lamp_ip_address"
aa["gosund_lb1_3.yaml"]="sensor.floor_lamp_girlfriend_ip_address"
aa["gosund_lb1_4.yaml"]="sensor.desk_lamp_girlfriend_ip_address"
aa["gosund_lb1_5.yaml"]="sensor.floor_lamp_ip_address"

__flash() {

    __config="${1}"
    __entity_name="${aa[${__config}]}"
    echo "Getting ${__config} IP..."

    __ip="$(
        ./hassio.sh -o yaml state get \
            "${__entity_name}" |
            grep -E '^ *state' | sed -e 's/.* //'
    )"

    echo "IP: ${__ip}"

    if [ "${__ip}" == 'unavailable' ]; then
        echo 'Ignoring...'
    else
        echo "Flashing..."
        ./esphome.sh "${__config}" run --upload-port="${__ip}"
    fi
    
    echo

}

if [ "${#}" -gt 0 ]; then
    until [ "${#}" == 0 ]; do
        __flash "${1}"
        shift
    done
else
    for __config in ${!aa[@]}; do
        __flash "${__config}"
    done
fi

exit
```

this allows me to mostly painlessly flash my devices, though truth be told there is little need.

# Custom software

I developed for myself a tool in Golang to help tie more of my devices together.
It is rather uncreatively/cryptically named `ha-mqtt-iot` - that is, "Home Assistant MQTT Internet of Things".
I may rename this some day, but why bother.
It is similar to IOTLink (which is Windows only), and HASS Workstation Service - they are great projects, but this one is mine, even if it is poorly written.

The gist of the software is that most (all?) device types supported by Home Assistant may be implemented using a selection of user defined commands.
The most prominent examples in my case are in order to enable/disable dark mode on my desktop.
I automate this according to ambient light in my room, to better match the aesthetic I want.
Additionally, I can use it to turn my desktop monitor off, without resorting to using a relay outlet, and even change the color temperature of my system.
The script I use for this looks like the following:

```bash
#!/bin/bash

__monitor_i2c='dev:/dev/i2c-3'
__monitor_dpms='0xd6'
__monitor_brightness='0x10'
__monitor_standby='4'
__monitor_off='5'
__monitor_on='1'

__unknown() {
    echo "Unknown ${1}"
}

f2i() {
    awk 'BEGIN{for (i=1; i<ARGC;i++)
   printf "%.0f\n", ARGV[i]}' "$@"
}

com="${1}"
arg="${2}"

case "${com}" in
"command")
    case "${arg}" in
    "ON")
        xset dpms force on
        ;;
    "OFF")
        (
            #xset dpms force off
            #sleep 0.5s
            #ddccontrol -r "${__monitor_dpms}" -w "${__monitor_standby}" "${__monitor_i2c}" -f
            #sleep 2s
            ddccontrol -r "${__monitor_dpms}" -w "${__monitor_off}" "${__monitor_i2c}" -f
        ) &
        ;;
    *)
        __unknown "${arg}"
        ;;
    esac
    ;;
"command-state")
    echo -n "$(xset q | grep 'Monitor is' | sed -e 's/.* //' | tr '[:lower:]' '[:upper:]')"
    ;;
"color-temp")
    v="$(f2i "$(bc -l <<<"1000000/${arg}")")"
    ./scripts/run-in-user-session.sh gsettings set org.gnome.settings-daemon.plugins.color night-light-temperature "${v}"
    ;;
"color-temp-state")
    v="$(./scripts/run-in-user-session.sh gsettings get org.gnome.settings-daemon.plugins.color night-light-temperature)"
    echo -n "$(f2i "$(bc -l <<<"1000000/${v/* /}")")"
    ;;
"brightness")
    ddccontrol -r "${__monitor_brightness}" "${__monitor_i2c}" -w "${arg}"
    ;;
"brightness-state")
    echo -n "$(ddccontrol 2>/dev/null -r "${__monitor_brightness}" "${__monitor_i2c}" | tail -n 1 | grep -o '/[0-9]*/100' | sed -e 's|^/||' -e 's|/.*||')"
    ;;

*)
    __unknown "root command ${com}"
    ;;
esac

exit
```

Note that the display doesn't respond to being turned back on, so this is somewhat incomplete, but it's good enough for my needs.
The corresponding portion of the config for `ha-mqtt-iot` looks like the following:

```json
    "lights": [
        {
            "info": {
                "name": "Desktop Monitor",
                "id": "monitor"
            },
            "command": [
                "./scripts/monitor.sh",
                "command"
            ],
            "command_state": [
                "./scripts/monitor.sh",
                "command-state"
            ],
            "command_color_temp": [
                "./scripts/monitor.sh",
                "color-temp"
            ],
            "command_color_temp_state": [
                "./scripts/monitor.sh",
                "color-temp-state"
            ],
            "command_brightness": [
                "./scripts/monitor.sh",
                "brightness"
            ],
            "command_brightness_state": [
                "./scripts/monitor.sh",
                "brightness-state"
            ],
            "brightness_scale": 100,
            "update_interval": 5
        }
    ]
```

Pretty simple.
This makes custom system sensors trivial.
For example, to show my system IP, I use the following:

```json
    "sensors": [
        {
            "info": {
                "name": "IP Address Desktop Solus",
                "id": "ip-address-desktop-solus",
                "icon": "mdi:ip-network"
            },
            "command_state": [
                "/bin/bash",
                "-c",
                "ip -j address show eno1 | jq -r '.[0].addr_info[0].local'"
            ],
            "update_interval": 10
        }
    ]
```

Some common use cases are built in as well.
Currently, this includes laptop displays (as lights) and batteries (as sensors), as well as Crypto prices (though the CoinGecko Golang library).
These are really easy to call.
An exhaustive example is quite short:

```json
    "builtin": {
        "prefix": "Name Prefix ",
        "backlight": {
            "enable": true,
            "temperature": false,
            "range": {
                "minimum": 0.025,
                "maximum": 0.95
            }
	},
	"battery": {
            "enable": true
        },
	"crypto": [
            {
             	"coin_name": "dogecoin",
                "currency_name": "usd",
                "update_interval": 1,
                "icon": "mdi:currency-usd"
            }
	]
    }
```

This lets me tailor my setup to each machine I'm using, while still enjoying the benefits of Home Assistant MQTT Discovery.
The primary limitation at present is the inability to signal to `ha-mqtt-iot` from another process - it can only poll for changes.
This will be addressed one day, when it is important for my own needs.

# How to host?

But the question is now, how do I access my HomeAssistant instance if it's also hosted at school?
I most certainly don't have a public IP, so in comes AutoSSH.
I'm not sure which is the best one at this stage, but refer to [this](https://github.com/psallandre/hassio-addons-autossh) repo and check the various forks of the parent project.

I have configured on my VPS a docker image that accepts reverse SSH tunnelling, authorized only to the key of the HA addon.
From my `docker-compose.yml`:

```json
  homeassistant:
    image: "docker.io/panubo/sshd"
    container_name: homeassistant
    environment:
      - TCP_FORWARDING=true
      - GATEWAY_PORTS=true
      - SSH_ENABLE_ROOT=true
      - DISABLE_SFTP=true
    volumes:
      - "./hassio/authorized_keys:/root/.ssh/authorized_keys:ro"
      - ./docker-config/hassio/data/:/data
      - ./docker-config/hassio/keys/:/etc/ssh/keys
    ports:
      - "<MY_PORT>:22"
    restart: unless-stopped
    hostname: "homeassistant"
```

This is then reverse proxied to using Caddy, to expose the website on a subdomain of a website.
From my `Caddyfile`:

```dockerfile
<MY_SUBDOMAIN>.{$MY_DOMAIN} {
    reverse_proxy homeassistant:8123
    encode gzip
}
```

Pretty simple, but not without some hiccups now and again - I occasionally have to restart the sshd docker on my VPS if something goes wrong with HomeAssistant.

# Bonus: Android tie in

I use Sleep As Android to track my sleeping patterns, and as my alarm clock.
Using Tasker, I can run an action when I begin sleep tracking, which (using a HomeAssistant plugin for Tasker) can call a script on my HomeAssistant instance to turn off my lights (only if I'm home, of course).
Similarly, it turns on my bedhead light when my alarm goes off in the morning, and could optionally make me coffee...