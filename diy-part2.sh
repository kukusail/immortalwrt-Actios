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

# 默认开启 USB Host（扩展坞/OTG 场景）：开机后把 ci_hdrc 切到 host
mkdir -p files/etc/init.d files/etc/rc.d
cat > files/etc/init.d/usbhost <<'USBHOST_EOF'
#!/bin/sh /etc/rc.common

START=99
STOP=10

set_host() {
	for f in /sys/class/usb_role/*/role; do
		[ -w "$f" ] || continue
		echo host > "$f" 2>/dev/null && { logger -t usbhost "host mode via $f"; return 0; }
	done
	for f in /sys/devices/platform/*/role /sys/devices/platform/*/*/role /sys/devices/platform/*/*/*/role; do
		[ -r "$f" ] || continue
		case "$(cat "$f" 2>/dev/null)" in
			host|gadget|otg)
				[ -w "$f" ] || continue
				echo host > "$f" 2>/dev/null && { logger -t usbhost "host mode via $f"; return 0; }
				;;
		esac
	done
	mount -t debugfs none /sys/kernel/debug 2>/dev/null
	for f in /sys/kernel/debug/usb/ci_hdrc.*/role; do
		[ -w "$f" ] || continue
		echo host > "$f" 2>/dev/null && { logger -t usbhost "host mode via $f"; return 0; }
	done
	return 1
}

boot() {
	(
		i=0
		while [ $i -lt 20 ]; do
			set_host && exit 0
			sleep 0.5
			i=$((i+1))
		done
		logger -t usbhost "failed to switch to host mode"
	) &
}
USBHOST_EOF
chmod 755 files/etc/init.d/usbhost
ln -sf ../init.d/usbhost files/etc/rc.d/S99usbhost