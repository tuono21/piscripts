#!/bin/bash
# pibench.sh

function usage() { echo -e "\n\tUsage: $0 test_option";
	echo -e "${c}pibench.sh - run as root (not sudo) and from a directory on the drive/partition to test${d}";
	echo "**  just a few benchmarks to compare storage media r/w speeds and pi models/overclocking **";
	echo " all - for all tests (disk,cpu,mem) ~45mins!, nodisk - to skip fileio tests ~5mins, memonly - for duh";
	exit -1; }

b=`tput setaf 3`
c=`tput setaf 6`
d=`tput sgr0`

test="$1"

if [[ -z "$test" ]]; then
  usage
fi

if (( EUID != 0 )); then
  echo -e "\n\tERROR: You need to be running as root.\n"
  exit -1
fi

if [[ "$(which sysbench)" != "/usr/local/bin/sysbench" ]]; then
  echo "WARNING: sysbench 1.1.0+ is not installed."
  echo "This script expects the latest sysbench 1.1.0+ to be compiled - not the old distro version in the repos"
  echo "The newer version has different command options that are used in this script"
  exit -2
fi

function clear { sleep 1; }

case $1 in
	all)

echo -e "\nFirst run a background script to clear disk buffer every 1/4 second"
echo "Then remount / filesystem with sync option"

while true; do sysctl -q -w vm.drop_caches=3; sleep 0.25; done &
pid=$!

mount -o remount,sync /

echo -e "\npibench testing started at: $(date)"
echo -e "${b}Running disk tests in directory: `pwd`${d}"
echo -e "${c}\ndd - write and read - one 512MB test file with 1MB r/w block size${d}"
echo -e "${b}vvvvv dd - WRITE 512MB test file all zeros vvvvv${d}"
rm tempfile > /dev/null 2>&1
clear
dd if=/dev/zero of=tempfile bs=1MiB count=512 conv=fsync oflag=noatime 2>&1 | grep -v records

echo -e "${b}vvvvv dd - READ vvvvv${d}"
clear
dd if=tempfile of=/dev/null bs=1MiB count=512 2>&1 | grep -v records

echo -e "${c}vvvvv Copy dd's 512MB test file to /dev/null vvvvv${d}"
clear
pv tempfile > /dev/null

echo -e "${c}\nSYSBENCH FileIO - Creating 128 test files of total size 512MB using 1MB block size and random data${d}"
sysbench fileio cleanup > /dev/null 2>&1
clear
sysbench --file-fsync-all --validate=on fileio --file-block-size=1M --file-num=128 --file-total-size=512M prepare | egrep 'real|MiB' && echo -e "${b}^^^^^ 512MB of files create time ^^^^^${d}"

echo -e "${c}vvvvv Copy SYSBENCH's 512MB of test files to /dev/null vvvvv${d}"
clear
pv test* > /dev/null

echo -e "${b}Each SYSBENCH test will run for 20 seconds - random and sequential running one thread${d}"
clear
sysbench --time=20 fileio --file-block-size=16K --file-num=128 --file-total-size=512M --file-test-mode=rndrd run | grep read: && echo -e "${b}^^^^^ 16KB blocksize random READ ^^^^^${d}"

clear
sysbench --time=20 fileio --file-block-size=1M --file-num=128 --file-total-size=512M --file-test-mode=seqrd run | grep read: && echo -e "${b}^^^^^ 1MB blocksize sequential READ ^^^^^${d}"

clear
sysbench --file-fsync-all --time=20 fileio --file-block-size=64K --file-num=128 --file-total-size=512M --file-test-mode=rndwr run | grep write: && echo -e "${b}^^^^^ 64KB blocksize random WRITE - this one very tough on slow devices ^^^^^${d}"

clear
sysbench --file-fsync-all --time=20 fileio --file-block-size=1M --file-num=128 --file-total-size=512M --file-test-mode=seqwr run | grep write: && echo -e "${b}^^^^^ 1MB blocksize sequential WRITE ^^^^^${d}"


