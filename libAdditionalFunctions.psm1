#Creates shortcut 
function New-Shortcut {
	param(
	    [Parameter(Mandatory = $true)]
        [Alias('Link')]
        [String] $LinkPath,

        [Parameter(Mandatory = $true)]
        [Alias('Target')]
        [String] $TargetPath,

        [Parameter(Mandatory = $true)]
        [Alias('Icon')]
        [String] $IconPath,

        [Alias('Arg')]
        [String] $Arguments,

        [Alias('Description')]
        [String] $Desc,

        [Alias('Working')]
        [String] $WorkingPath,

        [Alias('HotKey')]
        [String] $HotKeySet
	)

	Write-Log 'Creating Shortcut' -Header

	$Ext = [System.IO.Path]::GetExtension($LinkPath)
	if($Ext -ne '.lnk') {
		Write-Log "Bad Link Path $LinkPath"
		Write-Log "Shortcut not created" -Footer
		Exit
	}

	$shell = New-Object -ComObject WScript.Shell

	Write-Log "Shortcut at $LinkPath"
	Write-Log "Shortcut to $TargetPath"

	$shortcut = $shell.CreateShortcut($LinkPath)
	$shortcut.TargetPath = $TargetPath
	$shortcut.IconLocation = $IconPath
	if($Arguments -ne $null) { $shortcut.Arguments = $Arguments }
	if($Desc -ne $null) { $shortcut.Description = $Desc }
	if($WorkingPath -ne $null) { $shortcut.WorkingDirectory = $WorkingPath }
	if($HotKeySet -ne $null) { $shortcut.HotKey = $HotKeySet }
	
	$shortcut.Save()

	Write-Log 'Shortcut Created' -Footer
}

