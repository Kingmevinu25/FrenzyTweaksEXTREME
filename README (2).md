# FRENZY TWEAKS

Windows performance and low-latency toolkit (Fortnite focus).

## Install / run

Open **Windows PowerShell** and paste:

```powershell
irm https://raw.githubusercontent.com/Kingmevinu25/FrenzyTweaksEXTREME/main/Frenzy.ps1 | iex
```

Accept the Administrator prompt. A ~12 second loader runs while the latest version downloads, then the app opens.

## Repo files

| File | Purpose |
|------|---------|
| `Frenzy.ps1` | Loader (splash + downloader). This is the file the one-liner fetches. |
| `FrenzyApp.ps1` | The app itself. Downloaded and cached by the loader. |

## Publishing an update

```powershell
git add .
git commit -m "v3.3: describe the change"
git push
```

Users get the new version the next time they run the one-liner. Bump `$script:AppVersion` in `FrenzyApp.ps1` when you release.

## Safety

Every registry value, service and task is backed up before it is changed. Use the in-app undo, or System Restore (a restore point is created before applying).
