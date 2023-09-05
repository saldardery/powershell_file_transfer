# Script to download MR release bits from ftpsite.vmware.com.
# File list json is the same json for uploading files.
# Author: Ken Gould - kengould@vmware.com
# v5.1

# Change log:
# 2023-01-31    Replaced MR3.0 with MR3.1
# 2022-10-18    Enhanced 'All files' download options to first check for presence of local file. If local file is found, checksum is compared.
#               If local file is found with matching checksum, file download is skipped.
# 2022-10-13    Enhanced Download Server Access test to be a more accurate test of HTTP protocol instead of ICMP
#               Removed misleading references to FTP Access when download protocol is actually HTTP
#               Moved Windows Version test to be more obvious
# 2022-08-04    Added version choice menu
#               Ensured that downloaded files are sent to an MR specific folder
# 2022-08-03    Added support for extras file type. Downloadable via option 4.
#               Added Windows 2019 version check when on windows
# 2022-04-04    Initial v1.1 added httpLinksOutput Option 5 (hidden)
# 2022-04-03    Initial v1.0 to be used for MR1/MR2 bits based on user question

#internal variables
$Global:CheckSumReport = @()
$Global:baseURL="http://ftpsite.vmware.com/download/vcf/migration_bundles/v3.x_to_4.x"
$Global:fileList = "vcf_transition_file_list.json"
$Global:detectedOSPlatform = [System.Environment]::OSVersion.Platform
$Global:detectedOSVersion = [System.Environment]::OSVersion.Version.Major

Function anyKey 
{
    Write-Host ''; Write-Host -Object 'Press any key to continue/return to menu...' -ForegroundColor Yellow; Write-Host '';

	if($headlessPassed){
		$response = Read-Host 
		}
	else{
		$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
	}
}

Function Test-DownloadServerAccess
{
    Param (
        [Parameter (Mandatory = $true)] [String]$Url
    )
    try
    {
        (Invoke-WebRequest -Uri $Url -UseBasicParsing -DisableKeepAlive).StatusCode
    }
    catch [Net.WebException]
    {
        [int]$_.Exception.Response.StatusCode
    }
}

Function New-AllFilesObject
{
    $filesObject=@()
    $fileindex = 1
    Foreach ($category in "assessment","tools","commonBundles","migrationBundles","vsrnBundles","vxrailBundles","documentation","extras")
    {
        Foreach ($file in $fileListJSON.$($category).files)
        {
            If ($file.fileName)
            {
                If (($category -eq "commonBundles") -OR ($category -eq "vsrnBundles"))
                {
                    $extensionList = @(".manifest",".manifest.sig",".tar")
                    Foreach ($fileExtension in $extensionList)
                    {
                        $checkSumProperty = ($fileExtension -replace '[.]')+"chkSum"
                        $filesObject += [pscustomobject]@{
                            'Num'    = $fileindex
                            'FileName' = $file.filename+$fileExtension
                            'Category' = $category
                            'Chksum'   = $file.$checkSumProperty    
                            'Folder'   = "bundles"
                            'Comments'  = $file.comments
                        }
                        $fileindex++
                    }
                }
                elseif (($category -eq "migrationBundles") -OR ($category -eq "vxrailBundles"))
                {
                    $filesObject += [pscustomobject]@{
                        'Num'    = $fileindex
                        'FileName' = $file.fileName
                        'Category' = $category
                        'Chksum'   = $file.chksum
                        'Folder'   = "bundles"
                        'Comments'  = $file.comments
                    }
                    $fileindex++
                }
                else
                {
                    $filesObject += [pscustomobject]@{
                        'Num'    = $fileindex
                        'FileName' = $file.fileName
                        'Category' = $category
                        'Chksum'   = $file.chksum
                        'Folder'   = $category
                        'Comments'  = $file.comments
                    }
                    $fileindex++
                }
            }
        }
    }
    $Global:allFilesObject = $filesObject
}

Function Get-MRBundleFileList
{
    $Global:downloadServerAccess = Test-DownloadServerAccess -url $($baseURL+"/"+$mrVersion)
    If ($downloadServerAccess -eq "403")
    {
        If (Test-Path -path $fileList) {Remove-Item $fileList -confirm:$false | Out-Null}
        $url=$baseURL+"/"+$mrVersion+"/"+$fileList
        Get-TransitionFile -source $url -destination ("./"+$mrVersion+"/"+$fileList) -silent
    }
    else
    {
        Write-Host "Unable to contact the download server. Please ensure HTTP access to $baseURL/$mrVersion is possible " -ForegroundColor Red
        Exit
    }
    Try
    {
        $Global:fileListJSON = Get-Content ("./"+$mrVersion+"/"+$fileList) | ConvertFrom-Json -ErrorAction SilentlyContinue
        IF ($fileListJSON.version -eq $mrVersion)
        {   
            Write-Host "Successfully sourced the $mrVersion FileList JSON" -ForegroundColor Green
        }
        else
        {
            Write-Host "$mrVersion FileList JSON sourced does not match the MR version chosen. Please verify and try again" -ForegroundColor Red
            Exit
        }
    }
    Catch
    {
        Write-Host "$mrVersion FileList JSON sourced is not a valid JSON file. Please verify and try again" -ForegroundColor Red
        Exit
    }
}

