#Creates the log file and sets it to the default state
function Initialize-LogFile {
    if (Test-Path "$($EnvironmentProperties.TempDirectory)\EDS_$($ScriptProperties.ApplicationName)_$($ScriptProperties.ApplicationVersion).log"){
        $logFile = Get-Item "$($EnvironmentProperties.TempDirectory)\EDS_$($ScriptProperties.ApplicationName)_$($ScriptProperties.ApplicationVersion).log" -ErrorAction 'SilentlyContinue'
        $logFileSize = [double]$logFile.Length/1MB
        
        if ($logFileSize -gt 100) {
            Remove-Item "$($EnvironmentProperties.TempDirectory)\EDS_$($ScriptProperties.ApplicationName)_$($ScriptProperties.ApplicationVersion).log" -ErrorAction 'SilentlyContinue'
        }
    }

    Start-Transcript -Path "$($EnvironmentProperties.TempDirectory)\EDS_$($ScriptProperties.ApplicationName)_$($ScriptProperties.ApplicationVersion)_$($ScriptProperties.ApplicationRevision).log" -Append | Out-Null
                            

    Write-Host "$([Environment]::NewLine)$('*' * 30) Starting Script $('*' * 30)$([Environment]::NewLine)"
}


#Gets the value for runtime global variables
function Initialize-GlobalVariables {
    Write-Log 'Environment Properties' -Header
    
    Write-Log "Script version: $($ScriptProperties.Version)"

    #Gets the currently logged on userId
    $EnvironmentProperties.UserId = (Get-LoggedOnUsers | select -first 1).userid
    
    #Gets the currently logged on users's SID 
    $EnvironmentProperties.UserProfileSid = Get-UserProfileSid
    
    #Gets the currently logged on user's preferred display language
    $EnvironmentProperties.PreferredDisplayLanguage = Get-PreferredUILanguage

    ($EnvironmentProperties.GetEnumerator() | Sort-Object Name) | ForEach-Object {
        Write-Log "$($_.Key):  $($_.Value)"
    }

    Write-Log 'Environment Properties' -Footer
}


#Tests the environment's compatibility with the script
function Test-EnvironmentCompatibility {
    Write-Log "Checking environment compatibility" -Header

    Write-Log "Checking OS version compatibility"
    if (($ScriptProperties.UnsupportedOSVersions).Contains([version]"$(($EnvironmentProperties.OSVersion).Major).$($($EnvironmentProperties.OSVersion).Minor)")) {
        Write-Log "FAILED - The Operating System version $(($EnvironmentProperties.OSVersion).Major).$($($EnvironmentProperties.OSVersion).Minor) is not supported by $($ScriptProperties.ApplicationName) $($ScriptProperties.ApplicationVersion).  Exiting script."
        $ScriptProperties.ExitCode = 0
        Stop-Script
    } else {
        Write-Log "PASSED - OS version compatibility"
    }
    
    if ($ScriptProperties.Is64BitOnly) {
        Write-Log "Checking for 64bit OS"
        if($EnvironmentProperties.OSArchitecture -ne "AMD64") {
            Write-Log "FAILED - The OS is not 64 bit"
            $ScriptProperties.ExitCode = 0
            Stop-Script
        } else {
            Write-Log "PASSED - The OS is 64 bit"
        }
    }
    
    if ($ScriptProperties.AdminRequired) {
        Write-Log "Checking for Admin access"
        if(Test-IsAdmin) {
            Write-Log "Admin rights found."
        } else {
            Write-Log "Admin rights not found, aborting script."
            $ScriptProperties.ExitCode = 999
            Stop-Script
        }
    }
    
    Write-Log "Checking PowerShell version compatibility"
    if ($EnvironmentProperties.PowerShellVersion -lt $ScriptProperties.MinimumPowerShellVersion) {
        Write-Log "FAILED - The installed PowerShell version is lower than the minimum required version for the script to run properly.  Exiting script."
        $ScriptProperties.ExitCode = 0
        Stop-Script
    } else {
        Write-Log "PASSED - PowerShell version compatibility"
    }

    Write-Log "Checking Common Language Runtime for .Net Framework version compatibility"
    if ($EnvironmentProperties.CLRVersion -lt $ScriptProperties.MinimumCLRVersion) {
        Write-Log "FAILED - The installed Common Language Runtime for .Net Framework version is lower than the minimum required version for the script to run properly.  Exiting script."
        $ScriptProperties.ExitCode = 0
        Stop-Script
    } else {
        Write-Log "PASSED - Common Language Runtime for .Net Framework version compatibility"
    }

    Write-Log "Finished checking environment compatibility" -Footer
}


