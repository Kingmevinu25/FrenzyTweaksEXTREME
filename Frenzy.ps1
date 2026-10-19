#Requires -Version 5.1
<#
  FRENZY TWEAKS - web loader  v1.2
  Run from PowerShell:
      irm https://raw.githubusercontent.com/Kingmevinu25/FrenzyTweaksEXTREME/main/Frenzy.ps1 | iex

  What it does
    1. Asks for Administrator (UAC), then re-opens itself hidden (no console window in your face).
    2. Shows the FRENZY splash IN FRONT of every window (forced to the foreground).
    3. Downloads the latest FrenzyApp.ps1 from GitHub in the background and caches it.
    4. Pre-compiles the UI engine while the splash animates, then opens the app.
       The splash stays on screen until the app window is ready - no blank gap.
  If GitHub is unreachable it launches the last cached copy.
  Log file: %ProgramData%\FrenzyTweaks\loader.log
#>
$ErrorActionPreference = 'Stop'

# ===================== EDIT IF YOUR REPO CHANGES =====================
$GH_USER   = 'Kingmevinu25'
$GH_REPO   = 'FrenzyTweaksEXTREME'
$GH_BRANCH = 'main'
$MinSeconds = 8.0           # minimum splash length in seconds
# =====================================================================
$BaseUrl   = "https://raw.githubusercontent.com/$GH_USER/$GH_REPO/$GH_BRANCH"
$LoaderUrl = "$BaseUrl/Frenzy.ps1"
$AppUrl    = "$BaseUrl/FrenzyApp.ps1"
$DataDir   = Join-Path $env:ProgramData 'FrenzyTweaks'
$AppPath   = Join-Path $DataDir 'FrenzyApp.ps1'
$LogPath   = Join-Path $DataDir 'loader.log'
$LoaderVersion = '1.2'

