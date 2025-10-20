#!/bin/bash

#TODO colors, loopback cleanup doesnt catch first CTRL-C remove ERR and just EXIT and move back up above fist CTRL-C msg
function cleanup() {
  if losetup $loopback &>/dev/null ; then
	losetup -d "$loopback"
	echo "Cleanup removed loop device"
  else
	echo "Cleanup found no loop device"
  fi
}

usage() { echo -e "\n\tUsage: $0 imagefile.img [newimagefile.img]"; exit -1; }

bold=$(tput bold)
blink=$(tput blink)
so=$(tput smso) 
off=$(tput sgr0)

#Args
img="$1"

loopback="nada"

#Usage checks
echo -e "\n\tShrink started at: \c"; date
if [[ -z "$img" ]]; then
  usage
fi
if [[ ! -f "$img" ]]; then
  echo "ERROR: $img is not a file..."
  exit -2
fi
if (( EUID != 0 )); then
  echo "ERROR: You need to be running as root."
  exit -3
fi

#Check that what we need is installed
for command in pv parted losetup tune2fs md5sum e2fsck resize2fs; do
  which $command 2>&1 >/dev/null
  if (( $? != 0 )); then
    echo "ERROR: $command is not installed."
    exit -4
  fi
done

#Copy to new file if requested
if [ -n "$2" ]; then
  echo "Copying $1 to $2..."
#  cp --reflink=auto --sparse=always "$1" "$2"
  pv "$1" > "$2"
  if (( $? != 0 )); then
    echo "ERROR: Could not copy file..."
    exit -5
  fi
  old_owner=$(stat -c %u:%g "$1")
  chown $old_owner "$2"
  img="$2"
fi

origsizeimgls=$(ls -l "$img" | cut -d ' ' -f 5)
origsizeimgparted=$(parted -ms "$img" unit B print free | tail -1)

if [[ -z $(echo "$origsizeimgparted" | grep free - ) ]] ; then
	origsizeimgparted=$(($(echo "$origsizeimgparted" | cut -d ':' -f 3 | tr -d 'B') + 1))
else 
  echo "The last partition in the image file is followed by free space."
  echo "This may be ok but check later output carefully before committing to resize."
  origsizeimgparted=$(($(parted -ms "$img" unit B print | tail -1 | cut -d ':' -f 3 | tr -d 'B') + 1))
fi

parted_output=$(parted -ms "$img" unit B print | tail -n 1)
partnum=$(echo "$parted_output" | cut -d ':' -f 1)
if [[ $partnum != 2 ]]; then echo "ERROR: This scripts expects two standard raspios partitions, but there appears to be $partnum partitions in the image file partition table.\nNOOBS images not supported" ; exit -5 ; fi
partstart=$(echo "$parted_output" | cut -d ':' -f 2 | tr -d 'B')
loopback=$(losetup -f --show -o $partstart "$img")
tune2fs_output=$(tune2fs -l "$loopback")
currentsize=$(echo "$tune2fs_output" | grep '^Block count:' | tr -d ' ' | cut -d ':' -f 2)
blocksize=$(echo "$tune2fs_output" | grep '^Block size:' | tr -d ' ' | cut -d ':' -f 2)
originalbytes=$(($currentsize * $blocksize))

echo "These details are first determined for the unmodified img file and the rootfs partition within"
echo -e "\nThe $img image file is the following size in bytes : $(printf "%'.f" $origsizeimgls)"
echo "The img partition table lists bytes used by both partitions as : $(printf "%'.f" $origsizeimgparted)"
echo -e "\nrootfs partition number (should be 2): $partnum"
#echo "rootfs partition starts at byte  : $(printf "%'.f" $partstart)"
echo "current size of rootfs (Blocks)  : $(printf "%'.f" $currentsize)"
echo "blocksize of rootfs (Bytes)         : $blocksize"


echo -e "\nReview details above carefully before proceeding!"
echo -e "\nThe next step is to check and fix the img filesystem, if needed."
echo -e "This MAY modify the original img if a copy wasn't made earlier - careful...\n"
read -p "Press enter to continue or Ctrl-C to quit"

#Make sure filesystem is ok
echo -e "\nChecking rootfs filesystem within img file for errors..."
e2fsck -p -f -v "$loopback"
case "$?" in
	0) echo "No filesystem errors detected" ;;
	1) echo "Filesystem errors corrected. Proceeding..." ;;
	*) echo "Errors detected. Check img file manually."
	   exit -6;;	
esac

# cleanup at script exit
trap cleanup ERR EXIT

