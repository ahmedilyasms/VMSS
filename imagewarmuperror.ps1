[bool] $lastReturnValueForCosmosDbEmulatorRunning = $false
$registryPath = "HKCU:\Software\Microsoft\AzureDevOps\VMSS"
$regKeyIsWarmupRunning = "IsWarmupRunning"
$regKeyIsHealthy = "IsHealthy"

function AddOrUpdateHealthyStatus { param([bool]$isHealthyVal)
    AddOrUpdateRegistryValueBool -regPath $registryPath -regKeyName $regKeyIsHealthy -regKeyBoolValue $isHealthyVal
}

function GetHealthyStatus()
{
    $healthyStatusValue = GetRegistryValueBool -registryPath $registryPath -registryKey $regKeyIsHealthy

    $val = [Convert]::ToBoolean($healthyStatusValue) #if reg key not found, null is returned and doing a convert tobool makes it a false value. 
    return $val
}

function GetRegistryValueBool{ param([string]$registryPath, [string]$registryKey, [bool]$returnNullIfNotFound = $false)
   
    $value = GetRegistryValue -registryPath $registryPath -registryKey $registryKey
    if ($value -eq $null) 
    {
        if ($returnNullIfNotFound -eq $true) { return $null }
    }

    [bool]$convertedValue = [Convert]::ToBoolean($value)
    return $convertedValue
}

function GetRegistryValue{ param([string]$registryPath, [string]$registryKey)
    
    if (!(Test-Path $registryPath))
    {
        return $null
    }
    
    $value = (Get-ItemProperty -Path $registryPath -Name $registryKey).$registryKey
    return $value
}

function AddOrUpdateRegistryValueBool {
  param([string] $regPath, [string] $regKeyHasWarmupRan, [bool]$regKeyBoolValue)

  [int]$intVal = [Convert]::ToInt32($regKeyBoolValue)

  if (!(Test-Path $regPath))
  {
    New-Item -Path $regPath -Force | Out-Null
  }
  
  New-ItemProperty -Path $regPath -Name $regKeyHasWarmupRan -Value $intVal -PropertyType DWORD -Force | Out-Null
}

function AddOrUpdateWarmupRegistry {
  param([bool] $isWarmupRunning)

  AddOrUpdateRegistryValueBool -regPath $registryPath -regKeyName $regKeyIsWarmupRunning -regKeyValue $isWarmupRunning
}

function GetPreviousHealthResult{ param([bool]$returnNullIfKeyNotFound = $false)

   $healthResult = GetRegistryValueBool -registryPath $registryPath -registryKey $regKeyIsHealthy -returnNullIfNotFound $returnNullIfKeyNotFound
   return $healthResult
}

function IsFirstWarmupRun()
{
    #Null should indicate yes, first warmup is running
    $warmupRegKeyFound = GetRegistryValueBool -registryPath $registryPath -registryKey $regKeyIsWarmupRunning -returnNullIfNotFound $true
    if ($warmupRegKeyFound -eq $null) { return $true } else { return $false }
    #We return false even if a key is found because we care, at this point, if the key exists or not. A non existant key == this is first time its running.
}


function CheckAndSetWarmupRun()
{
    $isFirstWarmupRun = IsFirstWarmupRun
    if ($isFirstWarmupRun -eq $true)
    {
        AddOrUpdateWarmupRegistry -isWarmupRunning $true
        Log -dataToLog "This is officially the first warmup and setting it to true"
    }
    else
    {
        Log -dataToLog "Warmup already ran in CheckAndSetupWarmupRun!"
    }
}

CheckAndSetWarmupRun


function CheckIfWarmupAlreadyRan()
{
    # Get reg value
   $hasRan = GetRegistryValueBool -registryPath $registryPath -registryKey $regKeyIsWarmupRunning -returnNullIfNotFound $true
   if ($hasRan -eq $null) { $hasRan = $false }

   Log -dataToLog "Checking if warmup already ran: $hasRan"
   return $hasRan    
}

