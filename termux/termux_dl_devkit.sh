#!/system/bin/sh
# termux_dl_devkit.sh - download frida-devkit (prebuilt) with mirror fallback chain
PREFIX=/data/data/com.termux/files/usr
HOME=/data/data/com.termux/files/home
export PREFIX HOME
export PATH=$PREFIX/bin:$PATH
cd /data/data/com.termux/files/home
URL_BASE=https://github.com/frida/frida/releases/download/17.23.3
FILE=frida-devkit-android-x86_64-17.23.3.tar.xz
for m in "" "https://gh-proxy.com/" "https://ghfast.top/" "https://ghproxy.net/" "https://mirror.ghproxy.com/" "https://github.moeyy.xyz/"; do
  echo "=== try $m ==="
  wget -T 30 -O "$FILE" "${m}${URL_BASE}/${FILE}" 2>&1 | tail -2
  if [ -f "$FILE" ] && [ $(stat -c%s "$FILE") -gt 1000000 ]; then
    echo "OK size=$(stat -c%s $FILE)"
    break
  fi
done
ls -l "$FILE" 2>/dev/null
