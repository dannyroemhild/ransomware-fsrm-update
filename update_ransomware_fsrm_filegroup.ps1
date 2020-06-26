<#
    .SYNOPSIS

    script is used to import and compare the Black and Whitelist txt files with existing file extensions in windows fsrm (fileserver ressource manager)

    .DESCRIPTION
    the script imports the content of txt files to fsrm. the txt files should look like the sample txt files in github.
    The  directory should be defined in variable. 
    The File Group Name is "Ransomware". If you choose another Name you can change it into in the Function "updateransomware"
     
         This Script can be implemented on a Central Task Server in a Domain

    .EXAMPLE
    -

    .Notes
    -
    this script does not create filegroup or filescreens etc.
    

    .References
    -
    Update existing File Groups in FSRM via Powershell on multiple Systems   
    https://www.frankysweb.de/windows-fileserver-vor-ransomware-crypto-locker-schuetzen/

    .ToDo:_How_do_i_run_this_script?
    -

    You need To Create a Data Group on your (FSRM) File server --> more in Referneces 
    

    To run this Script you have to run it with Local Admin Credentials of the File Server you will Add this Extentions.
    Define the Path of the extention Black- and Whitelist
    
    Place the FQDN of the Servers in the Server List like the Example given in GitHub 
    This script can Push the Extentions of Mulitple File Server you defined in the list

    ---------------------------------------------------------------------------------
                                                                                 
    Script:                   Update_Ransomware_Dateierweiterungsfilter.s1                                      
    Author:                   Danny Roemhild, Luca Kaufmann
    ModifyDate:               26.06.2020                                                       
    Usage:        
    Version:                  1.0
                                                                                  
    ---------------------------------------------------------------------------------
#>
                                           # Beginn Variables to Define
#############################################################################################

$Serverlist = "(placeyourpathhere)"+$serverlistdomain+".txt"
$PathBlacklist  = "(placeyourpathhere)\blacklist.txt"
$PathWhitelist  = "(placeyourpathhere)\Whitelist.txt"

#############################################################################################
                                           #End Variables to Define

#Beginn Variables

#Read Domain of User Account on Task Server
$serverlistdomain = $ENV:USERDOMAIN.ToLower()
# Get Serverlist
[array]$importServerlist = Get-Content -Path $Serverlist

# Get Content of Black and Whitelist
[string[]]$importBlackList = Get-Content -Path $PathBlacklist
[string[]]$importWhiteList = Get-Content -Path $PathWhitelist

# Sort and eliminate double entries
$BlackList = $importBlackList | sort -Unique
$Whitelist = $importWhiteList | sort -Unique 


#Functions

#Begin Function getransomware ###############
function getransomware() {

$Group = Get-FSRMFileGroup -Name "Ransomware"
Write-Host "In 5 Seconds all Extentions will be shown" -ForegroundColor Red
Start-Sleep -Seconds "5"
$list = $Group.IncludePattern
$listType = $Group.IncludePattern.GetType()
} ###Debugonly###
#end Function getransomware    ###############


#Beginn Function updateransomware
function updateransomware($blacklist,$whitelist) { 

#The Funktion got a Security Mechanism which denies the Push of an empty Ransomware Extention list if they where corrupted
#This Funktion only Add new Extentions and eliminate Whitelisted Extentions 

$Group = Get-FSRMFileGroup -Name "Ransomware"
$currentpattern = $Group.IncludePattern


# The loop only Add the new Extentions

foreach($CheckB in $BlackList)
{
    If($currentpattern -contains $CheckB)
    {
       Write-Host $CheckB -Foregroundcolor DarkMagenta  
    }
    else
    {
        
        Write-Host $CheckB -ForegroundColor Yellow   
        [string[]]$Pattern = $Group.IncludePattern += $CheckB
        
    } 
     
}   

$Pattern = $Pattern.Where({$_ -ne ""}) | sort -Unique
Set-FSRMFileGroup -Name "Ransomware" –IncludePattern $Pattern 

#Check Extentions Again, Filter Whitelisted  Ext. and Push Pattern List Again.

$groupnew = Get-FsrmFileGroup -Name "Ransomware"
$pat = $groupnew.IncludePattern 
$patwhitelist = @($pat).ForEach{$_}

foreach($CheckW in $whitelist)
{
    if($patwhitelist -contains $CheckW)
    {
        $patwhitelist.Remove($CheckW)
        Write-Host $CheckW "Removed" -ForegroundColor Red
    }
    else
    {
     
    }
    
}
[string[]]$patwhitelist | Sort -Unique
Set-FsrmFileGroup -Name "Ransomware" -IncludePattern $patwhitelist


}
#End Function updateransomware

#End Functions 


#Beginn Script 

#Push Script on all servers defined in the list.

foreach($server in $importServerlist){

Invoke-Command -Computername $server  -ScriptBlock ${function:updateransomware} -ArgumentList $BlackList,$Whitelist

}

#End Script