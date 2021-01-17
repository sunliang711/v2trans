#!/bin/bash
rpath="$(readlink ${BASH_SOURCE})"
if [ -z "$rpath" ];then
    rpath=${BASH_SOURCE}
fi
pwd=${PWD}
this="$(cd $(dirname $rpath) && pwd)"
# cd "$this"
export PATH=$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

user="${SUDO_USER:-$(whoami)}"
home="$(eval echo ~$user)"

# export TERM=xterm-256color

# Use colors, but only if connected to a terminal, and that terminal
# supports them.
if which tput >/dev/null 2>&1; then
  ncolors=$(tput colors 2>/dev/null)
fi
if [ -t 1 ] && [ -n "$ncolors" ] && [ "$ncolors" -ge 8 ]; then
    RED="$(tput setaf 1)"
    GREEN="$(tput setaf 2)"
    YELLOW="$(tput setaf 3)"
    BLUE="$(tput setaf 4)"
            CYAN="$(tput setaf 5)"
    BOLD="$(tput bold)"
    NORMAL="$(tput sgr0)"
else
    RED=""
    GREEN=""
    YELLOW=""
            CYAN=""
    BLUE=""
    BOLD=""
    NORMAL=""
fi
_err(){
    echo "$*" >&2
}

_runAsRoot(){
    cmd="${*}"
    local rootID=0
    if [ "${EUID}" -ne "${rootID}" ];then
        echo -n "Not root, try to run as root.."
        # or sudo sh -c ${cmd} ?
        if eval "sudo ${cmd}";then
            echo "ok"
            return 0
        else
            echo "failed"
            return 1
        fi
    else
        # or sh -c ${cmd} ?
        eval "${cmd}"
    fi
}

rootID=0
function _root(){
    if [ ${EUID} -ne ${rootID} ];then
        echo "Need run as root!"
        exit 1
    fi
}

ed=vi
if command -v vim >/dev/null 2>&1;then
    ed=vim
fi
if command -v nvim >/dev/null 2>&1;then
    ed=nvim
fi
if [ -n "${editor}" ];then
    ed=${editor}
fi
###############################################################################
# write your code below (just define function[s])
# function is hidden when begin with '_'
###############################################################################
# TODO
lanSubnet="10.1.1.0/24"
start(){
    _runAsRoot "systemctl start v2trans.service"
}

a(){

    cd "${this}/.."
    local v2Tmp=/tmp/v2trans.tmp
sed -n -e '1,/BEGIN vpn domain/p' etc/config.json.tmpl #> "${v2Tmp}"
while read -r line;do
    echo ",\"${line}\"" >> "${v2Tmp}"
done</tmp/outboundAddress

sed -n -e '/END vpn domain/,$p' etc/config.json.tmp >> "${v2Tmp}"
}

