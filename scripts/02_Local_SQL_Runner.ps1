param(
    [string]$Server = 'localhost'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$queueRoot = Join-Path $projectRoot 'artifacts\sql_queue'
$pending = Join-Path $queueRoot 'pending'
$running = Join-Path $queueRoot 'running'
$completed = Join-Path $queueRoot 'completed'
foreach ($path in @($pending, $running, $completed)) {
    New-Item -ItemType Directory -Path $path -Force | Out-Null
}

$readyFile = Join-Path $queueRoot 'runner_ready.txt'
[System.IO.File]::WriteAllText($readyFile, "Started UTC: $((Get-Date).ToUniversalTime().ToString('o'))`r`nServer: $Server`r`nWindows Authentication`r`n")
Write-Output "SQL runner ready. Queue: $pending"
Write-Output 'Leave this PowerShell window open while project work continues. Create artifacts\sql_queue\STOP to end it.'

while (-not (Test-Path -LiteralPath (Join-Path $queueRoot 'STOP'))) {
    $job = Get-ChildItem -LiteralPath $pending -Filter '*.sql' -File |
        Sort-Object Name |
        Select-Object -First 1
    if ($null -eq $job) {
        Start-Sleep -Seconds 2
        continue
    }

    $runPath = Join-Path $running $job.Name
    $resultPath = Join-Path $completed $job.BaseName
    if (Test-Path -LiteralPath $resultPath) {
        Write-Warning "Skipping $($job.Name): completed output already exists."
        Start-Sleep -Seconds 2
        continue
    }

    Move-Item -LiteralPath $job.FullName -Destination $runPath
    New-Item -ItemType Directory -Path $resultPath | Out-Null
    $outputPath = Join-Path $resultPath 'output.txt'
    $errorPath = Join-Path $resultPath 'stderr.txt'
    $statusPath = Join-Path $resultPath 'status.json'
    Write-Output "Running $($job.Name)"
    $startUtc = (Get-Date).ToUniversalTime()
    & sqlcmd -S $Server -E -C -I -d DBAdmin -b -r 1 -l 15 -w 65535 -y 0 -Y 0 -i $runPath -o $outputPath 2> $errorPath
    $exitCode = $LASTEXITCODE
    $status = [pscustomobject]@{
        File = $job.Name
        StartedUTC = $startUtc.ToString('o')
        FinishedUTC = (Get-Date).ToUniversalTime().ToString('o')
        ExitCode = $exitCode
    }
    $status | ConvertTo-Json | Set-Content -LiteralPath $statusPath -Encoding UTF8
    Write-Output "Finished $($job.Name): exit code $exitCode"
}

Remove-Item -LiteralPath $readyFile -ErrorAction SilentlyContinue
Write-Output 'SQL runner stopped.'
