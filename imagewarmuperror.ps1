function Log 
{ 
  param([string] $dataToLog)
  try
  {
    $logFile = "c:\MyLog.txt"
   
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
       while(-not (IsCosmosDbEmulatorRunning -source $Source) -and $stopwatch.Elapsed.TotalSeconds -lt $timeoutSeconds) 
       {
           Start-Sleep -Seconds 1  
       }
       
       Write-Host "All good"
       Log -dataToLog "All good"
       exit 0
    }
    catch
    {
       Write-Host $_
       exit -19
    }

    $stopwatch.Stop()
} 
else 
{
    # Ignore Images without Cosmos DB installed
    Log -dataToLog "CosmosDB Emulator not installed. Exiting INTENTIONALLY with a non-zero code."
    exit -50
}
