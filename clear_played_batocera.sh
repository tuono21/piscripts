#!/bin/sh
#clear_played_batocera.sh

for f in /media/user/SHARE/roms/**/gamelist.xml
do
echo "file: $f"
grep -e lastplayed -e playcount -v $f > "$f.tmp"
mv -f "$f.tmp" $f
done

