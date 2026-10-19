#Requires -Version 5.1
<#
  FRENZY TWEAKS v1.2  (WinForms UI)
  - Applies / undoes the tweaks from your list
  - Creates a restore point first; backs up the REAL original value of every registry
    setting, service and task it touches, so Undo restores your actual previous state
  Run with Windows PowerShell 5.1 as Administrator (it self-elevates).
#>

# ---------- Elevation ----------
$script:AppVersion = '1.2'
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    if ($PSCommandPath) { Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -STA -File `"$PSCommandPath`"" }
    else { Write-Host 'FRENZY TWEAKS needs Administrator. Re-run the install command from an elevated PowerShell.' -ForegroundColor Red }
    return
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ---------- UI engine (custom-drawn controls, compiled once at start) ----------
$script:FzSource = @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace Fz
{
    public static class Theme
    {
        public static string Head = "Segoe UI";
        public static string Mono = "Consolas";
        public static Color Bg = Color.FromArgb(8, 11, 21);
        public static Color Side = Color.FromArgb(11, 15, 28);
        public static Color Card = Color.FromArgb(18, 25, 43);
        public static Color Card2 = Color.FromArgb(29, 39, 64);
        public static Color Border = Color.FromArgb(40, 53, 84);
        public static Color Text = Color.FromArgb(240, 244, 255);
        public static Color Dim = Color.FromArgb(138, 152, 184);
        public static Color Accent = Color.FromArgb(255, 106, 0);
        public static Color Good = Color.FromArgb(74, 222, 128);
        public static Color Warn = Color.FromArgb(255, 200, 70);
        public static Color Bad = Color.FromArgb(255, 82, 82);
        static Dictionary<string, Font> cache = new Dictionary<string, Font>();
        public static Font F(float px, bool bold)
        {
            string k = "H" + px + bold;
            Font f;
            if (!cache.TryGetValue(k, out f)) { f = new Font(Head, px, bold ? FontStyle.Bold : FontStyle.Regular, GraphicsUnit.Pixel); cache[k] = f; }
            return f;
        }
        public static Font M(float px, bool bold)
        {
            string k = "M" + px + bold;
            Font f;
            if (!cache.TryGetValue(k, out f)) { f = new Font(Mono, px, bold ? FontStyle.Bold : FontStyle.Regular, GraphicsUnit.Pixel); cache[k] = f; }
            return f;
        }
    }

    public static class Gfx
    {
        public static GraphicsPath Round(RectangleF r, float rad)
        {
            GraphicsPath p = new GraphicsPath();
            float d = rad * 2f;
            if (d > r.Width) d = r.Width;
            if (d > r.Height) d = r.Height;
            if (d < 1f) { p.AddRectangle(r); return p; }
            p.AddArc(r.X, r.Y, d, d, 180, 90);
            p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
            p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
            p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
            p.CloseFigure();
            return p;
        }
        public static Color A(Color c, int a) { return Color.FromArgb(Math.Max(0, Math.Min(255, a)), c); }
        public static Color Mix(Color a, Color b, float t)
        {
            if (t < 0f) t = 0f; if (t > 1f) t = 1f;
            return Color.FromArgb(255, (int)(a.R + (b.R - a.R) * t), (int)(a.G + (b.G - a.G) * t), (int)(a.B + (b.B - a.B) * t));
        }
        public static Color BgOf(Control c)
        {
            Control p = c.Parent;
            while (p != null) { if (p.BackColor.A == 255) return p.BackColor; p = p.Parent; }
            return Theme.Bg;
        }
        public static void Quality(Graphics g)
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
            g.PixelOffsetMode = PixelOffsetMode.Half;
        }
        public static StringFormat Fmt(StringAlignment h, StringAlignment v)
        {
            StringFormat f = new StringFormat(StringFormat.GenericTypographic);
            f.Alignment = h; f.LineAlignment = v;
            f.Trimming = StringTrimming.EllipsisCharacter;
            f.FormatFlags = StringFormatFlags.NoWrap;
            return f;
        }
        public static bool IsLight(Color c) { return (c.R * 299 + c.G * 587 + c.B * 114) / 1000 > 150; }
    }

    public static class Icons
    {
        static PointF P(float x, float y, float s, float ox, float oy) { return new PointF(ox + x * s, oy + y * s); }
        public static void Draw(Graphics g, string kind, RectangleF r, Color c, float w)
        {
            float s = Math.Min(r.Width, r.Height), ox = r.X, oy = r.Y;
            using (Pen p = new Pen(c, w))
            using (SolidBrush b = new SolidBrush(c))
            {
                p.StartCap = LineCap.Round; p.EndCap = LineCap.Round; p.LineJoin = LineJoin.Round;
                switch (kind)
                {
                    case "home":
                        g.DrawLines(p, new PointF[] { P(.08f, .52f, s, ox, oy), P(.5f, .12f, s, ox, oy), P(.92f, .52f, s, ox, oy) });
                        g.DrawLines(p, new PointF[] { P(.2f, .44f, s, ox, oy), P(.2f, .9f, s, ox, oy), P(.8f, .9f, s, ox, oy), P(.8f, .44f, s, ox, oy) });
                        break;
                    case "sliders":
                        for (int i = 0; i < 3; i++)
                        {
                            float y = .2f + i * .3f, kx = (i == 0 ? .66f : i == 1 ? .32f : .55f);
                            g.DrawLine(p, P(.08f, y, s, ox, oy), P(.92f, y, s, ox, oy));
                            g.FillEllipse(b, ox + (kx - .11f) * s, oy + (y - .11f) * s, .22f * s, .22f * s);
                        }
                        break;
                    case "trash":
                        g.DrawLine(p, P(.12f, .24f, s, ox, oy), P(.88f, .24f, s, ox, oy));
                        g.DrawLines(p, new PointF[] { P(.34f, .24f, s, ox, oy), P(.38f, .08f, s, ox, oy), P(.62f, .08f, s, ox, oy), P(.66f, .24f, s, ox, oy) });
                        g.DrawLines(p, new PointF[] { P(.2f, .24f, s, ox, oy), P(.26f, .92f, s, ox, oy), P(.74f, .92f, s, ox, oy), P(.8f, .24f, s, ox, oy) });
                        break;
                    case "bolt":
                        g.DrawLines(p, new PointF[] { P(.58f, .06f, s, ox, oy), P(.22f, .55f, s, ox, oy), P(.5f, .55f, s, ox, oy), P(.4f, .94f, s, ox, oy), P(.78f, .4f, s, ox, oy), P(.5f, .4f, s, ox, oy), P(.58f, .06f, s, ox, oy) });
                        break;
                    case "chip":
                        g.DrawRectangle(p, ox + .24f * s, oy + .24f * s, .52f * s, .52f * s);
                        for (int i = 0; i < 3; i++)
                        {
                            float t = .34f + i * .16f;
                            g.DrawLine(p, P(t, .24f, s, ox, oy), P(t, .08f, s, ox, oy)); g.DrawLine(p, P(t, .76f, s, ox, oy), P(t, .92f, s, ox, oy));
                            g.DrawLine(p, P(.24f, t, s, ox, oy), P(.08f, t, s, ox, oy)); g.DrawLine(p, P(.76f, t, s, ox, oy), P(.92f, t, s, ox, oy));
                        }
                        break;
                    case "globe":
                        g.DrawEllipse(p, ox + .1f * s, oy + .1f * s, .8f * s, .8f * s);
                        g.DrawEllipse(p, ox + .34f * s, oy + .1f * s, .32f * s, .8f * s);
                        g.DrawLine(p, P(.1f, .5f, s, ox, oy), P(.9f, .5f, s, ox, oy));
                        break;
                    case "game":
                        using (GraphicsPath gp = Gfx.Round(new RectangleF(ox + .06f * s, oy + .26f * s, .88f * s, .5f * s), .22f * s)) g.DrawPath(p, gp);
                        g.DrawLine(p, P(.26f, .42f, s, ox, oy), P(.26f, .6f, s, ox, oy)); g.DrawLine(p, P(.17f, .51f, s, ox, oy), P(.35f, .51f, s, ox, oy));
                        g.FillEllipse(b, ox + .62f * s, oy + .4f * s, .1f * s, .1f * s); g.FillEllipse(b, ox + .74f * s, oy + .52f * s, .1f * s, .1f * s);
                        break;
                    case "search":
                        g.DrawEllipse(p, ox + .1f * s, oy + .1f * s, .56f * s, .56f * s);
                        g.DrawLine(p, P(.58f, .58f, s, ox, oy), P(.9f, .9f, s, ox, oy));
                        break;
                    case "shield":
                        g.DrawLines(p, new PointF[] { P(.5f, .06f, s, ox, oy), P(.86f, .2f, s, ox, oy), P(.82f, .56f, s, ox, oy), P(.5f, .94f, s, ox, oy), P(.18f, .56f, s, ox, oy), P(.14f, .2f, s, ox, oy), P(.5f, .06f, s, ox, oy) });
                        g.DrawLines(p, new PointF[] { P(.34f, .5f, s, ox, oy), P(.46f, .62f, s, ox, oy), P(.68f, .38f, s, ox, oy) });
                        break;
                    case "gear":
                        g.DrawEllipse(p, ox + .3f * s, oy + .3f * s, .4f * s, .4f * s);
                        for (int i = 0; i < 8; i++)
                        {
                            double a = i * Math.PI / 4.0; float cx = ox + .5f * s, cy = oy + .5f * s;
                            g.DrawLine(p, cx + (float)Math.Cos(a) * .3f * s, cy + (float)Math.Sin(a) * .3f * s, cx + (float)Math.Cos(a) * .44f * s, cy + (float)Math.Sin(a) * .44f * s);
                        }
                        break;
                    case "apps":
                        for (int i = 0; i < 4; i++) { float x = (i % 2) * .46f + .06f, y = (i / 2) * .46f + .06f; using (GraphicsPath gp = Gfx.Round(new RectangleF(ox + x * s, oy + y * s, .38f * s, .38f * s), .08f * s)) g.DrawPath(p, gp); }
                        break;
                    case "clock":
                        g.DrawEllipse(p, ox + .1f * s, oy + .1f * s, .8f * s, .8f * s);
                        g.DrawLines(p, new PointF[] { P(.5f, .26f, s, ox, oy), P(.5f, .5f, s, ox, oy), P(.68f, .6f, s, ox, oy) });
                        break;
                    case "undo":
                        g.DrawArc(p, ox + .16f * s, oy + .2f * s, .68f * s, .64f * s, 200, 250);
                        g.DrawLines(p, new PointF[] { P(.12f, .14f, s, ox, oy), P(.2f, .36f, s, ox, oy), P(.42f, .28f, s, ox, oy) });
                        break;
                    case "arrow":
                        g.DrawLine(p, P(.12f, .5f, s, ox, oy), P(.86f, .5f, s, ox, oy));
                        g.DrawLines(p, new PointF[] { P(.58f, .22f, s, ox, oy), P(.88f, .5f, s, ox, oy), P(.58f, .78f, s, ox, oy) });
                        break;
                    case "check":
                        g.DrawLines(p, new PointF[] { P(.16f, .54f, s, ox, oy), P(.4f, .78f, s, ox, oy), P(.86f, .24f, s, ox, oy) });
                        break;
                    case "scan":
                        g.DrawEllipse(p, ox + .12f * s, oy + .12f * s, .76f * s, .76f * s);
                        g.DrawEllipse(p, ox + .32f * s, oy + .32f * s, .36f * s, .36f * s);
                        g.FillEllipse(b, ox + .45f * s, oy + .45f * s, .1f * s, .1f * s);
                        break;
                    default:
                        g.FillEllipse(b, ox + .3f * s, oy + .3f * s, .4f * s, .4f * s);
                        break;
                }
            }
        }
    }

    public static class Native
    {
        [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int val, int size);
        [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
        [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int n);
        [DllImport("user32.dll")] static extern bool BringWindowToTop(IntPtr h);
        [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
        [DllImport("user32.dll")] static extern bool AttachThreadInput(uint a, uint b, bool f);
        [DllImport("user32.dll")] static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
        [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
        [DllImport("uxtheme.dll", CharSet = CharSet.Unicode)] static extern int SetWindowTheme(IntPtr h, string sub, string idl);
        [DllImport("user32.dll")] public static extern bool ReleaseCapture();
        [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, int msg, int w, int l);

        public static void DarkScroll(IntPtr hwnd)
        {
            try { SetWindowTheme(hwnd, "DarkMode_Explorer", null); } catch { }
        }
        public static void DarkTitle(IntPtr hwnd)
        {
            try
            {
                int one = 1;
                DwmSetWindowAttribute(hwnd, 20, ref one, 4);
                DwmSetWindowAttribute(hwnd, 19, ref one, 4);
                int cap = (Theme.Side.B << 16) | (Theme.Side.G << 8) | Theme.Side.R;
                DwmSetWindowAttribute(hwnd, 35, ref cap, 4);
                int txt = (Theme.Text.B << 16) | (Theme.Text.G << 8) | Theme.Text.R;
                DwmSetWindowAttribute(hwnd, 36, ref txt, 4);
            }
            catch { }
        }
        public static void Foreground(IntPtr hwnd)
        {
            try
            {
                ShowWindow(hwnd, 9);
                keybd_event(0x12, 0, 0, UIntPtr.Zero);
                keybd_event(0x12, 0, 2, UIntPtr.Zero);
                IntPtr fg = GetForegroundWindow();
                uint pid; uint fgT = GetWindowThreadProcessId(fg, out pid); uint me = GetCurrentThreadId();
                if (fgT != me && fgT != 0) AttachThreadInput(me, fgT, true);
                BringWindowToTop(hwnd); SetForegroundWindow(hwnd);
                if (fgT != me && fgT != 0) AttachThreadInput(me, fgT, false);
            }
            catch { }
        }
    }

    public class FzFlow : FlowLayoutPanel
    {
        public FzFlow() { this.DoubleBuffered = true; }
        protected override void OnHandleCreated(EventArgs e) { base.OnHandleCreated(e); Native.DarkScroll(Handle); }
    }

    public class FzCard : Panel
    {
        bool hot, lit;
        public int Radius = 12;
        public Color Accent = Theme.Accent;
        public bool Stripe = false;
        public bool Glow = false;
        public string Icon = null;
        public int IconSize = 18;
        public int IconX = 16;
        public int IconY = -1;
        public bool Hover = true;
        public FzCard()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            BackColor = Theme.Card;
        }
        Color unlit;
        public bool Lit
        {
            get { return lit; }
            set
            {
                if (lit == value) return;
                if (value) { unlit = BackColor; BackColor = Gfx.Mix(unlit, Accent, 0.10f); } else { BackColor = unlit; }
                lit = value; Invalidate();
            }
        }
        protected override void OnControlAdded(ControlEventArgs e)
        {
            base.OnControlAdded(e);
            e.Control.MouseEnter += ChildMouse; e.Control.MouseLeave += ChildMouse;
        }
        void ChildMouse(object s, EventArgs a) { CheckHot(); }
        protected override void OnMouseEnter(EventArgs e) { base.OnMouseEnter(e); CheckHot(); }
        protected override void OnMouseLeave(EventArgs e) { base.OnMouseLeave(e); CheckHot(); }
        void CheckHot()
        {
            if (!Hover || !IsHandleCreated) return;
            bool h = false;
            try { h = ClientRectangle.Contains(PointToClient(Cursor.Position)); } catch { }
            if (h != hot) { hot = h; Invalidate(); }
        }
        protected override void OnPaintBackground(PaintEventArgs e)
        {
            using (SolidBrush b = new SolidBrush(Gfx.BgOf(this))) e.Graphics.FillRectangle(b, e.ClipRectangle);
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics; Gfx.Quality(g);
            RectangleF r = new RectangleF(1f, 1f, Width - 3f, Height - 3f);
            using (GraphicsPath p = Gfx.Round(r, Radius))
            {
                using (SolidBrush b = new SolidBrush(BackColor)) g.FillPath(b, p);
                if (lit || Glow)
                {
                    for (int i = 3; i >= 1; i--) using (Pen gp = new Pen(Gfx.A(Accent, 16 * (4 - i)), i * 2f)) g.DrawPath(gp, p);
                }
                Color bc = lit ? Gfx.A(Accent, 215) : (hot ? Gfx.A(Accent, 130) : Theme.Border);
                using (Pen bp = new Pen(bc, lit ? 1.5f : 1f)) g.DrawPath(bp, p);
            }
            if (Stripe)
            {
                using (GraphicsPath sp = Gfx.Round(new RectangleF(1f, 14f, 4f, Math.Max(8f, Height - 30f)), 2f))
                using (SolidBrush sb = new SolidBrush(lit ? Accent : Gfx.A(Accent, 150))) g.FillPath(sb, sp);
            }
            if (Icon != null)
            {
                float iy = IconY >= 0 ? IconY : (Height - IconSize) / 2f;
                Icons.Draw(g, Icon, new RectangleF(IconX, iy, IconSize, IconSize), Gfx.A(Accent, 230), IconSize > 20 ? 2.1f : 1.7f);
            }
        }
    }

    public class FzHeader : Panel
    {
        public Color Accent = Theme.Accent;
        public FzHeader()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            BackColor = Theme.Bg;
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics; Gfx.Quality(g);
            using (SolidBrush b = new SolidBrush(Theme.Bg)) g.FillRectangle(b, ClientRectangle);
            using (GraphicsPath gp = new GraphicsPath())
            {
                gp.AddEllipse(Width - 560f, -230f, 720f, 380f);
                using (PathGradientBrush pg = new PathGradientBrush(gp))
                {
                    pg.CenterColor = Gfx.A(Accent, 62);
                    pg.SurroundColors = new Color[] { Gfx.A(Accent, 0) };
                    g.FillPath(pg, gp);
                }
            }
            using (Pen gridPen = new Pen(Gfx.A(Accent, 9), 1f))
            {
                for (int x = 0; x < Width; x += 34) g.DrawLine(gridPen, x, 0, x, Height);
                for (int y = 0; y < Height; y += 34) g.DrawLine(gridPen, 0, y, Width, y);
            }
            Rectangle lr = new Rectangle(0, Height - 2, Math.Max(2, Width), 2);
            using (LinearGradientBrush lb = new LinearGradientBrush(lr, Gfx.A(Accent, 230), Gfx.A(Accent, 0), 0f)) g.FillRectangle(lb, lr);
        }
    }

    public class FzHero : Panel
    {
        public Color Accent = Theme.Accent;
        public FzHero()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            BackColor = Color.FromArgb(14, 19, 34);
        }
        protected override void OnPaintBackground(PaintEventArgs e)
        {
            using (SolidBrush b = new SolidBrush(Gfx.BgOf(this))) e.Graphics.FillRectangle(b, e.ClipRectangle);
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics; Gfx.Quality(g);
            RectangleF r = new RectangleF(1f, 1f, Width - 3f, Height - 3f);
            using (GraphicsPath p = Gfx.Round(r, 14f))
            {
                using (SolidBrush b = new SolidBrush(BackColor)) g.FillPath(b, p);
                GraphicsState st = g.Save();
                g.SetClip(p, CombineMode.Intersect);
                using (GraphicsPath gp = new GraphicsPath())
                {
                    gp.AddEllipse(-120f, -140f, 760f, 420f);
                    using (PathGradientBrush pg = new PathGradientBrush(gp))
                    {
                        pg.CenterColor = Gfx.A(Accent, 70); pg.SurroundColors = new Color[] { Gfx.A(Accent, 0) };
                        g.FillPath(pg, gp);
                    }
                }
                using (Pen gp2 = new Pen(Gfx.A(Accent, 22), 1f))
                {
                    for (int x = 0; x < Width; x += 28) g.DrawLine(gp2, x, 0, x, Height);
                    for (int y = 0; y < Height; y += 28) g.DrawLine(gp2, 0, y, Width, y);
                }
                g.Restore(st);
                using (Pen bp = new Pen(Gfx.A(Accent, 90), 1f)) g.DrawPath(bp, p);
            }
            using (Pen br = new Pen(Accent, 2.4f))
            {
                float L = 26f, m = 12f;
                g.DrawLines(br, new PointF[] { new PointF(m, m + L), new PointF(m, m), new PointF(m + L, m) });
                g.DrawLines(br, new PointF[] { new PointF(Width - m, Height - m - L), new PointF(Width - m, Height - m), new PointF(Width - m - L, Height - m) });
            }
        }
    }

    public class FzButton : Button
    {
        bool hot, down;
        public Color Accent = Theme.Accent;
        public bool Primary = false;
        public string Icon = null;
        public int Radius = 9;
        public FzButton()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            Cursor = Cursors.Hand; Font = Theme.F(12f, true);
        }
        protected override void OnMouseEnter(EventArgs e) { base.OnMouseEnter(e); hot = true; Invalidate(); }
        protected override void OnMouseLeave(EventArgs e) { base.OnMouseLeave(e); hot = false; down = false; Invalidate(); }
        protected override void OnMouseDown(MouseEventArgs e) { base.OnMouseDown(e); down = true; Invalidate(); }
        protected override void OnMouseUp(MouseEventArgs e) { base.OnMouseUp(e); down = false; Invalidate(); }
        protected override void OnEnabledChanged(EventArgs e) { base.OnEnabledChanged(e); Invalidate(); }
        protected override void OnTextChanged(EventArgs e) { base.OnTextChanged(e); Invalidate(); }
        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics; Gfx.Quality(g);
            g.Clear(Gfx.BgOf(this));
            RectangleF r = new RectangleF(0.5f, 0.5f, Width - 2f, Height - 2f);
            Color fg; 
            using (GraphicsPath p = Gfx.Round(r, Radius))
            {
                if (!Enabled)
                {
                    using (SolidBrush b = new SolidBrush(Theme.Card2)) g.FillPath(b, p);
                    fg = Gfx.A(Theme.Dim, 150);
                }
                else if (Primary)
                {
                    Color top = Gfx.Mix(Accent, Color.White, down ? 0f : (hot ? 0.28f : 0.14f));
                    Color bot = Gfx.Mix(Accent, Color.Black, down ? 0.3f : 0.16f);
                    using (LinearGradientBrush lb = new LinearGradientBrush(new RectangleF(0, 0, Width, Height + 1), top, bot, 90f)) g.FillPath(lb, p);
                    if (hot) using (Pen gp = new Pen(Gfx.A(Accent, 90), 2.5f)) g.DrawPath(gp, p);
                    fg = Gfx.IsLight(Accent) ? Color.FromArgb(20, 12, 4) : Color.White;
                }
                else
                {
                    Color fill = hot ? Gfx.Mix(Theme.Card2, Accent, 0.18f) : Theme.Card2;
                    using (SolidBrush b = new SolidBrush(down ? Gfx.Mix(fill, Color.Black, 0.2f) : fill)) g.FillPath(b, p);
                    using (Pen bp = new Pen(hot ? Gfx.A(Accent, 200) : Theme.Border, 1.2f)) g.DrawPath(bp, p);
                    fg = hot ? Color.White : Theme.Text;
                }
            }
            float tx = 0f; float iw = 0f;
            if (Icon != null) iw = 16f;
            SizeF ts = g.MeasureString(Text, Font, 2000, StringFormat.GenericTypographic);
            float total = ts.Width + (iw > 0 ? iw + 7f : 0f);
            float sx = Math.Max(8f, (Width - total) / 2f);
            if (iw > 0) { Icons.Draw(g, Icon, new RectangleF(sx, (Height - iw) / 2f, iw, iw), fg, 1.6f); tx = sx + iw + 7f; } else tx = sx;
            using (SolidBrush tb = new SolidBrush(fg))
            using (StringFormat f = Gfx.Fmt(StringAlignment.Near, StringAlignment.Center))
                g.DrawString(Text, Font, tb, new RectangleF(tx, 0, Math.Max(10f, Width - tx - 6f), Height), f);
        }
    }

    public class FzToggle : Control
    {
        bool on; float pos; Timer t;
        public Color OnColor = Theme.Accent;
        public event EventHandler CheckedChanged;
        public FzToggle()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw | ControlStyles.Selectable, true);
            Size = new Size(46, 24); Cursor = Cursors.Hand;
            t = new Timer(); t.Interval = 14; t.Tick += Step;
        }
        public bool Checked
        {
            get { return on; }
            set { if (on == value) return; on = value; pos = on ? 1f : 0f; t.Stop(); Invalidate(); if (CheckedChanged != null) CheckedChanged(this, EventArgs.Empty); }
        }
        void Step(object s, EventArgs a)
        {
            float target = on ? 1f : 0f;
            pos += (target - pos) * 0.4f;
            if (Math.Abs(target - pos) < 0.02f) { pos = target; t.Stop(); }
            Invalidate();
        }
        protected override void OnClick(EventArgs e)
        {
            base.OnClick(e);
            if (!Enabled) return;
            on = !on; t.Start(); Invalidate();
            if (CheckedChanged != null) CheckedChanged(this, EventArgs.Empty);
        }
        protected override void OnEnabledChanged(EventArgs e) { base.OnEnabledChanged(e); Invalidate(); }
        protected override void Dispose(bool d) { if (d && t != null) { t.Stop(); t.Dispose(); } base.Dispose(d); }
        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics; Gfx.Quality(g);
            g.Clear(Gfx.BgOf(this));
            float h = Height - 4f, w = Width - 4f;
            RectangleF tr = new RectangleF(2f, 2f, w, h);
            Color offC = Color.FromArgb(52, 64, 96);
            Color c = Gfx.Mix(offC, OnColor, pos);
            if (!Enabled) c = Gfx.Mix(c, Theme.Bg, 0.5f);
            using (GraphicsPath p = Gfx.Round(tr, h / 2f))
            {
                if (pos > 0.05f) using (Pen gp = new Pen(Gfx.A(OnColor, (int)(60 * pos)), 3f)) g.DrawPath(gp, p);
                using (SolidBrush b = new SolidBrush(c)) g.FillPath(b, p);
            }
            float d = h - 6f;
            float kx = 2f + 3f + pos * (w - 6f - d);
            using (SolidBrush kb = new SolidBrush(Enabled ? Color.White : Theme.Dim)) g.FillEllipse(kb, kx, 2f + 3f, d, d);
        }
    }

    public class FzProgress : Control
    {
        int max = 100, val = 0;
        public Color Accent = Theme.Accent;
        public FzProgress()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            Height = 6;
        }
        public int Maximum { get { return max; } set { max = Math.Max(1, value); Invalidate(); } }
        public int Value { get { return val; } set { val = Math.Max(0, Math.Min(max, value)); Invalidate(); } }
        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics; Gfx.Quality(g);
            g.Clear(Gfx.BgOf(this));
            RectangleF tr = new RectangleF(0, 0, Width - 1f, Height - 1f);
            using (GraphicsPath p = Gfx.Round(tr, Height / 2f)) using (SolidBrush b = new SolidBrush(Theme.Card2)) g.FillPath(b, p);
            float fw = (Width - 1f) * val / (float)max;
            if (fw >= Height)
            {
                RectangleF fr = new RectangleF(0, 0, fw, Height - 1f);
                using (GraphicsPath p = Gfx.Round(fr, Height / 2f))
                using (LinearGradientBrush lb = new LinearGradientBrush(new RectangleF(0, 0, Math.Max(2f, fw), Height), Gfx.Mix(Accent, Color.Black, 0.25f), Gfx.Mix(Accent, Color.White, 0.25f), 0f))
                    g.FillPath(lb, p);
            }
        }
    }

    public class FzPill : Control
    {
        public Color Tint = Theme.Good;
        public FzPill()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            Font = Theme.M(11f, true); Height = 20;
        }
        public void Fit()
        {
            Size s = TextRenderer.MeasureText(Text, Font, new Size(2000, 40), TextFormatFlags.NoPadding);
            Width = s.Width + 20; 
        }
        protected override void OnTextChanged(EventArgs e) { base.OnTextChanged(e); Invalidate(); }
        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics; Gfx.Quality(g);
            g.Clear(Gfx.BgOf(this));
            RectangleF r = new RectangleF(0.5f, 0.5f, Width - 2f, Height - 2f);
            using (GraphicsPath p = Gfx.Round(r, (Height - 2f) / 2f))
            {
                using (SolidBrush b = new SolidBrush(Gfx.A(Tint, 34))) g.FillPath(b, p);
                using (Pen pen = new Pen(Gfx.A(Tint, 110), 1f)) g.DrawPath(pen, p);
            }
            using (SolidBrush tb = new SolidBrush(Tint)) using (StringFormat f = Gfx.Fmt(StringAlignment.Center, StringAlignment.Center))
                g.DrawString(Text, Font, tb, new RectangleF(0, 0, Width, Height), f);
        }
    }

    public class FzNav : Control
    {
        bool hot;
        public Color Accent = Theme.Accent;
        public string Icon = "home";
        public string Badge = "";
        public bool Selected = false;
        public FzNav()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            Cursor = Cursors.Hand; Height = 44;
        }
        public void Select(bool s) { Selected = s; Invalidate(); }
        protected override void OnMouseEnter(EventArgs e) { base.OnMouseEnter(e); hot = true; Invalidate(); }
        protected override void OnMouseLeave(EventArgs e) { base.OnMouseLeave(e); hot = false; Invalidate(); }
        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics; Gfx.Quality(g);
            g.Clear(Gfx.BgOf(this));
            RectangleF r = new RectangleF(8f, 2f, Width - 16f, Height - 5f);
            using (GraphicsPath p = Gfx.Round(r, 10f))
            {
                if (Selected)
                {
                    using (SolidBrush b = new SolidBrush(Gfx.Mix(Theme.Side, Accent, 0.17f))) g.FillPath(b, p);
                    using (Pen pen = new Pen(Gfx.A(Accent, 120), 1.2f)) g.DrawPath(pen, p);
                }
                else if (hot) using (SolidBrush b = new SolidBrush(Theme.Card)) g.FillPath(b, p);
            }
            if (Selected) using (GraphicsPath bp = Gfx.Round(new RectangleF(8f, 11f, 4f, Height - 22f), 2f)) using (SolidBrush bb = new SolidBrush(Accent)) g.FillPath(bb, bp);
            Color ic = Selected ? Accent : (hot ? Gfx.Mix(Theme.Dim, Accent, 0.6f) : Gfx.Mix(Theme.Dim, Accent, 0.28f));
            Icons.Draw(g, Icon, new RectangleF(24f, (Height - 18f) / 2f, 18f, 18f), ic, 1.7f);
            Font f = Theme.F(14f, true);
            using (SolidBrush tb = new SolidBrush(Selected || hot ? Theme.Text : Gfx.Mix(Theme.Dim, Theme.Text, 0.4f))) using (StringFormat sf = Gfx.Fmt(StringAlignment.Near, StringAlignment.Center))
                g.DrawString(Text, f, tb, new RectangleF(54f, 0, Width - 110f, Height), sf);
            if (!string.IsNullOrEmpty(Badge))
            {
                Font bf = Theme.M(11f, true);
                SizeF bs = g.MeasureString(Badge, bf, 100, StringFormat.GenericTypographic);
                float bw = bs.Width + 14f, bx = Width - 18f - bw;
                RectangleF br = new RectangleF(bx, (Height - 20f) / 2f, bw, 20f);
                using (GraphicsPath bp = Gfx.Round(br, 10f))
                {
                    using (SolidBrush bb = new SolidBrush(Selected ? Gfx.A(Accent, 50) : Theme.Card2)) g.FillPath(bb, bp);
                }
                using (SolidBrush tb = new SolidBrush(Selected ? Accent : Theme.Dim)) using (StringFormat sf = Gfx.Fmt(StringAlignment.Center, StringAlignment.Center)) g.DrawString(Badge, bf, tb, br, sf);
            }
        }
    }

    public class FzChip : Control
    {
        bool hot, chk;
        public Color Accent = Theme.Accent;
        public string Sub = "";
        public string Status = "";
        public Color StatusColor = Theme.Dim;
        public bool Locked = false;
        public bool ShowCheck = true;
        public string Group = "";
        public event EventHandler CheckedChanged;
        public FzChip()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            Height = 58; Cursor = Cursors.Hand;
        }
        public bool Checked
        {
            get { return chk; }
            set { if (chk == value) return; chk = value; Invalidate(); if (CheckedChanged != null) CheckedChanged(this, EventArgs.Empty); }
        }
        protected override void OnMouseEnter(EventArgs e) { base.OnMouseEnter(e); hot = true; Invalidate(); }
        protected override void OnMouseLeave(EventArgs e) { base.OnMouseLeave(e); hot = false; Invalidate(); }
        protected override void OnClick(EventArgs e) { base.OnClick(e); if (ShowCheck && !Locked) Checked = !chk; }
        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics; Gfx.Quality(g);
            g.Clear(Gfx.BgOf(this));
            RectangleF r = new RectangleF(3f, 3f, Width - 7f, Height - 7f);
            Color fill = chk ? Gfx.Mix(Theme.Card, Accent, 0.17f) : (Locked ? Gfx.Mix(Theme.Bg, Theme.Card, 0.55f) : (hot ? Gfx.Mix(Theme.Card, Theme.Card2, 0.6f) : Theme.Card));
            using (GraphicsPath p = Gfx.Round(r, 10f))
            {
                using (SolidBrush b = new SolidBrush(fill)) g.FillPath(b, p);
                if (chk) for (int i = 3; i >= 1; i--) using (Pen gp = new Pen(Gfx.A(Accent, 22 * (4 - i)), i * 2f)) g.DrawPath(gp, p);
                Color bc = chk ? Accent : (hot && !Locked ? Gfx.A(Accent, 150) : Theme.Border);
                using (Pen bp = new Pen(bc, chk ? 1.6f : 1f)) g.DrawPath(bp, p);
            }
            float lx = 18f;
            if (ShowCheck)
            {
                RectangleF cr = new RectangleF(16f, (Height - 22f) / 2f, 22f, 22f);
                if (chk)
                {
                    using (SolidBrush cb = new SolidBrush(Accent)) g.FillEllipse(cb, cr);
                    Icons.Draw(g, "check", new RectangleF(cr.X + 4f, cr.Y + 4f, 14f, 14f), Gfx.IsLight(Accent) ? Color.FromArgb(20, 12, 4) : Color.White, 2.2f);
                }
                else using (Pen rp = new Pen(Locked ? Theme.Border : Gfx.Mix(Theme.Border, Theme.Dim, 0.5f), 1.8f)) g.DrawEllipse(rp, cr.X + 1f, cr.Y + 1f, cr.Width - 2f, cr.Height - 2f);
                lx = 50f;
            }
            else using (GraphicsPath bp = Gfx.Round(new RectangleF(12f, 14f, 4f, Height - 28f), 2f)) using (SolidBrush bb = new SolidBrush(StatusColor)) g.FillPath(bb, bp);
            if (!ShowCheck) lx = 28f;
            Font tf = Theme.F(14f, true), sf = Theme.F(12f, false), stf = Theme.M(11f, true);
            float stw = 0f;
            if (!string.IsNullOrEmpty(Status)) stw = g.MeasureString(Status, stf, 400, StringFormat.GenericTypographic).Width + 8f;
            float tw = Math.Max(30f, Width - lx - stw - 22f);
            bool two = !string.IsNullOrEmpty(Sub);
            using (SolidBrush tb = new SolidBrush(Locked ? Theme.Dim : Theme.Text)) using (StringFormat f = Gfx.Fmt(StringAlignment.Near, StringAlignment.Center))
                g.DrawString(Text, tf, tb, new RectangleF(lx, two ? 8f : 0f, tw, two ? 24f : Height), f);
            if (two) using (SolidBrush sb = new SolidBrush(Theme.Dim)) using (StringFormat f = Gfx.Fmt(StringAlignment.Near, StringAlignment.Center))
                g.DrawString(Sub, sf, sb, new RectangleF(lx, 29f, Math.Max(30f, Width - lx - 16f), 20f), f);
            if (stw > 0f) using (SolidBrush sb = new SolidBrush(StatusColor)) using (StringFormat f = Gfx.Fmt(StringAlignment.Far, StringAlignment.Near))
                g.DrawString(Status, stf, sb, new RectangleF(Width - 16f - stw, 10f, stw, 20f), f);
        }
    }

    public static class Msg
    {
        public static DialogResult Show(string text, string title) { return Show(text, title, MessageBoxButtons.OK, MessageBoxIcon.None); }
        public static DialogResult Show(string text, string title, MessageBoxButtons buttons) { return Show(text, title, buttons, MessageBoxIcon.None); }
        public static DialogResult Show(string text, string title, MessageBoxButtons buttons, MessageBoxIcon icon)
        {
            Color acc = Theme.Accent; string ic = "bolt";
            if (icon == MessageBoxIcon.Warning) { acc = Theme.Warn; ic = "shield"; }
            else if (icon == MessageBoxIcon.Error) { acc = Theme.Bad; ic = "shield"; }
            else if (icon == MessageBoxIcon.Question) { acc = Color.FromArgb(77, 141, 255); ic = "sliders"; }
            else if (icon == MessageBoxIcon.Information) { acc = Color.FromArgb(34, 211, 238); ic = "check"; }
            Form owner = Form.ActiveForm;
            Form f = new Form();
            f.FormBorderStyle = FormBorderStyle.None; f.ShowInTaskbar = false; f.StartPosition = FormStartPosition.CenterScreen;
            f.BackColor = Theme.Card; f.TopMost = true; f.KeyPreview = true;
            int W = 540;
            Font tf = Theme.F(14f, false);
            Size ms = TextRenderer.MeasureText(text, tf, new Size(W - 96, 0), TextFormatFlags.WordBreak | TextFormatFlags.NoPadding);
            bool scroll = ms.Height > 330;
            int bodyH = scroll ? 330 : Math.Max(24, ms.Height + 4);
            int H = 70 + bodyH + 76;
            f.ClientSize = new Size(W, H);
            Control body;
            if (scroll)
            {
                TextBox tb = new TextBox(); tb.Multiline = true; tb.ReadOnly = true; tb.ScrollBars = ScrollBars.Vertical; tb.BorderStyle = BorderStyle.None;
                tb.BackColor = Theme.Card; tb.ForeColor = Theme.Text; tb.Font = tf; tb.Text = text; tb.TabStop = false; body = tb;
            }
            else { Label lb = new Label(); lb.Text = text; lb.Font = tf; lb.ForeColor = Theme.Text; lb.BackColor = Color.Transparent; lb.UseMnemonic = false; body = lb; }
            body.Location = new Point(48, 66); body.Size = new Size(W - 96, bodyH);
            Label tl = new Label(); tl.Text = title.ToUpper(); tl.Font = Theme.F(17f, true); tl.ForeColor = Theme.Text; tl.BackColor = Color.Transparent;
            tl.UseMnemonic = false; tl.Location = new Point(48, 24); tl.Size = new Size(W - 96, 30);
            f.Controls.Add(body); f.Controls.Add(tl);
            Color accC = acc; string icC = ic;
            f.Paint += delegate(object s, PaintEventArgs e)
            {
                Graphics g = e.Graphics; Gfx.Quality(g);
                using (Pen bp = new Pen(Gfx.A(accC, 200), 1.6f)) g.DrawRectangle(bp, 0, 0, f.Width - 1, f.Height - 1);
                using (SolidBrush ab = new SolidBrush(accC)) g.FillRectangle(ab, 0, 0, 5, f.Height);
                Icons.Draw(g, icC, new RectangleF(18f, 28f, 22f, 22f), accC, 2f);
            };
            f.MouseDown += delegate(object s, MouseEventArgs e) { Native.ReleaseCapture(); Native.SendMessage(f.Handle, 0xA1, 2, 0); };
            tl.MouseDown += delegate(object s, MouseEventArgs e) { Native.ReleaseCapture(); Native.SendMessage(f.Handle, 0xA1, 2, 0); };
            List<FzButton> btns = new List<FzButton>();
            Action<string, DialogResult, bool> add = delegate(string t, DialogResult r, bool primary)
            {
                FzButton b = new FzButton(); b.Text = t; b.Primary = primary; b.Accent = primary ? accC : Theme.Dim; b.Size = new Size(110, 38); b.DialogResult = r; btns.Add(b);
            };
            DialogResult esc = DialogResult.Cancel;
            switch (buttons)
            {
                case MessageBoxButtons.YesNo: add("NO", DialogResult.No, false); add("YES", DialogResult.Yes, true); esc = DialogResult.No; break;
                case MessageBoxButtons.YesNoCancel: add("CANCEL", DialogResult.Cancel, false); add("NO", DialogResult.No, false); add("YES", DialogResult.Yes, true); break;
                case MessageBoxButtons.OKCancel: add("CANCEL", DialogResult.Cancel, false); add("OK", DialogResult.OK, true); break;
                default: add("OK", DialogResult.OK, true); esc = DialogResult.OK; break;
            }
            int x = W - 28;
            for (int i = btns.Count - 1; i >= 0; i--) { x -= btns[i].Width; btns[i].Location = new Point(x, H - 58); x -= 10; f.Controls.Add(btns[i]); }
            DialogResult escC = esc;
            f.KeyDown += delegate(object s, KeyEventArgs e) { if (e.KeyCode == Keys.Escape) { f.DialogResult = escC; f.Close(); } };
            f.Shown += delegate(object s, EventArgs e) { f.Activate(); };
            try { f.Region = new Region(Gfx.Round(new RectangleF(0, 0, f.Width, f.Height), 14f)); } catch { }
            DialogResult res = DialogResult.Cancel;
            try { res = owner != null ? f.ShowDialog(owner) : f.ShowDialog(); } finally { f.Dispose(); }
            return res;
        }
    }
}
'@
if (-not ('Fz.FzCard' -as [type])) {
    try { Add-Type -TypeDefinition $script:FzSource -ReferencedAssemblies 'System.Windows.Forms', 'System.Drawing' }
    catch { if (-not ('Fz.FzCard' -as [type])) { throw } }
}
$script:HeadFont = 'Segoe UI'
try { if ((New-Object Drawing.Text.InstalledFontCollection).Families | Where-Object { $_.Name -eq 'Bahnschrift' }) { $script:HeadFont = 'Bahnschrift' } } catch {}
[Fz.Theme]::Head = $script:HeadFont
function Pump { [System.Windows.Forms.Application]::DoEvents() }