mkdir /tmp/ram 2>&1 > /dev/null
mount -t tmpfs -o size=256m ramdisk /tmp/ram
echo -e "${c}\nFinally a real-world small file copy test to compare with the sysbench and dd tests above"
echo -e "It will collect ~5000 files from the root filesystem between 4k and 64k and then time copying them"
echo -e "to and from a ram tmpfs${d}"
rm -rf /tmp/ram/small_test_files 2>&1 > /dev/null
rm -rf small_test_files 2>&1 > /dev/null
mkdir /tmp/ram/small_test_files
mkdir small_test_files
find / -mount -not \( -path $(pwd) -prune \) -type f -size +4k -size -64k | head -5000 | xargs -I % cp % /tmp/ram/small_test_files/ 
echo -e "$(du -bs /tmp/ram/small_test_files/) - size of all $(ls -l /tmp/ram/small_test_files/|wc -l) files in bytes"
echo -e "${b}Collection to RAM tempdir complete... now begin timed WRITE copy test to $(pwd) from RAM${d}"
clear
rsync -Whhh --stats /tmp/ram/small_test_files/* small_test_files/ | egrep 'bytes/sec|transferred:'
clear
echo -e "${b}clear RAM tmpfs and begin timed READ copy test from $(pwd) to RAM${d}"
rm -rf /tmp/ram/small_test_files/*
rsync -Whhh --stats small_test_files/* /tmp/ram/small_test_files/ | egrep 'bytes/sec|transferred:'

echo -e "${c}\nDisk testing complete. Killing background buffer clearing script pid $pid ${d}"
kill $pid
echo "${b}remounting / filesystem with default options from fstab${d}"
mount -o remount /
echo "${b}Cleaning up... delete all test files${d}"
rm tempfile

sysbench fileio cleanup

rm -rf /tmp/ram/small_test_files
rm -rf small_test_files

echo "${b}remove tmpfs in ram${d}"
umount /tmp/ram
rmdir /tmp/ram/
date
exit

;&

	nodisk)

echo -e "${c}SYSBENCH CPU tests - 30 second prime number calc 1 and 4 threads${d}"

sleep 1
sysbench --threads=1 --time=30 cpu run | grep "events per second:" && echo -e "${b}^^^^^ cpu prime threads=1 ^^^^^${d}"
sleep 1
sysbench --threads=4 --time=30 cpu run | grep "events per second:" && echo -e "${b}^^^^^ cpu prime threads=4 ^^^^^${d}"
;&

	memonly)

echo -e "${c}SYSBENCH Read memory tests - 100GB${d}"

sleep 1
sysbench --threads=1 memory --memory-block-size=1K  --memory-oper=read run | grep MiB/s && echo -e "${b}^^^^^ 1KB memory read threads=1 ^^^^^${d}"
sleep 1
sysbench --threads=1 memory --memory-block-size=16K  --memory-oper=read run | grep MiB/s && echo -e "${b}^^^^^ 16KB memory read threads=1 ^^^^^${d}"
sleep 1
sysbench --threads=1 memory --memory-block-size=64K  --memory-oper=read run | grep MiB/s && echo -e "${b}^^^^^ 64KB memory read threads=1 ^^^^^${d}"
sleep 1
sysbench --threads=1 memory --memory-block-size=256K  --memory-oper=read run | grep MiB/s && echo -e "${b}^^^^^ 256KB memory read threads=1 ^^^^^${d}"
sleep 1
sysbench --threads=1 memory --memory-block-size=1M  --memory-oper=read run | grep MiB/s && echo -e "${b}^^^^^ 1MiB memory read threads=1 ^^^^^${d}"

echo -e "${c}SYSBENCH Write memory tests - 100GB${d}"
sleep 1
sysbench --threads=1 memory --memory-block-size=1K  --memory-oper=write run | grep MiB/s && echo -e "${b}^^^^^ 1KB memory write threads=1 ^^^^^${d}"
sleep 1
sysbench --threads=1 memory --memory-block-size=16K  --memory-oper=write run | grep MiB/s && echo -e "${b}^^^^^ 16KB memory write threads=1 ^^^^^${d}"
sleep 1
sysbench --threads=1 memory --memory-block-size=64K  --memory-oper=write run | grep MiB/s && echo -e "${b}^^^^^ 64KB memory write threads=1 ^^^^^${d}"
sleep 1
sysbench --threads=1 memory --memory-block-size=256K  --memory-oper=write run | grep MiB/s && echo -e "${b}^^^^^ 256KB memory write threads=1 ^^^^^${d}"
sleep 1
sysbench --threads=1 memory --memory-block-size=1M  --memory-oper=write run | grep MiB/s && echo -e "${b}^^^^^ 1MiB memory write threads=1 ^^^^^${d}"
;&

	*)
echo -e "Testing ended at: $(date)"
;;

esac

