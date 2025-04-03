#! /bin/bash
set -x
set -e

source servers.sh

# Selected configuration for each machine
DUT=dut
GEN=gen
if [ -n "$MACHNET" ]; then
	echo "Configuring enviroment for MACHNET..."
	DUT=machnet
	GEN=machnet
fi

# Gather the fingerprints
ssh-keyscan "${dests[@]}" >> "$HOME/.ssh/known_hosts"

# Copy some files
for m in "${dests[@]}"; do
	# Copy the ssh-key
	scp "$HOME"/.ssh/dummy/* "${user}@${m}:~/.ssh/"
	# Copy setup script
	scp ./setup.sh "${user}@${m}:~/"
	# Copy helper scripts
	scp -r ./scripts "${user}@${m}:~/"

	# Make sure the system knows the github ssh fingerpring so that the
	# setup script runs smoothly
	ssh "${user}@${m}" <<EOF
	ssh-keyscan github.com >> ~/.ssh/known_hosts
EOF
done


# ==================================================================
# TODO: I still haven't figured out what is the most convinient way of shipping
# custom kernels :)
# Move my patched kernel to the DUT
#
# NOTES: for improvement, move the custom archive dir to the config. Also the
# version of kernel should be defined in the config so we fetch the correct
# source file for installing other tools
# ..................................................................
tar="$HOME"/linux-kernel-6.13.3-arena-prefetch.tar.xz
ssh "${user}@${dut_machine}" "mkdir -p ~/disk/_kernel"
scp "$tar" "${user}@${dut_machine}:~/disk/_kernel/custom_kernel.tar.xz"
# ==================================================================

# Run setup script
ssh "${user}@${dut_machine}" "bash ~/setup.sh $DUT"

ssh "${user}@${gen_machine}" "bash ~/setup.sh $GEN"

# TODO: make the config system more flexible :)
if [ -n "$gen_machine_2" ]; then
	ssh "${user}@${gen_machine_2}" "bash ~/setup.sh $GEN"
fi
