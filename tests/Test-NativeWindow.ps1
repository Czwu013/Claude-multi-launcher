param([Parameter(Mandatory=$true)][int]$HostProcessId, [Parameter(Mandatory=$true)][string]$EvidenceDir, [string]$Theme='dark')
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Collections.Generic;
using System.Text;
public static class CmlWindowTest {
 [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left,Top,Right,Bottom; }
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h,out Rect r);
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h,int command);
 [DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr h);
 [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
 [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h,IntPtr dc,uint flags);
 [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h,IntPtr after,int x,int y,int width,int height,uint flags);
 [DllImport("user32.dll")] public static extern IntPtr GetParent(IntPtr h);
 [DllImport("user32.dll",EntryPoint="GetWindowLongPtrW")] public static extern IntPtr GetWindowLongPtr(IntPtr h,int index);
 [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h,int msg,IntPtr w,IntPtr l);
 private delegate bool EnumCallback(IntPtr h,IntPtr l);
 [DllImport("user32.dll")] private static extern bool EnumChildWindows(IntPtr h,EnumCallback callback,IntPtr l);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] private static extern int GetWindowText(IntPtr h,StringBuilder text,int length);
 public static Dictionary<string,IntPtr> Buttons(IntPtr parent) {
  var result=new Dictionary<string,IntPtr>();
  EnumChildWindows(parent,delegate(IntPtr h,IntPtr l){var t=new StringBuilder(200);GetWindowText(h,t,200);string s=t.ToString();if(s=="\uE921"||s=="\uE922"||s=="\uE923"||s=="\uE8BB")result[s]=h;return true;},IntPtr.Zero);
  return result;
 }
}
'@
$process=[Diagnostics.Process]::GetProcessById($HostProcessId)
$handle=$process.MainWindowHandle
if ($handle -eq [IntPtr]::Zero) { throw 'Native host has no window.' }
$buttons=[CmlWindowTest]::Buttons($handle)
if ($buttons.Count -ne 3) { throw ('Expected three native caption button HWNDs; found '+$buttons.Count) }
$max=$buttons[[string][char]0xE922]
$min=$buttons[[string][char]0xE921]
[void][CmlWindowTest]::ShowWindow($handle,9)
[void][CmlWindowTest]::SetForegroundWindow($handle)
Start-Sleep -Milliseconds 400
if ($Theme -eq 'dark') {
    [void][CmlWindowTest]::SendMessage($max,0xF5,[IntPtr]::Zero,[IntPtr]::Zero)
    $deadline=(Get-Date).AddSeconds(2)
    while (-not [CmlWindowTest]::IsZoomed($handle) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 50 }
    if (-not [CmlWindowTest]::IsZoomed($handle)) { throw 'Maximize button failed.' }
    [void][CmlWindowTest]::SendMessage($max,0xF5,[IntPtr]::Zero,[IntPtr]::Zero)
    $deadline=(Get-Date).AddSeconds(2)
    while ([CmlWindowTest]::IsZoomed($handle) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 50 }
    if ([CmlWindowTest]::IsZoomed($handle)) { throw 'Restore button failed.' }
    [void][CmlWindowTest]::SendMessage($min,0xF5,[IntPtr]::Zero,[IntPtr]::Zero)
    $deadline=(Get-Date).AddSeconds(2)
    while (-not [CmlWindowTest]::IsIconic($handle) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 50 }
    if (-not [CmlWindowTest]::IsIconic($handle)) { throw 'Minimize button failed.' }
    [void][CmlWindowTest]::ShowWindow($handle,9)
}
[void][CmlWindowTest]::SetForegroundWindow($handle)
Start-Sleep -Milliseconds 400
# Root WM_PRINT synthesizes an obsolete system nonclient caption for a custom-frame form.
# Capture the real client caption panel instead, and separately prove there is no OS caption.
if (([CmlWindowTest]::GetWindowLongPtr($handle,-16).ToInt64() -band 0xC00000) -ne 0) { throw 'Unexpected system caption style.' }
$captionHandle=[CmlWindowTest]::GetParent([CmlWindowTest]::GetParent($max))
$rect=New-Object CmlWindowTest+Rect
[void][CmlWindowTest]::GetWindowRect($captionHandle,[ref]$rect)
$bitmap=New-Object Drawing.Bitmap(($rect.Right-$rect.Left),($rect.Bottom-$rect.Top),[Drawing.Imaging.PixelFormat]::Format24bppRgb)
$graphics=[Drawing.Graphics]::FromImage($bitmap)
try {
    $dc=$graphics.GetHdc()
    try { if (-not [CmlWindowTest]::PrintWindow($captionHandle,$dc,3)) { throw 'Target-window capture failed.' } }
    finally { $graphics.ReleaseHdc($dc) }
    $caption=$bitmap.GetPixel(300,16)
    $expected=if ($Theme -eq 'dark') { [Drawing.Color]::FromArgb(15,14,13) } else { [Drawing.Color]::FromArgb(245,244,238) }
    if ($caption.ToArgb() -ne $expected.ToArgb()) { throw ('Unexpected caption color: '+$caption) }
    $bitmap.Save((Join-Path $EvidenceDir ('native-caption-'+$Theme+'.png')),[Drawing.Imaging.ImageFormat]::Png)
    Write-Output ('PASS native client caption (no system caption) '+$Theme+' colors match; caption controls and screenshot verified')
} finally { $graphics.Dispose();$bitmap.Dispose();$process.Dispose() }
