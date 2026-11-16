# Audient iD 4.4.2 — выпраўленне разрастання логаў

[English](README.md) | [Русский](README.ru.md) | [Українська](README.uk.md) | **Беларуская**

Неафіцыйнае і празрыстае выпраўленне для Audient iD Software **4.4.2** пад Windows, якая
запаўняе папку `%APPDATA%\com.audient.iD` логамі на дзясяткі і сотні гігабайтаў.

Нічога спампоўваць не трэба: усё выпраўленне — кароткі PowerShell-скрыпт, які можна прачытаць перад запускам.

> Праект не звязаны з Audient, не ўхвалены і не падтрымліваецца кампаніяй. Выкарыстоўвайце на сваю рызыку.

## Сімптомы

- Папка `C:\Users\<карыстальнік>\AppData\Roaming\com.audient.iD` увесь час расце (бывае 100+ ГБ).
- Лог запоўнены радкамі накшталт:

```
Failed to send bmRequest: 161 bRequest: 1 wIndex: 15872 ret: -285212668 sendRequest Failed, error code: 2
```

## Прычына

iD увесь час апытвае інтэрфейс USB-запытам, які заўсёды завяршаецца памылкай, і запісвае ў лог кожную памылку:

| Поле | Значэнне | Сэнс |
|---|---|---|
| `bmRequest` | `161` = `0xA1` | Запыт класа, прылада → хост, да інтэрфейсу |
| `bRequest` | `1` | `GET_CUR` |
| `wIndex` | `15872` = `0x3E00` | Unit ID `0x3E` (Extension Unit), інтэрфейс 0 |

Выпраўленне прымушае функцыю, якая адпраўляе гэты запыт (Extension Unit `0x3E`, селектар `0x06`), адразу вяртацца.

## Што менавіта змяняецца

Адна змена на 3 байты ў `iD.exe`:

| | |
|---|---|
| Зрух у файле | `0x1360A0` |
| Было | `48 8B 49` |
| Стала | `31 C0 C3` (`xor eax, eax; ret`) |
| SHA-256 да | `932AC9B791A158975D6D26389A3B079037ABEC8C98AD233B73FF9267FE8FE794` |
| SHA-256 пасля | `EAEF2EF805E33BCEE3D3C4C0BF4EAC57C7C87C9541C28A4E71BEF20EA015F381` |

Прашыўка, драйверы (USB/ASIO) і сістэмныя файлы Windows не закранаюцца. Нічога не ўсталёўваецца.

## Сумяшчальнасць

- Толькі Audient iD Software **4.4.2** для Windows. Скрыпт правярае SHA-256 і адмаўляецца працаваць з іншай зборкай.
- Праверана на Audient iD4 MKII.
- Абнаўленне iD перазапіша патч. **Не** ўжывайце яго да іншай версіі: зрух там будзе іншы.

## Як ужыць

1. Адкрыйце **PowerShell ад імя адміністратара** (Пуск → увядзіце `PowerShell` → *Запуск ад імя адміністратара*).
2. Скапіруйце ўвесь блок ніжэй, устаўце ў PowerShell і націсніце Enter.
   Той жа код ляжыць у [`pollfix.ps1`](pollfix.ps1).

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

Скрыпт:

1. Правярае, што запушчаны ад адміністратара.
2. Правярае SHA-256 `iD.exe` (спыняецца на невядомай зборцы і нічога не робіць, калі патч ужо ўжыты).
3. Закрывае Audient iD.
4. Захоўвае рэзервовую копію `iD.exe.bak` побач з арыгіналам.
5. Правярае зыходныя байты па зруху і запісвае 3 новыя байты.
6. Правярае выніковы SHA-256 і аднаўляе копію, калі хэш не супаў.

Калі iD усталяваны ў іншую папку, змяніце `$Path` у пачатку скрыпта.

### Праверка выніку

Запусціце Audient iD, пачакайце пару хвілін і выканайце двойчы з інтэрвалам у хвіліну:

```powershell
Get-ChildItem "$env:APPDATA\com.audient.iD" -Recurse -File |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 5 Name, Length, LastWriteTime
```

Калі `Length` больш не расце, выпраўленне працуе. Пасля гэтага можна выдаліць старыя раздзьмутыя логі з гэтай папкі.

## Як адкаціць

Выканайце ў PowerShell ад імя адміністратара:

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

Пераўсталёўка Audient iD таксама верне арыгінальны файл.

## Альтэрнатывы без патча

- Калі праграма iD не патрэбна ўвесь час, прыбярыце яе з аўтазагрузкі. Інтэрфейс працуе і без яе, а пакуль iD закрыты, логі не пішуцца.
- Абнавіце прашыўку інтэрфейсу, паспрабуйце іншы USB-порт (наўпрост у мацярынскую плату, без хаба).
- Паведаміце пра праблему ў падтрымку Audient, дадаўшы радок з логу вышэй.

## Падзякі

Месца для патча знайшоў [chirola2232](https://github.com/chirola2232/audient-id4-pollfix).
Гэты рэпазітар афармляе яго ў выглядзе чытэльнага скрыпта, каб нікому не даводзілася запускаць непадпісаны бінарны файл.
