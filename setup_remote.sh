user=farbod
dut_machine=amd159.utah.cloudlab.us
gen_machine=amd166.utah.cloudlab.us


# # Copy the ssh-key
scp $HOME/.ssh/dummy/* ${user}@${dut_machine}:~/.ssh/
scp $HOME/.ssh/dummy/* ${user}@${gen_machine}:~/.ssh/

# Copy script
scp ./setup.sh ${user}@${dut_machine}:~/
scp ./setup.sh ${user}@${gen_machine}:~/

# Run setup script

ssh ${user}@${dut_machine} <<EOF
bash ~/setup.sh dut
EOF

ssh ${user}@${gen_machine} <<EOF
bash ~/setup.sh gen
EOF
