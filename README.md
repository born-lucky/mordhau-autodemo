# Mordhau Auto Demo

Automatically records a Mordhau demo (`demorec`) of **every match you play**. Install it once and forget about it.

## Install

1. Download **MordhauAutoDemo.zip** from [Releases](../../releases/latest) and extract it anywhere.
2. Double-click **Install.bat**.

That's it. It's running now and will start by itself every time you log in to Windows. No admin rights are needed.

> If Windows shows a warning for the .bat file, click **More info → Run anyway**. Everything is plain readable script, so you can check it first.

## What it does

- Each time you join a server, the map changes, or you start an offline / practice game, it opens the console for a split second and types `demorec auto_<date>_<time>_<map>`.
- Mordhau stops a demo by itself on every map change, so each map gets its own file.
- It **only types while the Mordhau window is focused**. If you're alt-tabbed, it waits until you come back.
- It **waits until you aren't pressing anything** (no key or mouse button held for ~1 s, e.g. on the spawn screen), clears any half-typed text in the console line, then types the command in about a quarter of a second. Your keys and its keys never mix.
- If you start a demo yourself, it notices and leaves you alone.
- The main menu and demo playback are never recorded.
- Old `auto_*` demos are deleted once they pass **10 GB** total (a match is ~15-30 MB). Demos you name yourself are never touched.

**Your demos:** `%LOCALAPPDATA%\Mordhau\Saved\Demos` (paste that into Explorer's address bar)  
**Watch one:** open the console in-game and type `demoplay auto_20260929_140312_skm_mashpit`  
**Activity log:** `%LOCALAPPDATA%\MordhauAutoDemo\autodemo.log`

## Uninstall

**Settings → Apps → Installed apps → Mordhau Auto Demo → Uninstall**, or run **Uninstall.bat**. Your demos are kept.

## Settings

Edit `%LOCALAPPDATA%\MordhauAutoDemo\settings.ini`, then log out and back in (or run Install.bat again):

| Setting | Default | |
|---|---|---|
| `MaxGB` | `10` | Delete oldest auto demos past this size (`0` = never) |
| `RecordOffline` | `1` | Also record offline / practice / bot games |
| `ConsoleKey` | *(auto)* | Your console key if not the default, e.g. `F10`, `Insert` |
| `StartDelay` | `3` | Seconds after the map loads before recording |
| `RecordHz` | `0` | e.g. `120` for sharper timing (bigger files) |
| `Beep` | `0` | `1` = a short sound when a recording starts |
| `QuietMs` | `1200` | How long you must press nothing before it types |

## Is this safe?

It doesn't touch the game's files or memory. It reads Mordhau's own log file (`Saved\Logs\Mordhau.log`) to know when a map loads, then presses keys exactly like you typing `demorec` yourself.

## Troubleshooting

`autodemo.log` says **"Could not start a demo"** → your console key probably isn't the default. Set `ConsoleKey` in settings.ini.

## License

MIT
