#!/system/bin/sh
# termux_try_frida.sh - diagnose pip/build issues inside Termux
PREFIX=/data/data/com.termux/files/usr
HOME=/data/data/com.termux/files/home
export PREFIX HOME
export PATH=$PREFIX/bin:$PATH
echo "--- try pkg install frida ---"
apt install -y frida 2>&1 | tail -5
echo "--- make? ---"
which make gcc clang cargo 2>&1
echo "--- pip frida verbose tail ---"
pip install frida 2>&1 | tail -20
