#Requires -Version 5.1
<#
.SYNOPSIS  restart-app-v1.ps1 - cold-restart the ChatGPT (OpenAI Codex MSIX) desktop app via normal AUMID.
.NOTES  For the MAIN session. Graceful close first (CloseMainWindow, 15s), fallback taskkill /T /F on the SAME pid only.
  Relaunch via explorer shell:AppsFolder (normal identity, not direct-exe). Polls up to 150s for a NEW ChatGPT.exe
  main window. NEVER touches credentials, proxies, hosts, services, or other processes. Exit 0 = new window found.
  KEEP THE UTF-8 BOM.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][int]$TargetPid,
  [Parameter(Mandatory=$true)][string]$Out,
  [string]$Aumid = 'OpenAI.Codex_2p2nqsd0c76g0!App'
)
$ErrorActionPreference='Stop'
$script:Sw=[System.Diagnostics.Stopwatch]::StartNew()
$script:Res=[ordered]@{ schema='dot-bridge.restart-app/v1'; ok=$false; exitCode=2
  startedUtc=[DateTime]::UtcNow.ToString('o'); endedUtc=$null; durationMs=0
  aumid=$Aumid; targetPid=$TargetPid
  preState=$null; closeMethod=$null; taskkillExit=$null
  newPid=$null; newHwnd=$null; newExe=$null; waitedMs=$null
  errors=@(); notes=@() }
function Err([string]$m){ $script:Res.errors += $m }
function Note([string]$m){ $script:Res.notes += $m }
try {
  if(-not [System.IO.Path]::IsPathRooted($Out)){ throw 'Out must be absolute' }
  if(Test-Path -LiteralPath $Out){ throw ('REFUSED: Out already exists: '+$Out) }
  $pre = Get-Process -Id $TargetPid -ErrorAction SilentlyContinue
  if(-not $pre){ throw ('target pid not found: '+$TargetPid) }
  $prePath = $pre.Path
  $script:Res.preState = [ordered]@{ pid=$TargetPid; path=$prePath; responding=$pre.Responding; hwnd=[int64]$pre.MainWindowHandle }
  if(-not ($prePath -like '*WindowsApps\OpenAI.Codex_*\app\ChatGPT.exe')){ throw ('refused: unexpected exe path: '+$prePath) }

  # 1) graceful close of exactly this process
  $null = $pre.CloseMainWindow()
  $graceDeadline = 15000
  while($script:Sw.ElapsedMilliseconds -lt $graceDeadline){
    if(-not (Get-Process -Id $TargetPid -ErrorAction SilentlyContinue)){ break }
    Start-Sleep -Milliseconds 500
  }
  if(Get-Process -Id $TargetPid -ErrorAction SilentlyContinue){
    $closeMethod = 'taskkill-tree'
    $tk = Start-Process -FilePath "$env:SystemRoot\System32\taskkill.exe" -ArgumentList @('/PID',"$TargetPid",'/T','/F') -NoNewWindow -Wait -PassThru
    $taskkillExit = $tk.ExitCode
    Note ('taskkill /T /F exit='+$taskkillExit)
  } else { $closeMethod = 'close-main-window' }
  $script:Res.closeMethod = $closeMethod
  $script:Res.taskkillExit = $taskkillExit
  Start-Sleep -Seconds 3

  # 2) normal AUMID relaunch
  Start-Process -FilePath 'explorer.exe' -ArgumentList @('shell:AppsFolder\'+$Aumid)
  Note 'launched via shell:AppsFolder AUMID (normal identity)'

  # 3) wait for a NEW ChatGPT main window (different pid, non-zero hwnd)
  $launchAt = $script:Sw.ElapsedMilliseconds
  $found = $null
  while(($script:Sw.ElapsedMilliseconds - $launchAt) -lt 150000){
    $cand = Get-Process -Name ChatGPT -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $TargetPid -and $_.MainWindowHandle -ne 0 }
    if($cand){ $found = @($cand)[0]; break }
    Start-Sleep -Milliseconds 1000
  }
  if(-not $found){ throw 'no new ChatGPT main window appeared within 150s' }
  Start-Sleep -Seconds 10   # let renderer settle
  $found.Refresh()
  $script:Res.newPid = $found.Id
  $script:Res.newHwnd = [int64]$found.MainWindowHandle
  $script:Res.newExe = $found.Path
  $script:Res.waitedMs = [int]($script:Sw.ElapsedMilliseconds - $launchAt)
  if($found.Path -notlike '*WindowsApps\OpenAI.Codex_*\app\ChatGPT.exe'){ Err ('new exe unexpected: '+$found.Path) }
  elseif($found.MainWindowHandle -eq 0){ Err 'new window hwnd is 0 after settle' }
  else { $script:Res.ok=$true; $script:Res.exitCode=0 }
}
catch { Err ('internal error: '+$_.Exception.Message) }
finally {
  $script:Res.endedUtc=[DateTime]::UtcNow.ToString('o'); $script:Res.durationMs=[int]$script:Sw.ElapsedMilliseconds
  try { $j=$script:Res|ConvertTo-Json -Depth 8; [System.IO.File]::WriteAllText($Out,$j,(New-Object System.Text.UTF8Encoding($false))) } catch { Write-Output ('FATAL json: '+$_.Exception.Message) }
  Write-Output ('ok='+$script:Res.ok+' close='+$script:Res.closeMethod+' newPid='+$script:Res.newPid+' hwnd='+$script:Res.newHwnd)
}
exit $script:Res.exitCode