function Get-ExeTargetMachine
{
    <#
    .SYNOPSIS Displays the machine type of any Windows executable.
     
    .DESCRIPTION
        Displays the target machine type of any Windows executable file (.exe or .dll).
        The expected usage is to determine if an executable is 32- or 64-bit, in which case it will return "x86" or "x64", respectively.
        However, all machine types that were known as of the date of this script's authoring are detected.
         
    .PARAMETER Path
        A string that contains the path to the file to be checked. Can be relative or absolute.
     
    .PARAMETER IncludeFileName
        If set, includes the file name in the displayed output.
         
    .PARAMETER IgnoreInvalidFiles
        Silently skips 16-bit or non-executable files.
         
    .PARAMETER SuppressErrors
        Errors (except invalid path) are not reported.
        Warnings about 16-bit and non-PE files are still reported; use IgnoreInvalidFiles to suppress.
         
    .LINK
        http://msdn.microsoft.com/en-us/windows/hardware/gg463119.aspx
        https://etechgoodness.wordpress.com/2014/12/11/powershell-determine-if-an-exe-is-32-or-64-bit-and-other-tricks/
         
    .OUTPUTS
        If IncludeFileName is not specified, outputs a custom object with a TargetMachine property that contains a string with the executable's target machine type.
        If IncludeFileName is specified, outputs a custom object with a Path property that contains the full path of the executable's name and a TargetMachine property that contains a string with the executable's target machine type.
         
    .NOTES
        Author: Eric Siron
        Copyright: (C) 2014 Eric Siron
        Version 1.0.1 November 3, 2015 Modified non-EXE handling to return as soon as further processing is unnecessary
        Version 1.0 Authored Date: December 10, 2014
     
    .EXAMPLE PS C:\> Get-ExeTargetMachine C:\Windows\bfsvc.exe
         
        Description
        -----------
        Returns a TargetMachine of x64
    .EXAMPLE
        PS C:\> Get-ExeTargetMachine C:\Windows\winhlp32.exe
         
        Description
        -----------
        Returns a TargetMachine of x86
    .EXAMPLE
        PS C:\> Get-ChildItem 'C:\Program Files (x86)\*.exe' -Recurse | Get-ExeTargetMachine -IncludeFileName
         
        Description
        -----------
        Returns the TargetMachine of all EXE files under C:\Program Files (x86) and all subfolders, displaying their complete path names along with their machine type.
    .EXAMPLE
        PS C:\> Get-ChildItem 'C:\Program Files\*.exe' -Recurse | Get-ExeTargetMachine -IncludeFileName | where { $_.TargetMachine -ne "x64" }
         
        Description
        -----------
        Returns the Path and TargetMachine of all EXE files under C:\Program Files and all subfolders that are not 64-bit (x64).
    .EXAMPLE
        PS C:\> Get-ChildItem 'C:\windows\*.exe' -Recurse | Get-ExeTargetMachine | where { $_.TargetMachine -eq "" }
         
        Description
        -----------
        Shows only errors and warnings for the EXE files under C:\Windows and subfolders. This can be used to find 16-bit and other EXEs that don't conform to the portable executable standard.
         
    .EXAMPLE
        PS C:\> Get-ChildItem 'C:\Program Files\' -Recurse | Get-ExeTargetMachine -IncludeFileName -IgnoreInvalidFiles -SuppressErrors | Out-GridView
         
        Description
        -----------
        Finds every file in C:\Program Files and subfolders with a portable executable header, regardless of extension, and displays their names and Target Machine in a grid view.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=1, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias("FullName")][String]$Path,
        [Parameter()][Switch]$IncludeFileName = $false,
        [Parameter()][Switch]$IgnoreInvalidFiles = $false,
        [Parameter()][Switch]$SuppressErrors = $false
    )
    BEGIN {
        ## Constants ##
        New-Variable -Name PEHeaderOffsetLocation -Option Constant -Value 0x3c
        New-Variable -Name PEHeaderOffsetLocationNumBytes -Option Constant -Value 2
        New-Variable -Name PESignatureNumBytes -Option Constant -Value 4
        New-Variable -Name MachineTypeNumBytes -Option Constant -Value 2
         
        ## Globals ##
        $NonStandardExeFound = $false
    }
 
    PROCESS {
        $Path = (Get-Item -Path $Path -ErrorAction Stop).FullName
        try
        {
            $PEHeaderOffset = New-Object Byte[] $PEHeaderOffsetLocationNumBytes
            $PESignature = New-Object Byte[] $PESignatureNumBytes
            $MachineType = New-Object Byte[] $MachineTypeNumBytes
             
            Write-Verbose "Opening $Path for reading."
            try
            {
                $FileStream = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            }
            catch
            {
                if($SuppressErrors)
                {
                    return
                }
                throw $_    #implicit 'else'
            }
             
            Write-Verbose "Moving to the header location expected to contain the location of the PE (portable executable) header."
            $FileStream.Position = $PEHeaderOffsetLocation
            $BytesRead = $FileStream.Read($PEHeaderOffset, 0, $PEHeaderOffsetLocationNumBytes)
            if($BytesRead -eq 0)
            {
                if($SuppressErrors)
                {
                    return
                }
                throw "$Path is not the correct format (PE header location not found)."    #implicit 'else'
            }
            Write-Verbose "Moving to the indicated position of the PE header."
            $FileStream.Position = [System.BitConverter]::ToUInt16($PEHeaderOffset, 0)
            Write-Verbose "Reading the PE signature."
            $BytesRead = $FileStream.Read($PESignature, 0, $PESignatureNumBytes)
            if($BytesRead -ne $PESignatureNumBytes)
            {
                if($IgnoreInvalidFiles)
                {
                    return
                }
                throw("$Path is not the correct format (PE Signature is an incorrect size).")    # implicit 'else'
            }
            Write-Verbose "Verifying the contents of the PE signature (must be characters `"P`" and `"E`" followed by two null characters)."
            if(-not($PESignature[0] -eq [Char]'P' -and $PESignature[1] -eq [Char]'E' -and $PESignature[2] -eq 0 -and $PESignature[3] -eq 0))
            {
                if(-not($IgnoreInvalidFiles))
                {
                    Write-Warning "$Path is 16-bit or is not a Windows executable."
                }
                return                
 
            }
            Write-Verbose "Retrieving machine type."
            $BytesRead = $FileStream.Read($MachineType, 0, $MachineTypeNumBytes)
            if($BytesRead -ne $MachineTypeNumBytes)
            {
                if($SuppressErrors)
                {
                    return
                }
                throw "$Path appears damaged (Machine Type not correct size)."    # implicit 'else'
            }
            $RawMachineType = [System.BitConverter]::ToUInt16($MachineType, 0)
            $TargetMachine = switch ($RawMachineType)
            {
                0x0        { 'Unknown' }
                0x1d3        { 'Matsushita AM33' }
                0x8664    { 'x64' }
                0x1c0        { 'ARM little endian' }
                0x1c4        { 'ARMv7 (or higher) thumb mode only' }
                0xaa64    { 'ARMv8 in 64-bit mode' }
                0xebc        { 'EFI byte code' }
                0x14c        { 'x86' }
                0x200        { 'Itanium 64 bit' }
                0x9041    { 'Mitsubishi M32R little endian' }
                0x266        { 'MIPS16' }
                0x366        { 'MIPS with FPU' }
                0x466        { 'MIPS16 with FPU' }
                0x1f0        { 'PowerPC little endian' }
                0x1f1        { 'PowerPC with floating point support' }
                0x166        { 'MIPS little endian' }
                0x1a2        { 'Hitachi SH3' }
                0x1a3        { 'Hitachi SH3 DSP' }
                0x1a6        { 'Hitachi SH4' }
                0x1a8        { 'Hitachi SH5' }
                0x1c2        { 'ARM or Thumb ("interworking")' }
                0x169        { 'MIPS little endian WCE v2' }
                default {
                    $NonStandardExeFound = $true
                    "{0:X0}" -f $RawMachineType
                }
            }
            $Output = New-Object PSCustomObject
            if($IncludeFileName)
            {
                Add-Member -InputObject $Output -MemberType NoteProperty -Name Path -Value $Path
            }
            Add-Member -InputObject $Output -MemberType NoteProperty -Name TargetMachine -Value $TargetMachine
            $Output
        }
        catch
        {
            # the real purpose of the outer try/catch is to ensure that any file streams are properly closed. pass errors through
            Write-Error $_
        }
        finally
        {
            if($FileStream)
            {
                $FileStream.Close()
            }
        }
    }
 
    END {
        if($NonStandardExeFound)
        {
            Write-Warning -Message "Executable found with an unknown target machine type. Please refer to section 2.3.1 of the Microsoft documentation (http://msdn.microsoft.com/en-us/windows/hardware/gg463119.aspx)."
        }
    }
}

