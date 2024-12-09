#!/bin/bash

# 定义当前版本号
SCRIPT_VERSION="1.0.0"

# 检查是否提供了扩展名参数
if [ -z "$1" ]; then
    echo "用法: $0 <文件扩展名> [<目录路径>]"
    exit 1
fi

fm_EXTENSION="$1"
fm_WORKDIR="${2:-$(pwd)}"

# 检查目录是否存在
if [ ! -d "$fm_WORKDIR" ]; then
    echo -e "${Error} ${RedBG} 目录 $fm_WORKDIR 不存在 请检查路径 ${Font}"
    exit 1
fi

# 保存当前工作目录
original_dir=$(pwd)

# 切换到工作目录
cd "$fm_WORKDIR" || exit 1

# 函数: 列出当前目录下所有指定扩展名的文件
fm_list_files() {
    echo -e "${GreenBG} 列出所有 .$fm_EXTENSION 文件 ${Font}"
    ls "*.$fm_EXTENSION" 2>/dev/null || echo -e "${Warning} ${YellowBG} 没有找到 .$fm_EXTENSION 文件 ${Font}"
}

# 函数: 创建一个新的 serverName 文件
fm_create_servername_file() {
    local url
    read -p "请输入网址 (例如 hey.run ), 不要包含 http:// 或 https:// 开头: " url
    if [[ $url =~ ^(http|https):// ]]; then
        echo -e "${Error} ${RedBG} 网址不能包含 http:// 或 https:// 开头 ${Font}"
        return
    fi
    echo "${url}: reality;" > "${url}.serverName"
    echo -e "${OK} ${GreenBG} 文件 ${url}.serverName 已创建 ${Font}"
    fm_restart_nginx_and_check_status
}

# 函数: 创建一个新的 wsServer 或 grpcServer 文件
fm_create_ws_or_grpc_server_file() {
    local host port weight content firewall_set_fq
    read -p "请输入主机 (host): " host
    read -p "请输入端口 (port): " port
    read -p "请输入权重 (0~100 默认值 50): " weight
    weight=${weight:-50}
    
    if ! [[ $weight =~ ^[0-9]+$ ]] || [ "$weight" -lt 0 ] || [ "$weight" -gt 100 ]; then
        echo -e "${Error} ${RedBG} 权重必须是 0 到 100 之间的整数 ${Font}"
        return
    fi
    
    content="server ${host}:${port} weight=${weight} max_fails=2 fail_timeout=10;"
    echo "$content" > "${host}.${fm_EXTENSION}"
    echo -e "${OK} ${GreenBG} 文件 ${host}.${fm_EXTENSION} 已创建 ${Font}"

    # 询问是否需要修改防火墙
    echo -e "\n${GreenBG} 是否需要设置防火墙 [Y/${Red}N${Font}${GreenBG}]? ${Font}"
    read -r firewall_set_fq
    case $firewall_set_fq in
    [yY][eE][sS] | [yY])
                
        if [[ "${ID}" == "centos" ]]; then
            pkg_install "iptables-services"
        else
            pkg_install "iptables-persistent"
        fi
        iptables -I INPUT -p tcp --dport ${port} -j ACCEPT
        iptables -I INPUT -p udp --dport ${port} -j ACCEPT
        iptables -I OUTPUT -p tcp --sport ${port} -j ACCEPT
        iptables -I OUTPUT -p udp --sport ${port} -j ACCEPT
        echo -e "${OK} ${GreenBG} 防火墙 追加 完成 ${Font}"
        if [[ "${ID}" == "centos" && ${VERSION_ID} -ge 7 ]]; then
            service iptables save
            service iptables restart
            echo -e "${OK} ${GreenBG} 防火墙 重启 完成 ${Font}"
        else
            netfilter-persistent save
            systemctl restart iptables
            echo -e "${OK} ${GreenBG} 防火墙 重启 完成 ${Font}"
        fi
    ;;
    *)
        echo -e "${OK} ${GreenBG} 跳过防火墙设置 ${Font}"
        ;;
    esac
    fm_restart_nginx_and_check_status
}

# 函数: 编辑一个已存在的指定扩展名的文件
fm_edit_file() {
    fm_list_files
    local filename
    read -p "请输入要编辑的 .$fm_EXTENSION 文件名 (不包括扩展名 ): " filename
    if [ -f "${filename}.${fm_EXTENSION}" ]; then
        # 检查 vim 是否安装
        if ! command -v vim &> /dev/null; then
            echo -e "${Warning} ${YellowBG} vim 未安装 正在尝试安装 ${Font}"
            pkg_install vim
        fi
        vim "${filename}.${fm_EXTENSION}"
        echo -e "${OK} ${GreenBG} 文件 ${filename}.${fm_EXTENSION} 已编辑 ${Font}"
        fm_restart_nginx_and_check_status
    else
        echo -e "${Error} ${RedBG} 文件 ${filename}.${fm_EXTENSION} 未找到 ${Font}"
    fi
}

