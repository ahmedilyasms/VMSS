# this script checks that performance is running as expected
# if performance is too slow the machine is rebooted, reboots continue until deletion or improvement

function Log { param($dataToLog)
    Write-Host $dataToLog
    Add-Content "c:\MyLog.txt" "$dataToLog `n"
}

function IsCosmosDbEmulatorRunning([string] $source){
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
    # private enum EmulatorStatus
    # {
    #     Error = 0,
    #     Starting = 1,
    #     Running = 2,
    #     Stopped = 3,
    # }
}

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
    while(-not (IsCosmosDbEmulatorRunning -source $Source) -and $stopwatch.Elapsed.TotalSeconds -lt $timeoutSeconds) {
        Start-Sleep -Seconds 1            
    }

    $stopwatch.Stop()
    if(IsCosmosDbEmulatorRunning -source $Source)
    {
        Log -dataToLog "Cosmos DB Emulator is in running state"
        $tmpLoggerEndPoint = "https://vmssazdosimplelogger-test.azurewebsites.net/api/VMSSAzDevOpsSimpleTestLogger"
        $params = @{"data"="Cosmos DB Emulator is in running state but intentionally failing the extension."}
        Invoke-WebRequest -Uri $tmpLoggerEndPoint -Method POST -Body $params
        exit -100
    } 
    else
    {
        Log -dataToLog "Cosmos DB Emulator didn't get to running state within $timeoutSeconds seconds. Exiting with non zero exit code."        
        $tmpLoggerEndPoint = "https://vmssazdosimplelogger-test.azurewebsites.net/api/VMSSAzDevOpsSimpleTestLogger"
        $params = @{"data"="Cosmos DB Emulator didn't get to running state within the timeframe. Restarting VM."}
        Invoke-WebRequest -Uri $tmpLoggerEndPoint -Method POST -Body $params
        exit -50
    }
} 
else 
{
    # Ignore Images without Cosmos DB installed
    Log -dataToLog "CosmosDB Emulator not installed. Exiting INTENTIONALLY with a non-zero code."
    try
    {
        # call out for logging.
    $tmpLoggerEndPoint = "https://vmssazdosimplelogger-test.azurewebsites.net/api/VMSSAzDevOpsSimpleTestLogger"
    $params = @{"data"="Warmup script logging from VMSS image - Cosmos DB Em not installed."}
    Invoke-WebRequest -Uri $tmpLoggerEndPoint -Method POST -Body $params
    }
    catch
    {
        Log -dataToLog $_
    }
    
    exit -50
}
