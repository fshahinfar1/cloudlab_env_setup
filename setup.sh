#! /bin/bash

# This script configures the current machine based on the selected mode
# (see usage)
# Expecting Cloudlab xl170 (ubuntu-20.04/ubuntu-22.04)

# Global vars
NAS="/proj/progstack-PG0/farbod/"

function check_pre_conditions {
	ls $NAS &> /dev/null
	ret=$?
	if [ ! $ret -eq 0 ]; then
		echo "Failed to find the directory on the NAS ($NAS)"
		exit 1
	fi

	if [ ! -f $HOME/.ssh/id_dummy ]; then
		echo "The dummy key is not imported yet!"
		exit 1
	fi
}

function install_clang {
	# Install clang
	CLANG_VERSION=15
	cd $HOME
	wget https://apt.llvm.org/llvm.sh
	chmod +x llvm.sh
	sudo ./llvm.sh $CLANG_VERSION
	# Both install clang-15 and clang-16
	sudo ./llvm.sh 18

	# Configure the clang
	sudo update-alternatives --install /usr/bin/clang clang /usr/bin/clang-$CLANG_VERSION 100
	sudo update-alternatives --install /usr/bin/llc llc /usr/bin/llc-$CLANG_VERSION 100
	sudo update-alternatives --install /usr/bin/llvm-strip llvm-strip /usr/bin/llvm-strip-$CLANG_VERSION 100
}

function install_gcc11 {
	# Install g++-11
	sudo add-apt-repository -y ppa:ubuntu-toolchain-r/test
	sudo apt install -y gcc-11 g++-11
	sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-11 100
	sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-11 100
}

function get_repos {
	# "git@github.com:fshahinfar1/auto_generated_bpf.git" \
	# "git@github.com:fshahinfar1/auto_bpf_offload_case_study.git" \
	list_repos=( "git@github.com:fshahinfar1/kashk.git" \
		"git@github.com:fshahinfar1/auto_kern_offload_bench.git" \
		"git@github.com:fshahinfar1/bpf_prefetch.git" \
	)
	for repo_addr in ${list_repos[@]}; do
		cd $HOME
		git clone $repo_addr --config core.sshCommand='ssh -i ~/.ssh/id_dummy'
	done
}

function get_wrk_gen {
	sudo apt install -y libssl-dev
	# TCP Traffic Gen
	cd $HOME
	git clone https://github.com/fshahinfar1/tcp_traffic_gen
	cd tcp_traffic_gen
	make
	cp wrk $HOME/tcpgen
	cd $HOME

	# UDP Traffic Gen
	cd $HOME
	git clone https://github.com/fshahinfar1/udp_traffic_gen/
	cd udp_traffic_gen/src
	make
}

function bring_gen_scripts {
	# Place some scripts which help run experiments
	cd $HOME
	files=( gen.sh ping_pong.lua twt_c.lua )

	for f in ${files[@]}; do
		cp $NAS/$f ./
	done
}

