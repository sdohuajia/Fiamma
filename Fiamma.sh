#!/bin/bash

# 脚本保存路径
SCRIPT_PATH="$HOME/Fiamma.sh"

# 主菜单函数
function main_menu() {
    while true; do
        clear
        echo "脚本由推特 @ferdie_jhovie，免费开源，请勿相信收费"
        echo "================================================================"
        echo "节点社区 Telegram 群组: https://t.me/niuwuriji"
        echo "节点社区 Telegram 频道: https://t.me/niuwuriji"
        echo "节点社区 Discord 社群: https://discord.gg/GbMV5EcNWF"
        echo "退出脚本，请按键盘ctrl c退出即可"
        echo "请选择要执行的操作:"
        echo "1) 安装和配置 Fiamma 节点"
        echo "2) 创建验证器"
        echo "3) 委托"
        echo "4) 查看日志"
        echo "5) 删除节点"
        echo "6) 退出"
        echo "================================================================"
        read -p "请输入选项 (1, 2, 3, 4, 5, 6): " choice

        case $choice in
            1)
                install_and_configure_fiamma
                ;;
            2)
                create_and_update_validator
                ;;
            3)
                delegate
                ;;
            4)
                journalctl -u fiammad -f -o cat
                ;;
            5)
                delete_node
                ;;
            6)
                echo "退出脚本。"
                exit 0
                ;;
            *)
                echo "无效的选项，请重新选择。"
                sleep 2
                ;;
        esac
    done
}

# 安装和配置 Fiamma 节点函数
function install_and_configure_fiamma() {
    # 更新系统包列表并升级现有包
    sudo apt update && sudo apt upgrade -y

    # 安装必要的软件包
    sudo apt install -y curl git wget htop tmux build-essential jq make lz4 gcc unzip
    sudo apt-get install -y libssl-dev

    # 设置 Go 语言版本
    ver="1.22.3"

    # 检查 Go 是否已安装以及版本
    go_version_check=$(go version 2>/dev/null)

    if [[ $? -eq 0 ]]; then
        installed_version=$(echo $go_version_check | awk '{print $3}' | sed 's/go//')
        echo "已安装 Go 版本: $installed_version"
        
        if [[ "$installed_version" < "$ver" ]]; then
            echo "Go 版本低于 $ver，准备更新..."
            install_go=true
        else
            echo "Go 语言符合要求 (>= $ver)。"
            install_go=false
        fi
    else
        echo "未安装 Go。"
        install_go=true
    fi

    if [[ "$install_go" == true ]]; then
        # 下载并安装 Go 语言
        cd $HOME
        wget "https://golang.org/dl/go$ver.linux-amd64.tar.gz"

        sudo rm -rf /usr/local/go
        sudo tar -C /usr/local -xzf "go$ver.linux-amd64.tar.gz"
        rm "go$ver.linux-amd64.tar.gz"

        # 更新环境变量
        echo "export PATH=\$PATH:/usr/local/go/bin:$HOME/go/bin" >> $HOME/.bash_profile
        source $HOME/.bash_profile

        echo "Go 语言已成功安装或更新到版本 $ver。"
    else
        echo "Go 语言已是最新版本，不需要更新。"
    fi

    # 下载 Fiamma
    cd $HOME
    rm -rf fiamma
    git clone https://github.com/fiamma-chain/fiamma

    # 进入 Fiamma 目录
    cd fiamma

    # 切换到指定版本并安装
    git checkout v0.2.0
    make install

    echo "Fiamma 已成功安装并切换到 v0.2.0 版本。"
    
    # 初始化节点
    echo "请输入验证人名称："
    read -r validname
    
    fiammad init "$validname" --chain-id fiamma-testnet-1
    wget https://raw.githubusercontent.com/fiamma-chain/networks/main/fiamma-testnet-1/genesis.json -O ~/.fiamma/config/genesis.json


    # 配置 peers 和 seeds
    SEEDS="5d6828849a45cf027e035593d8790bc62aca9cef@18.182.20.173:26656,526d13f3ce3e0b56fa3ac26a48f231e559d4d60c@35.73.202.182:26656"
    PEERS="5d6828849a45cf027e035593d8790bc62aca9cef@18.182.20.173:26656,526d13f3ce3e0b56fa3ac26a48f231e559d4d60c@35.73.202.182:26656"
    sed -i -e "/^\[p2p\]/,/^\[/{s/^[[:space:]]*seeds *=.*/seeds = \"$SEEDS\"/}" \
       -e "/^\[p2p\]/,/^\[/{s/^[[:space:]]*persistent_peers *=.*/persistent_peers = \"$PEERS\"/}" $HOME/.fiamma/config/config.toml

    # 设置 minimum-gas-prices
    sed -i -e '/^minimum-gas-prices *=/d' $HOME/.fiamma/config/app.toml
    echo 'minimum-gas-prices = "0.00001ufia"' >> $HOME/.fiamma/config/app.toml

    # 创建 systemd 服务文件
    sudo tee /etc/systemd/system/fiamma.service > /dev/null <<EOF
[Unit]
Description=Fiamma daemon
After=network-online.target

[Service]
User=$USER
ExecStart=$(which cosmovisor) run start --x-crisis-skip-assert-invariants
Restart=always
RestartSec=3
LimitNOFILE=infinity

Environment="DAEMON_NAME=fiammad"
Environment="DAEMON_HOME=${HOME}/.fiamma"
Environment="DAEMON_RESTART_AFTER_UPGRADE=true"
Environment="DAEMON_ALLOW_DOWNLOAD_BINARIES=false"

[Install]
WantedBy=multi-user.target
EOF

    # 启用并启动 Fiamma 服务
    sudo systemctl daemon-reload
    sudo systemctl enable fiammad
    sudo systemctl restart fiammad

    echo "Fiamma 服务已成功创建、启用并启动。运行命令4可查看服务日志："

    # 等待用户按任意键以返回主菜单
    read -p "按任意键返回主菜单..."
}

