#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Build and install a native (no Rosetta) driver for HP LaserJet Pro "-z2"
# ZjStream printers on macOS, then create a CUPS print queue for the printer.
#
# Usage: ./install.sh [--ip ADDRESS] [--paper A4|Letter|Legal] [--name QUEUE] [--test] [--dry-run]
set -euo pipefail

PREFIX=/Library/Printers/foo2zjs
REPO="$(cd "$(dirname "$0")" && pwd)"
IP="" PAPER="" QUEUE="" TEST=0 DRY_RUN=0

usage() { sed -n '3,6p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }
die()   { echo "error: $*" >&2; exit 1; }
info()  { echo "==> $*"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --ip)    IP="${2:?}"; shift 2 ;;
    --paper) PAPER="${2:?}"; shift 2 ;;
    --name)  QUEUE="${2:?}"; shift 2 ;;
    --test)  TEST=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage ;;
    *) echo "unknown option: $1" >&2; usage 1 ;;
  esac
done

[ "$(uname -s)" = Darwin ] || die "this installer is for macOS"
xcode-select -p >/dev/null 2>&1 || die "Xcode Command Line Tools are required. Run: xcode-select --install"

# Sends a PJL INFO ID request to port 9100 and prints the model string.
pjl_id() {
  printf '\033%%-12345X@PJL INFO ID\r\n\033%%-12345X' \
    | nc -w 3 "$@" 9100 2>/dev/null \
    | tr -d '\r\f"' | grep -v -e '^@PJL' -e '^[[:space:]]*$' | head -1 || true
}

model_for_id() {
  case "$1" in
    *M12a*)   echo "HP LaserJet Pro M12a" ;;
    *M12w*)   echo "HP LaserJet Pro M12w" ;;
    *P1102w*) echo "HP LaserJet Pro P1102w" ;;
    *P1102*)  echo "HP LaserJet Pro P1102" ;;
    *P1566*)  echo "HP LaserJet Pro P1566" ;;
    *P1606*)  echo "HP LaserJet Pro P1606dn" ;;
    *) return 1 ;;
  esac
}

IFACE="$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')"

if [ -z "$IP" ]; then
  MYIP="$(ipconfig getifaddr "$IFACE" 2>/dev/null || true)"
  [ -n "$MYIP" ] || die "could not determine the local network; pass --ip ADDRESS"
  NET="${MYIP%.*}"
  info "Scanning $NET.0/24 for printers on port 9100..."
  CANDIDATES="$(
    for i in $(seq 1 254); do
      ( nc -z -G 1 -w 1 "$NET.$i" 9100 >/dev/null 2>&1 && echo "$NET.$i" ) &
    done; wait
  )"
  for c in $CANDIDATES; do
    id="$(pjl_id "$c")"
    if model_for_id "$id" >/dev/null; then IP="$c"; break; fi
    [ -n "$id" ] && echo "    $c: $id (not supported)"
  done
  [ -n "$IP" ] || die "no supported printer found. Make sure it is on and on this network, or pass --ip ADDRESS"
fi

ID="$(pjl_id "$IP")"
[ -n "$ID" ] || die "no answer from $IP:9100. Is the printer on and reachable?"
MODEL="$(model_for_id "$ID")" || die "$IP reports '$ID', which is not a supported model"
info "Found $MODEL at $IP"

# Prefer the IPv6 link-local address derived from the printer MAC (EUI-64): it
# never changes, so the queue keeps working when DHCP hands out a new IPv4.
URI="socket://$IP:9100"
MAC="$(arp -n "$IP" 2>/dev/null | awk '{print $4}')"
if [ -n "$MAC" ] && [ -n "$IFACE" ] && [[ "$MAC" == *:*:*:*:*:* ]]; then
  IFS=: read -r o1 o2 o3 o4 o5 o6 <<< "$MAC"
  LL="$(printf 'fe80::%x:%xff:fe%x:%x' \
        $(( (0x$o1 ^ 0x02) << 8 | 0x$o2 )) $((0x$o3)) $((0x$o4)) $(( 0x$o5 << 8 | 0x$o6 )))"
  if [ -n "$(pjl_id -6 "$LL%$IFACE")" ]; then
    URI="socket://[$LL%25$IFACE]:9100"
    info "Using stable IPv6 link-local address $LL (survives IPv4 changes)"
  fi
fi

if [ -z "$PAPER" ]; then
  case "$(defaults read -g AppleLocale 2>/dev/null || true)" in
    *_US*|*_CA*|*_MX*|*_PH*) PAPER=Letter ;;
    *) PAPER=A4 ;;
  esac
fi
case "$PAPER" in A4|Letter|Legal) ;; *) die "--paper must be A4, Letter or Legal" ;; esac
[ -n "$QUEUE" ] || QUEUE="$(echo "$MODEL" | tr ' ' '_')_foo2zjs"

info "Building..."
make -C "$REPO" >/dev/null

PPD="$(mktemp -t foo2zjs-ppd)"
trap 'rm -f "$PPD"' EXIT
sed -e "s|@MODEL@|$MODEL|g" -e "s|@PAPER@|$PAPER|g" -e "s|@PREFIX@|$PREFIX|g" \
  "$REPO/ppd/foo2zjs-z2.ppd.in" > "$PPD"

if [ "$DRY_RUN" = 1 ]; then
  echo "Dry run: would install to $PREFIX and create queue '$QUEUE' ($MODEL, $PAPER) -> $URI"
  exit 0
fi

info "Installing to $PREFIX (administrator password required)..."
sudo mkdir -p "$PREFIX"
sudo install -o root -g wheel -m 755 \
  "$REPO/build/foo2zjs" "$REPO/build/rastertopbm" "$REPO/build/rastertozjs-foo2zjs" "$PREFIX/"
sudo install -o root -g wheel -m 644 "$PPD" "$PREFIX/foo2zjs-z2.ppd"

info "Creating print queue '$QUEUE' -> $URI"
sudo lpadmin -p "$QUEUE" -E -D "$MODEL (foo2zjs)" -L "$IP" -v "$URI" -P "$PREFIX/foo2zjs-z2.ppd"
sudo lpadmin -p "$QUEUE" -o PageSize="$PAPER" -o printer-is-shared=false

if [ "$TEST" = 1 ]; then
  info "Printing a test page..."
  printf '%s\n\nfoo2zjs native macOS driver test page.\nIf you can read this, printing works.\n\nABCDEFGHIJKLMNOPQRSTUVWXYZ\n0123456789\n' "$MODEL" \
    | lp -d "$QUEUE" -t "foo2zjs test page" >/dev/null
fi

echo
echo "Done. Select \"$MODEL (foo2zjs)\" when printing."
[ "$TEST" = 1 ] || echo "Print a test page with: ./install.sh --test, or: echo hello | lp -d $QUEUE"
