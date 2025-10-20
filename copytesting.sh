function clear { sync; sleep 2; sysctl -q -w vm.drop_caches=3; sleep 5; }
 
echo -e "${c}Finally a real-world small file copy test to compare with the random sysbench write test above"
echo -e "It will collect all files in the root filesystem between 4k and 64k and then copy them to a second test directory${d}"
rm -rf small_test_files2 2>&1 > /dev/null
rm -rf small_test_files 2>&1 > /dev/null
mkdir small_test_files2
mkdir small_test_files
clear
find / -mount -not \( -path $(pwd) -prune \) -type f -size +4k -size -64k -exec cp '{}' small_test_files/ \;
#echo -e "$(cd small_test_files;du -bs;cd ..) - size of all files in bytes"
echo "Collection to tempdir1 complete... now begin timed copy test to tempdir2"
clear
rsync -Whhh --stats small_test_files/* small_test_files2/ | egrep 'bytes/sec|transferred:'
rm -rf small_test_files2
rm -rf small_test_files