function Write-LoaderLog([string]$m) {
    try { Add-Content -Path $LogPath -Value ('[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m) -ErrorAction Stop } catch {}
}

# ---------- Elevate + STA (irm | iex has no file, so re-run the one-liner hidden) ----------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$isSta = ([Threading.Thread]::CurrentThread.GetApartmentState() -eq 'STA')
if (-not $isAdmin -or -not $isSta -or $PSVersionTable.PSVersion.Major -ge 6) {
    if ($PSCommandPath) { $ra = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$PSCommandPath`"" }
    else { $ra = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -Command `"irm '$LoaderUrl' | iex`"" }
    try { Start-Process powershell.exe -Verb RunAs -ArgumentList $ra }
    catch { Write-Host 'FRENZY TWEAKS needs Administrator permission to apply tweaks.' -ForegroundColor Red }
    return
}
try { New-Item -ItemType Directory -Path $DataDir -Force | Out-Null } catch {}
Write-LoaderLog "---- loader v$LoaderVersion started (PS $($PSVersionTable.PSVersion))"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()

# ---------- Win32 helpers: force the splash to the front ----------
if (-not ('FzLoaderWin' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class FzLoaderWin
{
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int n);
    [DllImport("user32.dll")] static extern bool BringWindowToTop(IntPtr h);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] static extern bool AttachThreadInput(uint a, uint b, bool f);
    [DllImport("user32.dll")] static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
    [DllImport("kernel32.dll")] static extern IntPtr GetConsoleWindow();
    [DllImport("kernel32.dll")] static extern uint GetConsoleProcessList(uint[] list, uint count);
    public static void Front(IntPtr h)
    {
        try
        {
            ShowWindow(h, 9);
            keybd_event(0x12, 0, 0, UIntPtr.Zero);
            keybd_event(0x12, 0, 2, UIntPtr.Zero);
            IntPtr fg = GetForegroundWindow();
            uint pid; uint fgT = GetWindowThreadProcessId(fg, out pid); uint me = GetCurrentThreadId();
            if (fgT != 0 && fgT != me) AttachThreadInput(me, fgT, true);
            SetWindowPos(h, new IntPtr(-1), 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0040);
            BringWindowToTop(h); SetForegroundWindow(h);
            if (fgT != 0 && fgT != me) AttachThreadInput(me, fgT, false);
        }
        catch { }
    }
    public static void HideConsoleIfOwned()
    {
        try
        {
            IntPtr c = GetConsoleWindow();
            if (c == IntPtr.Zero) return;
            uint[] l = new uint[4];
            if (GetConsoleProcessList(l, 4) <= 1) ShowWindow(c, 0);
        }
        catch { }
    }
}
'@
}
[FzLoaderWin]::HideConsoleIfOwned()

# ---------- Drawing helpers ----------
function Get-RoundPath([single]$x, [single]$y, [single]$w, [single]$h, [single]$r) {
    $p = New-Object Drawing.Drawing2D.GraphicsPath; $d = $r * 2
    $p.AddArc($x, $y, $d, $d, 180, 90); $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90); $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $p.CloseFigure(); return $p
}
function Draw-FrenzyLogo($g, [single]$x, [single]$y, [single]$s) {
    $path = Get-RoundPath $x $y $s $s ($s * 0.24)
    $rect = New-Object Drawing.RectangleF($x, $y, $s, $s)
    $br = New-Object Drawing.Drawing2D.LinearGradientBrush($rect, [Drawing.Color]::FromArgb(255, 178, 36), [Drawing.Color]::FromArgb(255, 66, 0), 55.0)
    $g.FillPath($br, $path)
    $hl = New-Object Drawing.Drawing2D.LinearGradientBrush($rect, [Drawing.Color]::FromArgb(80, 255, 255, 255), [Drawing.Color]::FromArgb(0, 255, 255, 255), 90.0)
    $g.FillPath($hl, $path)
    $pts = @(@(0.28, 0.20), @(0.74, 0.20), @(0.74, 0.33), @(0.42, 0.33), @(0.42, 0.44), @(0.66, 0.44), @(0.66, 0.56), @(0.42, 0.56), @(0.42, 0.80), @(0.28, 0.80))
    $poly = @(foreach ($q in $pts) { New-Object Drawing.PointF(($x + $s * ($q[0] + 0.10 * (0.5 - $q[1]))), ($y + $s * $q[1])) })
    $g.FillPolygon([Drawing.Brushes]::White, [Drawing.PointF[]]$poly)
    $br.Dispose(); $hl.Dispose(); $path.Dispose()
}
function Get-SpacedInfo($g, [string]$txt, $font, [single]$sp) {
    $fmt = [Drawing.StringFormat]::GenericTypographic; $pt = New-Object Drawing.PointF(0, 0)
    $nW = $g.MeasureString('n', $font, $pt, $fmt).Width; $xs = New-Object System.Collections.ArrayList; $x = [double]0
    foreach ($ch in $txt.ToCharArray()) {
        [void]$xs.Add([single]$x)
        if ($ch -eq ' ') { $x += $nW * 0.9 + $sp } else { $x += $g.MeasureString([string]$ch, $font, $pt, $fmt).Width + $sp }
    }
    return @{ Txt = $txt; Xs = $xs.ToArray(); Width = [single]($x - $sp) }
}
function Draw-Info($g, $info, $font, $brush, [single]$x, [single]$y) {
    $fmt = [Drawing.StringFormat]::GenericTypographic
    for ($i = 0; $i -lt $info.Txt.Length; $i++) {
        $ch = $info.Txt[$i]
        if ($ch -ne ' ') { $g.DrawString([string]$ch, $font, $brush, [single]($x + $info.Xs[$i]), $y, $fmt) }
    }
}

# ---------- Splash state ----------
$W = 760; $H = 480
$script:Sp = @{
    Clock = [Diagnostics.Stopwatch]::StartNew(); Last = 0.0; P = 0.0; Ready = $false; UseCache = $false
    Text = $null; Task = $null; Closing = $false; Cancel = $false; Fail = $null; FailAt = 0.0
    Compile = $null; CompileDone = $false; Launch = $false; Fade = $false
    Parts = New-Object System.Collections.ArrayList
}
$rnd = New-Object Random
for ($i = 0; $i -lt 44; $i++) {
    [void]$script:Sp.Parts.Add(@{ X = $rnd.NextDouble() * $W; Y = $rnd.NextDouble() * $H; V = 16 + $rnd.NextDouble() * 50; S = 1.2 + $rnd.NextDouble() * 3.0; Ph = $rnd.NextDouble() * 6.28; A = 0.35 + $rnd.NextDouble() * 0.65 })
}
$script:Stages = @(
    @(0.00, 'connecting to server'), @(0.16, 'verifying secure connection'), @(0.34, 'downloading latest modules'),
    @(0.56, 'compiling interface engine'), @(0.76, 'preparing environment'), @(0.90, 'launching FRENZY TWEAKS'))

$headName = 'Segoe UI'
try { if ((New-Object Drawing.Text.InstalledFontCollection).Families | Where-Object { $_.Name -eq 'Bahnschrift' }) { $headName = 'Bahnschrift' } } catch {}
$monoName = 'Consolas'
$fWord  = New-Object Drawing.Font($headName, 58, [Drawing.FontStyle]::Bold, [Drawing.GraphicsUnit]::Pixel)
$fMono  = New-Object Drawing.Font($monoName, 13, [Drawing.FontStyle]::Bold, [Drawing.GraphicsUnit]::Pixel)
$fMonoS = New-Object Drawing.Font($monoName, 11, [Drawing.FontStyle]::Bold, [Drawing.GraphicsUnit]::Pixel)
$fPct   = New-Object Drawing.Font($monoName, 13, [Drawing.FontStyle]::Bold, [Drawing.GraphicsUnit]::Pixel)

$tmpB = New-Object Drawing.Bitmap(1, 1); $tmpG = [Drawing.Graphics]::FromImage($tmpB)
$infoA = Get-SpacedInfo $tmpG 'FRENZY' $fWord 6
$infoB = Get-SpacedInfo $tmpG 'TWEAKS' $fWord 6
$infoBy = Get-SpacedInfo $tmpG '// BY FRENZY' $fMono 5
$infoOn = Get-SpacedInfo $tmpG '// SYSTEM ONLINE' $fMono 4
$infoFt = Get-SpacedInfo $tmpG ("V $LoaderVersion  .  WINDOWS  .  SYSTEM START") $fMonoS 3
$tmpG.Dispose(); $tmpB.Dispose()

# pre-render the glowing title once (cheap to draw every frame)
$titleH = 150
$titleBmp = New-Object Drawing.Bitmap($W, $titleH, [Drawing.Imaging.PixelFormat]::Format32bppPArgb)
$tg = [Drawing.Graphics]::FromImage($titleBmp); $tg.TextRenderingHint = 'AntiAliasGridFit'; $tg.SmoothingMode = 'AntiAlias'
$glowB = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(11, 255, 96, 0))
$mainB = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(255, 226, 92))
foreach ($dy in -5, -3, 0, 3, 5) { foreach ($dx in -5, -3, 0, 3, 5) {
        Draw-Info $tg $infoA $fWord $glowB ([single](($W - $infoA.Width) / 2 + $dx)) ([single](6 + $dy))
        Draw-Info $tg $infoB $fWord $glowB ([single](($W - $infoB.Width) / 2 + $dx)) ([single](70 + $dy)) } }
