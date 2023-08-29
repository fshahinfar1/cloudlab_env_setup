user=farbod
dut_machine=amd177.utah.cloudlab.us
gen_machine=amd173.utah.cloudlab.us


ssh-keyscan $dut_machine $gen_machine >> $HOME/.ssh/known_hosts

# # Copy the ssh-key
scp $HOME/.ssh/dummy/* ${user}@${dut_machine}:~/.ssh/
scp $HOME/.ssh/dummy/* ${user}@${gen_machine}:~/.ssh/

# Copy script
scp ./setup.sh ${user}@${dut_machine}:~/
scp ./setup.sh ${user}@${gen_machine}:~/

# Run setup script

ssh ${user}@${dut_machine} <<EOF
ssh-keyscan github.com >> ~/.ssh/known_hosts
bash ~/setup.sh dut
EOF

ssh ${user}@${gen_machine} <<EOF
ssh-keyscan github.com >> ~/.ssh/known_hosts
bash ~/setup.sh gen
EOF