_start_pre(){
    local v2Tmp=/tmp/v2trans.tmp
    sed -n -e '1,/BEGIN vps domain/p' ${this}/../etc/config.json.tmpl > "${v2Tmp}"
    while read -r line;do
        echo ",\"${line}\"" >> "${v2Tmp}"
    done</tmp/outboundAddress

    sed -n -e '/END vps domain/,$p' ${this}/../etc/config.json.tmpl >> "${v2Tmp}"

    mv "${v2Tmp}" etc/config.json

# 设置策略路由
ip rule add fwmark 1 table 100
ip route add local 0.0.0.0/0 dev lo table 100

# 代理局域网设备
iptables -t mangle -N V2RAY
iptables -t mangle -A V2RAY -d 127.0.0.1/32 -j RETURN
iptables -t mangle -A V2RAY -d 224.0.0.0/4 -j RETURN
iptables -t mangle -A V2RAY -d 255.255.255.255/32 -j RETURN
# 直连局域网，避免 V2Ray 无法启动时无法连网关的 SSH，如果你配置的是其他网段（如 10.x.x.x 等），则修改成自己的网段
iptables -t mangle -A V2RAY -d "${lanSubnet}" -p tcp -j RETURN
# 直连局域网，53 端口除外（因为要使用 V2Ray 的 DNS 解析)
iptables -t mangle -A V2RAY -d "${lanSubnet}" -p udp ! --dport 53 -j RETURN 
# 给 UDP 打标记 1，转发至 12345 端口
iptables -t mangle -A V2RAY -p udp -j TPROXY --on-port 12345 --tproxy-mark 1
# 给 TCP 打标记 1，转发至 12345 端口
iptables -t mangle -A V2RAY -p tcp -j TPROXY --on-port 12345 --tproxy-mark 1
# 应用规则
iptables -t mangle -A PREROUTING -j V2RAY

# 代理网关本机
iptables -t mangle -N V2RAY_MASK
iptables -t mangle -A V2RAY_MASK -d 224.0.0.0/4 -j RETURN
iptables -t mangle -A V2RAY_MASK -d 255.255.255.255/32 -j RETURN
# 直连局域网
iptables -t mangle -A V2RAY_MASK -d "${lanSubnet}" -p tcp -j RETURN
# 直连局域网，53 端口除外（因为要使用 V2Ray 的 DNS）
iptables -t mangle -A V2RAY_MASK -d "${lanSubnet}" -p udp ! --dport 53 -j RETURN
# 直连 SO_MARK 为 0xff 的流量(0xff 是 16 进制数，数值上等同与上面V2Ray 配置的 255)，此规则目的是避免代理本机(网关)流量出现回环问题
iptables -t mangle -A V2RAY_MASK -j RETURN -m mark --mark 0xff
# 给 UDP 打标记,重路由
iptables -t mangle -A V2RAY_MASK -p udp -j MARK --set-mark 1
# 给 TCP 打标记，重路由
iptables -t mangle -A V2RAY_MASK -p tcp -j MARK --set-mark 1
# 应用规则
iptables -t mangle -A OUTPUT -j V2RAY_MASK
}

stop(){
    _runAsRoot "systemctl stop v2trans"
}

_stop_post(){
    iptables -t mangle -F V2RAY
    iptables -t mangle -D PREROUTING -j V2RAY

    iptables -t mangle -F V2RAY_MASK
    iptables -t mangle -D OUTPUT -j V2RAY_MASK

    iptables -t mangle -X V2RAY
    iptables -t mangle -X V2RAY_MASK
}

log(){
    _runAsRoot "journalctl -u v2trans.service -f"
}


em(){
    $ed $0
}

###############################################################################
# write your code above
###############################################################################
function _help(){
    cd ${this}
    cat<<EOF2
Usage: $(basename $0) ${bold}CMD${reset}

${bold}CMD${reset}:
EOF2
    # perl -lne 'print "\t$1" if /^\s*(\w+)\(\)\{$/' $(basename ${BASH_SOURCE})
    # perl -lne 'print "\t$2" if /^\s*(function)?\s*(\w+)\(\)\{$/' $(basename ${BASH_SOURCE}) | grep -v '^\t_'
    perl -lne 'print "\t$2" if /^\s*(function)?\s*(\w+)\(\)\{$/' $(basename ${BASH_SOURCE}) | perl -lne "print if /^\t[^_]/"
}

function _loadENV(){
    if [ -z "$INIT_HTTP_PROXY" ];then
        echo "INIT_HTTP_PROXY is empty"
        echo -n "Enter http proxy: (if you need) "
        read INIT_HTTP_PROXY
    fi
    if [ -n "$INIT_HTTP_PROXY" ];then
        echo "set http proxy to $INIT_HTTP_PROXY"
        export http_proxy=$INIT_HTTP_PROXY
        export https_proxy=$INIT_HTTP_PROXY
        export HTTP_PROXY=$INIT_HTTP_PROXY
        export HTTPS_PROXY=$INIT_HTTP_PROXY
        git config --global http.proxy $INIT_HTTP_PROXY
        git config --global https.proxy $INIT_HTTP_PROXY
    else
        echo "No use http proxy"
    fi
}

function _unloadENV(){
    if [ -n "$https_proxy" ];then
        unset http_proxy
        unset https_proxy
        unset HTTP_PROXY
        unset HTTPS_PROXY
        git config --global --unset-all http.proxy
        git config --global --unset-all https.proxy
    fi
}


case "$1" in
     ""|-h|--help|help)
        _help
        ;;
    *)
        "$@"
esac