#Determines if the installation splash screen will be visible or hidden
function Set-ScriptVisibility {
    if ($IsSilent) {
        Write-Log 'Found Silent on the command line.  Running silent.'
    } else {                 
        Write-Log 'Found no silent arguments on the command line.  Running visible installation.'
        Invoke-SplashScreen
    }
}


#Displays the splashscreen
function Invoke-SplashScreen {
    try {
        Write-Log "Starting installation splash screen."
        $ScriptProperties.SplashScreen = New-Splash -ApplicationName "$($ScriptProperties.ApplicationName) $($ScriptProperties.ApplicationVersion)"  -DisplayLanguage $EnvironmentProperties.PreferredDisplayLanguage -Windowstate $WindowState
    } catch {
        Write-Log 'Could not start the splash screen.  Please verify SplashScreen.psm1 is in the modules directory.' -Error
    }
}


#Uses the PreviousVersionProperties table and determines if the software is installed
function Get-InstalledPreviousVersions {
    Write-Log 'Checking for previous versions.' -Header
    
    $PreviousVersionProperties | ForEach-Object {
        if (-not([string]::IsNullOrWhiteSpace($_.DisplayName)) -and -not([string]::IsNullOrWhiteSpace($_.UninstallKey))) {
            if ((Test-SoftwareInstalled -DisplayName $_.DisplayName -UninstallKey $_.UninstallKey)) {
                $_.IsInstalled = $true
                $ScriptProperties.PreviousVersionsDetected = $true
            }
        } else {
            Write-Log "No other previous versions detected"
        }
    }

    Write-Log 'Finished checking for previous versions' -Footer
}


#Uninstalls any detected previous versions of the software using the PreviousVersionProperties table
function Invoke-PreviousVersionUninstall {
    Write-Log 'Starting previous version uninstall.' -Header
    
    $PreviousVersionProperties | ForEach-Object {
        if ($_.IsInstalled) {
            Write-Log "Uninstalling $($_.DisplayName)"
            
            
            try {
                if (-not([string]::IsNullOrWhiteSpace($_.UninstallArguments))) {
                    Write-Log "Uninstalling with command $($_.UninstallPath) $($_.UninstallArguments)"
                    $exitCode = (Start-Process -FilePath $_.UninstallPath -ArgumentList $_.UninstallArguments -Wait -PassThru -WindowStyle Hidden).ExitCode  
                } else {
                    Write-Log "No uninstall arguments were found.  Uninstalling with command $($_.UninstallPath)"
                    $exitCode = (Start-Process -FilePath $_.UninstallPath -Wait -PassThru -WindowStyle Hidden).ExitCode  
                }
                
            } catch {
                Write-Log "Caught an error during the uninstall of $($_.DisplayName)"
            }
            
            Write-Log "$($_.DisplayName) uninstall exited with Exit Code: $exitCode"

            if (-not($ScriptProperties.AcceptableExitCodes.Contains($exitCode))) {
                Write-Log "An error occurred while uninstalling $($_.DisplayName)" -Error
            }
        }
        Start-Sleep -Seconds 10
    }

    Write-Log 'Finished previous version uninstall.' -Footer
}


