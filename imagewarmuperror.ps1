function Log 
{ 
  param([string] $dataToLog, [bool]$logToService = $true)
  try
  {   
    Write-Host $dataToLog
    if ($logToService)
    {
       try
       {
         $IPInfo = Get-NetIPAddress -AddressFamily IPv4 -AddressState Preferred
         $tmpLoggerEndPoint = "https://vmssazdosimplelogger-test.azurewebsites.net/api/VMSSAzDevOpsSimpleTestLogger"
         $machineInfo = "$env:COMPUTERNAME, $IPInfo"
         $params = @{"data"="$(Get-Date)- $machineInfo >>> $dataToLog"}
         Invoke-WebRequest -Uri $tmpLoggerEndPoint -Method POST -Body $params
       }
       catch
       {
         Write-Host "Unable to call webservice to log: $_"
       }
    }
   }
   catch
   {   
     $tmpLoggerEndPoint = "https://vmssazdosimplelogger-test.azurewebsites.net/api/VMSSAzDevOpsSimpleTestLogger"
     $params = @{"data"="Exception in log: $_"}
     Invoke-WebRequest -Uri $tmpLoggerEndPoint -Method POST -Body $params
     
     Write-Host $_      
   }
}


[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
$urlToDownload = "https://github.com/ahmedilyasms/VMSS/raw/master/VMWarmupCheck.zip"
$downloadLocation = "${ENV:Temp}\warmupChecker.zip"
$extractLocation = "C:\tmpWarmupChecker\"

Write-Host "Downloading Warmup Checker: $urlToDownload"
$webClient = New-Object Net.WebClient
$webClient.DownloadFile($urlToDownload, $downloadLocation)

Write-Host "Unzipping Warmup checker to folder $extractLocation"
Add-Type -AssemblyName System.IO.Compression.FileSystem
if(Test-Path $extractLocation) {
    Remove-Item $extractLocation -Recurse -Force
}

[System.IO.Compression.ZipFile]::ExtractToDirectory($downloadLocation, $extractLocation)

Log -dataToLog "Successfully unzipped warmup checker to location $extractLocation, Now running the checker"
$fullPath = [IO.Path]::Combine($extractLocation, 'VMWarmupCheck.exe')
try
{
  $theExitCode = (Start-Process -FilePath $fullPath -PassThru -Wait).ExitCode 
  exit $theExitCode
}
catch
{
 exit -500
}
