# this script checks that performance is running as expected
# if performance is too slow the machine is rebooted, reboots continue until deletion or improvement
[bool] $isHealthy = $true
$HealthyLogFile = "c:\Healthy.txt"
$UnhealthyLogFile = "c:\Unhealthy.txt"
$logFile = "c:\MyLog.txt"

function DoPageFileMove {
    # This script sets a larger page file size on the D drive, this overwrites the existing page file settings and shouldn't be used outside of Azure.

    $physicalmem = systeminfo | Where-Object {$_ -Match "Total Physical Memory"}

    $physicalmb = (($physicalmem -replace '\D+(\d+)','$1') -replace '(\d+)\D+','$1')

    # Windows perf team recommends 1.5x
    $maxmb = [int]([int]$physicalmb * 1.5)

    reg ADD "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" /v PagingFiles /t REG_MULTI_SZ /d "D:\pagefile.sys $physicalmb $maxmb" /f
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


function Get-SqlDataFolderStatus([String]$Source, [String]$Destination)
{
    if ((Test-Path $Destination) -and (Test-Path $Source))
    {
        $sourceContents = Get-ChildItem -Recurse -path "$Source"
        $destinationContents = Get-ChildItem -Recurse -path "$Destination"
        if (($destinationContents) -and -not (Compare-Object -ReferenceObject $sourceContents -DifferenceObject $destinationContents))
        {
            if ((Get-Service -Name "SQL Server (MSSQLSERVER)").Status -eq 'Running')
            {
                if (Test-Path "$Source\MS_AgentSigningCertificate.cer")
                {
                    return $true
                }
            }
        }
    }
    return $false
}

function DoSQLPerf
{
    $SQLSource = "C:\Program Files\Microsoft SQL Server\MSSQL13.MSSQLSERVER\MSSQL\DATA"
    $SQLDestination = "D:\sql\Data"

    if (-not (Get-SqlDataFolderStatus $SQLSource $SQLDestination))
    {
        Write-Host "trying to move"
        # This is expected to take < 15 seconds.
        $timeoutSeconds = 30
        $code = {
            param (
                [string]$Source,
                [string]$Destination
            )
            net stop "SQL Server (MSSQLSERVER)"
            xcopy $Source "$Destination\" /S /E /K /O
            rmdir $Source -Recurse -Force
            New-Item -Path $Source -ItemType SymbolicLink -Value $Destination
            net start "SQL Server (MSSQLSERVER)"
    
            Invoke-Sqlcmd -Query "SELECT cast('12/12/12 12:12:12' as datetime2) AT TIME ZONE 'UTC'"
        }
        $j = Start-Job -ScriptBlock $code -ArgumentList ($SQLSource, $SQLDestination)
        if (Wait-Job $j -Timeout $timeoutSeconds) { Receive-Job $j }
        Remove-Job -force $j
        if (-not (Get-SqlDataFolderStatus $SQLSource $SQLDestination))
        {
            Write-Error "Everything went wrong with the sql restart"
            Log -dataToLog "Everything went wrong with the sql restart so returning false"
            #Restart-Computer
            return $false
        }
    }
    Write-Host "Got here without moving"
    Log -dataToLog "Got here without moving"
    return $true
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
          
          Write-Host "All good"
          Log -dataToLog "All good"
          return $true
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

Log -dataToLog "Doing pageFile move"
DoPageFileMove
Log -dataToLog "Done pagefile move"

Log -dataToLog "Beginning to do SQL Perf"
$sqlPerfResult = DoSQLPerf
Log -dataToLog "SQL Perf result returned: $($sqlPerfResult)"
$isHealthy = $sqlPerfResult
if ($sqlPerfResult -eq $true)
{
    Log -dataToLog "Beginning to do Cosmos DB Check"
    #now to CosmosDB check
    $cosmosDBCheckResult = DoCosmosDBCheck
    $isHealthy = $cosmosDBCheckResult
    Log -dataToLog "End doing cosmos db check. Result: $($cosmosDBCheckResult)"
    FinalizeWarmupResult
    if (-not $isHealthy)
    {
        return 0 #should be return -1 or whatever
    }
    else
    {
        return 0
    }
}
else
{
    FinalizeWarmupResult
    Log -dataToLog "SQL Perf went bad"
    return 0 #-10 #SQL
}
