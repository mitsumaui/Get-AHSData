function New-TrustAllWebClient {
    <#
      Source for New-TrustAllWebClient is found at http://poshcode.org/624
      Use is governed by the Creative Commons "No Rights Reserved" license 
      and is considered public domain see http://creativecommons.org/publicdomain/zero/1.0/legalcode 
      published by Stephen Campbell of Marchview Consultants Ltd. 
    #>

    <# Create a compilation environment #>    
   $Provider=New-Object Microsoft.CSharp.CSharpCodeProvider
   $Compiler=$Provider.CreateCompiler()
   $Params=New-Object System.CodeDom.Compiler.CompilerParameters
   $Params.GenerateExecutable=$False
   $Params.GenerateInMemory=$True
   $Params.IncludeDebugInformation=$False
   $Params.ReferencedAssemblies.Add('System.DLL') > $null
   $TASource=@'
namespace Local.ToolkitExtensions.Net.CertificatePolicy {
   public class TrustAll : System.Net.ICertificatePolicy {
       public TrustAll() { 
       }
       public bool CheckValidationResult(System.Net.ServicePoint sp,
           System.Security.Cryptography.X509Certificates.X509Certificate cert, 
           System.Net.WebRequest req, int problem) {
           return true;
       }
   }
}
'@ 

   $TAResults=$Provider.CompileAssemblyFromSource($Params,$TASource)
   $TAAssembly=$TAResults.CompiledAssembly

   <# We now create an instance of the TrustAll and attach it to the ServicePointManager #>
   $TrustAll=$TAAssembly.CreateInstance('Local.ToolkitExtensions.Net.CertificatePolicy.TrustAll')
   [System.Net.ServicePointManager]::CertificatePolicy=$TrustAll

   <# The ESX Upload requires the Preauthenticate value to be true which is not the default
      for the System.Net.WebClient class which has very simple-to-use downloadFile and uploadfile
      methods.  We create an override class which simply sets that Preauthenticate value.
      After creating an instance of the Local.ToolkitExtensions.Net.WebClient class, we use it just
      like the standard WebClient class.
   #>
   $WCSource=@'
namespace Local.ToolkitExtensions.Net { 
       class WebClient : System.Net.WebClient {
       protected override System.Net.WebRequest GetWebRequest(System.Uri uri) {
           System.Net.WebRequest webRequest = base.GetWebRequest(uri);
           webRequest.PreAuthenticate = true;
           webRequest.Timeout = 10000;
           return webRequest;
       }
   }
}
'@
   $WCResults=$Provider.CompileAssemblyFromSource($Params,$WCSource)
   $WCAssembly=$WCResults.CompiledAssembly

   <# Now return the custom WebClient. It behaves almost like a normal WebClient. #>
   $WebClient=$WCAssembly.CreateInstance('Local.ToolkitExtensions.Net.WebClient')
   return $WebClient
}

<#
   .Synopsis
   Download AHS data from HPE iLO
   .DESCRIPTION
   Download AHS data from HPE iLO 4+ for troubleshooting H/W with HPE Support
   .EXAMPLE
   Get-AHSData -Server 'myilo.local' -Credential $MyCredential 
   .EXAMPLE
   Another example of how to use this cmdlet