#Gets the currently logged on userId
function Get-LoggedOnUsers() {
    $queryPath = "$Env:WinDir\system32\query.exe"

    $pattern = $pattern = "^(?:\s?|>?|)(?<userid>[^>]\S+)(?:\s{2,})(?<session_name>\S+)(?:\s{2,})(?<session_id>\d{1,})(?:\s{2,})(?<state>.+(?!\S\s{2}))(?:\s{2,})(?<idle_time>.+(?!\S\s{2}))(?:\s{2,})(?<logon_time>\d{1,2}.\d{1,2}.\d{2,4}\s\d{1,2}.\d{1,2}\s\w{0,2})$"
    <# 
    matches start of line symbol or empty character
    ^(?:\s?|>?|)
    
    captures the user id
    (?<userid>[^>]\S+)
    
    matches 2 or more consecutive spaces, but does not capture
    (?:\s{2,})
    
    captures the session name
    (?<session_name>\S+)
    
    matches 2 or more consecutive spaces, but does not capture
    (?:\s{2,})
    
    captures the session id
    (?<session_id>\d{1,})
    
    matches 2 or more consecutive spaces, but does not capture
    (?:\s{2,})
    
    captures the state of the session
    (?<state>.+(?!\S\s{2}))
    
    matches 2 or more consecutive spaces, but does not capture
    (?:\s{2,})
    
    captures the idle time of the session
    (?<idle_time>.+(?!\S\s{2}))
    
    matches 2 or more consecutive spaces, but does not capture
    (?:\s{2,})
    
    captures the logon datetime
    (?<logon_time>\d{1,2}.\d{1,2}.\d{2,4}\s\d{1,2}.\d{1,2}\s\w{0,2})$
    #>

    If ($EnvironmentProperties.OSArchitecture -match "AMD64") {
        If (Test-Path "$Env:WinDir\sysnative\query.exe") {
            $queryPath = "$Env:WinDir\sysnative\query.exe"
        } Else {
            $queryPath = "$Env:WinDir\system32\query.exe"
        }   
    }                 
  
    $query = Invoke-Expression "$querypath user | select -skip 1"
    
    $loggedOnUsers = @()

    $query | ForEach-Object {

        $results = [Regex]::Match($_, $pattern, 'IgnorePatternWhitespace')

        
        $results | ForEach-Object {
            $userSession = @{
                UserId = ($results.Groups['userid'].Value.Trim())
                SessionName = ($results.Groups['session_name'].Value.Trim())
                SessionId = ($results.Groups['session_id'].Value.Trim())
                State = ($results.Groups['state'].Value.Trim())
                IdleTime = ($results.Groups['idle_time'].Value.Trim())
                LogonTime = ($results.Groups['logon_time'].Value.Trim())
            }

            $loggedOnUsers += $userSession
        }
    }

  Return $loggedOnUsers
}


#Gets the users SID based on it's username
function Get-UserProfileSid {
    Write-Verbose "Getting a list of user profiles on the machine."
    $profileList = Get-RegKey -KeyRoot 'HKLM' -Key 'SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\' -ErrorAction 'SilentlyContinue'

    #Loops through each profile and gets the Profile Path
    $profileList | ForEach-Object {
        $userProfileSid = $_
        $profileImagePath = Get-RegValue -KeyRoot 'HKLM' -Key "SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$userProfileSid" -Value 'ProfileImagePath' -ErrorAction 'SilentlyContinue'

        #Resets the $Matches variable to null
        $Matches = $null

        #Filters out the username from the Profile Path 
        $profileImagePath | Where-Object {$_ -match '\d*\w*$'} | Out-Null

        $profilePathUserId = $Matches[0]

        #Matches the machine owners UserID to the UserID retrieved from the SID profile path.
        if ($profilePathUserId -like $EnvironmentProperties.UserId) {
            Write-Verbose "The profile path userID of: $profilePathUserId matched the currently logged on user of $($EnvironmentProperties.UserId)"
            return $userProfileSid
        }
    }
}


