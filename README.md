# OpenWrt / LibWrt 云编译项目 (兆能 ZN-M2 硬改版：1GB 内存 + USB3.0 / 无 Wi-Fi)

本项目基于 **GitHub Actions** 实现全自动化云端编译，专为 **兆能 ZN-M2 (Qualcomm IPQ60XX)** 深度定制，并针对 **硬件魔改机型** 做了设备树适配：**1GB 内存**、**加装 USB3.0 接口（含 USB 供电）**、**无 Wi-Fi**。项目采用 `laipeng668/openwrt-6.x`（`25.12-nss` 分支）作为底层源码，集成高通 **NSS (Network Subsystem) v11.4** 硬件网络加速引擎与 **Linux 6.12.x** 内核。

---

## ⚠️ 刷机前必读（重要声明）

1. **纯有线固件（无 Wi-Fi 功能）**：
   * 编译阶段已显式关闭整套无线协议栈（`kmod-cfg80211`、`kmod-mac80211`、`kmod-ath11k`、`ath11k-firmware-ipq6018`、各类 `wpad`、`hostapd`、`wpa-supplicant`、`iw`），
     并且编译前会把 `ipq6000-m2.dts` 中的 `&wifi` 节点置为 `disabled`。
   * **固件不包含任何无线网络功能**，适用于弱电箱主路由、纯有线网关或外接独立 AP 的场景，可节省内存与存储空间。
2. **1GB 内存依赖 Bootloader 识别**：
   * 固件侧已在 `ipq6000-m2.dts` 中显式声明 `memory@40000000` 为 **1GB**（`0x40000000 ~ 0x80000000`）。
   * 但上游 `ipq6018.dtsi` 本身没有 `/memory` 节点，实际内存容量通常由 **U-Boot 上报**。若刷机后 `free -m` 仍显示 256MB/512MB，说明 Bootloader 的 DDR 配置未识别 1GB 颗粒，需要更换 1G 版 U-Boot 或修改 bootconfig，固件侧无法绕过。
   * 本固件按“已改 1GB”的机器编译，**不要在未改内存的原机刷入**（会按 1GB 寻址）。
3. **USB3.0 与供电**：
   * `ipq6018-common.dtsi` 已使能 `usb2`/`usb3` 控制器与 PHY，固件同时编入 `kmod-usb3`、`kmod-usb-dwc3`、`kmod-usb-dwc3-qcom`。
   * USB 口 5V 供电按 **硬改直供** 处理；若你的板子是 GPIO 控制 VBUS，需要在设备树中补 `regulator-fixed` + `vbus-supply`（本固件未包含该节点）。
4. **后台默认地址变更**：
   * 默认管理后台 IP 已修改为 **`192.168.2.1`**，刷机后请确保电脑处于 `192.168.2.x` 网段或使用 DHCP。
5. **默认无密码**：
   * 首次登录无需密码，进入系统后请第一时间前往 **系统 -> 管理权** 设置管理员密码。

---

## 📌 核心特性与技术架构

| 特性维度 | 详细配置说明 |
| :--- | :--- |
| **目标机型** | 兆能 ZN-M2 (`qualcommax_ipq60xx_DEVICE_zn_m2`)，硬件魔改版 |
| **源码仓库** | `https://github.com/laipeng668/openwrt-6.x.git` (分支: `25.12-nss`) |
| **内核版本** | Linux `6.12.x` |
| **硬件加速** | 高通 NSS 固件 `11.4` (`CONFIG_NSS_FIRMWARE_VERSION_11_4=y`) |
| **内存** | 设备树显式 1GB（`memory@40000000`，size `0x40000000`），`ZRAM` 压缩（`LZ4`） |
| **USB** | DWC3 USB3.0（SS）+ USB2.0，含 UASP 与外接存储文件系统支持 |
| **无线** | 完全移除：无 ath11k 驱动/固件、无 hostapd/wpad，`&wifi` 节点 disabled |
| **编译器优化** | `-O3 -pipe -march=armv8-a+crypto+crc -mcpu=cortex-a53+crypto+crc -mtune=cortex-a53` |
| **CPU 调速器** | 内核完整集成 6 种调度器 (`performance`、`powersave`、`userspace`、`ondemand`、`conservative`、`schedutil`) |
| **软件包格式** | 支持新版 OpenWrt `.apk` 软件包格式，编译产物自动打包 `IPQ60XX.Packages.tar.gz` |
| **界面与语言** | 默认内置 `Argon` 主题 (`luci-theme-argon`)，包含繁体中文 (`zh_Hant`) 与基础中文语言包 |

---

## 🛠️ 预装软件与精简清单

### 1. 已集成插件与工具
* **网络与代理核心**：
  * **OpenClash** (`luci-app-openclash`)：编译时直接拉取 `vernesong/OpenClash` 最新源码，并独立拉取最新 `Golang` 环境编译，完整集成 `ruby`、`ruby-yaml`、`kmod-tun`、`ip-full`、`ipset`、`iptables-mod-tproxy`、`iptables-mod-extra`、`libcap-bin`、`coreutils-nohup` 等运行依赖。
  * **UPnP** (`luci-app-upnp`)：支持内网设备自动端口映射。
  * **动态域名解析** (`luci-app-ddns`)：支持主流域名服务商的 DDNS 动态解析。
