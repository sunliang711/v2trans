#!/bin/bash

rpath="$(readlink ${BASH_SOURCE})"
if [ -z "$rpath" ];then
    rpath=${BASH_SOURCE}
fi

root="$(cd $(dirname $rpath) && pwd)"
cd "$root"

need(){
    if ! command -v $1 >/dev/null 2>&1;then
        echo "need $1"
        exit 1
    fi
}

need curl
need unzip

downloadDir=/tmp/v2ray-download
echo "downloadDir: $downloadDir"
if [ ! -d "$downloadDir" ];then
    mkdir "$downloadDir"
fi
cd "$downloadDir"

version=4.32.1
case $(uname) in
    Darwin)
        url="https://source711.oss-cn-shanghai.aliyuncs.com/v2ray/${version}/MacOS/v2ray-macos.zip"
        zipfile=${url##*/}
        dest=$root/Darwin
        ;;
    Linux)
        url="https://source711.oss-cn-shanghai.aliyuncs.com/v2ray/${version}/Linux/v2ray-linux-64.zip"
        zipfile=${url##*/}
        dest=$root/Linux
        ;;
esac

# rasperberry arm64
if [ $(uname -m) == "aarch64" ];then
    url=https://source711.oss-cn-shanghai.aliyuncs.com/v2ray/${version}/Linux/v2ray-linux-arm64-v8a.zip
    zipfile=${url##*/}
    dest=$root/Linux
fi

if [ -d "$dest" ];then
    rm -rf "$dest"
fi
mkdir "$dest"

if [ ! -e "$zipfile" ];then
    curl -LO "$url" || { echo "download $zipfile error"; exit 1; }
fi

echo "unzip zipfile: $zipfile..."
unzip -d "$dest" "$zipfile"


cd "$root"
