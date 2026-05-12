<#
.SYNOPSIS
  Mount one or more FSLogix Profile VHD/VHDX files, clean OneDrive\Downloads, and optionally write logs to a file.

  Created by Joey Verlinden. Use at your own risk!

.DESCRIPTION
  - Mounts the specified VHD/VHDX
  - Assigns drive letter E to the mounted volume (or uses existing)
  - Deletes OneDrive\Downloads from the FSLogix profile content
  - Dismounts the VHD/VHDX
  - Uses built-in Windows disk image cmdlets instead of Hyper-V PowerShell tools
  - Supports optional logging to FSLogixOneDriveCleanup-<timestamp>.log via -LogFolder

.PARAMETER VhdPath
  Full path to a single FSLogix profile container (.vhd or .vhdx)

.PARAMETER ImagePath
  Root folder that contains FSLogix profile directories. The script will find all .vhd/.vhdx files below this path.

.PARAMETER DriveLetter
  Drive letter to assign (default: E)

.PARAMETER LogFolder
  Optional folder to store log output. If provided, messages from Write-Info/Write-Warn/Write-Err are appended to FSLogixOneDriveCleanup-<timestamp>.log

.PARAMETER WhatIf
  Shows what would be deleted without actually deleting anything

.EXAMPLE - Single VHD
  .\Cleanup-FSLogix-OneDriveDownloads.ps1 -VhdPath "\\server\share\Profiles\user.vhdx"

.EXAMPLE - Single VHD with WhatIf
  .\Cleanup-FSLogix-OneDriveDownloads.ps1 -VhdPath "D:\FSLogix\Profiles\user.vhdx" -DriveLetter E -WhatIf

.EXAMPLE - Single VHD with logfile output
  .\Cleanup-FSLogix-OneDriveDownloads.ps1 -VhdPath "D:\FSLogix\Profiles\user.vhdx" -DriveLetter E -LogFolder "C:\temp\logfiles"

.EXAMPLE - All VHDs under a folder with WhatIf
  .\Cleanup-FSLogix-OneDriveDownloads.ps1 -ImagePath "F:\" -DriveLetter E -WhatIf

.EXAMPLE - All VHDs under a folder
  .\Cleanup-FSLogix-OneDriveDownloads.ps1 -ImagePath "F:\" -DriveLetter E

.EXAMPLE - All VHDs under a folder with logfile output
  .\Cleanup-FSLogix-OneDriveDownloads.ps1 -ImagePath "F:\" -DriveLetter E -LogFolder "C:\temp\logfiles"
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
  [Parameter(Mandatory=$true, ParameterSetName='Single')]
  [ValidateNotNullOrEmpty()]
  [string]$VhdPath,

  [Parameter(Mandatory=$true, ParameterSetName='Batch')]
  [ValidateNotNullOrEmpty()]
  [string]$ImagePath,

  [Parameter(Mandatory=$false)]
  [ValidatePattern('^[A-Z]$')]
  [string]$DriveLetter = 'E',

  [Parameter(Mandatory=$false)]
  [string]$LogFolder
)

$script:LogFilePath = $null

if ($LogFolder) {
  if (-not (Test-Path -LiteralPath $LogFolder)) {
    New-Item -Path $LogFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
  }

  $runTimestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  $script:LogFilePath = Join-Path -Path $LogFolder -ChildPath "FSLogixOneDriveCleanup-$runTimestamp.log"
  New-Item -Path $script:LogFilePath -ItemType File -Force -ErrorAction Stop | Out-Null
}

function Write-Log {
  param(
    [Parameter(Mandatory=$true)]
    [string]$Level,

    [Parameter(Mandatory=$true)]
    [string]$Message,

    [Parameter(Mandatory=$true)]
    [string]$Color
  )

  $consoleLine = "[$Level] $Message"
  Write-Host $consoleLine -ForegroundColor $Color

  if ($script:LogFilePath) {
    $logTimestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -LiteralPath $script:LogFilePath -Value "$logTimestamp $consoleLine"
  }
}

function Write-Info($msg) { Write-Log -Level 'INFO ' -Message $msg -Color 'Cyan' }
function Write-Warn($msg) { Write-Log -Level 'WARN ' -Message $msg -Color 'Yellow' }
function Write-Err ($msg) { Write-Log -Level 'ERROR' -Message $msg -Color 'Red' }

# --- Pre-flight checks ---
if ($PSCmdlet.ParameterSetName -eq 'Single') {
  if (-not (Test-Path -LiteralPath $VhdPath)) {
    throw "VHD/VHDX not found: $VhdPath"
  }
}
else {
  if (-not (Test-Path -LiteralPath $ImagePath)) {
    throw "ImagePath not found: $ImagePath"
  }
}

# Require admin
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  throw "This script must be run as Administrator."
}

# Built-in Windows Storage cmdlets needed
foreach ($cmd in @('Mount-DiskImage','Dismount-DiskImage','Get-DiskImage','Get-Disk','Get-Partition','Get-Volume','Set-Partition','Remove-PartitionAccessPath')) {
  if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
    throw "Required cmdlet not found: $cmd. This script requires the built-in Windows Storage module."
  }
}

