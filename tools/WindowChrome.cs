// Own caption surface: no white system title strip, including on Windows 10.
using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;

internal class WindowChrome : Form
{
    protected readonly Panel Content = new Panel();
    private readonly Panel caption = new Panel();
    private readonly Label captionText = new Label();
    private readonly PictureBox captionIcon = new PictureBox();
    private readonly FlowLayoutPanel buttons = new FlowLayoutPanel();
    private readonly Button minimize, maximize, close;
    private Color foreground = Color.FromArgb(239, 238, 234);

    [DllImport("user32.dll")] private static extern bool ReleaseCapture();
    [DllImport("user32.dll")] private static extern IntPtr SendMessage(IntPtr window, int msg, IntPtr wParam, IntPtr lParam);
    [DllImport("dwmapi.dll")] private static extern int DwmSetWindowAttribute(IntPtr window, int attribute, ref int value, int size);
    [StructLayout(LayoutKind.Sequential)] private struct PointNative { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)] private struct MinMaxInfo
    { public PointNative Reserved, MaxSize, MaxPosition, MinTrackSize, MaxTrackSize; }

    internal WindowChrome()
    {
        FormBorderStyle = FormBorderStyle.None;
        DoubleBuffered = true;
        Content.Dock = DockStyle.Fill;
        caption.Dock = DockStyle.Top;
        caption.Height = 34;
        captionIcon.Size = new Size(18, 18);
        captionIcon.Location = new Point(14, 8);
        captionIcon.SizeMode = PictureBoxSizeMode.Zoom;
        captionText.Location = new Point(40, 0);
        captionText.Size = new Size(400, 34);
        captionText.TextAlign = ContentAlignment.MiddleLeft;
        captionText.Font = new Font("Segoe UI", 9);
        buttons.Dock = DockStyle.Right;
        buttons.Width = 138;
        buttons.FlowDirection = FlowDirection.LeftToRight;
        buttons.WrapContents = false;
        buttons.Margin = Padding.Empty;
        minimize = CaptionButton("\uE921", Launcher.T("minimize"));
        maximize = CaptionButton("\uE922", Launcher.T("maximize"));
        close = CaptionButton("\uE8BB", Launcher.T("close"));
        minimize.Click += delegate { WindowState = FormWindowState.Minimized; };
        maximize.Click += delegate { ToggleMaximize(); };
        close.Click += delegate { Close(); };
        buttons.Controls.AddRange(new Control[] { minimize, maximize, close });
        caption.Controls.AddRange(new Control[] { captionIcon, captionText, buttons });
        Controls.Add(Content);
        Controls.Add(caption);
        caption.MouseDown += DragCaption;
        captionText.MouseDown += DragCaption;
        caption.MouseDoubleClick += delegate { ToggleMaximize(); };
        captionText.MouseDoubleClick += delegate { ToggleMaximize(); };
        TextChanged += delegate { captionText.Text = Text; };
        Resize += delegate { maximize.Text = WindowState == FormWindowState.Maximized ? "\uE923" : "\uE922"; };
        SetChromeColors(Color.FromArgb(15, 14, 13), foreground);
    }

    private Button CaptionButton(string symbol, string accessibleName)
    {
        var b = new Button();
        b.Text = symbol;
        b.AccessibleName = accessibleName;
        b.Font = new Font("Segoe MDL2 Assets", 10);
        b.Size = new Size(46, 34);
        b.Margin = Padding.Empty;
        b.Padding = Padding.Empty;
        b.FlatStyle = FlatStyle.Flat;
        b.FlatAppearance.BorderSize = 0;
        b.TabStop = true;
        return b;
    }

    protected void SetChromeColors(Color background, Color text)
    {
        BackColor = Content.BackColor = caption.BackColor = captionText.BackColor = captionIcon.BackColor = buttons.BackColor = background;
        foreground = text;
        ForeColor = Content.ForeColor = text;
        captionText.ForeColor = text;
        foreach (Control control in buttons.Controls)
        {
            Button b = (Button)control;
            b.BackColor = background;
            b.ForeColor = text;
            b.FlatAppearance.MouseOverBackColor = background.GetBrightness() < .5 ? Color.FromArgb(42, 40, 38) : Color.FromArgb(228, 226, 218);
            b.FlatAppearance.MouseDownBackColor = b.FlatAppearance.MouseOverBackColor;
        }
        if (IsHandleCreated)
        {
            int border = background.R | (background.G << 8) | (background.B << 16);
            DwmSetWindowAttribute(Handle, 34, ref border, sizeof(int));
        }
    }

    protected override void OnShown(EventArgs e)
    {
        string png = System.IO.Path.Combine(Launcher.Root, "assets", "launcher.png");
        if (System.IO.File.Exists(png)) captionIcon.Image = Image.FromFile(png);
        base.OnShown(e);
    }

    private void ToggleMaximize() { WindowState = WindowState == FormWindowState.Maximized ? FormWindowState.Normal : FormWindowState.Maximized; }
    private void DragCaption(object sender, MouseEventArgs e)
    {
        if (e.Button != MouseButtons.Left) return;
        ReleaseCapture();
        SendMessage(Handle, 0xA1, new IntPtr(2), IntPtr.Zero);
    }

    protected override CreateParams CreateParams
    {
        get { var p = base.CreateParams; p.Style |= 0x40000 | 0x20000 | 0x10000 | 0x80000; return p; }
    }
    protected override void WndProc(ref Message m)
    {
        if (m.Msg == 0x83 && m.WParam != IntPtr.Zero) { m.Result = IntPtr.Zero; return; }
        base.WndProc(ref m);
        if (m.Msg == 0x24)
        {
            var info = (MinMaxInfo)Marshal.PtrToStructure(m.LParam, typeof(MinMaxInfo));
            var screen = Screen.FromHandle(Handle);
            info.MaxPosition.X = screen.WorkingArea.Left - screen.Bounds.Left;
            info.MaxPosition.Y = screen.WorkingArea.Top - screen.Bounds.Top;
            info.MaxSize.X = screen.WorkingArea.Width;
            info.MaxSize.Y = screen.WorkingArea.Height;
            Marshal.StructureToPtr(info, m.LParam, false);
        }
        if (m.Msg == 0x84 && WindowState == FormWindowState.Normal)
        {
            long value = m.LParam.ToInt64();
            var p = PointToClient(new Point((short)(value & 0xffff), (short)((value >> 16) & 0xffff)));
            int edge = Math.Max(5, (int)(DeviceDpi / 96.0 * 6));
            bool left = p.X < edge, right = p.X >= ClientSize.Width - edge, top = p.Y < edge, bottom = p.Y >= ClientSize.Height - edge;
            int hit = top ? (left ? 13 : right ? 14 : 12) : bottom ? (left ? 16 : right ? 17 : 15) : left ? 10 : right ? 11 : 0;
            if (hit != 0) m.Result = new IntPtr(hit);
        }
    }
}