#>
function Get-AHSData
{
 [CmdletBinding()]
 [Alias()]
 [OutputType([System.IO.FileInfo])]
 Param
 (
   # DNS/IP Address of iLO to connect to
   [Parameter(Mandatory=$true,
       ValueFromPipelineByPropertyName=$true,
   Position=0)]
   [string[]]$Server,

   # Credential to use to authenticate against iLO
   [Parameter(Mandatory=$true,
       ValueFromPipelineByPropertyName=$false,
   Position=1)]
   [System.Management.Automation.PSCredential]$Credential,
       
   # Start Date for iLO Logs - Default -1 Day from current date
   [Parameter(Mandatory=$false,
       ValueFromPipelineByPropertyName=$false,
   Position=2)]
   [System.DateTime]$StartDate = (Get-Date).AddDays(-1),
           
   # End Date for iLO Logs - Default today
   [Parameter(Mandatory=$false,
       ValueFromPipelineByPropertyName=$false,
   Position=3)]
   [System.DateTime]$EndDate = (Get-Date),
   
   # Location for AHS file(s) to be saved
   [Parameter(Mandatory=$true,
       ValueFromPipelineByPropertyName=$false,
   Position=4)]
   [string]$Folder        
 )

 Begin
 {  
   # Convert Dates to format required by iLO    
   Write-Verbose '[Get-AHSData] Converting Dates to iLO Format'
   $AHSStart = $StartDate.ToString('yyyy-MM-dd')
   $AHSEnd = $EndDate.ToString('yyyy-MM-dd')
   
  
   # Convert PSCredential to JSON for Invoke-WebRequest
   Write-Verbose '[Get-AHSData] Converting Credential to JSON'
   $JSONPass = @{UserName=$Credential.GetNetworkCredential().UserName; Password=$Credential.GetNetworkCredential().Password} | ConvertTo-Json
   
   # Validate folder
   Write-Verbose '[Get-AHSData] Validating folder'
   if(!(Test-Path $Folder)) {
     Write-Error 'Invalid folder specified!'
     break
   }
   
   if(!($folder.EndsWith('\'))) {
     $Folder += '\'
   }
   
   $Files = @()
   
 }
 Process
 {   
   foreach($iLO in $Server) {
     Write-Verbose "[Get-AHSData] Processing: $iLO"

     # Initialize Web Client (Trust all ignores certificate issues)
     Write-Verbose '[Get-AHSData] Initializing Web Client' 
     $WebClient = New-TrustAllWebClient

     # Get iLO Data from XMLDATA
     Write-Verbose '[Get-AHSData] Getting XMLData from iLO'
     try {
       [xml]$iLOData = $WebClient.DownloadString("https://$iLO/xmldata?item=all")
     } catch {
       Write-Error 'Error getting iLO XMLData'
       continue
     }
     $iLOSerial = $iLOData.RIMP.HSI.SBSN
     Write-Verbose "[Get-AHSData] iLO Serial: $iLOSerial"
   
     # Authenticate against REST API
     Write-Verbose '[Get-AHSData] Authenticating against iLO REST API'
     $WebClient.Headers.Add('Content-Type','application/json')   
     $LoginResult = $WebClient.UploadString("https://$iLO/rest/v1/Sessions", 'POST', $JSONPass)
   
     if($WebClient.ResponseHeaders['X-Auth-Token']) {
       # We got a Auth token to use for AHS download
       Write-Verbose '[Get-AHSData] Authentication Successful! Adding Token to header'
       $WebClient.Headers.Add('X-Auth-Token',$WebClient.ResponseHeaders['X-Auth-Token'])
     
       $Date = (Get-Date).ToString('ddMMMyy').ToUpper()
       $FileName = "$($iLOSerial)-$($Date).AHS"
       $FullPath = "$($Folder)$($FileName)"
       Write-Verbose "[Get-AHSData] Output filename: $FullPath"
     
       $URL = "https://$iLO/ahsdata/$($FileName)?from=$AHSStart&&to=$AHSEnd"
       Write-Verbose "[Get-AHSData] URL: $URL"
       Write-Host "Getting AHS Logs for $iLO... Please Wait"
       $Result = $WebClient.DownloadFile($URL, $FullPath)
     
       if((Test-Path $FullPath)) {
         Write-Verbose '[Get-AHSData] File Saved successfully!'
         $Files += Get-Item $FullPath
       } else {
         Write-Error 'File did not save'
         continue
       }
     } else {
       Write-Error 'Authentication Failure'
       continue
     }
   }
 }
 End
 {
   return $Files
 }
}