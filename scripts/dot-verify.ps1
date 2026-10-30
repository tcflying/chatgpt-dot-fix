#Requires -Version 5.1
<#
.SYNOPSIS  dot-cycle-v2.ps1 - GUI cycle helper for the ChatGPT (Codex MSIX) window. v1 stays sealed and untouched.
.NOTES  The MAIN session drives it; this script only performs GUI actions and never decides business acceptance.
  -TargetPid <int> -Handle <long> -Action Inspect|OpenDot|Retry|Home|Capture -Out <absolute NEW json> [-Image <absolute NEW png>] [-ObserveSeconds 15]
  Gates before EVERY action: owner pid EXACT + top level window + ChatGPT.exe of the OpenAI.Codex_* MSIX; any existing Out/Image is refused.
  W-string imports use CharSet.Unicode + ExactSpelling=true (v1 read only "C"). Click: InvokePattern first, else SendInput at the FRESH
  bounding rect centre while DPI aware AND foreground==target. dot tab = UNIQUE visible TabItem (NO Button fallback). No chat body/auth/draft.
  v2 deltas: capture = focus+restore, fresh bounds, IsIconic false, >=400x300, foreground==target, no image at all when refused; Observe =
  the LAST sample carries dotTab AND editor enabled in the SAME sample and the final consecutive >=3 s window is >=2 Hz and error free
  (EverSeen never passes); Home/Retry = action + no error only, the dot tab is NOT required, businessNotAccepted. Exit: 0 ok | 2 fail | 3 n/r.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][int]$TargetPid,
    [Parameter(Mandatory=$true)][long]$Handle,
    [Parameter(Mandatory=$true)][ValidateSet('Inspect','OpenDot','Retry','Home','Capture')][string]$Action,
    [Parameter(Mandatory=$true)][string]$Out,
    [string]$Image,
    [int]$ObserveSeconds = 15,
    [string]$DotName = ''
)
$ErrorActionPreference='Stop'
try { [Console]::OutputEncoding=New-Object System.Text.UTF8Encoding($false) } catch { }
$script:Sw=[System.Diagnostics.Stopwatch]::StartNew()
$script:Dpi='unknown'
$script:Res=[ordered]@{ schema='dot-bridge.dot-cycle/v2'; action=$Action; ok=$false; outcome='error'; exitCode=2
    startedUtc=[DateTime]::UtcNow.ToString('o'); endedUtc=$null; durationMs=0; observeSeconds=$ObserveSeconds; target=$null
    actionResult=$null; observation=$null; image=$null; errors=@(); notes=@(); businessAccepted=$false; businessStatus='not-accepted'
    businessNote='this helper only performs GUI actions; the MAIN session decides the business acceptance' }
