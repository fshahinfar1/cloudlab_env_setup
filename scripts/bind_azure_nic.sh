#!/bin/bash
if [ -z "$NET_IFACE" ];then
	echo NET_IFACE not set
	exit 1
fi
sudo modprobe uio_hv_generic
DEV_UUID=$(basename $(readlink /sys/class/net/$NET_IFACE/device))
sudo driverctl -b vmbus set-override $DEV_UUID uio_hv_generic
