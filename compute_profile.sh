#!/bin/bash

function statusUpdate() {
 echo -e "${1}"" ""${2}..."
}


SElinux="/etc/sysconfig/selinux"
HOST_NAME="/etc/hostname"
HOST_ONLY_CON="/etc/sysconfig/network-scripts/ifcfg-ens33"
DNS="/etc/hosts"
AUTH_KEYS="/root/.ssh/authorized_keys"
SSH_CONFIG="/root/.ssh/config"


statusUpdate 'changing' 'hostname'
if [ -f ${HOST_NAME} ]; then
        echo "cp01">${HOST_NAME}
fi

statusUpdate 'disabling' 'NetworkManager'
systemctl stop NetworkManager.service
systemctl disable NetworkManager.service


statusUpdate 'disabling' 'SElinux'
if [ -f ${SElinux} ]; then
        echo "SELINUX=disabled">${SElinux}
fi

statusUpdate 'configuring' 'Host-Only adapter'
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


statusUpdate 'configuring' 'DNS'
if [ -f ${DNS} ]; then
cat <<EOF >> $DNS
192.168.225.100 sp header main
192.168.225.101 cp01 compute1 
192.168.225.102 cp02 compute2
EOF
fi


statusUpdate 'restarting' 'network'
systemctl restart network


statusUpdate 'disabling' 'firewall'
systemctl stop firewalld.service
systemctl disable firewalld.service


statusUpdate 'checking' 'ssh'
if [ -d $HOME/.ssh ];then
rm -rf $HOME/.ssh
fi

if [ -z $SSH_AGENT_PID ]; then
eval `ssh-agent`
fi


statusUpdate 'creating' 'ssh-keys'
echo -e '\n\n\n'|ssh-keygen 1> /dev/null 2>&1

ssh-add 1>/dev/null 2>&1

cat <<EOF > ${SSH_CONFIG}
Host *
        IdentitiesOnly yes
	ServerAliveInterval 30
	ServerAliveCountMax 10
        StrictHostKeyChecking no
EOF

#ping -c 1 sp

