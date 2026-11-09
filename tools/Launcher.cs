// Native WinForms host. Uses the existing local UI; never launches a browser application.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows.Forms;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

internal static class Launcher
{
    internal static readonly string Root = AppDomain.CurrentDomain.BaseDirectory;
    internal static Dictionary<string, string> Strings;
    internal static string T(string key) { return Strings[key]; }
    [STAThread]
    private static int Main()
    {
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        try
        {
            string lang = CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "zh" ? "zh" : "en";
            Strings = new JavaScriptSerializer().Deserialize<Dictionary<string, string>>(
                File.ReadAllText(Path.Combine(Root, "src", "i18n", "native." + lang + ".json")));
            foreach (string file in new string[] { "Microsoft.Web.WebView2.Core.dll", "Microsoft.Web.WebView2.WinForms.dll", "WebView2Loader.dll" })
                if (!File.Exists(Path.Combine(Root, file))) throw new FileNotFoundException(T("dependencies_missing"));
            RunWindow(); // Missing SDK assemblies can be caught before this method is JIT loaded.
            return 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine(ex.GetType().Name + ": " + ex.Message);
            string message = Strings == null ? "Extract the complete launcher package (src/i18n is missing)." : T("startup_failed");
            MessageBox.Show(message + "\n\n" + ex.Message, "Claude Multi Launcher", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
    private static void RunWindow() { Application.Run(new LauncherWindow()); }
}

internal sealed class LauncherWindow : WindowChrome
{
    private readonly WebView2 view = new WebView2();
    private readonly Label loading = new Label();
    private readonly Timer serviceWatch = new Timer();
    private Process server;
    private Uri origin;
    private bool ready, allowClose, checkingClose, closing;
    internal LauncherWindow()
    {
        Text = Launcher.T("title");
        ClientSize = new Size(1180, 800);
        MinimumSize = new Size(1000, 640);
        StartPosition = FormStartPosition.CenterScreen;
        AutoScaleMode = AutoScaleMode.Dpi;
        string icon = Path.Combine(Launcher.Root, "assets", "launcher.ico");
        if (File.Exists(icon)) Icon = new Icon(icon);
        loading.Text = Launcher.T("starting");
        loading.Dock = DockStyle.Fill;
        loading.TextAlign = ContentAlignment.MiddleCenter;
        loading.Font = new Font("Segoe UI", 12);
        view.Dock = DockStyle.Fill;
        view.Visible = false;
        loading.BackColor = BackColor;
        loading.ForeColor = ForeColor;
        Content.Controls.Add(view);
        Content.Controls.Add(loading);
        Shown += async delegate { await StartAsync(); };
        FormClosing += OnClosing;
        FormClosed += delegate { Cleanup(); };
        serviceWatch.Interval = 1000;
        serviceWatch.Tick += delegate
        {
            if (ready && !closing) UpdateChromeAsync();
            if (!closing && server != null && server.HasExited)
            {
                serviceWatch.Stop();
                MessageBox.Show(this, Launcher.T("server_closed"), Text, MessageBoxButtons.OK, MessageBoxIcon.Error);
                allowClose = true;
                Close();
            }
        };
    }

    private async Task StartAsync()
    {
        try
        {
            string script = Path.Combine(Launcher.Root, "claude-multi-server.ps1");
            if (!File.Exists(script)) throw new FileNotFoundException(Launcher.T("server_missing"));
            var options = new CoreWebView2EnvironmentOptions();
            options.ReleaseChannels = CoreWebView2ReleaseChannels.Stable;
            try { CoreWebView2Environment.GetAvailableBrowserVersionString(null, options); }
            catch (WebView2RuntimeNotFoundException) { throw new InvalidOperationException(Launcher.T("runtime_missing")); }
            string localData = Environment.GetEnvironmentVariable("LOCALAPPDATA");
            if (String.IsNullOrEmpty(localData)) localData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            string userData = Path.Combine(localData,
                "claude-multi-launcher", "webview2"); // Own storage, never Claude or browser profiles.
            var environment = await CoreWebView2Environment.CreateAsync(null, userData, options);
            if (closing) return;
            await view.EnsureCoreWebView2Async(environment);
            if (closing) return;
            var psi = new ProcessStartInfo();
            psi.FileName = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell", "v1.0", "powershell.exe");
            psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File \"" + script +
                "\" -NoBrowser -ParentProcessId " + Process.GetCurrentProcess().Id.ToString(CultureInfo.InvariantCulture);
            psi.WorkingDirectory = Launcher.Root;
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            psi.RedirectStandardOutput = true;
            // A shell such as PowerShell 7 may have exported an incompatible PSModulePath.
            // Use Windows PowerShell's normal module locations in this child only.
            string documents = Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments);
            if (String.IsNullOrEmpty(documents)) documents = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Documents");
            psi.EnvironmentVariables["PSModulePath"] = Path.Combine(documents, "WindowsPowerShell", "Modules") + ";" +
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "WindowsPowerShell", "Modules") + ";" +
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell", "v1.0", "Modules");
            server = Process.Start(psi);
            // Private parent/child pipe; do not save the loopback access URL to disk.
            Task<string> line = server.StandardOutput.ReadLineAsync();
            if (await Task.WhenAny(line, Task.Delay(25000)) != line) throw new TimeoutException(Launcher.T("server_timeout"));
            string url = await line;
            Uri parsed;
            if (!Uri.TryCreate(url, UriKind.Absolute, out parsed) || parsed.Scheme != "http" ||
                parsed.Host != "127.0.0.1" || parsed.Port < 49200 || parsed.Port >= 65000 ||
                parsed.AbsolutePath != "/" || parsed.Query.Length != 35 || !parsed.Query.StartsWith("?t="))
                throw new InvalidOperationException(Launcher.T("server_timeout"));
            origin = parsed;
            DrainOutputAsync(server.StandardOutput); // Keep Write-Host output from filling the child pipe.
            ConfigureWebView();
            view.CoreWebView2.Navigate(origin.AbsoluteUri);
            view.Visible = true;
            view.BringToFront();
            loading.Visible = false;
            ready = true;
            serviceWatch.Start();
        }
        catch (Exception ex)
        {
            if (closing) return;
            Console.Error.WriteLine(ex.GetType().Name + ": " + ex.Message);
            MessageBox.Show(this, Launcher.T("startup_failed") + "\n\n" + ex.Message, Text, MessageBoxButtons.OK, MessageBoxIcon.Error);
            allowClose = true;
            Close();
        }
    }

    private bool IsLocal(string text)
    {
        Uri uri;
        return origin != null && Uri.TryCreate(text, UriKind.Absolute, out uri) &&
            uri.Scheme == origin.Scheme && uri.Host == origin.Host && uri.Port == origin.Port;
    }

    private bool updatingChrome;
    private async void UpdateChromeAsync()
    {
        if (updatingChrome || closing || view.CoreWebView2 == null) return;
        updatingChrome = true;
        try
        {
            string json = await view.CoreWebView2.ExecuteScriptAsync("[getComputedStyle(document.body).backgroundColor,getComputedStyle(document.body).color]");
            string[] colors = new JavaScriptSerializer().Deserialize<string[]>(json);
            SetChromeColors(CssColor(colors[0]), CssColor(colors[1]));
        }
        catch (Exception) { } // A page in initial navigation has no computed body yet; retry next tick.
        finally { updatingChrome = false; }
    }
    private Color CssColor(string css)
    {
        var match = System.Text.RegularExpressions.Regex.Match(css, @"rgb\((\d+),\s*(\d+),\s*(\d+)\)");
        if (!match.Success) throw new FormatException();
        return Color.FromArgb(Int32.Parse(match.Groups[1].Value), Int32.Parse(match.Groups[2].Value), Int32.Parse(match.Groups[3].Value));
    }

    private async void DrainOutputAsync(StreamReader reader)
    {
        char[] buffer = new char[2048];
        try { while (await reader.ReadAsync(buffer, 0, buffer.Length) > 0) { } }
        catch (IOException) { }
        catch (ObjectDisposedException) { }
    }

    private void ConfigureWebView()
    {
        var core = view.CoreWebView2;
        view.DefaultBackgroundColor = BackColor;
        core.NavigationCompleted += delegate { UpdateChromeAsync(); };
        core.Settings.AreHostObjectsAllowed = false;
        core.Settings.IsWebMessageEnabled = false;
        core.Settings.AreDevToolsEnabled = false;
        core.Settings.AreDefaultContextMenusEnabled = false;
        core.Settings.IsStatusBarEnabled = false;
        core.Settings.IsZoomControlEnabled = false;
        core.Settings.AreDefaultScriptDialogsEnabled = false;
        core.NavigationStarting += delegate(object sender, CoreWebView2NavigationStartingEventArgs e)
        { if (!String.Equals(e.Uri, origin.AbsoluteUri, StringComparison.Ordinal)) e.Cancel = true; };
        core.FrameNavigationStarting += delegate(object sender, CoreWebView2NavigationStartingEventArgs e) { e.Cancel = true; };
        core.NewWindowRequested += delegate(object sender, CoreWebView2NewWindowRequestedEventArgs e) { e.Handled = true; };
        core.DownloadStarting += delegate(object sender, CoreWebView2DownloadStartingEventArgs e) { e.Cancel = true; };
        core.PermissionRequested += delegate(object sender, CoreWebView2PermissionRequestedEventArgs e) { e.State = CoreWebView2PermissionState.Deny; };
        core.AddWebResourceRequestedFilter("*", CoreWebView2WebResourceContext.All);
        core.WebResourceRequested += delegate(object sender, CoreWebView2WebResourceRequestedEventArgs e)
        {
            if (!IsLocal(e.Request.Uri)) e.Response = core.Environment.CreateWebResourceResponse(Stream.Null, 403, "Blocked", "Content-Type: text/plain");
        };
        core.ProcessFailed += delegate
        {
            if (closing) return;
            MessageBox.Show(this, Launcher.T("startup_failed"), Text, MessageBoxButtons.OK, MessageBoxIcon.Error);
            allowClose = true;
            Close();
        };
    }

    private async void OnClosing(object sender, FormClosingEventArgs e)
    {
        if (allowClose || !ready) { closing = true; return; }
        e.Cancel = true;
        if (checkingClose) return;
        checkingClose = true;
        try
        {
            if (!IsLocal(view.Source == null ? "" : view.Source.AbsoluteUri)) throw new InvalidOperationException();
            string busy = await view.CoreWebView2.ExecuteScriptAsync("typeof operationBusy !== 'undefined' && operationBusy");
            if (busy == "true")
            {
                MessageBox.Show(this, Launcher.T("busy_close"), Text, MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }
            allowClose = true;
            Close();
        }
        catch { MessageBox.Show(this, Launcher.T("close_check_failed"), Text, MessageBoxButtons.OK, MessageBoxIcon.Information); }
        finally { checkingClose = false; }
    }

    private void Cleanup()
    {
        closing = true;
        serviceWatch.Stop();
        serviceWatch.Dispose();
        view.Dispose();
        if (server != null)
        {
            // Kill only our bound child service, never Claude or browser processes.
            try { if (!server.HasExited) { server.Kill(); server.WaitForExit(2000); } } catch (InvalidOperationException) { }
            server.Dispose();
        }
    }
}
