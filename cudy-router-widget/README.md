# Cudy Router – KDE Plasma 6 widget

A small Plasma 6 widget that shows what is connected to your Cudy router and
how its cellular link is doing, styled like an LCD or VFD display.

> **Tested only on a Cudy LT500D.**
> It may work with other Cudy models that use the same local API, but there is
> **no warranty** that it works with any other router. See [Disclaimer](#disclaimer).

## Features

- **Device list** – name, IP, connection type (Wi-Fi / Ethernet) and current
  download/upload rates, refreshed at an interval you choose.
- **Wi-Fi signal bars** for wireless clients; an Ethernet port symbol for wired ones.
- **Session tracking** – a new device flashes when it appears; a device that
  disappears stays in the list, greyed out, with "last seen … ago". The list
  lives only while the widget runs and starts fresh after a reboot.
- **Cellular status** – operator, network type and band, public IP and signal
  bars (for routers with a modem).
- **Display styles** – System (Plasma theme), LCD white/blue, LCD orange
  backlight, or VFD with a glow. Optional custom font (a segment font such as
  *DSEG14 Classic* gives the most authentic look).
- **Pause and refresh buttons** in the header: pause/resume the updates, or fetch right now
  (handy with a long refresh interval; works while paused too).
- **Transparent background** option, so the text (and the VFD glow) sits directly on the desktop wallpaper.

## Requirements

- KDE Plasma 6
- `curl`
- `avahi-utils` (provides `avahi-browse`) – only needed to find the login salt
  automatically; you can enter the salt by hand instead

The widget has no Python or other dependencies. The router protocol is
implemented in the widget's own JavaScript.

## Installation

```sh
unzip cudy-router-widget.zip
kpackagetool6 --type Plasma/Applet --install cudy-router-widget
```

To update an installed copy use `--upgrade` instead of `--install`, then
restart Plasma so new settings appear:

```sh
kquitapp6 plasmashell; kstart plasmashell
```

Add **Cudy Router** to the desktop or a panel like any other widget.
To try it in a window first: `plasmoidviewer -a cudy-router-widget`.

To remove it: `kpackagetool6 --type Plasma/Applet --remove org.kde.plasma.cudyrouter`

## Settings

| Setting | Meaning |
|---|---|
| Router URL | e.g. `https://192.168.10.1` |
| Password | the router's admin password |
| Refresh interval (ms) | how often the router is polled (minimum 1000) |
| Login salt | leave empty to auto-discover via `avahi-browse`; or run `avahi-browse -rt _http._tcp` once and copy the value after `salt=` |
| Cellular interface | interface name as the router expects it, lowercase (default `4g`); empty hides the cellular block |
| Display style | System / LCD white-blue / LCD orange / VFD |
| Display font / size | font family and size in percent for the display styles |
| Background | "Transparent background" hides the display panel completely |
| Debug | shows the raw data of the first device, useful if fields look wrong |

## How it works

The widget talks to the router's local JSON-RPC API over HTTP(S):
it fetches a challenge, logs in with a salted SHA-256 hash, then polls the
device list and (optionally) the cellular status. Requests are sent with
`curl`, because Qt's built-in HTTP client cannot accept the router's
self-signed certificate. The session token is kept in memory only.

## Security notes

- The password is stored **in plain text** in Plasma's configuration file in
  your home directory, like most widget settings.
- Only a one-time login hash (not the password) appears in the `curl` command
  line, and the session token appears there too while a request runs. Other
  local users who can list processes could briefly see them. Use this on a
  machine you trust.
- TLS certificate verification is **disabled** (`curl -k`) because the router
  uses a self-signed certificate. Use the widget only on your own local network.

## Troubleshooting

- **"Could not discover the router's login salt"** – install `avahi-utils`, or
  enter the salt manually (see Settings).
- **"Login failed"** – check the password and the salt.
- **"curl is not installed"** – install `curl`.
- **Blank or wrong device fields** – enable the Debug option, and open an issue
  with the raw data (remove MAC addresses first).
- **Cellular block shows an error** – check the cellular interface name;
  routers without a modem will not support it.

## Disclaimer

This is an unofficial, community project. It is not affiliated with or
endorsed by Cudy.

It was tested **only on a Cudy LT500D**. The router API is undocumented and
may differ between models and firmware versions. **There is no warranty of any
kind** that the widget works with other routers, that it displays correct
data, or that it is fit for any particular purpose. Use it at your own risk.

## License

GPL-2.0 or later (see `metadata.json`).
