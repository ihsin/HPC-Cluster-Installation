##### HPC-Cluster-Installation #####

A project to automate HPC environment configurations with slurm as schedular on GNOME Desktop installation of CentOS 7 using VMware.

Requirequirements:
1. VMware
2. CentOS 7 iso

Note:  The CentOS 7 iso should not be a minimal source.

Step 1. Creating the compute node.
1. Using the iso image create a VM with Network Adapter as Host Only.
2. Install CentOS-7 with GNOME Desktop configurations.

Step 2. Run compute_profile.sh on compute node as root.

Step 3. Creating the master node.
1. Using the iso image create a VM with Network Adapters as follows:
a. Host Only
b. NAT
2. Install CentOS-7 with GNOME Desktop configurations.

Step 4. Run server_profile.sh on master node as root.

Note: Running server_profile.sh will take about 20 minutes to complete.

Q. What the scripts does?

1. Provides a static IP address to Host Only adapters as follows:
	1. master node: 192.168.225.100
	2. compute node: 192.168.225.101
2. Configures local DNS 
3. Disables Firewalld and SELinux
4. Creates a passwordless ssh access for root from both ends.
5. Configures ftp
6. Creates yum centralized repositories accessable through ftp.
7. Adds epel
8. Configures master as squid proxy server for compute.
9. Configures nfs and automount to /glb/apps and /glb/home.
10. Configures nis and creates users munge and slurm.
*  Slurm Installation (Optional)
11. Installs python3 and it's dependencies.
12. Installs and configures munge.
13. Installs and configures slurm.

