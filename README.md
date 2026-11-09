# omarchy-dtp-workspace-styler

Workspace Styler on the Omarchy bar, in place of the stock workspace numbers, with this look:

- **Numbers**, with the theme accent on the marker.
- **Comet** when you switch workspace. The tail lags at 0.7.
- **Seven** workspaces stay on the row.
- No layout icon on the active number.

Peek, urgent workspaces, and timing that follows Hyprland stay at the plugin's own defaults. Right-click the row to change any of it. The shell plugin id is `io.github.sanchokusika.workspace-styler`, from [SanchoKusika/omarchy-workspace-styler](https://github.com/SanchoKusika/omarchy-workspace-styler). This repo records the placement and the settings.

## Install

`omarchy-dtp-install` runs this before the personal settings. From a local checkout:

```bash
./install.sh
```

The script adds the upstream plugin when it is not already installed, puts the row on the left immediately after the menu button (`dtpietrzak.menu`, or `omarchy.menu` when that one is still there), and turns `omarchy.workspaces` off. With no menu button on the left, the row takes the stock workspace widget's place. It then writes `settings.json` onto that widget. Running it again leaves a matching placement and matching settings alone. It does not copy monitors, touchpad settings, pinned apps, or the rest of `shell.json`.

## Check

```bash
bash tests/install-test.sh
```

## Undo

Bring the stock widget back, then remove the plugin:

```bash
omarchy plugin enable omarchy.workspaces --section left --after io.github.sanchokusika.workspace-styler
omarchy plugin remove io.github.sanchokusika.workspace-styler
```
