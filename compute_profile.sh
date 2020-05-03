#!/bin/bash

SElinux="/etc/sysconfig/selinux"
HOST_NAME="/etc/hostname"
HOST_ONLY_CON="/etc/sysconfig/network-scripts/ifcfg-ens33"
DNS="/etc/hosts"
AUTH_KEYS="/root/.ssh/authorized_keys"
SSH_CONFIG="/root/.ssh/config"

if [ -f ${HOST_NAME} ]; then
        echo "cp01">${HOST_NAME}
fi

systemctl stop NetworkManager.service
systemctl disable NetworkManager.service

if [ -f ${SElinux} ]; then
        echo "SELINUX=disabled">${SElinux}
fi

if [ -f ${HOST_ONLY_CON} ]; then
cat <<EOF > ${HOST_ONLY_CON}
TYPE=Ethernet
BOOTPROTO=none
DEFROUTE=yes
NAME=ens33
DEVICE=ens33
ONBOOT=yes
IPADDR=192.168.225.101
PREFIX=24
GATEWAY=192.168.225.100
EOF
fi

if [ -f ${DNS} ]; then
cat <<EOF >> $DNS
192.168.225.100 sp header main
192.168.225.101 cp01 compute1 
192.168.225.102 cp02 compute2
EOF
fi

systemctl restart network

systemctl stop firewalld.service
systemctl disable firewalld.service

if [ -d $HOME/.ssh ];then
rm -rf $HOME/.ssh
fi

if [ -z $SSH_AGENT_PID ]; then
eval `ssh-agent`
fi

echo -e '\n\n\n'|ssh-keygen

ssh-add

cat <<EOF > ${SSH_CONFIG}
Host *
        IdentitiesOnly yes
	ServerAliveInterval 30
	ServerAliveCountMax 10
        StrictHostKeyChecking no
EOF

ping -c 1 sp