Draw-Info $tg $infoA $fWord $mainB ([single](($W - $infoA.Width) / 2)) 6
Draw-Info $tg $infoB $fWord $mainB ([single](($W - $infoB.Width) / 2)) 70
$tg.Dispose(); $glowB.Dispose(); $mainB.Dispose()

$form = New-Object Windows.Forms.Form
$form.FormBorderStyle = 'None'; $form.StartPosition = 'CenterScreen'; $form.ClientSize = New-Object Drawing.Size($W, $H)
$form.BackColor = [Drawing.Color]::FromArgb(7, 9, 16); $form.ShowInTaskbar = $true; $form.TopMost = $true; $form.Text = 'FRENZY TWEAKS'
$form.KeyPreview = $true
$form.GetType().GetProperty('DoubleBuffered', [Reflection.BindingFlags]'NonPublic,Instance').SetValue($form, $true, $null)
try {
    $rg = Get-RoundPath 0 0 $W $H 16
    $form.Region = New-Object Drawing.Region($rg)
    $ib = New-Object Drawing.Bitmap(64, 64); $ig = [Drawing.Graphics]::FromImage($ib); $ig.SmoothingMode = 'AntiAlias'
    Draw-FrenzyLogo $ig 2 2 60; $form.Icon = [Drawing.Icon]::FromHandle($ib.GetHicon()); $ig.Dispose()
} catch {}
$form.Add_KeyDown({ param($s, $e) if ($e.KeyCode -eq 'Escape' -and -not $script:Sp.Launch) { $script:Sp.Cancel = $true; $s.Close() } })

