param([ValidateSet('bump','install','sync')][string]$Action)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path $PSScriptRoot -Parent
$utf8 = New-Object System.Text.UTF8Encoding($false)
$versionPath = Join-Path $taskRoot 'VERSION'
function Bump-Version {
    $parts = [IO.File]::ReadAllText($versionPath).Trim().Split('.')
    $newVersion = '{0}.{1}.{2}' -f $parts[0], $parts[1], ([int]$parts[2] + 1)
    [IO.File]::WriteAllText($versionPath, "$newVersion`n", $utf8)
    Write-Host "Version $newVersion"
}
function Invoke-Git {
    & git -c "safe.directory=$taskRoot" -C $taskRoot @args
    if ($LASTEXITCODE -ne 0) { throw "Git failed: $args" }
}
switch ($Action) {
    'bump' { Bump-Version }
    'install' {
        $destination = Join-Path $env:APPDATA 'REAPER\Scripts\Dax History Tools'
        New-Item -ItemType Directory -Force -Path $destination | Out-Null
        Copy-Item -LiteralPath (Join-Path $taskRoot 'VERSION') -Destination $destination
        Get-ChildItem -LiteralPath (Join-Path $taskRoot 'scripts') -Filter '*.lua' | Copy-Item -Destination $destination
        Write-Host "Installed $([IO.File]::ReadAllText($versionPath).Trim()) to $destination"
        Write-Host 'In REAPER: Actions > Show action list > New action > Load ReaScript, then load Register History Tools.lua once.'
    }
    'sync' {
        $changes = Invoke-Git status --porcelain
        if ($changes) {
            $headCommit = & git -c "safe.directory=$taskRoot" -C $taskRoot rev-parse --verify --quiet HEAD
            if ($LASTEXITCODE -eq 0) {
                $headVersion = Invoke-Git show HEAD:VERSION
                if (($headVersion -join '').Trim() -eq [IO.File]::ReadAllText($versionPath).Trim()) { Bump-Version }
            } elseif ([IO.File]::ReadAllText($versionPath).Trim() -eq '0.0.0') { Bump-Version }
            Invoke-Git add --all
            Invoke-Git commit -m ([IO.File]::ReadAllText($versionPath).Trim())
        }
        $remotes = Invoke-Git remote
        if (-not $remotes) { Write-Warning 'Local snapshot saved; no GitHub remote is configured.'; return }
        Invoke-Git push -u origin HEAD
    }
}
