# 1. Primeira amostragem (Híbrida: WMI + System Process)
$WmiSample1 = Get-WmiObject -Query "SELECT IDProcess, PercentProcessorTime, Timestamp_Sys100NS FROM Win32_PerfRawData_PerfProc_Process WHERE IDProcess > 0"
$ProcSample1 = Get-Process | Select-Object Id, TotalProcessorTime
$Time1 = [DateTime]::Now

# Coleta de serviços e mapeamento (Adicionado StartType)
$AllServices = Get-Service
$ServiceWmiMap = Get-WmiObject Win32_Service | Select-Object Name, ProcessId

# Intervalo para variação de CPU
Start-Sleep -Milliseconds 800 

# 2. Segunda amostragem
$WmiSample2 = Get-WmiObject -Query "SELECT IDProcess, PercentProcessorTime, Timestamp_Sys100NS FROM Win32_PerfRawData_PerfProc_Process WHERE IDProcess > 0"
$ProcSample2 = Get-Process | Select-Object Id, TotalProcessorTime
$Time2 = [DateTime]::Now

$TotalSeconds = ($Time2 - $Time1).TotalSeconds
$Cores = $env:NUMBER_OF_PROCESSORS
$Result = @()

foreach ($Service in $AllServices) {
    $CurrentMap = $ServiceWmiMap | Where-Object { $_.Name -eq $Service.Name }
    $ServicePID = $CurrentMap.ProcessId
    
    $Process = $null
    $CpuPct  = 0
    $WmiProcIO = $null
    
    if ($ServicePID -gt 0) {
        $Process = Get-Process -Id $ServicePID -ErrorAction SilentlyContinue
        $WmiProcIO = Get-WmiObject -Query "SELECT ReadOperationCount, WriteOperationCount, ReadTransferCount, WriteTransferCount FROM Win32_Process WHERE ProcessId = $ServicePID" -ErrorAction SilentlyContinue

        $p1 = $WmiSample1 | Where-Object { $_.IDProcess -eq $ServicePID }
        $p2 = $WmiSample2 | Where-Object { $_.IDProcess -eq $ServicePID }
        
        if ($p1 -and $p2 -and ($p2.PercentProcessorTime -gt $p1.PercentProcessorTime)) {
            $CpuDiff = $p2.PercentProcessorTime - $p1.PercentProcessorTime
            $TimeDiff = $p2.Timestamp_Sys100NS - $p1.Timestamp_Sys100NS
            $CpuPct = [Math]::Round(($CpuDiff / $TimeDiff) * 100 / $Cores, 2)
        } 
        else {
            $ps1 = $ProcSample1 | Where-Object { $_.Id -eq $ServicePID }
            $ps2 = $ProcSample2 | Where-Object { $_.Id -eq $ServicePID }
            if ($ps1 -and $ps2) {
                $CpuUsed = ($ps2.TotalProcessorTime - $ps1.TotalProcessorTime).TotalSeconds
                $CpuPct = [Math]::Round(($CpuUsed * 100) / ($TotalSeconds * $Cores), 2)
            }
        }
    }
    
    $MemUsage    = if ($Process) { $Process.WorkingSet64 } else { 0 }
    $CpuTime     = if ($Process) { [Math]::Round($Process.TotalProcessorTime.TotalSeconds, 2) } else { 0 }
    $Handles     = if ($Process) { $Process.HandleCount } else { 0 }
    $Threads     = if ($Process) { $Process.Threads.Count } else { 0 }
    $Uptime      = if ($Process -and $ServicePID -gt 0) { try { [Math]::Round(((Get-Date) - $Process.StartTime).TotalSeconds, 0) } catch { 0 } } else { 0 }
    
    $NetSent     = if ($WmiProcIO) { $WmiProcIO.WriteTransferCount } else { 0 }
    $NetRecv     = if ($WmiProcIO) { $WmiProcIO.ReadTransferCount } else { 0 }
    $DiskRead    = if ($WmiProcIO) { $WmiProcIO.ReadOperationCount } else { 0 }
    $DiskWrite   = if ($WmiProcIO) { $WmiProcIO.WriteOperationCount } else { 0 }

    # Mapeamento Numérico do Tipo de Inicialização
    $StartId = switch($Service.StartType) {
        "Automatic" { 0 }
        "Manual"    { 1 }
        "Disabled"  { 2 }
        "AutomaticDelayedStart" { 3 }
        Default     { 4 }
    }

    $Result += [PSCustomObject]@{
        "SERVICE.NAME"    = $Service.Name
        "SERVICE.DISPLAY" = $Service.DisplayName
        "STARTUP.TYPE"    = $StartId
        "STATUS.ID"       = switch($Service.Status) { "Running"{0}; "Stopped"{6}; Default{7} }
        "MEM.USAGE"       = $MemUsage
        "CPU.TIME"        = $CpuTime
        "CPU.UTIL"        = if ($CpuPct -lt 0) { 0 } else { $CpuPct }
        "HANDLES"         = $Handles
        "THREADS"         = $Threads
        "UPTIME.SEC"      = $Uptime
        "NET.SENT"        = $NetSent
        "NET.RECEIVED"    = $NetRecv
        "DISK.READ.OPS"   = $DiskRead
        "DISK.WRITE.OPS"  = $DiskWrite
    }
}

Write-Output ($Result | ConvertTo-Json -Compress)