# 创建和更新验证器函数
function create_and_update_validator() {
    # 检查同步状态
    echo "请确保节点已同步，否则无法创建验证器。"
    echo "拉取最新区块以检查同步状态..."
    cd $HOME
    if fiammad tendermint show-validator; then
        echo "验证器信息已显示。可以继续创建验证器。"

        # 创建钱包或导入钱包
        echo "是否要创建新钱包？（Y/N）"
        read -r create_wallet
        if [[ "$create_wallet" == "Y" || "$create_wallet" == "y" ]]; then
            echo "请输入钱包名称："
            read -r wallet_name
            fiammad keys add "$wallet_name"
        elif [[ "$create_wallet" == "N" || "$create_wallet" == "n" ]]; then
            echo "是否要导入现有钱包？（Y/N）"
            read -r import_wallet
            if [[ "$import_wallet" == "Y" || "$import_wallet" == "y" ]]; then
                echo "请输入钱包名称："
                read -r wallet_name
                echo "请输入助记词："
                read -r mnemonic
                echo "$mnemonic" | fiammad keys add "$wallet_name" --recover
            else
                echo "未创建或导入钱包，继续配置..."
            fi
        else
            echo "无效的输入。"
            exit 1
        fi

# 获取用户输入的 moniker 和 pubkey
    echo "请输入 moniker："
    read -r moniker
    echo "请输入 pubkey："
    read -r pubkey

    # 写入 validator.json
    cat << EOF > ~/.fiamma/config/validator.json
{
    "pubkey": {"@type":"/cosmos.crypto.ed25519.PubKey","key":"$pubkey"},
    "amount": "20000ufia",
    "moniker": "$moniker",
    "identity": "",
    "website": "",
    "security": "",
    "details": "RPCdot.com 🐦",
    "commission-rate": "0.1",
    "commission-max-rate": "0.2",
    "commission-max-change-rate": "0.01",
    "min-self-delegation": "1"
}
EOF

        # 重启服务以应用更改
        sudo systemctl restart fiammad
        echo "验证器信息已更新，Fiamma 服务已重启。"
    else
        echo "节点未同步或出现错误。请先同步节点。"
        exit 1
    fi
    
    # 等待用户按任意键以返回主菜单
    read -p "按任意键返回主菜单..."
}

# 委托函数
function delegate() {
    echo "请输入您的钱包名称（按回车使用默认）："
    read -r wallet_name

    # 设置默认值
    if [ -z "$wallet_name" ]; then
        wallet_name="默认钱包"  # 替换为您希望的默认钱包名称
    fi

    echo "请输入验证器地址 (valoper-address)："
    read -r valoper_address

    echo "正在进行委托操作..."
    fiammad tx staking delegate "$valoper_address" 10000ufia \
    --chain-id fiamma-testnet-1 \
    --from "$wallet_name" \
    --fees 500ufia \
    --node=http://localhost:657

    echo "委托请求已提交。"
    
    # 等待用户按任意键以返回主菜单
    read -p "按任意键返回主菜单..."
}

# 删除节点函数
function delete_node() {
    echo "正在删除 Fiamma 节点..."

    sudo systemctl stop fiammad
    sudo systemctl disable fiammad
    sudo rm -rf /etc/systemd/system/fiammad.service
    sudo systemctl daemon-reload
    sudo rm -f /usr/local/bin/fiammad
    sudo rm -f $(which fiamma)
    sudo rm -rf $HOME/.fiamma $HOME/fiamma
    sed -i "/FIAMMA_/d" $HOME/.bash_profile

    echo "Fiamma 节点已成功删除。"
    
    # 等待用户按任意键以返回主菜单
    read -p "按任意键返回主菜单..."
}

# 执行主菜单
main_menu
