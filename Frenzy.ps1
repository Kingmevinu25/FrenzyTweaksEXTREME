#Requires -Version 5.1
<#
  FRENZY TWEAKS - web loader
  Run from PowerShell:
      irm https://raw.githubusercontent.com/Kingmevinu25/FrenzyTweaksEXTREME/main/Frenzy.ps1 | iex

  What it does: elevates, shows the animated FRENZY splash (~12 s), downloads the latest
  FrenzyApp.ps1 from GitHub in the background, caches it, then launches the app.
  If GitHub is unreachable it launches the last cached copy.
#>
$ErrorActionPreference = 'Stop'

# ===================== EDIT IF YOUR REPO CHANGES =====================
$GH_USER   = 'Kingmevinu25'
$GH_REPO   = 'FrenzyTweaksEXTREME'
$GH_BRANCH = 'main'
$MinSeconds = 12.5          # splash length (10-15 s looks best)
# =====================================================================
$BaseUrl   = "https://raw.githubusercontent.com/$GH_USER/$GH_REPO/$GH_BRANCH"
$LoaderUrl = "$BaseUrl/Frenzy.ps1"
$AppUrl    = "$BaseUrl/FrenzyApp.ps1"
$DataDir   = Join-Path $env:ProgramData 'FrenzyTweaks'
$AppPath   = Join-Path $DataDir 'FrenzyApp.ps1'
$LoaderVersion = '1.0'

