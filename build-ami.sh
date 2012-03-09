#!/bin/bash

# Jamie Carranza
# October 3, 2011

# Build a Linux EC2 AMI
# For RPM based distributions


# Based on the this wonderful tutorial, thanks Phil!
# http://www.philchen.com/2009/02/14/how-to-create-an-amazon-elastic-compute-cloud-ec2-machine-image-ami

    ## Features

# Can build instance store or EBS backed AMIs from scratch
# Can use YUM repos from build host or distro default


# Must have access to any YUM repositories specifed

    ## Create Instance Store Backed AMIs

# Set "EBS=0", and set "ROOT" to be a local filesystem location large enough
# to hold your AMI, which can be 10GB max size.


    ## Create EBS Backed AMIs

# EBS volumes must be built on a EC2 instance.  Once built, snapshot and
# register the EBS volume as an AMI.

# Attach an EBS volume of desired size to a running instance.  Set "EBS=1",
# and set "ROOT" to be the mounted EBS volume.

# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
#			Basic Configuration
# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

WORKING_DIR=''

# Base name of the AMI to build (finished AMI will have a '.img' extension)
AMI_NAME=''

# Where to build AMI (instance store only)
AMI_DIR=""

# Mount point for AMI image
ROOT="/mnt/${AMI_NAME}"

# Services to disable
SVC_DISABLE=''

# Add curl command to rc.local to download private key from instance metadata
# overwriting or appending to exising /root/.ssh/authorized_keys, or "none" to
# delete all root private keys. 
# "overwrite", "append", or "none".  default: "overwrite"
PRIVATE_KEY='append'

# Add optional user account (use md5 hashed password)
#USER=''
#PASSWORD=''

# URL for EC2 AMI tools
AMI_TOOLS_URL=''

# URL for EC2 API tools
API_TOOLS_URL=''

# Build on EBS volume
EBS='1'

# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
#			Advanced Configuration
# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

# Yum package group, Core or Base 
YUM_GROUPS='base'

# Other packages to add, must be available in the repo you make available
PACKAGES=''

# Whether to use a default YUM configuration to build the AMI or copy the host system's
USE_HOST_YUM_CFG='0'

# If USE_HOST_YUM_CFG='1', whether to keep host system's YUM config in the AMI or reset with distro default
RESET_YUM_CFG='0'

# If USE_HOST_YUM_CFG='0', specify the URL to the package containing the desired distribution's YUM configuration, i.e. 'centos-release'
DISTRO_RELEASE=''

# Where to put AMI and API tools
AMI_TOOLS="${WORKING_DIR}/AMI_TOOLS"
API_TOOLS="${WORKING_DIR}/API_TOOLS"

# AMI Size (MB) - For instance-store only
# Limited to 10 GB (10240 MB)
SIZE='10240'

# Whether to make the image file sparse
SPARSE='1'

# Filesystem type for root filesystem
FSTYPE='ext3'

# Optional - URL for kernel modules
#KERNEL_MODULES=''

# Shell Command Paths
awk='/usr/bin/awk'
cat='/bin/cat'
chmod='/bin/chmod'
chroot='/usr/sbin/chroot'
cp='/bin/cp'
curl='/usr/bin/curl'
cut='/bin/cut'
depmod='/sbin/depmod'
dd='/bin/dd'
echo='/bin/echo'
mkdir='/bin/mkdir'
mkfs='/sbin/mkfs.ext3'
mknod='/bin/mknod'
mount='/bin/mount'
mv='/bin/mv'
rm='/bin/rm'
rpm='/bin/rpm'
sed='/bin/sed'
tar='/bin/tar'
touch='/bin/touch'
wget='/usr/bin/wget'
umount='/bin/umount'
unzip='/usr/bin/unzip'
yum='/usr/bin/yum'

# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
#			File Contents
# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

# Comment out entire "heredoc" to disable.

# Add to fstab (use for ephemeral storage
#EPHEMERAL_STORAGE=`$cat << EOF

#EOF`

# Sudoers content
#SUDOERS=`$cat << EOF

