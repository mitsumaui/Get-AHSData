# Get-AHSData

This module allows you to programmatically obtain AHS data from an HPE iLO4+ Management Processor. Useful for integrating into alerting automation, or to simplify obtaining AHS logs without the need to login to the iLO Web UI each time.

Get-AHSData
- You can specify an array of iLOs to grab from
- The Filename is automatically generated – so will create {serial}-{date}.AHS
- Places AHS in the folder specified, and returns an array of filenames. 
- Default is to get previous 1 days of AHS Data, otherwise you can specify start/end dates. 

Examples:

    $Credential = Get-Credential -Message 'iLO Credentials'
    $Files = Get-AHSData -Server 'server-ilo.local' -Credential $Credential -Folder C:\Temp 

    $Files = Get-AHSData -Server 'server-ilo.local' -Credential $Credential -Folder C:\Temp -StartDate '02/10/18'