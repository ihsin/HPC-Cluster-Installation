#!/bin/sh

USAGE=$(cat <<-EOF
${0} sets up the master or admin node
for the HPC cluster.
NOTE: Before running this script make 
sure you run the compute node script 
on the VM which you want to configure
as a compute node.
EOF
)

if [ $# -gt 0 ];then
echo $USAGE
exit 0
fi

function statusUpdate() {
 echo -e "${1}"" ""${2}..."
}


SElinux="/etc/sysconfig/selinux"
HOST_NAME="/etc/hostname"
NIS_DOMAIN="/etc/sysconfig/network"
HOST_ONLY_CON="/etc/sysconfig/network-scripts/ifcfg-ens33"
NAT_CON="/etc/sysconfig/network-scripts/ifcfg-ens34"
DNS="/etc/hosts"
PROXY="/etc/squid/squid.conf"
SSH_CONFIG="/root/.ssh/config"
AUTH_KEYS="/root/.ssh/authorized_keys"
RPM_REPO="/run/media/root/CentOS 7 x86_64/Packages"
FTP_ROOT="/var/ftp/pub/"

statusUpdate 'changing' 'hostname'
if [ -f ${HOST_NAME} ];then
	echo "sp">${HOST_NAME}
fi

statusUpdate 'disabling' 'NetworkManager'
systemctl stop NetworkManager.service
systemctl disable NetworkManager.service

statusUpdate 'disabling' 'SElinux'
if [ -f ${SElinux} ];then
        echo "SELINUX=disabled">${SElinux}
fi

statusUpdate 'configuring' 'Host-Only adapter'
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

statusUpdate 'configuring' 'NAT adapter'
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

statusUpdate 'restarting' 'network'
systemctl restart network

statusUpdate 'configuring' 'DNS'
if [ -f ${DNS} ];then
cat <<EOF > $DNS
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6
192.168.225.100 sp header main
192.168.225.101 cp01 compute1 
192.168.225.102 cp02 compute2
EOF
fi

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
echo -e "\n\n\n"|ssh-keygen 1> /dev/null 2>&1
cat /root/.ssh/id_rsa.pub>${AUTH_KEYS}

cat <<EOF > ${SSH_CONFIG}
Host *
        IdentitiesOnly yes
	ServerAliveInterval 30
	ServerAliveCountMax 10 
        StrictHostKeyChecking no
EOF

statusUpdate 'pinging' 'cp01'
ping -c 1 cp01  1> /dev/null 2>&1

statusUpdate 'Copying ssh-keys to' 'cp01'
if [ $? -eq 0 ]; then
cat ~/.ssh/id_rsa.pub | ssh cp01 "chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
ssh-add  1> /dev/null 2>&1
ssh cp01 cat /root/.ssh/id_rsa.pub>>${AUTH_KEYS}
else
echo "\n Error connecting to cp01 \n"
fi

statusUpdate 'pinging' 'cp02'
ping -c 1 cp02  1> /dev/null 2>&1

if [ $? -eq 0 ]; then
cat ~/.ssh/id_rsa.pub | ssh cp02 "chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
ssh-add  1> /dev/null 2>&1
ssh cp02 cat /root/.ssh/id_rsa.pub>>${AUTH_KEYS}
else
echo "\n Error connecting to cp02 \n"
fi

scp ~/.ssh/authorized_keys cp01:/root/.ssh  1> /dev/null 2>&1
#scp ~/.ssh/authorized_keys cp02:/root/.ssh

statusUpdate 'Installing' 'vsftpd'
if [ -d "${RPM_REPO}" ];then
	vsftpd=$(ls "${RPM_REPO}"|grep vsftpd)
        rpm -ivh "${RPM_REPO}/${vsftpd}"  1> /dev/null 2>&1
else
	exit 1
fi

statusUpdate 'restarting' 'vsftpd'
systemctl restart vsftpd
systemctl enable vsftpd

statusUpdate 'copying rpms repository to' 'ftp root'
cp -r "${RPM_REPO}" ${FTP_ROOT}

statusUpdate 'creating' 'base repolist'
createrepo=$(ls "${RPM_REPO}"|grep createrepo)
rpm -ivh "${RPM_REPO}/${createrepo}"  1> /dev/null 2>&1
createrepo ${FTP_ROOT}

rm -rf /etc/yum.repos.d/*

cat <<EOF > /etc/yum.repos.d/CentOS-base.repo
[base]
name=CentOS DVD RPMs
baseurl=ftp://sp/pub
gpgcheck=0
enabled=1
EOF

yum clean all 1> /dev/null 2>&1
yum repolist 1> /dev/null 2>&1

statusUpdate 'copying' 'repolist to cp01'
ssh cp01 "rm -rf /etc/yum.repos.d/*"
scp /etc/yum.repos.d/CentOS-base.repo cp01:/etc/yum.repos.d/ 1> /dev/null 2>&1
#scp CentOS-Base.repo cp02:/etc/yum.repos.d/

statusUpdate 'installing' 'ftp on cp01'
ftp=$(ls "${RPM_REPO}"|grep ftp)
ssh cp01 "rpm -ivh '${RPM_REPO}'/${ftp} && yum clean all"

statusUpdate 'adding' 'epel repolist'
#Add epel to yum
wget --no-check-certificate https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
scp $HOME/epel-release-latest-7.noarch.rpm cp01:~

sed -i 's/^sslverify=.*/sslverify=false/g' /etc/yum.conf

if [ -z $(cat /etc/yum.conf |egrep ^sslverify) ];then
cat <<EOF >> /etc/yum.conf
sslverify=false
EOF
fi

rpm -ivh epel-release-latest-7.noarch.rpm 1> /dev/null 2>&1
ssh cp01 "rpm -ivh $HOME/epel-release-latest-7.noarch.rpm 1> /dev/null 2>&1"
yum repolist 1> /dev/null 2>&1

statusUpdate 'installing and configuring proxy'
yum -y install squid
cat<< EOF > ${PROXY}
visible_hostname sp
acl LAN src 192.168.225.0/24
http_access allow LAN
http_access deny all
http_port 8080
cache_dir ufs /var/spool/squid 4096 100 256
cache_mem 512 MB
EOF
systemctl restart squid
systemctl enable squid

statusUpdate 'installing' 'nfs on cp01'
ssh cp01 "yum -y install nfs-utils.x86_64 \
&& systemctl restart rpcbind \
&& systemctl enable rpcbind \
&& systemctl restart nfs \
&& systemctl enable nfs"

ssh cp01 "if [ -d /glb ];
then
rm -rf /glb
fi \
&& mkdir /glb"

statusUpdate 'installing' 'nfs'
yum -y install nfs-utils.x86_64 1> /dev/null 2>&1
if [ -d /glb ];then
rm -rf /glb
fi
mkdir -p /glb/home
mkdir -p /glb/apps

statusUpdate 'exporting' '/glb/home & /glb/apps'
cat <<EOF > /etc/exports
/glb/home *(rw,sync)
/glb/apps *(rw,sync)
EOF

exportfs -a

systemctl restart rpcbind
systemctl enable rpcbind

statusUpdate 'restarting' 'nfs'
systemctl restart nfs
systemctl enable nfs

#ssh cp01 "mount sp:/glb/home /glb/home"
#ssh cp02 "systemctl start rpcbind && systemctl enable nfs && mount sp:/glb/home /glb/home"

statusUpdate 'installing autofs and mounting' '/glb/home & /glb/apps on cp01'
ssh cp01 "yum install -y autofs.x86_64 \
&& sed -i 's/\/misc/\/glb/' /etc/auto.master \
&& sed -i 's/auto.misc/auto.home/' /etc/auto.master \
&& cat <<EOF > /etc/auto.home
home	-fstype=nfs,rw,soft,intr    sp:/glb/home
apps	-fstype=nfs,rw,soft,intr    sp:/glb/apps
EOF"

ssh cp01 "systemctl restart autofs && systemctl enable autofs"

statusUpdate 'installing and configuraing' 'nis'
yum -y install ypserv.x86_64 1> /dev/null 2>&1
nisdomainname nisDC
cat <<EOF > ${NIS_DOMAIN}
NISDOMAIN=nisDC
EOF

systemctl restart ypserv
systemctl enable ypserv
systemctl restart yppasswdd
systemctl enable yppasswdd

statusUpdate 'making it' 'master or domain controller'
echo -e "y\n"|/usr/lib64/yp/ypinit -m 1> /dev/null 2>&1

ssh cp01 "yum -y install ypbind.x86_64 \
&& authconfig --enablenis --nisdomain=nisDC --nisserver=sp --update \
&& systemctl restart ypbind \
&& systemctl enable ypbind"

statusUpdate 'adding user and invoking' 'make'
make -C /var/yp/ 1> /dev/null 2>&1


read -p "Install LSF? (y/N)? " choice
case "$choice" in 
y|Y ) lsf=1;;
* ) echo "WARN: Skipping Nagios Installation";;
esac

if [ ! -z $lsf ];then
if [ ! -f "$HOME/lsf10.1_no_jre_lsfinstall.tar.Z" ]; then
echo -e "Error: LSF bundle missing in root directory\n"
else
useradd -d /glb/home/lsfadmin lsfadmin
make -C /var/yp/ 1> /dev/null 2>&1
yum -y install java-1.8.0-openjdk.x86_64
tar -xzf $HOME/lsf10.1_no_jre_lsfinstall.tar.Z
mv $HOME/lsf10.1_lsfinstall/install.config $HOME/lsf10.1_lsfinstall/install.config.sample
cat <<EOF > $HOME/lsf10.1_lsfinstall/install.config
LSF_TOP="/glb/apps/lsf"
LSF_ADMINS="lsfadmin"
LSF_CLUSTER_NAME="VMWare_Cluster"
LSF_MASTER_LIST="sp"
LSF_ENTITLEMENT_FILE="$HOME/lsf_std_entitlement_10.1.dat"
LSF_ADD_SERVERS=“cp01"
LSF_ADD_CLIENTS=“cp01“
LSF_QUIET_INST="Y"
EOF
fi
fi