# ---------- Paint ----------
$form.Add_Paint({
        param($s, $e)
        $g = $e.Graphics; $sp = $script:Sp
        $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAliasGridFit'
        $t = $sp.Clock.Elapsed.TotalSeconds; $cx = $W / 2; $cy = 122
        $ember = [Drawing.Color]::FromArgb(255, 106, 0)

        # grid
        $gp = New-Object Drawing.Pen([Drawing.Color]::FromArgb(16, 255, 120, 30), 1)
        for ($x = 0; $x -lt $W; $x += 38) { $g.DrawLine($gp, $x, 0, $x, $H) }
        for ($y = 0; $y -lt $H; $y += 38) { $g.DrawLine($gp, 0, $y, $W, $y) }
        $gp.Dispose()
        # ember particles
        foreach ($p in $sp.Parts) {
            $a = [int](255 * $p.A * [math]::Max(0, [math]::Min(1, $p.Y / $H)) * 0.8)
            if ($a -le 4) { continue }
            $br = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb($a, 255, [int](90 + 90 * $p.A), 20))
            $g.FillEllipse($br, [single]$p.X, [single]$p.Y, [single]$p.S, [single]$p.S); $br.Dispose()
        }
        # pulsing glow behind the logo + title
        $pulse = 0.5 + 0.5 * [math]::Sin($t * 2.2)
        $gpth = New-Object Drawing.Drawing2D.GraphicsPath; $gpth.AddEllipse([single]($cx - 300), [single]($cy - 150), [single]600, [single]420)
        $pg = New-Object Drawing.Drawing2D.PathGradientBrush($gpth)
        $pg.CenterColor = [Drawing.Color]::FromArgb([int](46 + 36 * $pulse), 255, 90, 0)
        $pg.SurroundColors = [Drawing.Color[]]@([Drawing.Color]::FromArgb(0, 255, 90, 0))
        $g.FillPath($pg, $gpth); $pg.Dispose(); $gpth.Dispose()

        # corner brackets
        $bp = New-Object Drawing.Pen($ember, 2.6); $m = 22; $L = 46
        $g.DrawLines($bp, [Drawing.PointF[]]@((New-Object Drawing.PointF($m, ($m + $L))), (New-Object Drawing.PointF($m, $m)), (New-Object Drawing.PointF(($m + $L), $m))))
        $g.DrawLines($bp, [Drawing.PointF[]]@((New-Object Drawing.PointF(($W - $m - $L), $m)), (New-Object Drawing.PointF(($W - $m), $m)), (New-Object Drawing.PointF(($W - $m), ($m + 16)))))
        $g.DrawLines($bp, [Drawing.PointF[]]@((New-Object Drawing.PointF($m, ($H - $m - 16))), (New-Object Drawing.PointF($m, ($H - $m))), (New-Object Drawing.PointF(($m + $L), ($H - $m)))))
        $g.DrawLines($bp, [Drawing.PointF[]]@((New-Object Drawing.PointF(($W - $m), ($H - $m - $L))), (New-Object Drawing.PointF(($W - $m), ($H - $m))), (New-Object Drawing.PointF(($W - $m - $L), ($H - $m)))))
        $bp.Dispose()

        # header tag
        $eb = New-Object Drawing.SolidBrush($ember)
        Draw-Info $g $infoBy $fMono $eb ([single]($cx - $infoBy.Width / 2)) 30

        # rotating ember ring + logo
        $ang = ($t * 230) % 360
        $pen0 = New-Object Drawing.Pen([Drawing.Color]::FromArgb(40, 255, 120, 20), 2)
        $g.DrawEllipse($pen0, [single]($cx - 64), [single]($cy - 64), [single]128, [single]128); $pen0.Dispose()
        $pen1 = New-Object Drawing.Pen([Drawing.Color]::FromArgb(255, 255, 122, 20), 3.5); $pen1.StartCap = 'Round'; $pen1.EndCap = 'Round'
        $g.DrawArc($pen1, [single]($cx - 64), [single]($cy - 64), [single]128, [single]128, [single]$ang, [single]110); $pen1.Dispose()
        $pen2 = New-Object Drawing.Pen([Drawing.Color]::FromArgb(130, 255, 190, 70), 2.5); $pen2.StartCap = 'Round'; $pen2.EndCap = 'Round'
        $g.DrawArc($pen2, [single]($cx - 64), [single]($cy - 64), [single]128, [single]128, [single](($ang + 180) % 360), [single]55); $pen2.Dispose()
        Draw-FrenzyLogo $g ([single]($cx - 44)) ([single]($cy - 44)) ([single]88)

        Draw-Info $g $infoOn $fMono $eb ([single]($cx - $infoOn.Width / 2)) 204
        $g.DrawImageUnscaled($titleBmp, 0, 222)

        # progress block
        $bx = 120; $bwid = $W - 240; $by = 402
        if ($sp.Fail) { $col = [Drawing.Color]::FromArgb(255, 84, 72); $msg = $sp.Fail }
        else {
            $col = [Drawing.Color]::FromArgb(246, 243, 240); $msg = $script:Stages[0][1]
            foreach ($st in $script:Stages) { if ($sp.P -ge $st[0]) { $msg = $st[1] } }
            $msg += ('.' * ([int]([math]::Floor($t * 2.5) % 4)))
        }
        $dimb = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(170, 150, 138))
        $g.DrawString('INITIALIZING', $fPct, $dimb, [single]$bx, [single]($by - 26))
        $ldg = if ($sp.Fail) { 'ERROR' } else { 'LOADING' }; $lsz = $g.MeasureString($ldg, $fPct)
        $g.FillEllipse($eb, [single]($bx + $bwid - $lsz.Width - 14), [single]($by - 21), [single]7, [single]7)
        $g.DrawString($ldg, $fPct, $eb, [single]($bx + $bwid - $lsz.Width), [single]($by - 26))
        $track = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(36, 31, 28))
        $tp = Get-RoundPath $bx $by $bwid 5 2.5; $g.FillPath($track, $tp); $tp.Dispose(); $track.Dispose()
        $fw = [single]($bwid * [math]::Min(1, $sp.P))
        if ($fw -gt 5) {
            $fr = New-Object Drawing.RectangleF([single]$bx, [single]$by, $fw, [single]5)
            $fb = New-Object Drawing.Drawing2D.LinearGradientBrush($fr, [Drawing.Color]::FromArgb(255, 255, 60, 0), [Drawing.Color]::FromArgb(255, 255, 184, 52), 0.0)
            $fp = Get-RoundPath $bx $by $fw 5 2.5; $g.FillPath($fb, $fp); $fp.Dispose(); $fb.Dispose()
            $hb = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(90, 255, 160, 40))
            $g.FillEllipse($hb, [single]($bx + $fw - 9), [single]($by - 6), [single]18, [single]18); $hb.Dispose()
        }
        $cb = New-Object Drawing.SolidBrush($col)
        $g.DrawString('$ ' + $msg, $fMono, $cb, [single]$bx, [single]($by + 16)); $cb.Dispose()
        $ptxt = ('{0}%' -f [int]([math]::Floor($sp.P * 100))); $psz = $g.MeasureString($ptxt, $fPct)
        $g.DrawString($ptxt, $fPct, $eb, [single]($bx + $bwid - $psz.Width), [single]($by + 16))
        Draw-Info $g $infoFt $fMonoS $dimb ([single]($cx - $infoFt.Width / 2)) ($H - 44)
        $dimb.Dispose(); $eb.Dispose()

        # thin ember border
        $bp2 = Get-RoundPath 0.5 0.5 ($W - 1) ($H - 1) 16
        $pen = New-Object Drawing.Pen([Drawing.Color]::FromArgb(150, 255, 106, 0), 1.5); $g.DrawPath($pen, $bp2); $pen.Dispose(); $bp2.Dispose()
    })