function Get-PreferredUILanguage {
    #Gets all machine user profiles
    Write-Verbose "Detecting the users PreferredUILanguage to determine which language to display the interface in."

    $hkuDrive = New-PSDrive -Name HKU -PSProvider Registry -Root HKEY_USERS

    $preferredLanguageTag = Get-ItemProperty "hku:\$($EnvironmentProperties.UserProfileSid)\Control Panel\Desktop" -ErrorAction 'SilentlyContinue' | Select -Property 'PreferredUILanguages'

    if ($preferredLanguageTag.PreferredUILanguages -eq $null) {
        $preferredLanguageTag = @{
            PreferredUILanguages = 'en-us'
        }
    }

    $preferredLanguageTag.PreferredUILanguages = ($preferredLanguageTag.PreferredUILanguages).ToLower()

    if ($preferredLanguageTag.PreferredUILanguages -eq $null -or $preferredLanguageTag.PreferredUILanguages -match 'en-us') {
        Write-Verbose "The PreferredUILanguages key was not detected or was a null value.  Setting display language to: English"
        return 'English'
    } else {
        $preferredDisplayLanguage = $WindowsLanguageProperties | Where-Object { $_.LanguageTag -eq $preferredLanguageTag.PreferredUILanguages } | select -first 1
    
        if ($preferredLanguageTag.PreferredUILanguages -match $preferredDisplayLanguage.LanguageTag) {
            Write-Verbose "Detected $($preferredDisplayLanguage.Language) as the preferred UI language."
            Write-Verbose "Setting the splash screen display language to: $($preferredDisplayLanguage.Language)"
            return $preferredDisplayLanguage.Language
        }
    }

    Remove-PSDrive -Name HKU -Force -ErrorAction 'SilentlyContinue'

    Write-Verbose "Unknown language detected.  Setting language to English"
    return 'English'
}

#Checks to see if the passed software is installed by checking the Uninstall registry key for the GUID and DisplayName
function Test-SoftwareInstalled {
    param(
        [Parameter(Mandatory = $true)]
        [Alias('DisplayName')]
        [String] $softwareDisplayName,

        [Parameter(Mandatory = $true)]
        [Alias('UninstallKey')]
        [String] $softwareUninstallKey
    )

    Write-Log "Checking the registry to see if $softwareDisplayName is installed."
    $returnedDisplayName = Get-RegValue -KeyRoot 'HKLM' -Key "SOFTWARE\MICROSOFT\WINDOWS\CURRENTVERSION\UNINSTALL\$softwareUninstallKey" -Value 'DisplayName' -ErrorAction 'SilentlyContinue'

    if ([String]::IsNullOrWhiteSpace($returnedDisplayName)) {
        $returnedDisplayName = Get-RegValue -KeyRoot 'HKLM' -Key "SOFTWARE\MICROSOFT\WINDOWS\CURRENTVERSION\UNINSTALL\$softwareUninstallKey" -Value 'DisplayName' -x64 -ErrorAction 'SilentlyContinue'
        Write-Verbose "Looking in the x64 registry."

        if ([String]::IsNullOrWhiteSpace($returnedDisplayName)) {
            Write-Log "Unable to verify if $softwareDisplayName is installed."
            Return $false
        }
    }
    
    Write-Verbose "DisplayName reported as: $returnedDisplayName"

    if ($softwareDisplayName -eq $returnedDisplayName) {
        Write-Log "Found $softwareDisplayName installed.  Uninstalling."
        Return $true
    } else {
        Write-Log "Unable to verify if $softwareDisplayName is installed."
        Return $false
    }
}

