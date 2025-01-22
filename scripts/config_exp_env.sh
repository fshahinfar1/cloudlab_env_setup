#!/bin/bash
set -e
# set -x

RUN=1
UDP_QUEUE=4
SERVER_IP="192.168.1.1/24"
CPU=$(lscpu | grep Vendor | cut -d : -f 2 | tr -d ' ')

turn_off_busypolling() {
    echo 0 | sudo tee "/sys/class/net/$NET_IFACE/napi_defer_hard_irqs"
    echo 0 | sudo tee "/sys/class/net/$NET_IFACE/gro_flush_timeout"
}

busypoll_budget=200000
turn_on_busypolling() {
    echo 2 | sudo tee "/sys/class/net/$NET_IFACE/napi_defer_hard_irqs"
    echo "$busypoll_budget" | sudo tee "/sys/class/net/$NET_IFACE/gro_flush_timeout"
}

function on_signal {
	echo "On signal"
	RUN=0
	turn_off_busypolling
	sudo cpupower frequency-set -g schedutil &> /dev/null
	remove_all_flow_rules $NET_IFACE
	sudo cpupower idle-set -D 4
	echo 1 | sudo tee /proc/sys/kernel/numa_balancing
	echo 1 | sudo tee /sys/kernel/mm/ksm/run
	echo madvise | sudo tee /sys/kernel/mm/transparent_hugepage/enabled
	echo on | sudo tee /sys/devices/system/cpu/smt/control
    if [ "$CPU" = "GenuineIntel" ]; then
        sudo x86_energy_perf_policy normal > /dev/null
        echo 0 | sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo
    fi
	# sudo sysctl -w kernel.bpf_stats_enabled=1
	sudo systemctl start irqbalance
	sudo ethtool -K $NET_IFACE rx-checksumming on tso on gso on gro on lro off
	echo "Done!"
}

function is_iface_down {
	DEV=$1
	RET=0
	ip link | grep $NET_IFACE | grep DOWN &> /dev/null
	RET=$?
	if [ $RET -eq 0 ]; then
		echo "true"
	else
		echo "false"
	fi
}

function prepare_iface {
	DEV=$1
	IP=$2
	sudo ip link set dev $DEV up
	sudo ip addr add $IP dev $DEV
}

function remove_all_flow_rules {
	DEV=$1
	for x in $(sudo ethtool -u $DEV | grep Filter | cut -d ' ' -f 2); do
		sudo ethtool -U $DEV delete $x
	done

}

function add_flow_rules {
	DEV=$1
	# Check ntuple is enable
	can_filter=$(sudo ethtool -k "$DEV" | grep 'ntuple-filters' | cut -d ':' -f 2 | tr -d ' ')
	if [ "$can_filter" != 'on' ]; then
		echo "Warning: the ntuple-filters is not enabled on the selected NIC."
        sudo ethtool -K "$DEV" ntuple-filters on
	fi

	sudo ethtool -U "$DEV" flow-type udp4 action "$UDP_QUEUE"
}

function report_nic_numa_node {
	DEV=$1
	x=$(cat "/sys/class/net/$DEV/device/numa_node")
	echo "NIC ($DEV) is connected to NUMA $x"
}

function main {
	TMP=$(is_iface_down "$NET_IFACE")
	if [ "$TMP" = "true" ]; then
		prepare_iface "$NET_IFACE" "$SERVER_IP"
	fi
	report_nic_numa_node "$NET_IFACE"
	remove_all_flow_rules "$NET_IFACE"
	add_flow_rules "$NET_IFACE"
	sudo cpupower frequency-set -g performance > /dev/null
	sudo cpupower idle-set -D 1 > /dev/null
	echo 0 | sudo tee /proc/sys/kernel/numa_balancing
	echo 0 | sudo tee /sys/kernel/mm/ksm/run
	echo never | sudo tee /sys/kernel/mm/transparent_hugepage/enabled
	echo off | sudo tee /sys/devices/system/cpu/smt/control
	if [ "$CPU" = "GenuineIntel" ]; then
		sudo x86_energy_perf_policy performance > /dev/null
		echo 1 | sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo
	fi
	sudo sysctl -w kernel.bpf_stats_enabled=0
	sudo systemctl stop irqbalance
	sudo ethtool -K "$NET_IFACE" rx-checksumming off tso off gso off gro off lro off
	turn_on_busypolling
	trap "on_signal" SIGINT SIGHUP
	echo "hit Ctrl-C to terminate"
	while [ $RUN -eq 1 ] ; do
		sleep 3
	done
}

if [ "x$NET_IFACE" = "x" ]; then
	echo "NET_IFACE is not set"
	exit 1
fi

main
