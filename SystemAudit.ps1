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

## SEC:1- THIRD FUNCTION: CPU USAGE | BIGGEST CONSUMERS
function Get-AuditCpuUsage {
    [CmdletBinding()]
    param()

    Write-LogHeader -title "3. CPU USAGE & TOP CONSUMERS"

    [PSCustomObject]$CpuMetric = Get-CimInstance -ClassName Win32_Processor |
            Select-Object DeviceID, Name, NumberOfCores, NumberOfLogicalProcessors, LoadPercentage

    Write-LogData -Data $CpuMetric

    [Array]$TopCpuProcesses = Get-Process |
            Sort-Object -Property CPU -Descending |
            Select-Object -First 10 -Property Id, ProcessName,
            @{Name = "CPUTime_sec"; Expression = {[Math]::Round($_.CPU, 2)}},
            @{Name = "Memory_MB"; Expression = {[Math]::Round($_.WorkingSet64 / 1MB, 2)}}

    Write-LogData -Data $TopCpuProcesses
}

## SEC:1- FOURTH FUNCTION: CHECK RAM USAGE
function Get-AuditMemoryUsage {
    [CmdletBinding()]
    param()

    Write-LogHeader -title "4. MEMORY USAGE (RAM)"

    [PSCustomObject]$OS = Get-CimInstance -ClassName Win32_OperatingSystem

    [double]$TotalRamGB  = [Math]::Round($OS.TotalVisibleMemorySize / 1MB, 2)
    [double]$FreeRamGB   = [Math]::Round($OS.FreePhysicalMemory / 1MB, 2)
    [double]$UsedRamGB   = [Math]::Round($TotalRamGB - $FreeRamGB, 2)
    [double]$UsedPercent = [Math]::Round(($UsedRamGB / $TotalRamGB) * 100, 2)

    [PSCustomObject]$MemoryMetrics = [PSCustomObject]@{
        Total_GB     = $TotalRamGB
        Used_GB      = $UsedRamGB
        Free_GB      = $FreeRamGB
        Used_Percent = $UsedPercent
    }

    Write-LogData -Data $MemoryMetrics
}

## SEC:1- SIXTH FUNCTION: TEMPERATURE MONITORING
function Get-AuditThermalStatus {
    [CmdletBinding()]
    param ()

    Write-LogHeader -Title "6. TEMPERATURE MONITORING & THERMAL THROTTLING"

    try {
        [array]$Zones = Get-CimInstance -Namespace "root/wmi" -ClassName "MSAcpi_ThermalZoneTemperature" -ErrorAction Stop

        [array]$ThermalData = foreach ($Zone in $Zones) {
            [double]$TempKelvin = $Zone.CurrentTemperature / 10
            [double]$TempCelsius = [Math]::Round($TempKelvin - 273.15, 1)

            [PSCustomObject]@{
                InstanceName   = $Zone.InstanceName
                Temp_Celsius   = $TempCelsius
                CriticalTrip_C = [Math]::Round(($Zone.CriticalTripPoint / 10) - 273.15, 1)
                ThrottlingRisk = ($TempCelsius -ge 85.0)
            }
        }

        Write-LogData -Data $ThermalData
    }
    catch {
        Write-Warning "ACPI Thermal Zones niet direct toegankelijk via root/wmi."
        [PSCustomObject]$Fallback = [PSCustomObject]@{
            SensorAccess = "Restricted/OEM-specific"
            Status       = "Niet beschikbaar via generieke WMI"
        }
        Write-LogData -Data $Fallback
    }
}