function configure_dev_env {
	# Configure tmux
	cat > $HOME/.tmux.conf <<EOF
unbind-key C-b
set -g prefix C-Space
set -g escape-time 0
bind r source-file ~/.tmux.conf \; display "Configuration executed"
set -g default-terminal "xterm-256color"
set -g mouse on
set -ga terminal-overrides ',*256color*:smcup@:rmcup@'
set -g terminal-overrides 'xterm-256color:smcup@:rmcup@'
set-window-option -g mode-keys vi

bind-key k select-pane -U
bind-key j select-pane -D
bind-key h select-pane -L
bind-key l select-pane -R
EOF

	# Configure git
	git config --global core.editor vim
	git config --global user.name "Farbod Shahinfar"
	git config --global user.email "fshahinfar1@gmail.com"
	git config --global init.defaultBranch "master"

	# Install general packages we might use
	sudo apt update
	sudo apt install -y htop build-essential exuberant-ctags mosh cmake \
		silversearcher-ag pkg-config libelf-dev libdw-dev gcc-multilib \
				python3 python3-pip python3-venv libpcap-dev libpci-dev \
				libnuma-dev flex bison libslang2-dev libcap-dev libssl-dev \
				libncurses-dev libslang2-dev jq

	# Configure vim
	cd $HOME
	git clone https://github.com/fshahinfar1/dotvim
	cd ./dotvim
	./install.sh
	cd $HOME

	# Configure ssh session
	eval $(ssh-agent)
	ssh-add $HOME/.ssh/id_dummy
	echo 'eval $(ssh-agent)' | tee -a $HOME/.bashrc
	echo 'ssh-add $HOME/.ssh/id_dummy' | tee -a $HOME/.bashrc

	# Configure NET_IFACE
	EXPERIMENT_IP_RANGE="192.168"
	tmp_ifaces_info=( $(ip -json addr | jq '.[] | [.ifname, .ifindex, .addr_info[].local] | join("|")' | grep $EXPERIMENT_IP_RANGE) )
	if [ ${#tmp_ifaces_info[@]} -eq 1 ]; then
		iface_name=$(echo ${tmp_ifaces_info[0]} | tr -d '"' | cut -f 1 -d '|')
		# iface_index=$(echo ${tmp_ifaces_info[0]} | tr -d '"' | cut -f 2 -d '|')
		echo "export NET_IFACE=\"$iface_name\""
		# echo "export NET_IFINDEX=$iface_index"
		# echo "export NET_PCI_ADDR=$iface_index"
	else
		echo Multiple interfaces with IP in experiment range found!
	fi
}

function install_go {
	cd $HOME
	mkdir go_tmp_dir/
	cd go_tmp_dir/
	wget https://go.dev/dl/go1.22.3.linux-amd64.tar.gz
	sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf go1.22.3.linux-amd64.tar.gz
	echo "export PATH=$PATH:/usr/local/go/bin" | tee -a $HOME/.bashrc
	source $HOME/.bashrc
}

function setup_nginx {
	# Setup NGINX
	sudo apt install -y nginx
	# sudo cp /proj/progstack-PG0/farbod/nginx.conf /etc/nginx/nginx.conf
	sudo systemctl stop nginx
	sudo systemctl disable nginx
}

function _install_custom_kernel {
	# Install new kernel
	# cd $NAS/kernel/binary/
	# cd $NAS/kernel/binary/
	# sudo dpkg -i linux-headers.deb \
	# 	linux-image.deb \
	# 	linux-libc-dev.deb
	echo "No new kernel will be installed"
}

function _install_custom_kernel_from_script {
	wget https://raw.githubusercontent.com/pimlie/ubuntu-mainline-kernel.sh/master/ubuntu-mainline-kernel.sh
	sudo bash ./ubuntu-mainline-kernel.sh -i 6.1.0
	sudo update-grub
}

function install_new_kernel {
	echo Installing new kernel ...
	_install_custom_kernel
	# _install_custom_kernel_from_script
}

function disable_irqbalance {
	sudo systemctl disable irqbalance.service
	sudo systemctl stop irqbalance.service
}

function install_cpupower {
	# Install cpupower tool on the server
	# cd $NAS/kernel/linux-6.1.4/tools/power/cpupower
	# sudo make install
	# echo "/usr/lib64" | sudo tee /etc/ld.so.conf.d/cpupower.conf
	# sudo ldconfig
	echo "Install cpupower tool after installing a new kernel ..."
}

function install_x86_energy {
	# cd $NAS/kernel/linux-6.1.4/tools/power/x86/x86_energy_perf_policy
	# sudo make clean
	# sudo make
	# sudo make install
	echo "Install x86_energy_perf tool after installing a new kernel ..."
}

function configure_for_exp {
	disable_irqbalance
	# Configure CPU scheduler policy
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
	# Flow rules
	if [ -z "$NET_IFACE" ]; then
		echo select your NIC
		echo "show ip addr ? [Y/n]"
		read cmd
		case $cmd in
			y|Y)
				ip a
				;;
			*)
				;;
		esac
		echo Name of the device is:
		read NET_IFACE
		if [ ! -z "$NET_IFACE" ]; then
			echo using $NET_IFACE for flow-steering
		else
			echo "warning: NET_IFACE is empty!"
			return 1
		fi
	fi
	sudo ethtool -U $NET_IFACE flow-type tcp4 dst-port 8080 action 2
	sudo ethtool -U $NET_IFACE flow-type udp4 dst-port 8080 action 2
	for i in $(seq 3); do
		echo $i
	done
	echo The flow rules are set as below. Make sure nothing is wrong.
	sudo ethtool -u $NET_IFACE
}

function install_dpdk_burst_replay {
	# DEPS
	sudo apt update
	sudo apt install -y meson ninja-build libpcap-dev libcap-dev libelf-dev \
		python3 python3-pip python3-pyelftools pkg-config \
		libnuma-dev libpcap-dev libcap-dev cmake
	pip install scapy
	# GRUB
	grub='GRUB_CMDLINE_LINUX_DEFAULT="default_hugepagesz=1G hugepagesz=1G hugepages=8 preempt=none"'
	echo $grub | sudo tee -a /etc/default/grub
	sudo update-grub
	# INSTALL DIR
	cd $HOME
	mkdir -p $HOME/gen/
	# OFED
	sudo lshw | grep mlx5 &> /dev/null
	has_mlx5=$?
	if [ $has_mlx5 -eq 0 ]; then
		echo This machine uses MLX5 driver
		source /etc/lsb-release
		if [ -z "$DISTRIB_ID" -o "$DISTRIB_ID" != "Ubuntu" ]; then
			echo "Failed to install the Mellanox OFED. Expected Ubuntu distribution."
			return 1
		fi
		ubuntu_release=$DISTRIB_RELEASE
		tar_name="MLNX_OFED_LINUX-23.10-1.1.9.0-ubuntu$ubuntu_release-x86_64"
		cd $HOME/gen/
		wget "https://content.mellanox.com/ofed/MLNX_OFED-23.10-1.1.9.0/MLNX_OFED_LINUX-23.10-1.1.9.0-ubuntu$ubuntu_release-x86_64.tgz"
		tar -xf "./$tar_name.tgz"
		cd $tar_name/
		yes | sudo ./mlnxofedinstall --dkms --dpdk
		echo You will need to reboot
	fi
	# DPDK
	cd $HOME/gen/
	wget https://fast.dpdk.org/rel/dpdk-23.11.tar.xz
	tar -xf ./dpdk-23.11.tar.xz
	cd dpdk-23.11/
	meson build/
	cd build/
	ninja
	sudo meson install
	# tool
	cd $HOME/gen/
	sudo apt install libyaml-dev libcsv-dev cmake
	git clone https://github.com/fshahinfar1/dpdk-burst-replay.git
	cd dpdk-burst-replay
	git checkout multicore-txrate
	git submodule update --init
	mkdir build/
	cd build/
	cmake ../
	make
}