# ---------- Paths / state ----------
$script:Dir       = Join-Path $env:ProgramData 'FrenzyTweaks'
$script:StateFile = Join-Path $script:Dir 'state.json'
$script:LogFile   = Join-Path $script:Dir 'tweaker.log'
New-Item -ItemType Directory -Path $script:Dir -Force | Out-Null
# one-time migration of the undo/backup state from the old folder name
$oldState = Join-Path (Join-Path $env:ProgramData 'FortniteTweaker') 'state.json'
if (-not (Test-Path $script:StateFile) -and (Test-Path $oldState)) { Copy-Item $oldState $script:StateFile -Force }
$script:Root = if ($PSCommandPath) { Split-Path -Parent $PSCommandPath } else { $script:Dir }
$script:State  = @{}
$script:Tweaks = New-Object System.Collections.ArrayList
$script:LogBox = $null
$script:RebootNeeded = $false

function Load-State {
    if (Test-Path $script:StateFile) {
        try {
            $o = Get-Content $script:StateFile -Raw | ConvertFrom-Json
            foreach ($p in $o.PSObject.Properties) { $script:State[$p.Name] = $p.Value }
        } catch {}
    }
}
function Save-State { $script:State | ConvertTo-Json -Depth 6 | Set-Content -Path $script:StateFile -Encoding UTF8 }

function Log([string]$m, [string]$lvl = 'INFO') {
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format 'HH:mm:ss'), $lvl, $m
    Add-Content -Path $script:LogFile -Value $line -ErrorAction SilentlyContinue
    if ($script:LogBox) {
        $script:LogBox.AppendText($line + "`r`n")
        [System.Windows.Forms.Application]::DoEvents()
    }
}

# ---------- Helpers ----------
function Backup-Reg($Path, $Name) {
    $k = "reg|$Path|$Name"
    if ($script:State.ContainsKey($k)) { return }
    try {
        $item = Get-Item -LiteralPath $Path -ErrorAction Stop
        if ($item.GetValueNames() -contains $Name) {
            $kind = $item.GetValueKind($Name).ToString()
            if ($kind -notin 'DWord', 'QWord', 'String', 'ExpandString') { return }
            $script:State[$k] = @{ Absent = $false; K = $kind; V = $item.GetValue($Name, $null, 'DoNotExpandEnvironmentNames') }
        } else { $script:State[$k] = @{ Absent = $true } }
    } catch { $script:State[$k] = @{ Absent = $true } }
    Save-State
}
function Set-Reg($Path, $Name, $Value, $Type = 'DWord', [switch]$NoBackup) {
    if (-not $NoBackup) { Backup-Reg $Path $Name }
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
}
function Remove-Reg($Path, $Name) { Remove-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue }
function Restore-Reg($Path, $Name, $Fallback, $Type = 'DWord') {
    $k = "reg|$Path|$Name"
    if ($script:State.ContainsKey($k)) {
        $o = $script:State[$k]; $script:State.Remove($k); Save-State
        if ($o.Absent) { Remove-Reg $Path $Name } else { Set-Reg $Path $Name $o.V $o.K -NoBackup }
        return
    }
    if ($null -ne $Fallback) { Set-Reg $Path $Name $Fallback $Type -NoBackup } else { Remove-Reg $Path $Name }
}
function Get-GuidFrom([string]$Text) {
    $m = [regex]::Match($Text, '[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}')
    if ($m.Success) { return $m.Value } else { return $null }
}

function Disable-Svc([string]$Name) {
    $key = "HKLM:\SYSTEM\CurrentControlSet\Services\$Name"
    if (-not (Test-Path $key)) { Log "Service $Name not present - skipped" 'WARN'; return }
    $p = Get-ItemProperty $key
    $sk = "svc:$Name"
    if (-not $script:State.ContainsKey($sk)) {
        $d = $null; if ($null -ne $p.DelayedAutostart) { $d = [int]$p.DelayedAutostart }
        $script:State[$sk] = @{ Start = [int]$p.Start; Delayed = $d; When = (Get-Date).ToString('g') }
        Save-State
    }
    try { Set-ItemProperty -Path $key -Name Start -Value 4 -ErrorAction Stop }
    catch { & sc.exe config $Name start= disabled | Out-Null }
    Get-Service -Name "$Name*" -ErrorAction SilentlyContinue | ForEach-Object {
        try { Stop-Service -InputObject $_ -Force -ErrorAction Stop } catch {}
    }
    Log "Disabled service $Name (original start=$($p.Start))"
}
function Enable-Svc([string]$Name) {
    $sk = "svc:$Name"
    if (-not $script:State.ContainsKey($sk)) { Log "No saved state for $Name - skipped" 'WARN'; return }
    $o = $script:State[$sk]
    $key = "HKLM:\SYSTEM\CurrentControlSet\Services\$Name"
    try {
        Set-ItemProperty -Path $key -Name Start -Value ([int]$o.Start) -ErrorAction Stop
        if ($null -ne $o.Delayed) { Set-ItemProperty -Path $key -Name DelayedAutostart -Value ([int]$o.Delayed) }
    } catch { Log "Could not restore $Name : $($_.Exception.Message)" 'WARN' }
    if ([int]$o.Start -le 2) { Start-Service -Name $Name -ErrorAction SilentlyContinue }
    $script:State.Remove($sk); Save-State
    Log "Restored service $Name"
}

function Set-Task([string]$Full, [bool]$Enable) {
    $i = $Full.LastIndexOf('\'); $tp = $Full.Substring(0, $i + 1); $tn = $Full.Substring($i + 1)
    $t = Get-ScheduledTask -TaskPath $tp -TaskName $tn -ErrorAction SilentlyContinue
    if (-not $t) { Log "Task $Full not found - skipped" 'WARN'; return }
    $tk = "task:$Full"
    if (-not $Enable) {
        if ($t.State -eq 'Disabled') { return }
        try { Disable-ScheduledTask -TaskPath $tp -TaskName $tn -ErrorAction Stop | Out-Null }
        catch { & schtasks.exe /Change /TN $Full /DISABLE | Out-Null }
        $script:State[$tk] = $true; Save-State
        Log "Disabled task $Full"
    } else {
        if (-not $script:State.ContainsKey($tk)) { return }
        try { Enable-ScheduledTask -TaskPath $tp -TaskName $tn -ErrorAction Stop | Out-Null }
        catch { & schtasks.exe /Change /TN $Full /ENABLE | Out-Null }
        $script:State.Remove($tk); Save-State
        Log "Re-enabled task $Full"
    }
}

function Disable-Feat([string[]]$Names) {
    foreach ($n in $Names) {
        $f = Get-WindowsOptionalFeature -Online -FeatureName $n -ErrorAction SilentlyContinue
        if ($f -and $f.State -eq 'Enabled') {
            Disable-WindowsOptionalFeature -Online -FeatureName $n -NoRestart -ErrorAction SilentlyContinue | Out-Null
            $script:State["feat:$n"] = $true; Save-State
            $script:RebootNeeded = $true
            Log "Disabled feature $n"
        }
    }
}
function Enable-Feat([string[]]$Names) {
    foreach ($n in $Names) {
        if ($script:State.ContainsKey("feat:$n")) {
            Enable-WindowsOptionalFeature -Online -FeatureName $n -NoRestart -ErrorAction SilentlyContinue | Out-Null
            $script:State.Remove("feat:$n"); Save-State
            $script:RebootNeeded = $true
            Log "Re-enabled feature $n"
        }
    }
}

function Clear-Folder([string]$Path, [string]$Filter = '*') {
    if (-not (Test-Path $Path)) { Log "$Path not found" 'WARN'; return }
    $items = Get-ChildItem -Path $Path -Filter $Filter -Force -ErrorAction SilentlyContinue
    $size = ($items | Get-ChildItem -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    $items | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Log ("Cleaned {0} (~{1} MB)" -f $Path, [math]::Round(([double]$size) / 1MB, 1))
}

function Set-NicProp([string[]]$Keywords, $Value) {
    foreach ($nic in (Get-NetAdapter -Physical -ErrorAction SilentlyContinue)) {
        foreach ($kw in $Keywords) {
            $prop = Get-NetAdapterAdvancedProperty -Name $nic.Name -RegistryKeyword $kw -ErrorAction SilentlyContinue
            if ($prop) {
                $sk = "nic|$($nic.Name)|$kw"
                if (-not $script:State.ContainsKey($sk)) { $script:State[$sk] = "$($prop.RegistryValue[0])"; Save-State }
                try { Set-NetAdapterAdvancedProperty -Name $nic.Name -RegistryKeyword $kw -RegistryValue $Value -ErrorAction Stop; Log "NIC $($nic.Name): $kw = $Value" }
                catch { Log "NIC $($nic.Name) $kw failed: $($_.Exception.Message)" 'WARN' }
            }
        }
    }
}
function Restore-NicProp([string[]]$Keywords) {
    foreach ($k in @($script:State.Keys | Where-Object { $_ -like 'nic|*' })) {
        $parts = $k.Split('|')
        if ($Keywords -contains $parts[2]) {
            try { Set-NetAdapterAdvancedProperty -Name $parts[1] -RegistryKeyword $parts[2] -RegistryValue $script:State[$k] -ErrorAction Stop; Log "NIC $($parts[1]): $($parts[2]) restored" } catch {}
            $script:State.Remove($k)
        }
    }
    Save-State
}

# ---------- Dialog helpers ----------
function Confirm-Action([string]$Title, [string]$Msg) {
    return ([Fz.Msg]::Show($Msg, $Title, 'YesNo', 'Warning') -eq 'Yes')
}
function Select-FromList([string]$Title, [string]$Prompt, [string[]]$Items) {
    $f = New-Object Windows.Forms.Form
    $f.Text = $Title; $f.Size = New-Object Drawing.Size(540, 560); $f.StartPosition = 'CenterScreen'
    $f.BackColor = [Drawing.Color]::FromArgb(24, 24, 30); $f.ForeColor = [Drawing.Color]::White
    $lbl = New-Object Windows.Forms.Label; $lbl.Text = $Prompt; $lbl.Dock = 'Top'; $lbl.Height = 60; $lbl.Padding = New-Object Windows.Forms.Padding(8)
    $cl = New-Object Windows.Forms.CheckedListBox; $cl.Dock = 'Fill'; $cl.CheckOnClick = $true
    $cl.BackColor = [Drawing.Color]::FromArgb(14, 14, 18); $cl.ForeColor = [Drawing.Color]::White; $cl.BorderStyle = 'None'
    foreach ($i in $Items) { [void]$cl.Items.Add($i, $true) }
    $pn = New-Object Windows.Forms.FlowLayoutPanel; $pn.Dock = 'Bottom'; $pn.Height = 46; $pn.FlowDirection = 'RightToLeft'; $pn.Padding = New-Object Windows.Forms.Padding(8)
    $ok = New-Object Windows.Forms.Button; $ok.Text = 'Remove selected'; $ok.Width = 130; $ok.DialogResult = 'OK'
    $no = New-Object Windows.Forms.Button; $no.Text = 'Skip'; $no.Width = 90; $no.DialogResult = 'Cancel'
    $all = New-Object Windows.Forms.Button; $all.Text = 'Toggle all'; $all.Width = 90
    $all.Add_Click({ $s = ($cl.CheckedItems.Count -lt $cl.Items.Count); for ($k = 0; $k -lt $cl.Items.Count; $k++) { $cl.SetItemChecked($k, $s) } }.GetNewClosure())
    $pn.Controls.AddRange(@($ok, $no, $all))
    $f.Controls.Add($cl); $f.Controls.Add($pn); $f.Controls.Add($lbl); $cl.BringToFront()
    $f.AcceptButton = $ok; $f.CancelButton = $no
    $res = @()
    if ($f.ShowDialog() -eq 'OK') { $res = @($cl.CheckedItems | ForEach-Object { [string]$_ }) }
    $f.Dispose()
    return , $res
}

# ---------- Fortnite helpers ----------
$script:FnCfg     = "$env:LOCALAPPDATA\FortniteGame\Saved\Config\WindowsClient\GameUserSettings.ini"
$script:FnSection = '/Script/FortniteGame.FortGameUserSettings'
$script:HasNvidia = $false
try { $script:HasNvidia = [bool](Get-CimInstance Win32_VideoController -ErrorAction Stop | Where-Object { $_.Name -match 'NVIDIA' }) } catch {}
$script:NipB64    = '77u/PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0idXRmLTE2Ij8+DQo8QXJyYXlPZlByb2ZpbGU+DQogIDxQcm9maWxlPg0KICAgIDxQcm9maWxlTmFtZT5Gb3J0bml0ZTwvUHJvZmlsZU5hbWU+DQogICAgPEV4ZWN1dGVhYmxlcz4NCiAgICAgIDxzdHJpbmc+Zm9ydG5pdGVsYXVuY2hlci5leGU8L3N0cmluZz4NCiAgICAgIDxzdHJpbmc+Zm9ydG5pdGVjbGllbnQtd2luNjQtc2hpcHBpbmdfYmUuZXhlPC9zdHJpbmc+DQogICAgICA8c3RyaW5nPmZvcnRuaXRlY2xpZW50LXdpbjY0LXNoaXBwaW5nX2VhY19lb3MuZXhlPC9zdHJpbmc+DQogICAgICA8c3RyaW5nPmZvcnRuaXRlY2xpZW50LmV4ZTwvc3RyaW5nPg0KICAgICAgPHN0cmluZz5mb3J0bml0ZWNsaWVudC13aW42NC1zaGlwcGluZy5leGU8L3N0cmluZz4NCiAgICAgIDxzdHJpbmc+Zm9ydG5pdGVjbGllbnQtd2luNjQtdGVzdC5leGU8L3N0cmluZz4NCiAgICAgIDxzdHJpbmc+Zm9ydG5pdGVjbGllbnQtd2luNjQtc2hpcHBpbmdfZWFjLmV4ZTwvc3RyaW5nPg0KICAgIDwvRXhlY3V0ZWFibGVzPg0KICAgIDxTZXR0aW5ncz4NCiAgICAgIDxQcm9maWxlU2V0dGluZz4NCiAgICAgICAgPFNldHRpbmdOYW1lSW5mbz4gPC9TZXR0aW5nTmFtZUluZm8+DQogICAgICAgIDxTZXR0aW5nSUQ+MzkwNDY3PC9TZXR0aW5nSUQ+DQogICAgICAgIDxTZXR0aW5nVmFsdWU+MjwvU2V0dGluZ1ZhbHVlPg0KICAgICAgICA8VmFsdWVUeXBlPkR3b3JkPC9WYWx1ZVR5cGU+DQogICAgICA8L1Byb2ZpbGVTZXR0aW5nPg0KICAgICAgPFByb2ZpbGVTZXR0aW5nPg0KICAgICAgICA8U2V0dGluZ05hbWVJbmZvPlRleHR1cmUgZmlsdGVyaW5nIC0gTmVnYXRpdmUgTE9EIGJpYXM8L1NldHRpbmdOYW1lSW5mbz4NCiAgICAgICAgPFNldHRpbmdJRD4xNjg2Mzc2PC9TZXR0aW5nSUQ+DQogICAgICAgIDxTZXR0aW5nVmFsdWU+MTwvU2V0dGluZ1ZhbHVlPg0KICAgICAgICA8VmFsdWVUeXBlPkR3b3JkPC9WYWx1ZVR5cGU+DQogICAgICA8L1Byb2ZpbGVTZXR0aW5nPg0KICAgICAgPFByb2ZpbGVTZXR0aW5nPg0KICAgICAgICA8U2V0dGluZ05hbWVJbmZvPlNoYXJwZW5pbmcgVmFsdWU8L1NldHRpbmdOYW1lSW5mbz4NCiAgICAgICAgPFNldHRpbmdJRD4zMDcwMTU3PC9TZXR0aW5nSUQ+DQogICAgICAgIDxTZXR0aW5nVmFsdWU+MDwvU2V0dGluZ1ZhbHVlPg0KICAgICAgICA8VmFsdWVUeXBlPkR3b3JkPC9WYWx1ZVR5cGU+DQogICAgICA8L1Byb2ZpbGVTZXR0aW5nPg0KICAgICAgPFByb2ZpbGVTZXR0aW5nPg0KICAgICAgICA8U2V0dGluZ05hbWVJbmZvPlNoYXJwZW5pbmcgLSBEZW5vaXNpbmcgRmFjdG9yPC9TZXR0aW5nTmFtZUluZm8+DQogICAgICAgIDxTZXR0aW5nSUQ+MzA3MDE1ODwvU2V0dGluZ0lEPg0KICAgICAgICA8U2V0dGluZ1ZhbHVlPjA8L1NldHRpbmdWYWx1ZT4NCiAgICAgICAgPFZhbHVlVHlwZT5Ed29yZDwvVmFsdWVUeXBlPg0KICAgICAgPC9Qcm9maWxlU2V0dGluZz4NCiAgICAgIDxQcm9maWxlU2V0dGluZz4NCiAgICAgICAgPFNldHRpbmdOYW1lSW5mbz5ETFNTIE1vZGVsIFByZXNldCBQcm9maWxlPC9TZXR0aW5nTmFtZUluZm8+DQogICAgICAgIDxTZXR0aW5nSUQ+NjUwNTEwNTwvU2V0dGluZ0lEPg0KICAgICAgICA8U2V0dGluZ1ZhbHVlPjA8L1NldHRpbmdWYWx1ZT4NCiAgICAgICAgPFZhbHVlVHlwZT5Ed29yZDwvVmFsdWVUeXBlPg0KICAgICAgPC9Qcm9maWxlU2V0dGluZz4NCiAgICAgIDxQcm9maWxlU2V0dGluZz4NCiAgICAgICAgPFNldHRpbmdOYW1lSW5mbz5QcmVmZXJyZWQgcmVmcmVzaCByYXRlPC9TZXR0aW5nTmFtZUluZm8+DQogICAgICAgIDxTZXR0aW5nSUQ+NjYwMDAwMTwvU2V0dGluZ0lEPg0KICAgICAgICA8U2V0dGluZ1ZhbHVlPjA8L1NldHRpbmdWYWx1ZT4NCiAgICAgICAgPFZhbHVlVHlwZT5Ed29yZDwvVmFsdWVUeXBlPg0KICAgICAgPC9Qcm9maWxlU2V0dGluZz4NCiAgICAgIDxQcm9maWxlU2V0dGluZz4NCiAgICAgICAgPFNldHRpbmdOYW1lSW5mbz5NYXhpbXVtIHByZS1yZW5kZXJlZCBmcmFtZXM8L1NldHRpbmdOYW1lSW5mbz4NCiAgICAgICAgPFNldHRpbmdJRD44MTAyMDQ2PC9TZXR0aW5nSUQ+DQogICAgICAgIDxTZXR0aW5nVmFsdWU+MTwvU2V0dGluZ1ZhbHVlPg0KICAgICAgICA8VmFsdWVUeXBlPkR3b3JkPC9WYWx1ZVR5cGU+DQogICAgICA8L1Byb2ZpbGVTZXR0aW5nPg0KICAgICAgPFByb2ZpbGVTZXR0aW5nPg0KICAgICAgICA8U2V0dGluZ05hbWVJbmZvPlRleHR1cmUgZmlsdGVyaW5nIC0gQW5pc290cm9waWMgZmlsdGVyIG9wdGltaXphdGlvbjwvU2V0dGluZ05hbWVJbmZvPg0KICAgICAgICA8U2V0dGluZ0lEPjg3MDMzNDQ8L1NldHRpbmdJRD4NCiAgICAgICAgPFNldHRpbmdWYWx1ZT4xPC9TZXR0aW5nVmFsdWU+DQogICAgICAgIDxWYWx1ZVR5cGU+RHdvcmQ8L1ZhbHVlVHlwZT4NCiAgICAgIDwvUHJvZmlsZVNldHRpbmc+DQogICAgICA8UHJvZmlsZVNldHRpbmc+DQogICAgICAgIDxTZXR0aW5nTmFtZUluZm8+VmVydGljYWwgU3luYzwvU2V0dGluZ05hbWVJbmZvPg0KICAgICAgICA8U2V0dGluZ0lEPjExMDQxMjMxPC9TZXR0aW5nSUQ+DQogICAgICAgIDxTZXR0aW5nVmFsdWU+MTM4NTA0MDA3PC9TZXR0aW5nVmFsdWU+DQogICAgICAgIDxWYWx1ZVR5cGU+RHdvcmQ8L1ZhbHVlVHlwZT4NCiAgICAgIDwvUHJvZmlsZVNldHRpbmc+DQogICAgICA8UHJvZmlsZVNldHRpbmc+DQogICAgICAgIDxTZXR0aW5nTmFtZUluZm8+U2hhZGVyIGRpc2sgY2FjaGUgbWF4aW11bSBzaXplPC9TZXR0aW5nTmFtZUluZm8+DQogICAgICAgIDxTZXR0aW5nSUQ+MTEzMDYxMzU8L1NldHRpbmdJRD4NCiAgICAgICAgPFNldHRpbmdWYWx1ZT4xMDI0MDA8L1NldHRpbmdWYWx1ZT4NCiAgICAgICAgPFZhbHVlVHlwZT5Ed29yZDwvVmFsdWVUeXBlPg0KICAgICAgPC9Qcm9maWxlU2V0dGluZz4NCiAgICAgIDxQcm9maWxlU2V0dGluZz4NCiAgICAgICAgPFNldHRpbmdOYW1lSW5mbz5PdmVycmlkZSBETFNTRyBtdWx0aS1mcmFtZSBjb3VudDwvU2V0dGluZ05hbWVJbmZvPg0KICAgICAgICA8U2V0dGluZ0lEPjI3MzUwNzk0MzwvU2V0dGluZ0lEPg0KICAgICAgICA8U2V0dGluZ1ZhbHVlPjA8L1NldHRpbmdWYWx1ZT4NCiAgICAgICAgPFZhbHVlVHlwZT5Ed29yZDwvVmFsdWVUeXBlPg0KICAgICAgPC9Qcm9maWxlU2V0dGluZz4NCiAgICAgIDxQcm9maWxlU2V0dGluZz4NCiAgICAgICAgPFNldHRpbmdOYW1lSW5mbz5Qb3dlciBtYW5hZ2VtZW50IG1vZGU8L1NldHRpbmdOYW1lSW5mbz4NCiAgICAgICAgPFNldHRpbmdJRD4yNzQxOTczNjE8L1NldHRpbmdJRD4NCiAgICAgICAgPFNldHRpbmdWYWx1ZT4xPC9TZXR0aW5nVmFsdWU+DQogICAgICAgIDxWYWx1ZVR5cGU+RHdvcmQ8L1ZhbHVlVHlwZT4NCiAgICAgIDwvUHJvZmlsZVNldHRpbmc+DQogICAgICA8UHJvZmlsZVNldHRpbmc+DQogICAgICAgIDxTZXR0aW5nTmFtZUluZm8+RW5hYmxlIEFuc2VsPC9TZXR0aW5nTmFtZUluZm8+DQogICAgICAgIDxTZXR0aW5nSUQ+Mjc2MTU4ODM0PC9TZXR0aW5nSUQ+DQogICAgICAgIDxTZXR0aW5nVmFsdWU+MDwvU2V0dGluZ1ZhbHVlPg0KICAgICAgICA8VmFsdWVUeXBlPkR3b3JkPC9WYWx1ZVR5cGU+DQogICAgICA8L1Byb2ZpbGVTZXR0aW5nPg0KICAgICAgPFByb2ZpbGVTZXR0aW5nPg0KICAgICAgICA8U2V0dGluZ05hbWVJbmZvPkFudGlhbGlhc2luZyAtIEdhbW1hIGNvcnJlY3Rpb248L1NldHRpbmdOYW1lSW5mbz4NCiAgICAgICAgPFNldHRpbmdJRD4yNzY2NTI5NTc8L1NldHRpbmdJRD4NCiAgICAgICAgPFNldHRpbmdWYWx1ZT4yPC9TZXR0aW5nVmFsdWU+DQogICAgICAgIDxWYWx1ZVR5cGU+RHdvcmQ8L1ZhbHVlVHlwZT4NCiAgICAgIDwvUHJvZmlsZVNldHRpbmc+DQogICAgICA8UHJvZmlsZVNldHRpbmc+DQogICAgICAgIDxTZXR0aW5nTmFtZUluZm8+QW50aWFsaWFzaW5nIC0gTW9kZTwvU2V0dGluZ05hbWVJbmZvPg0KICAgICAgICA8U2V0dGluZ0lEPjI3Njc1NzU5NTwvU2V0dGluZ0lEPg0KICAgICAgICA8U2V0dGluZ1ZhbHVlPjA8L1NldHRpbmdWYWx1ZT4NCiAgICAgICAgPFZhbHVlVHlwZT5Ed29yZDwvVmFsdWVUeXBlPg0KICAgICAgPC9Qcm9maWxlU2V0dGluZz4NCiAgICAgIDxQcm9maWxlU2V0dGluZz4NCiAgICAgICAgPFNldHRpbmdOYW1lSW5mbz5GUkwgTG93IExhdGVuY3k8L1NldHRpbmdOYW1lSW5mbz4NCiAgICAgICAgPFNldHRpbmdJRD4yNzcwNDExNTI8L1NldHRpbmdJRD4NCiAgICAgICAgPFNldHRpbmdWYWx1ZT4xPC9TZXR0aW5nVmFsdWU+DQogICAgICAgIDxWYWx1ZVR5cGU+RHdvcmQ8L1ZhbHVlVHlwZT4NCiAgICAgIDwvUHJvZmlsZVNldHRpbmc+DQogICAgICA8UHJvZmlsZVNldHRpbmc+DQogICAgICAgIDxTZXR0aW5nTmFtZUluZm8+VG9nZ2xlIHRoZSBWUlIgZ2xvYmFsIGZlYXR1cmU8L1NldHRpbmdOYW1lSW5mbz4NCiAgICAgICAgPFNldHRpbmdJRD4yNzgxOTY1Njc8L1NldHRpbmdJRD4NCiAgICAgICAgPFNldHRpbmdWYWx1ZT4wPC9TZXR0aW5nVmFsdWU+DQogICAgICAgIDxWYWx1ZVR5cGU+RHdvcmQ8L1ZhbHVlVHlwZT4NCiAgICAgIDwvUHJvZmlsZVNldHRpbmc+DQogICAgICA8UHJvZmlsZVNldHRpbmc+DQogICAgICAgIDxTZXR0aW5nTmFtZUluZm8+VlJSIHJlcXVlc3RlZCBzdGF0ZTwvU2V0dGluZ05hbWVJbmZvPg0KICAgICAgICA8U2V0dGluZ0lEPjI3ODE5NjcyNzwvU2V0dGluZ0lEPg0KICAgICAgICA8U2V0dGluZ1ZhbHVlPjA8L1NldHRpbmdWYWx1ZT4NCiAgICAgICAgPFZhbHVlVHlwZT5Ed29yZDwvVmFsdWVUeXBlPg0KICAgICAgPC9Qcm9maWxlU2V0dGluZz4NCiAgICAgIDxQcm9maWxlU2V0dGluZz4NCiAgICAgICAgPFNldHRpbmdOYW1lSW5mbz5Bbmlzb3Ryb3BpYyBmaWx0ZXJpbmcgbW9kZTwvU2V0dGluZ05hbWVJbmZvPg0KICAgICAgICA8U2V0dGluZ0lEPjI4MjI0NTkxMDwvU2V0dGluZ0lEPg0KICAgICAgICA8U2V0dGluZ1ZhbHVlPjE8L1NldHRpbmdWYWx1ZT4NCiAgICAgICAgPFZhbHVlVHlwZT5Ed29yZDwvVmFsdWVUeXBlPg0KICAgICAgPC9Qcm9maWxlU2V0dGluZz4NCiAgICAgIDxQcm9maWxlU2V0dGluZz4NCiAgICAgICAgPFNldHRpbmdOYW1lSW5mbz5PdmVycmlkZSBETFNTLUZHIHByZXNldDwvU2V0dGluZ05hbWVJbmZvPg0KICAgICAgICA8U2V0dGluZ0lEPjI4MzM4NTMyOTwvU2V0dGluZ0lEPg0KICAgICAgICA8U2V0dGluZ1ZhbHVlPjA8L1NldHRpbmdWYWx1ZT4NCiAgICAgICAgPFZhbHVlVHlwZT5Ed29yZDwvVmFsdWVUeXBlPg0KICAgICAgPC9Qcm9maWxlU2V0dGluZz4NCiAgICAgIDxQcm9maWxlU2V0dGluZz4NCiAgICAgICAgPFNldHRpbmdOYW1lSW5mbz5FbmFibGUgRExTUy1GRyBvdmVycmlkZTwvU2V0dGluZ05hbWVJbmZvPg0KICAgICAgICA8U2V0dGluZ0lEPjI4MzM4NTM0NzwvU2V0dGluZ0lEPg0KICAgICAgICA8U2V0dGluZ1ZhbHVlPjA8L1NldHRpbmdWYWx1ZT4NCiAgICAgICAgPFZhbHVlVHlwZT5Ed29yZDwvVmFsdWVUeXBlPg0KICAgICAgPC9Qcm9maWxlU2V0dGluZz4NCiAgICAgIDxQcm9maWxlU2V0dGluZz4NCiAgICAgICAgPFNldHRpbmdOYW1lSW5mbz5FbmFibGUgRy1TWU5DIGdsb2JhbGx5PC9TZXR0aW5nTmFtZUluZm8+DQogICAgICAgIDxTZXR0aW5nSUQ+Mjk0OTczNzg0PC9TZXR0aW5nSUQ+DQogICAgICAgIDxTZXR0aW5nVmFsdWU+MDwvU2V0dGluZ1ZhbHVlPg0KICAgICAgICA8VmFsdWVUeXBlPkR3b3JkPC9WYWx1ZVR5cGU+DQogICAgICA8L1Byb2ZpbGVTZXR0aW5nPg0KICAgIDwvU2V0dGluZ3M+DQogICAgPEV4ZWN1dGFibGVGaW5kRmlsZXMgLz4NCiAgPC9Qcm9maWxlPg0KPC9BcnJheU9mUHJvZmlsZT4='

function Find-FortniteExe([switch]$Quiet) {
    foreach ($f in (Get-ChildItem "$env:ProgramData\Epic\EpicGamesLauncher\Data\Manifests\*.item" -ErrorAction SilentlyContinue)) {
        try {
            $j = Get-Content $f.FullName -Raw | ConvertFrom-Json
            if ($j.AppName -eq 'Fortnite' -or $j.DisplayName -eq 'Fortnite') {
                $e = Join-Path $j.InstallLocation 'FortniteGame\Binaries\Win64\FortniteClient-Win64-Shipping.exe'
                if (Test-Path $e) { return $e }
            }
        } catch {}
    }
    foreach ($d in 'C', 'D', 'E', 'F', 'G') {
        $e = "${d}:\Program Files\Epic Games\Fortnite\FortniteGame\Binaries\Win64\FortniteClient-Win64-Shipping.exe"
        if (Test-Path $e) { return $e }
    }
    if ($Quiet) { return $null }
    $dlg = New-Object Windows.Forms.OpenFileDialog
    $dlg.Title = 'Locate FortniteClient-Win64-Shipping.exe'; $dlg.Filter = 'FortniteClient-Win64-Shipping.exe|FortniteClient-Win64-Shipping.exe'
    if ($dlg.ShowDialog() -eq 'OK') { return $dlg.FileName }
    return $null
}

function Find-Nip {
    foreach ($p in (Join-Path $script:Root 'Comp_Fortnite_Profile.nip'), (Join-Path $script:Dir 'Comp_Fortnite_Profile.nip')) { if (Test-Path $p) { return $p } }
    $out = Join-Path $script:Dir 'Comp_Fortnite_Profile.nip'
    [IO.File]::WriteAllBytes($out, [Convert]::FromBase64String($script:NipB64))
    Log "Extracted built-in Fortnite profile to $out"
    return $out
}

function Find-NPI {
    $cands = @(
        (Join-Path $script:Root 'nvidiaProfileInspector.exe'),
        (Join-Path $script:Root 'nvidiaProfileInspector\nvidiaProfileInspector.exe'),
        (Join-Path $script:Dir 'npi\nvidiaProfileInspector.exe'))
    foreach ($c in $cands) { if (Test-Path $c) { return $c } }
    $r = [Fz.Msg]::Show("NVIDIA Profile Inspector was not found.`n`nYES = download it now from the official GitHub releases (Orbmu2k/nvidiaProfileInspector)`nNO = browse for nvidiaProfileInspector.exe yourself`nCANCEL = skip", 'NVIDIA Profile Inspector', 'YesNoCancel', 'Question')
    if ($r -eq 'Yes') {
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $rel = Invoke-RestMethod 'https://api.github.com/repos/Orbmu2k/nvidiaProfileInspector/releases/latest' -Headers @{ 'User-Agent' = 'FortniteTweaker' }
            $asset = $rel.assets | Where-Object { $_.name -like '*.zip' } | Select-Object -First 1
            if (-not $asset) { throw 'No zip asset found in latest release' }
            $dir = Join-Path $script:Dir 'npi'; New-Item -ItemType Directory -Path $dir -Force | Out-Null
            $zip = Join-Path $script:Dir 'npi.zip'
            Log "Downloading $($asset.name) ..."
            Invoke-WebRequest $asset.browser_download_url -OutFile $zip -UseBasicParsing
            Expand-Archive -Path $zip -DestinationPath $dir -Force
            $exe = Get-ChildItem $dir -Recurse -Filter 'nvidiaProfileInspector.exe' | Select-Object -First 1
            if ($exe) { return $exe.FullName }
            throw 'nvidiaProfileInspector.exe not found in download'
        } catch { Log "Download failed: $($_.Exception.Message)" 'ERROR'; return $null }
    }
    if ($r -eq 'No') {
        $dlg = New-Object Windows.Forms.OpenFileDialog; $dlg.Filter = 'nvidiaProfileInspector.exe|nvidiaProfileInspector.exe'
        if ($dlg.ShowDialog() -eq 'OK') { return $dlg.FileName }
    }
    return $null
}

# ---------- GameUserSettings.ini editing ----------
function Get-IniSection($lines, [string]$section) {
    $keys = New-Object System.Collections.ArrayList; $sec = -1; $in = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $l = $lines[$i].Trim()
        if ($l -match '^\[(.+)\]$') { $in = ($Matches[1] -eq $section); if ($in -and $sec -lt 0) { $sec = $i }; continue }
        if ($in -and $l -match '^([^=;#]+)=(.*)$') { [void]$keys.Add([pscustomobject]@{ Line = $i; Key = $Matches[1].Trim(); Val = $Matches[2] }) }
    }
    return [pscustomobject]@{ Sec = $sec; Keys = @($keys) }
}
function Set-IniRule($lines, [string]$section, $r) {
    $s = Get-IniSection $lines $section
    $targets = @($s.Keys | Where-Object { if ($r.Mode -eq 'Match') { $_.Key -match $r.K } else { $_.Key -ieq $r.K } })
    if ($targets.Count -eq 0) {
        if ($r.Mode -eq 'Set') {
            if ($s.Sec -lt 0) { $lines.Add(''); $lines.Add("[$section]"); $lines.Add("$($r.K)=$($r.V)") } else { $lines.Insert($s.Sec + 1, "$($r.K)=$($r.V)") }
            if (-not $script:State.ContainsKey("ini|$($r.K)")) { $script:State["ini|$($r.K)"] = '<absent>' }
            Log "  + $($r.K)=$($r.V) (added)"
        } else { Log "  key matching '$($r.K)' not present in config - skipped" 'WARN' }
        return
    }
    foreach ($t in $targets) {
        $val = $r.V
        if ($r.V -eq '<off>') { $val = if ($t.Val.Trim() -match '^(?i)(true|false)$') { 'False' } else { '0' } }
        if (-not $script:State.ContainsKey("ini|$($t.Key)")) { $script:State["ini|$($t.Key)"] = $t.Val }
        $lines[$t.Line] = "$($t.Key)=$val"
        Log "  ~ $($t.Key): $($t.Val) -> $val"
    }
}
function Undo-IniRule($lines, [string]$section, $r) {
    $keys = @($script:State.Keys | Where-Object { $_ -like 'ini|*' } | ForEach-Object { $_.Substring(4) } | Where-Object { if ($r.Mode -eq 'Match') { $_ -match $r.K } else { $_ -ieq $r.K } })
    foreach ($k in $keys) {
        $orig = $script:State["ini|$k"]
        $s = Get-IniSection $lines $section
        $t = $s.Keys | Where-Object { $_.Key -ieq $k } | Select-Object -First 1
        if ($orig -eq '<absent>') { if ($t) { $lines.RemoveAt($t.Line) } }
        elseif ($t) { $lines[$t.Line] = "$k=$orig" }
        elseif ($s.Sec -ge 0) { $lines.Insert($s.Sec + 1, "$k=$orig") }
        $script:State.Remove("ini|$k"); Log "  restored $k"
    }
    Save-State
}
function Read-FnIni {
    if (-not (Test-Path $script:FnCfg)) { throw "GameUserSettings.ini not found at $script:FnCfg - launch Fortnite once first." }
    if (Get-Process -Name 'FortniteClient-Win64-Shipping' -ErrorAction SilentlyContinue) { throw 'Close Fortnite first - it overwrites its config on exit.' }
    $fi = Get-Item $script:FnCfg; if ($fi.IsReadOnly) { $fi.IsReadOnly = $false; Log 'Cleared read-only flag on config' }
    $l = New-Object 'System.Collections.Generic.List[string]'
    $l.AddRange([string[]][IO.File]::ReadAllLines($script:FnCfg))
    return , $l
}
function Write-FnIni($lines) { [IO.File]::WriteAllLines($script:FnCfg, $lines, (New-Object Text.UTF8Encoding($false))); Save-State }

