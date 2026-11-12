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

# 默认把第二个 RTL8152B（eth1）也加入 br-lan
mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/99-lan-eth1 <<'UCI_EOF'
#!/bin/sh
# 双网卡 RTL8152B：eth0 默认已在 br-lan，这里补 eth1
uci -q del_list network.@device[0].ports='eth1'
uci add_list network.@device[0].ports='eth1'
uci commit network
exit 0
UCI_EOF
chmod 755 files/etc/uci-defaults/99-lan-eth1

# 关闭 modem 接口的开机自动拉起（由 modem-retry 在 ModemManager 就绪后 ifup）
if [ -d feeds/openstick ]; then
	TWEAK=$(find feeds/openstick -path '*openstick-tweaks/files/openstick_tweak' | head -n1)
	[ -n "$TWEAK" ] && sed -i "s/network.modem.auto='1'/network.modem.auto='0'/" "$TWEAK"
fi

# ModemManager 就绪后再拉起 modem 接口，避免开机 set allowed modes 竞争
mkdir -p files/etc/init.d files/etc/rc.d
cat > files/etc/init.d/modem-retry <<'MODEM_EOF'
#!/bin/sh /etc/rc.common

START=99
STOP=10

boot() {
	[ -x /usr/bin/mmcli ] || exit 0
	[ -n "$(uci -q get network.modem)" ] || exit 0
	(
		logger -t modem-retry "waiting for modem"
		i=0
		while [ $i -lt 90 ]; do
			mmcli -L 2>/dev/null | grep -q 'Modem/' && break
			sleep 2
			i=$((i+1))
		done
		sleep 15
		tries=0
		while [ $tries -lt 3 ]; do
			if ifstatus modem 2>/dev/null | grep -q '"up": true'; then
				logger -t modem-retry "modem up"
				exit 0
			fi
			logger -t modem-retry "ifup modem (try $((tries+1)))"
			ifdown modem 2>/dev/null
			sleep 2
			ifup modem
			sleep 30
			tries=$((tries+1))
		done
		if ifstatus modem 2>/dev/null | grep -q '"up": true'; then
			logger -t modem-retry "modem up"
		else
			logger -t modem-retry "modem still down"
		fi
	) &
}
MODEM_EOF
chmod 755 files/etc/init.d/modem-retry
ln -sf ../init.d/modem-retry files/etc/rc.d/S99zz-modem-retry

# br-lan 开启 STP，双网口都接线时防止二层环路
cat > files/etc/uci-defaults/99-lan-stp <<'STP_EOF'
#!/bin/sh
uci -q set network.@device[0].stp='1'
uci commit network
exit 0
STP_EOF
chmod 755 files/etc/uci-defaults/99-lan-stp

# 只保留 S99zz-modem-retry，清掉 rc.common 自动生成的重复启动项
cat > files/etc/uci-defaults/zz-modem-order <<'ORDER_EOF'
#!/bin/sh
rm -f /etc/rc.d/S99modem-retry /etc/rc.d/K10modem-retry
exit 0
ORDER_EOF
chmod 755 files/etc/uci-defaults/zz-modem-order

# ufi003：内核直接 USB Host（与 qrzl903 共用 ufi001c 板级 DTS）
if [ -f "$DTS_DIR/msm8916-thwc-ufi001c.dts" ]; then
	cp "$DTS_DIR/msm8916-thwc-ufi001c.dts" "$DTS_DIR/msm8916-thwc-ufi003.dts"
	cat >> "$DTS_DIR/msm8916-thwc-ufi003.dts" <<'DTS_EOF'

&usb {
	dr_mode = "host";
	/delete-property/ extcon;
};
DTS_EOF
	python3 - <<'PY' || exit 1
p = 'target/linux/msm89xx/image/msm8916.mk'
s = open(p).read()
old = '''define Device/openstick-ufi003
  $(Device/openstick-ufi001c)'''
new = '''define Device/openstick-ufi003
  $(Device/openstick-ufi001c)
  DEVICE_DTS := msm8916-thwc-ufi003'''
if old not in s:
    raise SystemExit('ufi003 device block not found')
s = s.replace(old, new, 1)
open(p, 'w').write(s)
PY
fi