@echo off
echo CLI ONLY! Shells will fail...

rename GL*.LRV GX*.MOV

echo renamed LRV files to MOV - PAUSED in case filename changes need to be duplicated to have filenames match before copying to proxy folder
pause

if not exist \proxy\NUL mkdir "proxy\"
move *.MOV proxy\

mkdir thumbnails
move *.thm thumbnails

echo proxy files renamed and moved to proxy subfolder - same with thumbnails