#EOF`

#-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=

if
	[ ! -d "$WORKING_DIR" ]
then
	$echo "ERROR: $WORKING_DIR does not exist ...exiting"
	exit 1
fi

# Create AMI_DIR if needed

[ -d "$AMI_DIR" ] || $mkdir -p "$AMI_DIR"

# Get EC2 tools
if
	[ ! -d ${WORKING_DIR}/AMI_TOOLS ] && [ ! -d ${WORKING_DIR}/API_TOOLS ]
then
	cd $WORKING_DIR

    $mkdir ${WORKING_DIR}/AMI_TOOLS ${WORKING_DIR}/API_TOOLS

	# Set up AMI tools
	$wget $AMI_TOOLS_URL
	$unzip ec2-ami-tools*.zip

	# Set up API tools
	$wget $API_TOOLS_URL
	$unzip ec2-api-tools*.zip

	$rm -f *.zip
	$mv ec2-ami-tools*/ AMI_TOOLS
	$mv ec2-api-tools*/ API_TOOLS
fi

# If creating EBS backed AMI
if
    [ "$EBS" -eq 1 ]
then :
else
        # Create & mount image file
    if
	    if
		    [ $SPARSE = 1 ]
	    then
		    SIZE=$(($SIZE-1))
		    $dd if=/dev/zero of=${AMI_DIR}/${AMI_NAME} bs=1M oflag=direct seek=${SIZE} count=1
	    else
		    $dd if=/dev/zero of=${AMI_DIR}/${AMI_NAME} bs=1M oflag=direct count=${SIZE}
	    fi
	    $mkfs -F ${AMI_DIR}/${AMI_NAME} -L $AMI_NAME
    then :
    else
	    $echo "ERROR: image file creation or formatting failed ...exiting"
	    exit 1
    fi

    [ -d "$ROOT" ] || $mkdir -p $ROOT

    $mount -o loop ${AMI_DIR}/${AMI_NAME} $ROOT
fi

# Set environment
export EC2_HOME="$API_TOOLS"

# Create Basic Filesystem
cd $ROOT
$mkdir {etc,proc,dev,sys}
$mkdir -p var/{cache,lock,log}
$mkdir var/lock/rpm

# Make Special Files
$mknod -m 666 dev/zero c 1 5
$mknod -m 600 dev/console c 5 1
$mknod -m 666 dev/null c 1 3

# Make mountpoints for ephemeral instance storage if necessary
if
	[ "x${EPHEMERAL_STORAGE}" != x ]
then
	$echo "$EPHEMERAL_STORAGE" | while read line; do
		DEVICE=`echo "$line" | $cut -f2`
		[ ! -d $DEVICE ] && $mkdir $DEVICE
	done
fi

# Write fstab
$cat << EOF > etc/fstab
/dev/sda1  /         ext3    defaults        1 1
none       /dev/pts  devpts  gid=5,mode=620  0 0
none       /dev/shm  tmpfs   defaults        0 0
none       /proc     proc    defaults        0 0
none       /sys      sysfs   defaults        0 0
$EPHEMERAL_STORAGE
EOF

# Mount proc fs
$mount -t proc proc ${ROOT}/proc

# Mount sys fs
$mount -t sysfs sysfs ${ROOT}/sys

# Configure YUM
if
	[ "$USE_HOST_YUM_CFG" -eq 1 ]
then
	$cp /etc/yum.conf $ROOT/etc
	$cp -R /etc/yum.repos.d ${ROOT}/etc
	$cp -R /etc/yum ${ROOT}/etc
else
	cd $WORKING_DIR
	$wget $DISTRO_RELEASE
	pkg_name=`$echo $DISTRO_RELEASE | $awk -F/ '{print $NF}'`
	$rpm --root $ROOT --nodeps -Uvh $pkg_name
fi

# Install base/core packages
$yum -y --installroot=${ROOT} groupinstall $YUM_GROUPS
sync

$mkdir -p ${ROOT}/root/.ssh

