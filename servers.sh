# THIS FILE READS THE CONFIG AND SHARES THE SERVER VARIABLE FOR DIFFERENT
# SCRIPTS TO USE
CURDIR=$(realpath $(dirname $0))
YAML=$CURDIR/config.yaml

function read_from_yaml {
	# Very simplestic
	field=$1
	echo $(cat $YAML | grep -v "^#" | grep "$field:" | cut -d ':' -f 2 | tr -d '[:space:]')
}

user=$(read_from_yaml "user")
# TODO: make the config system more flexible :)
dut_machine=$(read_from_yaml "dut_machine")
gen_machine=$(read_from_yaml "gen_machine")
gen_machine_2=$(read_from_yaml "gen_machine_2")
dests=( $dut_machine $gen_machine $gen_machine_2 )
# dests=( $dut_machine )
