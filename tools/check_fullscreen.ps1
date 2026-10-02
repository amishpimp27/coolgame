$ErrorActionPreference = "Stop"
$godot = "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
$proj  = "C:/Users/Benji/Documents/shitty-ai-game"

Add-Type @"
using System;
using System.Runtime.InteropServices;
public struct RECT2 { public int L, T, R, B; }
public class Win2 {
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT2 r);
}
"@
function RectOf($h) {
  $r = New-Object RECT2
  [void][Win2]::GetWindowRect($h, [ref]$r)
  return "$($r.R - $r.L) x $($r.B - $r.T)  at $($r.L),$($r.T)"
}

$p = Start-Process -FilePath $godot -ArgumentList '--path', $proj, '--', '--auto=world', '--scene=area:hallway' -PassThru
Start-Sleep -Seconds 7
$p.Refresh()
$h = $p.MainWindowHandle
Write-Host "windowed     : $(RectOf $h)"

$wsh = New-Object -ComObject WScript.Shell
[void]$wsh.AppActivate($p.Id)
Start-Sleep -Milliseconds 700
$wsh.SendKeys("{F11}")
Start-Sleep -Seconds 2
$p.Refresh()
Write-Host "after F11    : $(RectOf $h)"

$wsh.SendKeys("{F11}")
Start-Sleep -Seconds 2
$p.Refresh()
Write-Host "after F11 x2 : $(RectOf $h)"
Stop-Process -Id $p.Id -Force