# Put host system's repo back in place if necessary, it may have been overwritten by Core/Base install
if
	[ "$USE_HOST_YUM_CFG" -eq 1 ]
then
	$mv ${ROOT}/etc/yum.repos.d ${ROOT}/etc/yum.repos.d.dist
	$mv ${ROOT}/etc/yum.conf ${ROOT}/etc/yum.conf.dist
	$mv ${ROOT}/etc/yum ${ROOT}/etc/yum.dist
	$cp /etc/yum.conf ${ROOT}/etc/
	$cp -R /etc/yum.repos.d ${ROOT}/etc/
	$cp -R /etc/yum ${ROOT}/etc/
fi

# Install other packages
$yum -y --installroot=${ROOT} install $PACKAGES

# Put default YUM config in place if needed
if
	[ "$USE_HOST_YUM_CFG" -eq 1 ] && [ "$RESET_YUM_CFG" -eq 1 ]
then
	$rm -Rf ${ROOT}/etc/yum ${ROOT}/etc/yum.conf ${ROOT}/etc/yum.repos.d
	$mv ${ROOT}/etc/yum.dist ${ROOT}/etc/yum
	$mv ${ROOT}/etc/yum.conf.dist ${ROOT}/etc/yum.conf
	$mv ${ROOT}/etc/yum.repos.d.dist ${ROOT}/etc/yum.repos.d
fi

# Disable unneeded services
for service in $SVC_DISABLE; do
	$chroot $ROOT /sbin/chkconfig $service off
done

# Install kernel modules if needed
if
	[ ! "x${KERNEL_MODULES}" = x ]
then
	cd $WORKING_DIR
	$curl -s $KERNEL_MODULES | $tar -xzC $ROOT
	chroot $ROOT $depmod
fi

# Write sudoers
if [ ! "x${SUDOERS}" = x ]; then
    $echo "$SUDOERS" > ${ROOT}/etc/sudoers
fi

## Root Private Key

# write commands to rc.local to download private part of keypair used for
# launch either overwriting, appending, or deleting all root private keys.
if [ "$PRIVATE_KEY" = 'overwrite' ]; then
$cat << EOF > ${ROOT}/etc/rc.local
$curl -f http://169.254.169.254/latest/meta-data/public-keys/0/openssh-key > /root/.ssh/authorized_keys
$chmod 600 /root/.ssh/authorized_keys
EOF
elif [ "$PRIVATE_KEY" = 'append' ]; then
$cat << EOF > ${ROOT}/etc/rc.local
$curl -f http://169.254.169.254/latest/meta-data/public-keys/0/openssh-key >> /root/.ssh/authorized_keys
$chmod 600 /root/.ssh/authorized_keys
EOF
# delete root key
elif [ "$PRIVATE_KEY" = 'none' ]; then
$cat << EOF > ${ROOT}/etc/rc.local
$cat /dev/null > /root/.ssh/authorized_keys
EOF
fi

# Edit sshd configuration
$sed -i 's/#UseDNS yes/UseDNS no/' ${ROOT}/etc/ssh/sshd_config
$sed -i 's/#PermitRootLogin yes/PermitRootLogin without-password/' ${ROOT}/etc/ssh/sshd_config


# Add optional user account
if
    [ ! "x${USER}" = x ] && [ ! "x${PASSWORD}" = x ]
then
    $touch $ROOT/etc/shadow
    $chroot $ROOT /usr/sbin/useradd -m $USER -p $PASSWORD -G wheel
fi

# Write network configuration
cd $ROOT

$cat << EOF > etc/sysconfig/network
NETWORKING=yes
HOSTNAME=localhost.localdomain
EOF

$cat << EOF > etc/sysconfig/network-scripts/ifcfg-eth0
ONBOOT=yes
DEVICE=eth0
BOOTPROTO=dhcp
EOF

cd $WORKING_DIR

# Cleanup
sync
sleep 5
$umount ${ROOT}/proc
$umount ${ROOT}/sys
[ "$EBS" -eq 0 ] && $umount $ROOT

