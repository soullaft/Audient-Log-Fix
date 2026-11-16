# Audient iD 4.4.2 — исправление разрастания логов

[English](README.md) | **Русский** | [Українська](README.uk.md) | [Беларуская](README.be.md)

Неофициальное и прозрачное исправление для Audient iD Software **4.4.2** под Windows, которая
забивает папку `%APPDATA%\com.audient.iD` логами на десятки и сотни гигабайт.

Ничего скачивать не нужно: всё исправление — короткий PowerShell-скрипт, который можно прочитать перед запуском.

> Проект не связан с Audient, не одобрен и не поддерживается компанией. Используйте на свой риск.

## Симптомы

- Папка `C:\Users\<пользователь>\AppData\Roaming\com.audient.iD` постоянно растёт (бывает 100+ ГБ).
- Лог заполнен строками вида:

```
Failed to send bmRequest: 161 bRequest: 1 wIndex: 15872 ret: -285212668 sendRequest Failed, error code: 2
```

## Причина

iD постоянно опрашивает интерфейс USB-запросом, который всегда завершается ошибкой, и пишет в лог каждую ошибку:

| Поле | Значение | Смысл |
|---|---|---|
| `bmRequest` | `161` = `0xA1` | Запрос класса, устройство → хост, к интерфейсу |
| `bRequest` | `1` | `GET_CUR` |
| `wIndex` | `15872` = `0x3E00` | Unit ID `0x3E` (Extension Unit), интерфейс 0 |

Исправление заставляет функцию, отправляющую этот запрос (Extension Unit `0x3E`, селектор `0x06`), сразу возвращаться.

## Что именно меняется

Одна правка в 3 байта в `iD.exe`:

| | |
|---|---|
| Смещение в файле | `0x1360A0` |
| Было | `48 8B 49` |
| Стало | `31 C0 C3` (`xor eax, eax; ret`) |
| SHA-256 до | `932AC9B791A158975D6D26389A3B079037ABEC8C98AD233B73FF9267FE8FE794` |
| SHA-256 после | `EAEF2EF805E33BCEE3D3C4C0BF4EAC57C7C87C9541C28A4E71BEF20EA015F381` |

Прошивка, драйверы (USB/ASIO) и системные файлы Windows не затрагиваются. Ничего не устанавливается.

## Совместимость

- Только Audient iD Software **4.4.2** для Windows. Скрипт проверяет SHA-256 и отказывается работать с другой сборкой.
- Проверено на Audient iD4 MKII.
- Обновление iD перезапишет патч. **Не** применяйте его к другой версии: смещение там будет другим.

## Как применить

1. Откройте **PowerShell от имени администратора** (Пуск → введите `PowerShell` → *Запуск от имени администратора*).
2. Скопируйте весь блок ниже, вставьте в PowerShell и нажмите Enter.
   Тот же код лежит в [`pollfix.ps1`](pollfix.ps1).

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

1. Проверяет, что запущен от администратора.
2. Проверяет SHA-256 `iD.exe` (останавливается на неизвестной сборке и ничего не делает, если патч уже применён).
3. Закрывает Audient iD.
4. Сохраняет резервную копию `iD.exe.bak` рядом с оригиналом.
5. Проверяет исходные байты по смещению и записывает 3 новых байта.
6. Проверяет итоговый SHA-256 и восстанавливает копию, если хеш не совпал.

Если iD установлен в другую папку, измените `$Path` в начале скрипта.

### Проверка результата

Запустите Audient iD, подождите пару минут и выполните дважды с интервалом в минуту:

```powershell
Get-ChildItem "$env:APPDATA\com.audient.iD" -Recurse -File |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 5 Name, Length, LastWriteTime
```

Если `Length` больше не растёт, исправление работает. После этого можно удалить старые раздутые логи из этой папки.

## Как откатить

Выполните в PowerShell от имени администратора:

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

Переустановка Audient iD тоже вернёт оригинальный файл.

## Альтернативы без патча

- Если приложение iD не нужно постоянно, уберите его из автозагрузки. Интерфейс работает и без него, а пока iD закрыт, логи не пишутся.
- Обновите прошивку интерфейса, попробуйте другой USB-порт (напрямую в материнскую плату, без хаба).
- Сообщите о проблеме в поддержку Audient, приложив строку из лога выше.

## Благодарности

Место для патча нашёл [chirola2232](https://github.com/chirola2232/audient-id4-pollfix).
Этот репозиторий оформляет его в виде читаемого скрипта, чтобы никому не приходилось запускать неподписанный бинарник.