* **系统与硬件管理**：
  * **CPU 调频** (`luci-app-cpufreq`)：支持查看 CPU 实时频率及切换调度策略。
  * **磁盘管理** (`luci-app-diskman`)：可视化分区、格式化及挂载外接存储（配合 USB3.0）。
  * **USB 存储链路**：`kmod-usb-storage`、`kmod-usb-storage-uas`、`kmod-usb-storage-extras`、`usbutils`，
    文件系统 `ext4`、`f2fs`、`vfat`、`exfat`、`ntfs3`，`nls-cp437`、`nls-utf8`。
* **底层维护与性能测试工具**：
  * 终端与编辑器：`tmux`、`nano-full`、`openssh-sftp-server`
  * 监控与压测：`htop`、`btop`、`dmesg`、`coremark`、`autocore`
  * 磁盘与分区工具：`fdisk`、`cfdisk`、`sgdisk`、`tune2fs`、`fstrim`、`hdparm`、`smartmontools-drivedb`

### 2. 已移除插件（源码级彻底清理）
为防止插件冲突、减少固件体积并加快云编译速度，自定义脚本 (`Roc-script.sh`) 已从 `feeds` 源码层彻底删除了以下组件及其依赖：
* **代理类**：PassWall (`luci-app-passwall`) 及其全套核心依赖（`xray-core`、`sing-box`、`hysteria`、`v2ray-geodata`、`chinadns-ng`、`shadowsocks-rust`、`trojan-plus`、`tuic-client` 等）。
* **网络与服务类**：`SmartDNS`、`SQM / sqm-scripts-nss`、`Frpc / Frps`、`WireGuard`、`Samba4`、`Aria2 / Ariang`、`BanIP`、`ACME`、`OAF 应用过滤`、`ARP 绑定`、`网络唤醒 (WOL)`、`KMS (vlmcsd)`、`USB 打印服务`。
* **系统与界面类**：`TTYd 网页终端`、`Watchcat`、`微信推送 (wechatpush)`、`定时重启 (autoreboot)`、`Argon 主题配置插件 (argon-config)`、`Aurora 主题`。
* **无线相关**：`kmod-ath11k` 系列、`ath11k-firmware-ipq6018`、`ipq-wifi-zn_m2` 板级校准数据、`kmod-qca-nss-drv-wifi-meshmgr`。

---

## 🌐 默认登录信息

* **管理后台地址**：`http://192.168.2.1`
* **SSH 连接地址**：`ssh root@192.168.2.1` (端口 `22`)
* **默认用户名**：`root`
* **默认密码**：`无`（直接回车或点击登录即可）

---

## 📂 仓库文件结构说明

```text
.
├── .github/
│   └── workflows/
│       └── IPQ60XX-LibWrt.yml   # GitHub Actions 自动化编译、配置校验与 Release 发布工作流
├── configs/
│   ├── IPQ60XX.config           # 目标平台 (qualcommax/ipq60xx)、ZN-M2 机型、NSS 11.4 及禁用无线配置
│   └── General.config           # GCC 架构优化、ZRAM、CPU 调速器、USB3.0/存储、插件清单
└── scripts/
    └── Roc-script.sh            # 编译前自定义脚本：改默认 IP、清理冗余包源码、更新 Golang、
                                 # 克隆 OpenClash，并改写 DTS（1GB 内存 / 无 WiFi / USB 使能）后自检
```

---

## 🚀 云编译使用教程

### 第一步：准备仓库与权限
1. 点击本仓库右上角的 **Fork** 按钮，将项目复刻到你自己的 GitHub 账号下。
2. 进入你 Fork 后的仓库，点击顶部菜单栏的 **Settings** -> 左侧 **Actions** -> **General**。
3. 向下滚动找到 **Workflow permissions**，勾选 **`Read and write permissions`**，然后点击 **Save** 保存（此步骤为自动发布 Releases 的必要权限）。

### 第二步：启动编译
1. 点击仓库顶部菜单栏的 **Actions**。
2. 在左侧工作流列表中选择 **`IPQ60XX-LibWrt`**。
3. 点击右侧的 **`Run workflow`** 下拉按钮，再次点击绿色的 **`Run workflow`** 即可开始云端编译。
4. 工作流内置 **ccache 与 staging_dir 持久化缓存**，首次编译约需 40~60 分钟，后续命中缓存会大幅缩短。
5. 编译前会自动执行 `Verify Feature Config` 校验：若 `.config` 中仍出现无线组件 `=y`、未选中 `zn_m2`、或缺少 USB3.0 相关包，会直接中止并报错，避免产出错固件。

### 第三步：获取固件
编译成功后，产物自动发布到 **Releases** 页面（Tag 为 `IPQ60XX`），主要包含：

