#!/bin/bash

# 定义当前版本号
mf_SCRIPT_VERSION="1.0.4"

mf_main_menu() {
    check_system
    echo -e -e "\n${GreenBG} 设置 Fail2ban 用于防止暴力破解, 请选择: ${Font}"
    echo -e "1. ${Green}安装 Fail2ban${Font}"
    echo -e "2. ${Green}管理 Fail2ban${Font}"
    echo -e "3. ${Green}卸载 Fail2ban${Font}"
    echo -e "4. ${Green}查看 Fail2ban 状态${Font}"
    echo -e "5. ${Green}退出${Font}"
    read -rp "请输入: " fail2ban_fq
    [[ -z "${fail2ban_fq}" ]] && fail2ban_fq=1

    case $fail2ban_fq in
        1) mf_install_fail2ban ;;
        2) mf_manage_fail2ban ;;
        3) mf_uninstall_fail2ban ;;
        4) mf_display_fail2ban_status ;;
        5) source "${idleleo}" ;;
        *) echo -e "\n${Error} ${RedBG} 无效的选择 请重试 ${Font}" ;;
    esac
}

mf_install_fail2ban() {
    if command -v fail2ban-client &> /dev/null; then
        echo -e "${OK} ${Green} Fail2ban 已经安装, 跳过安装步骤 ${Font}"
    else
        pkg_install "fail2ban"
        mf_configure_fail2ban
        judge "Fail2ban 安装"
        source "${idleleo}"
    fi
}

mf_configure_fail2ban() {

    if [[ ! -f "/etc/fail2ban/jail.local" ]]; then
        cp -fp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
    fi

    # 检查 Nginx 是否安装
    if [[ ${tls_mode} == "TLS" || ${reality_add_nginx} == "on" ]]; then
        if [[ ! -f "${nginx_dir}/sbin/nginx" ]]; then
            echo -e "${Warning} ${YellowBG} Nginx 未安装, 请先安装 Nginx ${Font}"
            return
        fi
    fi

    if [[ -z $(grep "filter   = sshd" /etc/fail2ban/jail.local) ]]; then
        sed -i "/sshd_log/i \enabled  = true\\nfilter   = sshd\\nmaxretry = 5\\nbantime  = 604800" /etc/fail2ban/jail.local
    fi

    if [[ ${tls_mode} == "TLS" || ${reality_add_nginx} == "on" ]]; then
        sed -i "/nginx_error_log/d" /etc/fail2ban/jail.local
        sed -i "s/http,https$/http,https,8080/g" /etc/fail2ban/jail.local
        sed -i "/^maxretry.*= 2$/c \\maxretry = 5" /etc/fail2ban/jail.local
        sed -i "/nginx-botsearch/i \[nginx-badbots]\\n\\nenabled  = true\\nport     = http,https,8080\\nfilter   = apache-badbots\\nlogpath  = ${nginx_dir}/logs/access.log\\nbantime  = 604800\\nmaxretry = 5\\n" /etc/fail2ban/jail.local
        sed -i "/nginx-botsearch/a \\\nenabled  = true\\nfilter   = nginx-botsearch\\nlogpath  = ${nginx_dir}/logs/access.log\\n           ${nginx_dir}/logs/error.log\\nbantime  = 604800" /etc/fail2ban/jail.local
    fi

    # 启用 nginx-no-host 规则
    if [[ ${reality_add_nginx} == "on" ]] && [[ -z $(grep "filter   = nginx-no-host" /etc/fail2ban/jail.local) ]]; then
        mf_create_nginx_no_host_filter
        sed -i "\$ a\\\n[nginx-no-host]\nenabled  = true\nfilter   = nginx-no-host\nlogpath  = $nginx_dir/logs/error.log\nbantime  = 604800\nmaxretry = 600" /etc/fail2ban/jail.local
    fi
    systemctl daemon-reload
    systemctl restart fail2ban
    judge "Fail2ban 配置"
}

mf_create_nginx_no_host_filter() {
    local filter_file="/etc/fail2ban/filter.d/nginx-no-host.conf"
    if [[ ! -f "$filter_file" ]]; then
        cat >"$filter_file" <<EOF
[Definition]
failregex = \[error\].*?no host in upstream.*?, client: <HOST>,
ignoreregex =
EOF
    fi
}

mf_manage_fail2ban() {
    if ! command -v fail2ban-client &> /dev/null; then
        echo -e "${Error} ${RedBG} Fail2ban 未安装, 请先安装 Fail2ban ${Font}"
        return
    fi

    echo -e "\n${Green} 请选择 Fail2ban 操作: ${Font}"
    echo "1. 启动 Fail2ban"
    echo "2. 重启 Fail2ban"
    echo "3. 停止 Fail2ban"
    echo "4. 添加自定义规则"
    echo "5. 返回"
    read -rp "请输入: " mf_action
    [[ -z "${mf_action}" ]] && mf_action=1

    case $mf_action in
        1)
            mf_start_enable_fail2ban
            ;;
        2)
            mf_restart_fail2ban
            mf_main_menu
            ;;
        3)
            mf_stop_disable_fail2ban
            ;;
        4)
            mf_add_custom_rule
            mf_main_menu
            ;;
        5) mf_main_menu ;;
        *)
            echo -e "\n${Error} ${RedBG} 无效的选择 请重试 ${Font}"
            ;;
    esac
}