function New-EmailTemplate {
    param(
        [Parameter(Mandatory=$true)]
        [Alias('To')]
        [String] $toField,

        [Alias('Subject')]
        [String] $subjectField,

        [Parameter(Mandatory=$true)]
        [Alias('Body')]
        [String] $emailBody,

        [Alias('Attachment')]
        [System.Net.Mail.Attachment] $emailAttachment,

        [Alias('Bcc')]
        [String] $bccField,        

        [Alias('BodyAsHtml')]
        [Switch] $isBodyHtml,

        [Alias('From')]
        [String] $fromField
    )

    $message = New-Object Net.Mail.MailMessage

    if ($isBodyHtml) {
        $message.IsBodyHtml = $true
    }
    
    $message.To.Add($toField)
    $message.Subject = $subjectField
    $message.Body = $emailBody
    $message.From = $fromField
    $message.ReplyTo = $fromField

    if (-not($emailAttachment -eq $null)) {
        $message.Attachments.Add($emailAttachment)
    }

    if (-not([String]::IsNullOrWhiteSpace($bccField))) {
        $message.Bcc.Add($bccField)
    }

    return $message
}


function New-InlineAttachment {
    param(
        [Parameter(Mandatory=$true)]
        [Alias('Path')]
        [String] $filePath,

        [Parameter(Mandatory=$true)]
        [Alias('MediaType')]
        [String] $attachmentMediaType
    )
    
    $attachment = Get-ChildItem $filePath

    $mailAttachment = New-Object System.Net.Mail.Attachment -ArgumentList $filePath

    $mailAttachment.ContentDisposition.Inline = $True
    $mailAttachment.ContentDisposition.DispositionType = 'Inline'
    $mailAttachment.ContentType.MediaType = $attachmentMediaType
    $mailAttachment.ContentId = $attachment.Name

    return $mailAttachment
}


function Send-Email {
    param(
        [Parameter(Mandatory=$true)]
        [Alias('SmtpServer')]
        [String] $mailServer,

        [Parameter(Mandatory=$true)]
        [Alias('Email')]
        [Net.Mail.MailMessage] $mailMessage
    )

    $smtp = New-Object Net.Mail.SmtpClient($mailServer)
    $smtp.Send($mailMessage)
}