# ---------- Background download (async, UI stays smooth) ----------
$wc = New-Object Net.WebClient
$wc.Encoding = [Text.Encoding]::UTF8
$wc.Headers.Add('User-Agent', "FrenzyTweaks-Loader/$LoaderVersion")
$wc.Headers.Add('Cache-Control', 'no-cache')
$script:Sp.Task = $wc.DownloadStringTaskAsync("$AppUrl`?t=$([DateTime]::UtcNow.Ticks)")

# Pre-compile the C# UI engine (embedded in FrenzyApp.ps1) in a background runspace while the splash animates
function Start-FzPrecompile([string]$AppText) {
    try {
        $m = [regex]::Match($AppText, '(?s)\$script:FzSource = @''\r?\n(.*?)\r?\n''@')
        if (-not $m.Success) { return $null }
        $ps = [powershell]::Create()
        [void]$ps.AddScript({
                param($code)
                try {
                    if (-not ('Fz.FzCard' -as [type])) { Add-Type -TypeDefinition $code -ReferencedAssemblies 'System.Windows.Forms', 'System.Drawing' }
                    'ok'
                } catch { 'ERR: ' + $_.Exception.Message }
            }).AddArgument($m.Groups[1].Value)
        return @{ Ps = $ps; Handle = $ps.BeginInvoke() }
    } catch { Write-LoaderLog "precompile start failed: $($_.Exception.Message)"; return $null }
}