initreserved=$(echo "$tune2fs_output" | grep 'Reserved block count' | tr -d ' ' | cut -d ':' -f 2)
initfree=$(echo "$tune2fs_output" | grep 'Free blocks' | tr -d ' ' | cut -d ':' -f 2)
echo -e "\ntune2fs reports $(printf "%'.f" $initreserved) reserved blocks or $(printf "%'.f" $(($initreserved * $blocksize))) bytes"
echo -e "            and $(printf "%'.f" $initfree) free blocks or $(printf "%'.f" $(($initfree * $blocksize))) bytes"
echo -e "tune2fs usable free bytes would be: $(printf "%'.f" $((($initfree - $initreserved) * $blocksize)))\n"

mkdir tmpmnt
mount "$loopback" tmpmnt
cd tmpmnt
originalbytesfree=$(df --output=avail -B 1 "$PWD" |tail -n 1)
cd ..
umount "$PWD/tmpmnt"
rmdir tmpmnt
echo -e "Mounting the rootfs partition showed $(printf "%'.f" $originalbytesfree) free bytes\n"

echo "Checking on minimum possible size of rootfs filesystem..."
minsize=$(resize2fs -P "$loopback" | cut -d ':' -f 2 | tr -d ' ')
echo "Minimum size possible of rootfs (Blocks) : $(printf "%'.f" $minsize)"
echo "This would reduce the total size of the image file by $(printf "%'.f" $((($currentsize - $minsize) * $blocksize))) bytes"
if [[ $currentsize -eq $minsize ]]; then
  echo -e "\nThis image is already the smallest size possible even if free space is reported above"
  echo "There are two options - if free blocks is just enough to make the img fit your storage device,"
  echo "the create new option can be used to rsync copy all files to a new img file - NOT READY YET"
  echo "Or - the img can be mounted and large files temporarily moved to a temp location on your PC."
  echo -e "This script can then be run again. CD game images in rom folders are probably easiest."
  echo "example:"
  echo " # mkdir /mnt/tmp"
  echo " # losetup -f --show -P $img"
  echo " # mount /dev/loopXp2 /mnt/tmp"
  echo "(remove files from /mnt/tmp/home/pi/Retro-Pie/roms/somewhere for example)"
  echo " # umount /mnt/tmp"
  echo " # losetup -d /dev/loopX"
  echo -e "Then rerun script...\n"
  exit -8
fi

echo -e "\nReview details above carefully before proceeding!"
read -p "Press enter to continue or Ctrl-C to quit"

if [[ $initreserved -gt 5000 || $initreserved -lt 1024 ]]; then
echo -e "\nSetting reserved blocks to 10MB to maximize available space but leave"
echo " a little buffer once the img is expanded again"
tune2fs -r 2560 "$loopback"
  if (( $? != 0 )); then
    echo "ERROR: Could not set reserved blocks..."
    exit -7
  fi
fi

echo -e "\nChecking rootfs filesystem within img file for errors again after mounting..."
e2fsck -p -f "$loopback"
case "$?" in 
        0) echo "No filesystem errors detected" ;;
        1) echo "Filesystem errors corrected. Proceeding..." ;;
        *) echo "Errors detected. Check img file manually."
           exit -6;;    
esac       

echo -e "\nShrink filesystem..."
resize2fs -p "$loopback" $minsize
if [[ $? != 0 ]]; then
  echo "ERROR: resize2fs failed..."
  exit -10
fi
sleep 3

echo -e "Shrink partition..."
tune2fs_output=$(tune2fs -l "$loopback")
currentsize=$(echo "$tune2fs_output" | grep '^Block count:' | tr -d ' ' | cut -d ':' -f 2)
oldnewsize=$(($minsize * $blocksize))
partnewsize=$(($currentsize * $blocksize))
newpartend=$(($partstart + $partnewsize))
echo "Original partition size (Bytes)  : $(printf "%'.f" $originalbytes)"
echo "OLD method would have reported new size as:$(printf "%'.f" $oldnewsize)"
echo "New partition size (Bytes)       : $(printf "%'.f" $partnewsize)"
#echo "newpartend (Bytes)        : $newpartend"
parted -s -a minimal "$img" rm $partnum #>/dev/null
parted -s "$img" unit B mkpart primary $partstart $newpartend #>/dev/null

echo -e "\nTruncate the img file..."
endresult=$(parted -ms "$img" unit B print free | tail -1 | cut -d ':' -f 2 | tr -d 'B')
truncate -s $endresult "$img"
aftersize=$(ls -l "$img" | cut -d ' ' -f 5)
echo -e "Original full img file (Bytes) : $(printf "%'.f" $origsizeimgls)"
echo -e "New full img file (Bytes)      : $(printf "%'.f" $aftersize)"
echo -e "\nShrink ended at: $(date)\n"
