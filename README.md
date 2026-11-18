# Office CCTV Viewer

A fast, clean live-view wall for **Dahua** recorders (NVR / DVR / XVR). Works in Chrome or Edge, no plugins, no SmartPSS.

- 4×4 camera wall, working cameras first, cameras without a signal moved to the end
- Full-quality streams in the wall (1080p / 1440p) with smooth playback
- Click a camera for full screen, Esc to go back
- "Last seen" snapshot on cameras that have lost their signal
- **Office display mode:** no login, opens by itself when the PC starts and goes full screen on the second display (TV / monitor over HDMI) as soon as one is connected
- One-click installer: downloads everything it needs, asks for the recorder details once

## Install (Windows 10 / 11)

1. On GitHub click **Code → Download ZIP** and extract it (or `git clone` the repo).
2. Double-click **`install.bat`**.
3. Answer the questions:
   - the recorder (the installer searches your network and lists Dahua devices; pick yours or type its IP)
   - recorder username (usually `admin`) and password
   - how many camera channels it has (16 for a 16-channel recorder)
4. Say **yes** to "Show the cameras full screen on the second display" for the office TV setup.
5. The **Office CCTV** icon on the desktop opens the wall in a normal window any time.

The computer must be on the **same network as the recorder** (office Wi-Fi or LAN).

### What the installer does

| Step | What happens |
|---|---|
| Viewer page | Copied to `%LOCALAPPDATA%\OfficeCCTV\www` |
| go2rtc 1.9.15 | Downloaded from the official [go2rtc releases](https://github.com/AlexxIT/go2rtc/releases) and checked against a fixed SHA-256 checksum before it is installed |
| Camera settings | Written to `%LOCALAPPDATA%\OfficeCCTV\go2rtc.yaml` on **this computer only** |
| Launcher | A desktop shortcut that starts go2rtc in the background and opens the viewer in a window |
| Auto start (optional) | A shortcut in your Startup folder runs a small hidden watcher (`watch.ps1`) when you sign in |

Nothing else is installed. No admin rights are needed.

## Everyday use

- **Open:** double-click *Office CCTV* on the desktop.
- **All 16 / Working only** button (top bar, or press **W**; on the TV wall move the mouse onto the TV and the top bar slides in): show every channel in a 4×4 wall, or only the cameras that are working, filling the screen.
- Cameras that lose signal (power cut, recorder restart) are retried every 30 seconds and come back on their own.
- **HD / Fast** button (top bar): HD uses the recorder's main streams. Switch to Fast on a slow computer.
- **Stop it** (including the watcher, so it does not reopen): right-click `%LOCALAPPDATA%\OfficeCCTV\stop.ps1` → *Run with PowerShell*.
- **Turn auto start off:** delete *Office CCTV* from the Startup folder (Win+R → `shell:startup`) or run `install.bat -NoAutoStart`.

## Change settings or update

- **Change recorder, password or channel count:** run `install.bat -Reconfigure` (or edit `%LOCALAPPDATA%\OfficeCCTV\go2rtc.yaml`).
- **Update the viewer:** download the newer ZIP and run `install.bat` again. It first stops and removes the old copy (old page, scripts, go2rtc, shortcuts and the wall's browser data, and any go2rtc started by hand from another folder), then installs everything fresh. Only your camera settings are kept.
- **Remove everything:** double-click `uninstall.bat`.

## Office TV setup (automatic, no login)

The viewer has **no login**: whoever can reach the PC sees the cameras, and the page only listens on this computer.

The watcher (`watch.ps1`) starts when you sign in to Windows. Every few seconds it checks for a second display. When one appears it opens the wall full screen on it with no title bar, mouse cursor hidden and the screen kept awake. If the display is unplugged or switched off it closes the wall, and it opens again when the display comes back. It also restarts go2rtc if that stops.

For this to work unattended:

1. **Display mode: Extend.** Press **Win+P** and choose **Extend**. In Duplicate mode Windows sees only one screen.
2. **Automatic sign-in**, so the wall returns after a restart or power cut. Press **Win+R**, type `netplwiz`, untick *Users must enter a user name and password*, enter the PC password once. (Windows cannot show anything before someone is signed in.)
3. Optional: in Windows power settings set the PC to never sleep.

Log file: `%LOCALAPPDATA%\OfficeCCTV\watch.log`.

## Show it on other computers

Install it on each computer with the steps above. Each one connects to the recorder directly. Do **not** expose this to the internet. For remote viewing use the recorder maker's phone app (DMSS).

## Troubleshooting

| Problem | Fix |
|---|---|
| A tile says **NO SIGNAL** | That channel has no camera or has lost power or cable. Remove its `camN` lines from `go2rtc.yaml` if it is not used. |
| Every tile says NO SIGNAL | Wrong IP, username or password, or this computer is on another network. Run `install.bat -Reconfigure`. |
| Wall does not appear on the TV | Check Win+P is set to **Extend** and the TV is on the right HDMI input. See `watch.log`. |
| Picture stutters | Click **HD** to switch to **Fast**, close other heavy programs. |
| Windows warns about `go2rtc.exe` | It is unsigned open-source software. The installer checks its checksum. Choose *More info → Run anyway* if SmartScreen asks. |
| Special characters in the password | Handled automatically. |
| Recorder uses H.265 only | Browsers may not play H.265. Set the recorder's main/sub stream encoding to **H.264**. |

## Security

- Your recorder password is stored only in `go2rtc.yaml` on each computer. It is **not** part of this repository (see `.gitignore`).
- The viewer listens on `127.0.0.1` (this computer only), so nothing else on the network can reach it.
- Change the recorder's default password if it is something simple like `admin` or `password`.

## Credits

Built on [go2rtc](https://github.com/AlexxIT/go2rtc) (MIT licence). See `THIRD-PARTY-NOTICES.md`.
