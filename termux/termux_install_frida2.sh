#!/system/bin/sh
# termux_install_frida2.sh - install python + frida-tools inside Termux
PREFIX=/data/data/com.termux/files/usr
HOME=/data/data/com.termux/files/home
export PREFIX HOME
export PATH=$PREFIX/bin:$PATH
echo "--- install python ---"
apt install -y python 2>&1 | tail -6
echo "--- verify python ---"
which python pip 2>&1
python --version 2>&1
echo "--- pip install frida-tools ---"
pip install frida-tools 2>&1 | tail -12
echo "--- verify frida ---"
which frida 2>&1
frida --version 2>&1
