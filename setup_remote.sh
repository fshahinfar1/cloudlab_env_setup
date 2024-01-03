#! /bin/bash
user=farbod

dut_machine=hp097.utah.cloudlab.us
gen_machine=hp096.utah.cloudlab.us
dests=( $dut_machine $gen_machine )
# dests=( $dut_machine )

# Gather the fingerprints
ssh-keyscan ${dests[@]} >> $HOME/.ssh/known_hosts

# Copy some files
for m in ${dests[@]}; do
	# Copy the ssh-key
	scp $HOME/.ssh/dummy/* ${user}@${m}:~/.ssh/
	# Copy setup script
	scp ./setup.sh ${user}@${m}:~/
	# Copy helper scripts
	scp -r ./scripts ${user}@${m}:~/

	# Run setup script
	ssh ${user}@${m} <<EOF
	ssh-keyscan github.com >> ~/.ssh/known_hosts
EOF
done

# Run setup script
ssh ${user}@${dut_machine} <<EOF
bash ~/setup.sh dut
EOF

ssh ${user}@${gen_machine} <<EOF
bash ~/setup.sh gen
EOF
