#! /bin/bash
set -x -e

CURDIR=$(realpath $(dirname $0))
YAML=$CURDIR/config.yaml

function read_from_yaml {
	# Very simplestic
	field=$1
	echo $(cat $YAML | grep $field | cut -d ':' -f 2 | tr -d '[:space:]')
}

user=$(read_from_yaml "user")
dut_machine=$(read_from_yaml "dut_machine")
gen_machine=$(read_from_yaml "gen_machine")
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
