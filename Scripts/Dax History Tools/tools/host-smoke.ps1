$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path $PSScriptRoot -Parent
$testRoot = Join-Path $taskRoot '.tools\reaper-test'
New-Item -ItemType Directory -Force -Path (Join-Path $testRoot 'UserPlugins') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $testRoot 'Scripts\ReaTeam Extensions\API') | Out-Null
Copy-Item -LiteralPath (Join-Path $env:APPDATA 'REAPER\UserPlugins\reaper_imgui-x64.dll') -Destination (Join-Path $testRoot 'UserPlugins')
Copy-Item -LiteralPath (Join-Path $env:APPDATA 'REAPER\Scripts\ReaTeam Extensions\API\imgui.lua') -Destination (Join-Path $testRoot 'Scripts\ReaTeam Extensions\API')
# Reuse the user's installed license in this disposable resource directory.
# No license contents are printed or added to the repository.
$license = Join-Path $env:APPDATA 'REAPER\reaper-license.rk'
if (Test-Path -LiteralPath $license) { Copy-Item -LiteralPath $license -Destination $testRoot }
$utf8 = New-Object System.Text.UTF8Encoding($false)
$config = Join-Path $testRoot 'reaper.ini'
[IO.File]::WriteAllText($config, "[reaper]`nshowlastproject=0`nloadlastproject=0`nnewprojdo=0`n", $utf8)
$executable = 'C:\Program Files\AUDIO\REAPER (x64)\reaper.exe'
$arguments = '-newinst -nosplash -cfgfile "{0}" "{1}"' -f $config, (Join-Path $taskRoot 'tests\reaper_smoke.lua')
$process = Start-Process -FilePath $executable -ArgumentList $arguments -WindowStyle Hidden -PassThru
Write-Host "Isolated REAPER test PID: $($process.Id)"
$result = Join-Path $testRoot 'result.txt'
if (Test-Path -LiteralPath $result) { Remove-Item -LiteralPath $result }
$deadline = [DateTime]::UtcNow.AddSeconds(45)
while (-not (Test-Path -LiteralPath $result) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 250 }
if (Test-Path -LiteralPath $result) {
    $text = [IO.File]::ReadAllText($result)
    Write-Host $text
    if (-not $text.StartsWith('PASS:')) { exit 1 }
} else {
    if (-not $process.HasExited) { Stop-Process -Id $process.Id }
    Write-Error 'No result from the isolated REAPER test within 45 seconds.'
}
