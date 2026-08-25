# Omaerofan

Raw fan and battery-limit control for the **Gigabyte AERO 17 XB**.

Talks to the embedded controller through the in-tree `ec_sys` interface. No nbfc, no `ec_probe`.

Built as a small Omarchy TUI (`Omaerofan` in the app launcher) plus a CLI.

## Install

Needs `gcc`, `sudo`, and `pkexec` once:

```bash
./omaerofan install
```

That compiles the helper, installs it to `/usr/local/libexec/omaerofan-ec`, adds a passwordless `sudo` rule for that binary only, loads `ec_sys` with write support, and creates the desktop launcher.

## Usage

```bash
omaerofan                 # status
omaerofan ui              # TUI
omaerofan auto|quiet|gaming
omaerofan fans 40         # both fans, 0-100
omaerofan cpu 25
omaerofan gpu 40
omaerofan battery 60
omaerofan battery off
omaerofan dump            # raw EC bytes
omaerofan restore         # last saved settings
```

The embedded controller resets fans and the charge limit on suspend. `install` enables a user service that runs `omaerofan restore` after resume.

TUI keys: `1-4` modes, `j/k` select, `h/l` adjust, `b` battery, `d` dump, `q` quit.

## Hardware

Verified on firmware FB07 (AERO 17 XB / P77XB):

| What | Register |
| --- | --- |
| CPU / GPU / MLB temp | `0x60` `0x61` `0x62` |
| Fan RPM | `0xFC` `0xFE` (16-bit BE) |
| Fan duty | `0xB0` `0xB1` |
| Quiet / gaming / custom / fixed | `0x08.6` `0x0C.4` `0x0D.0` `0x06.4` |
| Charge limit enable / percent | `0x0F` bit 2, `0xA9` |

Manual fan duty is 0–100%. `0` stops the fans. Watch temperatures.

Writing the wrong EC register can brick a laptop. The helper only allows known fan and charge registers.

## License

MIT
