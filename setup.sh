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

function bring_gen_script {
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

function install_new_kernel {
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

function cpupower_config {
	# Configure CPU scheduler policy
	cpupower frequency-set -g performance
	sudo cpupower idle-set -D 1
}

function usage {
	echo "setup.sh <mode>"
	echo "MODES:"
	echo "  * gen: configure the workload generator machine"
	echo "  * dut: configure the machine under test"
	echo "  * repo: only fetch the repos"
	echo "  * kern: only install the custom kernel"
}


check_pre_conditions

if [ $# -lt 1 ] ; then
	usage
	exit 0
fi

# TODO: use switch-case
if [ "x$1" = "xgen" ]; then
	configure_dev_env
	get_wrk_gen
	bring_gen_scripts
	disable_irqbalance
	exit 0
fi

if [ "x$1" = "xdut" ]; then
	configure_dev_env
	install_new_kernel

	sudo apt install -y libbpf-dev libelf-dev libdw-dev gcc-multilib cmake python3-pip
	pip install flask

	# Install clang
	CLANG_VERSION=15
	cd $HOME
	wget https://apt.llvm.org/llvm.sh
	chmod +x llvm.sh
	sudo ./llvm.sh $CLANG_VERSION

	# Configure the clang
	sudo update-alternatives --install /usr/bin/clang clang /usr/bin/clang-$CLANG_VERSION 100
	sudo update-alternatives --install /usr/bin/llc llc /usr/bin/llc-$CLANG_VERSION 100
	sudo update-alternatives --install /usr/bin/llvm-strip llvm-strip /usr/bin/llvm-strip-$CLANG_VERSION 100

	# Install g++-11
	sudo add-apt-repository -y ppa:ubuntu-toolchain-r/test
	sudo apt install -y gcc-11 g++-11
	sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-11 100
	sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-11 100

	# Configure HUGEPAGES
	grub='GRUB_CMDLINE_LINUX_DEFAULT="default_hugepagesz=1G hugepagesz=1G hugepages=8"'
	echo $grub | sudo tee -a /etc/default/grub
	sudo update-grub

	get_repos
	# setup_nginx

	disable_irqbalance
	install_cpupower
	cpupower_config
	exit 0
fi

if [ "x$1" = "xrepo" ]; then
	get_repos
	exit 0
fi

if [ "x$1" = "xkern" ]; then
	install_new_kernel
	exit 0
fi

echo "Did you mean to run this script for 'dut'!"
exit 1
