#!/bin/bash

# 1. 修改默认管理 IP (192.168.2.1)
sed -i 's/192.168.1.1/192.168.2.1/g' package/base-files/files/bin/config_generate

# 2. 移除所有不再需要的包源码
rm -rf feeds/luci/applications/luci-app-3cat
rm -rf feeds/luci/applications/luci-app-passwall
rm -rf feeds/luci/applications/luci-app-smartdns
rm -rf feeds/luci/applications/luci-app-sqm
rm -rf feeds/luci/applications/luci-app-wol
rm -rf feeds/luci/applications/luci-app-frpc
rm -rf feeds/luci/applications/luci-app-frps
rm -rf feeds/luci/applications/luci-app-samba4
rm -rf feeds/luci/applications/luci-app-aria2
rm -rf feeds/luci/applications/luci-app-wechatpush
rm -rf feeds/luci/applications/luci-app-ttyd
rm -rf feeds/luci/applications/luci-app-watchcat
rm -rf feeds/luci/applications/luci-app-argon-config
rm -rf feeds/luci/themes/luci-theme-aurora
rm -rf feeds/packages/net/open-app-filter
rm -rf feeds/packages/net/ariang

# 3. 彻底清理 PassWall 的依赖组件 (释放空间)
rm -rf feeds/packages/net/{xray-core,v2ray-geodata,sing-box,chinadns-ng,dns2socks,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-libev,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,trojan-plus,tuic-client,v2ray-plugin,xray-plugin,geoview,shadow-tls}

# 4. 更新 Golang 版本 (加入安全性判断)
rm -rf feeds/packages/lang/golang
git clone --depth=1 -b master --single-branch --filter=blob:none --sparse https://github.com/laipeng668/packages temp_pkg
cd temp_pkg && git sparse-checkout set lang/golang
if [ -d "lang/golang" ]; then
    mv -f lang/golang ../feeds/packages/lang/golang
elif [ -d "golang" ]; then
    mv -f golang ../feeds/packages/lang/golang
fi
cd .. && rm -rf temp_pkg

# 5. 安装 OpenClash (直接放入 package 目录)
rm -rf package/luci-app-openclash
git clone --depth=1 https://github.com/vernesong/OpenClash package/luci-app-openclash

# 6. 重新建立 packages feed 的索引
./scripts/feeds install -a -p packages

# 7. 兆能 ZN-M2 硬件魔改适配（1GB 内存 / 无 WiFi / USB3.0 + USB2.0）
#    - 内存：DTS 显式声明 1GB（0x40000000 ~ 0x80000000），避免内核只识别前 512MB
#    - WiFi：把 &wifi 改为 disabled（与 configs 中关闭 ath11k / wpad 配合，彻底无无线）
#    - USB ：显式使能 usb2 / usb3 控制器及其 PHY；USB 5V 供电为硬改直供，无需 GPIO 描述
python3 - <<'PY'
import re
import sys
from pathlib import Path

dts_path = Path("target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq6000-m2.dts")
if not dts_path.exists():
    sys.exit("[ERR] 未找到 ipq6000-m2.dts，上游仓库结构可能已变更")

text = dts_path.read_text(encoding="utf-8")
anchor = 'compatible = "zn,m2", "qcom,ipq6018";'
if anchor not in text:
    sys.exit("[ERR] ipq6000-m2.dts 中未找到 zn,m2 的 compatible，无法定位插入点")

mem_block = """
	/* 1GB 内存硬改：显式声明 1GB，内核不再只使用前 512MB */
	memory@40000000 {
		device_type = "memory";
		reg = <0x0 0x40000000 0x0 0x40000000>;
	};"""

if "memory@40000000" not in text:
    text = text.replace(anchor, anchor + "\n" + mem_block, 1)

# USB：正常情况下上游 ipq6018-common.dtsi 已使能 usb2/usb3 及其 PHY，
# 仅当上游未使能时才在板级 DTS 里补上，避免引用不存在的 label 导致 dtc 报错
common_dtsi = Path("target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq6018-common.dtsi")
usb_ready = False
if common_dtsi.exists():
    ctext = common_dtsi.read_text(encoding="utf-8")
    usb_ready = bool(re.search(r'&usb3\s*\{[^}]*status = "okay"', ctext, re.S))

if not usb_ready and "&usb3" not in text:
    text += """
/* USB3.0 / USB2.0 加装：使能控制器与 PHY（5V 供电为硬改直供，无需 GPIO 描述） */
&usb2 {
	status = "okay";
};

&usb3 {
	status = "okay";
};

&qusb_phy_0 {
	status = "okay";
};

&qusb_phy_1 {
	status = "okay";
};

&ssphy_0 {
	status = "okay";
};
"""

# 无 WiFi 硬件：把无线节点置为 disabled
if "&wifi {" in text:
    text = re.sub(r'(&wifi \{[^}]*?)status = "okay";', r'\1status = "disabled";', text, count=1, flags=re.S)
else:
    print("[WARN] 未找到 &wifi 节点，跳过 WiFi 禁用")

dts_path.write_text(text, encoding="utf-8")
print("[OK] ipq6000-m2.dts 已按 1GB 内存 / 无 WiFi / USB3.0 改写")

# 无 WiFi 设备不再需要板级 WiFi 校准数据包，去掉可省体积
mk_path = Path("target/linux/qualcommax/image/ipq60xx.mk")
if mk_path.exists():
    mk = mk_path.read_text(encoding="utf-8")
    if "DEVICE_PACKAGES := ipq-wifi-zn_m2" in mk:
        mk = mk.replace("DEVICE_PACKAGES := ipq-wifi-zn_m2", "DEVICE_PACKAGES :=")
        mk_path.write_text(mk, encoding="utf-8")
        print("[OK] ipq60xx.mk 已移除 ipq-wifi-zn_m2")
PY

# 8. 校验 DTS 改写结果，避免编译出内存/WiFi 不符的固件
DTS=target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq6000-m2.dts
grep -F -q 'memory@40000000' "$DTS" || { echo "[ERR] DTS 1GB 内存节点写入失败"; exit 1; }
grep -F -A3 '&wifi {' "$DTS" | grep -F -q 'status = "disabled"' || { echo "[ERR] DTS 中 WiFi 未成功禁用"; exit 1; }
echo "--- DTS 关键片段 ---"
grep -F -n 'memory@40000000' -A3 "$DTS"
grep -F -n '&wifi {' -A3 "$DTS"
