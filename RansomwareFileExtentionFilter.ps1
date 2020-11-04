<#
    .SYNOPSIS
    script is used to import and compare the Blocklist on Github and your Trustlist txt file  extensions in windows fsrm (fileserver ressource manager)
    .DESCRIPTION
    The script imports the content of the git hub extentionlist  compares it with your Trustlist of Fileextentions 
    and push the compared Version to the fsrm filegroup of your Fileserver
     
         This Script can be implemented on a Central Task Server in a Domain
    .EXAMPLE
    -
    .Notes
    -

    .ToDo:_How_do_i_run_this_script?
    -
    
    To run this Script you have to run it with Local Admin Credentials of the File Server you will Add this Extentions.
    Define the Path of the extention Trustlist
    
    Place the FQDN of the Servers in the Server List like the Example given in GitHub 
    This script can Push the Extentions of Mulitple File Server you defined in the list
    The ServerList is necessary, because you can add an installed File Server and the Script automaticly creates all filegroups included The BlockRules.
    You just need to create the Screen
    With the Switch Parameter "-ScreenAllVolumes" you can Define if all your volumes on your Fileserver should get automaticly 
    a Active File Screen
    
    
    .References
    -Update existing File Groups in FSRM via Powershell on multiple Systems   
    https://www.frankysweb.de/windows-fileserver-vor-ransomware-crypto-locker-schuetzen/
    
    ---------------------------------------------------------------------------------
                                                                                 
    Script:                   Ransomware_Fileextentionfilter.ps1                                      
    Author:                   Danny Roemhild, Luca Kaufmann
    ModifyDate:               04.11.2020                                                       
    Usage:        
    Version:                  2.0
                                                                                  
    ---------------------------------------------------------------------------------
#>
Param(
    [Parameter(Mandatory=$True)]
    [switch]$ScreenAllVolumes
)



#Defineable Variable

$AdminMailAdress = "Administrator@domain.de"
$SmtpServer ="127.0.0.1"
$PathServerList = "\\DEFINEHEREYOUREPATH\serverlist_"+$localserverdomain+".txt"
$pathTrustList = "C:\temp\TrustList.txt"

#Environment

$localserverdomain = $ENV:USERDOMAIN.ToLower()
[array]$serverlist = Get-Content -Path $PathServerList


#funktions

function createEventdownloadError {
  
    # Source can be custimized
    if (![System.Diagnostics.EventLog]::SourceExists("File Extention Script")) {
        New-EventLog -logname 'Ransomware Extentionfilter' -Source 'File Extention Script'
    }
    
    # create Eventlog 
    Write-EventLog -entrytype "Information" -logname "Ransomware Extentionfilter" -eventID 1 -Source 'File Extention Script' -Category 0  -Message "File Extentions for Ransomware Extentionfilter cannot be downloaded"
    
    }

function createFSRMGroup ([string]$AdminMailAdress, [string]$SmtpServer){
    
# SMTP-Settings for FSRM :
Set-FsrmSetting -SmtpServer $SmtpServer -AdminEmailAddress $AdminMailAdress

# New FSRM Group and create Template :
New-FsrmFileGroup -Name "Ransomware" –IncludePattern @("*.0day", "*.crypt")

$Notification = New-FsrmAction -Type Email -MailTo $AdminMailAdress -Subject "Nicht autorisierte Datei aus der Dateigruppe '[Violated File Group]' festgestellt." -Body "Vom Benutzer '[Source Io Owner]' wurde der Versuch unternommen, die Datei '[Source File Path]' unter '[File Screen Path]' auf dem Server '[Server]' zu speichern. Diese Datei befindet sich in der Dateigruppe '[Violated File Group]', die auf dem Server nicht zulässig ist."
New-FsrmFileScreenTemplate -Name "Ransomware" –IncludeGroup "Ransomware" -Notification $Notification -Active
}

function checkFSRMGroupRansomware($server)
{
$Check = Invoke-Command -ComputerName $server -ScriptBlock {Get-FsrmFileGroup -Name "Ransomware"}

if($Check.Name -eq "Ransomware")
{
    return $true

}
else
{
    return $false
}


}
function autocheckVolumescreateScreen
{
    $Volumes = Get-Partition | Where-Object {$_.DiskNumber -ne 0} | Select-Object DriveLetter
    [System.Collections.ArrayList]$Drives = @()
    foreach ($Volume in $Volumes)
    {
        [string]$Drive = $Volume.DriveLetter+":"+"\"
        $Drives.Add($Drive)


    }

    foreach($Drive in $Drives)
    {
        $GetScreen = Get-FSRMFileScreen -Path $Drive -ErrorAction Ignore
        if ($? -eq $false) 
        {
            New-FSRMFileScreen -Path $Drive -Template "Ransomware"
            
        }
    }

}



}

    #Beginn Script

    try {
        $download = Invoke-WebRequest https://raw.githubusercontent.com/dannyroemhild/ransomware-fileext-list/master/fileextlist.txt
    } catch {
        
        createEventdownloadError
        break
    }
    
    $blockList = ($download).content -split "`n"
    $TrustList = Get-Content -Path $pathTrustList
    $blockList | foreach {
                            if ($TrustList -notcontains $_) 
                            { 
                                [array]$newlist += $_
                            }        
                         }



foreach($server in $serverlist)
{

$checkforFSRMGroup = checkFSRMGroupRansomware $server

while ($checkforFSRMGroup -eq $false) {

    Invoke-Command -ComputerName $server -ScriptBlock ${function:createFSRMGroup} -ArgumentList $AdminMailAdress,$SmtpServer
    Start-Sleep -Seconds 3
    $checkforFSRMGroup = checkFSRMGroupRansomware $server
    } 
if (ScreenAllVolumes -eq $true) 
{
    Invoke-Command -ComputerName $server -ScriptBlock ${function:autocheckVolumescreateScreen}
}

Invoke-Command -ComputerName $server -ScriptBlock {Set-FsrmFileGroup -Name "Ransomware" -IncludePattern $newlist}

}
#End Script