# ---------- Animation tick ----------
$timer = New-Object Windows.Forms.Timer; $timer.Interval = 20
$timer.Add_Tick({
        try {
            $sp = $script:Sp; $t = $sp.Clock.Elapsed.TotalSeconds; $dt = [math]::Min(0.1, $t - $sp.Last); $sp.Last = $t
            foreach ($p in $sp.Parts) {
                $p.Y -= $p.V * $dt; $p.X += [math]::Sin($t * 1.3 + $p.Ph) * 14 * $dt
                if ($p.Y -lt -6) { $p.Y = $H + 6; $p.X = (Get-Random -Minimum 0 -Maximum $W) }
            }
            # download result
            if (-not $sp.Ready -and -not $sp.Fail -and $sp.Task.IsCompleted) {
                $ok = $false
                if (-not $sp.Task.IsFaulted -and -not $sp.Task.IsCanceled) {
                    $txt = [string]$sp.Task.Result
                    if ($txt.Length -gt 20000 -and $txt -match 'FRENZY TWEAKS') { $sp.Text = $txt; $ok = $true }
                } else { Write-LoaderLog "download failed: $($sp.Task.Exception.GetBaseException().Message)" }
                if (-not $ok -and (Test-Path $AppPath)) { $sp.UseCache = $true; $ok = $true; Write-LoaderLog 'using cached app' }
                if ($ok) {
                    $sp.Ready = $true
                    $src = $sp.Text; if (-not $src) { try { $src = [IO.File]::ReadAllText($AppPath) } catch {} }
                    if ($src) { $sp.Compile = Start-FzPrecompile $src }
                    if (-not $sp.Compile) { $sp.CompileDone = $true }
                } else { $sp.Fail = 'Could not reach the server. Check your internet and try again.'; $sp.FailAt = $t }
            }
            if ($sp.Ready -and -not $sp.CompileDone -and $sp.Compile -and $sp.Compile.Handle.IsCompleted) {
                try { $r = $sp.Compile.Ps.EndInvoke($sp.Compile.Handle); Write-LoaderLog "precompile: $($r -join ' ')" } catch { Write-LoaderLog "precompile error: $($_.Exception.Message)" }
                try { $sp.Compile.Ps.Dispose() } catch {}
                $sp.CompileDone = $true
            }
            if ($sp.Fail) {
                if (($t - $sp.FailAt) -gt 3.5) { $timer.Stop(); $form.Close() }
            } else {
                $raw = [math]::Min(1.0, $t / $MinSeconds); $smooth = $raw * $raw * (3 - 2 * $raw)
                $okToGo = ($raw -ge 1.0 -and $sp.Ready -and $sp.CompileDone)
                $target = if ($sp.Closing) { 1.0 } elseif ($okToGo) { 0.97 } else { [math]::Min(0.97, $smooth * 0.97) }
                $sp.P += ($target - $sp.P) * 0.16
                if ($okToGo -and -not $sp.Launch -and $sp.P -gt 0.94) { $sp.Launch = $true }
                if ($sp.Closing -and $sp.P -gt 0.985) { $sp.Fade = $true }
            }
            if ($sp.Fade) {
                $form.Opacity = [math]::Max(0, $form.Opacity - 0.09)
                if ($form.Opacity -le 0.02) { $timer.Stop(); $form.Close() }
            }
            $form.Invalidate()
        } catch { Write-LoaderLog "tick error: $($_.Exception.Message)" }
    })