Function Get-TransitionFile 
{
    Param (
        [Parameter (Mandatory = $true)] [String]$source,
        [Parameter (Mandatory = $true)] [String]$destination,
        [Parameter (Mandatory = $false)] [Switch]$silent
    )
    Try
    {
        If ($detectedOSPlatform -eq 'Win32NT')
        {
            If ($detectedOSVersion -lt 10)
            {
                Write-Host "Windows system pre Windows 2019 detected. May require manual install of true 'curl.exe' (i.e. not the PowerShell alias for Invoke-WebRequest) to operate correctly. " -ForegroundColor Yellow
            }
            $fileSizeResponse = (curl.exe -sI $source | select-string "Content-Length") -split (" ")
        }
        else
        {
            $fileSizeResponse = (curl -sI $source | select-string "Content-Length") -split (" ")   
        }
        $fileSize = (($fileSizeResponse[1]/1MB).ToString(".000")) + "MB"
        If (!$silent)
        {
            Write-Host "Getting " -nonewline -ForegroundColor Yellow
            Write-Host $source.split("/")[-1] -ForegroundColor White -nonewline
            Write-Host " ($fileSize)" -ForegroundColor Yellow
            $StopWatch = New-Object -TypeName System.Diagnostics.Stopwatch
            If ($detectedOSPlatform -eq 'Win32NT')
            {
                $StopWatch.Start(); curl.exe -# -o $destination $source; $StopWatch.Stop()
            }
            else
            {
                $StopWatch.Start(); curl -# -o $destination $source; $StopWatch.Stop()
            }
            Write-Host "Download complete: $($Stopwatch.Elapsed.Minutes) mins/$($StopWatch.Elapsed.seconds) secs/$($StopWatch.Elapsed.milliseconds) milliseconds" -ForegroundColor Green
        }
        else
        {
            If ($detectedOSPlatform -eq 'Win32NT')
            {
                curl.exe -s -o $destination $source
            }
            else
            {
                curl -s -o $destination $source
            }
        }
    }
    Catch
    {
        Write-Host $_.Exception.Message
    }
}

Function Get-FileMD5
{
	Param (
        [Parameter (Mandatory = $true)] [String]$path,
		[Parameter (Mandatory = $true)] [String]$knownChkSum
    )
	Write-Host "Validating Checksum for " -ForegroundColor Yellow -nonewline
    Write-Host "$($path.split("/")[-1]):" -ForegroundColor White -nonewline
    
    $fileMD5Hash = (Get-FileHash -Algorithm MD5 -Path $path).hash
    IF ($fileMD5Hash -eq $knownChkSum)
	{
		Write-Host " Checksum Valid" -ForegroundColor Green
		$checkSumValid = "[MATCH] Checksum is good for: "
	}
	else
	{
		Write-Host " Checksum Not Valid" -ForegroundColor Red
		$checkSumValid = "[ERROR] Checksum does not match for: "
	}
    Write-Host ""
	[array]$Global:CheckSumReport += "$checkSumValid $path"
}

Function Get-VCFTransitionFile
{
    Param (
        [Parameter (Mandatory = $true)] [String]$category
    )
    If ($category -eq "tools")
    { $message = "Downloading `'$category`' Files"}
    else
    { $message = "`nDownloading `'$category`' Files"}
    Write-Host $message -ForegroundColor Cyan
    $seperator = ""
    For ($i = 0; $i -le ($message.length + 1); $i++) {
        $seperator = $seperator + '-'
    }
    Write-Host $seperator -ForegroundColor Cyan
    $filesInCategory = $allFilesObject | where-object {$_.category -eq $category}
    Foreach ($file in $filesInCategory)
    {
        $localFile = ($PSScriptRoot+"/"+$mrVersion+"/"+$file.folder+"/"+$file.filename)
        $localFileExists = Test-Path -path $localFile
        If ($localFileExists)
        {
            Write-Host "Existing File " -nonewline -ForegroundColor Yellow
            Write-Host $file.filename -nonewline -ForegroundColor White
            Write-Host " found. Validating checksum." -ForegroundColor Yellow
            $fileMD5Hash = (Get-FileHash -Algorithm MD5 -Path $localFile).hash
            If ($fileMD5Hash -ne $file.chkSum)
            {
                Write-Host "Checksum does not match. Attempting redownload." -ForegroundColor Red
            }
        }
        If ((!$localFileExists) -or ($fileMD5Hash -ne $file.chkSum))
        {
                $url=$baseURL+"/"+$mrVersion+"/"+$file.folder+"/"+$file.filename
                Get-TransitionFile -source $url -destination $localFile
                Get-FileMD5 -path $localFile -knownChkSum $file.chkSum

        }
        else 
        {
            Write-Host "Checksum matches. Skipping download." -ForegroundColor Green              
        }
    }
}