#Checks to see if a process is running and stops it
function Invoke-StopProcess {
    param (
        [Parameter(Mandatory = $true)]
        [alias('Process')]
        [string] $processToStop
    )

    Write-Log 'Invoking Stop Process' -Header

    $processToStop = $processToStop -replace '.exe', ''

    Write-Log 'Getting all running processes'
    $runningProcesses = Get-Process

    if ($runningProcesses.ProcessName -Contains $processToStop) {
        Write-Log "Found $processToStop running.  Attempting to stop $processToStop."
        Stop-Process -Name $processToStop -Force -ErrorAction 'SilentlyContinue'

        Try{ Wait-Process -Name $processToStop -ErrorAction 'SilentlyContinue' } Catch {}
    } else {
        Write-Log "Unable to find the $processToStop process running."
    }

    Write-Log 'Stop Process Completed' -Footer
}

#Checks to see if a process is running and returns true or false
function Invoke-FindProcess {
    param (
        [Parameter(Mandatory = $true)]
        [alias('Process')]
        [string] $processtofind
    )

    Write-Log 'Invoking Find Process' -Header

    $processtofind = $processtofind -replace '.exe', ''

    Write-Log 'Getting all running processes'

    $runningprocesses = Get-Process

    if($runningprocesses.ProcessName -Contains $processtofind) {
        Write-Log "Found $processtofind running."
        Write-Log 'Find Process Completed' -Footer
        return $true
    } else {
        Write-Log "Unable to find $processtofind running"
        Write-Log 'Find Process Completed' -Footer
        return $false
    }
}

#Returns a registry value based on the passed path
function Get-RegValue {
    param(
        [Parameter(Mandatory = $true)]
        [Alias('Root')]
        [String] $keyRoot,

        [Parameter(Mandatory = $true)]
        [Alias('Key')]
        [String] $keyPath,

        [Alias('Value')]
        [String] $keyValue,

        [Alias('x64')]
        [Switch] $targetRegistryArchitecture
    )

        $regArchitecture = [Microsoft.Win32.RegistryView]::Registry32

        if ($targetRegistryArchitecture){
            $regArchitecture = [Microsoft.Win32.RegistryView]::Registry64
        }

        Switch($keyRoot){
            'HKLM'{$key = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $regArchitecture)}
            'HKCU'{$key = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::CurrentUser, $regArchitecture)}
            'HKU' {$key = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::Users, $regArchitecture)}
            Default{$key = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $regArchitecture)}
        }
        
        $subKey =  $key.OpenSubKey("$keyPath")

        if($subKey -ne $null) {
            $value = $subKey.GetValue("$keyValue")
        }

        Return $value
}


#Returns a registry Key based on the passed path
function Get-RegKey {
    param(
        [Parameter(Mandatory = $true)]
        [Alias('Root')]
        [String] $keyRoot,

        [Parameter(Mandatory = $true)]
        [Alias('Key')]
        [String] $keyPath,

        [Alias('x64')]
        [Switch] $targetRegistryArchitecture
    )

        $regArchitecture = [Microsoft.Win32.RegistryView]::Registry32

        if ($targetRegistryArchitecture){
            $regArchitecture = [Microsoft.Win32.RegistryView]::Registry64
        }

        Switch($keyRoot){
            'HKLM'{$key = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $regArchitecture)}
            'HKCU'{$key = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::CurrentUser, $regArchitecture)}
            'HKU' {$key = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::Users, $regArchitecture)}
            Default{$key = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $regArchitecture)}
        }
        
        #$subKey =  $key.OpenSubKey("$keyPath")

        #$value = $subKey.GetSubKeyNames()
        $subKey =  $key.OpenSubKey("$keyPath")

        if($subKey -ne $null) {
            #$value = $subKey.GetValue("$keyValue")
            Return $true
        }
        else{
            return $false
        }

        #Return $value
}

