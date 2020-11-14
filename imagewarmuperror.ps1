[bool] $isHealthy = $true
$HealthyLogFile = "c:\Healthy.txt"
$UnhealthyLogFile = "c:\Unhealthy.txt"
$logFile = "c:\MyLog.txt"

function GetPreviousWarmupResult()
{
   if (Test-Path -Path $HealthyLogFile)
   {
      return $true
   }
   
   if (Test-Path -Path $UnhealthyLogFile)
   {
      return $false
   }
   
   return $false #unknown/for future
}

function CheckIfWarmupAlreadyRan()
{
   #for now, the only way to determine if it already executed is by checking files on disk that the script already writes.
   if (Test-Path -Path $HealthyLogFile)
   {
      return $true
   }
   
   if (Test-Path -Path $UnhealthyLogFile)
   {
      return $true
   }
   
   if (Test-Path -Path $logFile)
   {
      return $true
   }
   
   return $false
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
      exit 0
   }
   else
   { 
      if (!(Test-Path -Path $UnhealthyLogFile))
      {
          Set-Content -Path $UnhealthyLogFile -Value ""
      }
    
      Log -dataToLog "Unhealthy..."
      Add-Content -Path $UnhealthyLogFile -Value "$(Get-Date) Determined all is NOT healthy `n"
      exit -200
   }
}

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

$lastReturnValueForCosmosDbEmulatorRunning = $false
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
        $lastReturnValueForCosmosDbEmulatorRunning = $true
        return $true
    }

    $lastReturnValueForCosmosDbEmulatorRunning = $false
    return $false
}

if (-not (CheckIfWarmupAlreadyRan))
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
       #Start-Process -FilePath $Source -ArgumentList $Arguments -Wait
       # This is expected to take < 300 seconds.
       $timeoutSeconds = 300
       Log -dataToLog "Waiting for Cosmos DB Emulator Come to running state within $timeoutSeconds seconds"

       $stopwatch = [system.diagnostics.stopwatch]::StartNew()
       try
       {
          while(-not (IsCosmosDbEmulatorRunning -source $Source)) 
          {
              if ($stopwatch.Elapsed.TotalSeconds -lt $timeoutSeconds) 
              {
                 Log -dataToLog "Sleeping..."
                 Start-Sleep -Seconds 1  
              }
              else
              {
                 Log -dataToLog "Stopwatch has hit the timeout. Last Result for cosmos db check is: $lastReturnValueForCosmosDbEmulatorRunning"
              }
          }
          
          Log -dataToLog "Outside while loop. The last result was: $lastReturnValueForCosmosDbEmulatorRunning"
          Write-Host "Outside while loop. The last result was: $lastReturnValueForCosmosDbEmulatorRunning"
          $isHealthy = $lastReturnValueForCosmosDbEmulatorRunning
          if ($isHealth) {
          Write-Host "All good"
          Log -dataToLog "All good"
          }
          else
          {
            Write-Host "Not good"
            Log -dataToLog "Not good"
          }
       }
       catch
       {
          $isHealthy = $false
          Write-Host $_ 
          $string_err = $_ | Out-String
          Log -dataToLog "$string_err"
       }

       $stopwatch.Stop()
   } 
   else 
   { 
       $isHealthy = $false
       # Ignore Images without Cosmos DB installed
       Log -dataToLog "CosmosDB Emulator not installed. Exiting INTENTIONALLY with a non-zero code."   
   }

   #Finalize the warmup result
   FinalizeWarmupResult
}
else
{
   #Warmup already ran. What was the result? Lets return that result back to the caller.
   if (-not (GetPreviousWarmupResult))
   {
      return -200 #return non zero exit code
   }
   else
   {
      return 0
   }
}
