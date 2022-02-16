function InvokeWebRequest([string]$Uri, [String]$OutFile) {
    
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $Uri -OutFile $outFile
    $ProgressPreference = 'Continue'

}



#==============================================================================================================================================================================================
function ExpandArchive([string]$LiteralPath, [String]$DestinationPath) {
    
    $ProgressPreference = 'SilentlyContinue'
    Expand-Archive -LiteralPath $LiteralPath -DestinationPath $DestinationPath
    $ProgressPreference = 'Continue'

}



#==============================================================================================================================================================================================
function AutoUpdate([switch]$Close) {
    
    if ($Version -eq "Version Missing" -or $VersionDate -eq "Date Missing") {
        UpdateStatusLabel "Current version is missing! Could not update!"
        return
    }

    $update = $false
    try {
        if ($Settings.Core.LocalTempFolder -eq $True)   { CreateSubPath $Paths.LocalTemp;   $file = $Paths.LocalTemp   + "\version.txt" }
        else                                            { CreateSubPath $Paths.AppDataTemp; $file = $Paths.AppDataTemp + "\version.txt" }

        $versionURL = (Get-Content -LiteralPath ($Paths.Master + "\version.txt"))[3]
        InvokeWebRequest -Uri $versionURL -OutFile $file
        $newVersion = (Get-Content -LiteralPath $file)[0]
        $newDate    = (Get-Content -LiteralPath $file)[1]
        RemoveFile $file

        if ($Settings.Core.SkipUpdate -eq $True) {
            try {
                if ($Settings.Core.LastUpdateVersionCheck -eq $newVersion -and (Get-Date $Settings.Core.LastUpdateDateCheck) -eq (Get-Date $newDate) ) { return }
                else {
                    $Settings.Core.SkipUpdate = $False
                    Out-IniFile -FilePath $Files.settings -InputObject $Settings | Out-Null
                }
            }
            catch { return }
        }

        if     ($Version -lt $newVersion)                            { $update = $true }
        elseif ( (Get-Date $VersionDate) -lt (Get-Date $newDate) )   { $update = $true }
        $Settings.Core.LastUpdateVersionCheck = $newVersion
        $Settings.Core.LastUpdateDateCheck    = $newDate
    }
    catch { UpdateStatusLabel "Could not update Patcher64+ Tool" }
    
    if ($update) {
        ShowUpdateDialog
        if ($close) { $MainDialog.Close() }
    }

}



#==============================================================================================================================================================================================
function ShowUpdateDialog {

    $UpdateDialog = New-Object System.Windows.Forms.Form
    $UpdateDialog.Size = DPISize (New-Object System.Drawing.Size(440, 180))
    $UpdateDialog.Text = $ScriptName
    $UpdateDialog.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $UpdateDialog.StartPosition = "CenterScreen"
    $UpdateDialog.Icon = $Files.icon.main

    $label   = CreateLabel -x (DPISize 20)  -Y (DPISize 10) -Text ("Would you like to update Patcher64+?`n" + "New Version: " + $newVersion + " (" + $newDate + ")") -Font $Fonts.Medium -AddTo $UpdateDialog
    $yesBtn  = CreateButton -X (DPISize 20)  -Y (DPISize 80)  -Width (DPISize 100) -Height (DPISize 50) -AddTo $UpdateDialog -Text "Yes"
    $noBtn   = CreateButton -X (DPISize 160) -Y (DPISize 80)  -Width (DPISize 100) -Height (DPISize 50) -AddTo $UpdateDialog -Text "No"
    $skipBtn = CreateButton -X (DPISize 300) -Y (DPISize 80)  -Width (DPISize 100) -Height (DPISize 50) -AddTo $UpdateDialog -Text "Skip Version"
    
    $yesBtn.Add_Click(  { $UpdateDialog.Close(); RunUpdate } )
    $noBtn.Add_Click(   { $UpdateDialog.Close()            } )
    $skipBtn.Add_Click( {
        $UpdateDialog.Close()
        $Settings.Core.SkipUpdate = $True
        Out-IniFile -FilePath $Files.settings -InputObject $Settings | Out-Null
    } )

    $UpdateDialog.ShowDialog() | Out-Null
    $UpdateDialog = $label = $yesBtn = $noBtn = $null

}



