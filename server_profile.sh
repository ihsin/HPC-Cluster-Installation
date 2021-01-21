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

#Check if script is running with root permissions
if [[ $UID != "0" ]]; then
  echo "Sorry, must be root to run this."
  exit
fi

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
MUNGE_KEY="/etc/munge/munge.key"

statusUpdate 'changing' 'hostname'
if [ -f ${HOST_NAME} ];then
	echo "sp">${HOST_NAME}
fi

statusUpdate 'disabling' 'NetworkManager'
systemctl stop NetworkManager.service 1> /dev/null 2>&1
systemctl disable NetworkManager.service 1> /dev/null 2>&1

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
systemctl restart network 1> /dev/null 2>&1

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
systemctl stop firewalld.service 1> /dev/null 2>&1
systemctl disable firewalld.service 1> /dev/null 2>&1

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
systemctl restart vsftpd 1> /dev/null 2>&1
systemctl enable vsftpd 1> /dev/null 2>&1

statusUpdate 'copying rpms repository to' 'ftp root'
cp -r "${RPM_REPO}" ${FTP_ROOT}

statusUpdate 'creating' 'base repolist'
createrepo=$(ls "${RPM_REPO}"|grep createrepo)
rpm -ivh "${RPM_REPO}/${createrepo}"  1> /dev/null 2>&1
createrepo ${FTP_ROOT} 1> /dev/null 2>&1

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
yum repolist 1> /dev/null 2>&1

statusUpdate 'installing and configuring proxy'
yum -y install squid 1> /dev/null 2>&1
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

systemctl restart rpcbind 1> /dev/null 2>&1
systemctl enable rpcbind 1> /dev/null 2>&1

statusUpdate 'restarting' 'nfs'
systemctl restart nfs 1> /dev/null 2>&1
systemctl enable nfs 1> /dev/null 2>&1

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
nisdomainname nisDC 1> /dev/null 2>&1
cat <<EOF > ${NIS_DOMAIN}
NISDOMAIN=nisDC
EOF

systemctl restart ypserv 1> /dev/null 2>&1
systemctl enable ypserv 1> /dev/null 2>&1
systemctl restart yppasswdd 1> /dev/null 2>&1
systemctl enable yppasswdd 1> /dev/null 2>&1

statusUpdate 'making it' 'master or domain controller'
echo -e "y\n"|/usr/lib64/yp/ypinit -m 1> /dev/null 2>&1

ssh cp01 "yum -y install ypbind.x86_64 \
&& authconfig --enablenis --nisdomain=nisDC --nisserver=sp --update \
&& systemctl restart ypbind \
&& systemctl enable ypbind"

make -C /var/yp/ 1> /dev/null 2>&1

ssh cp01 "rpm -ivh $HOME/epel-release-latest-7.noarch.rpm 1> /dev/null 2>&1"

read -p "Install slurm? (y/N)? " choice
case "$choice" in
y|Y ) slurm=1;;
* ) echo "WARN: Skipping Slurm Installation";;
esac

statusUpdate 'adding' 'functional Users'
useradd -d /glb/home/munge munge
useradd -d /glb/home/slurm slurm
make -C /var/yp/ 1> /dev/null 2>&1


if [ ! -z $slurm ];then
statusUpdate 'Installing' 'munge'
yum -y install munge 1> /dev/null 2>&1
ssh cp01 "bash -c 'yum -y install munge'" 1>/dev/null 2>&1
if [ ! -f "$HOME/slurm-20.11.2.tar.bz2" ]; then
echo -e "Warn: Slurm source file missing in root directory"
echo -e "Downloading it"
wget --no-check-certificate  https://download.schedmd.com/slurm/slurm-20.11.2.tar.bz2 1> /dev/null 2>&1
tar -xjf $HOME/slurm-20.11.2.tar.bz2
fi

statusUpdate 'Creating and copying' 'munge random key'
/usr/sbin/create-munge-key 1> /dev/null 2>&1
scp ${MUNGE_KEY} cp01:${MUNGE_KEY}
statusUpdate 'Changing' 'Ownership and Permissions'
chown -R munge: /etc/munge/ /var/log/munge/ /var/lib/munge/ /run/munge/
ssh cp01 "chown -R munge: /etc/munge/ /var/log/munge/ /var/lib/munge/ /run/munge/"
systemctl start munge
systemctl enable munge
ssh cp01 "systemctl start munge && systemctl enable munge"

statusUpdate "installing" "python dependencies"
yum install gcc openssl-devel bzip2-devel libffi-devel -y 1> /dev/null 2>&1
ssh cp01 "yum install gcc openssl-devel bzip2-devel libffi-devel -y" 1> /dev/null 2>&1

statusUpdate "installing" "python3"
if [ ! -f "$HOME/Python-3.8.1.tgz" ]; then
echo -e "Warn: python source file missing in root directory"
echo -e "Downloading it"
wget --no-check-certificate https://www.python.org/ftp/python/3.8.1/Python-3.8.1.tgz 1> /dev/null 2>&1
[[ $? -ne 0 ]] && exit
tar -xzf $HOME/Python-3.8.1.tgz
fi
cd $HOME/Python-3.8.1/
./configure --enable-optimizations --prefix=/glb/apps/python3 && make altinstall

statusUpdate "installing" "slurm: THIS WILL TAKE FEW MINUTES"
ln -s /glb/apps/python3/bin/python3.8 /glb/apps/python3/bin/python3
export PATH=$PATH:/glb/apps/python3/bin/
cd $HOME/slurm-20.11.2/
./configure --prefix=/glb/apps/slurm && make && make install
fi