function Remove-RegKey(){
    param(
        [Parameter(Mandatory = $true)]
        [Alias('Root')]
        [String] $KeyRoot,

        [Parameter(Mandatory = $true)]
        [Alias('Key')]
        [String] $KeyPath,

        #[Parameter(Mandatory = $true)]
        #[Alias('Name')]
        #[String] $KeyName,

        [Parameter(Mandatory = $true)]
        [Alias('RegType')]
        [String] $RegistryType
    )
        $RegArchitecture = [Microsoft.Win32.RegistryView]::Registry32

        if ($RegistryType -like "x64"){
            $RegArchitecture = [Microsoft.Win32.RegistryView]::Registry64
        }

        Switch($keyRoot){
            'HKLM'{$key = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $regArchitecture)}
            'HKCU'{$key = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::CurrentUser, $regArchitecture)}
            'HKU' {$key = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::Users, $regArchitecture)}
            Default{$key = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $regArchitecture)}
        }
             
        $subKey =  $Key.OpenSubKey($KeyPath, $true)

        #$subKey.DeleteSubKeyTree($KeyPath)
        $key.DeleteSubKeyTree($KeyPath)
}

function Set-RegValue(){
    param(
        [Parameter(Mandatory = $true)]
        [Alias('Root')]
        [Microsoft.Win32.RegistryHive] $KeyRoot,

        [Parameter(Mandatory = $true)]
        [Alias('Key')]
        [String] $KeyPath,

        [Parameter(Mandatory = $true)]
        [Alias('Name')]
        [String] $KeyName,

        [Parameter(Mandatory = $true)]
        [Alias('Value')]
        [String] $KeyValue,

        [Parameter(Mandatory = $true)]
        [Alias('DataType')]
        [Microsoft.Win32.RegistryValueKind] $Type,

        [Alias('x64')]
        [Switch] $b64
    )

        $RegArchitecture = [Microsoft.Win32.RegistryView]::Registry32

        if ($b64 -eq $true){
            $RegArchitecture = [Microsoft.Win32.RegistryView]::Registry64
        }

        $Key = [Microsoft.Win32.RegistryKey]::OpenBaseKey($KeyRoot, $RegArchitecture)
             
        $subKey =  $Key.OpenSubKey($KeyPath, $true)
        $subKey.SetValue($KeyName, $KeyValue, $Type)
        $root = $subKey.GetValue($KeyName)

        if ($root -eq $null) {
            $root = ""
        }

        return $root
}

#Writes to the log file
function Write-Log {
    param(
        [String] $message,
        
        [Alias('Header')]
        [Switch] $headerTag,

        [Alias('Footer')]
        [Switch] $footerTag,        

        [Alias('Error')]
        [Switch] $errorMessage
    )

    if ($headerTag) {
        Write-Host "$([Environment]::NewLine)$('=' * 20) $message $('=' * 20) $([Environment]::NewLine)"
    }

    if ($footerTag) {
        Write-Host "$('=' * 20) $message $('=' * 20) $([Environment]::NewLine)`r`n"
    }

    if ($errorMessage) {
        Write-Host "$([Environment]::NewLine * 2)$(Get-Date) ERROR - $message `r`n $([Environment]::NewLine)"
    }

    if (-not($errorMessage) -and -not($headertag) -and -not($footerTag)) {
        Write-Host "  - $(Get-Date)     $message `r`n"
    } 
}

#Tests for admin rights
function Test-IsAdmin {
	If (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
		return $false
	} else {
		return $true
	}
}

#Exits the script
function Stop-Script {
    if ($ScriptProperties.SplashScreen -ne $null) {
        try { 
            Stop-Splash -Splash $ScriptProperties.SplashScreen
        } catch {
            Write-Log 'Caught an error while attempting to stop the splash screen.'
        }
        
        Write-Log 'Stopping splash screen.'
    }

    Write-Log "Script completed with an exit code of: $($ScriptProperties.ExitCode)"

    Write-Host "$([Environment]::NewLine) $('*' * 30) Script Complete $('*' * 30)$([Environment]::NewLine)"
    
    #Closes the transcript file.
    Stop-Transcript
    Exit $ScriptProperties.ExitCode
}