function Err([string]$m){ $script:Res.errors += $m }
function Note([string]$m){ $script:Res.notes += $m }
$cs = @'
using System; using System.Runtime.InteropServices; using System.Text; using System.Threading;
public static class DC {
 [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
 [StructLayout(LayoutKind.Sequential)] public struct MI { public int dx,dy; public uint mouseData,dwFlags,time; public IntPtr extra; }
 [StructLayout(LayoutKind.Sequential)] public struct IN { public uint type; public MI mi; }
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r); [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int a, out RECT r, int s); [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
 [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h); [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h); [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint f);
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow(); [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h); [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
 [DllImport("user32.dll", CharSet=CharSet.Unicode, ExactSpelling=true)] public static extern bool GetWindowTextW(IntPtr h, StringBuilder s, int n); [DllImport("user32.dll", CharSet=CharSet.Unicode, ExactSpelling=true)] public static extern bool GetClassNameW(IntPtr h, StringBuilder s, int n);
 [DllImport("user32.dll")] public static extern int GetSystemMetrics(int n); [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr v); [DllImport("shcore.dll")] public static extern int SetProcessDpiAwareness(int a);
 [DllImport("user32.dll")] public static extern bool SetProcessDPIAware(); [DllImport("kernel32.dll")] public static extern IntPtr OpenProcess(uint a, bool i, uint p); [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
 [DllImport("kernel32.dll", CharSet=CharSet.Unicode, ExactSpelling=true)] public static extern bool QueryFullProcessImageNameW(IntPtr p, uint f, StringBuilder s, ref uint n);
 [DllImport("user32.dll")] public static extern uint SendInput(uint n, IN[] i, int s); [DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, IntPtr l, uint f, uint t, out IntPtr r);
 public static string Dpi(){ try{ if(SetProcessDpiAwarenessContext(new IntPtr(-4))) return "perMonitorV2"; }catch{} try{ if(SetProcessDpiAwareness(2)==0) return "perMonitor"; }catch{} try{ SetProcessDPIAware(); return "system"; }catch{} return "unaware"; }
 public static uint OwnerPid(IntPtr h){ uint p; GetWindowThreadProcessId(h,out p); return p; }
 public static bool IsRoot(IntPtr h){ return GetAncestor(h,2)==h; }
 public static string Title(IntPtr h){ var s=new StringBuilder(1024); GetWindowTextW(h,s,1024); return s.ToString(); }
 public static string Cls(IntPtr h){ var s=new StringBuilder(512); GetClassNameW(h,s,512); return s.ToString(); }
 public static string ProcPath(uint pid){ IntPtr h=OpenProcess(0x1000,false,pid); if(h==IntPtr.Zero) h=OpenProcess(0x0400,false,pid); if(h==IntPtr.Zero) return null; try{ uint n=2048; var s=new StringBuilder(2048); return QueryFullProcessImageNameW(h,0,s,ref n)? s.ToString(): null; } finally { CloseHandle(h); } }
 public static int[] VS(){ int x=GetSystemMetrics(76),y=GetSystemMetrics(77),w=GetSystemMetrics(78),h=GetSystemMetrics(79); if(w<=0||h<=0){ w=GetSystemMetrics(0); h=GetSystemMetrics(1); x=0; y=0; } return new[]{x,y,w,h}; }
 public static int[] Bounds(IntPtr h){ RECT d,w; bool hd=DwmGetWindowAttribute(h,9,out d,16)==0 && d.R>d.L && d.B>d.T; bool hw=GetWindowRect(h,out w) && w.R>w.L && w.B>w.T;
   if(hd) return new[]{d.L,d.T,d.R-d.L,d.B-d.T}; if(hw) return new[]{w.L,w.T,w.R-w.L,w.B-w.T}; return null; }
 public static bool Print(IntPtr h, IntPtr hdc, uint msg, uint fl, int ms){ IntPtr r; return SendMessageTimeout(h,msg,hdc,new IntPtr((long)fl),0x0002,(uint)ms,out r)!=IntPtr.Zero; }
 public static bool Foreground(IntPtr h){ return GetForegroundWindow()==h; }
 public static bool Focus(IntPtr h){ ShowWindow(h,9); SetForegroundWindow(h); int w=0; while(w<2500 && GetForegroundWindow()!=h){ Thread.Sleep(50); w+=50; } return GetForegroundWindow()==h; }
 public static bool Click(int x,int y){ int[] v=VS(); if(v[2]<=1||v[3]<=1) return false;
   int nx=(int)(((x-v[0])*65535.0)/(v[2]-1)), ny=(int)(((y-v[1])*65535.0)/(v[3]-1)); if(nx<0)nx=0; if(nx>65535)nx=65535; if(ny<0)ny=0; if(ny>65535)ny=65535; int sz=Marshal.SizeOf(typeof(IN));
   IN[] a=new IN[2]; a[0].type=0; a[0].mi.dx=nx; a[0].mi.dy=ny; a[0].mi.dwFlags=0x0001|0x8000|0x4000; a[1].type=0; a[1].mi.dx=nx; a[1].mi.dy=ny; a[1].mi.dwFlags=0x0002; if(SendInput(2,a,sz)!=2) return false;
   Thread.Sleep(70); IN[] b=new IN[1]; b[0].type=0; b[0].mi.dwFlags=0x0004; return SendInput(1,b,sz)==1; }
}
'@
Add-Type -TypeDefinition $cs -ErrorAction Stop
Add-Type -AssemblyName UIAutomationClient -ErrorAction Stop
Add-Type -AssemblyName UIAutomationTypes -ErrorAction Stop
$AE=[System.Windows.Automation.AutomationElement]
$TS=[System.Windows.Automation.TreeScope]
$CT=[System.Windows.Automation.ControlType]
$script:ErrNames=@('ChatGPT 遇到了问题','ChatGPT遇到了问题','出了点问题','出了点问题。请重试以继续','ChatGPT encountered an issue',
  'ChatGPT encountered an error','ChatGPT hit a snag','hit a snag','Something went wrong','Something went wrong. Try again to continue',
  'Try again to continue','Oops, something went wrong','Unable to open this conversation',
  "This conversation isn't available",'This conversation is unavailable','This conversation is no longer available')
if(-not $DotName){ $script:DotToken=''; $script:DotExact=@() }
else { $script:DotToken=($DotName -replace '^🔴','' -replace '🔴$','')
  $script:DotExact=@($DotName); if($script:DotToken -and $script:DotToken -ne $DotName){ $script:DotExact+=$script:DotToken } }
$script:EditNames=@('消息','Message','Send a message','使用 ChatGPT Work','Ask ChatGPT','给 ChatGPT 发消息')
function ElName($e){ try { return [string]$e.Current.Name } catch { return '' } }
function ElOff($e){ try { return [bool]$e.Current.IsOffscreen } catch { return $true } }
function AllByType($root,$ct,[int]$max){ $o=@(); try { $c=[System.Windows.Automation.PropertyCondition]::new($AE::ControlTypeProperty,$ct); $f=$root.FindAll($TS::Descendants,$c)
    for($i=0;$i -lt $f.Count -and $o.Count -lt $max;$i++){ $o+=$f.Item($i) } } catch { }
  return $o }
function FindErrs($root){ $o=@(); try { $cs=@(); foreach($n in $script:ErrNames){ $cs+=[System.Windows.Automation.PropertyCondition]::new($AE::NameProperty,$n) }
    $oc=[System.Windows.Automation.OrCondition]::new([System.Windows.Automation.Condition[]]$cs); $f=$root.FindAll($TS::Descendants,$oc); for($i=0;$i -lt $f.Count;$i++){ $o+=(ElName $f.Item($i)) } } catch { }
  return @($o | Select-Object -Unique) }
function FindDotTab($root){ $ex=@(); $co=@()
  foreach($t in (AllByType $root $CT::TabItem 120)){ $n=ElName $t; if(-not $n){continue}
    if($script:DotExact -contains $n){ $ex+=$t } elseif($script:DotToken -and $n.Contains($script:DotToken)){ $co+=$t } }
  $vis=@((@($ex)+@($co)) | Where-Object { -not (ElOff $_) }); $found=$false; $kind=$null; $name=$null
  if($vis.Count -eq 1){ $found=$true; $name=(ElName $vis[0]); if($script:DotExact -contains $name){$kind='exact'}else{$kind='contains'} }
  return [ordered]@{ found=$found; match=$kind; visibleCount=$vis.Count; name=$name; exactTitle=($script:DotExact -contains $name); tokenComplete=($name -and $script:DotToken -and $name.Contains($script:DotToken)) } }
function FindEditor($root){ $hit=$null
  foreach($e in (AllByType $root $CT::Edit 80)){ $n=ElName $e; if($n -and ($script:EditNames -contains $n)){ $hit=$e; break } }
  if($null -eq $hit){ return [ordered]@{ found=$false; name=$null; enabled=$null } }
  $en=$null; try { $en=[bool]$hit.Current.IsEnabled } catch { }
  return [ordered]@{ found=$true; name=(ElName $hit); enabled=$en } }
function TakeSample([IntPtr]$h){ $s=[ordered]@{ utc=[DateTime]::UtcNow.ToString('o'); dotTab=$false; dotMatch=$null; dotName=$null; editorFound=$false; editorEnabled=$null; errs=@(); visible=$null; iconic=$null; lost=$false }
  try { $root=$AE::FromHandle($h); if($null -eq $root){ $s.lost=$true; return $s }
    $s.visible=[DC]::IsWindowVisible($h); $s.iconic=[DC]::IsIconic($h); $d=FindDotTab $root
    $s.dotTab=[bool]$d.found; $s.dotMatch=$d.match; $s.dotName=$d.name; $e=FindEditor $root
    $s.editorFound=[bool]$e.found; $s.editorEnabled=$e.enabled; $s.errs=FindErrs $root
  } catch { $s.lost=$true; $s.errs=@('sample-error: '+$_.Exception.Message) }
  return $s }
function Observe([IntPtr]$h,[int]$secs){ $o=[ordered]@{ samples=0; observedSeconds=0.0; sampleFloor=($secs*2); rateHz=0.0; rateOk=$false; durationOk=$false
    dotTabEverSeen=$false; editorEnabledEverSeen=$false; errorSeen=$false; errorTexts=@(); errorFirstUtc=$null; errorLastUtc=$null; windowLost=$false
    hiddenSeen=$false; iconicSeen=$false; finalWindow=$null; finalWindowOk=$false; lastSample=$null; timeline=@() }
  $st=[System.Diagnostics.Stopwatch]::StartNew(); $rows=@(); $runStart=$null; $runSamples=0; $runSecs=0.0
  while(($st.Elapsed.TotalSeconds -lt $secs) -or ($o.samples -lt $o.sampleFloor)){
    if($st.Elapsed.TotalSeconds -gt ($secs*3+12)){ break }
    $t0=[datetime]::UtcNow; $s=TakeSample $h; $o.samples++
    $good=([bool]$s.dotTab -and $s.editorEnabled -eq $true -and $s.errs.Count -eq 0)
    $rows+=,[ordered]@{ utc=$s.utc; dotTab=[bool]$s.dotTab; editorEnabled=$s.editorEnabled; errCount=$s.errs.Count; good=$good; visible=$s.visible }
    if($s.lost){ $o.windowLost=$true; break }
    if($s.visible -eq $false){ $o.hiddenSeen=$true }; if($s.iconic){ $o.iconicSeen=$true }
    if($s.dotTab){ $o.dotTabEverSeen=$true }; if($s.editorEnabled -eq $true){ $o.editorEnabledEverSeen=$true }
    if($s.errs.Count -gt 0){ if(-not $o.errorSeen){ $o.errorFirstUtc=$s.utc; $o.errorSeen=$true }; $o.errorLastUtc=$s.utc; foreach($x in $s.errs){ $o.errorTexts+=$x } }
    if($good){ if($null -eq $runStart){ $runStart=$t0; $runSamples=1 } else { $runSamples++ }; $runSecs=([datetime]::UtcNow-$runStart).TotalSeconds }
    else { $runStart=$null; $runSamples=0; $runSecs=0.0 }
    $gap=[int](450-(([datetime]::UtcNow-$t0).TotalMilliseconds)); if($gap -lt 10){$gap=10}
    Start-Sleep -Milliseconds $gap }
  $o.observedSeconds=[math]::Round($st.Elapsed.TotalSeconds,2); if($o.observedSeconds -gt 0){ $o.rateHz=[math]::Round($o.samples/$o.observedSeconds,2) }
  $o.rateOk=($o.rateHz -ge 2.0); $o.durationOk=($o.observedSeconds -ge $secs)
  $fw=[ordered]@{ startUtc=$null; endUtc=$null; samples=0; seconds=0.0; rateHz=0.0; minSeconds=3.0; minRateHz=2.0; ok=$false; reason='' }
  if($runSamples -gt 0){ $fw.samples=$runSamples; $fw.seconds=[math]::Round($runSecs,2); if($runSecs -gt 0){ $fw.rateHz=[math]::Round($runSamples/$runSecs,2) }
    $fw.startUtc=$rows[($rows.Count-$runSamples)].utc; $fw.endUtc=$rows[$rows.Count-1].utc }
  if($fw.samples -eq 0){ $fw.reason='no sample carried dotTab AND editor enabled AND no error; EverSeen never passes' }
  elseif($fw.seconds -lt $fw.minSeconds){ $fw.reason=('the final consecutive good window is only '+$fw.seconds+' s ('+$fw.minSeconds+' s required)') }
  elseif($fw.rateHz -lt $fw.minRateHz){ $fw.reason=('the final window rate is '+$fw.rateHz+' Hz ('+$fw.minRateHz+' Hz required)') }
  else { $fw.ok=$true; $fw.reason='the final window is continuous, >=3 s, >=2 Hz and error free' }
  $o.finalWindow=$fw; $o.finalWindowOk=$fw.ok; $o.errorTexts=@($o.errorTexts | Select-Object -Unique)
  if($rows.Count -gt 0){ $o.lastSample=$rows[$rows.Count-1] }; $o.timeline=$rows; return $o }
function PickUnique($cands){ $vis=@($cands | Where-Object { -not (ElOff $_) }); $names=@($vis | ForEach-Object { (ElName $_) })
  $uniq=@($vis | Where-Object { $names -contains (ElName $_) } | Group-Object { (ElName $_) } | Where-Object { $_.Count -eq 1 } | ForEach-Object { $_.Group[0] })
  return [ordered]@{ visible=$vis.Count; unique=$uniq.Count; element=($uniq | Select-Object -First 1) } }
function DoClick([IntPtr]$h,$el){ $r=[ordered]@{ ok=$false; method=$null; reason=$null; x=$null; y=$null; fgBefore=$false; fgAfter=$false; dpi=$script:Dpi; invokeError=$null }
  $inv=$null; try { $inv=[System.Windows.Automation.InvokePattern]$el.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern) } catch { $inv=$null }
  if($null -ne $inv){ try { $inv.Invoke(); $r.ok=$true; $r.method='invokePattern'; return $r } catch { $r.invokeError=$_.Exception.Message } }
  $r.method='sendInput-click'; if($script:Dpi -eq 'unaware'){ $r.reason='SendInput click refused: the process is not DPI aware'; return $r }
  $fg=[DC]::Foreground($h); $r.fgBefore=$fg
  if(-not $fg){ $r.reason='SendInput click refused: the target window is not the foreground window'; return $r }
  $br=$null; try { $br=$el.Current.BoundingRectangle } catch { }
  if($null -eq $br -or $br.Width -le 0 -or $br.Height -le 0){ $r.reason='SendInput click refused: no fresh bounding rectangle'; return $r }
  $x=[int]($br.X+$br.Width/2); $y=[int]($br.Y+$br.Height/2); $r.x=$x; $r.y=$y
  if([DC]::Click($x,$y)){ $r.ok=$true } else { $r.reason='SendInput did not deliver the click sequence' }
  $r.fgAfter=[DC]::Foreground($h); return $r }
function SaveCap([IntPtr]$h,[string]$path){ $r=[ordered]@{ path=$path; ok=$false; mode=$null; fallback=$false; label='true'; width=0; height=0; distinctColors=$null
    uniformGray=$null; blank=$false; fgBefore=$false; fgAfter=$false; focused=$false; iconic=$false; visible=$false; minWidth=400; minHeight=300
    note=''; bounds=$null; imageWritten=$false }
  [void][DC]::Focus($h); Start-Sleep -Milliseconds 450
  $r.focused=[DC]::Foreground($h); $r.iconic=[DC]::IsIconic($h); $r.visible=[DC]::IsWindowVisible($h)
  if($r.iconic){ $r.note='refused: the target window is still minimized after the restore (IsIconic)'; return $r }
  if(-not $r.visible){ $r.note='refused: the target window is not visible'; return $r }
  if(-not $r.focused){ $r.note='refused: the foreground window is not the target window after the focus'; return $r }
  $b=[DC]::Bounds($h); if($null -eq $b){ $r.note='refused: no window bounds after the restore'; return $r }
  $v=[DC]::VS(); $l=[math]::Max([int]$b[0],$v[0]); $t=[math]::Max([int]$b[1],$v[1])
  $w=[math]::Min([int]$b[2],$v[0]+$v[2]-$l); $h2=[math]::Min([int]$b[3],$v[1]+$v[3]-$t)
  if($w -lt $r.minWidth -or $h2 -lt $r.minHeight){ $r.note=('refused: the fresh bounds '+$w+'x'+$h2+' are below the required '+$r.minWidth+'x'+$r.minHeight); return $r }
  $r.bounds=[ordered]@{ left=$l; top=$t; width=$w; height=$h2 }; $bmp=$null
  try { $bmp=[System.Drawing.Bitmap]::new($w,$h2,[System.Drawing.Imaging.PixelFormat]::Format32bppArgb); $g=[System.Drawing.Graphics]::FromImage($bmp)
      try { $g.CopyFromScreen($l,$t,0,0,[System.Drawing.Size]::new($w,$h2)) } finally { $g.Dispose() }
      $r.mode='copyFromScreen'; $r.fallback=$false } catch { $bmp=$null; $r.note=('copyFromScreen failed: '+$_.Exception.Message) }
  if($null -eq $bmp){ try { $bmp=[System.Drawing.Bitmap]::new($w,$h2,[System.Drawing.Imaging.PixelFormat]::Format32bppArgb); $g=[System.Drawing.Graphics]::FromImage($bmp); $sent=$false
      try { $hdc=$g.GetHdc(); try { $sent=[DC]::Print($h,$hdc,0x0317,0x01E7,1200)
          if(-not $sent){ $sent=[DC]::Print($h,$hdc,0x0318,0x001D,1200) } } finally { $g.ReleaseHdc($hdc) } } finally { $g.Dispose() }
      $r.mode='printWindow-bounded'; $r.fallback=$true; $r.label='true' } catch { $bmp=$null; $r.note=('bounded print failed: '+$_.Exception.Message) } }
  if($null -eq $bmp){ $r.note=($r.note+' | no bitmap'); return $r }
  $r.width=$bmp.Width; $r.height=$bmp.Height; $cols=New-Object 'System.Collections.Generic.HashSet[int]'; $gray=$true
  $sx=[math]::Max(1,[int]($bmp.Width/20)); $sy=[math]::Max(1,[int]($bmp.Height/20))
  for($x=0;$x -lt $bmp.Width;$x+=$sx){ for($y=0;$y -lt $bmp.Height;$y+=$sy){ try { $c=$bmp.GetPixel($x,$y); [void]$cols.Add($c.ToArgb())
      if($c.R -ne $c.G -or $c.G -ne $c.B){ $gray=$false } } catch { } } }
  $r.distinctColors=$cols.Count; $r.uniformGray=$gray; $r.blank=(($cols.Count -le 1) -or ($gray -and $cols.Count -le 3))
  $dir=[IO.Path]::GetDirectoryName($path); if($dir -and -not (Test-Path -LiteralPath $dir)){ New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  $bmp.Save($path,[System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose(); $r.imageWritten=$true; $r.fgAfter=[DC]::Foreground($h)
  if(-not $r.fgAfter){ $r.note=($r.note+' | refused: the foreground window changed during the capture'); $r.ok=$false }
  elseif($r.blank){ $r.note=($r.note+' | BLANK/uniform image - never accepted as a pass'); $r.ok=$false }
  else { $r.ok=$true }
  return $r }
if (Test-Path -LiteralPath $Out){ Write-Output ('REFUSED: Out already exists (never overwritten): '+$Out); exit 2 }
if ($Image -and (Test-Path -LiteralPath $Image)){ Write-Output ('REFUSED: Image already exists (never overwritten): '+$Image); exit 2 }
$code=0
try {
  if(-not [IO.Path]::IsPathRooted($Out)){ throw ('Out must be an absolute path: '+$Out) }
  if($Image -and -not [IO.Path]::IsPathRooted($Image)){ throw ('Image must be an absolute path: '+$Image) }
  if($Image -and $Image -eq $Out){ throw 'Image and Out must be different files' }
  if($ObserveSeconds -lt 1){ $ObserveSeconds=1 }
  $hwnd=[IntPtr]::new([int64]$Handle); $script:Dpi=[DC]::Dpi()
  try { Add-Type -AssemblyName System.Drawing -ErrorAction Stop } catch { Add-Type -AssemblyName System.Drawing.Common -ErrorAction Stop }
  $ownerPid=[DC]::OwnerPid($hwnd); $procPath=[DC]::ProcPath([uint32]$TargetPid)
  $leaf=''; if($procPath){ $leaf=[IO.Path]::GetFileName($procPath) }
  $okLeaf=($leaf -ieq 'ChatGPT.exe'); $okMsix=($procPath -like '*\WindowsApps\OpenAI.Codex_*\app\ChatGPT.exe')
  $isRoot=[DC]::IsRoot($hwnd); $visible=[DC]::IsWindowVisible($hwnd)
  $script:Res.target=[ordered]@{ pid=$TargetPid; hwnd=[int64]$Handle; ownerPid=[int64]$ownerPid; ownerPidMatches=($ownerPid -eq [uint32]$TargetPid); ownerType='topLevelWindow'
    isRootWindow=$isRoot; title=[DC]::Title($hwnd); className=[DC]::Cls($hwnd); visible=$visible; iconic=[DC]::IsIconic($hwnd); processPath=$procPath; processPathVerified=($okLeaf -and $okMsix); dpiAwareness=$script:Dpi }
  if($ownerPid -ne [uint32]$TargetPid){ Err ('owner pid mismatch: window pid='+$ownerPid+' expected='+$TargetPid); $code=2 }
  elseif(-not $isRoot){ Err 'the handle is not a top level (root) window'; $code=2 }
  elseif(-not ($okLeaf -and $okMsix)){ Err ('owner process is not ChatGPT.exe of the OpenAI.Codex MSIX package: '+$procPath); $code=2 }
  elseif(-not $visible){ Err 'the target window is not visible'; $code=2 }
  if($code -ne 0){ $script:Res.outcome='refused'; $script:Res.exitCode=2; $script:Res.ok=$false }
  else {
    $ar=[ordered]@{ selector=$Action; actionSucceeded=$false; clicked=$false; method=$null; targetName=$null; candidateCount=0; visibleCount=0; uniqueCount=0; candidateNames=@(); click=$null; skipped=$null; foreground=$false; requiresDotState=$false }
    if($Action -eq 'Capture'){
      if(-not $Image){ Err 'the Capture action requires -Image'; $code=2 }
      else { $ar.foreground=[DC]::Foreground($hwnd); $script:Res.image=SaveCap $hwnd $Image
        if(-not $script:Res.image.ok){ Err ('capture refused/failed: '+$script:Res.image.note); $code=2 } else { $code=0; $ar.actionSucceeded=$true }
        $ar.click=[ordered]@{ ok=$true; method='capture-only'; note='no click was performed' } }
    } else {
      $root=$AE::FromHandle($hwnd)
      if($null -eq $root){ Err 'the window handle has no UI Automation element'; $code=3 }
      else {
        $hbtn=@(); $dot=@(); $retry=@()
        foreach($b in (AllByType $root $CT::Button 300)){ $n=ElName $b; if(-not $n){continue}
          if($n -ceq '首页' -or $n -ceq 'Home'){ $hbtn+=$b }
          elseif($n -ceq '重试' -or $n -ceq 'Retry'){ $retry+=$b }
          elseif($script:DotToken -and $n.Contains($script:DotToken)){ $dot+=$b } }
        $cands=@(); if($Action -eq 'Home'){ $cands=$hbtn } elseif($Action -eq 'Retry'){ $cands=$retry } else { $cands=$dot }
        $ar.candidateCount=$cands.Count; $ar.candidateNames=@($cands | ForEach-Object { (ElName $_) } | Select-Object -Unique)
        if($Action -eq 'Inspect'){ $ar.skipped='observe-only: no click was performed (current Inspector state)'; $ar.requiresDotState=$true }
        elseif($cands.Count -eq 0){ Err ($Action+' refused: no matching Button was found'); $code=2 }
        else {
          $sel=PickUnique $cands; $ar.visibleCount=$sel.visible; $ar.uniqueCount=$sel.unique
          if($sel.visible -ne 1 -or $sel.unique -ne 1){ Err ($Action+' refused: the matching button is not a single visible one (total='+$cands.Count+' visible='+$sel.visible+' unique='+$sel.unique+')'); $code=2 }
          else { $ar.targetName=(ElName $sel.element); $clk=DoClick $hwnd $sel.element; $ar.click=$clk; $ar.method=$clk.method
            if(-not $clk.ok){ Err ($Action+' refused: '+$clk.reason); $code=2 }
            else { $ar.clicked=$true; $ar.actionSucceeded=$true; Note ($Action+' clicked via '+$clk.method); Start-Sleep -Milliseconds 900 } } }
        if($code -eq 0){
          $script:Res.observation=Observe $hwnd $ObserveSeconds; $ob=$script:Res.observation
          if($ob.errorSeen){ Err ('an error page was seen during the observation: '+(($ob.errorTexts) -join ' / ')+' | finalWindowOk='+$ob.finalWindowOk); $code=2 }
          elseif(-not $ob.durationOk){ Err ('not ready: the observation covered '+$ob.observedSeconds+' s of the required '+$ObserveSeconds+' s'); $code=3 }
          elseif((($Action -eq 'OpenDot' -or $Action -eq 'Inspect') -and -not $ob.finalWindowOk)){ Err ('not ready: '+$ob.finalWindow.reason); $code=3 }
          else { $code=0 } } } }
    if($Action -eq 'Home' -or $Action -eq 'Retry'){ Note 'Home/Retry are graded on the action and the absence of an error page only; the dot tab is NOT required and the result is businessNotAccepted' }
    $script:Res.actionResult=$ar; $script:Res.exitCode=$code; $script:Res.ok=($code -eq 0)
    if($code -eq 0){ $script:Res.outcome= if($Action -eq 'Home' -or $Action -eq 'Retry'){ 'action-ok-business-not-accepted' } else { 'ok-business-not-accepted' } }
    elseif($code -eq 3){ $script:Res.outcome='not-ready' } else { $script:Res.outcome='failure' } } }
catch { Err ('internal error: '+$_.Exception.Message); if($_.ScriptStackTrace){ Note $_.ScriptStackTrace }; $code=2; $script:Res.ok=$false; $script:Res.outcome='internal-error'; $script:Res.exitCode=2 }
finally {
  $script:Res.endedUtc=[DateTime]::UtcNow.ToString('o'); $script:Res.durationMs=[int]$script:Sw.ElapsedMilliseconds
  try { $json=$script:Res | ConvertTo-Json -Depth 12
    $dir=[IO.Path]::GetDirectoryName($Out); if($dir -and -not (Test-Path -LiteralPath $dir)){ New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [IO.File]::WriteAllText($Out,$json,(New-Object System.Text.UTF8Encoding($false))) } catch { Write-Output ('FATAL: could not write the result json: '+$_.Exception.Message); $code=2 }
  Write-Output ('action='+$Action+' ok='+$script:Res.ok+' outcome='+$script:Res.outcome+' exit='+$code+' durationMs='+$script:Sw.ElapsedMilliseconds+' out='+$Out) }
exit $code
