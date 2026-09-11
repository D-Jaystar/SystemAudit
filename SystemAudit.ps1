# 1. Configuration and logging setup
# ====================================

$ScriptDir = $PSScriptRoot
if (-not $ScriptDir) {
    $ScriptDir = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
}

# Makes a submap within projectmap
$LogDir = Join-Path -Path $ScriptDir -ChildPath "AuditLogs"
$Timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$LogFile = Join-Path -Path $LogDir -ChildPath "SystemAudit_$Timestamp.log"

# Failsafe: maak de map aan als deze nog niet bestaat
if (-not (Test-Path -Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

function Write-LogHeader {
    [Cmdletbinding()]
    param (
    [Parameter(Mandatory = $true)]
    [String]$title
    )
    [String]$Divider = "=" * 70
    Write-Host "`n$Divider" -ForegroundColor Cyan
    Write-Host "`n$Divider" -ForegroundColor Yellow
    Write-Host "`n$Divider" -ForegroundColor Cyan
    if ($LogFile -and (Test-Path -Path $LogDir)) {
        Add-Content -Path $LogFile -Value "`n$Divider`n $Title`n$Divider"
    }
}

function Write-LogData {
    [Cmdletbinding()]
    param (
    [Parameter(Mandatory = $true, ValueFromPipeline =$true)]
    [Object]$Data
    )
    [String]$Output = $Data | Out-String
    Write-Host $Output -ForegroundColor Gray
    if($LogFile -and (Test-Path -path $LogDir)) {
        Add-Content -Path $LogFile -Value $Output
    }
}
## SEC:1- FIRST FUNCTION: DISK SPACE
function Get-AuditDiskSpace {
    [CmdletBindingAttribute()]
    param ()

    Write-LogHeader -title "1. DISK SPACE (BESCHIKBARE OPSLAG)"
    [Array]$Disks = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "Drivetype=3" |
    Select-Object DeviceID, VolumeName,
        @{Name = "FreeSpace_GB"; Expression = {[math]::Round($_.FreeSpace / 1GB, 2)}},
        @{Name = "TotalSize_GB"; Expression = {[math]::Round($_.Size / 1GB, 2)}},
        @{Name = "Free_Percent"; Expression = {[math]::Round(($_.FreeSpace / $_.Size) * 100, 2)}}
    Write-LogData -Data $Disks
}
## SEC:1- SECOND FUNCTION:  DISK HEALTH SMART
function Get-AuditDiskHealth {
    [Cmdletbinding()]
    param()

    Write-LogHeader -title "2. DISK HEALTH & S.M.A.R.T "

    [Array]$PhysicalDisks = Get-PhysicalDisk |
        Select-Object DeviceId, FriendlyName, MediaType, OperationalStatus, HealthStatus
    Write-LogData -Data $PhysicalDisks

    [Array]$Reliability = Get-StorageReliabilityCounter -PhysicalDisk (Get-PhysicalDisk) -ErrorAction SilentlyContinue |
        Select-Object DeviceId, ReadErrorsTotal, WriteErrorsTotal, Temperature, Wear

    if ($Reliability) {
        Write-LogData -Data $Reliability
        
    }
}

## SEC:1- THIRD FUNCTION: CPU USSAGE | BIGGEST CONSUMERS
function Get-AuditCpuUsage
{
    [CmdletBinding()]
    param()
    Write-LogHeader -title "3. CPU USAGE & TOP CONSUMERS"

    [PSCustomObject]$CpuMetric = Get-CimInstance -ClassName Win32_Processor|
            Select-Object DeviceID, Name, NumberOfCores, NumberOfLogicalProcessors, LoadPercentage

    Write-LogData -Data $CpuMetric
    [Array]$TopCpuProcesses = Get-Process |
        Sort-Object -Property CPU -Descending |
        Select-Object -First 10 -Property Id, ProcessName,
            @{Name = "CPUTime_sec"; Expression = {[Math]::Round($_.CPU, 2)}}
            @{name = "Memory_MB"; Expression = {[Math]::Round($_.WorkingSet64 / 1MB, 2)}}
    Write-LogData -Data $TopCpuProcesses
}

## SEC:1- Fourth Function: CHECK RAM USAGE
function Get-AuditMemoryUsage {
    [Cmdletbinding()]
    param()
    Write-LogHeader -title "4. MEMORY USAGE (RAM)"

    [PSCustomObject]$OS = Get-CimInstance -ClassName Win32_OperatingSystem

    [double]$TotalRamGB = [Math]::Round($OS.TotalVisavleMemorySize / 1MB, 2 )
    [double]$FreeRamGB = [Math]::Round($OS.FreePhysicalMemory / 1MB, 2)
    [double]$UsedRamGB = [Math]::Round($OS.TotalRamGB - $FreeRamGB, 2)
    [double]$UsedPercent = [Math]::Round(($UsedRamGB / $TotalRamGB) * 100, 2)

    [PSCustomObject]$MemoryMetrics =[PSCustomObject]@{
        Total_GB = $TotalRamGB
        Used_GB = $UsedRamGB
        Free_GB = $FreeRamGB
        Used_Percent = $UsedPercent
    }
    Write-LogData -Data $MemoryMetrics
}
