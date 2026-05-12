# FSLogix OneDrive Downloads Cleaner

A PowerShell script to clean up OneDrive\Downloads folders from FSLogix profile containers (VHD/VHDX files).

## Overview

This script mounts one or more FSLogix profile container disk images, removes the contents of the OneDrive\Downloads folder, and then safely dismounts the disks. It uses built-in Windows Storage cmdlets rather than Hyper-V tools, making it lightweight and dependency-free.

## Features

- ✅ Single VHD/VHDX processing or batch processing of entire directories
- ✅ Automatic drive letter assignment (default: E)
- ✅ Optional logging to timestamped log files
- ✅ WhatIf mode to preview deletions without making changes
- ✅ Administrator privilege requirement (enforced)
- ✅ Skips in-use profiles (detects .metadata sidecars)
- ✅ Flexible OneDrive folder detection (handles various path patterns)
- ✅ Proper cleanup and error handling with detailed console output

## Requirements

- **Operating System:** Windows 10/11 or Windows Server 2016+
- **Privileges:** Administrator (required)
- **PowerShell:** 3.0+ with built-in Storage module (`Mount-DiskImage`, `Dismount-DiskImage`, etc.)

## Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `VhdPath` | string | Yes* | - | Full path to a single FSLogix profile container (.vhd or .vhdx) |
| `ImagePath` | string | Yes* | - | Root folder containing FSLogix profile directories. Script finds all .vhd/.vhdx files recursively. |
| `DriveLetter` | string | No | E | Drive letter to assign to the mounted volume (single letter A-Z) |
| `LogFolder` | string | No | - | Optional folder path where cleanup logs will be saved as `FSLogixOneDriveCleanup-<timestamp>.log` |
| `WhatIf` | switch | No | - | Preview what would be deleted without actually deleting anything |

*Either `VhdPath` (single VHD) or `ImagePath` (batch) must be provided, but not both.

## Usage Examples

### Single VHD File
Process a single VHD/VHDX file:
```powershell
.\Cleanup-FSLogix-OneDriveDownloads.ps1 -VhdPath "\\server\share\Profiles\user.vhdx"
```

### Single VHD with Custom Drive Letter
```powershell
.\Cleanup-FSLogix-OneDriveDownloads.ps1 -VhdPath "D:\FSLogix\Profiles\user.vhdx" -DriveLetter E
```

### Preview Mode (WhatIf)
See what would be deleted without making changes:
```powershell
.\Cleanup-FSLogix-OneDriveDownloads.ps1 -VhdPath "D:\FSLogix\Profiles\user.vhdx" -DriveLetter E -WhatIf
```

### With Logging
Enable logging to a specified folder:
```powershell
.\Cleanup-FSLogix-OneDriveDownloads.ps1 -VhdPath "D:\FSLogix\Profiles\user.vhdx" -DriveLetter E -LogFolder "C:\temp\logfiles"
```

### Batch Processing All VHDs
Process all VHD/VHDX files under a directory:
```powershell
.\Cleanup-FSLogix-OneDriveDownloads.ps1 -ImagePath "F:\" -DriveLetter E
```

### Batch Processing with Preview
```powershell
.\Cleanup-FSLogix-OneDriveDownloads.ps1 -ImagePath "F:\" -DriveLetter E -WhatIf
```

### Batch Processing with Logging
```powershell
.\Cleanup-FSLogix-OneDriveDownloads.ps1 -ImagePath "F:\" -DriveLetter E -LogFolder "C:\temp\logfiles"
```

## How It Works

1. **Validation:** Checks that the script runs as Administrator and required cmdlets are available
2. **Mount:** Mounts the VHD/VHDX file as a disk image
3. **Drive Letter Assignment:** Assigns the specified drive letter (e.g., E:\)
4. **Locate Downloads:** Searches for OneDrive\Downloads folders in typical FSLogix profile paths:
   - `Profile\OneDrive\Downloads`
   - `Profile\OneDrive - *\Downloads` (handles renamed OneDrive)
   - `Users\*\OneDrive\Downloads`
   - `Users\*\OneDrive - *\Downloads`
5. **Delete:** Removes the Downloads folder and all its contents (unless in WhatIf mode)
6. **Cleanup:** Removes the drive letter assignment and dismounts the disk image
7. **Logging:** If `-LogFolder` is specified, logs all operations with timestamps

## Logging

When `-LogFolder` is provided, the script creates a log file named `FSLogixOneDriveCleanup-<yyyyMMdd-HHmmss>.log` with entries like:
```
2026-05-12 14:30:15 [INFO ] Processing VHD: D:\FSLogix\Profiles\user.vhdx
2026-05-12 14:30:15 [INFO ] Mounting VHD: D:\FSLogix\Profiles\user.vhdx
2026-05-12 14:30:17 [INFO ] Mounted as DiskNumber: 3
2026-05-12 14:30:17 [INFO ] Assigning drive letter E to partition.
```

## Output Colors

- **INFO** (Cyan): General informational messages
- **WARN** (Yellow): Warnings (e.g., active profiles skipped)
- **ERROR** (Red): Error conditions and failures

## Batch Processing Behavior

When using `-ImagePath`, the script:
- Recursively searches for all .vhd and .vhdx files
- **Skips** profiles that have a `.metadata` sidecar file (indicating they are currently in use)
- Processes each available profile sequentially
- Reports warnings for skipped files

## Error Handling

- Script throws on missing paths, insufficient privileges, or missing cmdlets
- Failed VHD processing doesn't prevent processing of subsequent files
- Detailed error messages are logged and displayed
- Safe cleanup occurs even if errors are encountered (finally blocks ensure dismounting)

## Safety Features

- ✅ Skips in-use profiles (detected by .metadata sidecar files)
- ✅ WhatIf mode for risk-free previewing
- ✅ Administrator check prevents accidental non-privileged execution
- ✅ Clear logging and console output for verification
- ✅ Proper error handling and resource cleanup

## Troubleshooting

### "This script must be run as Administrator"
- Run PowerShell as Administrator before executing the script

### "Required cmdlet not found"
- Ensure you're on Windows 10/11 or Windows Server 2016+
- The built-in Storage module should be available on all modern Windows systems

### "VHD/VHDX not found"
- Verify the path is correct and accessible
- Check file permissions
- Ensure the path uses forward slashes (/) or escaped backslashes (\\)

### "Could not find a usable partition"
- The VHD/VHDX file may be corrupted or have an unexpected structure
- Try mounting manually with File Explorer or Disk Management to verify

## License & Disclaimer

Use at your own risk. This script directly modifies file system contents of mounted disk images. Always test with a backup copy first.

---

For updates or issues, please refer to the repository.