Function Get-CommonDownloads
{
    Get-VCFTransitionFile -category 'tools'
    Get-VCFTransitionFile -category 'documentation'
    Get-VCFTransitionFile -category 'migrationBundles'
    Get-VCFTransitionFile -category 'commonBundles'
}

Function outputCheckSumReport
{
    $CheckSumReport
    $CheckSumReport | Add-Content -path $PSScriptRoot"\CheckSumReport.txt"
}

Function downloadSpecificFile
{    
    Write-Host "Download Specific File" -ForegroundColor cyan
    Write-Host "-----------------------" -ForegroundColor cyan
    $allFilesObject | format-table -Property num,fileName,category,comments -autosize | Out-String | ForEach-Object { $_.Trim("`r","`n") } 
    Write-Host ""; Write-Host "Enter File Number you wish to download, or C to Cancel: " -ForegroundColor Yellow -nonewline
    $selection = Read-Host
    Write-Host ""
    If ($selection -ne 'C')
    {
        $selectedFile = $allFilesObject | where-object {$_.num -eq $selection}
        $message = "Downloading $($selectedFile.fileName)"
        Write-Host $message -ForegroundColor Cyan
        $seperator = ""
        For ($i = 0; $i -le ($message.length + 1); $i++) {
            $seperator = $seperator + '-'
        }
        Write-Host $seperator -ForegroundColor Cyan

        If ($selectedFile.category -in "commonBundles","vsrnBundles","migrationBundles","vxrailBundles")
        {
            $folder="bundles"
        }
        else
        {
            $folder=$selectedFile.category
        }
        $localFile = ($PSScriptRoot+"/"+$mrVersion+"/"+$folder+"/"+$selectedFile.filename)
        $url=$baseURL+"/"+$mrVersion+"/"+$folder+"/"+$selectedFile.filename
        Get-TransitionFile -source $url -destination $localFile
        Get-FileMD5 -path $localFile -knownChkSum $selectedFile.chkSum
    }
    else
    {
        DownloadMenu
    }

}

Function VersionMenu
{

    Do {
        Clear-Host     
        Write-Host ""; Write-Host -Object " VCF 3x to 4x Transition Download Utility" -ForegroundColor Cyan
        Write-Host -Object " Choose Migration Coordinator Version" -ForegroundColor Yellow      
        Write-Host -Object " 1. MR3.2" -ForegroundColor White
        Write-Host -Object " 2. MR3.1" -ForegroundColor White
		Write-Host -Object " 3. MR2.0-Patch01" -ForegroundColor White        
        Write-Host -Object ""
        Write-Host -Object " Q. Press Q to Quit" -ForegroundColor Cyan;
        Write-Host -Object $errout
        $MenuInput = Read-Host -Prompt ' (1-2 or Q)'
        $MenuInput = $MenuInput -replace "`t|`n|`r",""
        Switch ($MenuInput) 
        {
			1
            {
                $Global:mrVersion = "MR3.2"
                New-LocalFolders
                Get-MRBundleFileList
                New-AllFilesObject
                DownloadMenu
            }
            2
            {
                $Global:mrVersion = "MR3.1"
                New-LocalFolders
                Get-MRBundleFileList
                New-AllFilesObject
                DownloadMenu
            }  
            3
            {
                $Global:mrVersion = "MR2.0-Patch01"
                New-LocalFolders
                Get-MRBundleFileList
                New-AllFilesObject
                DownloadMenu
            }            
            Q
            {
                Exit
            }   
        }
    }
    Until ($MenuInput -eq 'q')
}

