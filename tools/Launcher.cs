// Tiny launcher: starts claude-multi-server.ps1 (next to this exe) (the local window server) with a hidden PowerShell.
// Built locally by build-exe.cmd with the C# compiler that ships with Windows. C# 5 only.
using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

internal static class Launcher
{
    [STAThread]
    private static int Main()
    {
        string dir = AppDomain.CurrentDomain.BaseDirectory;
        string gui = Path.Combine(dir, "claude-multi-server.ps1");
        if (!File.Exists(gui))
        {
            MessageBox.Show("claude-multi-server.ps1 was not found next to this exe:\n" + dir,
                "claude-multi-launcher", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
        ProcessStartInfo psi = new ProcessStartInfo();
        psi.FileName = "powershell.exe";
        psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File \"" + gui + "\"";
        psi.WorkingDirectory = dir;
        psi.UseShellExecute = false;
        psi.CreateNoWindow = true;
        try
        {
            Process.Start(psi);
        }
        catch (Exception ex)
        {
            MessageBox.Show("Could not start PowerShell: " + ex.Message,
                "claude-multi-launcher", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
        return 0;
    }
}