# ---------- Tweak registry ----------
function Add-Tweak {
    param($Cat, $Name, $Desc, $Risk = 'Safe', [bool]$Default = $false, [bool]$Reversible = $true, $Apply, $Undo = $null, $Arg = $null)
    [void]$script:Tweaks.Add([pscustomobject]@{
        Cat = $Cat; Name = $Name; Desc = $Desc; Risk = $Risk; Default = $Default
        Reversible = ($Reversible -and ($null -ne $Undo)); Apply = $Apply; Undo = $Undo; Arg = $Arg
        Kind = $(if ("$Apply" -eq "$($script:RegApply)") { 'Reg' } elseif ("$Apply" -eq "$($script:SvcApply)") { 'Svc' } elseif ("$Apply" -eq "$($script:TaskApply)") { 'Task' } else { 'Other' })
    })
}

$script:RegApply = { param($a) foreach ($i in $a) { $t = if ($i.T) { $i.T } else { 'DWord' }; Set-Reg $i.P $i.N $i.V $t } }
$script:RegUndo  = { param($a) foreach ($i in $a) { $t = if ($i.T) { $i.T } else { 'DWord' }; Restore-Reg $i.P $i.N $i.O $t } }
$script:SvcApply = { param($a) foreach ($s in $a) { Disable-Svc $s } }
$script:SvcUndo  = { param($a) foreach ($s in $a) { Enable-Svc $s } }
$script:TaskApply = { param($a) foreach ($t in $a) { Set-Task $t $false } }
$script:TaskUndo  = { param($a) foreach ($t in $a) { Set-Task $t $true } }

function Add-RegTweak {
    param($Cat, $Name, $Desc, $Risk = 'Safe', [bool]$Default = $false, [hashtable[]]$Items)
    Add-Tweak -Cat $Cat -Name $Name -Desc $Desc -Risk $Risk -Default $Default -Apply $script:RegApply -Undo $script:RegUndo -Arg $Items
}
function Add-SvcTweak {
    param($Cat, $Name, $Desc, $Risk = 'Moderate', [bool]$Default = $false, [string[]]$Svcs)
    Add-Tweak -Cat $Cat -Name $Name -Desc $Desc -Risk $Risk -Default $Default -Apply $script:SvcApply -Undo $script:SvcUndo -Arg $Svcs
}
function Add-TaskTweak {
    param($Cat, $Name, $Desc, $Risk = 'Safe', [bool]$Default = $false, [string[]]$Tasks)
    Add-Tweak -Cat $Cat -Name $Name -Desc $Desc -Risk $Risk -Default $Default -Apply $script:TaskApply -Undo $script:TaskUndo -Arg $Tasks
}

$HKLMP = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows'
$MMCSS = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
$ADV   = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
$EDGE  = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'

# ===== CLEANUP & SHELL =====
$c = '1. Cleanup & Shell'
Add-Tweak $c 'Clear Update Cache' 'Deletes downloaded Windows Update files to free disk space.' 'Safe' $true $false -Apply {
    Stop-Service wuauserv, bits -Force -ErrorAction SilentlyContinue
    Clear-Folder "$env:WINDIR\SoftwareDistribution\Download"
    Start-Service bits, wuauserv -ErrorAction SilentlyContinue
}
Add-Tweak $c 'Pause Windows Updates (365 days)' 'Pauses update delivery for a year. Security patches will NOT install while paused - undo regularly.' 'Moderate' $false -Apply {
    $f = 'yyyy-MM-ddTHH:mm:ssZ'; $ci = [Globalization.CultureInfo]::InvariantCulture
    $s = (Get-Date).ToUniversalTime().ToString($f, $ci); $e = (Get-Date).ToUniversalTime().AddDays(365).ToString($f, $ci)
    $p = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
    foreach ($n in 'PauseUpdatesStartTime', 'PauseFeatureUpdatesStartTime', 'PauseQualityUpdatesStartTime') { Set-Reg $p $n $s 'String' }
    foreach ($n in 'PauseUpdatesExpiryTime', 'PauseFeatureUpdatesEndTime', 'PauseQualityUpdatesEndTime') { Set-Reg $p $n $e 'String' }
} -Undo {
    $p = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
    foreach ($n in 'PauseUpdatesStartTime', 'PauseFeatureUpdatesStartTime', 'PauseQualityUpdatesStartTime', 'PauseUpdatesExpiryTime', 'PauseFeatureUpdatesEndTime', 'PauseQualityUpdatesEndTime') { Restore-Reg $p $n $null 'String' }
}
Add-RegTweak $c 'Faster Menus' 'Menus open instantly (MenuShowDelay = 0).' 'Safe' $true -Items @{ P = 'HKCU:\Control Panel\Desktop'; N = 'MenuShowDelay'; V = '0'; T = 'String'; O = '400' }
Add-RegTweak $c 'Display for Performance' 'Trims window animations for speed.' 'Safe' $true -Items @(
    @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'; N = 'VisualFXSetting'; V = 2; O = 0 },
    @{ P = 'HKCU:\Control Panel\Desktop\WindowMetrics'; N = 'MinAnimate'; V = '0'; T = 'String'; O = '1' },
    @{ P = $ADV; N = 'TaskbarAnimations'; V = 0; O = 1 },
    @{ P = $ADV; N = 'ListviewAlphaSelect'; V = 0; O = 1 })

# ===== PRIVACY =====
$c = '2. Privacy'
Add-RegTweak $c 'Disable Activity History' 'Stops activity tracking/upload.' 'Safe' $true -Items @(
    @{ P = "$HKLMP\System"; N = 'EnableActivityFeed'; V = 0 }, @{ P = "$HKLMP\System"; N = 'PublishUserActivities'; V = 0 }, @{ P = "$HKLMP\System"; N = 'UploadUserActivities'; V = 0 })
Add-RegTweak $c 'Disable Consumer Features' 'Kills Windows promos and silent app installs.' 'Safe' $true -Items @(
    @{ P = "$HKLMP\CloudContent"; N = 'DisableWindowsConsumerFeatures'; V = 1 },
    @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; N = 'SilentInstalledAppsEnabled'; V = 0; O = 1 },
    @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; N = 'SubscribedContent-338388Enabled'; V = 0; O = 1 },
    @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; N = 'SubscribedContent-338389Enabled'; V = 0; O = 1 })
