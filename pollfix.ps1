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