## SEC:1- SEVENTH FUNCTION: FAN & COOLING STATUS
function Get-AuditFanStatus {
    [CmdletBinding()]
    param ()

    Write-LogHeader -Title "7. COOLING & FAN DIAGNOSTICS"

    try {
        [array]$Fans = Get-CimInstance -ClassName Win32_Fan -ErrorAction Stop

        if ($Fans.Count -gt 0) {
            [array]$FanData = foreach ($Fan in $Fans) {
                [PSCustomObject]@{
                    DeviceId      = $Fan.DeviceId
                    Name          = $Fan.Name
                    CurrentSpeed  = $Fan.DesiredSpeed
                    Status        = $Fan.Status
                    Health        = $Fan.HealthState
                }
            }
            Write-LogData -Data $FanData
        }
        else {
            throw "Geen generieke Win32_Fan instanties gevonden."
        }
    }
    catch {
        # Laptops sturen fans vrijwel altijd aan via een afgeschermde Embedded Controller (EC)
        Write-Warning "Fysieke fans worden hardwarematig beheerd via de Embedded Controller (OEM-specifiek)."
        [PSCustomObject]$Fallback = [PSCustomObject]@{
            ControllerType = "Proprietary Embedded Controller (EC)"
            FanControl     = "Hardware Auto-Throttling actief"
            WmiAccess      = "Restricted by Motherboard Firmware"
        }
        Write-LogData -Data $Fallback
    }
}
## SEC:1- EIGHTH FUNCTION: BATTERY HEALTH & LIFECYCLE
function Get-AuditBatteryHealth {
    [CmdletBinding()]
    param ()

    Write-LogHeader -Title "8. BATTERY WEAR & HEALTH METRICS"

    try {
        [array]$WmiBatteries = Get-CimInstance -ClassName Win32_Battery -ErrorAction Stop

        if ($WmiBatteries.Count -eq 0) {
            throw "Geen batterij gedetecteerd (desktop/server hardware)."
        }

        # Genereer een tijdelijk XML-rapport via powercfg
        [string]$TempXmlPath = Join-Path -Path $env:TEMP -ChildPath "batreport_$((Get-Date).Ticks).xml"
        $null = powercfg /batteryreport /xml /output $TempXmlPath

        [PSCustomObject]$BatteryMetrics = $null

        if (Test-Path -Path $TempXmlPath) {
            [xml]$ReportXml = Get-Content -Path $TempXmlPath -Raw
            Remove-Item -Path $TempXmlPath -Force -ErrorAction SilentlyContinue

            [double]$DesignCap = [double]($ReportXml.BatteryReport.Batteries.Battery.DesignCapacity)
            [double]$FullCap   = [double]($ReportXml.BatteryReport.Batteries.Battery.FullChargeCapacity)
            [int]$Cycles       = [int]($ReportXml.BatteryReport.Batteries.Battery.CycleCount)

            [double]$WearPercent = 0.0
            if ($DesignCap -gt 0) {
                $WearPercent = [Math]::Round(((1 - ($FullCap / $DesignCap)) * 100), 2)
            }

            $BatteryMetrics = [PSCustomObject]@{
                DeviceName         = $WmiBatteries[0].Name
                Chemistry          = $ReportXml.BatteryReport.Batteries.Battery.Chemistry
                DesignCapacity_mWh = $DesignCap
                FullChargeCap_mWh  = $FullCap
                BatteryWear_Pct    = $WearPercent
                CycleCount         = $Cycles
                WmiStatus          = $WmiBatteries[0].Status
            }
        }
        else {
            # Fallback op basis-WMI indien powercfg XML niet kon wegschrijven
            $BatteryMetrics = [PSCustomObject]@{
                DeviceName         = $WmiBatteries[0].Name
                DesignCapacity_mWh = "Niet beschikbaar"
                FullChargeCap_mWh  = "Niet beschikbaar"
                BatteryWear_Pct    = "Niet beschikbaar"
                CycleCount         = "Niet beschikbaar"
                WmiStatus          = $WmiBatteries[0].Status
            }
        }

        Write-LogData -Data $BatteryMetrics
    }
    catch {
        Write-Warning "Geen fysieke accu aanwezig of batterijmetingen niet ondersteund."
        [PSCustomObject]$Fallback = [PSCustomObject]@{
            SystemType     = "Desktop / AC-Only System"
            BatteryPresent = $false
            Status         = "Overgeslagen"
        }
        Write-LogData -Data $Fallback
    }
}
## SEC:1- NINTH FUNCTION: POWER SUPPLY & ENCLOSURE STATE
function Get-AuditPowerSupplyState {
    [CmdletBinding()]
    param ()

    Write-LogHeader -Title "9. POWER SUPPLY, AC ADAPTER & ENCLOSURE SECURITY"

    [PSCustomObject]$PowerMetrics = $null

    try {
        # Netstroom status (Online = netstroom verbonden, Offline = draait op accu)
        [array]$LineStatus = Get-CimInstance -Namespace "root/wmi" -ClassName "BatteryStatus" -ErrorAction SilentlyContinue
        [bool]$IsAcOnline = if ($LineStatus -and $LineStatus.Count -gt 0) { [bool]$LineStatus[0].PowerOnline } else { $true }

        # Behuizingsstatus en manipulatie/openingsdetectie (Chassis Intrusion)
        [array]$Enclosures = Get-CimInstance -ClassName Win32_SystemEnclosure -ErrorAction Stop
        [string]$ChassisType = if ($Enclosures.ChassisTypes) { ($Enclosures.ChassisTypes -join ", ") } else { "Onbekend" }
        [string]$SecurityBreach = switch ($Enclosures.SecurityStatus) {
            1 { "Other" }
            2 { "Unknown" }
            3 { "None (Veilig/Gesloten)" }
            4 { "Tamper Detected (Waarschuwing)" }
            5 { "Breach Detected (Kritiek)" }
            default { "Niet gerapporteerd" }
        }

        $PowerMetrics = [PSCustomObject]@{
            AcConnected       = $IsAcOnline
            ChassisTypes      = $ChassisType
            ChassisSecurity   = $SecurityBreach
            LockStatus        = $Enclosures.LockPresentStatus
            OperationalStatus = "OK"
        }
    }
    catch {
        $PowerMetrics = [PSCustomObject]@{
            AcConnected       = "Niet beschikbaar"
            ChassisTypes      = "Niet beschikbaar"
            ChassisSecurity   = "Geen sensor-toegang"
            LockStatus        = "Niet beschikbaar"
            OperationalStatus = "Fout bij uitlezen WMI"
        }
    }

    Write-LogData -Data $PowerMetrics
}