#==============================================================================================================================================================================================
function RunUpdate() {
    
    $updateURL = (Get-Content -LiteralPath ($Paths.Master + "\version.txt"))[2]
    if ($Settings.Core.LocalTempFolder -eq $True)   { $path = $Paths.LocalTemp   }
    else                                            { $path = $Paths.AppDataTemp }
    CreateSubPath $Path
    $Path = $Path + "\updater"
    CreateSubPath $Path

    $zip = $path + "\master.zip"
    Get-ChildItem -Path $path -Directory | ForEach-Object { RemovePath ($path + "\" + $_) }
    RemoveFile $zip

    try { InvokeWebRequest -Uri $updateURL -OutFile $zip }
    catch {
        RemovePath $path
        WriteToConsole "Could not download new update!"
        return
    }

    if (!(TestFile $zip)) {
        RemovePath $path
        WriteToConsole "Could not extract new update!"
        return
    }

    ExpandArchive -LiteralPath $zip -DestinationPath $path

    RemovePath $Paths.Games
    RemovePath $Paths.Tools
    RemovePath $Paths.Main
    RemovePath $Paths.Scripts
    RemovePath ($Paths.Base + "\Info")

    Get-ChildItem -Path $path   -Directory | ForEach-Object { $folder = $path + "\" + $_ }
    Get-ChildItem -Path $folder -Directory | ForEach-Object { Copy-Item -LiteralPath ($folder + "\" + $_) -Destination $Paths.Base -Force -Recurse }
    Move-Item -LiteralPath ($folder + "\Patcher64+ Tool.ps1") -Destination ($Paths.Base + "\Patcher64+ Tool.ps1") -Force
    Move-Item -LiteralPath ($folder + "\Readme.txt")          -Destination ($Paths.Base + "\ReadMe.txt")          -Force
    Move-Item -LiteralPath ($folder + "\Files\version.txt")   -Destination ($Paths.Master + "\version.txt")       -Force

    RemovePath $path
    $global:FatalError = $True
    $global:Relaunch   = $True

}



#==============================================================================================================================================================================================
function UpdateAddon([string]$Repo, [string]$Master, [string]$AddonPath, [string]$Addon) {
    
    $update = $false
    if ($Settings.Core.LocalTempFolder -eq $True)   { $path = $Paths.LocalTemp   }
    else                                            { $path = $Paths.AppDataTemp }
    CreateSubPath $Path
    $Path = $Path + "\updater-" + $Addon
    CreateSubPath $Path

    if (TestFile ($AddonPath + "\lastUpdate.txt")) {
        try {
            $file = $Path + "\lastUpdate.txt"
            InvokeWebRequest -Uri $Repo -OutFile $file
            $oldVersion = (Get-Content -LiteralPath ($AddonPath + "\lastUpdate.txt"))[0]
            $newVersion = (Get-Content -LiteralPath $file)[0]
            if ( (Get-Date $oldVersion) -lt (Get-Date $newVersion) ) { $update = $true }
            else {
                RemovePath $path
                return
            }
        }
        catch {
            RemovePath $path
            WriteToConsole ("Could not retrieve last version info for " + $Addon + "!")
            return
        }
    }
    else {
        WriteToConsole ("Could not find last update for " + $Addon + "! Downloading now!")
        $update = $true
    }

    if ($update) {
        $zip = $path + "\" + $Addon + ".zip"
        Get-ChildItem -Path $path -Directory | ForEach-Object { RemovePath ($path + "\" + $_) }
        RemoveFile $zip

        try { InvokeWebRequest -Uri $Master -OutFile $zip }
        catch {
            RemovePath $path
            WriteToConsole ("Could not download lastest version for " + $Addon + "!")
            return
        }

        if (!(TestFile $zip)) {
            RemovePath $path
            WriteToConsole ("Could not extract new " + $Addon + "!")
            return
        }

        ExpandArchive -LiteralPath $zip -DestinationPath $path -Force
        RemovePath $AddonPath
        Get-ChildItem -Path $path -Directory | ForEach-Object { $folder = $path + "\" + $_ }
        CreateSubPath $Paths.Addons
        Move-Item -LiteralPath ($folder + "\Files\Addons\" + $Addon) -Destination $AddonPath -Force
        RemovePath $path
    }

}

(Get-Command -Module "Updater") | % { Export-ModuleMember $_ }