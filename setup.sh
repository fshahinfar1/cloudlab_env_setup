#! /bin/bash

# This script configures the current machine based on the selected mode
# (see usage)
# Expecting Cloudlab ubuntu-20.04

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
	list_repos=( "git@github.com:fshahinfar1/kashk.git" \
		"git@github.com:fshahinfar1/auto_generated_bpf.git" \
		"git@github.com:fshahinfar1/auto_bpf_offload_case_study.git" \
		"git@github.com:fshahinfar1/auto_kern_offload_bench.git" \
	)

	for repo_addr in ${list_repos[@]}; do
		cd $HOME
		git clone $repo_addr --config core.sshCommand='ssh -i ~/.ssh/id_dummy'
	done

	c
}

function get_wrk_gen {
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
EOF

	# Configure git
	git config --global core.editor vim
	git config --global user.name "Farbod Shahinfar"
	git config --global user.email "fshahinfar1@gmail.com"
	git config --global init.defaultBranch "master"

	sudo apt update
	sudo apt install -y htop build-essential exuberant-ctags mosh cmake silversearcher-ag

	# Configure vim
	cd $HOME
	git clone https://github.com/fshahinfar1/dotvim
	cd ./dotvim
	./install.sh
	cd $HOME
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
	cd $NAS/kernel/binary/
	sudo dpkg -i linux-headers-6.1.4_6.1.4-6_amd64.deb \
		linux-image-6.1.4_6.1.4-6_amd64.deb \
		linux-libc-dev_6.1.4-6_amd64.deb

	# Install bpftool
	# TODO: this is failing (test it)
	cd $NAS/kernel/linux-6.1.4/tools/bpf/bpftool/
	sudo make clean
	sudo make
	sudo make install

	# Install perf
	sudo ln -s $NAS/kernel/linux-6.1.4/tools/perf/perf /usr/bin/perf
}

function install_new_kernel {
	# _install_custom_kernel
	wget https://raw.githubusercontent.com/pimlie/ubuntu-mainline-kernel.sh/master/ubuntu-mainline-kernel.sh
	sudo bash ./ubuntu-mainline-kernel.sh -i 6.1.0
	sudo update-grub
}

function disable_irqbalance {
	sudo systemctl disable irqbalance.service
	sudo systemctl stop irqbalance.service
}

function install_cpupower {
	# Install cpupower tool on the server
	cd $NAS/kernel/linux-6.1.4/tools/power/cpupower
	sudo make install
	echo "/usr/lib64" | sudo tee /etc/ld.so.conf.d/cpupower.conf
	sudo ldconfig
}

function install_x86_energy {
	cd $NAS/kernel/linux-6.1.4/tools/power/x86/x86_energy_perf_policy
	sudo make clean
	sudo make
	sudo make install
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
		esac
		echo Name of the device is:
		read NET_IFACE
		echo using $NET_IFACE for flow-steering
	fi
	sudo ethtool -U $NET_IFACE flow-type tcp4 dst-port 8080 action 2
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

function do_gen {
	configure_dev_env
	get_wrk_gen
	bring_gen_scripts
	install_cpupower
	install_x86_energy
	configure_for_exp
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

function do_dut {
	configure_dev_env
	install_new_kernel

	sudo apt install -y libelf-dev libdw-dev gcc-multilib cmake \
		python3 python3-pip python3-venv
	install_libbpf
	pip install flask
	install_clang
	# install_gcc11

	# Configure HUGEPAGES
	grub='GRUB_CMDLINE_LINUX_DEFAULT="default_hugepagesz=1G hugepagesz=1G hugepages=8 nosmt"'
	echo $grub | sudo tee -a /etc/default/grub
	sudo update-grub

	get_repos
	# setup_nginx

	# install_cpupower
	# install_x86_energy
	sudo apt install linux-tools-`uname -r`
	configure_for_exp
}

case $1 in
	"dev_env")
		configure_dev_env ;;
	"gen")
		do_gen ;;
	"dut")
		do_dut ;;
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
	*)
		echo "Error: unknown mode was selected"
		usage
		exit 1
		;;
esac
exit 0
