#!/usr/bin/env bash
set -euo pipefail

echo "=== short_cuts 更新脚本 ==="

# ==================== 检测 GitHub SSH 权限 (适配 rmbbiji) ====================
echo "正在检测 rmbbiji (GitHub) SSH 权限..."

# GitHub 认证成功也会返回非 0，不能直接用 ssh 退出码判断。
ssh_output=$(ssh -o BatchMode=yes -o ConnectTimeout=12 -o StrictHostKeyChecking=no -T rmbbiji 2>&1 || true)
if printf "%s\n" "$ssh_output" | grep -qi "successfully authenticated"; then
    echo "✅ SSH 认证成功（GitHub），开始更新仓库..."

    auth_file="short_cuts/web/data/auth.json"
    auth_backup="auth.json"
    if [ -f "$auth_file" ]; then
        if [ -e "$auth_backup" ]; then
            echo "❌ 根目录已存在 $auth_backup，无法备份认证文件。"
            exit 1
        fi
        mv "$auth_file" "$auth_backup"
        echo "✅ 已备份 web 认证文件。"
    fi

    rm -rf short_cuts
    git clone git@rmbbiji:rain-strom/short_cuts.git
    
    if [ ! -d "short_cuts" ]; then
        echo "❌ git clone 失败！"
        exit 1
    fi

    if [ -f "$auth_backup" ]; then
        mkdir -p "$(dirname "$auth_file")"
        mv "$auth_backup" "$auth_file"
        echo "✅ 已恢复 web 认证文件。"
    fi
    echo "✅ 仓库更新完成。"
    
else
    echo "⚠️  无法通过 SSH 访问 rmbbiji，跳过更新，使用本地已有版本。"
fi

# ==================== 后续操作 ====================
echo "正在添加执行权限..."
if [ -f "short_cuts/expand/get_running_python.sh" ]; then
    chmod +x short_cuts/expand/get_running_python.sh
    echo "✅ 执行权限已添加。"
else
    echo "❌ 未找到 short_cuts/expand/get_running_python.sh"
    echo "   请确保仓库已正确存在或网络正常。"
    exit 1
fi

echo "正在安装依赖..."
if [ -f "short_cuts/requirements.txt" ]; then
    pip3 install --break-system-packages -r short_cuts/requirements.txt
    echo "✅ 依赖安装完成。"
else
    echo "⚠️  未找到 short_cuts/requirements.txt，跳过安装。"
fi

# ==================== 重启 short_cuts Web 服务 ====================
server_script="/root/short_cuts/web/server.py"
server_port="4188"

if [ ! -f "$server_script" ]; then
    echo "❌ 未找到 Web 服务文件：$server_script"
    exit 1
fi

get_server_pids() {
    # 只返回 Python 进程，并且命令行必须包含目标 server.py。
    # 即使 bash -c 的命令行里出现 server.py，也会因为进程名不是 Python 而被排除。
    ps -eo pid=,comm=,args= | awk -v target="$server_script" '
        $2 ~ /^python/ && index($0, target) { print $1 }
    '
}

echo "正在停止旧的 short_cuts Web 服务..."
server_pids=$(get_server_pids)
if [ -n "$server_pids" ]; then
    for pid in $server_pids; do
        kill "$pid" 2>/dev/null || true
    done

    # 给服务一个正常退出的机会，避免新服务启动时端口仍被占用。
    sleep 1
    remaining_pids=$(get_server_pids)
    if [ -n "$remaining_pids" ]; then
        echo "⚠️  旧服务未正常退出，正在强制停止..."
        for pid in $remaining_pids; do
            kill -KILL "$pid" 2>/dev/null || true
        done
        sleep 1
        remaining_pids=$(get_server_pids)
        if [ -n "$remaining_pids" ]; then
            echo "❌ 无法停止旧的 Web 服务，请确认当前用户有权限结束这些进程：$remaining_pids"
            exit 1
        fi
    fi
    echo "✅ 旧的 Web 服务已停止。"
else
    echo "ℹ️  未找到正在运行的旧 Web 服务。"
fi

echo "正在启动新的 short_cuts Web 服务..."
nohup python3 "$server_script" --host 0.0.0.0 --port "$server_port" >/dev/null 2>&1 &
server_pid=$!
sleep 1
if ! kill -0 "$server_pid" 2>/dev/null; then
    echo "❌ Web 服务启动失败。"
    exit 1
fi
echo "✅ Web 服务已启动（PID: $server_pid，端口: $server_port）。"

echo "🎉 所有步骤执行完毕！"
