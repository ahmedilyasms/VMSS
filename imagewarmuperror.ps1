[bool] $isHealthy = $true
[bool] $lastReturnValueForCosmosDbEmulatorRunning = $false
$HealthyLogFile = "c:\Healthy.txt"
$UnhealthyLogFile = "c:\Unhealthy.txt"
$logFile = "c:\MyLog.txt"

$registryPath = "HKCU:\Software\Microsoft\AzureDevOps\VMSS\MSEng"
$regKeyIsWarmupRunning = "IsWarmupRunning"
$regKeyIsHealthy = "IsHealthy"
$regKeyIsFirstRun = "IsFirstRun"


function Log 
{ 
  param([string] $dataToLog, [bool]$logToService = $true)
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
     $tmpLoggerEndPoint = "https://vmssazdosimplelogger-test.azurewebsites.net/api/VMSSAzDevOpsSimpleTestLogger"
     $params = @{"data"="Exception in log: $_"}
     Invoke-WebRequest -Uri $tmpLoggerEndPoint -Method POST -Body $params
     
     Write-Host $_      
   }
}

function AddOrUpdateRegistryValueBool { param([string] $regPath, [string] $regKey, [bool]$regKeyBoolValue)

  [int]$intVal = [Convert]::ToInt32($regKeyBoolValue)
  if (!(Test-Path $regPath))
  {
    Log -dataToLog "Regpath did not exist so creating"
    New-Item -Path $regPath -Force | Out-Null
  }
  
  New-ItemProperty -Path $regPath -Name $regKey -Value $intVal -PropertyType DWORD -Force | Out-Null
  Log -dataToLog "Wrote Registry: $regKey : $regKeyBoolValue"
}

function GetRegistryValue{ param([string]$regPath, [string]$regKey)
    
    if (!(Test-Path $regPath))
    {
        return $null
    }
    
    $value = (Get-ItemProperty -Path $regPath -Name $regKey).$regKey
    return $value
}


function GetRegistryValueBool{ param([string]$regPath, [string]$regKey, [bool]$returnNullIfNotFound = $false)
   
    $value = GetRegistryValue -regPath $regPath -regKey $regKey
    Log -dataToLog "Before eval value: GetRegValBool $regPath $regKey : Value is: $value"
    if ($value -eq $null) 
    {
        if ($returnNullIfNotFound -eq $true) 
        { 
            Log -dataToLog "GetRegistryValueBool: value is null and returnNullIfNotFound is true. Returning null"
            return $null 
        }
    }

    [bool]$convertedValue = [Convert]::ToBoolean($value)
    Log -dataToLog "GetRegValBool $regPath $regKey : Value is: $value and convertedval is $convertedValue"
    return $convertedValue
}


function AddOrUpdateWarmupRunningRegistry { param([bool] $isWarmupRunning)
  AddOrUpdateRegistryValueBool -regPath $registryPath -regKey $regKeyIsWarmupRunning -regKeyBoolValue $isWarmupRunning
}

function AddOrUpdateFirstRunRegistry { param([bool] $isFirstRun)
  AddOrUpdateRegistryValueBool -regPath $registryPath -regKey $regKeyIsFirstRun -regKeyBoolValue $isFirstRun
}

function AddOrUpdateIsHealthyRegistry { param([bool] $isHealthy)
  AddOrUpdateRegistryValueBool -regPath $registryPath -regKey $regKeyIsHealthy -regKeyBoolValue $isHealthy
}


function Initialize()
{
    #Create regkeys with default values if they do not exist
    
    $val = GetRegistryValueBool -regPath $registryPath -regKey $regKeyIsWarmupRunning -returnNullIfNotFound $true
    if ($val -eq $null)
    {
        AddOrUpdateWarmupRunningRegistry -isWarmupRunning $false
    }

    $val = GetRegistryValueBool -regPath $registryPath -regKey $regKeyIsHealthy -returnNullIfNotFound $true
    if ($val -eq $null)
    {
        AddOrUpdateIsHealthyRegistry -isHealthy $false
    }

    $val = GetRegistryValueBool -regPath $registryPath -regKey $regKeyIsFirstRun -returnNullIfNotFound $true
    if ($val -eq $null)
    {
        AddOrUpdateFirstRunRegistry -isFirstRun $true
    }
}

