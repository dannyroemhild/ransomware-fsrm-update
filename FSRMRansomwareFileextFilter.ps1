<#
    .SYNOPSIS
    This script is used to import and compare the Blocklist on Github and your Trustlist txt file in windows fsrm (fileserver ressource manager)
    .DESCRIPTION
    The script imports the content of the git hub extensionlist 
    compares it with your Trustlist of Fileextensions 
    and pushes the compared Version to the fsrm filegroup of your Fileserver
     
    This Script can be implemented on a Central Task Server in a Domain
    .EXAMPLE
    -
    .Notes
    -
    .ToDo:_How_do_i_run_this_script?
    -
    
    - To run this Script you have to run it with credentials that have local administrative rights on the File Server you want to add the Extensions (No domain admin rights needed)
    
    - Define the Path of an extension Trustlist - in which you can define exceptions for file extensions that will never be blocked regardless if this extension is included in the blocklist at the moment or anytime in the future
    
    - Define the Admin Mail Adress so block events can be send to you for further investigation
    
    - Define an SMTP Server Adress for the aforementioned System Mails
    
    - Place the FQDN of the Server(s) you want to push the list to in the Server List like the Example given in GitHub 
    This script can push the Extensions to mulitple Fileservers you define in thi list
    The serverlist is necessary, because you can add an installed File Server and the Script automaticly creates all filegroups included The BlockRules
    
    - You just need to create the Screen manually if you only want to monitor specific Volumes on your fileserver
    You can use the optional script parameter "-ScreenAllVolumes" to automatically create an active filescreen for all volumes on your Fileserver 
        
    .References
    -Update existing File Groups in FSRM via Powershell on multiple Systems   
    https://www.frankysweb.de/windows-fileserver-vor-ransomware-crypto-locker-schuetzen/
    
    ---------------------------------------------------------------------------------
                                                                                 
    Script:                   Ransomware_Fileextentionfilter.ps1                                      
    Author:                   Danny Roemhild, Luca Kaufmann
    ModifyDate:               07.11.2020                                                       
    Usage:        
    Version:                  2.3
                                                                                  
    ---------------------------------------------------------------------------------
#>
Param(
    [Parameter(Mandatory=$False)]
    [switch]$ScreenAllVolumes
)
$localserverdomain = $ENV:USERDOMAIN.ToLower()


#defineable Variables

$AdminMailAdress = "Administrator@domain.de"
$SmtpServer ="127.0.0.1"
$PathServerList = "C:\temp\serverlist_"+$localserverdomain+".txt"
$pathTrustList = "C:\temp\TrustList.txt"

#environment

[array]$serverlist = Get-Content -Path $PathServerList


#functions

function createEventdownloadError {
  
    # Source can be customized
    if (![System.Diagnostics.EventLog]::SourceExists("File Extension Blocklist Script")) {
        New-EventLog -logname 'Ransomware Extension Filter' -Source 'File Extension Blocklist Script' 
    }
    
    # create Eventlog 
    Write-EventLog -entrytype "Information" -logname "Ransomware Extensionfilter" -eventID 1 -Source 'File Extension Blocklist Script' -Category 0  -Message "File Extensions for Ransomware Extensionfilter could not be downloaded."
    
    }



function createFSRMGroup ([string]$AdminMailAdress, [string]$SmtpServer){

$sys = Get-WmiObject -Class "Win32_ComputerSystem"
[string]$FromMail = $sys.Name+"@"+$sys.Domain


# SMTP-Settings for FSRM :
Set-FsrmSetting -SmtpServer $SmtpServer -AdminEmailAddress $AdminMailAdress -FromEmailAdress $FromMail

# New FSRM Group and create Template :
New-FsrmFileGroup -Name "Ransomware" -IncludePattern @("*.0day", "*.crypt")

$Notification = New-FsrmAction -Type Email -MailTo $AdminMailAdress -Subject "Nicht autorisierte Datei aus der Dateigruppe '[Violated File Group]' festgestellt." -Body "Vom Benutzer '[Source Io Owner]' wurde der Versuch unternommen, die Datei '[Source File Path]' unter '[File Screen Path]' auf dem Server '[Server]' zu speichern. Diese Datei befindet sich in der Dateigruppe '[Violated File Group]', die auf dem Server nicht zulässig ist."
New-FsrmFileScreenTemplate -Name "Ransomware" -IncludeGroup "Ransomware" -Notification $Notification -Active
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

function autocheckVolumescreateScreen()
{
    function createEventScreenVolume ($Volume) 
        {
  
            # Source can be custimized
            if (![System.Diagnostics.EventLog]::SourceExists("File Extension Blocklist Script")) {
                New-EventLog -logname 'Ransomware Extensionfilter' -Source 'File Extension Blocklist Script' 
            }
            #Create Message
            $Message = "Created FSRM Ransomware Screen for Volume: " + $Volume 
            # create Eventlog 
            Write-EventLog -entrytype "Information" -logname "Ransomware Extensionfilter" -eventID 1 -Source 'File Extension Blocklist Script' -Category 0  -Message $Message
    
        }


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
            createEventScreenVolume -Volume $Drive
            
        }
    }

}


function updateransomware($Blocklist,$Trustlist) { 

$Group = Get-FSRMFileGroup -Name "Ransomware"
$currentpattern = $Group.IncludePattern

foreach($new in $Blocklist)
{
    If($currentpattern -notcontains $new)
    {
        Write-Host $new -ForegroundColor Black
       $Pattern = $Group.IncludePattern += $new
    }

}   
$Pattern = $Pattern.Where({$_ -ne ""}) | Sort-Object -Unique
$currentpattern = @($Pattern).ForEach{$_}

foreach($trust in $Trustlist)
{
    if($currentpattern -contains $trust)
    {
        Write-Host $trust -ForegroundColor Red
        $currentpattern.Remove($trust)
        
    }
    
}

Set-FsrmFileGroup -Name "Ransomware" -IncludePattern $currentpattern


}

#Beginn Script
   
    try {
        $download = Invoke-WebRequest https://raw.githubusercontent.com/dannyroemhild/ransomware-fileext-list/master/fileextlist.txt -UseBasicParsing
    } catch {
        
        createEventdownloadError
        break
    }
    
    $BlockList = ($download).content -split "`n"
    $TrustList = Get-Content -Path $pathTrustList
        

foreach($server in $serverlist)
{

$checkforFSRMGroup = checkFSRMGroupRansomware $server

while ($checkforFSRMGroup -eq $false) {

    Invoke-Command -ComputerName $server -ScriptBlock ${function:createFSRMGroup} -ArgumentList $AdminMailAdress,$SmtpServer
    Start-Sleep -Seconds 3
    $checkforFSRMGroup = checkFSRMGroupRansomware $server
    } 
if ($ScreenAllVolumes -eq $true) 
{
    Invoke-Command -ComputerName $server -ScriptBlock ${function:autocheckVolumescreateScreen}
}



Invoke-Command -ComputerName $server -ScriptBlock ${function:updateransomware} -ArgumentList $BlockList,$TrustList

}
#End Script
