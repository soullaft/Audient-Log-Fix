# Audient iD 4.4.2 — виправлення розростання логів

[English](README.md) | [Русский](README.ru.md) | **Українська** | [Беларуская](README.be.md)

Неофіційне та прозоре виправлення для Audient iD Software **4.4.2** під Windows, яка
заповнює теку `%APPDATA%\com.audient.iD` логами на десятки й сотні гігабайтів.

Нічого завантажувати не потрібно: усе виправлення — короткий PowerShell-скрипт, який можна прочитати перед запуском.

> Проєкт не пов'язаний з Audient, не схвалений і не підтримується компанією. Використовуйте на власний ризик.

## Симптоми

- Тека `C:\Users\<користувач>\AppData\Roaming\com.audient.iD` постійно росте (буває 100+ ГБ).
- Лог заповнений рядками на кшталт:

```
Failed to send bmRequest: 161 bRequest: 1 wIndex: 15872 ret: -285212668 sendRequest Failed, error code: 2
```

## Причина

iD постійно опитує інтерфейс USB-запитом, який завжди завершується помилкою, і записує до логу кожну помилку:

| Поле | Значення | Зміст |
|---|---|---|
| `bmRequest` | `161` = `0xA1` | Запит класу, пристрій → хост, до інтерфейсу |
| `bRequest` | `1` | `GET_CUR` |
| `wIndex` | `15872` = `0x3E00` | Unit ID `0x3E` (Extension Unit), інтерфейс 0 |

Виправлення змушує функцію, що надсилає цей запит (Extension Unit `0x3E`, селектор `0x06`), одразу повертатися.

## Що саме змінюється

Одна зміна на 3 байти в `iD.exe`:

| | |
|---|---|
| Зміщення у файлі | `0x1360A0` |
| Було | `48 8B 49` |
| Стало | `31 C0 C3` (`xor eax, eax; ret`) |
| SHA-256 до | `932AC9B791A158975D6D26389A3B079037ABEC8C98AD233B73FF9267FE8FE794` |
| SHA-256 після | `EAEF2EF805E33BCEE3D3C4C0BF4EAC57C7C87C9541C28A4E71BEF20EA015F381` |

Прошивка, драйвери (USB/ASIO) і системні файли Windows не зачіпаються. Нічого не встановлюється.

## Сумісність

- Лише Audient iD Software **4.4.2** для Windows. Скрипт перевіряє SHA-256 і відмовляється працювати з іншою збіркою.
- Перевірено на Audient iD4 MKII.
- Оновлення iD перезапише патч. **Не** застосовуйте його до іншої версії: зміщення там буде іншим.

## Як застосувати

1. Відкрийте **PowerShell від імені адміністратора** (Пуск → введіть `PowerShell` → *Запуск від імені адміністратора*).
2. Скопіюйте весь блок нижче, вставте в PowerShell і натисніть Enter.
   Той самий код лежить у [`pollfix.ps1`](pollfix.ps1).

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

Скрипт:

1. Перевіряє, що запущений від адміністратора.
2. Перевіряє SHA-256 `iD.exe` (зупиняється на невідомій збірці й нічого не робить, якщо патч уже застосовано).
3. Закриває Audient iD.
4. Зберігає резервну копію `iD.exe.bak` поруч з оригіналом.
5. Перевіряє вихідні байти за зміщенням і записує 3 нові байти.
6. Перевіряє підсумковий SHA-256 і відновлює копію, якщо хеш не збігся.

Якщо iD встановлено в іншу теку, змініть `$Path` на початку скрипта.

### Перевірка результату

Запустіть Audient iD, зачекайте кілька хвилин і виконайте двічі з інтервалом у хвилину:

```powershell
Get-ChildItem "$env:APPDATA\com.audient.iD" -Recurse -File |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 5 Name, Length, LastWriteTime
```

Якщо `Length` більше не росте, виправлення працює. Після цього можна видалити старі роздуті логи з цієї теки.

## Як скасувати

Виконайте в PowerShell від імені адміністратора:

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

Перевстановлення Audient iD теж поверне оригінальний файл.

## Альтернативи без патча

- Якщо застосунок iD не потрібен постійно, приберіть його з автозавантаження. Інтерфейс працює і без нього, а поки iD закритий, логи не пишуться.
- Оновіть прошивку інтерфейсу, спробуйте інший USB-порт (напряму в материнську плату, без хаба).
- Повідомте про проблему в підтримку Audient, додавши рядок із логу вище.

## Подяки

Місце для патча знайшов [chirola2232](https://github.com/chirola2232/audient-id4-pollfix).
Цей репозиторій оформлює його у вигляді читабельного скрипта, щоб нікому не доводилося запускати непідписаний бінарний файл.