# Re-assert the foreground for the first ~2 seconds (a freshly elevated process is not allowed to take focus by default)
$script:FrontTicks = 0
$frontTimer = New-Object Windows.Forms.Timer; $frontTimer.Interval = 150
$frontTimer.Add_Tick({
        $script:FrontTicks++
        try { [FzLoaderWin]::Front($form.Handle); $form.Activate() } catch {}
        if ($script:FrontTicks -ge 14) { $frontTimer.Stop() }
    })

# ---------- Show splash (non-modal so the app can build behind it) ----------
try {
    $form.Show()
    [FzLoaderWin]::Front($form.Handle); $form.Activate(); $form.BringToFront()
    $timer.Start(); $frontTimer.Start()
    while (-not $form.IsDisposed -and -not $script:Sp.Launch) {
        [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 8
    }
} catch { Write-LoaderLog "splash error: $($_.Exception.Message)" }
$frontTimer.Stop()

# ---------- Launch ----------
if ($script:Sp.Cancel) { try { $timer.Stop() } catch {}; return }
if ($script:Sp.Fail) {
    try { $timer.Stop(); $form.Close() } catch {}
    [void][Windows.Forms.MessageBox]::Show($script:Sp.Fail, 'FRENZY TWEAKS', 'OK', 'Warning'); return
}
if (-not $script:Sp.Launch) { return }
try {
    New-Item -ItemType Directory -Path $DataDir -Force | Out-Null
    if (-not $script:Sp.UseCache -and $script:Sp.Text) {
        [IO.File]::WriteAllText($AppPath, $script:Sp.Text, (New-Object Text.UTF8Encoding($true)))
    }
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction SilentlyContinue
    Unblock-File -Path $AppPath -ErrorAction SilentlyContinue
    $ErrorActionPreference = 'Continue'
    # The app closes the splash itself once its window is ready (it sets $global:FrenzySplash.Closing)
    $global:FrenzySplash = $script:Sp
    & $AppPath
} catch {
    Write-LoaderLog "app error: $($_.Exception.Message)"
    try { $script:Sp.Closing = $true; $script:Sp.Fade = $true } catch {}
    [void][Windows.Forms.MessageBox]::Show("FRENZY TWEAKS could not start:`n`n$($_.Exception.Message)", 'FRENZY TWEAKS', 'OK', 'Error')
} finally {
    # make sure the splash never stays on screen
    try {
        $script:Sp.Closing = $true; $script:Sp.Fade = $true
        $n = 0; while (-not $form.IsDisposed -and $n -lt 60) { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 20; $n++ }
        if (-not $form.IsDisposed) { $timer.Stop(); $form.Close() }
        $timer.Dispose()
    } catch {}
    Remove-Variable -Name FrenzySplash -Scope Global -ErrorAction SilentlyContinue
}
