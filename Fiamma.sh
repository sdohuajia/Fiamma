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
        echo "4) 退出"
        echo "================================================================"
        read -p "请输入选项 (1, 2, 3, 4): " choice

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

    # 安装 libssl-dev 库
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

    # 初始化 Fiamma
    echo "请输入验证人名称："
    read -r validname
    fiamma init "$validname" --chain-id fiamma-testnet-1

    # 配置 client.toml
    sed -i -e "s|^node *=.*|node = \"tcp://localhost:26657\"|" $HOME/.fiamma/config/client.toml
    sed -i -e "s|^keyring-backend *=.*|keyring-backend = \"os\"|" $HOME/.fiamma/config/client.toml
    sed -i -e "s|^chain-id *=.*|chain-id = \"fiamma-testnet-1\"|" $HOME/.fiamma/config/client.toml

    # 创建 systemd 服务文件
    sudo tee /etc/systemd/system/fiammad.service > /dev/null <<EOF
[Unit]
Description=Fiamma node
After=network-online.target
[Service]
User=$USER
WorkingDirectory=$HOME/.fiamma
ExecStart=$(which fiammad) start --home $HOME/.fiamma
Restart=on-failure
RestartSec=5
LimitNOFILE=65535
[Install]
WantedBy=multi-user.target
EOF

    # 启用并启动 Fiamma 服务
    sudo systemctl daemon-reload
    sudo systemctl enable fiammad
    sudo systemctl restart fiammad

    # 显示服务日志
    echo "Fiamma 服务已成功创建、启用并启动。服务日志如下："
    sudo journalctl -u fiammad -f
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

        # 获取用户输入的信息
        echo "请输入公钥："
        read -r pubkey
        echo "请输入验证人名称（Moniker）："
        read -r moniker
        echo "请输入网站（可选）："
        read -r website

        # 更新验证器信息
        echo "正在更新验证器信息..."
        cat << EOF > ~/.fiamma/config/validator.json
{
    "pubkey": {"@type":"/cosmos.crypto.ed25519.PubKey","key":"$pubkey"},
    "amount": "20000ufia",
    "moniker": "$moniker",
    "identity": "",
    "website": "$website",
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
}

# 委托函数
function delegate() {
    echo "请输入您的钱包名称："
    read -r wallet_name

    echo "请输入验证器地址 (valoper-address)："
    read -r valoper_address

    echo "正在进行委托操作..."
    fiammad tx staking delegate "$valoper_address" 10000ufia \
    --chain-id fiamma-testnet-1 \
    --from "$wallet_name" \
    --fees 500ufia \
    --node=http://localhost:657

    echo "委托请求已提交。"
}

# 执行主菜单
main_menu