function FinalizeWarmupResult()
{
   $HealthyLogFile = "c:\Healthy.txt"
   $UnhealthyLogFile = "c:\Unhealthy.txt"

   $healthyValue = GetHealthyStatus
   Log -dataToLog "In FinalizeWarmupResult with isHealthy being: $healthyValue"
   if ($healthyValue)
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
  param([string] $dataToLog, [bool]$logToService = $true)
  
  $logFile = "c:\MyLog.txt"

  try
  {   
    Write-Host $dataToLog
    if (!(Test-Path -Path $logFile))
    {
       Set-Content -Path $logFile -Value ""
    }
   
    Add-Content -Path $logFile -Value "$(Get-Date) $dataToLog `n"
    
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
         Add-Content -Path $logFile -Value "Unable to call webservice to log: $_"
       }
    }
   }
   catch
   {
    try
    {
     $tmpLoggerEndPoint = "https://vmssazdosimplelogger-test.azurewebsites.net/api/VMSSAzDevOpsSimpleTestLogger"
     $params = @{"data"="Exception in log: $_"}
     Invoke-WebRequest -Uri $tmpLoggerEndPoint -Method POST -Body $params
     }
     catch
     {
        Write-Host $_
     }

      Write-Host $_
      exit -200
   }
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

        # find proc and taskkill. I am truly dearly sorry Windows for doing this to you....
        try
        {
            Log -dataToLog "Finding cosmosdb emulator related items first and killing it if its running"
            Get-Process | Where-Object {$_.Name -like "Microsoft.Azure.Cosmos*"} | Stop-Process
            Get-Process | Where-Object {$_.Name -like "CosmosDb*"} | Stop-Process
            Log -dataToLog "Finished finding cosmosdb emulator related items....Waiting for a few seconds..."
            Start-Sleep -Seconds 5
        }
        catch
        {
            Log -dataToLog $_
            #No proc found
        }
        
       Log -dataToLog "Starting Cosmos DB Emulator..."
       try
       {
           $tmp = Start-Process -FilePath $Source -ArgumentList $Arguments -PassThru
           $tmp | Wait-Process -Timeout 5 -ErrorAction Stop
           Log -dataToLog "Waited for process successfully for timeout to start the emulator"
       }
       catch
       {
           Log -dataToLog "Error in wait process: $_"
       }
    
       # This is expected to take < 300 seconds.
       $timeoutSeconds = 300
       Log -dataToLog "Waiting for Cosmos DB Emulator Come to running state within $timeoutSeconds seconds"
       
       [bool]$isHealthy = $false

       $stopwatch = [system.diagnostics.stopwatch]::StartNew()
       try
       {
          while(-not (IsCosmosDbEmulatorRunning -source $Source) -and $stopwatch.Elapsed.TotalSeconds -lt $timeoutSeconds) 
          {
                 Log -dataToLog "Sleeping..." -logToService $false
                 Start-Sleep -Seconds 10
          }
          
          $stopwatch.Stop()
          Log -dataToLog "Outside while loop. The last result was: $lastReturnValueForCosmosDbEmulatorRunning"
          
          #one more if false
          if (-not ($lastReturnValueForCosmosDbEmulatorRunning))
          {
            $lastReturnValueForCosmosDbEmulatorRunning = IsCosmosDbEmulatorRunning -source $Source
            
            Log -dataToLog "One last run... The last result was: $lastReturnValueForCosmosDbEmulatorRunning"
          }
               
          $isHealthy = $lastReturnValueForCosmosDbEmulatorRunning #IsCosmosDbEmulatorRunning -source $Source
          AddOrUpdateHealthyStatus -isHealthyVal $isHealthy
          if ($isHealthy) 
          {
             Log -dataToLog "All good"
          }
          else
          {
            Log -dataToLog "Not good"
          }
       }
       catch
       {
          $stopwatch.Stop()
          AddOrUpdateHealthyStatus -isHealthyVal $false
          Write-Host $_ 
          $string_err = $_ | Out-String
          Log -dataToLog "$string_err"
       }

   } 
   else 
   { 
       AddOrUpdateHealthyStatus -isHealthyVal $false
       # Ignore Images without Cosmos DB installed
       Log -dataToLog "CosmosDB Emulator not installed. Exiting INTENTIONALLY with a non-zero code."   
   }

   #Finalize the warmup result
   FinalizeWarmupResult
}
else
{
   $previousHealthValue = GetPreviousHealthResult -returnNullIfKeyNotFound $true
   if ($previousHealthValue -eq $null)
   {
      Log -dataToLog "Warmup already ran but the health value was null!"
      exit -201
   }
   else
   {
       Log -dataToLog "Warmup already ran and it's result was: $previousHealthValue"
  
       if (-not ($previousHealthValue))
       {
          exit -200 #return non zero exit code
       }
       else
       {
          exit 0
       }
   }
}