# ---------- Elevate + STA (irm | iex has no file, so re-run the one-liner) ----------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$isSta = ([Threading.Thread]::CurrentThread.GetApartmentState() -eq 'STA')
if (-not $isAdmin -or -not $isSta -or $PSVersionTable.PSVersion.Major -ge 6) {
    if ($PSCommandPath) { $ra = "-NoProfile -ExecutionPolicy Bypass -STA -File `"$PSCommandPath`"" }
    else { $ra = "-NoProfile -ExecutionPolicy Bypass -STA -Command `"irm '$LoaderUrl' | iex`"" }
    try { Start-Process powershell.exe -Verb RunAs -ArgumentList $ra }
    catch { Write-Host 'FRENZY TWEAKS needs Administrator permission to apply tweaks.' -ForegroundColor Red }
    return
}
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()

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
function Measure-Spaced($g, [string]$txt, $font, [single]$sp) {
    $fmt = [Drawing.StringFormat]::GenericTypographic; $w = [double]0; $pt = New-Object Drawing.PointF(0, 0)
    $nW = $g.MeasureString('n', $font, $pt, $fmt).Width
    foreach ($ch in $txt.ToCharArray()) {
        if ($ch -eq ' ') { $w += $nW * 0.9 + $sp; continue }
        $w += $g.MeasureString([string]$ch, $font, $pt, $fmt).Width + $sp
    }
    return [single]($w - $sp)
}
function Draw-Spaced($g, [string]$txt, $font, $brush, [single]$x, [single]$y, [single]$sp) {
    $fmt = [Drawing.StringFormat]::GenericTypographic; $pt = New-Object Drawing.PointF(0, 0)
    $nW = $g.MeasureString('n', $font, $pt, $fmt).Width
    foreach ($ch in $txt.ToCharArray()) {
        if ($ch -eq ' ') { $x += $nW * 0.9 + $sp; continue }
        $g.DrawString([string]$ch, $font, $brush, $x, $y, $fmt)
        $x += $g.MeasureString([string]$ch, $font, $pt, $fmt).Width + $sp
    }
    return [single]$x
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
$W = 620; $H = 400
$script:Sp = @{
    Clock = [Diagnostics.Stopwatch]::StartNew(); Last = 0.0; P = 0.0; Ready = $false; UseCache = $false
    Text = $null; Task = $null; Closing = $false; Cancel = $false; Fail = $null; FailAt = 0.0
    Parts = New-Object System.Collections.ArrayList
}
$rnd = New-Object Random
for ($i = 0; $i -lt 38; $i++) {
    [void]$script:Sp.Parts.Add(@{ X = $rnd.NextDouble() * $W; Y = $rnd.NextDouble() * $H; V = 18 + $rnd.NextDouble() * 52; S = 1.2 + $rnd.NextDouble() * 3.2; Ph = $rnd.NextDouble() * 6.28; A = 0.35 + $rnd.NextDouble() * 0.65 })
}
$script:Stages = @(
    @(0.00, 'Connecting to server'), @(0.17, 'Verifying secure connection'), @(0.36, 'Downloading latest modules'),
    @(0.58, 'Preparing environment'), @(0.78, 'Optimizing interface'), @(0.94, 'Launching FRENZY TWEAKS'))

$fWord  = New-Object Drawing.Font('Segoe UI', 30, [Drawing.FontStyle]::Bold, [Drawing.GraphicsUnit]::Pixel)
$fTag   = New-Object Drawing.Font('Segoe UI', 11, [Drawing.FontStyle]::Bold, [Drawing.GraphicsUnit]::Pixel)
$fStage = New-Object Drawing.Font('Segoe UI', 14, [Drawing.FontStyle]::Regular, [Drawing.GraphicsUnit]::Pixel)
$fPct   = New-Object Drawing.Font('Segoe UI', 13, [Drawing.FontStyle]::Bold, [Drawing.GraphicsUnit]::Pixel)
$fSmall = New-Object Drawing.Font('Segoe UI', 10, [Drawing.FontStyle]::Regular, [Drawing.GraphicsUnit]::Pixel)

$tmpB = New-Object Drawing.Bitmap(1, 1); $tmpG = [Drawing.Graphics]::FromImage($tmpB)
$script:WmA = Get-SpacedInfo $tmpG 'FRENZY' $fWord 5
$script:WmB = Get-SpacedInfo $tmpG 'TWEAKS' $fWord 5
$script:WmT = Get-SpacedInfo $tmpG 'PERFORMANCE  SUITE' $fTag 4
$tmpG.Dispose(); $tmpB.Dispose()

$form = New-Object Windows.Forms.Form
$form.FormBorderStyle = 'None'; $form.StartPosition = 'CenterScreen'; $form.ClientSize = New-Object Drawing.Size($W, $H)
$form.BackColor = [Drawing.Color]::FromArgb(5, 5, 5); $form.ShowInTaskbar = $true; $form.TopMost = $true; $form.Text = 'FRENZY TWEAKS'
$form.KeyPreview = $true; $form.Opacity = 0
$form.GetType().GetProperty('DoubleBuffered', [Reflection.BindingFlags]'NonPublic,Instance').SetValue($form, $true, $null)
try {
    $rg = Get-RoundPath 0 0 $W $H 22
    $form.Region = New-Object Drawing.Region($rg)
    $ib = New-Object Drawing.Bitmap(64, 64); $ig = [Drawing.Graphics]::FromImage($ib); $ig.SmoothingMode = 'AntiAlias'
    Draw-FrenzyLogo $ig 2 2 60; $form.Icon = [Drawing.Icon]::FromHandle($ib.GetHicon()); $ig.Dispose()
} catch {}
$form.Add_KeyDown({ param($s, $e) if ($e.KeyCode -eq 'Escape') { $script:Sp.Cancel = $true; $s.Close() } })

# ---------- Paint ----------
$form.Add_Paint({
        param($s, $e)
        $g = $e.Graphics; $sp = $script:Sp
        $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAliasGridFit'
        $t = $sp.Clock.Elapsed.TotalSeconds; $cx = $W / 2; $cy = 118
        $ember = [Drawing.Color]::FromArgb(255, 106, 0)

        # ember particles
        foreach ($p in $sp.Parts) {
            $a = [int](255 * $p.A * [math]::Max(0, [math]::Min(1, $p.Y / $H)) * 0.8)
            if ($a -le 4) { continue }
            $br = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb($a, 255, [int](90 + 90 * $p.A), 20))
            $g.FillEllipse($br, [single]$p.X, [single]$p.Y, [single]$p.S, [single]$p.S); $br.Dispose()
        }
        # pulsing glow behind the logo
        $pulse = 0.5 + 0.5 * [math]::Sin($t * 2.4)
        $gp = New-Object Drawing.Drawing2D.GraphicsPath; $gp.AddEllipse([single]($cx - 210), [single]($cy - 160), [single]420, [single]320)
        $pg = New-Object Drawing.Drawing2D.PathGradientBrush($gp)
        $pg.CenterColor = [Drawing.Color]::FromArgb([int](50 + 34 * $pulse), 255, 90, 0)
        $pg.SurroundColors = [Drawing.Color[]]@([Drawing.Color]::FromArgb(0, 255, 90, 0))
        $g.FillPath($pg, $gp); $pg.Dispose(); $gp.Dispose()

        # rotating ember ring
        $ang = ($t * 230) % 360
        $pen0 = New-Object Drawing.Pen([Drawing.Color]::FromArgb(36, 255, 120, 20), 2)
        $g.DrawEllipse($pen0, [single]($cx - 68), [single]($cy - 68), [single]136, [single]136); $pen0.Dispose()
        $pen1 = New-Object Drawing.Pen([Drawing.Color]::FromArgb(255, 255, 122, 20), 3.5); $pen1.StartCap = 'Round'; $pen1.EndCap = 'Round'
        $g.DrawArc($pen1, [single]($cx - 68), [single]($cy - 68), [single]136, [single]136, [single]$ang, [single]110); $pen1.Dispose()
        $pen2 = New-Object Drawing.Pen([Drawing.Color]::FromArgb(130, 255, 190, 70), 2.5); $pen2.StartCap = 'Round'; $pen2.EndCap = 'Round'
        $g.DrawArc($pen2, [single]($cx - 68), [single]($cy - 68), [single]136, [single]136, [single](($ang + 180) % 360), [single]55); $pen2.Dispose()

        # F logo
        Draw-FrenzyLogo $g ([single]($cx - 47)) ([single]($cy - 47)) ([single]94)

        # wordmark  FRENZY (white) TWEAKS (ember)
        $gap = 16; $x0 = $cx - ($script:WmA.Width + $gap + $script:WmB.Width) / 2
        $bw = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(250, 248, 245)); $be = New-Object Drawing.SolidBrush($ember)
        Draw-Info $g $script:WmA $fWord $bw ([single]$x0) ([single]208)
        Draw-Info $g $script:WmB $fWord $be ([single]($x0 + $script:WmA.Width + $gap)) ([single]208)
        $bw.Dispose(); $be.Dispose()
        $dim = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(150, 140, 130))
        Draw-Info $g $script:WmT $fTag $dim ([single]($cx - $script:WmT.Width / 2)) ([single]250)

        # status line + percent
        $bx = 90; $bwid = $W - 180; $by = 332
        if ($sp.Fail) { $col = [Drawing.Color]::FromArgb(255, 84, 72); $msg = $sp.Fail }
        else {
            $col = [Drawing.Color]::FromArgb(246, 243, 240); $msg = $script:Stages[0][1]
            foreach ($st in $script:Stages) { if ($sp.P -ge $st[0]) { $msg = $st[1] } }
            $msg += ('.' * ([int]([math]::Floor($t * 2.5) % 4)))
        }
        $sb = New-Object Drawing.SolidBrush($col); $g.DrawString($msg, $fStage, $sb, [single]$bx, [single]($by - 28)); $sb.Dispose()
        $pb = New-Object Drawing.SolidBrush($ember); $ptxt = ('{0}%' -f [int]([math]::Floor($sp.P * 100)))
        $psz = $g.MeasureString($ptxt, $fPct); $g.DrawString($ptxt, $fPct, $pb, [single]($bx + $bwid - $psz.Width), [single]($by - 28)); $pb.Dispose()

        # progress bar
        $track = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(34, 30, 28))
        $tp = Get-RoundPath $bx $by $bwid 5 2.5; $g.FillPath($track, $tp); $tp.Dispose(); $track.Dispose()
        $fw = [single]($bwid * [math]::Min(1, $sp.P))
        if ($fw -gt 5) {
            $fr = New-Object Drawing.RectangleF([single]$bx, [single]$by, $fw, [single]5)
            $fb = New-Object Drawing.Drawing2D.LinearGradientBrush($fr, [Drawing.Color]::FromArgb(255, 255, 60, 0), [Drawing.Color]::FromArgb(255, 255, 184, 52), 0.0)
            $fp = Get-RoundPath $bx $by $fw 5 2.5; $g.FillPath($fb, $fp); $fp.Dispose(); $fb.Dispose()
            $hb = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(90, 255, 160, 40))
            $g.FillEllipse($hb, [single]($bx + $fw - 9), [single]($by - 6), [single]18, [single]18); $hb.Dispose()
        }
        # footer
        $g.DrawString("v$LoaderVersion", $fSmall, $dim, [single]28, [single]($H - 26))
        $ft = 'github.com/' + $GH_USER; $fsz = $g.MeasureString($ft, $fSmall)
        $g.DrawString($ft, $fSmall, $dim, [single]($W - 28 - $fsz.Width), [single]($H - 26)); $dim.Dispose()

        # thin ember border
        $bp = Get-RoundPath 0.5 0.5 ($W - 1) ($H - 1) 22
        $pen = New-Object Drawing.Pen([Drawing.Color]::FromArgb(150, 255, 106, 0), 1.5); $g.DrawPath($pen, $bp); $pen.Dispose(); $bp.Dispose()
    })

