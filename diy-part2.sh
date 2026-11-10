#!/bin/bash
# DIY脚本
# https://github.com/P3TERX/Actions-OpenWrt
# 文件名: diy-part2.sh
# 功能说明: OpenWrt DIY脚本第2部分（更新feeds之后）
# 版权: (c) 2019-2024 P3TERX <https://p3terx.com>
# 基于 MIT 开源协议，详见 /LICENSE

# 补回缺失的 libffi：lkiuyu/immortalwrt 树中没有 package/libs/libffi，
# 而 glib2 / ModemManager 依赖它，否则 glib2-gobject 打包会报
# "missing dependencies for the following libraries: libffi.so.8"。
if [ ! -d package/libs/libffi ]; then
  mkdir -p package/libs
  cp -rf "$GITHUB_WORKSPACE/custom-packages/libffi" package/libs/libffi
fi
# 修改默认IP地址
#sed -i 's/192.168.1.1/192.168.100.1/g' package/base-files/files/bin/config_generate


# 修改默认主题为 argon（路径不存在时跳过，不中断编译）
sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile 2>/dev/null || true

# 启用 IPv4 策略路由（直接写入内核 platform config，绕过 make defconfig 的依赖检查）
# CONFIG_KERNEL_IP_ADVANCED_ROUTER 在 OpenWrt Config.in 中无对应 wrapper，必须用此方式
#for cfg in target/linux/msm89xx/config-*; do
#  grep -q 'CONFIG_IP_ADVANCED_ROUTER' "$cfg" || echo 'CONFIG_IP_ADVANCED_ROUTER=y' >> "$cfg"
#  grep -q 'CONFIG_IP_MULTIPLE_TABLES' "$cfg" || echo 'CONFIG_IP_MULTIPLE_TABLES=y' >> "$cfg"
#done


# 临时添加的插件
# git clone https://github.com/lkiuyu/luci-app-cpu-perf package/luci-app-cpu-perf
# git clone https://github.com/lkiuyu/luci-app-cpu-status package/luci-app-cpu-status
# git clone https://github.com/gSpotx2f/luci-app-cpu-status-mini package/luci-app-cpu-status-mini
# git clone https://github.com/lkiuyu/luci-app-temp-status package/luci-app-temp-status
# git clone https://github.com/lkiuyu/DbusSmsForwardCPlus package/DbusSmsForwardCPlus

# qrzl903：内核直接 USB Host（dr_mode=host，不保留 gadget）
DTS_DIR="target/linux/msm89xx/dts"
if [ -f "$DTS_DIR/msm8916-thwc-ufi001c.dts" ]; then
	cp "$DTS_DIR/msm8916-thwc-ufi001c.dts" "$DTS_DIR/msm8916-thwc-qrzl903.dts"
	cat >> "$DTS_DIR/msm8916-thwc-qrzl903.dts" <<'DTS_EOF'

&usb {
	dr_mode = "host";
	/delete-property/ extcon;
};
DTS_EOF
	python3 - <<'PY' || exit 1
p = 'target/linux/msm89xx/image/msm8916.mk'
s = open(p).read()
old = '''define Device/openstick-qrzl903
  $(Device/openstick-ufi001c)'''
new = '''define Device/openstick-qrzl903
  $(Device/openstick-ufi001c)
  DEVICE_DTS := msm8916-thwc-qrzl903'''
if old not in s:
    raise SystemExit('qrzl903 device block not found')
s = s.replace(old, new, 1)
open(p, 'w').write(s)
PY
else
	echo "WARNING: msm8916-thwc-ufi001c.dts not found, skip host DTS patch"
fi