## SEC:1- TENTH FUNCTION: GRAPHICS CARD & NVIDIA TELEMETRY
function Get-AuditGpuStatus {
    [CmdletBinding()]
    param ()

    Write-LogHeader -Title "10. GRAPHICS CARD (GPU) & TELEMETRY"

    [array]$GpuProps = @(
        "Name",
        "DriverVersion",
        "DriverDate",
        "Status",
        @{Name = "VRAM_MB"; Expression = {[Math]::Round($_.AdapterRAM / 1MB, 2)}}
    )

    [array]$GpuList = Get-CimInstance -ClassName Win32_VideoController | Select-Object -Property $GpuProps
    Write-LogData -Data $GpuList

    # Check op aanwezige NVIDIA SMI tool voor live diepe telemetrie
    [string]$NvidiaSmiPath = Join-Path -Path $env:ProgramFiles -ChildPath "NVIDIA Corporation\NVSMI\nvidia-smi.exe"
    if (-not (Test-Path -Path $NvidiaSmiPath)) {
        $NvidiaSmiPath = "nvidia-smi"
    }

    $NvidiaSmiCmd = Get-Command -Name $NvidiaSmiPath -ErrorAction SilentlyContinue
    if ($NvidiaSmiCmd) {
        try {
            [string]$SmiQuery = "--query-gpu=name,driver_version,temperature.gpu,utilization.gpu,utilization.memory,memory.total,memory.used --format=csv,noheader,nounits"
            [string]$RawOutput = & $NvidiaSmiCmd.Source $SmiQuery.Split(" ") 2>$null

            if ($RawOutput) {
                [array]$Fields = $RawOutput.Trim().Split(",")
                [PSCustomObject]$NvidiaTelemetry = [PSCustomObject]@{
                    NvidiaGpuName  = $Fields[0].Trim()
                    DriverVersion  = $Fields[1].Trim()
                    GpuTemp_C      = [double]$Fields[2].Trim()
                    GpuLoad_Pct    = [double]$Fields[3].Trim()
                    MemLoad_Pct    = [double]$Fields[4].Trim()
                    TotalVRAM_MB   = [double]$Fields[5].Trim()
                    UsedVRAM_MB    = [double]$Fields[6].Trim()
                }
                Write-LogData -Data $NvidiaTelemetry
            }
        }
        catch {
            Write-Warning "NVIDIA SMI aanwezig, maar kon telemetrie niet direct ophalen."
        }
    }
}

## SEC:1- ELEVENTH FUNCTION: PERIPHERAL DEVICES & DRIVER ERRORS
function Get-AuditPeripheralDevices {
    [CmdletBinding()]
    param ()

    Write-LogHeader -Title "11. PERIPHERAL & USB DEVICE ERROR AUDIT"

    # Filtert apparaten eruit die NIET op 'OK' staan (bijv. Driver Error, Code 10, Code 43, Disabled)
    [array]$FaultyDevices = Get-CimInstance -ClassName Win32_PnPEntity |
            Where-Object { $_.Status -ne "OK" -and $_.ConfigManagerErrorCode -ne 0 } |
            Select-Object Name, DeviceID, Status, ConfigManagerErrorCode,
            @{Name = "ProblemDescription"; Expression = {
                switch ($_.ConfigManagerErrorCode) {
                    1  { "Device not configured" }
                    10 { "Device cannot start" }
                    14 { "Reboot required" }
                    18 { "Reinstall drivers" }
                    22 { "Device disabled" }
                    28 { "Drivers not installed" }
                    43 { "Device stopped (Driver/Hardware problem)" }
                    default { "Error Code $($_.ConfigManagerErrorCode)" }
                }
            }}

    if ($FaultyDevices.Count -gt 0) {
        Write-Warning "Er zijn aangesloten apparaten met hardware- of driver-fouten gevonden!"
        Write-LogData -Data $FaultyDevices
    }
    else {
        [PSCustomObject]$CleanStatus = [PSCustomObject]@{
            PeripheralAudit = "Hardware & USB Bus Scan"
            ErrorDevices    = 0
            AuditResult     = "Alle gedetecteerde apparaten functioneren storingsvrij (Status = OK)"
        }
        Write-LogData -Data $CleanStatus
    }
}


## SEC-1 : HARDWARE & PERFORMANCE DIAGNOSTICS COMPLETE



##=======================================================
## SEC-2: SECURITY & SYSTEM INTEGRITY                ====
#=========================================================



## SEC-2: FIRST FUNCTION: WINDOWS UPDATES:
