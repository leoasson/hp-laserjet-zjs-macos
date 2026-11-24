#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Remove every print queue that uses this driver, then the driver itself.
set -euo pipefail

PREFIX=/Library/Printers/foo2zjs

for q in $(lpstat -p 2>/dev/null | awk '/^printer/{print $2}'); do
  if grep -q "$PREFIX/rastertozjs-foo2zjs" "/etc/cups/ppd/$q.ppd" 2>/dev/null; then
    echo "==> Removing print queue $q"
    sudo lpadmin -x "$q"
  fi
done

if [ -d "$PREFIX" ]; then
  echo "==> Removing $PREFIX"
  sudo rm -rf "$PREFIX"
fi
echo "Done."
