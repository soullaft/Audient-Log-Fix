# Audient iD 4.4.2 — log flood fix

**English** | [Русский](README.ru.md) | [Українська](README.uk.md) | [Беларуская](README.be.md)

An unofficial, transparent fix for Audient iD Software **4.4.2** on Windows, which fills
`%APPDATA%\com.audient.iD` with tens or hundreds of gigabytes of logs.

No `.exe` to download: the whole fix is a short PowerShell script you can read before running.

> Not affiliated with, endorsed by or supported by Audient. Use at your own risk.

## Symptoms

- The `C:\Users\<you>\AppData\Roaming\com.audient.iD` folder keeps growing (100+ GB is possible).
- The log is full of lines like:

```
Failed to send bmRequest: 161 bRequest: 1 wIndex: 15872 ret: -285212668 sendRequest Failed, error code: 2
```

## Cause

iD keeps polling the interface with a USB request that always fails, and logs every failure:

| Field | Value | Meaning |
|---|---|---|
| `bmRequest` | `161` = `0xA1` | Class request, device-to-host, to an interface |
| `bRequest` | `1` | `GET_CUR` |
| `wIndex` | `15872` = `0x3E00` | Unit ID `0x3E` (Extension Unit), interface 0 |

The fix makes the function that sends this request (Extension Unit `0x3E`, selector `0x06`) return immediately.

## What exactly is changed

One 3-byte change in `iD.exe`:

| | |
|---|---|
| File offset | `0x1360A0` |
| Before | `48 8B 49` |
| After | `31 C0 C3` (`xor eax, eax; ret`) |
| SHA-256 before | `932AC9B791A158975D6D26389A3B079037ABEC8C98AD233B73FF9267FE8FE794` |
| SHA-256 after | `EAEF2EF805E33BCEE3D3C4C0BF4EAC57C7C87C9541C28A4E71BEF20EA015F381` |

Firmware, drivers (USB/ASIO) and Windows system files are not touched. Nothing is installed.

## Compatibility

- Audient iD Software **4.4.2** for Windows only. The script checks the SHA-256 and refuses any other build.
- Tested with an Audient iD4 MKII.
- After an iD update the patch is overwritten. Do **not** apply it to another version: the offset will be different.

## How to apply

1. Open **PowerShell as Administrator** (Start → type `PowerShell` → *Run as administrator*).
2. Copy the whole block below, paste it into PowerShell and press Enter.
   The same code is in [`pollfix.ps1`](pollfix.ps1).

```powershell
# Audient iD 4.4.2 log flood fix (unofficial)
# Patches 3 bytes in iD.exe so the failing USB poll (XU 0x3E, selector 0x06) is no longer sent.
# Run in PowerShell as Administrator.

& {
    $ErrorActionPreference = 'Stop'

    $Path        = 'C:\Program Files\Audient\iD\iD.exe'
    $Offset      = 0x1360A0
    $Original    = [byte[]](0x48, 0x8B, 0x49)
    $Patched     = [byte[]](0x31, 0xC0, 0xC3)   # xor eax,eax ; ret
    $HashOrig    = '932AC9B791A158975D6D26389A3B079037ABEC8C98AD233B73FF9267FE8FE794'
    $HashPatched = 'EAEF2EF805E33BCEE3D3C4C0BF4EAC57C7C87C9541C28A4E71BEF20EA015F381'

    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
               ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) { throw 'Run PowerShell as Administrator.' }

    if (-not (Test-Path $Path)) { throw "iD.exe not found: $Path" }

    $hash = (Get-FileHash $Path -Algorithm SHA256).Hash
    if ($hash -eq $HashPatched) { Write-Host 'Already patched. Nothing to do.' -ForegroundColor Green; return }
    if ($hash -ne $HashOrig)    { throw "Unsupported iD.exe build (SHA256 $hash). Only Audient iD 4.4.2 is supported. Nothing was changed." }

    Get-Process -Name iD -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 1

    Copy-Item $Path "$Path.bak" -Force
    Write-Host "Backup: $Path.bak"

    $bytes = [IO.File]::ReadAllBytes($Path)
    for ($i = 0; $i -lt 3; $i++) {
        if ($bytes[$Offset + $i] -ne $Original[$i]) { throw 'Unexpected bytes at patch offset. Nothing was changed.' }
    }
    for ($i = 0; $i -lt 3; $i++) { $bytes[$Offset + $i] = $Patched[$i] }
    [IO.File]::WriteAllBytes($Path, $bytes)

    $new = (Get-FileHash $Path -Algorithm SHA256).Hash
    if ($new -ne $HashPatched) {
        Copy-Item "$Path.bak" $Path -Force
        throw "Verification failed (SHA256 $new). Original restored."
    }

    Write-Host 'Patched successfully. You can start Audient iD again.' -ForegroundColor Green
}
```

The script:

1. Checks that it runs as Administrator.
2. Checks the SHA-256 of `iD.exe` (stops if the build is unknown, does nothing if already patched).
3. Closes Audient iD.
4. Saves a backup as `iD.exe.bak` next to the original.
5. Checks the original bytes at the offset, then writes the 3 new bytes.
6. Checks the resulting SHA-256 and restores the backup if it does not match.

If iD is installed somewhere else, change `$Path` at the top of the script.

### Check the result

Start Audient iD, wait a couple of minutes and run this twice, a minute apart:

```powershell
Get-ChildItem "$env:APPDATA\com.audient.iD" -Recurse -File |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 5 Name, Length, LastWriteTime
```

If `Length` no longer grows, the fix works. You can then delete the old oversized log files from that folder.

## How to undo

Run in PowerShell as Administrator:

```powershell
& {
    $ErrorActionPreference = 'Stop'
    $Path = 'C:\Program Files\Audient\iD\iD.exe'
    if (-not (Test-Path "$Path.bak")) { throw "Backup not found: $Path.bak" }
    Get-Process -Name iD -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 1
    Copy-Item "$Path.bak" $Path -Force
    Get-FileHash $Path -Algorithm SHA256
}
```

Reinstalling Audient iD also restores the original file.

## Alternatives without patching

- If you do not need the iD app running all the time, remove it from startup. The interface works without it, and nothing is logged while iD is closed.
- Update the interface firmware, try a different USB port (directly on the motherboard, without a hub).
- Report the issue to Audient support with the log line above.

## Credits

The patch location was found by [chirola2232](https://github.com/chirola2232/audient-id4-pollfix).
This repository repackages it as a readable script, so nobody has to run an unsigned binary.