Log -dataToLog "initializing!"
Initialize
$tmpWarmRunning = GetRegistryValueBool -regPath $registryPath -regKey $regKeyIsWarmupRunning -returnNullIfNotFound $true
$tmpIsFirstRun = GetRegistryValueBool -regPath $registryPath -regKey $regKeyIsFirstRun -returnNullIfNotFound $true
$tmpHealthy = GetRegistryValueBool -regPath $registryPath -regKey $regKeyIsHealthy -returnNullIfNotFound $true

Log -dataToLog "Initialize ran. Values: WarmupRunning $tmpWarmRunning, firstRun $tmpIsFirstRun, Healthy: $tmpHealthy"


function GetPreviousWarmupResult()
{
    $result = GetRegistryValueBool -regPath $registryPath -regKey $regKeyIsHealthy -returnNullIfNotFound $true
    if ($result -eq $null)
    {
        Log -dataToLog "PreviousWarmup never ran"
        $result = $false
    }

    return $result
}

function CheckIfWarmupAlreadyRan()
{
    $isWarmupRunning = GetRegistryValueBool -regPath $registryPath -regKey $regKeyIsWarmupRunning
    
    Log -dataToLog "In CheckIfWarmupAlreadyRan. Value is $isWarmupRunning"

    return $isWarmupRunning
}


function FinalizeWarmupResult()
{
    AddOrUpdateWarmupRunningRegistry -isWarmupRunning $false
    AddOrUpdateFirstRunRegistry -isFirstRun $false

    $healthyValue = GetRegistryValueBool -regPath $registryPath -regKey $regKeyIsHealthy
    Log -dataToLog "In FinalizeWarmupResult with isHealthy being: $healthyValue"
    if ($healthyValue -eq $true)
    {    
        Log -dataToLog "$(Get-Date) Determined all is healthy `n"
        exit 0
    }
    else
    {     
        Log -dataToLog "Unhealthy..."
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

$warmupAlreadyRan = CheckIfWarmupAlreadyRan
Log -dataToLog "Now checking if warmup already ran. Value is: $warmupAlreadyRan"

if ($warmupAlreadyRan -eq $false)
{
    AddOrUpdateWarmupRunningRegistry -isWarmupRunning $true

    $Source = "C:\Program Files\Azure Cosmos DB Emulator\CosmosDB.Emulator.exe"
    if (Test-Path $Source) 
    {
       $dataPath = "C:\"
       if(Test-Path "D:\") 
       {
           $dataPath = "D:\"
       }

       $Arguments = "/NoExplorer","/NoTelemetry","/DisableRateLimiting","/NoFirewall","/PartitionCount=25","/NoUI","/DataPath=$dataPath"

        # find proc and taskkill
        try
        {
            Log -dataToLog "Finding cosmosdb emulator related items first and killing it if its running"
            Get-Process | Where-Object {$_.Name -like "Microsoft.Azure.Cosmos*"} | Stop-Process
            Get-Process | Where-Object {$_.Name -like "CosmosDb*"} | Stop-Process
            Log -dataToLog "Finished finding cosmosdb emulator related items"
            Log -dataToLog "Waiting for a few seconds..."
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
               
          $isHealthy = $lastReturnValueForCosmosDbEmulatorRunning 
          AddOrUpdateIsHealthyRegistry -isHealthy $isHealthy
          if ($isHealth -eq $true) 
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
          $isHealthy = $false
          AddOrUpdateIsHealthyRegistry -isHealthy $isHealthy
          Write-Host $_ 
          $string_err = $_ | Out-String
          Log -dataToLog "$string_err"
       }

   } 
   else 
   { 
       $isHealthy = $false
       AddOrUpdateIsHealthyRegistry -isHealthy $isHealthy
       # Ignore Images without Cosmos DB installed
       Log -dataToLog "CosmosDB Emulator not installed. Exiting INTENTIONALLY with a non-zero code."   
   }

    #Finalize the warmup result
    FinalizeWarmupResult
}
else
{
    Log -dataToLog "Warmup already ran!!"
   #Warmup already ran. What was the result? Lets return that result back to the caller.
   if (-not (GetPreviousWarmupResult))
   {
      exit -200 #return non zero exit code
   }
   else
   {
      exit 0
   }
}
