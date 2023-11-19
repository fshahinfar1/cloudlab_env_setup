# Update kernel arguments
last_line=`tail -n 1 /etc/default/grub`
grub='GRUB_CMDLINE_LINUX_DEFAULT="default_hugepagesz=1G hugepagesz=1G hugepages=8 nosmt"'
if [ last_line != grub ]; then
	echo $grub | sudo tee -a /etc/default/grub
	sudo update-grub
	echo "Require a reboot!"
fi
# Install and do some changes
sudo apt update
sudo apt install linux-tools-`uname -r`
sudo systemctl disable irqbalance.service
sudo cpupower frequency-set -g performance
sudo cpupower idle-set -D 1
# Disable Numa balancing
echo 0 | sudo tee /proc/sys/kernel/numa_balancing
# Disable Kernel Same-Page Merging
echo 0 | sudo tee /sys/kernel/mm/ksm/run
# Disable Intel Turbo Boost
echo 1 | sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo
#
sudo x86_energy_perf_policy performance
# Disable Transparent Huge Pages
echo never | sudo tee /sys/kernel/mm/transparent_hugepage/enabled
# Disable ebpf stat collection if enable
sudo sysctl -w kernel.bpf_stats_enabled=0
