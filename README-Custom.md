- name: Checkout Projects
        uses: actions/checkout@main

      # 强行拉起最新版 Go 环境 (daed 后端刚需)
      - name: Setup Go
        uses: actions/setup-go@v5
        with:
          go-version: '1.22.x'

      # 强行拉起最新版 Node.js (daed 前端刚需)
      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'

      - name: Initialization Environment
        env:
          DEBIAN_FRONTEND: noninteractive
        run: |
          sudo -E apt -yqq purge firefox
          sudo -E apt -yqq update
          sudo -E apt -yqq full-upgrade
          sudo -E apt -yqq autoremove --purge
          sudo -E apt -yqq autoclean
          sudo -E apt -yqq clean
          # 补齐 eBPF 需要的 clang llvm 工具链，并调用在线初始化脚本
          sudo -E apt -yqq install dos2unix libfuse-dev clang llvm
          sudo bash -c 'bash <(curl -sL https://build-scripts.immortalwrt.org/init_build_environment.sh)'
          sudo -E systemctl daemon-reload
          sudo -E timedatectl set-timezone "Asia/Shanghai"

          sudo mkdir -p /mnt/build_wrt
          sudo chown $USER:$USER /mnt/build_wrt
          sudo ln -s /mnt/build_wrt $GITHUB_WORKSPACE/wrt