* `*-zn_m2-squashfs-factory.ubi`：**首次刷机**用（U-Boot 恢复模式 / UBI 写入）。
* `*-zn_m2-squashfs-sysupgrade.bin`：**已刷 OpenWrt/LibWrt 后升级**用（LuCI 系统升级）。
* `IPQ60XX.Packages.tar.gz`：本次编译生成的全部 `.apk` 软件包离线归档。
* `IPQ60XX.config` / `IPQ60XX.config.buildinfo` / `IPQ60XX.manifest`：完整配置与软件包清单备份。

---

## 🔧 进阶自定义修改指南

1. **开启定时自动编译**：
   打开 `.github/workflows/IPQ60XX-LibWrt.yml`，取消文件开头 `schedule` 两行的注释（默认北京时间每天 04:00 自动编译）：
   ```yaml
   schedule:
     - cron: 0 20 * * *  # UTC 20:00 = 北京时间次日 04:00
   ```
2. **修改默认管理 IP**：
   编辑 `scripts/Roc-script.sh` 第 1 步，将 `192.168.2.1` 替换为你需要的网段：
   ```bash
   sed -i 's/192.168.1.1/192.168.2.1/g' package/base-files/files/bin/config_generate
   ```
3. **调整内存声明（1GB ↔ 自动识别）**：
   `scripts/Roc-script.sh` 第 7 步会向 `ipq6000-m2.dts` 插入：
   ```dts
   memory@40000000 {
       device_type = "memory";
       reg = <0x0 0x40000000 0x0 0x40000000>;   /* 1GB */
   };
   ```
   * 改成 `0x0 0x20000000` → 512MB，`0x0 0x10000000` → 256MB。
   * 若要交回 Bootloader 决定容量，把 `mem_block` 整段删掉即可（原厂 U-Boot 会自行上报内存）。
4. **恢复 Wi-Fi 无线功能**（需硬件仍有无线模块）：
   * `configs/IPQ60XX.config`：取消/删除禁用的 `kmod-cfg80211`、`kmod-mac80211`、`kmod-ath11k*`、`ath11k-firmware-ipq6018`、`kmod-qca-nss-drv-wifi-meshmgr`、各类 `wpad`、`hostapd*`、`wpa-supplicant`、`iw` 行。
   * `scripts/Roc-script.sh`：注释掉第 7 步中把 `&wifi` 置为 `disabled` 的正则替换，并把第 8 步对应的 `grep` 校验一起删除（否则会中止编译）。
   * 还需要恢复 `ipq60xx.mk` 中的 `DEVICE_PACKAGES := ipq-wifi-zn_m2`（脚本第 7 步会把它清空）。
5. **添加额外插件**：
   * 在 `configs/General.config` 末尾追加 `CONFIG_PACKAGE_luci-app-xxx=y`。
   * 注意检查 `scripts/Roc-script.sh` 第 2~3 步，确保目标插件没有在 `rm -rf` 清理列表中被删除源码。

---

## 📋 刷机简要指引（兆能 ZN-M2 硬改版）

1. **首次刷入（从原厂或其他固件刷入）**：
   * 断电按住 Reset 键不放并通电，约 8~10 秒后松开进入 U-Boot 恢复模式。
   * 电脑网线连接 LAN 口，网卡设静态 IP（如 `192.168.1.2`），浏览器访问 `192.168.1.1`，上传 `*-squashfs-factory.ubi` 完成刷机。
   * 刷完后网卡改回 DHCP，通过 **`http://192.168.2.1`** 访问新系统。
2. **同源固件升级**：
   * 登录 `http://192.168.2.1`，进入 **系统 -> 备份/升级**，上传 `*-squashfs-sysupgrade.bin` 执行升级。
3. **OpenClash 内核补充**：
   * 固件内置 OpenClash 主程序与依赖，首次使用需在 **服务 -> OpenClash -> 插件设置 -> 版本更新** 下载或上传 `Meta (mihomo)` 内核（架构选 `linux-arm64`）。

---

## ✅ 刷机后验证清单

```bash
free -m                      # total 应接近 1000MB（1GB 内存生效）
ls /sys/class/ieee80211      # 应为空（无 WiFi）
ps | grep -E 'hostapd|wpa_supplicant'   # 应无进程
dmesg | grep -i dwc3         # 应有 USB3.0 (xhci/dwc3) 初始化日志
lsusb                        # 插上 U 盘/硬盘后应能看到设备
cat /sys/bus/usb/devices/*/speed        # 5000 表示跑在 USB3.0
```

* 若 `free -m` 只有 256/512MB：Bootloader 未识别 1GB 内存，需换 1G 版 U-Boot。
* 若 USB3 设备只协商到 480：多为线材/接口接触或供电问题，先确认 5V 供电与走线。

---

## 🙏 鸣谢与开源许可

* 底层源码：[laipeng668/openwrt-6.x](https://github.com/laipeng668/openwrt-6.x)
* 代理插件：[vernesong/OpenClash](https://github.com/vernesong/OpenClash)
* 编译依赖脚本：[ophub](https://ophub.org)
* Release 发布动作：[ncipollo/release-action](https://github.com/ncipollo/release-action)
