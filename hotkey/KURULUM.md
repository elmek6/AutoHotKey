# cascade -- yeni bilgisayarda kurulum

Bu klasorde calismak icin gereken HER SEY var; eksik olan tek sey `.venv`
(paketler). Onu tek komutla kuruyorsun.

## En kisa yol (onerilen): uv

`uv`, Python'i DA kendisi indiriyor -- ayrica Python kurmana gerek yok.

1. PowerShell ac, `uv`yi kur:

       powershell -c "irm https://astral.sh/uv/install.ps1 | iex"

   (ya da winget: `winget install astral-sh.uv`)

2. PowerShell'i kapatip yeniden ac, bu klasore gel:

       cd "$env:USERPROFILE\Documents\AutoHotKey\hotkey"

3. Paketleri kur (`.python-version` sayesinde 3.13'u kendi indirir):

       uv sync

4. Bitti. Calistir:

   * `baslat.vbs`      -- cift tikla, konsol acilmaz (normal kullanim)
   * `hata-ayikla.cmd` -- konsol acik kalir, hatalari gorursun

   Windows ile birlikte acilsin istiyorsan `baslat.vbs`in KISAYOLUNU
   `shell:startup` klasorune koy.

## uv istemiyorsan: elle Python

1. **python.org'dan Python 3.13 x64.** Microsoft Store surumu OLMAZ --
   COM/hook/registry cagrilari Store sandbox'ina takiliyor.
   Kurulumda "Add python.exe to PATH" isaretli olsun.

2. Bu klasorde sanal ortami kur ve paketleri yaz:

       py -3.13 -m venv .venv
       .venv\Scripts\python.exe -m pip install PySide6 orjson pillow
       .venv\Scripts\python.exe -m pip install winrt-runtime winrt-Windows.Foundation winrt-Windows.Foundation.Collections winrt-Windows.Globalization winrt-Windows.Graphics.Imaging winrt-Windows.Media.Ocr winrt-Windows.Storage.Streams

Her iki yol da `.venv`i BU klasorun icine kurar; `baslat.vbs` ve
`hata-ayikla.cmd` oraya bakiyor.

## Gercekte kullanilan paketler

Kodun import ettigi dis paketler yalnizca sunlar:

| paket | ne icin | olmazsa |
|---|---|---|
| **PySide6** | butun arayuz, olay dongusu | program hic acilmaz |
| **orjson** | pano/slot/incognito dosyalari | program hic acilmaz |
| **Pillow** | gorsel pano, ekran yakalama | program hic acilmaz |
| **winrt-\*** (7 paket) | Windows OCR (F14) | program ACILIR, yalniz OCR calismaz |

`pyproject.toml`da ayrica pywin32, comtypes, mss, psutil, watchdog,
pydantic yaziyor ama su an hicbiri import EDILMIYOR (gecis planindan
kalma). `uv sync` onlari da kurar, zarari yok.

Geri kalan her sey standart kutuphane: `ctypes`, `winreg`, `winsound`,
`subprocess`, `queue`, `threading`...

## Bilinmesi gerekenler

* **Yalniz Windows.** `ctypes` + Win32 API'lerine dogrudan baglanir.
* **`uv.lock` winrt paketlerini icermiyor** (pip ile kurulmuslardi).
  `uv sync` bunu fark edip kilidi kendisi tazeliyor -- ilk kurulumda
  internet gerekiyor.
* **`Files/` klasoru kopyalanmadi.** Icinde pano gecmisi, slotlar ve log
  var; kisisel veri. Program ilk acilista kendisi olusturuyor. Eski
  makinedeki gecmisi tasimak istersen `Files\clipboards.bin` ve
  `Files\slots.json`i elle kopyala.
* **Ayni anda iki kopya calismaz.** Tek ornek kilidi `cascade` adiyla
  aliniyor ve YENI ornek eskisini dusuruyor (AHK'deki
  `#SingleInstance Force` davranisi).
* **Incognito modulu registry'ye yaziyor** (`cascade/incognito.py`):
  yalniz HKCU, yonetici hakki gerekmiyor.
