#!/bin/bash
set -e

USAGE=$(cat <<-EOF

${0} sets up the compute or server node
for the HPC cluster.

NOTE: After running this script make 
sure you run the master node script 
on the VM which you want to configure
as a master node.
EOF
)

#Check if script is running with root permissions
if [[ $UID != "0" ]]; then
  echo "Sorry, must be root to run this."
  exit
fi

if [ $# -gt 0 ];then
echo $USAGE
exit 0
fi

#Check if OS is not a minimal installation
#
if [ "$(grep minimal /root/anaconda-ks.cfg)" != "" ];then
	printf "Detected Minimal installation! Exiting"
	exit 3
fi

#Check if it is running on  CentOS 7 
#
OSVER=$(awk -F "=" '{print $2}' /etc/os-release|head -n 2|sed 's/\"//g'|tr "\n" " ")
arr=($OSVER)
[ "${arr[0]}" != "CentOS" ] || [ "${arr[2]}" != "7" ] && echo "OS is not CentOS7! Exiting" && exit 4

# Check if this tool is run in a virtualized environment
#
if [ $(command dmesg &> /dev/null; echo $?) -eq 0 ]; then
    env=$(dmesg | awk '/paravirtualized/{print $7}')
   if [ ! -z "$env" ] && [ "$env" == 'bare' ]; then
     printf "Detected Non-virualized OS! Exiting\n"
     exit 2
   fi
fi

function statusUpdate() {
 echo -e "${1}"" ""${2}..."
}


SElinux="/etc/sysconfig/selinux"
HOST_NAME="/etc/hostname"
HOST_ONLY_CON="/etc/sysconfig/network-scripts/ifcfg-ens33"
DNS="/etc/hosts"
AUTH_KEYS="/root/.ssh/authorized_keys"
SSH_CONFIG="/root/.ssh/config"
PROXY="/etc/profile.d/proxy.sh"

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

cat <<EOF > ${PROXY}
export http_proxy=http://sp:8080/
export https_proxy=https://sp:8080/
EOF

#ping -c 1 sp
sed -i 's/^sslverify=.*/sslverify=false/g' /etc/yum.conf

if [ -z $(cat /etc/yum.conf |egrep ^sslverify) ];then
cat <<EOF >> /etc/yum.conf
sslverify=false
EOF
fi

