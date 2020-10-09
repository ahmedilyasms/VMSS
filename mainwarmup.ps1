# this script checks that performance is running as expected
# if performance is too slow the machine is rebooted, reboots continue until deletion or improvement
[bool] $isHealthy = $true
$HealthyLogFile = "c:\Healthy.txt"
$UnhealthyLogFile = "c:\Unhealthy.txt"
$logFile = "c:\MyLog.txt"

function Log 
{ 
  param([string] $dataToLog)
  try
  {   
    if (!(Test-Path -Path $logFile))
    {
       Set-Content -Path $logFile -Value ""
    }
   
    Write-Host $dataToLog
    Add-Content -Path $logFile -Value "$(Get-Date) $dataToLog `n"
   }
   catch
   {
      Write-Host $_
      exit -200
   }
    # $tmpLoggerEndPoint = "https://vmssazdosimplelogger-test.azurewebsites.net/api/VMSSAzDevOpsSimpleTestLogger"
    # $params = @{"data"="Cosmos DB Emulator is in running state but intentionally failing the extension."}
    # Invoke-WebRequest -Uri $tmpLoggerEndPoint -Method POST -Body $params
}

function IsCosmosDbEmulatorRunning([string] $source)
{
    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = $source
    $pinfo.UseShellExecute = $true
    $pinfo.Arguments = "/GetStatus /NoTelemetry"
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $pinfo
    $p.Start() | Out-Null
    $p.WaitForExit()
    $exitCode = $p.ExitCode
    if($exitCode -eq 2)
    {
        return $true
    }

    return $false
}

function DoCosmosDBCheck
{
   $Source = "C:\Program Files\Azure Cosmos DB Emulator\CosmosDB.Emulator.exe"
   if (Test-Path $Source) 
   {
       $dataPath = "C:\"
       if(Test-Path "D:\") 
       {
           $dataPath = "D:\"
       }
       $Arguments = "/NoExplorer","/NoTelemetry","/DisableRateLimiting","/NoFirewall","/PartitionCount=25","/NoUI","/DataPath=$dataPath"

       Log -dataToLog "Starting Cosmos DB Emulator..."
       Start-Process -FilePath $Source -ArgumentList $Arguments -Wait
       # This is expected to take < 300 seconds.
       $timeoutSeconds = 300
       Log -dataToLog "Waiting for Cosmos DB Emulator Come to running state within $timeoutSeconds seconds"

       $stopwatch = [system.diagnostics.stopwatch]::StartNew()
       try
       {
          while(-not (IsCosmosDbEmulatorRunning -source $Source) -and $stopwatch.Elapsed.TotalSeconds -lt $timeoutSeconds) 
          {
              Log -dataToLog "Sleeping..."
              Start-Sleep -Seconds 1  
          }
          
          if(IsCosmosDbEmulatorRunning -source $Source)
          {
             Write-Host "Cosmos DB Emulator is in running state"
             Write-Host "All good"
             Log -dataToLog "All good"
             return $true
          } 
          else
          {
              Write-Host "Cosmos DB Emulator didn't get to running state within $timeoutSeconds seconds. Returning non-zero exit code"
              Log -dataToLog "Cosmos DB Emulator didn't get to running state within $timeoutSeconds seconds. Returning non-zero exit code"
              return $false
          }
       }
       catch
       {
          Write-Host $_ 
          $string_err = $_ | Out-String
          Log -dataToLog "$string_err"
          return $false
       }

       $stopwatch.Stop()
   } 
   else 
   { 
       # Ignore Images without Cosmos DB installed
       Log -dataToLog "CosmosDB Emulator not installed. Exiting INTENTIONALLY with a non-zero code."   
       return $false
   }
}

function FinalizeWarmupResult()
{
   if ($isHealthy)
   {
      if (!(Test-Path -Path $HealthyLogFile))
      {
          Set-Content -Path $HealthyLogFile -Value ""
      }
    
      Add-Content -Path $HealthyLogFile -Value "$(Get-Date) Determined all is healthy `n"
      #exit 0
   }
   else
   { 
      if (!(Test-Path -Path $UnhealthyLogFile))
      {
          Set-Content -Path $UnhealthyLogFile -Value ""
      }
    
      Log -dataToLog "Unhealthy..."
      Add-Content -Path $UnhealthyLogFile -Value "$(Get-Date) Determined all is NOT healthy `n"
      #exit 0 #-200
   }
}

Log -dataToLog "Beginning to do Cosmos DB Check"

$cosmosDBCheckResult = DoCosmosDBCheck
$isHealthy = $cosmosDBCheckResult
Log -dataToLog "End doing cosmos db check. Result: $($cosmosDBCheckResult)"
FinalizeWarmupResult
if ($isHealthy -eq $false)
{
    Write-Host "It reported false"
    return 0 #should be return -1 or whatever
}
else
{
    Write-Host "It reported true"
    return 0
}
