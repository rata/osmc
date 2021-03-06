#!/bin/sh

# (c) 2014-2015 Sam Nazarko
# email@samnazarko.co.uk

# Device specific settings and defaults

print_message()
{
	# Prints a message that won't be trimmed by overscan and will be visible
	echo -e "\n\n\n\n\nOSMC initrd\n\n${1}"
}

OPTION_DO_FSCK="1"
OPTION_ROOT="/dev/mmcblk0p2"
OPTION_ROOTDELAY="0"
OPTION_FILESYSTEM="ext4"
OPTION_INIT="/sbin/splash_early"
OPTION_MOUNT_OPTIONS="-o "
OPTION_MOUNT_PATH="/real_root"

# Set up our mounts

/bin/busybox mount -t devtmpfs devtmpfs /dev
/bin/busybox mount -t proc proc /proc
/bin/busybox mount -t sysfs sysfs /sys

# A nicer console

echo 0 > /sys/devices/virtual/graphics/fbcon/cursor_blink
echo 0 > /proc/sys/kernel/printk
clear

# Set up device nodes

echo /sbin/mdev > /proc/sys/kernel/hotplug 
mdev -s 

# Read /proc/cmdline and find out what we're doing.

for option in $(cat /proc/cmdline); do
	case $option in
	  rootdelay=*)
	    OPTION_ROOTDELAY="${arg#*=}"
	    ;;
	  root=*
		OPTION_ROOT="${arg#*=}"
		;;
	  rootfstype=*
		OPTION_FILESYSTEM="${arg#*=}"
		;;
	  init=*
		OPTION_INIT="${arg#*=}"
		;;
	  nfsroot=*
		OPTION_BOOTS_NFS="1"
		OPTION_DO_FSCK="0"
		# To be completed
		;;
	  nofsck)
		OPTION_DO_FSCK="0"
		;;	
	  osmcrescue)
		/bin/sh
		;;
	 esac
done

# Should we check the filesystem?

if [ "$OPTION_DO_FSCK" -eq 1 ]
then
	# Verify filesystem integrity
	FSCK_BIN="/bin/e2fsck"
	if [ -f /bin/fsck.${OPTION_FILESYSTEM}]; then FSCK_BIN="/bin/fsck.${OPTION_FILESYSTEM}"; fi
	$FSCK_BIN -a "$OPTION_ROOT" >/dev/null 2>&1
	fsck_result="$?"
	# 0 == no error
	# 1 == filesystem errors corrected
	# 2 == reboot needed
	# 4 == not fully repaired. need to force.
	if [ "$fsck_result" -eq 2 ]
	then
		print_message "OSMC has repaired some filesystem corruption on your system and needs to reboot"
		sleep 10
		/bin/busybox reboot
	fi
		if [ "$fsck_result" -eq 4 ]
	then
		print_message "OSMC is significantly corrupted. We will our best to repair this system"
		sleep 5
		$FSCK_BIN -y
		fsck_result="$?"
		if [ "$fsck_result" -eq 8 ]
		then
			# We are broken for good
			print_message "OSMC cannot repair the filesystem. Please re-install OSMC from osmc.tv/download"
			while true
			do
				sleep 1
			done
		fi
		print_message "OSMC has repaired your filesystem"
		sleep 10
	fi
fi

# Let's set up the new mountpoint and move our mounts over

mkdir -p "$OPTION_MOUNT_PATH"
/bin/busybox mount --move /dev /sysroot/dev
/bin/busybox mount --move /proc /sysroot/proc
/bin/busybox mount --move /sys /sysroot/sys

# Deactivate the hotplugger. systemd will take over
echo "" > /proc/sys/kernel/hotplug

# Let's try and mount

/bin/busybox mount "$OPTION_ROOT" "$OPTION_MOUNT_PATH" "$OPTION_MOUNT_OPTIONS" "$OPTION_FILESYSTEM"
mount_result="$?"
if [ "$mount_result" -eq 0 ]
then
	# If we checked the filesystem, tell systemd
	if [ "$OPTION_DO_FSCK" -eq 1 ]
	then
	mkdir -p "$OPTION_MOUNT_PATH"/run/initramfs
	touch "$OPTION_MOUNT_PATH"/run/initramfs/fsck-root
	fi
	exec switch_root "$OPTION_MOUNT_PATH" "$OPTION_INIT"
else
	print_message "OSMC cannot mount $OPTION_ROOT of $OPTION_FILESYSTEM filesystem"
	# Drop to a shell
	/bin/sh
fi