# 函数: 删除一个已存在的指定扩展名的文件
fm_delete_file() {
    fm_list_files
    local filename
    read -p "请输入要删除的 .$fm_EXTENSION 文件名 (不包括扩展名 ): " filename
    if [ -f "${filename}.${fm_EXTENSION}" ]; then
        rm "${filename}.${fm_EXTENSION}"
        echo -e "${OK} ${GreenBG} 文件 ${filename}.${fm_EXTENSION} 已删除 ${Font}"
        fm_restart_nginx_and_check_status
    else
        echo -e "${Error} ${RedBG} 文件 ${filename}.${fm_EXTENSION} 未找到 ${Font}"
    fi
}

# 根据扩展名选择创建文件的方式
fm_create_file() {
    case $fm_EXTENSION in
        serverName)
            fm_create_servername_file
            ;;
        wsServer|grpcServer)
            fm_create_ws_or_grpc_server_file
            ;;
        *)
            echo -e "${Error} ${RedBG} 不支持的文件扩展名 $fm_EXTENSION ${Font}"
            ;;
    esac
}

# 主菜单循环
fm_main_menu() {
    while true; do
        echo
        echo -e "${GreenBG} 主菜单 ${Font}"
        echo -e "1 ${Green}列出所有 $fm_EXTENSION 文件${Font}"
        echo -e "2 ${Green}创建一个新的 $fm_EXTENSION 文件${Font}"
        echo -e "3 ${Green}编辑一个已存在的 $fm_EXTENSION 文件${Font}"
        echo -e "4 ${Green}删除一个已存在的 $fm_EXTENSION 文件${Font}"
        echo -e "5 ${Green}退出${Font}"
        local choice
        read -p "请选择一个选项: " choice

        case $choice in
            1) fm_list_files ;;
            2) fm_create_file ;;
            3) fm_edit_file ;;
            4) fm_delete_file ;;
            5) source "$idleleo" ;;
            *) echo -e "${Error} ${RedBG} 无效选项 请重试 ${Font}" ;;
        esac
    done
}

check_for_updates() {
    local latest_version=""
    local update_choice=""

    # 直接使用 curl 下载远程版本信息
    latest_version=$(curl -s "$fm_remote_version_url")

    if [ -n "$latest_version" ] && [ "$latest_version" != "$SCRIPT_VERSION" ]; then
        echo -e "${Warning} ${YellowBG} 新版本可用: $latest_version 当前版本: $SCRIPT_VERSION ${Font}"
        echo -e "${Warning} ${YellowBG} 请访问 https://github.com/hello-yunshu/Xray_bash_onekey 查看更新说明 ${Font}"

        echo -e "${GreenBG} 是否要下载并安装新版本 [Y/${Red}N${Font}${GreenBG}]? ${Font}"
        read -r update_choice
        case $update_choice in
            [yY][eE][sS] | [yY])
                echo -e "${Info} ${Green} 正在下载新版本... ${Font}"
                curl -sL "$fm_remote_version_url" -o "${idleleo_dir}/file_manager.sh"

                if [ $? -eq 0 ]; then
                    chmod +x "${idleleo_dir}/file_manager.sh"
                    echo -e "${OK} ${Green} 下载完成，正在重新运行脚本... ${Font}"
                    source "${idleleo_dir}/file_manager.sh"
                else
                    echo -e "${Error} ${RedBG} 下载失败，请手动下载并安装新版本 ${Font}"
                fi
                ;;
            *)
                echo -e "${OK} ${Green} 跳过更新 ${Font}"
                ;;
        esac
    else
        echo -e "${OK} ${Green} 当前已经是最新版本: $SCRIPT_VERSION ${Font}"
    fi
}

fm_restart_nginx_and_check_status() {
    if [[ -f ${nginx_systemd_file} ]]; then
        systemctl restart nginx
        if systemctl is-active --quiet nginx; then
            echo -e "${OK} ${GreenBG} Nginx 重启成功 ${Font}"
        else
            echo -e "${Error} ${RedBG} Nginx 重启失败 请检查配置文件是否有误 ${Font}"
            fm_edit_file
        fi
    fi
}

# 检查更新
check_for_updates

# 运行主菜单
fm_main_menu

# 恢复原始工作目录
cd "$original_dir" || exit 1