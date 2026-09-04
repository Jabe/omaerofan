# Omaerofan

Omarchy bar plugin for raw fan, RAPL, and charge-limit control on the **Gigabyte AERO 17 XB**.

Talks to the embedded controller through the in-tree `ec_sys` interface. No nbfc, no `ec_probe`.

Fan mode stays independent. **RAPL follows the Omarchy power profile**. EC Auto floors around 30% / 2900 RPM — use **Curve** for a quieter software map on manual duty.

## Install

```bash
omarchy plugin add https://github.com/Jabe/omaerofan.git --enable
```

That clones the plugin into `~/.config/omarchy/plugins/jabe.omaerofan/` and puts **Omaerofan** on the bar. Open the panel and click **Install helper** once (`gcc` + `pkexec`). That compiles the EC helper, installs a passwordless `sudo` rule for that binary only, and loads `ec_sys` with write support. After suspend the plugin restores the last saved fan and charge-limit settings.

From a local checkout:

```bash
omarchy plugin add /path/to/omaerofan --enable
omarchy plugin validate /path/to/omaerofan
```

The helper install can also be run from a terminal:

```bash
~/.config/omarchy/plugins/jabe.omaerofan/omaerofan install
```

## Usage

Click the fan icon on the bar for modes, per-fan sliders, and the charge limit.

The plugin restores the last saved settings after suspend. The CLI still works for scripts and a fallback TUI:

```bash
omaerofan                 # status
omaerofan json            # JSON status
omaerofan ui              # TUI
omaerofan auto|quiet|gaming|manual|curve
omaerofan apply-curve
omaerofan curve-min 12
omaerofan curve-max 40
omaerofan fans 40         # both fans, 0-100
omaerofan cpu 25
omaerofan gpu 40
omaerofan battery 60
omaerofan battery off
omaerofan sync            # RAPL for the current Omarchy power profile
omaerofan rapl 35 50      # set PL1/PL2 watts once (overwritten on next sync)
omaerofan dump            # raw EC bytes
omaerofan restore         # last saved fan/battery settings + RAPL sync
```

TUI keys: `1-5` modes, `j/k` select, `h/l` adjust, `b` battery, `d` dump, `q` quit.

## Fan curve

`curve` writes a software duty map (not the EC auto curve). Default floor is 12%, ceiling 40% — it will not go to 100% even under thermal load. Duty moves at most one map neighbor every 2s, same as the EC. Points live in `~/.config/omaerofan/curve.json`. Dragging the manual sliders leaves curve and goes back to Manual.

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

## Power profiles

`sync` (also on plugin start, profile change, and after resume) writes Intel RAPL PL1/PL2 from `~/.config/omaerofan/power.json`:

| Omarchy profile | PL1 | PL2 |
| --- | --- | --- |
| `power-saver` | 25 W | 35 W |
| `balanced` | 35 W | 50 W |
| `performance` | 45 W | 135 W |

That file is created on first sync. Set `"follow_power_profile": false` to stop. Fans are not changed.

Quiet mode is a separate EC brake: it does **not** change RAPL or HWP. The EC asserts **EDP** (`MSR 0x64F`), which clips turbo — measured ~2.2 GHz vs 5.3 GHz. The panel/CLI `brake` line shows that.

Writing the wrong EC register can brick a laptop. The helper only allows known fan and charge registers, plus RAPL sysfs.

## License

MIT
