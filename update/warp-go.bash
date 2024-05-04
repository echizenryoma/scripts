#!/bin/bash

function check_arch() {
    case $(uname -m) in
        x86_64)
            arch=amd64
        ;;
        aarch64 | aarch64_be | arm64 | armv8b | armv8l)
            arch=armv7
        ;;
        *)
            echo -e "${Error} Unknown CPU arch"
            exit 1
        ;;
    esac
}

function get_x86_level() {
    if [[ arch != "amd64" ]]; then
        return
    fi
    local level
    level=$(curl -Lsf https://raw.githubusercontent.com/HenrikBengtsson/x86-64-level/main/x86-64-level | bash 2>/dev/null)
    if [[ -n "$level" ]]; then
        echo "v$level"
    fi
}

function get_latest_version() {
  local api_url="https://gitlab.com/api/v4/projects/ProjectWARP%2Fwarp-go/releases"
  curl -Lsf "$api_url" | jq -r '.[0].name' | tr -d 'v'
}

function upgrade() {
    mkdir -p /opt/warp-go
    mkdir -p /tmp/warp-go

    echo "Latest version: $version"

    pushd /tmp/warp-go
    curl -L "https://gitlab.com/ProjectWARP/warp-go/-/releases/v${version}/downloads/warp-go_${version}_linux_${arch}${level}.tar.gz" -o warp-go.tar.gz
    tar zxvf warp-go.tar.gz
    chmod +x warp-go
    mv -f warp-go /opt/warp-go/
    popd

    rm -rf /tmp/warp-go
}

check_arch
level="$(get_x86_level)"
version=$(get_latest_version)
upgrade
