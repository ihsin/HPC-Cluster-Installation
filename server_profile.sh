#!/bin/sh


SElinux="/etc/sysconfig/selinux"
HOST_NAME="/etc/hostname"
HOST_ONLY_CON="/etc/sysconfig/network-scripts/ifcfg-ens33"
NAT_CON="/etc/sysconfig/network-scripts/ifcfg-ens34"
DNS="/etc/hosts"
SSH_CONFIG="/root/.ssh/config"
AUTH_KEYS="/root/.ssh/authorized_keys"
RPM_REPO="/run/media/root/CentOS 7 x86_64/Packages"
FTP_ROOT="/var/ftp/pub/"

if [ -f ${HOST_NAME} ];then
	echo "sp">${HOST_NAME}
fi

systemctl stop NetworkManager.service
systemctl disable NetworkManager.service

if [ -f ${SElinux} ];then
        echo "SELINUX=disabled">${SElinux}
fi

if [ -f ${NAT_CON} ];then
cat <<EOF > ${NAT_CON}
TYPE=Ethernet
BOOTPROTO=dhcp
DEFROUTE=yes
NAME=ens34
DEVICE=ens34
ONBOOT=yes
EOF
fi

if [ -f ${HOST_ONLY_CON} ];then
cat <<EOF > ${HOST_ONLY_CON}
TYPE=Ethernet
BOOTPROTO=none
DEFROUTE=yes
NAME=ens33
DEVICE=ens33
ONBOOT=yes
IPADDR=192.168.225.100
PREFIX=24
EOF
fi

systemctl restart network

if [ -f ${DNS} ];then
cat <<EOF >> $DNS
192.168.225.100 sp header main
192.168.225.101 cp01 compute1 
192.168.225.102 cp02 compute2
EOF
fi

systemctl stop firewalld.service
systemctl disable firewalld.service

if [ -d $HOME/.ssh ];then
rm -rf $HOME/.ssh
fi

if [ -z $SSH_AGENT_PID ]; then
eval `ssh-agent`
fi

echo -e "\n\n\n"|ssh-keygen

cat /root/.ssh/id_rsa.pub>${AUTH_KEYS}

cat <<EOF > ${SSH_CONFIG}
Host *
        IdentitiesOnly yes
	ServerAliveInterval 30
	ServerAliveCountMax 10 
        StrictHostKeyChecking no
EOF

ping -c 1 cp01

if [ $? -eq 0 ]; then
cat ~/.ssh/id_rsa.pub | ssh cp01 "chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
ssh-add
ssh cp01 cat /root/.ssh/id_rsa.pub>>${AUTH_KEYS}
else
echo "\n Error connecting to cp01 \n"
fi

ping -c 1 cp02

if [ $? -eq 0 ]; then
cat ~/.ssh/id_rsa.pub | ssh cp02 "chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
ssh-add
ssh cp02 cat /root/.ssh/id_rsa.pub>>${AUTH_KEYS}
else
echo "\n Error connecting to cp02 \n"
fi

scp ~/.ssh/authorized_keys cp01:/root/.ssh
#scp ~/.ssh/authorized_keys cp02:/root/.ssh

if [ -d "${RPM_REPO}" ];then
        rpm -ivh "${RPM_REPO}/vsftpd-3.0.2-22.el7.x86_64.rpm"
else
	exit 1
fi

systemctl start vsftpd
systemctl enable vsftpd

cp -r "${RPM_REPO}" ${FTP_ROOT}

rpm -ivh "${RPM_REPO}/createrepo-0.9.9-28.el7.noarch.rpm"
createrepo ${FTP_ROOT}

rm -rf /etc/yum.repos.d/*

cat <<EOF > /etc/yum.repos.d/CentOS-base.repo
[base]
name=CentOS DVD RPMs
baseurl=ftp://sp/pub
gpgcheck=0
enabled=1
EOF

yum clean all
yum repolist

ssh cp01 "rm -rf /etc/yum.repos.d/*"
scp /etc/yum.repos.d/CentOS-base.repo cp01:/etc/yum.repos.d/
#scp CentOS-Base.repo cp02:/etc/yum.repos.d/

ssh cp01 "rpm -ivh '${RPM_REPO}'/ftp-0.17-67.el7.x86_64.rpm' && yum clean all"

ssh cp01 "echo -e 'y\n'|yum install nfs-utils.x86_64 \
&& systemctl start rpcbind \
&& systemctl enable rpcbind \
&& systemctl start nfs \
&& systemctl enable nfs \
&& mkdir -p /glb/home"

mkdir -p /glb/home

cat <<EOF > /etc/exports
/glb/home *(rw,sync)
EOF

exportfs -a

systemctl start rpcbind
systemctl enable rpcbind

systemctl start nfs
systemctl enable nfs

ssh cp01 "mount sp:/glb/home /glb/home"
#ssh cp02 "systemctl start rpcbind && systemctl enable nfs && mount sp:/glb/home /glb/home"

