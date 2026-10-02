$ErrorActionPreference = "Stop"
$godot = "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
$proj  = "C:/Users/Benji/Documents/shitty-ai-game"
$out   = "C:\Users\Benji\Documents\shitty-ai-game\tools\shots"

Add-Type @"
using System;
using System.Runtime.InteropServices;
public struct RECT { public int L, T, R, B; }
public class Win {
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
}
"@

function RectOf($h) {
  $r = New-Object RECT
  [void][Win]::GetWindowRect($h, [ref]$r)
  return "$($r.L),$($r.T) -> $($r.R),$($r.B)  [$($r.R - $r.L) x $($r.B - $r.T)]"
}

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
Write-Host "primary screen: $($screen.Width)x$($screen.Height)"

$p = Start-Process -FilePath $godot -ArgumentList '--path', $proj, '--', '--auto=world', '--scene=area:hallway' -PassThru
Start-Sleep -Seconds 7
$p.Refresh()
$h = $p.MainWindowHandle
Write-Host "window handle: $h"
Write-Host "windowed    : $(RectOf $h)"

[void][Win]::ShowWindow($h, 3)        # SW_MAXIMIZE
[void][Win]::SetForegroundWindow($h)
Start-Sleep -Seconds 4
Write-Host "maximized   : $(RectOf $h)"

$bmp = New-Object System.Drawing.Bitmap($screen.Width, $screen.Height)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($screen.X, $screen.Y, 0, 0, $bmp.Size)
$bmp.Save("$out\desktop_maximized.png", [System.Drawing.Imaging.ImageFormat]::Png)
Write-Host "captured -> $out\desktop_maximized.png"
$g.Dispose(); $bmp.Dispose()
Stop-Process -Id $p.Id -Force
