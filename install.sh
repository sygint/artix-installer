#!/bin/sh -e
#
# A simple installer for Artix Linux
#
# Copyright (c) 2022 Maxwell Anderson
#
# This file is part of artix-installer.
#
# artix-installer is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# artix-installer is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with artix-installer. If not, see <https://www.gnu.org/licenses/>.

confirm_password() {
	stty -echo
	until [ "$pass1" = "$pass2" ] && [ "$pass2" ]; do
		printf "%s: " "$1" >&2 && read -r pass1 && printf "\n" >&2
		printf "confirm %s: " "$1" >&2 && read -r pass2 && printf "\n" >&2
	done
	stty echo
	echo "$pass2"
}

# Load keymap
until grep -q "^#*$LANGCODE\.UTF-8 UTF-8  $" /etc/locale.gen; do
	printf "Language (en_US, de_DE, etc.): " && read -r LANGCODE
	[ ! "$LANGCODE" ] && LANGCODE="en_US"
done
case "$LANGCODE" in
"en_GB")
	MY_KEYMAP="uk"
	;;
"en_US")
	MY_KEYMAP="us"
	;;
*)
	MY_KEYMAP=$(echo "$LANGCODE" | cut -c1-2)
	;;
esac
sudo loadkeys "$MY_KEYMAP"

# Check boot mode
[ ! -d /sys/firmware/efi ] && printf "Not booted in UEFI mode. Aborting..." && exit 1

# Choose MY_INIT
until [ "$MY_INIT" = "openrc" ] || [ "$MY_INIT" = "dinit" ]; do
	printf "Init system (openrc/dinit): " && read -r MY_INIT
	[ ! "$MY_INIT" ] && MY_INIT="openrc"
done

# Choose disk
until [ -b "$MY_DISK" ]; do
	echo
	sudo fdisk -l
	printf "\nWarning: the selected disk will be rewritten.\n"
	printf "\nDisk to install to (e.g. /dev/sda): " && read -r MY_DISK
done

PART1="$MY_DISK"1
PART2="$MY_DISK"2
case "$MY_DISK" in
*"nvme"*)
	PART1="$MY_DISK"p1
	PART2="$MY_DISK"p2
	;;
esac

# If install partition is already LUKS
if [[ $(sudo blkid -o value -s TYPE $PART2) == "crypto_LUKS" ]]; then
	until [ "$USE_EXISTING_LUKS" ]; do
		printf "$PART2 is a LUKS partition, would you like to use this instead of creating a new one? (y/N): " && read -r USE_EXISTING_LUKS
		[ ! "$USE_EXISTING_LUKS" ] && USE_EXISTING_LUKS="n"
	done
else
	USE_EXISTING_LUKS="n"
fi

# Swap size
until (echo "$SWAP_SIZE" | grep -Eq "^[0-9]+$") && [ "$SWAP_SIZE" -gt 0 ] && [ "$SWAP_SIZE" -lt 97 ]; do
	printf "Size of swap partition in GiB (4): " && read -r SWAP_SIZE
	[ ! "$SWAP_SIZE" ] && SWAP_SIZE=4
done

# Choose filesystem
until [ "$MY_FS" = "btrfs" ] || [ "$MY_FS" = "ext4" ]; do
	printf "Filesystem (btrfs/ext4): " && read -r MY_FS
	[ ! "$MY_FS" ] && MY_FS="btrfs"
done

# Encrypt or not
if [ "$USE_EXISTING_LUKS" = "n" ]; then
	until [ "$ENCRYPTED" ]; do
		printf "Encrypt? (y/N): " && read -r ENCRYPTED
		[ ! "$ENCRYPTED" ] && ENCRYPTED="n"
	done

	# Prepare Encryption or not
	until [ "$PREPARE_ENCRYPTION" ]; do
		printf "Prepare for encryption by zeroing drive? (y/N): " && read -r PREPARE_ENCRYPTION
		[ ! "$PREPARE_ENCRYPTION" ] && PREPARE_ENCRYPTION="n"
	done
fi

if [ "$USE_EXISTING_LUKS" = "y" ] || [ "$ENCRYPTED" = "y" ]; then
	MY_ROOT="/dev/mapper/root"
	CRYPTPASS=$(confirm_password "encryption password")
else
	MY_ROOT=$PART2
	[ "$MY_FS" = "ext4" ] && MY_ROOT=$PART2
fi

# Timezone
until [ -f /usr/share/zoneinfo/"$REGION_CITY" ]; do
	printf "Region/City (e.g. 'America/Denver'): " && read -r REGION_CITY
	[ ! "$REGION_CITY" ] && REGION_CITY="America/Denver"
done

# Host
until [ "$MY_HOSTNAME" ]; do
	printf "Hostname: " && read -r MY_HOSTNAME
done

# Users
ROOT_PASSWORD=$(confirm_password "root password")

# print config
echo ""
echo "-----------------------"
echo ""
echo "Confirm config:"
echo ""
echo "Installation disk destination: $MY_DISK"
echo "Boot partition: $PART1"

printf "Root partition: $PART2 ($MY_FS)"

if [ "$USE_EXISTING_LUKS" = "y" ]; then
	printf " [use existing LUKS]"
elif [ "$ENCRYPTED" = "y" ]; then
	printf " [encrypted] (pass: $CRYPTPASS)"

	if [ "$PREPARE_ENCRYPTION" = "y" ]; then
		printf " (prep)"
	fi
fi
printf "\n"
# if [ "$MY_FS" = "btrfs" ]; then
# 	echo "    subvolumes:"
# fi

echo "Swap size: $SWAP_SIZE GB"
echo ""
echo "Init system: $MY_INIT"
echo "Language: $LANGCODE"
echo "Region: $REGION_CITY"
echo "Hostname: $MY_HOSTNAME"
echo "Root password: $ROOT_PASSWORD"
echo ""
echo "-----------------------"
echo ""

until [ "$CONFIRM" ]; do
	printf "Is this correct, ready for installation? (y/N): " && read -r CONFIRM
	[ ! "$CONFIRM" ] && CONFIRM="n"
done

if [ "$CONFIRM" = "y" ]; then
	printf "\nDone with configuration. Installing...\n"

	# Install
	sudo MY_INIT="$MY_INIT" MY_DISK="$MY_DISK" PART1="$PART1" PART2="$PART2" \
		SWAP_SIZE="$SWAP_SIZE" MY_FS="$MY_FS" ENCRYPTED="$ENCRYPTED" USE_EXISTING_LUKS=$USE_EXISTING_LUKS PREPARE_ENCRYPTION=$PREPARE_ENCRYPTION MY_ROOT="$MY_ROOT" \
		CRYPTPASS="$CRYPTPASS" \
		./src/installer.sh

	# Chroot
	sudo cp src/iamchroot.sh /mnt/root/ &&
	sudo MY_INIT="$MY_INIT" PART2="$PART2" MY_FS="$MY_FS" ENCRYPTED="$ENCRYPTED" \
		REGION_CITY="$REGION_CITY" MY_HOSTNAME="$MY_HOSTNAME" CRYPTPASS="$CRYPTPASS" \
		ROOT_PASSWORD="$ROOT_PASSWORD" LANGCODE="$LANGCODE" MY_KEYMAP="$MY_KEYMAP" \
		artix-chroot /mnt sh -ec './root/iamchroot.sh; rm /root/iamchroot.sh; exit' &&
	printf '\nYou may now poweroff.\n'
else
	printf "\ninstallation cancelled\n"
fi