Add-RegTweak $c 'Auto Folder Discovery Off' 'Stops Explorer re-laying out folders.' 'Safe' $true -Items @{ P = 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags\AllFolders\Shell'; N = 'FolderType'; V = 'NotSpecified'; T = 'String' }
Add-RegTweak $c 'Disable Location Tracking' 'Blocks location access.' 'Safe' $true -Items @(
    @{ P = "$HKLMP\LocationAndSensors"; N = 'DisableLocation'; V = 1 },
    @{ P = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location'; N = 'Value'; V = 'Deny'; T = 'String'; O = 'Allow' })
Add-RegTweak $c 'Disable Background Apps' 'Stops UWP apps running in the background.' 'Safe' $true -Items @(
    @{ P = "$HKLMP\AppPrivacy"; N = 'LetAppsRunInBackground'; V = 2 },
    @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications'; N = 'GlobalUserDisabled'; V = 1; O = 0 })
Add-RegTweak $c 'Disable Advertising ID' 'Turns off ad tracking.' 'Safe' $true -Items @(
    @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo'; N = 'Enabled'; V = 0; O = 1 }, @{ P = "$HKLMP\AdvertisingInfo"; N = 'DisabledByGroupPolicy'; V = 1 })
Add-RegTweak $c 'Disable Tailored Experiences' 'Turns off personalized tips, ads and suggestions.' 'Safe' $true -Items @(
    @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy'; N = 'TailoredExperiencesWithDiagnosticDataEnabled'; V = 0; O = 1 },
    @{ P = 'HKCU:\Software\Policies\Microsoft\Windows\CloudContent'; N = 'DisableTailoredExperiencesWithDiagnosticData'; V = 1 })
Add-RegTweak $c 'Disable CEIP and Insights' 'Turns off feedback, typing and inking insights.' 'Safe' $true -Items @(
    @{ P = 'HKLM:\SOFTWARE\Policies\Microsoft\SQMClient\Windows'; N = 'CEIPEnable'; V = 0 },
    @{ P = "$HKLMP\AppCompat"; N = 'AITEnable'; V = 0 }, @{ P = "$HKLMP\AppCompat"; N = 'DisableInventory'; V = 1 },
    @{ P = 'HKCU:\Software\Microsoft\Input\TIPC'; N = 'Enabled'; V = 0; O = 1 })
Add-RegTweak $c 'Disable Cross-Device Clipboard' 'Stops clipboard syncing across devices.' 'Safe' $true -Items @{ P = "$HKLMP\System"; N = 'AllowCrossDeviceClipboard'; V = 0 }
Add-RegTweak $c 'Reduce Telemetry Policy' 'Reduces diagnostic and policy telemetry.' 'Safe' $true -Items @(
    @{ P = "$HKLMP\DataCollection"; N = 'AllowTelemetry'; V = 0 }, @{ P = "$HKLMP\DataCollection"; N = 'DoNotShowFeedbackNotifications'; V = 1 })

# ===== NOTIFICATIONS & SURFACES =====
$c = '3. Notifications & Surfaces'
Add-RegTweak $c 'Turn Off Widgets' 'Removes the Widgets taskbar button.' 'Safe' $true -Items @(
    @{ P = $ADV; N = 'TaskbarDa'; V = 0; O = 1 }, @{ P = 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh'; N = 'AllowNewsAndInterests'; V = 0 })
Add-RegTweak $c 'Disable Notification Tray/Calendar' 'Cuts tray popups and toast notifications.' 'Moderate' $true -Items @(
    @{ P = 'HKCU:\Software\Policies\Microsoft\Windows\Explorer'; N = 'DisableNotificationCenter'; V = 1 },
    @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications'; N = 'ToastEnabled'; V = 0; O = 1 })
Add-RegTweak $c 'Keep Windows Search Local' 'Removes web and Store suggestions from Search.' 'Safe' $true -Items @(
    @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'; N = 'BingSearchEnabled'; V = 0; O = 1 },
    @{ P = 'HKCU:\Software\Policies\Microsoft\Windows\Explorer'; N = 'DisableSearchBoxSuggestions'; V = 1 })
Add-RegTweak $c 'Recommendations in Start Menu Off' 'Hides recommended content in Start.' 'Safe' $true -Items @(
    @{ P = $ADV; N = 'Start_IrisRecommendations'; V = 0; O = 1 }, @{ P = $ADV; N = 'Start_TrackDocs'; V = 0; O = 1 },
    @{ P = "$HKLMP\Explorer"; N = 'HideRecommendedSection'; V = 1 })
Add-RegTweak $c 'Microsoft Edge Optimization' 'Less Edge background activity and startup behavior.' 'Safe' $true -Items @(
    @{ P = $EDGE; N = 'StartupBoostEnabled'; V = 0 }, @{ P = $EDGE; N = 'BackgroundModeEnabled'; V = 0 })
Add-RegTweak $c 'Edge Debloat' 'Removes extra Edge features and helpers.' 'Safe' $true -Items @(
    @{ P = $EDGE; N = 'HubsSidebarEnabled'; V = 0 }, @{ P = $EDGE; N = 'EdgeShoppingAssistantEnabled'; V = 0 },
    @{ P = $EDGE; N = 'ShowMicrosoftRewards'; V = 0 }, @{ P = $EDGE; N = 'EdgeCollectionsEnabled'; V = 0 },
    @{ P = $EDGE; N = 'PersonalizationReportingEnabled'; V = 0 }, @{ P = $EDGE; N = 'DiagnosticData'; V = 0 })
Add-Tweak $c 'Disable Microsoft Copilot' 'Turns off Copilot policy and removes the Copilot app.' 'Safe' $true $false -Apply {
    Set-Reg "$HKLMP\WindowsCopilot" 'TurnOffWindowsCopilot' 1
    Set-Reg 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
    if (Confirm-Action 'Remove Copilot app?' 'The Copilot policy was set. Also uninstall the Copilot app packages?') {
        foreach ($n in 'Microsoft.Copilot', 'Microsoft.Windows.Ai.Copilot.Provider') { Get-AppxPackage -AllUsers -Name $n -ErrorAction SilentlyContinue | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue }
    } else { Log 'Copilot app removal skipped by user' }
}
Add-Tweak $c 'Remove OneDrive' 'Uninstalls OneDrive. CHECK WHERE YOUR DOCUMENTS/DESKTOP LIVE FIRST.' 'Expert' $false $false -Apply {
    $redir = @('MyDocuments', 'Desktop', 'MyPictures') | Where-Object { [Environment]::GetFolderPath($_) -like '*OneDrive*' }
    $warn = "This will UNINSTALL OneDrive.`n`n"
    if ($redir) { $warn += "WARNING: these folders are currently stored in OneDrive: $($redir -join ', ').`nCopy your files out of OneDrive first or they may become unreachable locally.`n`n" }
    $warn += 'Continue?'
    if (-not (Confirm-Action 'Remove OneDrive?' $warn)) { Log 'OneDrive removal skipped by user'; return }
    Stop-Process -Name OneDrive -Force -ErrorAction SilentlyContinue
    $x = "$env:SystemRoot\SysWOW64\OneDriveSetup.exe"; if (-not (Test-Path $x)) { $x = "$env:SystemRoot\System32\OneDriveSetup.exe" }
    if (Test-Path $x) { Start-Process $x '/uninstall' -Wait } else { Log 'OneDriveSetup.exe not found' 'WARN' }
}

# ===== DIAGNOSTICS & BACKGROUND =====
$c = '4. Diagnostics & Background'
Add-Tweak $c 'Disable Startup Apps' 'Removes Run-key startup entries (backed up). Keeps vendor/audio/NVIDIA/security entries.' 'Moderate' $true -Apply {
    $keep = 'SecurityHealth|Defender|Realtek|Rtk|Audio|NVIDIA|NvBackend|NvContainer|NvTray|Touchpad|Synaptics|ELAN|Bluetooth|Intel|Armoury|ASUS|Lenovo|Legion|Vantage|HP|Omen|Dell|Alienware|MSI|Acer|Nitro|Predator|Gigabyte|Aorus|Razer|Fan|Thermal'
    foreach ($hive in 'HKCU', 'HKLM') {
        $p = "${hive}:\Software\Microsoft\Windows\CurrentVersion\Run"
        if (-not (Test-Path $p)) { continue }
        $props = Get-ItemProperty $p
        foreach ($n in ($props.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' }).Name) {
            if ($n -match $keep) { Log "Kept startup entry: $n"; continue }
            $script:State["run|$hive|$n"] = [string]$props.$n; Save-State
            Remove-ItemProperty -Path $p -Name $n -ErrorAction SilentlyContinue
            Log "Removed startup entry: $n"
        }
    }
} -Undo {
    foreach ($k in @($script:State.Keys | Where-Object { $_ -like 'run|*' })) {
        $s = $k.Split('|'); Set-Reg "$($s[1]):\Software\Microsoft\Windows\CurrentVersion\Run" $s[2] $script:State[$k] 'String' -NoBackup
        $script:State.Remove($k); Log "Restored startup entry $($s[2])"
    }
    Save-State
}
Add-Tweak $c 'Disable Diagnostics and Maintenance' 'Disables DiagTrack / dmwappushservice and scheduled auto-maintenance.' 'Moderate' $true -Apply {
    Disable-Svc 'DiagTrack'; Disable-Svc 'dmwappushservice'
    Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\Maintenance' 'MaintenanceDisabled' 1
} -Undo {
    Enable-Svc 'DiagTrack'; Enable-Svc 'dmwappushservice'
    Restore-Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\Maintenance' 'MaintenanceDisabled' $null
}
Add-RegTweak $c 'Disable DiagTrack AutoLogger' 'Stops diagnostic tracing at boot.' 'Safe' $true -Items @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\AutoLogger-Diagtrack-Listener'; N = 'Start'; V = 0; O = 1 }
Add-Tweak $c 'Disable Windows Error Reporting' 'Turns off WER and its service.' 'Moderate' $false -Apply {
    Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting' 'Disabled' 1
    Set-Reg "$HKLMP\Windows Error Reporting" 'Disabled' 1
    Disable-Svc 'WerSvc'
} -Undo {
    Restore-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting' 'Disabled' $null
    Restore-Reg "$HKLMP\Windows Error Reporting" 'Disabled' $null
    Enable-Svc 'WerSvc'
}
Add-RegTweak $c 'Disable WPBT' 'Turns off Windows Platform Binary Table execution (OEM firmware-injected binaries).' 'Expert' $false -Items @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'; N = 'DisableWpbtExecution'; V = 1 }
Add-SvcTweak $c 'Disable Scanner and Maps' 'Disables image acquisition (stisvc) and offline maps (MapsBroker).' 'Safe' $false -Svcs @('stisvc', 'MapsBroker')

# ===== OPTIONAL WINDOWS FEATURES =====
$c = '5. Optional Windows Features'
Add-Tweak $c 'Disable Work Folders' 'Turns off the Work Folders client and service.' 'Safe' $true -Apply {
    Disable-Feat @('WorkFolders-Client'); Disable-Svc 'workfolderssvc'
} -Undo { Enable-Feat @('WorkFolders-Client'); Enable-Svc 'workfolderssvc' }
Add-Tweak $c 'Disable Printing' 'Disables Print Spooler, Print to PDF and XPS. You will NOT be able to print.' 'Moderate' $false -Apply {
    Disable-Svc 'Spooler'; Disable-Svc 'PrintNotify'
    Disable-Feat @('Printing-PrintToPDFServices-Features', 'Printing-XPSServices-Features')
} -Undo {
    Enable-Svc 'Spooler'; Enable-Svc 'PrintNotify'
    Enable-Feat @('Printing-PrintToPDFServices-Features', 'Printing-XPSServices-Features')
}
Add-Tweak $c 'Disable Hyper-V Features' 'Disables Hyper-V / VM Platform. Breaks WSL2, Sandbox, Memory Integrity.' 'Expert' $false -Apply {
    Disable-Feat @('Microsoft-Hyper-V-All', 'VirtualMachinePlatform', 'HypervisorPlatform', 'Containers-DisposableClientVM')
} -Undo { Enable-Feat @('Microsoft-Hyper-V-All', 'VirtualMachinePlatform', 'HypervisorPlatform', 'Containers-DisposableClientVM') }

# ===== INPUT DELAY =====
$c = '10. Input Delay'
Add-RegTweak $c 'Foreground Priority Boost' 'Win32PrioritySeparation = 0x26 (favor foreground app).' 'Safe' $true -Items @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl'; N = 'Win32PrioritySeparation'; V = 38; O = 2 }
Add-RegTweak $c 'Minimum System Service Priority' 'SystemResponsiveness = 0 and Games task priority = High.' 'Safe' $true -Items @(
    @{ P = $MMCSS; N = 'SystemResponsiveness'; V = 0; O = 20 },
    @{ P = "$MMCSS\Tasks\Games"; N = 'GPU Priority'; V = 8; O = 8 }, @{ P = "$MMCSS\Tasks\Games"; N = 'Priority'; V = 6; O = 2 },
    @{ P = "$MMCSS\Tasks\Games"; N = 'Scheduling Category'; V = 'High'; T = 'String'; O = 'Medium' }, @{ P = "$MMCSS\Tasks\Games"; N = 'SFIO Priority'; V = 'High'; T = 'String'; O = 'Normal' })
Add-RegTweak $c 'Disable Mouse Acceleration' 'Enhance pointer precision off.' 'Safe' $true -Items @(
    @{ P = 'HKCU:\Control Panel\Mouse'; N = 'MouseSpeed'; V = '0'; T = 'String'; O = '1' },
    @{ P = 'HKCU:\Control Panel\Mouse'; N = 'MouseThreshold1'; V = '0'; T = 'String'; O = '6' },
    @{ P = 'HKCU:\Control Panel\Mouse'; N = 'MouseThreshold2'; V = '0'; T = 'String'; O = '10' })
Add-RegTweak $c 'Block Accessibility Shortcut Popups' 'Stops Sticky/Filter/Toggle Keys prompts in games.' 'Safe' $true -Items @(
    @{ P = 'HKCU:\Control Panel\Accessibility\StickyKeys'; N = 'Flags'; V = '506'; T = 'String'; O = '510' },
    @{ P = 'HKCU:\Control Panel\Accessibility\Keyboard Response'; N = 'Flags'; V = '122'; T = 'String'; O = '126' },
    @{ P = 'HKCU:\Control Panel\Accessibility\ToggleKeys'; N = 'Flags'; V = '58'; T = 'String'; O = '62' })
Add-Tweak $c 'Disable NTFS Last Access Update' 'Fewer disk writes on file open.' 'Safe' $true -Apply { & fsutil.exe behavior set disablelastaccess 1 | Out-Null } -Undo { & fsutil.exe behavior set disablelastaccess 2 | Out-Null }
Add-SvcTweak $c 'Disable Windows Search (WSearch)' 'Turns off indexing. Start search may stop finding files.' 'Moderate' $false -Svcs @('WSearch')
Add-SvcTweak $c 'Disable SuperFetch (SysMain)' 'Fine on SSD; can slow loads on HDD.' 'Moderate' $false -Svcs @('SysMain')
Add-RegTweak $c 'Disable Game Bar and DVR' 'Turns off Game Bar and background recording.' 'Safe' $true -Items @(
    @{ P = 'HKCU:\System\GameConfigStore'; N = 'GameDVR_Enabled'; V = 0; O = 1 },
    @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR'; N = 'AppCaptureEnabled'; V = 0; O = 1 },
    @{ P = 'HKCU:\Software\Microsoft\GameBar'; N = 'UseNexusForGameBarEnabled'; V = 0; O = 1 },
    @{ P = 'HKCU:\Software\Microsoft\GameBar'; N = 'ShowStartupPanel'; V = 0; O = 1 },
    @{ P = "$HKLMP\GameDVR"; N = 'AllowGameDVR'; V = 0 })
Add-SvcTweak $c 'Disable Xbox Services and Components' 'XblAuthManager, XblGameSave, XboxGipSvc, XboxNetApiSvc. Can break Xbox-linked logins/party features.' 'Expert' $false -Svcs @('XblAuthManager', 'XblGameSave', 'XboxGipSvc', 'XboxNetApiSvc')
Add-Tweak $c 'Discord Optimization' 'Stops Discord launching at sign-in and disables hardware acceleration (close Discord first).' 'Safe' $true -Apply {
    $rp = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    $v = (Get-ItemProperty $rp -ErrorAction SilentlyContinue).Discord
    if ($v) { $script:State['discordRun'] = [string]$v; Save-State; Remove-Reg $rp 'Discord' }
    $f = "$env:APPDATA\discord\settings.json"
    if (Get-Process -Name Discord -ErrorAction SilentlyContinue) { Log 'Discord is running - it may overwrite these settings on exit. Close it and re-apply.' 'WARN' }
    if (Test-Path $f) {
        Copy-Item $f "$f.fnbak" -Force
        $j = Get-Content $f -Raw | ConvertFrom-Json
        $j | Add-Member -NotePropertyName 'enableHardwareAcceleration' -NotePropertyValue $false -Force
        $j | Add-Member -NotePropertyName 'OPEN_ON_STARTUP' -NotePropertyValue $false -Force
        [IO.File]::WriteAllText($f, ($j | ConvertTo-Json -Depth 10), (New-Object Text.UTF8Encoding($false)))
        Log 'Discord settings updated'
    } else { Log 'Discord settings.json not found' 'WARN' }
} -Undo {
    if ($script:State.ContainsKey('discordRun')) { Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' 'Discord' $script:State['discordRun'] 'String' -NoBackup; $script:State.Remove('discordRun'); Save-State }
    $f = "$env:APPDATA\discord\settings.json"; if (Test-Path "$f.fnbak") { Copy-Item "$f.fnbak" $f -Force }
}

# ===== POWER & GPU =====
$c = '11. Power & GPU'
Add-Tweak $c 'Disable PCIe Link Power Saving (plugged in)' 'Link State Power Management off on AC only. Slightly more heat.' 'Moderate' $true -Apply {
    & powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PCIEXPRESS ASPM 0 | Out-Null; & powercfg.exe /setactive SCHEME_CURRENT | Out-Null
} -Undo {
    & powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PCIEXPRESS ASPM 2 | Out-Null; & powercfg.exe /setactive SCHEME_CURRENT | Out-Null
}
Add-RegTweak $c 'Enable Hardware GPU Scheduling' 'HAGS on (RTX 40 series). Test it - helps some games, hurts others. Reboot required.' 'Moderate' $false -Items @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'; N = 'HwSchMode'; V = 2; O = 1 }
Add-Tweak $c 'Process Count Reduction' 'Groups services into fewer svchost processes (SvcHostSplitThresholdInKB = RAM). Low gain.' 'Expert' $false -Apply {
    $kb = [uint32]((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1KB)
    Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control' 'SvcHostSplitThresholdInKB' ([int]$kb); $script:RebootNeeded = $true
} -Undo { Restore-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control' 'SvcHostSplitThresholdInKB' 3670016; $script:RebootNeeded = $true }
Add-Tweak $c 'Disable PowerShell 7 Telemetry' 'Sets POWERSHELL_TELEMETRY_OPTOUT machine-wide.' 'Safe' $true -Apply {
    [Environment]::SetEnvironmentVariable('POWERSHELL_TELEMETRY_OPTOUT', '1', 'Machine')
} -Undo { [Environment]::SetEnvironmentVariable('POWERSHELL_TELEMETRY_OPTOUT', $null, 'Machine') }

$c = '11. Power & GPU'
Add-RegTweak $c 'Windows Game Mode ON' 'Lets Windows prioritise the game and hold back background maintenance/driver installs while it runs.' 'Safe' $true -Items @(
    @{ P = 'HKCU:\Software\Microsoft\GameBar'; N = 'AutoGameModeEnabled'; V = 1 }, @{ P = 'HKCU:\Software\Microsoft\GameBar'; N = 'AllowAutoGameMode'; V = 1 })
Add-RegTweak $c 'Disable Multiplane Overlay (MPO)' 'Fixes stutter, flicker or black screens on some GPU/driver combos. Leave off unless you have those symptoms. Reboot recommended.' 'Moderate' $false -Items @{ P = 'HKLM:\SOFTWARE\Microsoft\Windows\Dwm'; N = 'OverlayTestMode'; V = 5 }
Add-RegTweak $c 'Disable Memory Integrity (HVCI / VBS)' 'Can give a few % FPS on some systems. Lowers kernel security protection. Reboot required. (Do NOT disable Secure Boot/TPM - Fortnite may require them.)' 'Expert' $false -Items @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity'; N = 'Enabled'; V = 0 }

# ===== NETWORK =====
$c = '12. Network'
Add-Tweak $c 'Flush DNS' 'Clears the DNS cache now.' 'Safe' $true $false -Apply { & ipconfig.exe /flushdns | Out-Null }
Add-RegTweak $c 'DNS Priority Tune' 'Raises DNS lookup priority in the resolver.' 'Safe' $true -Items @(
    @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\ServiceProvider'; N = 'LocalPriority'; V = 4 },
    @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\ServiceProvider'; N = 'HostsPriority'; V = 5 },
    @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\ServiceProvider'; N = 'DnsPriority'; V = 6 },
    @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\ServiceProvider'; N = 'NetbtPriority'; V = 7 })
Add-Tweak $c 'Disable Energy Efficient Ethernet' 'Turns off EEE / Green Ethernet (brief connection drop).' 'Safe' $true -Apply {
    Set-NicProp @('*EEE', 'EEELinkAdvertisement', 'EnableGreenEthernet', 'GreenEthernet', 'AdvancedEEE', 'PowerSavingMode') 0
} -Undo { Restore-NicProp @('*EEE', 'EEELinkAdvertisement', 'EnableGreenEthernet', 'GreenEthernet', 'AdvancedEEE', 'PowerSavingMode') }
Add-Tweak $c 'NIC Low-Latency Profile' 'Interrupt moderation off, LSO off, RSS on. Test one at a time.' 'Moderate' $false -Apply {
    Set-NicProp @('*InterruptModeration', '*LsoV2IPv4', '*LsoV2IPv6') 0
    Set-NicProp @('*RSS') 1
} -Undo { Restore-NicProp @('*InterruptModeration', '*LsoV2IPv4', '*LsoV2IPv6', '*RSS') }
Add-Tweak $c 'Gaming QoS Priority' 'DSCP 46 QoS policy for Fortnite traffic.' 'Safe' $true -Apply {
    Remove-NetQosPolicy -Name 'FortniteTweaker' -Confirm:$false -ErrorAction SilentlyContinue
    New-NetQosPolicy -Name 'FortniteTweaker' -AppPathNameMatchCondition 'FortniteClient-Win64-Shipping.exe' -DSCPAction 46 -IPProtocolMatchCondition Both -ErrorAction Stop | Out-Null
} -Undo { Remove-NetQosPolicy -Name 'FortniteTweaker' -Confirm:$false -ErrorAction SilentlyContinue }
Add-RegTweak $c 'Disable Network Throttling' 'NetworkThrottlingIndex = off.' 'Safe' $true -Items @{ P = $MMCSS; N = 'NetworkThrottlingIndex'; V = -1; O = 10 }
Add-Tweak $c 'Disable Nagle Algorithm' 'TcpAckFrequency=1, TCPNoDelay=1 on active interfaces. Little effect for UDP games.' 'Moderate' $false -Apply {
    Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces' | ForEach-Object {
        $p = Get-ItemProperty $_.PSPath
        if ($p.DhcpIPAddress -or $p.IPAddress) { Set-Reg $_.PSPath 'TcpAckFrequency' 1; Set-Reg $_.PSPath 'TCPNoDelay' 1 }
    }
} -Undo {
    Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces' | ForEach-Object { Restore-Reg $_.PSPath 'TcpAckFrequency' $null; Restore-Reg $_.PSPath 'TCPNoDelay' $null }
}
Add-RegTweak $c 'Cap Delivery Optimization Bandwidth' 'Limits update bandwidth to 10%.' 'Safe' $true -Items @(
    @{ P = "$HKLMP\DeliveryOptimization"; N = 'DOPercentageMaxBackgroundBandwidth'; V = 10 }, @{ P = "$HKLMP\DeliveryOptimization"; N = 'DOPercentageMaxForegroundBandwidth'; V = 10 })
Add-RegTweak $c 'Disable Internet Peer Uploads' 'Delivery Optimization limited to LAN peers only.' 'Safe' $true -Items @{ P = "$HKLMP\DeliveryOptimization"; N = 'DODownloadMode'; V = 1 }
Add-SvcTweak $c 'Disable Local Discovery (EXPERT)' 'FDResPub, fdPHost, SSDPSRV, upnphost. Breaks network device discovery/UPnP.' 'Expert' $false -Svcs @('FDResPub', 'fdPHost', 'SSDPSRV', 'upnphost')
Add-Tweak $c 'Disable Remote Sharing (EXPERT)' 'Stops Server + RemoteRegistry services and blocks Remote Desktop.' 'Expert' $false -Apply {
    Disable-Svc 'LanmanServer'; Disable-Svc 'RemoteRegistry'
    Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' 'fDenyTSConnections' 1
} -Undo {
    Enable-Svc 'LanmanServer'; Enable-Svc 'RemoteRegistry'
    Restore-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' 'fDenyTSConnections' 1
}
Add-Tweak $c 'Disable LLMNR and NetBIOS Broadcasts (EXPERT)' 'Cuts local-network name broadcasts.' 'Expert' $false -Apply {
    Set-Reg "$HKLMP NT\DNSClient" 'EnableMulticast' 0
    Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces' -ErrorAction SilentlyContinue | ForEach-Object { Set-Reg $_.PSPath 'NetbiosOptions' 2 }
} -Undo {
    Restore-Reg "$HKLMP NT\DNSClient" 'EnableMulticast' $null
    Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces' -ErrorAction SilentlyContinue | ForEach-Object { Restore-Reg $_.PSPath 'NetbiosOptions' 0 }
}
Add-Tweak $c 'Disable Teredo (EXPERT)' 'Turns off Teredo tunneling. Can affect NAT type on some connections.' 'Expert' $false -Apply { & netsh.exe interface teredo set state disabled | Out-Null } -Undo { & netsh.exe interface teredo set state default | Out-Null }

# ===== FORTNITE: IN-GAME CONFIG =====
$script:IniApply = { param($a)
    $lines = Read-FnIni
    $bak = "$script:FnCfg.fnbak"; if (-not (Test-Path $bak)) { Copy-Item $script:FnCfg $bak -Force; Log "Config backup: $bak" }
    foreach ($r in $a) { Set-IniRule $lines $script:FnSection $r }
    Write-FnIni $lines
}
$script:IniUndo = { param($a)
    $lines = Read-FnIni
    foreach ($r in $a) { Undo-IniRule $lines $script:FnSection $r }
    Write-FnIni $lines
}
function Add-IniTweak {
    param($Name, $Desc, $Risk = 'Safe', [bool]$Default = $true, [hashtable[]]$Rules)
    Add-Tweak '13. Fortnite - In-Game Config (GameUserSettings.ini)' $Name $Desc $Risk $Default $true -Apply $script:IniApply -Undo $script:IniUndo -Arg $Rules
}
Add-IniTweak 'Fullscreen mode (exclusive)' 'Forces exclusive fullscreen. Leave off if Fortnite drops your monitor to 60 Hz on focus.' 'Moderate' $false @(
    @{ K = 'FullscreenMode'; V = '0'; Mode = 'Set' }, @{ K = 'LastConfirmedFullscreenMode'; V = '0'; Mode = 'Set' }, @{ K = 'PreferredFullscreenMode'; V = '0'; Mode = 'Set' })
Add-IniTweak 'Disable V-Sync' 'bUseVSync=False' 'Safe' $true @(@{ K = 'bUseVSync'; V = 'False'; Mode = 'Set' })
Add-IniTweak 'Disable motion blur' 'bMotionBlur=False' 'Safe' $true @(@{ K = 'bMotionBlur'; V = 'False'; Mode = 'Set' })
Add-IniTweak 'Show FPS' 'Built-in FPS counter on.' 'Safe' $true @(@{ K = 'bShowFPS'; V = 'True'; Mode = 'Set' })
Add-IniTweak 'Disable ray tracing' 'Turns off any ray-tracing keys present in the config (skipped if none).' 'Safe' $true @(@{ K = '(?i)ray.?trac'; V = '<off>'; Mode = 'Match' })
Add-IniTweak 'Disable energy saver' 'Turns off idle / focus-loss energy saving keys present in the config.' 'Safe' $true @(@{ K = '(?i)energy.?sav|power.?sav'; V = '<off>'; Mode = 'Match' })
Add-IniTweak 'Disable mouse acceleration (in-game)' 'bDisableMouseAcceleration=True (direct mouse input).' 'Safe' $true @(@{ K = 'bDisableMouseAcceleration'; V = 'True'; Mode = 'Set' })
Add-IniTweak 'Low scalability preset' 'sg.* View distance, shadows, GI, reflections, post-process, textures, effects = 0 (lowest).' 'Moderate' $true @(
    @{ K = 'sg.ViewDistanceQuality'; V = '0'; Mode = 'Set' }, @{ K = 'sg.ShadowQuality'; V = '0'; Mode = 'Set' }, @{ K = 'sg.GlobalIlluminationQuality'; V = '0'; Mode = 'Set' },
    @{ K = 'sg.ReflectionQuality'; V = '0'; Mode = 'Set' }, @{ K = 'sg.PostProcessQuality'; V = '0'; Mode = 'Set' }, @{ K = 'sg.TextureQuality'; V = '0'; Mode = 'Set' },
    @{ K = 'sg.EffectsQuality'; V = '0'; Mode = 'Set' })
Add-IniTweak 'Disable anti-aliasing' 'sg.AntiAliasingQuality=0' 'Moderate' $true @(@{ K = 'sg.AntiAliasingQuality'; V = '0'; Mode = 'Set' })
Add-IniTweak 'Foliage / grass quality = 0' 'sg.FoliageQuality=0' 'Safe' $true @(@{ K = 'sg.FoliageQuality'; V = '0'; Mode = 'Set' })
Add-IniTweak 'Shading quality = 0' 'sg.ShadingQuality=0' 'Safe' $true @(@{ K = 'sg.ShadingQuality'; V = '0'; Mode = 'Set' })
Add-IniTweak 'DLSS quality = 0 (only if config has the key)' 'Edits DLSS quality keys only if already present in your config.' 'Moderate' $false @(@{ K = '(?i)dlss.*quality'; V = '0'; Mode = 'Match' })

Add-IniTweak 'Uncap frame rate (FrameRateLimit=0)' 'Removes the in-game FPS cap. Use with NVIDIA Reflex = On + Boost in game.' 'Safe' $true @(@{ K = 'FrameRateLimit'; V = '0.000000'; Mode = 'Set' })

# ===== FORTNITE: NVIDIA & SYSTEM =====
$c = '14. Fortnite - NVIDIA & System'
Add-Tweak $c 'Fortnite: High-performance GPU preference' 'Windows Graphics setting: run Fortnite on the dedicated NVIDIA GPU (per-user).' 'Safe' $true -Apply {
    $e = Find-FortniteExe; if (-not $e) { throw 'Fortnite executable not found.' }
    Set-Reg 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences' $e 'GpuPreference=2;' 'String'
    $script:State['fnExe'] = $e; Save-State; Log "GPU preference set for $e"
} -Undo {
    if ($script:State.ContainsKey('fnExe')) { Remove-Reg 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences' $script:State['fnExe']; $script:State.Remove('fnExe'); Save-State }
}
Add-Tweak $c 'Fortnite: Above Normal priority (game must be running)' 'Raises the running game process priority. Resets when the game closes.' 'Safe' $false -Apply {
    $p = Get-Process -Name 'FortniteClient-Win64-Shipping' -ErrorAction SilentlyContinue
    if (-not $p) { throw 'Fortnite is not running - launch it, then apply.' }
    $p | ForEach-Object { $_.PriorityClass = 'AboveNormal' }; Log 'Fortnite priority = Above Normal'
} -Undo {
    Get-Process -Name 'FortniteClient-Win64-Shipping' -ErrorAction SilentlyContinue | ForEach-Object { $_.PriorityClass = 'Normal' }
}

Add-RegTweak $c 'Fortnite: persistent High CPU priority (no process handle needed)' 'Uses Windows Image File Execution Options so the game always starts at High priority, without touching the running process (safer with anti-cheat than setting priority from outside).' 'Safe' $true -Items @{ P = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\FortniteClient-Win64-Shipping.exe\PerfOptions'; N = 'CpuPriorityClass'; V = 3 }
Add-Tweak $c 'Fortnite: Defender folder exclusion' 'Excludes the Fortnite install folder from real-time scanning (less disk-scan hitching). Slight security trade-off.' 'Moderate' $false -Apply {
    $e = Find-FortniteExe; if (-not $e) { throw 'Fortnite executable not found.' }
    $root = Split-Path (Split-Path (Split-Path (Split-Path $e -Parent) -Parent) -Parent) -Parent
    Add-MpPreference -ExclusionPath $root -ErrorAction Stop
    $script:State['fnExclusion'] = $root; Save-State; Log "Defender exclusion added: $root"
} -Undo {
    if ($script:State.ContainsKey('fnExclusion')) { Remove-MpPreference -ExclusionPath $script:State['fnExclusion'] -ErrorAction SilentlyContinue; $script:State.Remove('fnExclusion'); Save-State }
}

# ===== FORTNITE: SESSION CLEANUP =====
$c = '15. Fortnite - Session Cleanup'
Add-Tweak $c 'Close Epic Games Launcher' 'Closes the launcher so cache files are not locked.' 'Safe' $true $false -Apply {
    Get-Process -Name 'EpicGamesLauncher', 'EpicWebHelper' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue; Log 'Epic Games Launcher closed'
}
Add-Tweak $c 'Clear Epic Launcher webcache' 'Clears launcher web cache (launcher may sign you in again).' 'Safe' $true $false -Apply {
    Get-ChildItem "$env:LOCALAPPDATA\EpicGamesLauncher\Saved" -Directory -Filter 'webcache*' -ErrorAction SilentlyContinue | ForEach-Object { Clear-Folder $_.FullName }
}
Add-Tweak $c 'Clear Fortnite DerivedDataCache' 'Rebuilds cleanly on next launch (first match may stutter briefly).' 'Safe' $true $false -Apply {
    foreach ($p in "$env:LOCALAPPDATA\FortniteGame\Saved\DerivedDataCache", "$env:LOCALAPPDATA\UnrealEngine\Common\DerivedDataCache") { if (Test-Path $p) { Clear-Folder $p } }
}



# ======================================================================
#  FRENZY TWEAKS v1.2 - UI layer (custom-drawn, per-category colours)
# ======================================================================
function New-Rgb([int]$r, [int]$g, [int]$b) { return [Drawing.Color]::FromArgb($r, $g, $b) }
$script:Clr = @{
    Bg = [Fz.Theme]::Bg; Side = [Fz.Theme]::Side; Card = [Fz.Theme]::Card; Card2 = [Fz.Theme]::Card2; Border = [Fz.Theme]::Border
    Text = [Fz.Theme]::Text; Dim = [Fz.Theme]::Dim; Accent = [Fz.Theme]::Accent; AccentHi = (New-Rgb 255 152 48)
    Good = [Fz.Theme]::Good; Warn = [Fz.Theme]::Warn; Bad = [Fz.Theme]::Bad
}
# every category has its own colour + icon
$script:PageClr = @{
    HOME = (New-Rgb 255 106 0); GENERAL = (New-Rgb 34 211 238); DEBLOAT = (New-Rgb 255 61 139); INPUT = (New-Rgb 255 210 63)
    GPU = (New-Rgb 74 222 128); NETWORK = (New-Rgb 77 141 255); GAMES = (New-Rgb 168 85 247)
}
$script:PageIcon = @{ HOME = 'home'; GENERAL = 'sliders'; DEBLOAT = 'trash'; INPUT = 'bolt'; GPU = 'chip'; NETWORK = 'globe'; GAMES = 'game' }
$script:Acc = $script:Clr.Accent
$script:Fnt = @{
    Norm = [Fz.Theme]::F(13, $false); Bold = [Fz.Theme]::F(13, $true); Small = [Fz.Theme]::F(12, $false); SmallB = [Fz.Theme]::F(12, $true)
    Row = [Fz.Theme]::F(14, $true); Mid = [Fz.Theme]::F(17, $true); Title = [Fz.Theme]::F(32, $true); Huge = [Fz.Theme]::F(30, $true); Hero = [Fz.Theme]::F(46, $true)
    Mono = [Fz.Theme]::M(12, $false); MonoB = [Fz.Theme]::M(12, $true); Tiny = [Fz.Theme]::M(11, $true)
}
$script:Tip = New-Object Windows.Forms.ToolTip; $script:Tip.AutoPopDelay = 15000; $script:Tip.InitialDelay = 300
$script:Pages = @{}; $script:Rows = New-Object System.Collections.ArrayList; $script:GroupHdr = New-Object System.Collections.ArrayList
$script:Tiles = @{}; $script:CurrentPage = 'HOME'; $script:Busy = $false; $script:RPDone = $false; $script:Loading = $false
$script:NavButtons = @{}
$STAR = [string][char]0x2605; $REV = [string][char]0x21BA; $DOT = [string][char]0x25CF; $BAR = [string][char]0x258C
$script:Links = [ordered]@{ Discord = ''; X = ''; TikTok = ''; YouTube = '' }   # <- put your own links here

function Fix-Scroll($c) { $c.Add_HandleCreated({ [Fz.Native]::DarkScroll($this.Handle) }) }

# ---------- System detection ----------
function Get-SysInfo {
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
    $enc = Get-CimInstance Win32_SystemEnclosure -ErrorAction SilentlyContinue
    $bat = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
    $types = @($enc.ChassisTypes)
    $portable = @($types | Where-Object { $_ -in 8, 9, 10, 11, 12, 14, 18, 21, 30, 31, 32 }).Count -gt 0
    $lap = $portable -or ($cs.PCSystemType -eq 2) -or ($bat -and $types.Count -eq 0)
    $gpus = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch 'Basic|Remote|Virtual|Parsec|Meta' } | ForEach-Object { $_.Name })
    $cpuName = if ($cpu) { ($cpu.Name -replace '\(R\)|\(TM\)|CPU|@.*$', '' -replace '\s+', ' ').Trim() } else { 'Unknown CPU' }
    return @{
        IsLaptop = [bool]$lap; Model = "$($cs.Manufacturer) $($cs.Model)"; Cpu = $cpuName; Cores = [int]$cpu.NumberOfCores; Threads = [int]$cpu.NumberOfLogicalProcessors
        Gpus = $gpus; RamGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1); HasBattery = [bool]$bat
    }
}
$script:Sys = Get-SysInfo
$script:Guard = [bool]$script:Sys.IsLaptop
$script:GpuShort = if ($script:Sys.Gpus.Count -gt 0) { ($script:Sys.Gpus | Where-Object { $_ -match 'NVIDIA|AMD Radeon|Arc' } | Select-Object -First 1) } else { $null }
if (-not $script:GpuShort -and $script:Sys.Gpus.Count -gt 0) { $script:GpuShort = $script:Sys.Gpus[0] }
if (-not $script:GpuShort) { $script:GpuShort = 'Unknown GPU' }

# ---------- Formatting ----------
function Format-Bytes([double]$b) {
    if ($b -ge 1GB) { return ('{0:N1} GB' -f ($b / 1GB)) }
    if ($b -ge 1MB) { return ('{0:N1} MB' -f ($b / 1MB)) }
    if ($b -ge 1KB) { return ('{0:N0} KB' -f ($b / 1KB)) }
    return ('{0:N0} B' -f $b)
}
function Format-Rate([double]$bps) { return ((Format-Bytes $bps) + '/s') }


# ---------- Brand: F logo + wordmark ----------
# ---------- Brand: F logo + wordmark ----------
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
function New-LogoBox([int]$Size, $BgColor) {
    $p = New-Object Windows.Forms.Panel; $p.Size = New-Object Drawing.Size($Size, $Size); $p.BackColor = $BgColor
    $p.Add_Paint({ param($sn, $e) $e.Graphics.SmoothingMode = 'AntiAlias'; Draw-FrenzyLogo $e.Graphics 1 1 ($sn.Width - 2) })
    return $p
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
function New-Wordmark([int]$X, [int]$Y, [single]$Px, [single]$Sp, $BgColor) {
    $font = New-Object Drawing.Font($script:HeadFont, $Px, [Drawing.FontStyle]::Bold, [Drawing.GraphicsUnit]::Pixel)
    $tmp = New-Object Drawing.Bitmap(1, 1); $mg = [Drawing.Graphics]::FromImage($tmp)
    $w1 = Measure-Spaced $mg 'FRENZY' $font $Sp; $w2 = Measure-Spaced $mg 'TWEAKS' $font $Sp; $gap = $Px * 0.5
    $mg.Dispose(); $tmp.Dispose()
    $p = New-Object Windows.Forms.Panel; $p.Location = New-Object Drawing.Point($X, $Y)
    $p.Size = New-Object Drawing.Size(([int]($w1 + $gap + $w2 + 6)), ([int]($Px * 1.45))); $p.BackColor = $BgColor
    $p.Tag = @{ Font = $font; Gap = $gap; Sp = $Sp }
    $p.Add_Paint({ param($sn, $e)
            $g = $e.Graphics; $g.TextRenderingHint = 'AntiAliasGridFit'; $t = $sn.Tag
            $b1 = New-Object Drawing.SolidBrush($script:Clr.Text); $b2 = New-Object Drawing.SolidBrush($script:Clr.Accent)
            $nx = Draw-Spaced $g 'FRENZY' $t.Font $b1 0 0 $t.Sp
            [void](Draw-Spaced $g 'TWEAKS' $t.Font $b2 ($nx + $t.Gap) 0 $t.Sp)
            $b1.Dispose(); $b2.Dispose() })
    return $p
}

# ---------- Control factories ----------
function New-Lbl([string]$Text, [int]$X, [int]$Y, [int]$W, [int]$H, $Font = $null, $Color = $null) {
    if (-not $Font) { $Font = $script:Fnt.Norm }; if (-not $Color) { $Color = $script:Clr.Text }
    $l = New-Object Windows.Forms.Label; $l.Text = $Text; $l.UseMnemonic = $false; $l.AutoSize = $false
    $l.Location = New-Object Drawing.Point($X, $Y); $l.Size = New-Object Drawing.Size($W, $H)
    $l.Font = $Font; $l.ForeColor = $Color; $l.BackColor = [Drawing.Color]::Transparent
    return $l
}
function New-Btn([string]$Text, [int]$W = 150, [int]$H = 36, [bool]$Primary = $false, $Accent = $null, [string]$Icon = '') {
    $b = New-Object Fz.FzButton; $b.Text = $Text; $b.Size = New-Object Drawing.Size($W, $H); $b.Primary = $Primary
    $b.Accent = $(if ($Accent) { $Accent } else { $script:Acc }); if ($Icon) { $b.Icon = $Icon }
    $b.Font = $script:Fnt.SmallB; $b.UseMnemonic = $false
    return $b
}
function New-Card([int]$W, [int]$H, [string]$Size = 'full', $Accent = $null) {
    $p = New-Object Fz.FzCard; $p.Size = New-Object Drawing.Size($W, $H); $p.Name = $Size
    $p.Accent = $(if ($Accent) { $Accent } else { $script:Acc }); $p.Margin = New-Object Windows.Forms.Padding(0, 0, 12, 12)
    return $p
}
function New-Section([string]$Text, $Accent = $null) {
    $a = $(if ($Accent) { $Accent } else { $script:Acc })
    $p = New-Object Windows.Forms.Panel; $p.Name = 'full'; $p.Height = 34; $p.Width = 800; $p.BackColor = $script:Clr.Bg
    $p.Margin = New-Object Windows.Forms.Padding(0, 8, 12, 2)
    $p.Controls.Add((New-Lbl "$BAR $Text" 0 6 800 24 $script:Fnt.Mid $a)); $p.Controls[0].BackColor = $script:Clr.Bg
    return $p
}
function Fit-Flow($f) {
    $w = $f.ClientSize.Width - $f.Padding.Horizontal - [Windows.Forms.SystemInformation]::VerticalScrollBarWidth - 2
    if ($w -lt 300) { return }
    $gap = 12; $f.SuspendLayout()
    foreach ($c in $f.Controls) {
        $nw = 0
        if ($c.Name -eq 'full') { $nw = $w - $gap }
        elseif ($c.Name -eq 'half') { $nw = [int](($w - $gap * 2) / 2) }
        elseif ($c.Name -eq 'third') { $nw = [int](($w - $gap * 3) / 3) }
        elseif ($c.Name -eq 'quarter') { $nw = [int](($w - $gap * 4) / 4) }
        if ($nw -gt 0 -and $c.Width -ne $nw) { $c.Width = $nw }
    }
    $f.ResumeLayout($true)
}
function New-Tile([string]$Title, $Accent = $null) {
    $a = $(if ($Accent) { $Accent } else { $script:Acc })
    $p = New-Card 240 138 'quarter' $a; $p.Stripe = $true
    $v = New-Lbl '--' 18 32 400 42 $script:Fnt.Huge; $av = New-Lbl '' 18 76 400 16 $script:Fnt.Tiny $script:Clr.Dim
    $s = New-Lbl '' 18 94 400 16 $script:Fnt.Small $script:Clr.Dim; $s.AutoEllipsis = $true
    $t = New-Lbl $Title 18 10 300 18 $script:Fnt.Tiny $a
    $bar = New-Object Fz.FzProgress; $bar.Accent = $a; $bar.Height = 6; $bar.Location = New-Object Drawing.Point(18, 118); $bar.Width = 200
    $p.Controls.AddRange(@($t, $v, $av, $s, $bar))
    $p.Add_Resize({ $w = $this.Width; foreach ($c in $this.Controls) { if ($c -is [Windows.Forms.Label] -and $c.Left -eq 18) { $c.Width = $w - 36 } elseif ($c -is [Fz.FzProgress]) { $c.Width = $w - 36 } } })
    return @{ Panel = $p; Val = $v; Avg = $av; Sub = $s; Bar = $bar }
}
function Set-Tile($Tile, [string]$Val, $Pct, [string]$Avg, [string]$Sub) {
    if (-not $Tile) { return }
    $Tile.Val.Text = $Val; $Tile.Avg.Text = $Avg; $Tile.Sub.Text = $Sub
    if ($null -ne $Pct) { $Tile.Bar.Value = [int][math]::Max(0, [math]::Min(100, $Pct)) }
}
function New-PageShell([string]$Key, [string]$Title, [string]$Sub, [int]$HeadH = 116) {
    $acc = $script:PageClr[$Key]; $script:Acc = $acc
    $p = New-Object Windows.Forms.Panel; $p.Dock = 'Fill'; $p.BackColor = $script:Clr.Bg; $p.Visible = $false
    $hd = New-Object Fz.FzHeader; $hd.Dock = 'Top'; $hd.Height = $HeadH; $hd.Accent = $acc
    $hd.Controls.Add((New-Lbl ('FRENZY TWEAKS  >  ' + $Title) 30 12 700 18 $script:Fnt.Tiny $script:Clr.Dim))
    $hd.Controls.Add((New-Lbl $Title 28 30 700 46 $script:Fnt.Title $script:Clr.Text))
    $sl = New-Lbl $Sub 31 78 900 22 $script:Fnt.Norm $script:Clr.Dim; $hd.Controls.Add($sl)
    $flow = New-Object Fz.FzFlow; $flow.Dock = 'Fill'; $flow.FlowDirection = 'LeftToRight'; $flow.WrapContents = $true
    $flow.AutoScroll = $true; $flow.BackColor = $script:Clr.Bg; $flow.Padding = New-Object Windows.Forms.Padding(28, 10, 16, 14)
    $flow.Add_Resize({ Fit-Flow $this })
    $p.Controls.Add($flow); $p.Controls.Add($hd); $flow.BringToFront()
    $script:Pages[$Key] = @{ Panel = $p; Flow = $flow; Header = $hd; Footer = $null; FooterLbl = $null; Accent = $acc }
    return $p
}

# ---------- Tweak rows (cards with toggle switches) ----------
function Add-GroupHeader($flow, [string]$Key, [string]$Group) {
    $a = $script:PageClr[$Key]
    $p = New-Object Windows.Forms.Panel; $p.Name = 'full'; $p.Height = 36; $p.Width = 800; $p.BackColor = $script:Clr.Bg
    $p.Margin = New-Object Windows.Forms.Padding(0, 10, 12, 2)
    $l = New-Lbl "$BAR $Group" 0 8 600 24 $script:Fnt.Mid $a; $l.BackColor = $script:Clr.Bg
    $c = New-Lbl '' 0 11 200 18 $script:Fnt.Tiny $script:Clr.Dim; $c.TextAlign = 'MiddleRight'; $c.BackColor = $script:Clr.Bg
    $p.Controls.Add($l); $p.Controls.Add($c)
    $p.Add_Resize({ $this.Controls[1].Left = $this.Width - 210 })
    $p.Width = 801
    $flow.Controls.Add($p)
    [void]$script:GroupHdr.Add([pscustomobject]@{ Page = $Key; Group = $Group; Lbl = $l; Cnt = $c; Panel = $p })
}
function Show-TweakInfo($t) {
    $u = if ($t.Reversible) { 'Yes - the original value is backed up and restored on undo.' } else { 'No automatic undo (one-time action).' }
    [void][Fz.Msg]::Show("$($t.Desc)`n`nRisk: $($t.Risk)`nUndo: $u", $t.Name, 'OK', 'Information')
}
function Add-TweakRow($flow, $t, [string]$Key, [string]$Group) {
    $acc = $script:PageClr[$Key]
    $row = New-Object Fz.FzCard; $row.Name = 'half'; $row.Height = 108; $row.Width = 480; $row.Accent = $acc
    $row.Margin = New-Object Windows.Forms.Padding(0, 0, 12, 12)
    $oneShot = -not $t.Reversible
    $nameL = New-Lbl $t.Name 18 12 380 22 $script:Fnt.Row $script:Clr.Text; $nameL.AutoEllipsis = $true
    $nameW = [Windows.Forms.TextRenderer]::MeasureText($t.Name, $script:Fnt.Row).Width + 2
    $starL = New-Lbl $STAR 0 13 18 20 $script:Fnt.Row $script:Clr.Warn; $starL.Visible = [bool]$t.Default
    $revL = New-Lbl $REV 0 13 18 20 $script:Fnt.Row $script:Clr.Good; $revL.Visible = [bool]$t.Reversible
    $descL = New-Lbl $t.Desc 18 38 440 34 $script:Fnt.Small $script:Clr.Dim; $descL.AutoEllipsis = $true
    $riskCol = switch ($t.Risk) { 'Safe' { $script:Clr.Good } 'Moderate' { $script:Clr.Warn } default { $script:Clr.Bad } }
    $pill = New-Object Fz.FzPill; $pill.Text = $t.Risk.ToUpper(); $pill.Tint = $riskCol; $pill.Location = New-Object Drawing.Point(18, 80); $pill.Fit()
    $nrL = New-Lbl $(if ($oneShot) { 'NOT REVERSIBLE' } else { '' }) ($pill.Right + 10) 82 150 16 $script:Fnt.Tiny $script:Clr.Bad
    $stat = New-Lbl '' 0 82 150 16 $script:Fnt.Tiny $script:Clr.Dim; $stat.TextAlign = 'MiddleRight'
    $info = New-Object Fz.FzButton; $info.Text = 'i'; $info.Size = New-Object Drawing.Size(26, 26); $info.Accent = $acc; $info.Font = $script:Fnt.SmallB; $info.Radius = 13; $info.Top = 11
    $info.Tag = $t; $info.Add_Click({ Show-TweakInfo $this.Tag })
    $chk = $null; $ctl = $null
    $rec = [pscustomobject]@{ Page = $Key; Group = $Group; T = $t; Chk = $null; Status = $stat; OneShot = $oneShot; Row = $row; Active = $false; Shown = $true }
    if ($oneShot) {
        $ctl = New-Btn 'RUN' 74 28 $false $acc 'bolt'; $ctl.Top = 10; $ctl.Tag = $t; $ctl.Add_Click({ Invoke-Run @($this.Tag) @() })
    } else {
        $chk = New-Object Fz.FzToggle; $chk.OnColor = $acc; $chk.Top = 12; $ctl = $chk; $rec.Chk = $chk; $chk.Tag = $rec
        $chk.Add_CheckedChanged({ $r = $this.Tag; $r.Row.Lit = $this.Checked; if (-not $script:Busy -and -not $script:Loading) { Update-Footer $r.Page } })
    }
    $row.Tag = @{ Name = $nameL; NameW = $nameW; Star = $starL; Rev = $revL; Desc = $descL; Info = $info; Ctl = $ctl; Stat = $stat }
    $row.Controls.AddRange(@($nameL, $starL, $revL, $descL, $pill, $nrL, $stat, $info, $ctl))
    $row.Add_Resize({
            $s = $this.Tag; $w = $this.Width
            $s.Ctl.Left = $w - 16 - $s.Ctl.Width; $s.Info.Left = $s.Ctl.Left - 34
            $avail = $s.Info.Left - 18 - 12
            $s.Name.Width = [math]::Max(60, [math]::Min($s.NameW, $avail - 44))
            $x = 18 + $s.Name.Width + 4
            $s.Star.Left = $x; $s.Rev.Left = $x + 18
            $s.Star.Visible = ($s.Star.Tag -ne 'off') -and ($x + 20 -lt $s.Info.Left)
            $s.Rev.Visible = ($s.Rev.Tag -ne 'off') -and ($x + 38 -lt $s.Info.Left)
            $s.Desc.Width = $w - 36; $s.Stat.Left = $w - 16 - $s.Stat.Width
        })
    if (-not $t.Default) { $starL.Tag = 'off' }; if (-not $t.Reversible) { $revL.Tag = 'off' }
    $row.Width = 481
    $tipText = "$($t.Name)`n$($t.Desc)`nRisk: $($t.Risk)   Undo: $(if ($t.Reversible) { 'yes' } else { 'no' })"
    foreach ($c in @($nameL, $descL, $row)) { $script:Tip.SetToolTip($c, $tipText) }
    $flow.Controls.Add($row); [void]$script:Rows.Add($rec)
    return $rec
}
function Refresh-Row($r) {
    $act = Test-TweakActive $r.T; $r.Active = $act
    if ($r.OneShot) {
        if ($act) { $r.Status.Text = 'DONE'; $r.Status.ForeColor = $script:Clr.Good } else { $r.Status.Text = 'ONE-TIME ACTION'; $r.Status.ForeColor = $script:Clr.Dim }
    } else {
        $r.Chk.Checked = $act; $r.Row.Lit = $act
        if ($act) { $r.Status.Text = "$DOT ACTIVE"; $r.Status.ForeColor = $script:Clr.Good } else { $r.Status.Text = 'OFF'; $r.Status.ForeColor = $script:Clr.Dim }
    }
}
function Refresh-AllRows {
    $script:Loading = $true; $n = 0
    try { foreach ($r in $script:Rows) { Refresh-Row $r; $n++; if (($n % 6) -eq 0) { Pump } } } finally { $script:Loading = $false }
    foreach ($k in @($script:Pages.Keys)) { Update-Footer $k }
}
function Get-PageStats([string]$Key) {
    $rows = @($script:Rows | Where-Object { $_.Page -eq $Key -and -not $_.OneShot })
    return @{
        Rows = $rows; Active = @($rows | Where-Object { $_.Active }).Count
        Apply = @($rows | Where-Object { $_.Chk.Checked -and -not $_.Active }); Undo = @($rows | Where-Object { -not $_.Chk.Checked -and $_.Active })
    }
}
function Update-Footer([string]$Key) {
    $pg = $script:Pages[$Key]; if (-not $pg -or -not $pg.FooterLbl) { return }
    $s = Get-PageStats $Key
    $pg.FooterLbl.Text = "{0} of {1} tweaks active   |   {2} to apply   |   {3} to undo" -f $s.Active, $s.Rows.Count, $s.Apply.Count, $s.Undo.Count
    foreach ($h in @($script:GroupHdr | Where-Object { $_.Page -eq $Key })) {
        $g = @($s.Rows | Where-Object { $_.Group -eq $h.Group }); $a = @($g | Where-Object { $_.Active }).Count
        if ($g.Count -gt 0) { $h.Cnt.Text = "{0} / {1} active" -f $a, $g.Count } else { $h.Cnt.Text = '' }
    }
    if ($pg.CountLbl) { $pg.CountLbl.Text = "{0} of {1}" -f @($script:Rows | Where-Object { $_.Page -eq $Key -and $_.Shown }).Count, @($script:Rows | Where-Object { $_.Page -eq $Key }).Count }
    if ($pg.RecBtn) { $n = @($script:Rows | Where-Object { $_.Page -eq $Key -and -not $_.OneShot -and $_.T.Default -and $_.T.Risk -ne 'Expert' }).Count; $pg.RecBtn.Text = "SELECT RECOMMENDED  $DOT  $n" }
}
function Invoke-PagePending([string]$Key) {
    $s = Get-PageStats $Key
    Invoke-Run @($s.Apply | ForEach-Object { $_.T }) @($s.Undo | ForEach-Object { $_.T })
}
function Select-Recommended([string]$Key) {
    foreach ($r in @($script:Rows | Where-Object { $_.Page -eq $Key -and -not $_.OneShot })) { if ($r.T.Default -and $r.T.Risk -ne 'Expert') { $r.Chk.Checked = $true } }
    Update-Footer $Key
}
function Filter-Page([string]$Key, [string]$Query) {
    $q = $Query.Trim().ToLower(); $pg = $script:Pages[$Key]; $pg.Flow.SuspendLayout()
    foreach ($r in @($script:Rows | Where-Object { $_.Page -eq $Key })) {
        $r.Shown = ($q -eq '') -or $r.T.Name.ToLower().Contains($q) -or $r.T.Desc.ToLower().Contains($q)
        $r.Row.Visible = $r.Shown
    }
    foreach ($h in @($script:GroupHdr | Where-Object { $_.Page -eq $Key })) {
        $h.Panel.Visible = (@($script:Rows | Where-Object { $_.Page -eq $Key -and $_.Group -eq $h.Group -and $_.Shown }).Count -gt 0)
    }
    $pg.Flow.ResumeLayout($true); Update-Footer $Key
}
function New-SearchBox([string]$Key) {
    $c = New-Object Fz.FzCard; $c.Size = New-Object Drawing.Size(340, 38); $c.Icon = 'search'; $c.Accent = $script:PageClr[$Key]; $c.Radius = 10; $c.BackColor = $script:Clr.Card
    $tb = New-Object Windows.Forms.TextBox; $tb.BorderStyle = 'None'; $tb.BackColor = $script:Clr.Card; $tb.ForeColor = $script:Clr.Text; $tb.Font = $script:Fnt.Norm
    $tb.Location = New-Object Drawing.Point(42, 10); $tb.Width = 282; $tb.Tag = $Key
    $tb.Add_TextChanged({ Filter-Page $this.Tag $this.Text })
    $c.Controls.Add($tb); return $c
}
function Build-TweakPage([string]$Key, [string]$Title, [string]$Sub, [scriptblock]$Pre = $null, [scriptblock]$Post = $null) {
    $p = New-PageShell $Key $Title $Sub 166; $pg = $script:Pages[$Key]; $flow = $pg.Flow; $acc = $pg.Accent
    $sb = New-SearchBox $Key; $sb.Location = New-Object Drawing.Point(30, 114); $pg.Header.Controls.Add($sb)
    $pg.CountLbl = New-Lbl '' 384 124 120 20 $script:Fnt.Mono $script:Clr.Dim; $pg.Header.Controls.Add($pg.CountLbl)
    $btnPanel = New-Object Windows.Forms.FlowLayoutPanel; $btnPanel.Dock = 'Right'; $btnPanel.Width = 500; $btnPanel.FlowDirection = 'RightToLeft'
    $btnPanel.Padding = New-Object Windows.Forms.Padding(0, 116, 24, 0); $btnPanel.BackColor = [Drawing.Color]::Transparent
    $bAll = New-Btn 'APPLY RECOMMENDED' 180 38 $true $acc 'bolt'; $bAll.Tag = $Key; $bAll.Add_Click({ Select-Recommended $this.Tag; Invoke-PagePending $this.Tag })
    $bSel = New-Btn 'SELECT RECOMMENDED' 250 38 $false $acc 'check'; $bSel.Tag = $Key; $bSel.Add_Click({ Select-Recommended $this.Tag }); $pg.RecBtn = $bSel
    $btnPanel.Controls.Add($bAll); $btnPanel.Controls.Add($bSel); $pg.Header.Controls.Add($btnPanel)
    $foot = New-Object Windows.Forms.Panel; $foot.Dock = 'Bottom'; $foot.Height = 58; $foot.BackColor = $script:Clr.Side
    $fl = New-Lbl '' 30 19 800 22 $script:Fnt.Mono $script:Clr.Dim
    $fb = New-Btn 'APPLY CHANGES' 190 38 $true $acc 'check'; $fb.Tag = $Key; $fb.Add_Click({ Invoke-PagePending $this.Tag })
    $fbp = New-Object Windows.Forms.Panel; $fbp.Dock = 'Right'; $fbp.Width = 220; $fbp.BackColor = $script:Clr.Side; $fb.Location = New-Object Drawing.Point(8, 10); $fbp.Controls.Add($fb)
    $foot.Controls.Add($fl); $foot.Controls.Add($fbp); $p.Controls.Add($foot); $flow.BringToFront()
    $pg.FooterLbl = $fl
    if ($Pre) { $null = & $Pre $flow }
    $last = $null
    foreach ($it in (Get-PageTweaks $Key)) {
        if ($it.Group -ne $last) { Add-GroupHeader $flow $Key $it.Group; $last = $it.Group }
        [void](Add-TweakRow $flow $it.T $Key $it.Group)
    }
    if ($Post) { $null = & $Post $flow }
    return $p
}

# ---------- Telemetry ----------
$script:Tel = @{ Hist = @{ cpu = (New-Object System.Collections.ArrayList); gpu = (New-Object System.Collections.ArrayList); mem = (New-Object System.Collections.ArrayList) }; Gpu = $null; Tick = 0; PeakNet = [double]0; PrevRx = [int64]0; PrevTx = [int64]0 }
$script:NvSmiPath = $null
$cmd = Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue
if ($cmd) { $script:NvSmiPath = $cmd.Source }
else { foreach ($p in "$env:ProgramFiles\NVIDIA Corporation\NVSMI\nvidia-smi.exe", "$env:WINDIR\System32\nvidia-smi.exe") { if (Test-Path $p) { $script:NvSmiPath = $p; break } } }
function Initialize-Telemetry {
    try { $script:CpuCtr = New-Object Diagnostics.PerformanceCounter('Processor Information', '% Processor Utility', '_Total'); [void]$script:CpuCtr.NextValue() }
    catch { try { $script:CpuCtr = New-Object Diagnostics.PerformanceCounter('Processor', '% Processor Time', '_Total'); [void]$script:CpuCtr.NextValue() } catch { $script:CpuCtr = $null } }
    Add-Type -AssemblyName Microsoft.VisualBasic
    $script:CI = New-Object Microsoft.VisualBasic.Devices.ComputerInfo
    $script:NetSw = [Diagnostics.Stopwatch]::StartNew()
    $nb = Get-NetBytes; $script:Tel.PrevRx = $nb[0]; $script:Tel.PrevTx = $nb[1]
    try { $script:LinkSpeed = (Get-NetAdapter -Physical -ErrorAction Stop | Where-Object Status -eq 'Up' | Select-Object -First 1).LinkSpeed } catch { $script:LinkSpeed = '' }
}
function Get-NetBytes {
    $rx = [int64]0; $tx = [int64]0
    foreach ($n in [Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
        if ($n.OperationalStatus -eq 'Up' -and $n.NetworkInterfaceType -ne 'Loopback' -and $n.NetworkInterfaceType -ne 'Tunnel') {
            try { $s = $n.GetIPv4Statistics(); $rx += $s.BytesReceived; $tx += $s.BytesSent } catch {}
        }
    }
    return @($rx, $tx)
}
function Get-NvSmi {
    if (-not $script:NvSmiPath) { return $null }
    try {
        $o = & $script:NvSmiPath '--query-gpu=name,driver_version,temperature.gpu,utilization.gpu,fan.speed,power.draw,power.limit,power.max_limit,power.min_limit,pstate' '--format=csv,noheader,nounits' 2>$null | Select-Object -First 1
        if (-not $o) { return $null }
        $f = @($o -split ',' | ForEach-Object { $_.Trim() })
        $num = { param($x) $d = 0.0; if ([double]::TryParse($x, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$d)) { $d } else { $null } }
        return [pscustomobject]@{ Name = $f[0]; Driver = $f[1]; Temp = (& $num $f[2]); Load = (& $num $f[3]); Fan = (& $num $f[4]); PowerDraw = (& $num $f[5]); PowerLimit = (& $num $f[6]); PowerMax = (& $num $f[7]); PowerMin = (& $num $f[8]); PState = $f[9] }
    } catch { return $null }
}
function Add-Hist([string]$k, [double]$v) { $h = $script:Tel.Hist[$k]; [void]$h.Add($v); if ($h.Count -gt 40) { $h.RemoveAt(0) } }
function Get-HistAvg([string]$k) { $h = $script:Tel.Hist[$k]; if ($h.Count -eq 0) { return 0 }; return [math]::Round(($h | Measure-Object -Average).Average, 0) }
function Update-Telemetry {
    if ($script:CurrentPage -ne 'HOME' -and $script:CurrentPage -ne 'GPU') { return }
    $cpu = 0; try { if ($script:CpuCtr) { $cpu = [math]::Min(100, [math]::Round($script:CpuCtr.NextValue(), 0)) } } catch {}
    Add-Hist 'cpu' $cpu
    $tot = [double]$script:CI.TotalPhysicalMemory; $av = [double]$script:CI.AvailablePhysicalMemory
    $mem = if ($tot -gt 0) { [math]::Round(($tot - $av) / $tot * 100, 0) } else { 0 }; Add-Hist 'mem' $mem
    $el = $script:NetSw.Elapsed.TotalSeconds; $script:NetSw.Restart(); if ($el -lt 0.2) { $el = 1.5 }
    $nb = Get-NetBytes; $rxs = [math]::Max(0, ($nb[0] - $script:Tel.PrevRx) / $el); $txs = [math]::Max(0, ($nb[1] - $script:Tel.PrevTx) / $el)
    $script:Tel.PrevRx = $nb[0]; $script:Tel.PrevTx = $nb[1]
    if (($rxs + $txs) -gt $script:Tel.PeakNet) { $script:Tel.PeakNet = $rxs + $txs }
    $script:Tel.Tick++
    if (($script:Tel.Tick % 2) -eq 1 -or -not $script:Tel.Gpu) { $script:Tel.Gpu = Get-NvSmi }
    $g = $script:Tel.Gpu
    if ($g -and $null -ne $g.Load) { Add-Hist 'gpu' $g.Load }
    Set-Tile $script:Tiles.cpu ("{0}%" -f $cpu) $cpu ("AVG {0}%" -f (Get-HistAvg 'cpu')) $script:Sys.Cpu
    Set-Tile $script:Tiles.mem ("{0}%" -f $mem) $mem ("AVG {0}%" -f (Get-HistAvg 'mem')) ("{0} / {1} GB" -f [math]::Round(($tot - $av) / 1GB, 1), [math]::Round($tot / 1GB, 1))
    if ($g -and $null -ne $g.Load) { Set-Tile $script:Tiles.gpu ("{0}%" -f $g.Load) $g.Load ("AVG {0}%" -f (Get-HistAvg 'gpu')) $g.Name }
    else { Set-Tile $script:Tiles.gpu 'N/A' 0 'no NVIDIA sensor' $script:GpuShort }
    Set-Tile $script:Tiles.net (Format-Rate ($rxs + $txs)) $null ('PEAK ' + (Format-Rate $script:Tel.PeakNet)) ("down {0}   up {1}" -f (Format-Rate $rxs), (Format-Rate $txs))
    if ($script:Tiles.gTemp) {
        if ($g) {
            $tp = if ($null -ne $g.Temp) { "{0} C" -f $g.Temp } else { 'N/A' }
            Set-Tile $script:Tiles.gTemp $tp $g.Temp '' ("P-state {0}" -f $g.PState)
            Set-Tile $script:Tiles.gLoad ("{0}%" -f $g.Load) $g.Load ("AVG {0}%" -f (Get-HistAvg 'gpu')) ''
            $fn = if ($null -ne $g.Fan) { "{0}%" -f $g.Fan } else { 'N/A' }
            Set-Tile $script:Tiles.gFan $fn $g.Fan '' $(if ($null -eq $g.Fan) { 'Laptop fans are EC-controlled' } else { '' })
            Set-Tile $script:Tiles.gDrv 'READY' 100 '' ("Driver " + $g.Driver)
        } else {
            foreach ($k in 'gTemp', 'gLoad', 'gFan') { Set-Tile $script:Tiles[$k] 'N/A' 0 '' 'NVIDIA sensor unavailable' }
            Set-Tile $script:Tiles.gDrv 'NOT FOUND' 0 '' 'nvidia-smi missing - install NVIDIA driver'
        }
    }
}

# ---------- Power helpers ----------
function Get-ActivePlan {
    $o = (& powercfg.exe /getactivescheme | Out-String)
    $name = ([regex]::Match($o, '\(([^)]+)\)')).Groups[1].Value
    return @{ Guid = (Get-GuidFrom $o); Name = $name }
}
function Get-AcIndex([string]$Scheme, [string]$Sub, [string]$Set) {
    $o = (& powercfg.exe /query $Scheme $Sub $Set 2>$null | Out-String)
    $hex = @([regex]::Matches($o, '0x([0-9a-fA-F]{8})'))
    if ($hex.Count -ge 2) { return [Convert]::ToInt32($hex[$hex.Count - 2].Groups[1].Value, 16) }
    return $null
}
$script:PowerSettings = @(
    @('SUB_PROCESSOR', 'PROCTHROTTLEMIN', 100), @('SUB_PROCESSOR', 'CPMINCORES', 100), @('SUB_PROCESSOR', 'PERFBOOSTMODE', 2),
    @('2a737441-1930-4402-8d77-b2bebba308a3', '48e6b7a6-50f5-4782-a5d4-53bb8f07e226', 0))
$script:PowerTweakName = 'Performance power plan (plugged in)'
$c = '11. Power & GPU'
Add-Tweak $c $script:PowerTweakName 'Desktop: creates and activates Ultimate Performance. Laptop (Laptop Guard on): keeps your current plan and only raises PLUGGED-IN values (CPU min 100%, no core parking, boost aggressive, USB suspend off) - battery behaviour is untouched.' 'Moderate' $true -Apply {
    $act = Get-ActivePlan
    if ($script:Guard) {
        foreach ($s in $script:PowerSettings) {
            $cur = Get-AcIndex $act.Guid $s[0] $s[1]
            if ($null -eq $cur) { continue }
            $k = "pwr|$($act.Guid)|$($s[0])|$($s[1])"
            if (-not $script:State.ContainsKey($k)) { $script:State[$k] = $cur }
            & powercfg.exe /setacvalueindex $act.Guid $s[0] $s[1] $s[2] | Out-Null
        }
        & powercfg.exe /setactive $act.Guid | Out-Null
        $script:State['power:mode'] = 'guard'; Save-State
        Log "Laptop Guard: plugged-in values raised on plan '$($act.Name)' (battery values unchanged)"
    } else {
        if ($act.Guid -and -not $script:State.ContainsKey('power:prev')) { $script:State['power:prev'] = $act.Guid }
        $new = Get-GuidFrom ((& powercfg.exe /duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>&1) | Out-String)
        if (-not $new) { Log 'Ultimate Performance unavailable - using High Performance' 'WARN'; $new = Get-GuidFrom ((& powercfg.exe /duplicatescheme 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>&1) | Out-String) }
        if (-not $new) { throw 'Could not create a performance power plan.' }
        & powercfg.exe /changename $new 'Frenzy Performance' 'Created by FRENZY TWEAKS' | Out-Null
        $script:State['power:new'] = $new
        foreach ($s in $script:PowerSettings) { & powercfg.exe /setacvalueindex $new $s[0] $s[1] $s[2] | Out-Null; & powercfg.exe /setdcvalueindex $new $s[0] $s[1] $s[2] | Out-Null }
        & powercfg.exe /setactive $new | Out-Null
        $script:State['power:mode'] = 'desktop'; Save-State
        Log "Active power plan: Frenzy Performance ($new)"
    }
} -Undo {
    foreach ($k in @($script:State.Keys | Where-Object { $_ -like 'pwr|*' })) {
        $p = $k.Split('|'); & powercfg.exe /setacvalueindex $p[1] $p[2] $p[3] ([int]$script:State[$k]) 2>$null | Out-Null; $script:State.Remove($k)
    }
    if ($script:State.ContainsKey('power:prev')) { & powercfg.exe /setactive $script:State['power:prev'] | Out-Null; $script:State.Remove('power:prev') }
    if ($script:State.ContainsKey('power:new')) { & powercfg.exe /delete $script:State['power:new'] | Out-Null; $script:State.Remove('power:new') }
    $cur = Get-ActivePlan; if ($cur.Guid) { & powercfg.exe /setactive $cur.Guid | Out-Null }
    $script:State.Remove('power:mode'); Save-State; Log 'Previous power settings restored'
}

# ---------- Tweak state detection ----------
function Test-TweakActive($t) {
    switch ($t.Kind) {
        'Reg' {
            foreach ($i in $t.Arg) {
                try { $cur = (Get-ItemProperty -Path $i.P -Name $i.N -ErrorAction Stop).($i.N) } catch { return $false }
                if ("$cur" -ne "$($i.V)") { return $false }
            }
            return $true
        }
        'Svc' {
            $found = 0
            foreach ($s in $t.Arg) {
                $k = "HKLM:\SYSTEM\CurrentControlSet\Services\$s"
                if (-not (Test-Path $k)) { continue }
                $found++; if ((Get-ItemProperty $k).Start -ne 4) { return $false }
            }
            return ($found -gt 0)
        }
        'Task' {
            $found = 0
            foreach ($full in $t.Arg) {
                $i = $full.LastIndexOf('\'); $x = Get-ScheduledTask -TaskPath $full.Substring(0, $i + 1) -TaskName $full.Substring($i + 1) -ErrorAction SilentlyContinue
                if (-not $x) { continue }; $found++; if ($x.State -ne 'Disabled') { return $false }
            }
            return ($found -gt 0)
        }
        default { return [bool]$script:State["applied:$($t.Name)"] }
    }
}

# ---------- Where does each tweak live in the UI ----------
$script:GroupOrder = @{
    GENERAL = @('CLEANUP & SHELL', 'PRIVACY', 'NOTIFICATIONS & SURFACES', 'DIAGNOSTICS & BACKGROUND', 'OPTIONAL WINDOWS FEATURES')
    INPUT   = @('PRIORITY & SCHEDULING', 'INPUT HARDWARE', 'BACKGROUND SERVICES', 'GAME SURFACES & OVERLAYS', 'COMPANION APPS')
    GPU     = @('POWER & PCIE')
    NETWORK = @('NETWORK TWEAKS', 'ADVANCED (EXPERT)')
    GAMES   = @('IN-GAME CONFIG', 'NVIDIA & SYSTEM', 'SESSION CLEANUP')
}
$script:InputMap = @{
    'Foreground Priority Boost' = 'PRIORITY & SCHEDULING'; 'Minimum System Service Priority' = 'PRIORITY & SCHEDULING'
    'Disable Mouse Acceleration' = 'INPUT HARDWARE'; 'Block Accessibility Shortcut Popups' = 'INPUT HARDWARE'
    'Disable NTFS Last Access Update' = 'BACKGROUND SERVICES'; 'Disable Windows Search (WSearch)' = 'BACKGROUND SERVICES'; 'Disable SuperFetch (SysMain)' = 'BACKGROUND SERVICES'
    'Disable Game Bar and DVR' = 'GAME SURFACES & OVERLAYS'; 'Disable Xbox Services and Components' = 'GAME SURFACES & OVERLAYS'
    'Windows Game Mode ON' = 'GAME SURFACES & OVERLAYS'; 'Disable Multiplane Overlay (MPO)' = 'GAME SURFACES & OVERLAYS'
    'Discord Optimization' = 'COMPANION APPS'
}
function Get-TweakPlace($t) {
    if ($script:InputMap.ContainsKey($t.Name)) { return @('INPUT', $script:InputMap[$t.Name]) }
    if ($t.Name -eq 'Disable PowerShell 7 Telemetry') { return @('GENERAL', 'DIAGNOSTICS & BACKGROUND') }
    switch -Wildcard ($t.Cat) {
        '1.*' { return @('GENERAL', 'CLEANUP & SHELL') }
        '2.*' { return @('GENERAL', 'PRIVACY') }
        '3.*' { return @('GENERAL', 'NOTIFICATIONS & SURFACES') }
        '4.*' { return @('GENERAL', 'DIAGNOSTICS & BACKGROUND') }
        '5.*' { return @('GENERAL', 'OPTIONAL WINDOWS FEATURES') }
        '11.*' { return @('GPU', 'POWER & PCIE') }
        '12.*' { if ($t.Risk -eq 'Expert') { return @('NETWORK', 'ADVANCED (EXPERT)') } else { return @('NETWORK', 'NETWORK TWEAKS') } }
        '13.*' { return @('GAMES', 'IN-GAME CONFIG') }
        '14.*' { return @('GAMES', 'NVIDIA & SYSTEM') }
        '15.*' { return @('GAMES', 'SESSION CLEANUP') }
    }
    return @('GENERAL', $t.Cat)
}
function Get-PageTweaks([string]$Key) {
    $out = New-Object System.Collections.ArrayList
    $all = foreach ($t in $script:Tweaks) { $pl = Get-TweakPlace $t; if ($pl[0] -eq $Key) { [pscustomobject]@{ Group = $pl[1]; T = $t } } }
    foreach ($g in $script:GroupOrder[$Key]) { foreach ($x in @($all | Where-Object { $_.Group -eq $g })) { [void]$out.Add($x) } }
    return @($out)
}

# ---------- Restore point / runner ----------
function Get-LastRestorePoint {
    try {
        $rp = Get-ComputerRestorePoint -ErrorAction Stop | Sort-Object SequenceNumber | Select-Object -Last 1
        if ($rp) { return ([Management.ManagementDateTimeConverter]::ToDateTime($rp.CreationTime)).ToString('g') }
    } catch {}
    return 'none found'
}
function New-RestorePoint {
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
        Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' 'SystemRestorePointCreationFrequency' 0 -NoBackup
        Checkpoint-Computer -Description 'Before FRENZY TWEAKS' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Log 'Restore point created'; $script:RPDone = $true; $script:LastRP = Get-LastRestorePoint
    } catch { Log "Restore point failed: $($_.Exception.Message)" 'WARN' }
    Update-Home
}
function Invoke-Run($ApplyList, $UndoList, [bool]$Confirm = $true) {
    if ($script:Busy) { return }
    $ApplyList = @($ApplyList); $UndoList = @($UndoList)
    $total = $ApplyList.Count + $UndoList.Count
    if ($total -eq 0) { [void][Fz.Msg]::Show('Nothing to change.', 'Optimizer'); return }
    $dry = $script:chkDry.Checked
    if (-not $dry -and $Confirm) {
        $names = @($ApplyList | ForEach-Object { '+ ' + $_.Name }) + @($UndoList | ForEach-Object { '- ' + $_.Name })
        $show = ($names | Select-Object -First 14) -join "`n"; if ($names.Count -gt 14) { $show += "`n... and $($names.Count - 14) more" }
        $nr = @($ApplyList | Where-Object { -not $_.Reversible }).Count
        $msg = "Apply these changes?`n`n$show"
        if ($nr -gt 0) { $msg += "`n`n$nr item(s) have no automatic undo." }
        if ([Fz.Msg]::Show($msg, 'Confirm', 'YesNo', 'Question') -ne 'Yes') { return }
    }
    if (-not $dry -and $ApplyList.Count -gt 0 -and $script:chkRP.Checked -and -not $script:RPDone) { New-RestorePoint }
    $script:Busy = $true; $script:RebootNeeded = $false; $script:Form.UseWaitCursor = $true
    $script:Progress.Maximum = [Math]::Max(1, $total); $script:Progress.Value = 0; $i = 0; $ok = 0; $fail = 0
    try {
        foreach ($pair in (@($ApplyList | ForEach-Object { @{ T = $_; M = 'Apply' } }) + @($UndoList | ForEach-Object { @{ T = $_; M = 'Undo' } }))) {
            $t = $pair.T; $i++; $script:Progress.Value = $i
            try {
                if ($dry) { Log "[DRY RUN] would $($pair.M.ToLower()): $($t.Name)"; continue }
                if ($pair.M -eq 'Apply') { Log ">> Applying: $($t.Name)"; & $t.Apply $t.Arg; $script:State["applied:$($t.Name)"] = $true }
                else { Log ">> Undoing: $($t.Name)"; & $t.Undo $t.Arg; $script:State.Remove("applied:$($t.Name)") }
                Save-State; $ok++
            } catch { $fail++; Log "FAILED $($t.Name): $($_.Exception.Message)" 'ERROR' }
            [Windows.Forms.Application]::DoEvents()
        }
    } finally { $script:Busy = $false; $script:Form.UseWaitCursor = $false }
    Log "Done. Succeeded: $ok  Failed: $fail"
    Refresh-AllRows; Update-Home
    if (-not $dry) {
        $m = 'Finished. A restart is recommended for all changes to take effect.'
        if ($script:RebootNeeded) { $m = 'Finished. A RESTART IS REQUIRED for some changes (features / GPU scheduling / svchost).' }
        if ($fail -gt 0) { $m += "`n`n$fail item(s) failed - see the log." }
        [void][Fz.Msg]::Show($m, 'Done')
    }
}



# ---------- Picker dialog (glowing tick-tiles) ----------
function New-PickHeader($D, [string]$Group) {
    $p = New-Object Windows.Forms.Panel; $p.Name = 'full'; $p.Height = 38; $p.Width = 900; $p.BackColor = $script:Clr.Bg; $p.Margin = New-Object Windows.Forms.Padding(0, 10, 12, 2)
    $l = New-Lbl "$BAR $Group" 0 8 640 24 $script:Fnt.Mid $D.Accent; $l.BackColor = $script:Clr.Bg
    $c = New-Lbl '' 0 11 140 18 $script:Fnt.Tiny $script:Clr.Dim; $c.TextAlign = 'MiddleRight'; $c.BackColor = $script:Clr.Bg
    $p.Controls.Add($l); $p.Controls.Add($c)
    $h = [pscustomobject]@{ Name = $Group; Panel = $p; Cnt = $c; Lbl = $l }
    if ($D.Checks) {
        $bA = New-Btn 'ALL' 46 24 $false $D.Accent; $bA.Radius = 7; $bA.Tag = @{ D = $D; G = $Group; V = $true }
        $bN = New-Btn 'NONE' 54 24 $false $D.Accent; $bN.Radius = 7; $bN.Tag = @{ D = $D; G = $Group; V = $false }
        foreach ($b in $bA, $bN) { $b.Top = 7; $b.Add_Click({ $x = $this.Tag; Set-PickGroup $x.D $x.G $x.V }) }
        $p.Controls.Add($bA); $p.Controls.Add($bN)
        $p.Tag = @{ A = $bA; N = $bN }
        $p.Add_Resize({ $t = $this.Tag; $t.N.Left = $this.Width - 60; $t.A.Left = $this.Width - 112; $this.Controls[1].Left = $this.Width - 270 })
    } else { $p.Add_Resize({ $this.Controls[1].Left = $this.Width - 150 }) }
    $p.Width = 901
    $D.Flow.Controls.Add($p)
    return $h
}
function Add-PickItem($D, [string]$Group, [string]$Title, [string]$Sub, [string]$Status, $StatusColor, [bool]$Checked, $Tag, [bool]$Locked = $false) {
    $h = @($D.Hdrs | Where-Object { $_.Name -eq $Group }) | Select-Object -First 1
    if (-not $h) { $h = New-PickHeader $D $Group; [void]$D.Hdrs.Add($h) }
    $c = New-Object Fz.FzChip; $c.Name = 'half'; $c.Text = $Title; $c.Sub = $Sub; $c.Status = $Status
    $c.StatusColor = $(if ($StatusColor) { $StatusColor } else { $script:Clr.Dim }); $c.Accent = $D.Accent; $c.ShowCheck = $D.Checks; $c.Locked = $Locked; $c.Group = $Group
    $c.Margin = New-Object Windows.Forms.Padding(0, 0, 12, 8); $c.Height = 58; $c.Width = 420
    if ($Locked) { $c.Cursor = [Windows.Forms.Cursors]::Default }
    $w = [pscustomobject]@{ Chip = $c; Group = $Group; Title = $Title; Sub = $Sub; Tag = $Tag; Vis = $true; Locked = $Locked }
    if ($Checked -and -not $Locked) { $c.Checked = $true }
    $c.Add_CheckedChanged({ $d = $this.FindForm().Tag; if ($d -and -not $d.Loading) { Update-Pick $d } })
    if ($Sub) { $script:Tip.SetToolTip($c, "$Title`n$Sub") }
    $D.Flow.Controls.Add($c); [void]$D.Items.Add($w)
    return $w
}
function Get-PickChecked($D) { return @($D.Items | Where-Object { $_.Chip.Checked -and -not $_.Locked }) }
function Update-Pick($D) {
    $sel = @(Get-PickChecked $D)
    if ($D.Checks) { $D.CountLbl.Text = ("{0} selected" -f $sel.Count) } else { $D.CountLbl.Text = ("{0} items" -f $D.Items.Count) }
    foreach ($h in $D.Hdrs) {
        $g = @($D.Items | Where-Object { $_.Group -eq $h.Name }); $n = @($g | Where-Object { $_.Chip.Checked }).Count
        if ($D.Checks) { $h.Cnt.Text = "$n / $($g.Count) selected" } else { $h.Cnt.Text = "$($g.Count) items" }
    }
    if ($D.OnChange) { & $D.OnChange $D }
}
function Set-PickChecks($D, [scriptblock]$Pred) {
    $D.Loading = $true
    try { foreach ($i in $D.Items) { if (-not $i.Locked) { $i.Chip.Checked = [bool](& $Pred $i) } } } finally { $D.Loading = $false }
    Update-Pick $D
}
function Set-PickGroup($D, [string]$Group, [bool]$Val) {
    $D.Loading = $true
    try { foreach ($i in $D.Items) { if ($i.Group -eq $Group -and $i.Vis -and -not $i.Locked) { $i.Chip.Checked = $Val } } } finally { $D.Loading = $false }
    Update-Pick $D
}
function Filter-Pick($D, [string]$Query) {
    $q = $Query.Trim().ToLower(); $D.Flow.SuspendLayout()
    foreach ($i in $D.Items) {
        $i.Vis = ($q -eq '') -or $i.Title.ToLower().Contains($q) -or ([string]$i.Sub).ToLower().Contains($q) -or ([string]$i.Group).ToLower().Contains($q)
        $i.Chip.Visible = $i.Vis
    }
    foreach ($h in $D.Hdrs) { $h.Panel.Visible = (@($D.Items | Where-Object { $_.Group -eq $h.Name -and $_.Vis }).Count -gt 0) }
    $D.Flow.ResumeLayout($true)
}
function Reload-Pick($D) {
    $D.Loading = $true
    try {
        $D.Flow.SuspendLayout()
        foreach ($c in @($D.Flow.Controls)) { $c.Dispose() }
        $D.Flow.Controls.Clear(); $D.Items.Clear(); $D.Hdrs.Clear()
        & $D.Populate $D
    } finally { $D.Flow.ResumeLayout($true); $D.Loading = $false }
    Fit-Flow $D.Flow
    if ($D.SearchBox -and $D.SearchBox.Text) { Filter-Pick $D $D.SearchBox.Text }
    Update-Pick $D
}
function Show-Picker {
    param([string]$Title, [string]$Sub, $Accent, [bool]$Checks, [scriptblock]$Populate, $Actions, [scriptblock]$OnChange = $null, [string]$Icon = 'sliders')
    $f = New-Object Windows.Forms.Form
    $f.Text = "FRENZY TWEAKS - $Title"; $f.StartPosition = 'CenterParent'; $f.ShowIcon = $false; $f.MinimizeBox = $false
    $f.BackColor = $script:Clr.Bg; $f.ForeColor = $script:Clr.Text; $f.Font = $script:Fnt.Norm
    $wa = [Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $f.Size = New-Object Drawing.Size([math]::Min(1120, $wa.Width - 60), [math]::Min(820, $wa.Height - 60)); $f.MinimumSize = New-Object Drawing.Size(860, 560)
    $D = @{ Form = $f; Items = (New-Object Collections.ArrayList); Hdrs = (New-Object Collections.ArrayList); Checks = $Checks; Accent = $Accent
        OnChange = $OnChange; Loading = $false; Populate = $Populate; Flow = $null; CountLbl = $null; SearchBox = $null }
    $f.Tag = $D
    $hd = New-Object Fz.FzHeader; $hd.Dock = 'Top'; $hd.Height = 158; $hd.Accent = $Accent
    $ic = New-Object Fz.FzCard; $ic.Size = New-Object Drawing.Size(52, 52); $ic.Location = New-Object Drawing.Point(26, 22); $ic.Icon = $Icon; $ic.IconSize = 28; $ic.IconX = 12; $ic.IconY = 12; $ic.Accent = $Accent; $ic.Glow = $true; $ic.Hover = $false
    $hd.Controls.Add($ic)
    $hd.Controls.Add((New-Lbl ($Title.ToUpper()) 92 20 800 40 $script:Fnt.Title $script:Clr.Text))
    $sl = New-Lbl $Sub 94 62 ($f.ClientSize.Width - 130) 36 $script:Fnt.Small $script:Clr.Dim; $hd.Controls.Add($sl)
    $sb = New-Object Fz.FzCard; $sb.Size = New-Object Drawing.Size(360, 38); $sb.Location = New-Object Drawing.Point(28, 108); $sb.Icon = 'search'; $sb.Accent = $Accent; $sb.Radius = 10
    $tb = New-Object Windows.Forms.TextBox; $tb.BorderStyle = 'None'; $tb.BackColor = $script:Clr.Card; $tb.ForeColor = $script:Clr.Text; $tb.Font = $script:Fnt.Norm
    $tb.Location = New-Object Drawing.Point(42, 10); $tb.Width = 302
    $tb.Add_TextChanged({ $d = $this.FindForm().Tag; Filter-Pick $d $this.Text })
    $sb.Controls.Add($tb); $hd.Controls.Add($sb); $D.SearchBox = $tb
    $flow = New-Object Fz.FzFlow; $flow.Dock = 'Fill'; $flow.FlowDirection = 'LeftToRight'; $flow.WrapContents = $true; $flow.AutoScroll = $true
    $flow.BackColor = $script:Clr.Bg; $flow.Padding = New-Object Windows.Forms.Padding(26, 6, 14, 10)
    $flow.Add_Resize({ Fit-Flow $this }); $D.Flow = $flow
    $bar = New-Object Windows.Forms.Panel; $bar.Dock = 'Bottom'; $bar.Height = 70; $bar.BackColor = $script:Clr.Side
    $cl = New-Lbl '' 28 24 360 24 $script:Fnt.MonoB $Accent; $bar.Controls.Add($cl); $D.CountLbl = $cl
    $bp = New-Object Windows.Forms.FlowLayoutPanel; $bp.Dock = 'Right'; $bp.FlowDirection = 'RightToLeft'; $bp.WrapContents = $false; $bp.AutoSize = $true
    $bp.Padding = New-Object Windows.Forms.Padding(8, 15, 20, 0); $bp.BackColor = $script:Clr.Side
    foreach ($a in $Actions) {
        $w = $(if ($a.W) { [int]$a.W } else { 170 })
        $b = New-Btn $a.T $w 40 ([bool]$a.Primary) $Accent; $b.Margin = New-Object Windows.Forms.Padding(8, 0, 0, 0); $b.Tag = @{ Fn = $a.Fn; D = $D }
        $b.Add_Click({ $x = $this.Tag; & $x.Fn $x.D }); $bp.Controls.Add($b)
    }
    $bar.Controls.Add($bp)
    $load = New-Lbl 'Scanning your system...' 0 0 400 30 $script:Fnt.Mid $script:Clr.Dim; $load.TextAlign = 'MiddleCenter'; $load.Dock = 'Top'; $load.Height = 80
    $f.Controls.Add($flow); $f.Controls.Add($bar); $f.Controls.Add($hd); $flow.BringToFront()
    $D.Loader = $load
    $f.Add_Shown({
            $d = $this.Tag; [Fz.Native]::DarkTitle($this.Handle); $this.Activate()
            $this.UseWaitCursor = $true; Pump
            try { Reload-Pick $d } catch { Log "Dialog load failed: $($_.Exception.Message)" 'ERROR' } finally { $this.UseWaitCursor = $false }
        })
    [void]$f.ShowDialog($script:Form); $f.Dispose()
}

# ---------- Disk cleanup ----------
# ---------- Disk cleanup ----------
$script:CleanItems = @(
    @{ Label = 'Local AppData Temp'; Path = "$env:LOCALAPPDATA\Temp"; Group = 'Temporary files'; Desc = 'Per-user temp files. Files in use are skipped.'; Review = $false; Def = $true }
    @{ Label = 'Windows Temp Files'; Path = "$env:WINDIR\Temp"; Group = 'Temporary files'; Desc = 'Operating-system temp files. Files in use are skipped.'; Review = $false; Def = $true }
    @{ Label = 'Thumbnail Cache'; Path = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"; Filter = 'thumbcache*.db'; Recurse = $false; Group = 'Caches'; Desc = 'Windows rebuilds thumbnails as you browse.'; Review = $false; Def = $true }
    @{ Label = 'IE / Edge Internet Cache'; Path = "$env:LOCALAPPDATA\Microsoft\Windows\INetCache"; Group = 'Caches'; Desc = 'Legacy internet cache. Modern Edge profiles are not touched.'; Review = $false; Def = $true }
    @{ Label = 'Delivery Optimization Files'; Path = "$env:WINDIR\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache"; Group = 'Caches'; Desc = 'Cached update delivery files; Windows can download them again.'; Review = $false; Def = $true }
    @{ Label = 'Downloaded Program Files'; Path = "$env:WINDIR\Downloaded Program Files"; Group = 'Caches'; Desc = 'Old ActiveX/Java components Windows no longer needs.'; Review = $false; Def = $true }
    @{ Label = 'Windows Error Reporting'; Path = "$env:PROGRAMDATA\Microsoft\Windows\WER"; Group = 'Logs and reports'; Desc = 'Archived crash reports (does not change diagnostics settings).'; Review = $false; Def = $true }
    @{ Label = 'Windows Upgrade Log Files'; Path = "$env:WINDIR\Panther"; Group = 'Logs and reports'; Desc = 'Keep them if you are troubleshooting an update.'; Review = $true; Def = $false }
    @{ Label = 'System Error Minidumps'; Path = "$env:WINDIR\Minidump"; Group = 'Logs and reports'; Desc = 'Small crash dumps used for troubleshooting.'; Review = $true; Def = $false }
    @{ Label = 'DirectX Shader Cache'; Path = "$env:LOCALAPPDATA\D3DSCache"; Group = 'Games (causes stutter until rebuilt)'; Desc = 'Games STUTTER while shaders are recreated. Only clear after a driver change.'; Review = $true; Def = $false }
    @{ Label = 'NVIDIA shader cache'; Path = "$env:LOCALAPPDATA\NVIDIA\DXCache"; Group = 'Games (causes stutter until rebuilt)'; Desc = 'Driver shader cache; stutter until rebuilt.'; Review = $true; Def = $false }
    @{ Label = 'Prefetch Cache'; Path = "$env:WINDIR\Prefetch"; Group = 'Review before deleting'; Desc = 'Windows rebuilds this launch cache; next app launches can be slower.'; Review = $true; Def = $false }
    @{ Label = 'Windows Web Cache'; Path = "$env:LOCALAPPDATA\Microsoft\Windows\WebCache"; Group = 'Review before deleting'; Desc = 'Some Microsoft apps may sign in again.'; Review = $true; Def = $false }
    @{ Label = 'Windows Cookies (Legacy)'; Path = "$env:LOCALAPPDATA\Microsoft\Windows\INetCookies"; Group = 'Review before deleting'; Desc = 'Sites may sign you out.'; Review = $true; Def = $false }
    @{ Label = 'Recent Documents (Legacy)'; Path = "$env:APPDATA\Microsoft\Windows\Recent"; Group = 'Review before deleting'; Desc = 'Removes shortcut history only; your documents are not deleted.'; Review = $true; Def = $false }
    @{ Label = 'Printer Spool Queue'; Path = "$env:WINDIR\System32\spool\PRINTERS"; Group = 'Review before deleting'; Desc = 'Cancels queued print jobs.'; Review = $true; Def = $false }
    @{ Label = 'Windows History (Legacy)'; Path = "$env:LOCALAPPDATA\Microsoft\Windows\History"; Group = 'Review before deleting'; Desc = 'Legacy browsing-history folder. Removes old history entries only.'; Review = $true; Def = $false }
    @{ Label = 'Windows Installer Patch Cache'; Path = "$env:WINDIR\Installer\`$PatchCache`$"; Special = 'Protected'; Group = 'Review before deleting'; Desc = 'Cached patch files. Deleting can break repair/uninstall/update of some older programs. Only use if you need the space.'; Review = $true; Def = $false }
    @{ Label = 'Recycle Bin'; Special = 'Recycle'; Group = 'Review before deleting'; Desc = 'Permanently deletes everything currently in the Recycle Bin.'; Review = $true; Def = $false }
    @{ Label = 'Previous Windows Installation'; Path = "$env:SystemDrive\Windows.old"; Special = 'Protected'; Group = 'Review before deleting'; Desc = 'You will no longer be able to roll back to the previous Windows.'; Review = $true; Def = $false }
    @{ Label = 'Temporary Windows Installation Files'; Path = "$env:SystemDrive\`$WINDOWS.~BT"; Special = 'Protected'; Group = 'Review before deleting'; Desc = 'Leftover setup files after an upgrade.'; Review = $true; Def = $false }
)
# 'Windows TMP Folder' = the %TMP% location; added only when it is not the same folder as Local AppData Temp
if ($env:TMP -and ($env:TMP.TrimEnd('\') -ne "$env:LOCALAPPDATA\Temp") -and ($env:TMP.TrimEnd('\') -ne "$env:WINDIR\Temp")) {
    $script:CleanItems += @{ Label = 'Windows TMP Folder'; Path = $env:TMP; Group = 'Temporary files'; Desc = 'The folder your TMP variable points to. Files in use are skipped.'; Review = $false; Def = $true }
}
function Measure-CleanItem($ci) {
    $r = @{ Count = 0; Bytes = [int64]0; Missing = $false }
    if ($ci.Special -eq 'Recycle') {
        foreach ($d in (Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction SilentlyContinue)) {
            $p = "$($d.DeviceID)\`$Recycle.Bin"
            $fs = @(Get-ChildItem -LiteralPath $p -Force -File -Recurse -ErrorAction SilentlyContinue)
            $r.Count += $fs.Count; $r.Bytes += [int64](($fs | Measure-Object Length -Sum).Sum)
        }
        return $r
    }
    if (-not (Test-Path -LiteralPath $ci.Path)) { $r.Missing = $true; return $r }
    $flt = if ($ci.Filter) { $ci.Filter } else { '*' }; $rec = if ($null -eq $ci.Recurse) { $true } else { [bool]$ci.Recurse }
    $fs = @(Get-ChildItem -LiteralPath $ci.Path -Filter $flt -Force -File -Recurse:$rec -ErrorAction SilentlyContinue)
    $r.Count = $fs.Count; $r.Bytes = [int64](($fs | Measure-Object Length -Sum).Sum)
    return $r
}
function Remove-Protected([string]$Path) {
    & takeown.exe /F $Path /R /A /D Y 2>&1 | Out-Null
    & icacls.exe $Path /grant 'Administrators:F' /T /C /Q 2>&1 | Out-Null
    Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
    Log "Removed $Path"
}
function Show-DiskCleanup {
    $pop = { param($D)
        foreach ($ci in $script:CleanItems) {
            $m = Measure-CleanItem $ci
            $sz = if ($m.Missing) { 'NOT FOUND' } else { Format-Bytes $m.Bytes }
            $lab = if ($ci.Review) { $ci.Label + '  [review]' } else { $ci.Label }
            $col = if ($m.Missing) { $script:Clr.Dim } elseif ($ci.Review) { $script:Clr.Warn } else { $script:Clr.Good }
            [void](Add-PickItem $D $ci.Group $lab $ci.Desc $sz $col ([bool]($ci.Def -and -not $m.Missing)) @{ CI = $ci; M = $m } $m.Missing)
            Pump
        }
    }
    $onc = { param($D)
        $n = 0; $b = [int64]0
        foreach ($i in (Get-PickChecked $D)) { $n++; $b += [int64]$i.Tag.M.Bytes }
        $D.CountLbl.Text = "{0} selected  -  {1} to free" -f $n, (Format-Bytes $b)
    }
    $acts = @(
        @{ T = 'RUN CLEANUP'; Primary = $true; W = 180; Fn = { param($D)
                $sel = @(Get-PickChecked $D | ForEach-Object { $_.Tag.CI }); if ($sel.Count -eq 0) { return }
                if ([Fz.Msg]::Show("Delete files from $($sel.Count) location(s)?`nPersonal files are not included.", 'Confirm cleanup', 'YesNo', 'Warning') -ne 'Yes') { return }
                if ($script:chkDry.Checked) { foreach ($s in $sel) { Log "[DRY RUN] would clean $($s.Label)" }; return }
                $D.Form.UseWaitCursor = $true
                foreach ($s in $sel) {
                    try {
                        if ($s.Special -eq 'Recycle') { Clear-RecycleBin -Force -ErrorAction SilentlyContinue; Log 'Recycle Bin emptied' }
                        elseif ($s.Special -eq 'Protected') { if (Test-Path -LiteralPath $s.Path) { Remove-Protected $s.Path } }
                        else { $flt = if ($s.Filter) { $s.Filter } else { '*' }; Clear-Folder $s.Path $flt }
                    } catch { Log "Cleanup failed for $($s.Label): $($_.Exception.Message)" 'WARN' }
                    Pump
                }
                $D.Form.UseWaitCursor = $false; Reload-Pick $D } }
        @{ T = 'SELECT SAFE'; W = 140; Fn = { param($D) Set-PickChecks $D { param($i) $i.Tag.CI.Def -and -not $i.Tag.M.Missing } } }
        @{ T = 'SELECT ALL'; W = 130; Fn = { param($D) Set-PickChecks $D { param($i) -not $i.Tag.M.Missing } } }
        @{ T = 'CLEAR'; W = 100; Fn = { param($D) Set-PickChecks $D { param($i) $false } } }
    )
    Show-Picker 'Disk Cleanup' 'Remove temporary files and caches. Personal files are excluded. Items marked [review] have trade-offs.' $script:PageClr.DEBLOAT $true $pop $acts $onc 'trash'
}

# ---------- Optional apps ----------
$script:AppFriendly = @{
    'Microsoft.BingNews' = 'Microsoft News'; 'Microsoft.BingWeather' = 'Weather'; 'Microsoft.BingSearch' = 'Bing Search'; 'Microsoft.BingFinance' = 'Money'; 'Microsoft.BingSports' = 'Sports'
    'Microsoft.BingTranslator' = 'Translator'; 'Microsoft.BingTravel' = 'Travel'; 'Microsoft.BingFoodAndDrink' = 'Food & Drink'; 'Microsoft.BingHealthAndFitness' = 'Health & Fitness'
    'Microsoft.GetHelp' = 'Get Help'; 'Microsoft.Getstarted' = 'Tips'; 'Microsoft.Microsoft3DViewer' = '3D Viewer'; 'Microsoft.MicrosoftOfficeHub' = 'Microsoft 365 hub'
    'Microsoft.MicrosoftSolitaireCollection' = 'Solitaire Collection'; 'Microsoft.MixedReality.Portal' = 'Mixed Reality Portal'; 'Microsoft.People' = 'People'
    'Microsoft.SkypeApp' = 'Skype'; 'Microsoft.WindowsFeedbackHub' = 'Feedback Hub'; 'Microsoft.YourPhone' = 'Phone Link'; 'Microsoft.ZuneMusic' = 'Media Player'
    'Microsoft.ZuneVideo' = 'Movies & TV'; 'Clipchamp.Clipchamp' = 'Clipchamp'; 'MicrosoftTeams' = 'Microsoft Teams (personal)'; 'MSTeams' = 'Microsoft Teams'
    'Microsoft.Todos' = 'Microsoft To Do'; 'Microsoft.PowerAutomateDesktop' = 'Power Automate'; 'Microsoft.549981C3F5F10' = 'Cortana'; 'Microsoft.WindowsMaps' = 'Maps'
    'Microsoft.OutlookForWindows' = 'Outlook (new)'; 'Microsoft.Copilot' = 'Copilot'; 'Microsoft.MicrosoftJournal' = 'Journal'; 'Microsoft.Whiteboard' = 'Whiteboard'
    'Microsoft.Office.OneNote' = 'OneNote'; 'Microsoft.Wallet' = 'Wallet'; 'Microsoft.NetworkSpeedTest' = 'Network Speed Test'; 'Microsoft.Print3D' = 'Print 3D'
    'Microsoft.MSPaint' = 'Paint 3D'; 'Microsoft.OneConnect' = 'Mobile Plans'; 'Microsoft.Messaging' = 'Messaging'; 'Microsoft.WindowsCommunicationsApps' = 'Mail and Calendar'
    'Microsoft.DevHome' = 'Dev Home'; 'MicrosoftCorporationII.QuickAssist' = 'Quick Assist'; 'MicrosoftCorporationII.MicrosoftFamily' = 'Microsoft Family'
    'Microsoft.XboxApp' = 'Xbox (legacy)'; 'Microsoft.GamingApp' = 'Xbox app'; 'Microsoft.XboxGamingOverlay' = 'Xbox Game Bar'; 'Microsoft.XboxGameOverlay' = 'Xbox Game Overlay'
    'Microsoft.XboxIdentityProvider' = 'Xbox Identity Provider'; 'Microsoft.XboxSpeechToTextOverlay' = 'Xbox Speech To Text'; 'Microsoft.Xbox.TCUI' = 'Xbox Live UI'
    'Microsoft.MicrosoftStickyNotes' = 'Sticky Notes'; 'Microsoft.WindowsCalculator' = 'Calculator'; 'Microsoft.WindowsCamera' = 'Camera'; 'Microsoft.WindowsAlarms' = 'Alarms & Clock'
    'Microsoft.Windows.Photos' = 'Photos'; 'Microsoft.ScreenSketch' = 'Snipping Tool'; 'Microsoft.Paint' = 'Paint'; 'Microsoft.WindowsNotepad' = 'Notepad'
    'Microsoft.WindowsSoundRecorder' = 'Sound Recorder'; 'Microsoft.WindowsTerminal' = 'Windows Terminal'; 'SpotifyAB.SpotifyMusic' = 'Spotify'; 'Disney.37853FC22B2CE' = 'Disney+'
}
$script:AppBloat = @('Microsoft.BingNews', 'Microsoft.BingWeather', 'Microsoft.BingSearch', 'Microsoft.BingFinance', 'Microsoft.BingSports', 'Microsoft.BingTranslator', 'Microsoft.BingTravel',
    'Microsoft.BingFoodAndDrink', 'Microsoft.BingHealthAndFitness', 'Microsoft.GetHelp', 'Microsoft.Getstarted', 'Microsoft.Microsoft3DViewer', 'Microsoft.MicrosoftOfficeHub',
    'Microsoft.MicrosoftSolitaireCollection', 'Microsoft.MixedReality.Portal', 'Microsoft.People', 'Microsoft.SkypeApp', 'Microsoft.WindowsFeedbackHub', 'Microsoft.YourPhone',
    'Microsoft.ZuneMusic', 'Microsoft.ZuneVideo', 'Clipchamp.Clipchamp', 'MicrosoftTeams', 'MSTeams', 'Microsoft.Todos', 'Microsoft.PowerAutomateDesktop', 'Microsoft.549981C3F5F10',
    'Microsoft.WindowsMaps', 'Microsoft.OutlookForWindows', 'Microsoft.Wallet', 'Microsoft.NetworkSpeedTest', 'Microsoft.Print3D', 'Microsoft.MSPaint', 'Microsoft.OneConnect',
    'Microsoft.Messaging', 'Microsoft.MicrosoftJournal', 'Microsoft.Whiteboard', 'Microsoft.DevHome', 'Microsoft.Copilot')
# never listed: Store, runtimes/frameworks, shell, security, drivers and OEM control apps
$script:AppProtect = '^(Microsoft\.(WindowsStore|StorePurchaseApp|DesktopAppInstaller|SecHealthUI|VCLibs|NET\.|UI\.Xaml|WindowsAppRuntime|Services\.Store|DirectXRuntime|AAD\.|AccountsControl|LockApp|CredDialogHost|ECApp|Win32WebViewHost|MicrosoftEdge|Edge|WebpImageExtension|HEIFImageExtension|HEVCVideoExtension|VP9VideoExtensions|AV1VideoExtension|RawImageExtension|WebMediaExtensions|ApplicationCompatibilityEnhancements|AsyncTextService|BioEnrollment|CloudExperienceHost|PPIProjection|WidgetsPlatformRuntime|StartExperiencesApp)|Windows\.|windows\.|MicrosoftWindows\.|NVIDIA|Realtek|Intel|AppUp\.|AdvancedMicroDevices|AMD|Dolby|Waves|Nahimic|SteelSeries|Razer|ASUS|Acer|HPInc|DellInc|Dell|Lenovo|Alienware|Killer|Qualcomm|ELAN|Synaptics|MSI)'
function Get-AppCatalog {
    $pk = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue)
    if ($pk.Count -eq 0) { $pk = @(Get-AppxPackage -ErrorAction SilentlyContinue) }
    $seen = @{}; $out = New-Object System.Collections.ArrayList
    foreach ($p in ($pk | Sort-Object Name)) {
        $n = [string]$p.Name
        if ($seen.ContainsKey($n)) { continue }
        if ($p.IsFramework -or $p.NonRemovable -or $p.SignatureKind -eq 'System' -or $p.IsResourcePackage) { continue }
        if ($n -match $script:AppProtect) { continue }
        $seen[$n] = $true
        $fr = $script:AppFriendly[$n]
        if (-not $fr) { $fr = (($n -replace '^[^.]+\.', '') -replace '([a-z])([A-Z])', '$1 $2'); if (-not $fr) { $fr = $n } }
        if ($n -like 'Microsoft.Xbox*' -or $n -eq 'Microsoft.GamingApp') { $g = '3. Xbox and gaming  (can break Game Pass sign-in)'; $rec = $false }
        elseif ($script:AppBloat -contains $n) { $g = '1. Bloat and consumer apps  (recommended)'; $rec = $true }
        elseif ($n -match '^(king\.com|.*CandyCrush|Disney|Netflix|SpotifyAB|AmazonVideo|Facebook|Instagram|TikTok|LinkedIn|Twitter|Hulu|Pandora|PicsArt|Adobe|ByteDance|Duolingo|Flipboard|Roblox|McAfee|Norton|WhatsApp)') { $g = '2. Third-party promoted apps  (recommended)'; $rec = $true }
        elseif ($n -like 'Microsoft*' -or $n -like 'Windows*') { $g = '4. Microsoft apps  (useful - review first)'; $rec = $false }
        else { $g = '5. Other installed apps'; $rec = $false }
        [void]$out.Add(@{ Name = $n; Title = $fr; Group = $g; Rec = $rec; Version = [string]$p.Version })
    }
    return @($out | Sort-Object { $_.Group }, { $_.Title })
}
function Remove-AppxByName([string]$Name, $Prov) {
    $err = $null
    foreach ($p in @(Get-AppxPackage -AllUsers -Name $Name -ErrorAction SilentlyContinue)) {
        try { Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction Stop }
        catch { try { Remove-AppxPackage -Package $p.PackageFullName -ErrorAction Stop } catch { $err = $_.Exception.Message } }
    }
    foreach ($pp in @($Prov | Where-Object { $_.DisplayName -eq $Name })) {
        try { Remove-AppxProvisionedPackage -Online -PackageName $pp.PackageName -ErrorAction Stop | Out-Null } catch { if (-not $err) { $err = $_.Exception.Message } }
    }
    $left = @(Get-AppxPackage -AllUsers -Name $Name -ErrorAction SilentlyContinue)
    return @{ Name = $Name; Removed = ($left.Count -eq 0); Error = $err }
}
function Show-AppsDialog {
    $pop = { param($D)
        $cat = @(Get-AppCatalog)
        if ($cat.Count -eq 0) { [void](Add-PickItem $D 'Nothing found' 'No removable apps were detected' 'Windows did not return any removable app packages for this account.' '' $script:Clr.Dim $false $null $true); return }
        foreach ($a in $cat) {
            [void](Add-PickItem $D $a.Group $a.Title ("{0}   v{1}" -f $a.Name, $a.Version) 'INSTALLED' $script:Clr.Good $false @{ Name = $a.Name; Rec = $a.Rec })
        }
    }
    $acts = @(
        @{ T = 'REMOVE SELECTED'; Primary = $true; W = 200; Fn = { param($D)
                $sel = @(Get-PickChecked $D); if ($sel.Count -eq 0) { [void][Fz.Msg]::Show('Tick at least one app first.', 'Nothing selected'); return }
                $names = @($sel | ForEach-Object { $_.Tag.Name })
                if ([Fz.Msg]::Show("Uninstall these $($names.Count) app(s)?`n`n" + (($sel | ForEach-Object { $_.Title }) -join "`n") + "`n`nYou can reinstall them from the Microsoft Store.", 'Confirm removal', 'YesNo', 'Warning') -ne 'Yes') { return }
                if ($script:chkDry.Checked) { foreach ($n in $names) { Log "[DRY RUN] would remove app $n" }; return }
                if ($script:chkRP.Checked -and -not $script:RPDone) { New-RestorePoint }
                $D.Form.UseWaitCursor = $true; $ok = 0; $bad = New-Object System.Collections.ArrayList; $i = 0
                $prov = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue)
                foreach ($n in $names) {
                    $i++; $D.CountLbl.Text = "Removing $i / $($names.Count): $n"; Pump
                    $r = Remove-AppxByName $n $prov
                    if ($r.Removed) { $ok++; Log "Removed app $n" } else { [void]$bad.Add($n); Log "Could not remove $n : $($r.Error)" 'WARN' }
                    Pump
                }
                $D.Form.UseWaitCursor = $false
                $m = "Removed $ok of $($names.Count) app(s)."
                if ($bad.Count -gt 0) { $m += "`n`nWindows refused to remove:`n" + ($bad -join "`n") + "`n`n(Protected by the system or in use. See the log.)" }
                [void][Fz.Msg]::Show($m, 'Optional apps', 'OK', $(if ($bad.Count -gt 0) { 'Warning' } else { 'Information' }))
                Reload-Pick $D } }
        @{ T = 'SELECT RECOMMENDED'; W = 210; Fn = { param($D) Set-PickChecks $D { param($i) $i.Tag -and $i.Tag.Rec } } }
        @{ T = 'SELECT ALL'; W = 130; Fn = { param($D) Set-PickChecks $D { param($i) [bool]$i.Tag } } }
        @{ T = 'CLEAR'; W = 100; Fn = { param($D) Set-PickChecks $D { param($i) $false } } }
    )
    Show-Picker 'Optional Apps' 'Tick the apps you want to removed. Store, runtimes, drivers, OEM control apps (NVIDIA, MSI, Realtek...) and system components are never listed. You confirm before anything is removed.' $script:PageClr.DEBLOAT $true $pop $acts $null 'apps'
}

# ---------- Services ----------
# ---------- Services ----------
$script:SvcGroups = @(
    @{ G = 'System maintenance'; S = @(@{ N = 'QWAVE'; D = 'Quality Windows Audio/Video Experience (streaming QoS)'; R = $true }) }
    @{ G = 'Remote Desktop & VPN'; S = @(@{ N = 'RasMan'; D = 'Remote Access Connection Manager - breaks built-in VPN'; R = $false }) }
    @{ G = 'Notifications'; S = @(@{ N = 'WpnService'; D = 'Windows Push Notifications System Service'; R = $true }, @{ N = 'WpnUserService'; D = 'Push notifications user service'; R = $true }) }
    @{ G = 'Network discovery'; S = @(@{ N = 'lmhosts'; D = 'TCP/IP NetBIOS Helper'; R = $false }, @{ N = 'iphlpsvc'; D = 'IP Helper (IPv6 transition) - can affect some ISPs'; R = $false }) }
    @{ G = 'Cloud & account sync'; S = @(@{ N = 'CDPSvc'; D = 'Connected Devices Platform Service'; R = $true }) }
    @{ G = 'Web proxy'; S = @(@{ N = 'WinHttpAutoProxySvc'; D = 'WinHTTP Web Proxy Auto-Discovery - may break proxy/VPN setups'; R = $false }) }
    @{ G = 'Local discovery / UPnP'; S = @(@{ N = 'FDResPub'; D = 'Function Discovery Resource Publication'; R = $false }, @{ N = 'fdPHost'; D = 'Function Discovery Provider Host'; R = $false }, @{ N = 'SSDPSRV'; D = 'SSDP Discovery'; R = $false }, @{ N = 'upnphost'; D = 'UPnP Device Host'; R = $false }) }
    @{ G = 'Sensors & display (protected on laptops)'; Guarded = $true; S = @(@{ N = 'SensrSvc'; D = 'Sensor Monitoring Service'; R = $false }, @{ N = 'SensorService'; D = 'Sensor Service'; R = $false }, @{ N = 'SensorDataService'; D = 'Sensor Data Service'; R = $false }, @{ N = 'WbioSrvc'; D = 'Windows Biometric Service (Hello)'; R = $false }, @{ N = 'DisplayEnhancementService'; D = 'Display Enhancement (auto-brightness/HDR)'; R = $false }) }
)
function Get-StartName($n) { switch ([int]$n) { 0 { 'Boot' } 1 { 'System' } 2 { 'Auto' } 3 { 'Manual' } 4 { 'Disabled' } default { "$n" } } }
function Show-ServicesDialog {
    $pop = { param($D)
        foreach ($g in $script:SvcGroups) {
            foreach ($s in $g.S) {
                $key = "HKLM:\SYSTEM\CurrentControlSet\Services\$($s.N)"; if (-not (Test-Path $key)) { continue }
                $cur = [int](Get-ItemProperty $key).Start; $sk = "svc:$($s.N)"
                $guard = ($g.Guarded -and $script:Guard); $lock = $false
                if ($script:State.ContainsKey($sk)) {
                    $o = $script:State[$sk]; $st = 'RESTORABLE'; $det = "Disabled by this tool. Original startup: $(Get-StartName $o.Start). $($s.D)"; $col = $script:Clr.Good
                } elseif ($guard) { $st = 'PROTECTED'; $det = 'Laptop Guard preserves sensor, biometric and display support.'; $col = $script:Clr.Dim; $lock = $true }
                elseif ($cur -eq 4) { $st = 'DISABLED'; $det = 'Already disabled (not by this tool).'; $col = $script:Clr.Dim; $lock = $true }
                else { $st = 'ENABLED'; $det = "$($s.D)   [startup: $(Get-StartName $cur)]"; $col = $script:Clr.Warn }
                [void](Add-PickItem $D $g.G $s.N $det $st $col $false @{ N = $s.N; R = $s.R; Guard = $guard; Saved = $script:State.ContainsKey($sk); Cur = $cur } $lock)
            }
        }
    }
    $acts = @(
        @{ T = 'DISABLE SELECTED'; Primary = $true; W = 190; Fn = { param($D)
                $sel = @(Get-PickChecked $D | Where-Object { -not $_.Tag.Guard -and -not $_.Tag.Saved -and $_.Tag.Cur -ne 4 }); if ($sel.Count -eq 0) { return }
                if ([Fz.Msg]::Show("Disable $($sel.Count) service(s)? Original startup modes are saved so you can re-enable them.", 'Confirm', 'YesNo', 'Question') -ne 'Yes') { return }
                foreach ($it in $sel) { if ($script:chkDry.Checked) { Log "[DRY RUN] would disable $($it.Tag.N)" } else { try { Disable-Svc $it.Tag.N } catch { Log "Failed $($it.Tag.N): $($_.Exception.Message)" 'WARN' } } ; Pump }
                Reload-Pick $D } }
        @{ T = 'RE-ENABLE'; W = 140; Fn = { param($D)
                $sel = @(Get-PickChecked $D | Where-Object { $_.Tag.Saved }); if ($sel.Count -eq 0) { return }
                foreach ($it in $sel) { if ($script:chkDry.Checked) { Log "[DRY RUN] would re-enable $($it.Tag.N)" } else { Enable-Svc $it.Tag.N } }
                Reload-Pick $D } }
        @{ T = 'SELECT RECOMMENDED'; W = 210; Fn = { param($D) Set-PickChecks $D { param($i) $i.Tag.R -and -not $i.Tag.Guard -and -not $i.Tag.Saved } } }
        @{ T = 'CLEAR'; W = 100; Fn = { param($D) Set-PickChecks $D { param($i) $false } } }
    )
    Show-Picker 'Services' 'Disable reviewed non-core Windows services. Every change records the original startup mode so it can be restored.' (New-Rgb 255 150 40) $true $pop $acts $null 'gear'
}

# ---------- Scheduled tasks ----------
# ---------- Scheduled tasks ----------
$script:TaskGroups = @(
    @{ G = 'Telemetry & diagnostics'; R = $true; T = @(
            @('Compatibility appraiser', '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser'), @('Program data updater', '\Microsoft\Windows\Application Experience\ProgramDataUpdater'),
            @('Startup app task', '\Microsoft\Windows\Application Experience\StartupAppTask'), @('Customer experience reporting', '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator'),
            @('USB usage reporting', '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip'), @('Disk diagnostics collector', '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector'),
            @('Feedback client', '\Microsoft\Windows\Feedback\Siuf\DmClient'), @('Feedback client (scenario)', '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload'),
            @('Queued error reporting', '\Microsoft\Windows\Windows Error Reporting\QueueReporting'), @('Disk footprint diagnostics', '\Microsoft\Windows\DiskFootprint\Diagnostics'),
            @('Memory diagnostic events', '\Microsoft\Windows\MemoryDiagnostic\ProcessMemoryDiagnosticEvents'), @('Power efficiency analysis', '\Microsoft\Windows\Power Efficiency Diagnostics\AnalyzeSystem'),
            @('Recommended troubleshooting scan', '\Microsoft\Windows\Diagnosis\RecommendedTroubleshootingScanner')) }
    @{ G = 'Background maintenance'; R = $true; T = @(
            @('Automatic disk cleanup', '\Microsoft\Windows\DiskCleanup\SilentCleanup'), @('Scheduled drive optimization', '\Microsoft\Windows\Defrag\ScheduledDefrag'),
            @('Storage Sense', '\Microsoft\Windows\DiskFootprint\StorageSense'), @('Windows performance assessment', '\Microsoft\Windows\Maintenance\WinSAT'),
            @('Remote Assistance maintenance', '\Microsoft\Windows\RemoteAssistance\RemoteAssistanceTask'), @('Speech model downloads', '\Microsoft\Windows\Speech\SpeechModelDownloadTask')) }
    @{ G = 'Cloud & sync'; R = $true; T = @(
            @('App list backup', '\Microsoft\Windows\AppListBackup\Backup'), @('Cloud experience setup', '\Microsoft\Windows\CloudExperienceHost\CreateObjectTask'),
            @('Mouse settings sync', '\Microsoft\Windows\Input\MouseSyncDataAvailable'), @('Touchpad settings sync', '\Microsoft\Windows\Input\TouchpadSyncDataAvailable'),
            @('Pen settings sync', '\Microsoft\Windows\Input\PenSyncDataAvailable'), @('Input settings sync', '\Microsoft\Windows\Input\LocalUserSyncDataAvailable'),
            @('Windows cloud restore backup', '\Microsoft\Windows\CloudRestore\Backup'), @('Offline maps update', '\Microsoft\Windows\Maps\MapsUpdateTask'), @('Offline maps notifications', '\Microsoft\Windows\Maps\MapsToastTask')) }
    @{ G = 'Windows features'; R = $false; T = @(@('Family Safety monitor', '\Microsoft\Windows\Shell\FamilySafetyMonitor'), @('Search index maintenance', '\Microsoft\Windows\Shell\IndexerAutomaticMaintenance')) }
    @{ G = 'Windows Update (security patches stop being fetched)'; R = $false; T = @(
            @('Update scan', '\Microsoft\Windows\UpdateOrchestrator\Schedule Scan'), @('Update work', '\Microsoft\Windows\UpdateOrchestrator\Schedule Work'),
            @('Update UX broker', '\Microsoft\Windows\UpdateOrchestrator\USO_UxBroker'), @('Windows Update scheduled start', '\Microsoft\Windows\WindowsUpdate\Scheduled Start'),
            @('Store update retry', '\Microsoft\Windows\InstallService\SmartRetry')) }
    @{ G = 'Xbox & gaming'; R = $false; T = @(, @('Xbox cloud-save maintenance', '\Microsoft\XblGameSave\XblGameSaveTask')) }
)
function Show-TasksDialog {
    $pop = { param($D)
        foreach ($g in $script:TaskGroups) {
            foreach ($t in $g.T) {
                $full = $t[1]; $i = $full.LastIndexOf('\')
                $x = Get-ScheduledTask -TaskPath $full.Substring(0, $i + 1) -TaskName $full.Substring($i + 1) -ErrorAction SilentlyContinue
                if (-not $x) { continue }
                $ours = $script:State.ContainsKey("task:$full"); $dis = ($x.State -eq 'Disabled'); $lock = $false
                if ($dis) { if ($ours) { $st = 'RESTORABLE'; $col = $script:Clr.Good } else { $st = 'DISABLED'; $col = $script:Clr.Dim; $lock = $true } }
                else { $st = 'ENABLED'; $col = $script:Clr.Warn }
                [void](Add-PickItem $D $g.G $t[0] $full $st $col $false @{ Full = $full; R = $g.R; Ours = $ours; Disabled = $dis } $lock)
            }
        }
    }
    $acts = @(
        @{ T = 'DISABLE SELECTED'; Primary = $true; W = 200; Fn = { param($D)
                $sel = @(Get-PickChecked $D | Where-Object { -not $_.Tag.Disabled }); if ($sel.Count -eq 0) { return }
                if ([Fz.Msg]::Show("Disable $($sel.Count) scheduled task(s)? You can restore them from this window.", 'Confirm', 'YesNo', 'Question') -ne 'Yes') { return }
                foreach ($it in $sel) { if ($script:chkDry.Checked) { Log "[DRY RUN] would disable $($it.Tag.Full)" } else { Set-Task $it.Tag.Full $false }; Pump }
                Reload-Pick $D } }
        @{ T = 'RESTORE SELECTED'; W = 190; Fn = { param($D)
                $sel = @(Get-PickChecked $D | Where-Object { $_.Tag.Ours }); if ($sel.Count -eq 0) { return }
                foreach ($it in $sel) { if ($script:chkDry.Checked) { Log "[DRY RUN] would restore $($it.Tag.Full)" } else { Set-Task $it.Tag.Full $true } }
                Reload-Pick $D } }
        @{ T = 'SELECT RECOMMENDED'; W = 210; Fn = { param($D) Set-PickChecks $D { param($i) $i.Tag.R -and -not $i.Tag.Disabled } } }
        @{ T = 'CLEAR'; W = 100; Fn = { param($D) Set-PickChecks $D { param($i) $false } } }
    )
    Show-Picker 'Scheduled Tasks' 'Pause reviewed background jobs. Only changes made by this tool can be restored from here.' (New-Rgb 255 210 63) $true $pop $acts $null 'clock'
}

# ---------- System checkup ----------
function Show-Checkup {
    $pop = { param($D)
        $add = { param($level, $name, $text)
            $col = switch ($level) { 'OK' { $script:Clr.Good } 'WARN' { $script:Clr.Warn } 'BAD' { $script:Clr.Bad } default { $script:Clr.Dim } }
            [void](Add-PickItem $D 'System checkup' $name $text $level $col $false $null) }
        & $add 'OK' 'Administrator' 'Running elevated - registry, services and power changes can be applied.'
        & $add 'INFO' 'Device type' ("{0} - {1}.  Laptop Guard is {2}." -f $(if ($script:Sys.IsLaptop) { 'Laptop' } else { 'Desktop' }), $script:Sys.Model, $(if ($script:Guard) { 'ON' } else { 'OFF' }))
        & $add 'INFO' 'CPU' ("{0} ({1} cores / {2} threads)" -f $script:Sys.Cpu, $script:Sys.Cores, $script:Sys.Threads)
        & $add $(if ($script:Sys.RamGB -lt 16) { 'WARN' } else { 'OK' }) 'Memory' ("{0} GB installed{1}" -f $script:Sys.RamGB, $(if ($script:Sys.RamGB -lt 16) { ' - 16 GB+ recommended for Fortnite' } else { '' }))
        $g = Get-NvSmi
        & $add 'INFO' 'Graphics' (($script:Sys.Gpus -join '  +  ') + $(if ($g) { "   (NVIDIA driver $($g.Driver))" } else { '' }))
        if ($script:Sys.Gpus.Count -gt 1) { & $add 'INFO' 'Hybrid graphics' 'Use the "High-performance GPU preference" tweak on the Fortnite page.' }
        $pl = Get-ActivePlan
        & $add $(if ($pl.Name -match 'Balanced|saver') { 'WARN' } else { 'OK' }) 'Power plan' ("{0}{1}" -f $pl.Name, $(if ($pl.Name -match 'Balanced|saver') { ' - apply the performance power plan from Home' } else { '' }))
        if ($script:Sys.IsLaptop) {
            $b = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($b) { & $add $(if ($b.BatteryStatus -eq 2 -or $b.BatteryStatus -ge 6) { 'OK' } else { 'WARN' }) 'Power source' $(if ($b.BatteryStatus -eq 2 -or $b.BatteryStatus -ge 6) { "Plugged in ($($b.EstimatedChargeRemaining)% charge)" } else { "On battery ($($b.EstimatedChargeRemaining)%) - plug in for full performance" }) }
        }
        $gm = (Get-ItemProperty 'HKCU:\Software\Microsoft\GameBar' -ErrorAction SilentlyContinue).AutoGameModeEnabled
        & $add $(if ($gm -eq 0) { 'WARN' } else { 'OK' }) 'Game Mode' $(if ($gm -eq 0) { 'Off' } else { 'On' })
        $hs = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -ErrorAction SilentlyContinue).HwSchMode
        & $add 'INFO' 'Hardware GPU scheduling' $(if ($hs -eq 2) { 'On' } else { 'Off (test it - helps some systems)' })
        try { $sb = Confirm-SecureBootUEFI -ErrorAction Stop; & $add $(if ($sb) { 'OK' } else { 'WARN' }) 'Secure Boot' $(if ($sb) { 'Enabled' } else { 'Disabled - Fortnite may require Secure Boot' }) } catch { & $add 'INFO' 'Secure Boot' 'Unknown (legacy BIOS or not accessible)' }
        try { $tp = Get-Tpm -ErrorAction Stop; & $add $(if ($tp.TpmPresent) { 'OK' } else { 'WARN' }) 'TPM' $(if ($tp.TpmPresent) { 'Present' } else { 'Not present' }) } catch {}
        $sd = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'" -ErrorAction SilentlyContinue
        if ($sd) { $free = [math]::Round($sd.FreeSpace / 1GB, 0); & $add $(if ($free -lt 30) { 'WARN' } else { 'OK' }) 'System drive free space' "$free GB free" }
        $fn = Find-FortniteExe -Quiet
        & $add $(if ($fn) { 'OK' } else { 'WARN' }) 'Fortnite' $(if ($fn) { $fn } else { 'Not detected' })
        $pend = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
        & $add $(if ($pend) { 'WARN' } else { 'OK' }) 'Pending restart' $(if ($pend) { 'Windows is waiting for a restart' } else { 'None' })
    }
    Show-Picker 'System Checkup' 'Read-only scan of your hardware and the settings that matter for Fortnite. Nothing is changed.' $script:PageClr.HOME $false $pop @(@{ T = 'CLOSE'; Primary = $true; W = 120; Fn = { param($D) $D.Form.Close() } }) $null 'scan'
}

# ---------- Updates ----------
$script:RawBase = 'https://raw.githubusercontent.com/Kingmevinu25/FrenzyTweaksEXTREME/main'
$script:LastCheck = $null
$script:UpdateState = if ($global:FrenzySplash) { if ($global:FrenzySplash.UseCache) { 'OFFLINE COPY' } else { 'UP TO DATE' } } else { "v$($script:AppVersion)" }
function Check-ForUpdates {
    $script:Form.UseWaitCursor = $true; Pump
    $msg = ''; $icon = 'Information'
    try {
        $wc = New-Object Net.WebClient; $wc.Encoding = [Text.Encoding]::UTF8; $wc.Headers.Add('Cache-Control', 'no-cache')
        $txt = $wc.DownloadString("$($script:RawBase)/FrenzyApp.ps1?t=$([DateTime]::UtcNow.Ticks)")
        $m = [regex]::Match($txt, 'AppVersion = ''([0-9.]+)''')
        $script:LastCheck = (Get-Date).ToString('g')
        if ($m.Success -and ([version]$m.Groups[1].Value) -gt ([version]$script:AppVersion)) {
            $msg = "STATUS: UPDATE AVAILABLE`nInstalled: v$($script:AppVersion)`nLatest: v$($m.Groups[1].Value)`n`nClose FRENZY TWEAKS and run the install command again to get the new version."; $icon = 'Warning'; $script:UpdateState = 'UPDATE AVAILABLE'
        } else { $msg = "STATUS: CURRENT`nVersion: v$($script:AppVersion)`n`nThis build is already current.`nLast checked: $($script:LastCheck)"; $script:UpdateState = 'UP TO DATE' }
    } catch { $msg = "Could not reach GitHub.`n$($_.Exception.Message)"; $icon = 'Warning' }
    $script:Form.UseWaitCursor = $false
    if ($script:UpdBtn) { $script:UpdBtn.Text = $script:UpdateState; $script:UpdBtn.Accent = $(if ($script:UpdateState -eq 'UPDATE AVAILABLE') { $script:Clr.Warn } else { $script:Clr.Good }) }
    [void][Fz.Msg]::Show($msg, 'App updates', 'OK', $icon)
}

# ---------- Games / home helpers ----------
function Get-TweakByName([string]$Name) { return ($script:Tweaks | Where-Object { $_.Name -eq $Name } | Select-Object -First 1) }
function Get-RecommendedPending { return @($script:Rows | Where-Object { -not $_.OneShot -and $_.T.Default -and $_.T.Risk -ne 'Expert' -and -not $_.Active }) }
function Update-GameCard {
    $h = $script:H; if (-not $h) { return }
    $h.GameHost.Controls.Clear()
    $exe = Find-FortniteExe -Quiet; $pc = $script:PageClr.GAMES
    $card = New-Object Fz.FzCard; $card.Dock = 'Fill'; $card.Accent = $pc; $card.Stripe = $true; $card.Margin = New-Object Windows.Forms.Padding(0)
    $card.Controls.Add((New-Lbl 'FORTNITE' 22 12 300 24 $script:Fnt.Mid $script:Clr.Text))
    if ($exe) {
        $keys = @('Disable V-Sync', 'Low scalability preset', 'Uncap frame rate (FrameRateLimit=0)')
        $done = @($script:Rows | Where-Object { $keys -contains $_.T.Name -and $_.Active }).Count
        $status = if ($done -ge 2) { 'CONFIGURED' } else { 'READY' }; $col = if ($done -ge 2) { $script:Clr.Good } else { $script:Clr.Warn }
        $l1 = New-Lbl ("Epic Games   -   " + $exe) 22 40 700 18 $script:Fnt.Small $script:Clr.Dim; $l1.AutoEllipsis = $true; $card.Controls.Add($l1)
    } else {
        $card.Controls.Add((New-Lbl 'Not detected - launch Fortnite once, then press SCAN GAMES.' 22 40 700 18 $script:Fnt.Small $script:Clr.Warn))
        $status = 'NOT FOUND'; $col = $script:Clr.Bad
    }
    $pill = New-Object Fz.FzPill; $pill.Text = $status; $pill.Tint = $col; $pill.Location = New-Object Drawing.Point(150, 14); $pill.Fit(); $card.Controls.Add($pill)
    $open = New-Btn 'OPEN TWEAKS' 150 34 $true $pc 'arrow'; $open.Add_Click({ Show-Page 'GAMES' })
    $card.Add_Resize({ $b = $this.Controls | Where-Object { $_ -is [Fz.FzButton] } | Select-Object -First 1; if ($b) { $b.Left = $this.Width - 170 } })
    $open.Top = 24; $card.Controls.Add($open); $card.Width = 900; $card.Width = 901
    $h.GameHost.Controls.Add($card)
}
function Update-Home {
    $h = $script:H; if (-not $h) { return }
    $rows = @($script:Rows | Where-Object { -not $_.OneShot }); $act = @($rows | Where-Object { $_.Active }).Count
    $h.Count.Text = "$act OF $($rows.Count) TWEAKS ACTIVE"
    $rec = @(Get-RecommendedPending); $h.BtnRec.Text = "APPLY $($rec.Count) RECOMMENDATIONS"; $h.BtnRec.Enabled = ($rec.Count -gt 0)
    $h.LastRP.Text = 'LAST RESTORE POINT:   ' + $script:LastRP
    $p = Get-ActivePlan; $h.Plan.Text = $p.Name
}

# ---------- Home page ----------
function Build-Home {
    $p = New-PageShell 'HOME' 'HOME' 'Live system overview, one-click recommendations and rollback safety.' 108
    $flow = $script:Pages['HOME'].Flow; $script:H = @{}; $ac = $script:PageClr.HOME
    $hero = New-Object Fz.FzHero; $hero.Name = 'full'; $hero.Height = 176; $hero.Width = 900; $hero.Accent = $ac; $hero.Margin = New-Object Windows.Forms.Padding(0, 0, 12, 12)
    $hero.Controls.Add((New-Lbl "// SYSTEM ONLINE" 38 22 400 18 $script:Fnt.MonoB $ac))
    $hero.Controls.Add((New-Lbl 'FRENZY TWEAKS' 34 40 700 70 $script:Fnt.Hero $script:Clr.Text))
    $script:H.Count = New-Lbl '' 38 108 420 20 $script:Fnt.MonoB $ac; $hero.Controls.Add($script:H.Count)
    $chip = ("{0}   |   {1}   |   {2}   |   {3} GB RAM" -f $(if ($script:Sys.IsLaptop) { 'LAPTOP' } else { 'DESKTOP' }), $script:Sys.Cpu, $script:GpuShort, $script:Sys.RamGB)
    $cl = New-Lbl $chip 38 134 620 20 $script:Fnt.Small $script:Clr.Dim; $cl.AutoEllipsis = $true; $hero.Controls.Add($cl)
    $script:H.BtnRec = New-Btn 'APPLY RECOMMENDATIONS' 300 46 $true $ac 'bolt'; $script:H.BtnRec.Top = 38
    $script:H.BtnRec.Add_Click({ $r = @(Get-RecommendedPending); Invoke-Run @($r | ForEach-Object { $_.T }) @() })
    $bRp = New-Btn 'CREATE RESTORE POINT' 300 40 $false $ac 'shield'; $bRp.Top = 96; $bRp.Add_Click({ New-RestorePoint })
    $hero.Controls.Add($script:H.BtnRec); $hero.Controls.Add($bRp)
    $hero.Tag = @($script:H.BtnRec, $bRp); $hero.Add_Resize({ foreach ($b in $this.Tag) { $b.Left = $this.Width - 330 } }); $hero.Width = 901
    $flow.Controls.Add($hero)

    $flow.Controls.Add((New-Section 'LIVE TELEMETRY' $ac))
    $script:Tiles.cpu = New-Tile 'CPU' (New-Rgb 255 106 0); $script:Tiles.gpu = New-Tile 'GPU' (New-Rgb 74 222 128)
    $script:Tiles.mem = New-Tile 'MEMORY' (New-Rgb 77 141 255); $script:Tiles.net = New-Tile 'NETWORK' (New-Rgb 168 85 247)
    foreach ($k in 'cpu', 'gpu', 'mem', 'net') { $flow.Controls.Add($script:Tiles[$k].Panel) }

    $rb = New-Card 400 150 'half' (New-Rgb 255 61 139); $rb.Icon = 'shield'; $rb.IconSize = 22; $rb.IconX = 20; $rb.IconY = 18
    $rb.Controls.Add((New-Lbl 'ROLLBACK SAFETY' 54 16 300 22 $script:Fnt.Mid $script:Clr.Text))
    $rb.Controls.Add((New-Lbl 'Every registry value, service and task is backed up with its REAL original value before it is changed.' 22 50 440 36 $script:Fnt.Small $script:Clr.Dim))
    $script:H.LastRP = New-Lbl '' 22 92 440 18 $script:Fnt.MonoB (New-Rgb 255 61 139); $rb.Controls.Add($script:H.LastRP)
    $bsr = New-Btn 'OPEN SYSTEM RESTORE' 200 34 $false (New-Rgb 255 61 139) 'undo'; $bsr.Location = New-Object Drawing.Point(22, 108); $bsr.Add_Click({ Start-Process rstrui.exe }); $rb.Controls.Add($bsr)
    $flow.Controls.Add($rb)
    $so = New-Card 400 150 'half' (New-Rgb 77 141 255)
    $so.Controls.Add((New-Lbl 'SYSTEM OVERVIEW' 22 14 300 22 $script:Fnt.Mid $script:Clr.Text))
    $rowsInfo = @(@('DEVICE', $(if ($script:Sys.IsLaptop) { 'Laptop' } else { 'Desktop' }) + ' - ' + $script:Sys.Model), @('CPU', $script:Sys.Cpu), @('GPU', $script:GpuShort), @('MEMORY', "$($script:Sys.RamGB) GB"))
    $yy = 44; foreach ($ri in $rowsInfo) { $so.Controls.Add((New-Lbl $ri[0] 22 $yy 80 16 $script:Fnt.Tiny $script:Clr.Dim)); $v = New-Lbl $ri[1] 100 ($yy - 2) 330 18 $script:Fnt.Small; $v.AutoEllipsis = $true; $so.Controls.Add($v); $yy += 22 }
    $so.Controls.Add((New-Lbl 'POWER PLAN' 22 $yy 80 16 $script:Fnt.Tiny $script:Clr.Dim))
    $script:H.Plan = New-Lbl '' 100 ($yy - 2) 330 18 $script:Fnt.Small (New-Rgb 77 141 255); $so.Controls.Add($script:H.Plan)
    $flow.Controls.Add($so)

    $flow.Controls.Add((New-Section 'QUICK ACTIONS' $ac))
    $qa = New-Card 900 150 'full' $ac
    $chkG = New-Object Fz.FzToggle; $chkG.OnColor = $ac; $chkG.Location = New-Object Drawing.Point(22, 18); $chkG.Checked = $script:Guard
    $chkG.Add_CheckedChanged({ $script:Guard = $this.Checked; if ($script:DevLbl) { $script:DevLbl.Text = ('{0}   Guard {1}' -f $(if ($script:Sys.IsLaptop) { 'LAPTOP' } else { 'DESKTOP' }), $(if ($script:Guard) { 'ON' } else { 'OFF' })) }; Update-Home })
    $qa.Controls.Add($chkG); $qa.Controls.Add((New-Lbl 'LAPTOP GUARD' 78 20 300 20 $script:Fnt.Row $script:Clr.Text))
    $gtxt = if ($script:Sys.IsLaptop) { 'Laptop detected. Guard keeps your battery plan, sleep, sensors and display/biometric support intact: the performance plan only raises PLUGGED-IN values. Untick only if you know you want desktop-style behaviour.' } else { 'Desktop detected - Laptop Guard is off. Tick it to force plugged-in-only power changes.' }
    $qa.Controls.Add((New-Lbl $gtxt 22 54 820 40 $script:Fnt.Small $script:Clr.Dim))
    $bPow = New-Btn 'APPLY PERFORMANCE POWER PLAN' 290 38 $true $ac 'bolt'; $bPow.Location = New-Object Drawing.Point(22, 100)
    $bPow.Add_Click({ $t = Get-TweakByName $script:PowerTweakName; if (Test-TweakActive $t) { [void][Fz.Msg]::Show('Already applied. Undo it from the GPU page if needed.', 'Power plan') } else { Invoke-Run @($t) @() } })
    $bChk = New-Btn 'SYSTEM CHECKUP' 200 38 $false $ac 'scan'; $bChk.Location = New-Object Drawing.Point(326, 100); $bChk.Add_Click({ Show-Checkup })
    $qa.Controls.AddRange(@($bPow, $bChk)); $flow.Controls.Add($qa)

    $flow.Controls.Add((New-Section 'GAMES LIBRARY' $script:PageClr.GAMES))
    $script:H.GameHost = New-Object Windows.Forms.Panel; $script:H.GameHost.Name = 'full'; $script:H.GameHost.Height = 84; $script:H.GameHost.Width = 900
    $script:H.GameHost.BackColor = $script:Clr.Bg; $script:H.GameHost.Margin = New-Object Windows.Forms.Padding(0, 0, 12, 12)
    $flow.Controls.Add($script:H.GameHost)
    return $p
}

# ---------- Debloat hub ----------
function New-HubCard([string]$Title, [string]$Desc, [string]$BtnText, [scriptblock]$Fn, $Accent, [string]$Icon) {
    $c = New-Card 300 196 'third' $Accent; $c.Icon = $Icon; $c.IconSize = 26; $c.IconX = 20; $c.IconY = 16; $c.Stripe = $true
    $c.Controls.Add((New-Lbl $Title 60 18 300 24 $script:Fnt.Mid $script:Clr.Text))
    $d = New-Lbl $Desc 22 56 300 72 $script:Fnt.Small $script:Clr.Dim; $c.Controls.Add($d)
    $b = New-Btn $BtnText 260 38 $true $Accent 'arrow'; $b.Location = New-Object Drawing.Point(22, 140); $b.Tag = $Fn; $b.Add_Click({ & $this.Tag }); $c.Controls.Add($b)
    $c.Tag = @($d, $b); $c.Add_Resize({ $this.Tag[0].Width = $this.Width - 44; $this.Tag[1].Width = $this.Width - 44 }); $c.Width = 301
    return $c
}
function Build-Debloat {
    $p = New-PageShell 'DEBLOAT' 'DEBLOAT' 'Review optional apps, services, scheduled tasks and temporary files. Windows essentials stay protected.' 112
    $flow = $script:Pages['DEBLOAT'].Flow
    $flow.Controls.Add((New-HubCard 'Optional Apps' 'See every removable app on this PC. Tick the ones you want gone - glowing tiles show your selection - and confirm before anything is uninstalled.' 'REVIEW APPS' { Show-AppsDialog } (New-Rgb 255 61 139) 'apps'))
    $flow.Controls.Add((New-HubCard 'Optional Services' 'Disable reviewed non-core services. The original startup mode is saved and can be re-enabled any time.' 'REVIEW SERVICES' { Show-ServicesDialog } (New-Rgb 255 150 40) 'gear'))
    $flow.Controls.Add((New-HubCard 'Scheduled Tasks' 'Pause reviewed background jobs (telemetry, maintenance, sync). Exact task paths shown; restorable.' 'REVIEW TASKS' { Show-TasksDialog } (New-Rgb 255 210 63) 'clock'))
    $flow.Controls.Add((New-HubCard 'Disk Cleanup' 'Find temporary files and caches you can remove. Shows exact sizes first; risky items are marked for review.' 'OPEN CLEANUP' { Show-DiskCleanup } (New-Rgb 74 222 128) 'trash'))
    $flow.Controls.Add((New-HubCard 'Windows Security' 'Core Windows components stay protected. Optionally exclude only the Fortnite folder from real-time scanning.' 'ADD FORTNITE EXCLUSION' { Invoke-Run @((Get-TweakByName 'Fortnite: Defender folder exclusion')) @() } (New-Rgb 34 211 238) 'shield'))
    $flow.Controls.Add((New-HubCard 'Remove Exclusion' 'Removes the Fortnite folder exclusion this tool added, restoring full real-time scanning of that folder.' 'REMOVE EXCLUSION' { Invoke-Run @() @((Get-TweakByName 'Fortnite: Defender folder exclusion')) } (New-Rgb 168 85 247) 'undo'))
    return $p
}

# ---------- GPU page ----------
function Update-GpuPower {
    $g = Get-NvSmi; $w = $script:GpuPow; if (-not $w) { return }
    if (-not $g) { $w.Info.Text = 'No NVIDIA GPU sensor available.'; $w.Btn.Enabled = $false; return }
    $cur = if ($null -ne $g.PowerLimit) { "{0:N0} W" -f $g.PowerLimit } else { '-- W' }; $mx = if ($null -ne $g.PowerMax) { "{0:N0} W" -f $g.PowerMax } else { '-- W' }
    $w.Info.Text = "Current limit: $cur        Driver maximum: $mx"
    $adj = ($null -ne $g.PowerMax -and $null -ne $g.PowerLimit -and $null -ne $g.PowerMin -and $g.PowerMax -gt $g.PowerMin -and $g.PowerLimit -lt $g.PowerMax)
    $w.Msg.Text = if ($adj) { 'The driver allows a higher power limit. It resets on reboot or driver restart.' } elseif ($null -eq $g.PowerMax) { 'The driver does not expose a power limit for this GPU.' } else { 'The driver does not expose an adjustable power-limit range for this GPU (common on laptops - the OEM fixes it).' }
    $w.Btn.Enabled = $adj; $w.Btn.Text = $(if ($adj) { 'SET TO MAXIMUM' } else { 'UNAVAILABLE' }); $w.Btn.Tag = $g
}
$script:NvNames = @{
    '390467' = @('Low Latency Mode (profile value 2)', 'Driver low-latency queue setting from your profile; use together with in-game Reflex.')
    '1686376' = @('Texture filtering: negative LOD bias = clamp', 'Stops negative-LOD shimmering.')
    '3070157' = @('Image sharpening: off', 'No driver sharpening override.'); '3070158' = @('Sharpening denoising factor: 0', 'Companion to sharpening.')
    '6505105' = @('DLSS model preset: default', 'No forced DLSS preset.'); '6600001' = @('Preferred refresh rate (profile value 0)', 'As stored in your profile.')
    '8102046' = @('Max pre-rendered frames = 1', 'Short CPU render queue for lower input latency.'); '8703344' = @('Anisotropic filter optimization: on', 'Slightly cheaper anisotropic sampling.')
    '11041231' = @('Vertical Sync: force off', 'Lowest presentation latency (tearing allowed).'); '11306135' = @('Shader disk cache size', 'Large persistent shader cache for fewer stutters.')
    '273507943' = @('DLSS-FG multi-frame override: 0', 'No frame-generation override (generated frames add latency).'); '274197361' = @('Power management: prefer maximum performance', 'Keeps GPU clocks high while Fortnite runs (more heat on laptops).')
    '276158834' = @('Ansel: off', 'Disables NVIDIA Ansel hooks.'); '276652957' = @('Antialiasing gamma correction (profile value)', 'As stored in your profile.')
    '276757595' = @('Antialiasing mode: application controlled', 'No driver AA override.'); '277041152' = @('Frame-rate limiter low-latency mode', 'Driver low-latency path from your profile.')
    '278196567' = @('VRR global feature: off', 'Matches uncapped, tearing-allowed play.'); '278196727' = @('VRR requested state: off', 'Companion VRR setting.')
    '282245910' = @('Anisotropic filtering mode: user-defined', 'Lets the application choose.'); '283385329' = @('DLSS-FG preset override: off', 'No override.')
    '283385347' = @('DLSS-FG override: off', 'No override.'); '294973784' = @('G-SYNC globally: off', 'Fortnite profile runs without G-SYNC.')
}
function Get-NipSettings {
    $nip = Find-Nip; $raw = Get-Content -LiteralPath $nip -Raw
    $out = New-Object System.Collections.ArrayList
    foreach ($m in [regex]::Matches($raw, '(?s)<ProfileSetting>.*?</ProfileSetting>')) {
        $id = [regex]::Match($m.Value, '<SettingID>(\d+)</SettingID>').Groups[1].Value
        $nm = ([regex]::Match($m.Value, '<SettingNameInfo>(.*?)</SettingNameInfo>').Groups[1].Value).Trim()
        $val = [regex]::Match($m.Value, '<SettingValue>(\d+)</SettingValue>').Groups[1].Value
        $pair = $script:NvNames[$id]
        $title = if ($pair) { $pair[0] } elseif ($nm) { $nm } else { "NVIDIA setting $id" }
        $desc = if ($pair) { $pair[1] } else { '' }
        [void]$out.Add([pscustomobject]@{ Id = $id; Title = $title; Desc = "$desc   [ID $id = $val]" })
    }
    return @($out)
}
function Invoke-NvApply {
    if (-not $script:HasNvidia) { [void][Fz.Msg]::Show('No NVIDIA GPU detected.', 'NVIDIA'); return }
    $ids = @($script:NvRows | Where-Object { $_.Chk.Checked } | ForEach-Object { $_.Id })
    if ($ids.Count -eq 0) { return }
    if ($script:chkDry.Checked) { Log "[DRY RUN] would import $($ids.Count) NVIDIA profile settings"; return }
    if ([Fz.Msg]::Show("Import $($ids.Count) setting(s) into the NVIDIA 'Fortnite' profile (not your global profile)?", 'NVIDIA profile', 'YesNo', 'Question') -ne 'Yes') { return }
    if ($script:chkRP.Checked -and -not $script:RPDone) { New-RestorePoint }
    try {
        $src = Get-Content -LiteralPath (Find-Nip) -Raw; $keep = $ids
        $txt = [regex]::Replace($src, '(?s)\s*<ProfileSetting>.*?</ProfileSetting>', ([Text.RegularExpressions.MatchEvaluator]({ param($m) $id = [regex]::Match($m.Value, '<SettingID>(\d+)</SettingID>').Groups[1].Value; if ($keep -contains $id) { $m.Value } else { '' } }.GetNewClosure())))
        $custom = Join-Path $script:Dir 'Custom_Fortnite_Profile.nip'
        [IO.File]::WriteAllText($custom, $txt, (New-Object Text.UTF8Encoding($true)))
        $npi = Find-NPI; if (-not $npi) { throw 'NVIDIA Profile Inspector not available.' }
        $pr = Start-Process -FilePath $npi -ArgumentList "-silentImport `"$custom`"" -Wait -PassThru
        Log "Profile Inspector exit code: $($pr.ExitCode)"
        foreach ($i in $ids) { $script:State["nv:$i"] = $true }; Save-State
        foreach ($r in $script:NvRows) { if ($script:State.ContainsKey("nv:$($r.Id)")) { $r.Status.Text = "$DOT APPLIED"; $r.Status.ForeColor = $script:Clr.Good } }
    } catch { Log "NVIDIA import failed: $($_.Exception.Message)" 'ERROR' }
}
function Build-Gpu {
    $pre = { param($flow)
        $ac = $script:PageClr.GPU
        $nm = if ($script:HasNvidia -and $script:Tel.Gpu) { $script:Tel.Gpu.Name } else { $script:GpuShort }
        $flow.Controls.Add((New-Section ("{0}   -   {1}" -f $nm, $(if ($script:HasNvidia) { 'live NVIDIA telemetry' } else { 'sensors need an NVIDIA GPU' })) $ac))
        $script:Tiles.gTemp = New-Tile 'TEMPERATURE' (New-Rgb 255 106 0); $script:Tiles.gLoad = New-Tile 'LOAD' $ac; $script:Tiles.gFan = New-Tile 'FAN SPEED' (New-Rgb 34 211 238); $script:Tiles.gDrv = New-Tile 'DRIVER STATUS' (New-Rgb 168 85 247)
        foreach ($k in 'gTemp', 'gLoad', 'gFan', 'gDrv') { $flow.Controls.Add($script:Tiles[$k].Panel) }
        $flow.Controls.Add((New-Section 'POWER LIMIT' $ac))
        $pc = New-Card 900 120 'full' $ac; $pc.Stripe = $true; $script:GpuPow = @{}
        $pc.Controls.Add((New-Lbl 'Maximum GPU power limit' 22 12 400 22 $script:Fnt.Row $script:Clr.Text))
        $script:GpuPow.Info = New-Lbl '' 22 40 640 20 $script:Fnt.MonoB $ac; $pc.Controls.Add($script:GpuPow.Info)
        $script:GpuPow.Msg = New-Lbl '' 22 66 640 44 $script:Fnt.Small $script:Clr.Dim; $pc.Controls.Add($script:GpuPow.Msg)
        $script:GpuPow.Btn = New-Btn 'UNAVAILABLE' 200 38 $true $ac 'bolt'; $script:GpuPow.Btn.Top = 14; $script:GpuPow.Btn.Enabled = $false
        $script:GpuPow.Btn.Add_Click({
                $g = $this.Tag; if (-not $g) { return }
                if ([Fz.Msg]::Show("Set the GPU power limit to $([int]$g.PowerMax) W? It resets on reboot. Higher power means more heat.", 'Power limit', 'YesNo', 'Warning') -ne 'Yes') { return }
                $o = & $script:NvSmiPath '-pl' ([string][int]$g.PowerMax) 2>&1 | Out-String; Log "nvidia-smi: $($o.Trim())"; Update-GpuPower })
        $pc.Controls.Add($script:GpuPow.Btn); $pc.Add_Resize({ $script:GpuPow.Btn.Left = $this.Width - 224; $script:GpuPow.Msg.Width = $this.Width - 270 }); $pc.Width = 901
        $flow.Controls.Add($pc)
        Update-GpuPower
    }
    $post = { param($flow)
        $ac = $script:PageClr.GPU
        $flow.Controls.Add((New-Section 'NVIDIA PROFILE (applied to the Fortnite profile only)' $ac))
        $script:NvRows = New-Object System.Collections.ArrayList
        if (-not $script:HasNvidia) {
            $n = New-Card 900 54 'full' $script:Clr.Warn; $n.Controls.Add((New-Lbl 'No NVIDIA GPU detected - NVIDIA profile settings are unavailable on this PC.' 22 16 800 20 $script:Fnt.Norm $script:Clr.Warn)); $flow.Controls.Add($n); return
        }
        foreach ($s in (Get-NipSettings)) {
            $row = New-Card 480 84 'half' $ac
            $chk = New-Object Fz.FzToggle; $chk.OnColor = $ac; $chk.Top = 12; $chk.Checked = $true; $row.Lit = $true
            $chk.Tag = $row; $chk.Add_CheckedChanged({ $this.Tag.Lit = $this.Checked })
            $st = New-Lbl '' 0 60 160 16 $script:Fnt.Tiny $script:Clr.Dim; $st.TextAlign = 'MiddleRight'
            if ($script:State.ContainsKey("nv:$($s.Id)")) { $st.Text = "$DOT APPLIED"; $st.ForeColor = $script:Clr.Good } else { $st.Text = 'NOT APPLIED' }
            $nl = New-Lbl $s.Title 18 12 380 22 $script:Fnt.Row $script:Clr.Text; $nl.AutoEllipsis = $true
            $dl = New-Lbl $s.Desc 18 36 440 22 $script:Fnt.Small $script:Clr.Dim; $dl.AutoEllipsis = $true
            $row.Controls.AddRange(@($nl, $dl, $st, $chk)); $row.Tag = @($chk, $nl, $dl, $st)
            $row.Add_Resize({ $t = $this.Tag; $t[0].Left = $this.Width - 62; $t[1].Width = $this.Width - 100; $t[2].Width = $this.Width - 36; $t[3].Left = $this.Width - 176 }); $row.Width = 481
            $flow.Controls.Add($row); [void]$script:NvRows.Add([pscustomobject]@{ Id = $s.Id; Chk = $chk; Status = $st })
        }
        $bn = New-Btn 'APPLY SELECTED NVIDIA SETTINGS' 340 40 $true $ac 'bolt'; $bn.Margin = New-Object Windows.Forms.Padding(0, 8, 12, 0); $bn.Add_Click({ Invoke-NvApply }); $flow.Controls.Add($bn)
        $hint = New-Lbl 'To revert: open NVIDIA Profile Inspector, select the Fortnite profile and choose Restore profile to defaults.' 0 0 800 22 $script:Fnt.Small $script:Clr.Dim; $hint.Name = 'full'; $hint.Margin = New-Object Windows.Forms.Padding(0, 14, 0, 0); $flow.Controls.Add($hint)
    }
    return (Build-TweakPage 'GPU' 'GPU' 'Sensors, power limit, PCIe power saving, scheduling and the Fortnite NVIDIA profile.' $pre $post)
}

# ---------- Network ----------
function Set-Hop([int]$i, [string]$Status, [string]$Detail, $Color = $null) {
    $h = $script:Hops[$i]; if (-not $Color) { $Color = $script:Clr.Dim }
    $h.Status.Text = $Status; $h.Status.ForeColor = $Color; $h.Detail.Text = $Detail; [Windows.Forms.Application]::DoEvents()
}
function Test-PingStats([string]$Target, [int]$N = 12) {
    $png = New-Object Net.NetworkInformation.Ping; $t = @(); $lost = 0
    for ($i = 0; $i -lt $N; $i++) {
        try { $r = $png.Send($Target, 1000); if ($r.Status -eq 'Success') { $t += [double]$r.RoundtripTime } else { $lost++ } } catch { $lost++ }
        Start-Sleep -Milliseconds 60; [Windows.Forms.Application]::DoEvents()
    }
    $avg = if ($t.Count) { ($t | Measure-Object -Average).Average } else { $null }
    $jit = 0; if ($t.Count -gt 1) { $s = 0; for ($i = 1; $i -lt $t.Count; $i++) { $s += [math]::Abs($t[$i] - $t[$i - 1]) }; $jit = $s / ($t.Count - 1) }
    return @{ Avg = $avg; Jitter = $jit; Loss = [math]::Round($lost / $N * 100, 0) }
}
function Test-TcpMs([string]$HostName, [int]$Port = 443, [int]$TimeoutMs = 1500) {
    $sw = [Diagnostics.Stopwatch]::StartNew(); $cl = New-Object Net.Sockets.TcpClient
    try { $ar = $cl.BeginConnect($HostName, $Port, $null, $null); if ($ar.AsyncWaitHandle.WaitOne($TimeoutMs)) { $cl.EndConnect($ar); return $sw.Elapsed.TotalMilliseconds } } catch {} finally { $cl.Close() }
    return $null
}
function Invoke-PingScan {
    $G = $script:Clr.Good; $W = $script:Clr.Warn; $B = $script:Clr.Bad
    $script:ScanBtn.Enabled = $false; $script:Form.UseWaitCursor = $true; $script:BestDns = $null; $script:BtnDns.Enabled = $false
    for ($i = 0; $i -lt 4; $i++) { Set-Hop $i 'SCANNING' '...' $script:Clr.Accent }
    try {
        # 1 - this PC
        $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Sort-Object { $_.RouteMetric + $_.InterfaceMetric } | Select-Object -First 1
        if (-not $route) { Set-Hop 0 'NO NETWORK' 'No default route found.' $B; throw 'offline' }
        $nic = Get-NetAdapter -InterfaceIndex $route.ifIndex -ErrorAction SilentlyContinue; $script:ScanIf = $route.ifIndex
        $wifi = ($nic.PhysicalMediaType -match '802\.11|Native') -or ($nic.InterfaceDescription -match 'Wi-?Fi|Wireless|802\.11')
        if ($wifi) { Set-Hop 0 'WI-FI' "$($nic.InterfaceDescription)`nLink $($nic.LinkSpeed). Wi-Fi adds jitter - use Ethernet for competitive play." $W } else { Set-Hop 0 'WIRED' "$($nic.InterfaceDescription)`nLink $($nic.LinkSpeed)." $G }
        # 2 - router
        $gw = $route.NextHop; Set-Hop 1 'PINGING' "Gateway $gw" $script:Clr.Accent
        $rs = Test-PingStats $gw 14
        if ($null -eq $rs.Avg) { Set-Hop 1 'NO REPLY' "Gateway $gw did not answer ICMP (some routers block it)." $W }
        elseif ($rs.Loss -gt 2) { Set-Hop 1 'PACKET LOSS' ("{0}% loss to {1}. Check cable/Wi-Fi signal." -f $rs.Loss, $gw) $B }
        elseif ($rs.Avg -gt 8 -or $rs.Jitter -gt 4) { Set-Hop 1 'UNSTABLE' ("{0:N1} ms avg, {1:N1} ms jitter to {2}. Move closer / use cable." -f $rs.Avg, $rs.Jitter, $gw) $W }
        else { Set-Hop 1 'HEALTHY' ("{0:N1} ms avg, {1:N1} ms jitter, {2}% loss to {3}." -f $rs.Avg, $rs.Jitter, $rs.Loss, $gw) $G }
        $script:RouterStats = $rs
        # 3 - DNS
        Set-Hop 2 'BENCHMARKING' 'Resolving test names...' $script:Clr.Accent
        $cur = @((Get-DnsClientServerAddress -InterfaceIndex $route.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses)
        $cands = [ordered]@{}; if ($cur.Count -gt 0) { $cands['Current (' + $cur[0] + ')'] = $cur[0] }
        $cands['Cloudflare 1.1.1.1'] = '1.1.1.1'; $cands['Google 8.8.8.8'] = '8.8.8.8'; $cands['Quad9 9.9.9.9'] = '9.9.9.9'
        $res = @{}
        foreach ($k in $cands.Keys) {
            $ts = @()
            foreach ($d in 'epicgames.com', 'fortnite.com', 'amazonaws.com') {
                try { $ts += (Measure-Command { Resolve-DnsName -Name $d -Server $cands[$k] -Type A -DnsOnly -ErrorAction Stop | Out-Null }).TotalMilliseconds } catch {}
                [Windows.Forms.Application]::DoEvents()
            }
            if ($ts.Count -gt 0) { $res[$k] = ($ts | Measure-Object -Average).Average }
        }
        if ($res.Count -eq 0) { Set-Hop 2 'NO DATA' 'DNS queries failed (firewall?).' $W }
        else {
            $best = $res.GetEnumerator() | Sort-Object Value | Select-Object -First 1
            $curKey = $cands.Keys | Select-Object -First 1; $curMs = $res[$curKey]
            $line = ($res.GetEnumerator() | Sort-Object Value | ForEach-Object { "{0}: {1:N0} ms" -f $_.Key, $_.Value }) -join "`n"
            if ($best.Key -ne $curKey -and $curMs -and ($curMs - $best.Value) -gt 5) {
                $script:BestDns = $cands[$best.Key]; $script:BtnDns.Enabled = $true; $script:BtnDns.Text = "APPLY BEST DNS ($($best.Key.Split(' ')[0]))"
                Set-Hop 2 'FASTER AVAILABLE' $line $W
            } else { Set-Hop 2 'FAST' $line $G }
        }
        # 4 - Fortnite region
        Set-Hop 3 'PROBING' 'Testing regions...' $script:Clr.Accent
        $regions = [ordered]@{ 'NA East' = 'us-east-1'; 'NA West' = 'us-west-2'; 'Europe' = 'eu-central-1'; 'Middle East' = 'me-south-1'; 'Asia' = 'ap-northeast-1'; 'Oceania' = 'ap-southeast-2'; 'Brazil' = 'sa-east-1' }
        $rm = @{}
        foreach ($k in $regions.Keys) {
            $ms = @(); for ($i = 0; $i -lt 3; $i++) { $v = Test-TcpMs "dynamodb.$($regions[$k]).amazonaws.com"; if ($null -ne $v) { $ms += $v }; [Windows.Forms.Application]::DoEvents() }
            if ($ms.Count) { $rm[$k] = ($ms | Measure-Object -Minimum).Minimum }
        }
        if ($rm.Count -eq 0) { Set-Hop 3 'UNREACHABLE' 'Could not reach any region endpoint.' $B }
        else {
            $bestR = $rm.GetEnumerator() | Sort-Object Value | Select-Object -First 1
            $txt = ($rm.GetEnumerator() | Sort-Object Value | Select-Object -First 4 | ForEach-Object { "{0}: {1:N0} ms" -f $_.Key, $_.Value }) -join "`n"
            $col = if ($bestR.Value -lt 60) { $G } elseif ($bestR.Value -lt 120) { $W } else { $B }
            Set-Hop 3 ("BEST: " + $bestR.Key.ToUpper()) ($txt + "`n(approx. via AWS regional endpoints)") $col
            $script:PingLbl.Text = "{0:N0} ms" -f $bestR.Value
        }
        $script:JitLbl.Text = if ($script:RouterStats.Avg) { "{0:N1} ms (router)" -f $script:RouterStats.Jitter } else { '--' }
        $script:ConnLbl.Text = if ($wifi) { 'Wi-Fi' } else { 'Ethernet' }
    } catch { if ($_.Exception.Message -ne 'offline') { Log "Scan error: $($_.Exception.Message)" 'WARN' } }
    finally { $script:ScanBtn.Enabled = $true; $script:Form.UseWaitCursor = $false }
}
function Set-BestDns {
    if (-not $script:BestDns -or -not $script:ScanIf) { return }
    $sec = switch ($script:BestDns) { '1.1.1.1' { '1.0.0.1' } '8.8.8.8' { '8.8.4.4' } default { '149.112.112.112' } }
    $old = @((Get-DnsClientServerAddress -InterfaceIndex $script:ScanIf -AddressFamily IPv4).ServerAddresses)
    if ($script:chkDry.Checked) { Log "[DRY RUN] would set DNS $($script:BestDns), $sec"; return }
    if (-not $script:State.ContainsKey("dns|$($script:ScanIf)")) {
        $dhcp = $true
        try {
            $guid = (Get-NetAdapter -InterfaceIndex $script:ScanIf -ErrorAction Stop).InterfaceGuid
            $ns = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$guid" -ErrorAction Stop).NameServer
            $dhcp = [string]::IsNullOrWhiteSpace($ns)
        } catch {}
        $script:State["dns|$($script:ScanIf)"] = @{ Old = $old; Dhcp = $dhcp }; Save-State
    }
    Set-DnsClientServerAddress -InterfaceIndex $script:ScanIf -ServerAddresses @($script:BestDns, $sec); Clear-DnsClientCache
    Log "DNS set to $($script:BestDns), $sec (previous: $($old -join ', '))"
}
function Restore-NetworkDefaults {
    if ([Fz.Msg]::Show('Undo every active network tweak and restore your previous DNS servers?', 'Restore network defaults', 'YesNo', 'Question') -ne 'Yes') { return }
    foreach ($k in @($script:State.Keys | Where-Object { $_ -like 'dns|*' })) {
        $idx = [int]$k.Split('|')[1]; $old = @($script:State[$k].Old)
        try { if ($old.Count -eq 0 -or $script:State[$k].Dhcp -eq $true) { Set-DnsClientServerAddress -InterfaceIndex $idx -ResetServerAddresses } else { Set-DnsClientServerAddress -InterfaceIndex $idx -ServerAddresses $old }; Log "DNS restored for interface $idx" } catch { Log "DNS restore failed: $($_.Exception.Message)" 'WARN' }
        $script:State.Remove($k)
    }
    Save-State
    $act = @($script:Rows | Where-Object { $_.Page -eq 'NETWORK' -and -not $_.OneShot -and $_.Active } | ForEach-Object { $_.T })
    if ($act.Count -gt 0) { Invoke-Run @() $act $false } else { Refresh-AllRows }
}
function Build-Network {
    $pre = { param($flow)
        $ac = $script:PageClr.NETWORK
        $flow.Controls.Add((New-Section 'YOUR ROUTE TO FORTNITE' $ac))
        $sc = New-Card 900 78 'full' $ac; $sc.Stripe = $true
        $sc.Controls.Add((New-Lbl 'Every hop between you and the server - scanned for ping killers.' 22 12 800 22 $script:Fnt.Row $script:Clr.Text))
        $sc.Controls.Add((New-Lbl 'Checks your adapter, router, DNS speed and latency to Fortnite hosting regions. Read-only until you choose to apply something.' 22 40 900 34 $script:Fnt.Small $script:Clr.Dim))
        $flow.Controls.Add($sc)
        $script:Hops = @(); $hc = @((New-Rgb 74 222 128), (New-Rgb 255 210 63), (New-Rgb 168 85 247), (New-Rgb 255 106 0)); $i = 0
        foreach ($n in 'YOUR PC', 'ROUTER', 'DNS', 'FORTNITE') {
            $c = New-Card 232 150 'quarter' $hc[$i]; $i++
            $c.Controls.Add((New-Lbl $n 18 12 200 16 $script:Fnt.Tiny $c.Accent))
            $s = New-Lbl 'STANDING BY' 18 34 300 24 $script:Fnt.Mid $script:Clr.Dim; $d = New-Lbl '' 18 62 300 84 $script:Fnt.Small $script:Clr.Dim
            $c.Controls.Add($s); $c.Controls.Add($d); $c.Tag = @($s, $d); $c.Add_Resize({ $this.Tag[0].Width = $this.Width - 36; $this.Tag[1].Width = $this.Width - 36 })
            $flow.Controls.Add($c); $script:Hops += @{ Status = $s; Detail = $d }
        }
        $act = New-Card 900 108 'full' $ac
        $script:ScanBtn = New-Btn 'RUN PING OPTIMIZER SCAN' 270 40 $true $ac 'scan'; $script:ScanBtn.Location = New-Object Drawing.Point(22, 14); $script:ScanBtn.Add_Click({ Invoke-PingScan })
        $script:BtnDns = New-Btn 'APPLY BEST DNS' 250 40 $false $ac 'check'; $script:BtnDns.Location = New-Object Drawing.Point(304, 14); $script:BtnDns.Enabled = $false; $script:BtnDns.Add_Click({ Set-BestDns })
        $bR = New-Btn 'RESTORE NETWORK DEFAULTS' 260 40 $false $ac 'undo'; $bR.Location = New-Object Drawing.Point(568, 14); $bR.Add_Click({ Restore-NetworkDefaults })
        $act.Controls.AddRange(@($script:ScanBtn, $script:BtnDns, $bR))
        $act.Controls.Add((New-Lbl 'BEST PING' 22 66 150 14 $script:Fnt.Tiny $script:Clr.Dim)); $script:PingLbl = New-Lbl '--' 22 80 200 22 $script:Fnt.Bold; $act.Controls.Add($script:PingLbl)
        $act.Controls.Add((New-Lbl 'JITTER' 250 66 150 14 $script:Fnt.Tiny $script:Clr.Dim)); $script:JitLbl = New-Lbl '--' 250 80 220 22 $script:Fnt.Bold; $act.Controls.Add($script:JitLbl)
        $act.Controls.Add((New-Lbl 'CONNECTION' 500 66 150 14 $script:Fnt.Tiny $script:Clr.Dim)); $script:ConnLbl = New-Lbl '--' 500 80 220 22 $script:Fnt.Bold; $act.Controls.Add($script:ConnLbl)
        $flow.Controls.Add($act)
    }
    return (Build-TweakPage 'NETWORK' 'NETWORKING' 'Scan your route, fix the weak hop, and tune the Windows network stack.' $pre)
}

# ---------- Fortnite page ----------
function Build-Games {
    $pre = { param($flow)
        $ac = $script:PageClr.GAMES
        $flow.Controls.Add((New-Section 'SET THESE IN-GAME' $ac))
        $gc = New-Card 900 178 'full' $ac; $gc.Stripe = $true
        $gc.Controls.Add((New-Lbl 'No script can do this reliably - set them in Fortnite:' 22 12 800 22 $script:Fnt.Row $script:Clr.Text))
        $tips = @('Rendering Mode = Performance  (the single biggest FPS gain; Epic documents launch options -d3d12 -FeatureLevelEs31 if it will not save)',
            'NVIDIA Reflex Low Latency = On + Boost,  V-Sync = Off,  3D Resolution = 100%',
            'Display mode = Fullscreen,  Frame rate limit = Unlimited (or just above your refresh rate)',
            'Do NOT disable Secure Boot / TPM - Fortnite may require them',
            'Close Fortnite before applying config tweaks - the game rewrites its settings file when it exits')
        $y = 44; foreach ($t in $tips) { $l = New-Lbl ($DOT + '  ' + $t) 22 $y 1000 20 $script:Fnt.Small $script:Clr.Dim; $gc.Controls.Add($l); $y += 26 }
        $flow.Controls.Add($gc)
    }
    return (Build-TweakPage 'GAMES' 'FORTNITE' 'In-game configuration, GPU preference, anti-cheat-safe priority and session cleanup.' $pre)
}

# ---------- Navigation ----------
function Show-Page([string]$Key) {
    foreach ($k in $script:Pages.Keys) { $script:Pages[$k].Panel.Visible = ($k -eq $Key) }
    $script:CurrentPage = $Key
    if ($script:Pages[$Key].Flow) { Fit-Flow $script:Pages[$Key].Flow }
    foreach ($k in $script:NavButtons.Keys) { $script:NavButtons[$k].Select($k -eq $Key) }
    Update-Footer $Key
    if ($Key -eq 'GPU') { Update-GpuPower }
    Update-Telemetry
}
function Add-Page($r) {
    $p = @($r | Where-Object { $_ -is [Windows.Forms.Panel] }) | Select-Object -Last 1
    if ($p) { $script:PagesHost.Controls.Add($p) }
}

# ---------- Main window ----------
$script:LastRP = '...'
Load-State
Initialize-Telemetry
Pump

$script:Form = New-Object Windows.Forms.Form
$fm = $script:Form; $fm.Text = "FRENZY TWEAKS  v$($script:AppVersion)"
$wa = [Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$fm.Size = New-Object Drawing.Size([math]::Min(1420, $wa.Width - 30), [math]::Min(920, $wa.Height - 30))
$fm.MinimumSize = New-Object Drawing.Size([math]::Min(1180, $wa.Width - 30), [math]::Min(740, $wa.Height - 30))
$fm.StartPosition = 'CenterScreen'; $fm.BackColor = $script:Clr.Bg; $fm.ForeColor = $script:Clr.Text; $fm.Font = $script:Fnt.Norm

# top bar
$topBar = New-Object Windows.Forms.Panel; $topBar.Dock = 'Top'; $topBar.Height = 58; $topBar.BackColor = $script:Clr.Side
$tbLogo = New-LogoBox 34 $script:Clr.Side; $tbLogo.Location = New-Object Drawing.Point(16, 12); $topBar.Controls.Add($tbLogo)
$topBar.Controls.Add((New-Wordmark 60 17 21 2.5 $script:Clr.Side))
try { $ib = New-Object Drawing.Bitmap(64, 64); $ig = [Drawing.Graphics]::FromImage($ib); $ig.SmoothingMode = 'AntiAlias'; Draw-FrenzyLogo $ig 2 2 60; $fm.Icon = [Drawing.Icon]::FromHandle($ib.GetHicon()); $ig.Dispose() } catch {}
$topRight = New-Object Windows.Forms.FlowLayoutPanel; $topRight.Dock = 'Right'; $topRight.Width = 760; $topRight.FlowDirection = 'RightToLeft'; $topRight.BackColor = $script:Clr.Side
$topRight.Padding = New-Object Windows.Forms.Padding(0, 13, 14, 0)
$script:UpdBtn = New-Btn $script:UpdateState 150 32 $false $script:Clr.Good; $script:UpdBtn.Radius = 8; $script:UpdBtn.Add_Click({ Check-ForUpdates })
$script:UpdBtn.Margin = New-Object Windows.Forms.Padding(8, 0, 0, 0)
$adm = New-Object Fz.FzPill; $adm.Text = "$DOT ADMIN"; $adm.Tint = $script:Clr.Good; $adm.Fit(); $adm.Height = 24; $adm.Margin = New-Object Windows.Forms.Padding(8, 4, 8, 0)
$script:chkRP = New-Object Fz.FzToggle; $script:chkRP.OnColor = $script:PageClr.GPU; $script:chkRP.Checked = $true; $script:chkRP.Size = New-Object Drawing.Size(42, 22); $script:chkRP.Margin = New-Object Windows.Forms.Padding(0, 4, 6, 0)
$lRP = New-Lbl 'RESTORE POINT FIRST' 0 0 150 22 $script:Fnt.Tiny $script:Clr.Dim; $lRP.TextAlign = 'MiddleLeft'; $lRP.Margin = New-Object Windows.Forms.Padding(0, 4, 14, 0)
$script:chkDry = New-Object Fz.FzToggle; $script:chkDry.OnColor = $script:PageClr.INPUT; $script:chkDry.Size = New-Object Drawing.Size(42, 22); $script:chkDry.Margin = New-Object Windows.Forms.Padding(0, 4, 6, 0)
$lDry = New-Lbl 'DRY RUN (PREVIEW)' 0 0 140 22 $script:Fnt.Tiny $script:Clr.Dim; $lDry.TextAlign = 'MiddleLeft'; $lDry.Margin = New-Object Windows.Forms.Padding(0, 4, 14, 0)
$topRight.Controls.AddRange(@($script:UpdBtn, $adm, $lRP, $script:chkRP, $lDry, $script:chkDry)); $topBar.Controls.Add($topRight)
$script:UpdBtn.Text = $script:UpdateState

# sidebar
$side = New-Object Windows.Forms.Panel; $side.Dock = 'Left'; $side.Width = 244; $side.BackColor = $script:Clr.Side
$nav = New-Object Windows.Forms.FlowLayoutPanel; $nav.Dock = 'Fill'; $nav.FlowDirection = 'TopDown'; $nav.WrapContents = $false; $nav.BackColor = $script:Clr.Side; $nav.Padding = New-Object Windows.Forms.Padding(0, 12, 0, 0)
function Add-NavLabel([string]$t) { $l = New-Lbl $t 0 0 244 24 $script:Fnt.Tiny $script:Clr.Dim; $l.Padding = New-Object Windows.Forms.Padding(24, 8, 0, 0); $l.BackColor = $script:Clr.Side; $l.Margin = New-Object Windows.Forms.Padding(0, 6, 0, 0); $nav.Controls.Add($l) }
function Add-NavBtn([string]$Key, [string]$Text, [string]$Badge) {
    $b = New-Object Fz.FzNav; $b.Text = $Text; $b.Icon = $script:PageIcon[$Key]; $b.Accent = $script:PageClr[$Key]; $b.Badge = $Badge; $b.Width = 244; $b.Margin = New-Object Windows.Forms.Padding(0)
    $b.Tag = $Key; $b.Add_Click({ Show-Page $this.Tag }); $nav.Controls.Add($b); $script:NavButtons[$Key] = $b
}
Add-NavLabel 'CORE'
Add-NavBtn 'HOME' 'Home' ''
Add-NavBtn 'GAMES' 'Fortnite' ([string](Get-PageTweaks 'GAMES').Count)
Add-NavLabel 'TWEAKS'
Add-NavBtn 'GENERAL' 'General' ([string](Get-PageTweaks 'GENERAL').Count)
Add-NavBtn 'DEBLOAT' 'Debloat' ''
Add-NavBtn 'INPUT' 'Input Delay' ([string](Get-PageTweaks 'INPUT').Count)
Add-NavBtn 'GPU' 'GPU' ([string](Get-PageTweaks 'GPU').Count)
Add-NavBtn 'NETWORK' 'Networking' ([string](Get-PageTweaks 'NETWORK').Count)
$sideBot = New-Object Windows.Forms.Panel; $sideBot.Dock = 'Bottom'; $sideBot.Height = 262; $sideBot.BackColor = $script:Clr.Side
$dev = New-Object Fz.FzCard; $dev.Location = New-Object Drawing.Point(14, 6); $dev.Size = New-Object Drawing.Size(216, 40); $dev.Icon = 'chip'; $dev.Accent = $script:PageClr.GPU; $dev.Radius = 10; $dev.Hover = $false
$script:DevLbl = New-Lbl ('{0}   Guard {1}' -f $(if ($script:Sys.IsLaptop) { 'LAPTOP' } else { 'DESKTOP' }), $(if ($script:Guard) { 'ON' } else { 'OFF' })) 44 11 170 18 $script:Fnt.Tiny $script:Clr.Text
$dev.Controls.Add($script:DevLbl); $sideBot.Controls.Add($dev)
$socials = @(@('Discord', (New-Rgb 88 101 242)), @('X', (New-Rgb 70 74 90)), @('TikTok', (New-Rgb 37 244 238)), @('YouTube', (New-Rgb 255 48 64)))
$sy = 54
foreach ($s in $socials) {
    $b = New-Btn $s[0].ToUpper() 216 38 $true $s[1] 'arrow'; $b.Location = New-Object Drawing.Point(14, $sy); $b.Tag = $s[0]
    $b.Add_Click({
            $u = $script:Links[$this.Tag]
            if ($u) { try { Start-Process $u } catch {} } else { [void][Fz.Msg]::Show("No $($this.Tag) link set yet.`n`nOpen FrenzyApp.ps1 and fill in `$script:Links near the top of the UI section.", 'Social link', 'OK', 'Information') } })
    $sideBot.Controls.Add($b); $sy += 46
}
$sideBot.Controls.Add((New-Lbl "v $($script:AppVersion)" 14 ($sy + 2) 216 18 $script:Fnt.Tiny $script:Clr.Dim))
$side.Controls.Add($nav); $side.Controls.Add($sideBot); $nav.BringToFront()

# content + log
$content = New-Object Windows.Forms.Panel; $content.Dock = 'Fill'; $content.BackColor = $script:Clr.Bg
$script:PagesHost = New-Object Windows.Forms.Panel; $script:PagesHost.Dock = 'Fill'; $script:PagesHost.BackColor = $script:Clr.Bg
$logPanel = New-Object Windows.Forms.Panel; $logPanel.Dock = 'Bottom'; $logPanel.Height = 150; $logPanel.BackColor = $script:Clr.Side
$script:Progress = New-Object Fz.FzProgress; $script:Progress.Dock = 'Top'; $script:Progress.Height = 5; $script:Progress.Accent = $script:Clr.Accent
$logHead = New-Lbl "$BAR ACTIVITY LOG" 0 0 300 24 $script:Fnt.Tiny $script:Clr.Accent; $logHead.Dock = 'Top'; $logHead.Height = 24; $logHead.Padding = New-Object Windows.Forms.Padding(20, 6, 0, 0); $logHead.BackColor = $script:Clr.Side
$script:LogBox = New-Object Windows.Forms.TextBox; $script:LogBox.Multiline = $true; $script:LogBox.ReadOnly = $true; $script:LogBox.ScrollBars = 'Vertical'; $script:LogBox.Dock = 'Fill'
$script:LogBox.BackColor = (New-Rgb 6 9 17); $script:LogBox.ForeColor = (New-Rgb 150 190 255); $script:LogBox.Font = $script:Fnt.Mono; $script:LogBox.BorderStyle = 'None'
Fix-Scroll $script:LogBox
$logPanel.Controls.Add($script:LogBox); $logPanel.Controls.Add($logHead); $logPanel.Controls.Add($script:Progress); $script:LogBox.BringToFront()
$content.Controls.Add($script:PagesHost); $content.Controls.Add($logPanel); $script:PagesHost.BringToFront()
$fm.Controls.Add($content); $fm.Controls.Add($side); $fm.Controls.Add($topBar); $content.BringToFront()
Pump

# pages (the splash keeps animating because we pump between builds)
Add-Page (Build-Home); Pump
Add-Page (Build-TweakPage 'GENERAL' 'GENERAL' 'Baseline Windows privacy, notifications and cleanup. Flip the switches you want, then APPLY CHANGES.'); Pump
Add-Page (Build-Debloat); Pump
Add-Page (Build-TweakPage 'INPUT' 'INPUT DELAY' 'Mouse, keyboard, overlay and background-service tweaks that keep your inputs responsive.'); Pump
Add-Page (Build-Gpu); Pump
Add-Page (Build-Network); Pump
Add-Page (Build-Games); Pump

$script:Timer = New-Object Windows.Forms.Timer; $script:Timer.Interval = 1500
$script:Timer.Add_Tick({ if (-not $script:Busy) { try { Update-Telemetry } catch {} } })
$fm.Add_FormClosing({ $script:Timer.Stop() })
Log ("Loaded {0} tweaks. {1} detected ({2}). Laptop Guard: {3}." -f $script:Tweaks.Count, $(if ($script:Sys.IsLaptop) { 'Laptop' } else { 'Desktop' }), $script:Sys.Model, $(if ($script:Guard) { 'ON' } else { 'OFF' }))
Log "State/backup: $script:StateFile"
if (-not $script:HasNvidia) { Log 'No NVIDIA GPU detected - NVIDIA profile and GPU sensors are unavailable.' 'WARN' }

# everything that used to run after the window opened now runs behind the splash
Refresh-AllRows; Pump
$script:LastRP = Get-LastRestorePoint
Update-GameCard; Update-Home; Show-Page 'HOME'; Pump

$fm.Add_Shown({
        try { [Fz.Native]::DarkTitle($this.Handle) } catch {}
        $this.Activate(); [Fz.Native]::Foreground($this.Handle)
        $script:Timer.Start()
        if ($global:FrenzySplash) { $global:FrenzySplash.Closing = $true }
    })
[void]$fm.ShowDialog()