# ---------- Background download (async, UI stays smooth) ----------
$wc = New-Object Net.WebClient
$wc.Encoding = [Text.Encoding]::UTF8
$wc.Headers.Add('User-Agent', "FrenzyTweaks-Loader/$LoaderVersion")
$wc.Headers.Add('Cache-Control', 'no-cache')
$script:Sp.Task = $wc.DownloadStringTaskAsync("$AppUrl`?t=$([DateTime]::UtcNow.Ticks)")

# ---------- Animation tick ----------
$timer = New-Object Windows.Forms.Timer; $timer.Interval = 20
$timer.Add_Tick({
        try {
            $sp = $script:Sp; $t = $sp.Clock.Elapsed.TotalSeconds; $dt = [math]::Min(0.1, $t - $sp.Last); $sp.Last = $t
            if (-not $sp.Closing -and $form.Opacity -lt 1) { $form.Opacity = [math]::Min(1, $form.Opacity + 0.07) }
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
                }
                if (-not $ok -and (Test-Path $AppPath)) { $sp.UseCache = $true; $ok = $true }
                if ($ok) { $sp.Ready = $true } else { $sp.Fail = 'Could not reach the server. Check your internet and try again.'; $sp.FailAt = $t }
            }
            if ($sp.Fail) {
                if (($t - $sp.FailAt) -gt 3.5) { $timer.Stop(); $form.Close() }
            } else {
                $raw = [math]::Min(1.0, $t / $MinSeconds); $smooth = $raw * $raw * (3 - 2 * $raw)
                $target = if ($raw -ge 1.0 -and $sp.Ready) { 1.0 } else { [math]::Min(0.97, $smooth * 0.97) }
                $sp.P += ($target - $sp.P) * 0.16
                if ($sp.Ready -and $raw -ge 1.0 -and $sp.P -gt 0.995) { $sp.Closing = $true }
            }
            if ($sp.Closing) {
                $form.Opacity = [math]::Max(0, $form.Opacity - 0.09)
                if ($form.Opacity -le 0.02) { $timer.Stop(); $form.Close() }
            }
            $form.Invalidate()
        } catch { }
    })
$timer.Start()
[void]$form.ShowDialog()
$timer.Stop(); $timer.Dispose()
foreach ($f in $fWord, $fTag, $fStage, $fPct, $fSmall) { try { $f.Dispose() } catch {} }

# ---------- Launch ----------
if ($script:Sp.Cancel) { return }
if ($script:Sp.Fail) {
    [void][Windows.Forms.MessageBox]::Show($script:Sp.Fail, 'FRENZY TWEAKS', 'OK', 'Warning'); return
}
try {
    New-Item -ItemType Directory -Path $DataDir -Force | Out-Null
    if (-not $script:Sp.UseCache -and $script:Sp.Text) {
        [IO.File]::WriteAllText($AppPath, $script:Sp.Text, (New-Object Text.UTF8Encoding($true)))
    }
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction SilentlyContinue
    Unblock-File -Path $AppPath -ErrorAction SilentlyContinue
    $ErrorActionPreference = 'Continue'
    & $AppPath
} catch {
    [void][Windows.Forms.MessageBox]::Show("FRENZY TWEAKS could not start:`n`n$($_.Exception.Message)", 'FRENZY TWEAKS', 'OK', 'Error')
}
