#!/system/bin/sh
# termux_setup.sh - termux bootstrap helper
PREFIX=/data/data/com.termux/files/usr
HOME=/data/data/com.termux/files/home
export PREFIX HOME
export PATH=$PREFIX/bin:$PATH

# 1. switch to tuna mirror
cat > $PREFIX/etc/apt/sources.list <<'EOF'
deb https://mirrors.tuna.tsinghua.edu.cn/termux/termux-packages-24 stable main
EOF
echo "--- sources.list ---"
cat $PREFIX/etc/apt/sources.list

# 2. apt update
echo "--- apt update ---"
apt update 2>&1 | tail -5