function Invoke-CleanupForVhd {
  param(
    [Parameter(Mandatory=$true)]
    [string]$TargetVhdPath
  )

  $mounted = $false
  $diskNumber = $null
  $partition = $null
  $volume = $null
  $diskImage = $null

  try {
    Write-Info "Processing VHD: $TargetVhdPath"
    Write-Info "Mounting VHD: $TargetVhdPath"
    Mount-DiskImage -ImagePath $TargetVhdPath -ErrorAction Stop
    $mounted = $true

    # Resolve the disk number exposed by the mounted disk image.
    $diskImage = Get-DiskImage -ImagePath $TargetVhdPath -ErrorAction Stop
    $disk = $diskImage | Get-Disk -ErrorAction Stop
    $diskNumber = $disk.Number
    Write-Info "Mounted as DiskNumber: $diskNumber"

    # Wait a moment for PnP/volume discovery
    Start-Sleep -Seconds 2

    # Find the primary (largest) partition/volume (typical FSLogix single volume)
    $partition = Get-Partition -DiskNumber $diskNumber |
      Where-Object { $_.Type -ne 'Reserved' -and $_.GptType -ne '{E3C9E316-0B5C-4DB8-817D-F92DF00215AE}' } |
      Sort-Object Size -Descending |
      Select-Object -First 1

    if (-not $partition) {
      throw "Could not find a usable partition on disk $diskNumber."
    }

    # Assign requested drive letter if needed
    $currentLetter = ($partition | Get-Volume -ErrorAction SilentlyContinue).DriveLetter
    if ($currentLetter -and ($currentLetter -eq $DriveLetter)) {
      Write-Info "Drive letter $DriveLetter already assigned."
    }
    else {
      if ($currentLetter) {
        Write-Warn "Partition currently has drive letter $currentLetter. Reassigning to $DriveLetter."
        Set-Partition -DiskNumber $diskNumber -PartitionNumber $partition.PartitionNumber -NewDriveLetter $DriveLetter -ErrorAction Stop
      }
      else {
        Write-Info "Assigning drive letter $DriveLetter to partition."
        Set-Partition -DiskNumber $diskNumber -PartitionNumber $partition.PartitionNumber -NewDriveLetter $DriveLetter -ErrorAction Stop
      }
    }

    # Resolve volume info
    $volume = Get-Volume -DriveLetter $DriveLetter -ErrorAction Stop
    Write-Info "Volume mounted: $DriveLetter (FileSystem=$($volume.FileSystem), SizeRemaining=$([math]::Round($volume.SizeRemaining/1GB,2)) GB)"

    # --- Locate the OneDrive Downloads folder inside the mounted profile ---
    $candidates = @(
      "$DriveLetter`:\Profile\OneDrive\Downloads",
      "$DriveLetter`:\Profile\OneDrive - *\Downloads",
      "$DriveLetter`:\Users\*\OneDrive\Downloads",
      "$DriveLetter`:\Users\*\OneDrive - *\Downloads"
    )

    $targets = @()

    foreach ($c in $candidates) {
      $match = Get-ChildItem -Path $c -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer }
      if ($match) {
        $targets += $match.FullName
      }
    }

    $targets = $targets | Sort-Object -Unique

    if (-not $targets -or $targets.Count -eq 0) {
      Write-Warn "No OneDrive Downloads folder found in expected locations. Nothing to delete."
      return
    }

    Write-Info "Found the following OneDrive Downloads folders:"
    $targets | ForEach-Object { Write-Info "  - $_" }

    foreach ($t in $targets) {
      if ($PSCmdlet.ShouldProcess($t, "Remove OneDrive Downloads content")) {
        Write-Info "Deleting: $t"
        Remove-Item -LiteralPath $t -Recurse -Force -ErrorAction Stop
      }
    }

    Write-Info "Cleanup complete for: $TargetVhdPath"

  }
  catch {
    Write-Err "[$TargetVhdPath] $($_.Exception.Message)"
    throw
  }
  finally {
    if ($mounted) {
      try {
        Write-Info "Removing drive letter $DriveLetter (if assigned)..."
        $vol = Get-Volume -DriveLetter $DriveLetter -ErrorAction SilentlyContinue
        if ($vol) {
          $p = Get-Partition -DriveLetter $DriveLetter -ErrorAction SilentlyContinue
          if ($p) {
            Remove-PartitionAccessPath -DiskNumber $p.DiskNumber -PartitionNumber $p.PartitionNumber -AccessPath "$DriveLetter`:\" -ErrorAction SilentlyContinue | Out-Null
          }
        }

        Write-Info "Dismounting VHD: $TargetVhdPath"
        Dismount-DiskImage -ImagePath $TargetVhdPath -ErrorAction Stop
        Write-Info "Dismounted successfully."

      }
      catch {
        Write-Err "Failed during dismount/finalization for [$TargetVhdPath]: $($_.Exception.Message)"
        throw
      }
    }
  }
}

if ($PSCmdlet.ParameterSetName -eq 'Single') {
  Invoke-CleanupForVhd -TargetVhdPath $VhdPath
}
else {
  $vhdFiles = Get-ChildItem -Path $ImagePath -Recurse -File -ErrorAction Stop |
    Where-Object { $_.Extension -in @('.vhd', '.vhdx') }

  if (-not $vhdFiles -or $vhdFiles.Count -eq 0) {
    Write-Warn "No .vhd/.vhdx files found under: $ImagePath"
    return
  }

  foreach ($file in $vhdFiles) {
    $metadataSidecar = "$($file.FullName).metadata"
    if (Test-Path -LiteralPath $metadataSidecar) {
      Write-Warn "Skipping active/in-use profile (metadata present): $($file.FullName)"
      continue
    }

    Invoke-CleanupForVhd -TargetVhdPath $file.FullName
  }
}
