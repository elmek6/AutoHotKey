# AHK → Python port: güzergah

Kaynak: `AutoHotkey.ahk` + `Lib/` (30 modül). Hedef: aynı davranış, Python 3.13 + ctypes/Win32.

## Stack

- CPython **3.13 x64**, python.org installer (Store sürümü değil — COM/hook/registry sandbox'a takılıyor). Free-threaded build yok.
- **uv** — venv/pip/lock tek araç. `uv run python main.py`.
- Paketleme: geliştirmede PyInstaller, yayında Nuitka `--standalone --enable-plugin=pyside6`.

```bash
uv add pywin32 comtypes pillow mss psutil pyside6 orjson pydantic watchdog
uv add --dev pytest ruff pyright nuitka
```

Faz geldikçe: `winsdk` (Windows.Media.Ocr), `rapidocr-onnxruntime` (offline yedek), `opencv-python-headless` (ImageSearch), `pywinauto`/`uiautomation`, `dxcam`.

`keyboard`, `pynput`, `pyautogui` **kullanılmayacak** — cascade/scancode/sol-sağ modifier ayrımı hiçbirinde tam yok. Hook ve SendInput doğrudan ctypes.

## Yapı

```
main.py
app/core/    saf Python, Win32 import'u yasak, pytest buraya
app/win32/   ctypes sarmalayıcılar (hook, send, clipboard, window, registry)
app/ui/      PySide6
```

Mantık (geçmiş, slotlar, profil eşleşmesi, kayıt formatı) `core/`de kalırsa test edilebilir; AHK'de ayrılamayan şey buydu.

## Mimari kısıtlar

- Ana thread Qt event loop. LL hook **ayrı thread**te, kendi `GetMessage` döngüsüyle (`SetWindowsHookEx` kurulduğu thread'in pompasına bağlı). Aralarında `queue.Queue` + Qt signal.
- Hook callback O(1): yut/yutma kararı ver, kuyruğa at, dön. I/O yok. `LowLevelHooksTimeout` 300 ms — aşarsan Windows hook'u sessizce düşürür.
- `CFUNCTYPE` callback nesnesi ve DLL handle'ları modül seviyesinde tutulacak, yoksa GC toplar.
- `SendInput` `KEYEVENTF_SCANCODE` ile; VK oyunlarda ve RDP'de çalışmıyor.
- Pano dinleme `AddClipboardFormatListener` + `WM_CLIPBOARDUPDATE`, polling yok.

## Modül eşlemesi

| AHK | Python |
|---|---|
| `key_handler_hook`, `key_counter` | ctypes `SetWindowsHookEx(WH_KEYBOARD_LL/WH_MOUSE_LL)` |
| `key_handler_cascade`, `_mouse` | veri-güdümlü dispatcher tablosu (JSON) |
| `key_builder` | `SendInput` INPUT struct sarmalayıcı |
| `Gui`, `ListView`, `menus` | PySide6 `QDialog`/`QTableView`/`QMenu` |
| `TraySetIcon`, `A_TrayMenu` | `QSystemTrayIcon` |
| `#SingleInstance Force` | `CreateMutexW` named mutex |
| `clip_hist`, `clip_slot`, `memory_slots` | `win32clipboard` + `core/` veri katmanı + `orjson` |
| `gdip_mini`, `clip_image_store` | Pillow + `mss`/`dxcam` |
| `ole_drag_source` | `QDrag` + `QMimeData` (gerekirse `pythoncom.DoDragDrop`) |
| `screen_ocr`, `OCR.ahk` | `winsdk` → Windows.Media.Ocr; yedek RapidOCR |
| `settings`, `settings_dialog` | pydantic model → `settings.json` → üretilen Qt dialog |
| `error_handler`, log.txt | `logging` + `RotatingFileHandler` |
| `jsongo.v2` | `orjson` |
| WMI süreç sorguları | `psutil` |
| `magnifier.ahk` | değişmiyor, `subprocess` + `magnifier.exe` |
| autostart | `winreg`, HKCU Run |

## Fazlar

Her faz ayrı branch, sonunda çalışan program. AHK sürümü paralel çalışmaya devam eder; faz merge olunca o özellik AHK'de kapatılır. AHK dosyalarına dokunulmaz.

| # | İçerik | Karşılığı |
|---|---|---|
| 0 | iskelet, logging, mutex, tray, reload/exit kısayolu | `AutoHotkey.ahk`, `script_state`, `error_handler` |
| 1 | ayar sistemi + Qt ayar dialogu | `settings`, `settings_dialog` |
| 2 | hook katmanı: klavye+fare LL, yutma, sayaç, event kuyruğu | `key_handler_hook`, `key_counter` |
| 3 | gönderim katmanı: scancode SendInput | `key_builder` |
| 4 | dispatcher: cascade/mouse eşleme tabloları | `key_handler_cascade`, `_mouse` |
| 5 | pano geçmişi (metin) + slotlar + kalıcılık | `clip_hist`, `clip_slot`, `memory_slots` |
| 6 | GUI: geçmiş listesi, menüler, filtre | `menus`, `array_filter` |
| 7 | görsel pano + sürükleme | `clip_image_*`, `gdip_mini`, `ole_drag_source` |
| 8 | makro kaydedici/oynatıcı | `macro_recorder` |
| 9 | ekran yakalama + OCR | `screen_ocr`, `magnifier` |
| 10 | profiller, repository, incognito | `app_shorts`, `repository`, `incognito`, `trace_store` |
| 11 | Nuitka paketleme, autostart, sürüm | — |

Faz 2–3 işin kalbi, geri kalanı düz yazım.

**Faz 0 teslimat kriteri:** tray'de oturan, `Pause+Home` ile yeniden başlayan, `Pause+End` ile çıkan, her tuşu loglayan, seçilen bir tuşu yutabilen program.
