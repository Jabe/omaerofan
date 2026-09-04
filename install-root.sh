#!/bin/bash
set -euo pipefail

src_bin="${1:?binary}"
src_cli="${2:-}"

install -d /usr/local/libexec
install -o root -g root -m 755 "$src_bin" /usr/local/libexec/omaerofan-ec

if [[ -n $src_cli && -f $src_cli ]]; then
  if [[ $(realpath "$src_cli") != /usr/local/bin/omaerofan ]]; then
    install -o root -g root -m 755 "$src_cli" /usr/local/bin/omaerofan
  fi
fi

cat >/etc/sudoers.d/omaerofan <<'EOF'
%wheel ALL=(root) NOPASSWD: /usr/local/libexec/omaerofan-ec
EOF
chmod 440 /etc/sudoers.d/omaerofan
visudo -cf /etc/sudoers.d/omaerofan >/dev/null

cat >/etc/modprobe.d/omaerofan.conf <<'EOF'
options ec_sys write_support=1
EOF
cat >/etc/modules-load.d/omaerofan.conf <<'EOF'
ec_sys
msr
acpi_call
EOF

# drop the previous omafan name
rm -f /usr/local/libexec/omafan-ec /usr/local/bin/omafan \
  /etc/sudoers.d/omafan /etc/modprobe.d/omafan.conf /etc/modules-load.d/omafan.conf

modprobe ec_sys write_support=1 || true
modprobe msr || true
modprobe acpi_call || true
echo "omaerofan helper installed"
