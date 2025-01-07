#!/bin/bash
# reboot all the servers
source ./servers.sh
for m in ${dests[@]}; do
	ssh ${user}@${m} "sudo reboot"
done