function install_libbpf {
	cd $HOME
	mkdir libbpf
	cd $HOME/libbpf
	_VERSION="1.0.0"
	VERSION="v$_VERSION"
	wget https://github.com/libbpf/libbpf/archive/refs/tags/$VERSION.tar.gz
	tar -xf $VERSION.tar.gz
	cd libbpf-$_VERSION/src/
	make
	sudo make install
	echo "/usr/lib64/" | sudo tee /etc/ld.so.conf.d/libbpf.conf
	sudo ldconfig
}

function install_bpftool {
	# Install bpftool
	# TODO: this is failing (test it)
	# cd $NAS/kernel/linux-6.1.4/tools/bpf/bpftool/
	# sudo make clean
	# sudo make
	# sudo make install
	echo Install bpftool after installing kernel
}

function install_perf {
	# Install perf
	# path=$NAS/kernel/linux-6.1.4/tools/perf
	# cd $path/
	# sudo make clean
	# sudo make
	# sudo ln -s $path/perf /usr/bin/perf
	echo Install perf after installing kernel
}

function do_gen {
	configure_dev_env
	get_wrk_gen
	bring_gen_scripts
	install_dpdk_burst_replay
	install_cpupower
	install_x86_energy
	# configure_for_exp
}

function do_dut {
	configure_dev_env

	pip install flask
	install_clang
	# install_gcc11
	install_bpftool
	install_libbpf

	install_new_kernel

	# Configure HUGEPAGES
	grub='GRUB_CMDLINE_LINUX_DEFAULT="preempt=none default_hugepagesz=1G hugepagesz=1G hugepages=8 nosmt"'
	echo $grub | sudo tee -a /etc/default/grub
	sudo update-grub

	get_repos
	# setup_nginx

	install_perf
	install_cpupower
	install_x86_energy
	sudo apt install linux-tools-`uname -r`

	# configure_for_exp
}

function do_dut2 {
	set -e

	DISK="$HOME/disk"
	# configure the disk
	if [! -d $DISK ]; then
		mkdir $DISK
		sudo mkfs.ext4 /dev/sda4
	fi
	sudo mount /dev/sda4 $DISK
	sudo chown $USER $DISK

	configure_dev_env
	install_clang

	cd $DISK
	git clone "git@github.com:fshahinfar1/auto_kern_offload_bench.git"
	# TODO: make the source code

	cd $DISK
	git clone --depth 1 https://github.com/torvalds/linux.git --branch  v6.8-rc7 --single-branch
	cd linux/
	git am ../auto_kern_offload_bench/kernel/*.patch
	mkdir build/
	cd build/
	make -C ../ O=$(pwd) defconfig
	cp "$HOME/scripts/linux_config_6.8.7" .config
	yes '' | make oldconfig
	CORES=$(awk '/^processor/{x=$3};END{print x}' < /proc/cpuinfo)
	make -j $((CORES + 2))
}

function usage {
	echo "setup.sh <mode>"
	echo "MODES:"
	echo "  * gen: configure the workload generator machine"
	echo "  * dut: configure the machine under test"
	echo "  * repo: only fetch the repos"
	echo "  * kern: only install the custom kernel"
	echo "  * exp : configure machine for the experiment"
	echo "  * clang: install clang"
}

check_pre_conditions

if [ $# -lt 1 ] ; then
	usage
	exit 0
fi

case $1 in
	"dev_env")
		configure_dev_env ;;
	"gen")
		do_gen ;;
	"dut")
		do_dut ;;
	"dut2")
		do_dut2 ;;
	"repo")
		get_repos ;;
	"kern")
		install_new_kernel ;;
	"exp")
		configure_for_exp ;;
	"clang")
		install_clang ;;
	"gcc11")
		install_gcc11 ;;
	"nginx")
		setup_nginx ;;
	"dpdk_burst_reply")
		install_dpdk_burst_replay ;;
	*)
		echo "Error: unknown mode was selected"
		usage
		exit 1
		;;
esac
exit 0
