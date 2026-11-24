# hp-laserjet-zjs-macos

A native macOS printer driver for HP LaserJet Pro printers that use the
**ZjStream** protocol, such as the **LaserJet Pro M12w**. It runs on Apple
silicon without Rosetta.

## Why

HP's official macOS driver for these printers (`hpRaster.bundle/rastertozjs`)
is Intel-only and was last updated in 2016. Today it only works through
Rosetta 2, and Apple has announced that **macOS 28 will stop running Intel
apps**. After that, printing stops. These printers don't support AirPrint, so
there is no built-in fallback.

This project wraps the open source [foo2zjs](https://foo2zjs.linkevich.net/foo2zjs/)
driver in a CUPS filter that macOS can use natively.

## Supported printers

| Printer                    | Status                         |
|----------------------------|--------------------------------|
| HP LaserJet Pro M12w       | ✅ Tested (macOS 27, Apple M-series) |
| HP LaserJet Pro M12a       | Should work (untested)         |
| HP LaserJet Pro P1102      | Should work (untested)         |
| HP LaserJet Pro P1102w     | Should work (untested)         |
| HP LaserJet Pro P1566      | Should work (untested)         |
| HP LaserJet Pro P1606dn    | Should work (untested)         |

All of these use foo2zjs's `-P -z2 -L0` mode. If you test one of the untested
models, please open an issue or PR to update the table.

**Network printers only.** The installer finds the printer over the network
(port 9100). USB connections are not supported yet.

## Requirements

- macOS on Apple silicon or Intel. The build is universal.
- Xcode Command Line Tools (`xcode-select --install`), used to compile the driver.
- The printer is turned on and connected to the same network as the Mac.

## Install

```sh
git clone https://github.com/leoasson/hp-laserjet-zjs-macos.git
cd hp-laserjet-zjs-macos
./install.sh --test
```

The installer:

1. Scans your local network for a supported printer. It asks each device on
   port 9100 for its model over PJL.
2. Builds `foo2zjs` and the CUPS filter.
3. Installs them to `/Library/Printers/foo2zjs`. This step asks for your
   administrator password.
4. Creates a print queue, and with `--test` prints a test page.

Then pick **"HP LaserJet Pro M12w (foo2zjs)"**, or your model, in any print dialog.

### Options

| Option | Description |
|---|---|
| `--ip ADDRESS` | Skip the network scan and use this printer address |
| `--paper A4\|Letter\|Legal` | Default paper size. Defaults to Letter in the US, Canada, Mexico and the Philippines, A4 elsewhere |
| `--name QUEUE` | CUPS queue name. Default: `HP_LaserJet_Pro_<model>_foo2zjs` |
| `--test` | Print a test page after installing |
| `--dry-run` | Detect the printer and show what would be installed, without changing anything |

## The printer's IP address can change

Routers usually hand out IP addresses dynamically, so a printer's IPv4 address
can change after a reboot. To handle this, the installer computes the
printer's **IPv6 link-local address** (`fe80::…`) from its MAC address. That
address never changes. If the printer answers on it, the queue uses that
address instead of the IPv4 one.

If the printer doesn't answer over IPv6, the queue uses the IPv4 address. In
that case, either reserve the address for the printer in your router (look for
"DHCP reservation" or "static lease"), or re-run `./install.sh` when the
address changes.

These printers often aren't discoverable through Bonjour/AirPrint. On many home
networks their mDNS announcements don't come through, which is why the
installer talks to the printer directly instead.

## How it works

```
app ──PDF──▶ macOS CUPS ──CUPS raster (600 dpi, 1-bit)──▶ rastertozjs-foo2zjs
                                                             │
                                  rastertopbm (CUPS raster → PBM)
                                                             │
                                  foo2zjs -P -z2 -L0 (PBM → ZjStream)
                                                             │
                                            socket://printer:9100
```

- `src/rastertopbm.c` is a small converter from CUPS raster to PBM, linked
  against the system `libcups`. macOS renders the page and handles
  halftoning, so Ghostscript isn't needed.
- `src/rastertozjs-foo2zjs` is the CUPS filter. It picks the paper code
  foo2zjs sends to the printer (Letter, A4 or Legal) from the page height.
- `third_party/foo2zjs/` contains the unmodified foo2zjs and jbig-kit sources
  needed to build the `foo2zjs` binary.
- `ppd/foo2zjs-z2.ppd.in` is the printer description template that the
  installer fills in for your model.

## Troubleshooting

- **"no supported printer found"**: Check that the printer is on and connected
  to the same network as the Mac, then try `./install.sh --ip <printer-ip>`.
  The printer's IP address is on its configuration page. On the M12w, hold the
  wireless button for about 10 seconds to print it.
- **The job is sent, but nothing prints**: Check the CUPS log with
  `grep rastertozjs /var/log/cups/error_log`, or run `cupsctl --debug-logging`
  to get more detail.
- **The right edge is cut off**: The queue's paper size doesn't match the
  paper loaded. Change it in the print dialog, or re-install with `--paper`.

## Uninstall

```sh
./uninstall.sh
```

This removes every print queue that uses this driver, then removes
`/Library/Printers/foo2zjs`.

## License

GPL-2.0-or-later. See [LICENSE](LICENSE).

foo2zjs is © Rick Richardson and contributors, and jbig-kit is © Markus Kuhn.
Both are GPL-2.0-or-later. See [third_party/foo2zjs/README.md](third_party/foo2zjs/README.md).
This project is not affiliated with or endorsed by HP Inc.