mf_add_custom_rule() {
    local jail_name
    local filter_name
    local log_path
    local max_retry
    local ban_time

    read -rp "请输入新的 Jail 名称: " jail_name
    read -rp "请输入 Filter 名称: " filter_name
    read -rp "请输入日志路径: " log_path
    read -rp "请输入最大重试次数 (默认 5): " max_retry
    read -rp "请输入封禁时间 (秒, 默认 604800 秒): " ban_time

    max_retry=${max_retry:-5}
    ban_time=${ban_time:-604800}

    if [[ -z "$jail_name" || -z "$filter_name" || -z "$log_path" ]]; then
        echo -e "\n${Error} ${RedBG} Jail 名称、Filter 名称和日志路径不能为空 ${Font}"
        return
    fi

    if grep -q "\[$jail_name\]" /etc/fail2ban/jail.local; then
        echo -e "${Warning} ${YellowBG} Jail '$jail_name' 已存在 ${Font}"
        return
    fi

    echo -e "[$jail_name]\nenabled  = true\nfilter   = $filter_name\nlogpath  = $log_path\nmaxretry = $max_retry\nbantime  = $ban_time\n" >> /etc/fail2ban/jail.local
    echo -e "${OK} ${GreenBG} 自定义规则添加成功 ${Font}"

    systemctl daemon-reload
    systemctl restart fail2ban
    judge "Fail2ban 重启以应用新规则"
}

mf_start_enable_fail2ban() {
    systemctl daemon-reload
    systemctl start fail2ban
    systemctl enable fail2ban
    judge "Fail2ban 启动"
    timeout "清空屏幕!"
    clear
}

mf_uninstall_fail2ban() {
    systemctl stop fail2ban
    systemctl disable fail2ban
    ${INS} -y remove fail2ban
    [[ -f "/etc/fail2ban/jail.local" ]] && rm -rf /etc/fail2ban/jail.local
    if [[ -f "/etc/fail2ban/filter.d/nginx-no-host.conf" ]]; then
        rm -rf /etc/fail2ban/filter.d/nginx-no-host.conf
    fi
    judge "Fail2ban 卸载"
    timeout "清空屏幕!"
    clear
    source "${idleleo}"
}

mf_stop_disable_fail2ban() {
    systemctl stop fail2ban
    systemctl disable fail2ban
    echo -e "${OK} ${GreenBG} Fail2ban 停止成功 ${Font}"
    timeout "清空屏幕!"
    clear
}

mf_restart_fail2ban() {
    systemctl daemon-reload
    systemctl restart fail2ban
    judge "Fail2ban 重启"
    timeout "清空屏幕!"
    clear
}

mf_display_fail2ban_status() {
    if ! command -v fail2ban-client &> /dev/null; then
        echo -e "${Error} ${RedBG} Fail2ban 未安装, 请先安装 Fail2ban ${Font}"
        return
    fi

    echo -e "${GreenBG} Fail2ban 总体状态: ${Font}"
    fail2ban-client status

    echo -e "\n${Green} 默认启用的 Jail 状态: ${Font}"
    echo "----------------------------------------"
    echo -e "${Green} SSH 封锁情况: ${Font}"
    fail2ban-client status sshd
    if [[ ${tls_mode} == "TLS" || ${reality_add_nginx} == "on" ]]; then
        echo -e "${Green} Fail2ban Nginx 封锁情况: ${Font}"
        fail2ban-client status nginx-badbots
        fail2ban-client status nginx-botsearch
        if [[ ${reality_add_nginx} == "on" ]]; then
            echo -e "${Green} Fail2ban Nginx No Host 封锁情况: ${Font}"
            fail2ban-client status nginx-no-host
        fi
    fi
    mf_main_menu
}

mf_check_for_updates() {
    local latest_version
    local update_choice

    # 直接使用 curl 下载远程版本信息
    latest_version=$(curl -s "$mf_remote_url" | grep 'mf_SCRIPT_VERSION=' | head -n 1 | sed 's/mf_SCRIPT_VERSION="//; s/"//')
    if [ -n "$latest_version" ] && [ "$latest_version" != "$mf_SCRIPT_VERSION" ]; then
        echo -e "${Warning} ${YellowBG} 新版本可用: $latest_version 当前版本: $mf_SCRIPT_VERSION ${Font}"
        echo -e "${Warning} ${YellowBG} 请访问 https://github.com/hello-yunshu/Xray_bash_onekey 查看更新说明 ${Font}"

        echo -e "${GreenBG} 是否要下载并安装新版本 [Y/${Red}N${Font}${GreenBG}]? ${Font}"
        read -r update_choice
        case $update_choice in
            [yY][eE][sS] | [yY])
                echo -e "${Info} ${Green} 正在下载新版本... ${Font}"
                curl -sL "$mf_remote_url" -o "${idleleo_dir}/fail2ban_manager.sh"

                if [ $? -eq 0 ]; then
                    chmod +x "${idleleo_dir}/fail2ban_manager.sh"
                    echo -e "${OK} ${Green} 下载完成，正在重新运行脚本... ${Font}"
                    source "${idleleo}" --set-fail2ban
                else
                    echo -e "\n${Error} ${RedBG} 下载失败，请手动下载并安装新版本 ${Font}"
                fi
                ;;
            *)
                echo -e "${OK} ${Green} 跳过更新 ${Font}"
                ;;
        esac
    else
        echo -e "${OK} ${Green} 当前已经是最新版本: $mf_SCRIPT_VERSION ${Font}"
    fi
}

# 检查更新
mf_check_for_updates

mf_main_menu