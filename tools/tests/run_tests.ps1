# Solid Batch - automatic tests (development tool, not shipped in the .rbz).
#
# Deploys the plugin of the project into each SketchUp, starts SketchUp with
# -RubyStartup tools/tests/run_tests.rb, waits for the report written in
# tools/tests/results/latest-<major>.txt, closes that SketchUp and prints the
# report.
#
#   powershell -File tools\tests\run_tests.ps1                  # 2021 then 2017
#   powershell -File tools\tests\run_tests.ps1 -Versions 2017
#   powershell -File tools\tests\run_tests.ps1 -NoDeploy        # test what is installed
#
# SketchUp is found through the registry (InstallLocation). It must be closed:
# an open session is never touched, and only the SketchUp started here is
# closed. SketchUp 2021's welcome screen is switched off for the run, then back
# on; Make 2017 shows one: click its start button.
#
# Keep this file ASCII: Windows PowerShell 5.1 reads a .ps1 without BOM as ANSI.

param(
    [string[]]$Versions = @('2021', '2017'),
    [int]$Timeout = 300,
    [switch]$NoDeploy
)

$ErrorActionPreference = 'Stop'
$tests = $PSScriptRoot
$project = Split-Path -Parent (Split-Path -Parent $tests)
$results = Join-Path $tests 'results'
$majors = @{ '2017' = '17'; '2021' = '21' }

# "-Versions 2021,2017" reaches the script as one string with -File.
$Versions = @($Versions | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
foreach ($version in $Versions) {
    if (-not $majors.ContainsKey($version)) { Write-Host "Unknown SketchUp version: $version (2017 or 2021)"; exit 2 }
}

if (Get-Process SketchUp -ErrorAction SilentlyContinue) {
    Write-Host 'SketchUp is running: close it first (the tests never touch an open session).'
    exit 2
}
New-Item -ItemType Directory -Force $results | Out-Null

$failed = 0
foreach ($version in $Versions) {
    $location = Get-Item "HKLM:\SOFTWARE\SketchUp\SketchUp $version\InstallLocation" -ErrorAction SilentlyContinue
    $exe = if ($location) { Join-Path $location.GetValue('') 'SketchUp.exe' } else { $null }
    if (-not $exe -or -not (Test-Path $exe)) { Write-Host "SketchUp $version not found"; $failed++; continue }

    if (-not $NoDeploy) {
        $plugins = Join-Path $env:APPDATA "SketchUp\SketchUp $version\SketchUp\Plugins"
        if (-not (Test-Path $plugins)) { Write-Host "Plugins folder of SketchUp $version not found"; $failed++; continue }
        Copy-Item (Join-Path $project 'solid_batch.rb') $plugins -Force
        # Mirror: files removed from the project are removed from the plugin too.
        robocopy (Join-Path $project 'solid_batch') (Join-Path $plugins 'solid_batch') /MIR /NJH /NJS /NFL /NDL /NP | Out-Null
        if ($LASTEXITCODE -ge 8) { Write-Host "Deployment to SketchUp $version failed"; $failed++; continue }
    }

    # The welcome screen blocks -RubyStartup until it is closed. 2021: it is
    # switched off for the run and switched back on after. 2017 (Make): no
    # such setting, click its button by hand. The preferences are UTF-8
    # without BOM: read and written as such (Get-Content -Raw reads them as
    # ANSI in Windows PowerShell 5.1, which re-encoded every accented
    # character at each write); a file over 20 MB is not touched.
    $prefs = Join-Path $env:LOCALAPPDATA "SketchUp\SketchUp $version\SketchUp\PrivatePreferences.json"
    $utf8 = New-Object System.Text.UTF8Encoding $false
    $welcomeOn = '("WelcomeDialog":\s*\{\s*"ShowOnStartup":\s*)true'
    $welcomeOff = '("WelcomeDialog":\s*\{\s*"ShowOnStartup":\s*)false'
    $welcomeSwitched = $false
    if ((Test-Path $prefs) -and (Get-Item $prefs).Length -gt 20MB) {
        Write-Host "  $prefs is over 20 MB: not touched (welcome screen left as it is)."
    } elseif (Test-Path $prefs) {
        $text = [IO.File]::ReadAllText($prefs, $utf8)
        if ($text -match $welcomeOn) {
            [IO.File]::WriteAllText($prefs, ($text -replace $welcomeOn, '${1}false'), $utf8)
            $welcomeSwitched = $true
        }
    }

    $report = Join-Path $results ("latest-{0}.txt" -f $majors[$version])
    $startup = Join-Path $tests 'run_tests.rb'
    $start = Get-Date
    Write-Host "SketchUp $version - tests running..."
    if (-not $welcomeSwitched) { Write-Host "  If the welcome screen of SketchUp $version shows, click its start button." }
    $process = Start-Process $exe -ArgumentList '-RubyStartup', ('"{0}"' -f $startup) -PassThru
    $done = $false
    while (((Get-Date) - $start).TotalSeconds -lt $Timeout) {
        Start-Sleep -Seconds 2
        if ((Test-Path $report) -and (Get-Item $report).LastWriteTime -gt $start -and
            (Get-Content $report -Encoding UTF8 -Raw) -match '(?m)^DONE ') { $done = $true; break }
        if ($process.HasExited) { break }
    }
    # Only the SketchUp started here is closed.
    if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force }
    Start-Sleep -Seconds 2
    if ($welcomeSwitched -and (Test-Path $prefs)) {
        try {
            $text = [IO.File]::ReadAllText($prefs, $utf8)
            [IO.File]::WriteAllText($prefs, ($text -replace $welcomeOff, '${1}true'), $utf8)
        } catch {
            Write-Host "  Could not switch the welcome screen of SketchUp $version back on: $($_.Exception.Message)"
        }
    }

    if ($done) {
        $text = Get-Content $report -Encoding UTF8
        $text | ForEach-Object { Write-Host $_ }
        if (($text | Select-Object -Last 1) -notmatch 'failed=0 ') { $failed++ }
    } else {
        Write-Host "SketchUp $version - no report after $Timeout s (or SketchUp closed)"
        $failed++
    }
    Write-Host ''
}
exit $failed