Function file_transfer
{
    Write-Host " This tool is used to transfer either all bundles or a specific file from the local machine's bundle folder to the migration artifact folder inside SDDC " -ForegroundColor Yellow
    $option= Read-Host "Select 1 for transferring all file or 2 for a specific file transfer"
    if (1 -eq $option)
    {
    $folder= "./$Global:mrVersion/bundles"
    scp.exe $folder/* vcf@10.0.0.50:/home/vcf/testfolder
    }
    elseif(2 -eq $option)
    {Write-Host "single"}
}

    

Function DownloadMenu
{

    Do {
        Clear-Host     
        Write-Host ""; Write-Host -Object " VCF 3x to 4x Transition Download Utility" -nonewline -ForegroundColor Cyan
        Write-Host -Object " (Version: $mrVersion)" -ForegroundColor Yellow
        Write-Host -Object " 1. Download Files for Ready Node System" -ForegroundColor White
        Write-Host -Object " 2. Download Files for VxRail System" -ForegroundColor White
        Write-Host -Object " 3. Download Full Stack Assessment Tool (FSAT)" -ForegroundColor White
        Write-Host -Object " 4. Download Individual Migration Files and Extras" -ForegroundColor White
        Write-Host -Object " 5. SDDC Bundle transfer" -ForegroundColor White
        Write-Host -Object ""
        Write-Host -Object " Q. Press Q to Quit" -ForegroundColor Cyan;
        Write-Host -Object $errout
        $MenuInput = Read-Host -Prompt ' (1-5 or Q)'
        $MenuInput = $MenuInput -replace "`t|`n|`r",""
        Switch ($MenuInput) 
        {
            1
            {
                Clear-Host
                Get-CommonDownloads
                Get-VCFTransitionFile -category 'vsrnBundles'
				[array]$Global:CheckSumReport += ""
                outputCheckSumReport
				anyKey
                DownloadMenu
            }
            2
            {
                Clear-Host
                Get-CommonDownloads
                Get-VCFTransitionFile -category 'vxrailBundles'
				[array]$Global:CheckSumReport += ""
				outputCheckSumReport
				anyKey
                DownloadMenu
            }
            3
            {
                Clear-Host
                Get-VCFTransitionFile -category 'assessment'
                [array]$Global:CheckSumReport += ""
				outputCheckSumReport
                anyKey
                DownloadMenu

            }
            4
            {
                Clear-Host
                downloadSpecificFile
                outputCheckSumReport
                anyKey
                DownloadMenu

            }
            5
            {
                Clear-Host
                file_transfer
                anyKey
                DownloadMenu 
            }
            6
            {
                Clear-Host
                httpLinksOutput
                Exit

            }
            Q
            {
                Exit
            }   
        }
    }
    Until ($MenuInput -eq 'q')
}

Function httpLinksOutput
{
    Write-Host "HTTP Links for Migration Bundle Files" -ForegroundColor cyan
    Write-Host "--------------------------------------" -ForegroundColor cyan
    Foreach ($file in $allFilesObject)
    {
        $url=$baseURL+"/"+$mrVersion+"/"+$file.folder+"/"+$file.filename
        Write-Host $url
    }
}

#Run
Function New-LocalFolders
{
    #Create Local Folders as Needed
    If (!(Test-Path -path ($PSScriptRoot+"/"+$mrVersion))) { New-item -type directory -path ($PSScriptRoot+"/"+$mrVersion) | Out-Null }
    If (!(Test-Path -path ($PSScriptRoot+"/"+$mrVersion+"/bundles"))) { New-item -type directory -path ($PSScriptRoot+"/"+$mrVersion+"/bundles") | Out-Null }
    If (!(Test-Path -path ($PSScriptRoot+"/"+$mrVersion+"/tools"))) { New-item -type directory -path ($PSScriptRoot+"/"+$mrVersion+"/tools") | Out-Null }
    If (!(Test-Path -path ($PSScriptRoot+"/"+$mrVersion+"/documentation"))) { New-item -type directory -path ($PSScriptRoot+"/"+$mrVersion+"/documentation") | Out-Null }
    If (!(Test-Path -path ($PSScriptRoot+"/"+$mrVersion+"/assessment"))) { New-item -type directory -path ($PSScriptRoot+"/"+$mrVersion+"/assessment") | Out-Null }
    If (!(Test-Path -path ($PSScriptRoot+"/"+$mrVersion+"/extras"))) { New-item -type directory -path ($PSScriptRoot+"/"+$mrVersion+"/extras") | Out-Null }
}

#form start of report
[array]$Global:CheckSumReport += ""
[array]$Global:CheckSumReport += "Checksum Report"
[array]$Global:CheckSumReport += "*****************"

#Test System
Clear
If ($detectedOSPlatform -eq 'Win32NT')
{
    If ($detectedOSVersion -lt 10)
    {
        Write-Host "Pre Windows 2019 system detected. You need to ensure the true 'curl.exe' (i.e. not the PowerShell alias for Invoke-WebRequest) is manually installed for this script to operate correctly. " -ForegroundColor Yellow
        anyKey
    }
}

#Start Menu
VersionMenu
