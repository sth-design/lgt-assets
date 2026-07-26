# Script v.1.0.1

# Enable TLS 1.2 for GitHub downloads in SYSTEM context
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$TargetFolder = "C:\ProgramData\LGT Logistics\Desktop Background and Login Screen"
$LocalPath = "$TargetFolder\wallpaper2.jpg"
$ImageUrl = "https://raw.githubusercontent.com/sth-design/lgt-assets/main/wallpaper2.jpg"

try {
    # 1. Create target directory if missing
    if (!(Test-Path -Path $TargetFolder)) {
        New-Item -Path $TargetFolder -ItemType Directory -Force | Out-Null
    }

    # 2. Download image
    Invoke-WebRequest -Uri $ImageUrl -OutFile $LocalPath -UseBasicParsing

    # 3. --- SET LOCK SCREEN & DESKTOP VIA MDM PERSONALIZATION CSP (Windows 10/11 Pro & Enterprise) ---
    $CSPRegPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP"
    if (!(Test-Path -Path $CSPRegPath)) {
        New-Item -Path $CSPRegPath -Force | Out-Null
    }
    Set-ItemProperty -Path $CSPRegPath -Name "LockScreenImagePath"  -Value $LocalPath -Type String -Force
    Set-ItemProperty -Path $CSPRegPath -Name "LockScreenImageUrl"   -Value $LocalPath -Type String -Force
    Set-ItemProperty -Path $CSPRegPath -Name "LockScreenImageStatus" -Value 1          -Type DWord  -Force
    Set-ItemProperty -Path $CSPRegPath -Name "DesktopImagePath"     -Value $LocalPath -Type String -Force
    Set-ItemProperty -Path $CSPRegPath -Name "DesktopImageUrl"      -Value $LocalPath -Type String -Force
    Set-ItemProperty -Path $CSPRegPath -Name "DesktopImageStatus"   -Value 1          -Type DWord  -Force

    # 4. --- SET LOCK SCREEN VIA GROUP POLICY REGISTRY ---
    $LockScreenPoliciesPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization"
    if (!(Test-Path -Path $LockScreenPoliciesPath)) {
        New-Item -Path $LockScreenPoliciesPath -Force | Out-Null
    }
    Set-ItemProperty -Path $LockScreenPoliciesPath -Name "LockScreenImagePath" -Value $LocalPath -Type String -Force

    # 5. --- SET DESKTOP WALLPAPER VIA GROUP POLICY REGISTRY ---
    $DesktopPoliciesPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Control Panel\Desktop"
    if (!(Test-Path -Path $DesktopPoliciesPath)) {
        New-Item -Path $DesktopPoliciesPath -Force | Out-Null
    }
    Set-ItemProperty -Path $DesktopPoliciesPath -Name "Wallpaper"      -Value $LocalPath -Type String -Force
    Set-ItemProperty -Path $DesktopPoliciesPath -Name "WallpaperStyle" -Value "10"       -Type String -Force

    # 6. --- UPDATE LOADED USER PROFILES (HKU\<SID>\Control Panel\Desktop) ---
    Get-ChildItem Registry::HKEY_USERS | Where-Object { $_.PSChildName -notmatch "S-1-5-18|S-1-5-19|S-1-5-20|_Classes" } | ForEach-Object {
        $userHKU = "Registry::$($_.PSChildName)\Control Panel\Desktop"
        if (Test-Path -Path $userHKU) {
            Set-ItemProperty -Path $userHKU -Name "Wallpaper"      -Value $LocalPath -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $userHKU -Name "WallpaperStyle" -Value "10"       -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $userHKU -Name "TileWallpaper"   -Value "0"        -ErrorAction SilentlyContinue
        }
    }

    # 7. --- UPDATE DEFAULT USER PROFILE (NTUSER.DAT) FOR NEW USERS ---
    reg load HKU\DefaultUser "C:\Users\Default\NTUSER.DAT" 2>$null
    if (Test-Path "HKU:\DefaultUser") {
        reg add "HKU\DefaultUser\Control Panel\Desktop" /v Wallpaper /t REG_SZ /d "$LocalPath" /f 2>$null
        reg add "HKU\DefaultUser\Control Panel\Desktop" /v WallpaperStyle /t REG_SZ /d "10" /f 2>$null
        reg add "HKU\DefaultUser\Control Panel\Desktop" /v TileWallpaper /t REG_SZ /d "0" /f 2>$null
        [gc]::Collect()
        reg unload HKU\DefaultUser 2>$null
    }

    # 8. --- REFRESH ACTIVE USER DESKTOP (RUN IN USER SESSION VIA SCHEDULED TASK) ---
    try {
        $Action = New-ScheduledTaskAction -Execute "rundll32.exe" -Argument "user32.dll,UpdatePerUserSystemParameters 1, True"
        $Trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(2)
        $Principal = New-ScheduledTaskPrincipal -GroupId "BUILTIN\Users" -RunLevel Limited
        $TaskName = "RefreshUserWallpaper"
        
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
        Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Principal $Principal -ErrorAction SilentlyContinue | Out-Null
        Start-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    }
    catch {}

    # Direct P/Invoke call fallback
    try {
        $signature = @'
[DllImport("user32.dll", CharSet = CharSet.Auto)]
public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
'@
        $type = Add-Type -MemberDefinition $signature -Name Win32Utils -Namespace NativeMethods -PassThru
        $type::SystemParametersInfo(0x0014, 0, $LocalPath, 0x0001 -bor 0x0002) | Out-Null
    }
    catch {}

    Exit 0
}
catch {
    Write-Error $_.Exception.Message
    Exit 1
}