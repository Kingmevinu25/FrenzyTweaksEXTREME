# FRENZY TWEAKS  v1.2

Windows performance and low-latency toolkit (Fortnite focus).

## Install / run

Open **Windows PowerShell** and paste:

```powershell
irm https://raw.githubusercontent.com/Kingmevinu25/FrenzyTweaksEXTREME/main/Frenzy.ps1 | iex
```

Accept the Administrator prompt. The FRENZY loader pops up in front of your windows, downloads the latest version in the background, and stays on screen until the app is ready.

## Repo files

| File | Purpose |
|------|---------|
| `Frenzy.ps1` | Loader (splash + downloader). This is the file the one-liner fetches. |
| `FrenzyApp.ps1` | The app itself (also contains the UI engine). Downloaded and cached by the loader. |
| `.gitignore` | Ignores backup / log files. |

## Publishing an update

```powershell
git add .
git commit -m "v1.3: describe the change"
git push
```

Users get the new version the next time they run the one-liner. Bump `$script:AppVersion` in `FrenzyApp.ps1` (and `$LoaderVersion` in `Frenzy.ps1` if the loader changed) when you release.

## Your links

Open `FrenzyApp.ps1`, find `$script:Links` and put your Discord / X / TikTok / YouTube URLs in. The coloured sidebar buttons open them.

## Safety

Every registry value, service and task is backed up before it is changed. Use the in-app undo, or System Restore (a restore point is created before applying). Logs: `%ProgramData%\FrenzyTweaks\`.
