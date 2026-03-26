; Türkçe karakter girişi - İki dizilim
; Dizilim 1 (Long Press): uzun basışla Türkçe → c=çÇ  s=şŞ  i=ıİ  g=ğĞ
; Dizilim 2 (Direct):     direkt remap        → ü=ğĞ  sc00D=üÜ  ö=şŞ  ä=ıİ  ,=öÖ  .=çÇ  i=ıİ
;
; ScrollLock OFF     → Türkçe özellikler aktif
; ScrollLock ON      → Türkçe özellikler devre dışı
; ScrollLock uzun    → dizilim değiştir (1 ↔ 2)

global TkLayout := 1
; TURKISH_LONG_PRESS := 0.4 ; 400 / 1000

; ─── ScrollLock: kısa=ON/OFF toggle, uzun=dizilim değiştir ───────────────────
*ScrollLock:: {
    startTime := A_TickCount
    KeyWait "ScrollLock"
    duration := A_TickCount - startTime

    if (duration >= 600) {
        global TkLayout := (TkLayout = 1) ? 2 : 1
        ShowTip("Türkçe dizilim: " TkLayout, TipType.Info, 1200)
    } else {
        SetScrollLockState(!GetKeyState("ScrollLock", "T"))
        ShowTip(GetKeyState("ScrollLock", "T") ? "TR: Kapalı" : "TR: Açık", TipType.Info, 800)
    }
}

; ─── Layout 1 yardımcı: hemen gönder, uzun basışta Türkçe ile değiştir ───────
; $ prefix: hook zorla, Ctrl/Alt/Win kısayolları zaten geçer (yakalanmaz)
_HandleTurkish(key, lower, tkLower, tkUpper) {
    isShift := GetKeyState("Shift", "P")
    isCaps := GetKeyState("CapsLock", "T")
    isUpper := isCaps ? !isShift : isShift  ; CapsLock Shift'i ters çevirir

    ; Normal karakter: {Blind} ile gönder → OS CapsLock+Shift'i halleder, uygulama tekrar uygulamaz
    Send("{Blind}{" lower "}")

    released := KeyWait(key, "T0.4")

    if (!released) {
        KeyWait key
        Send("{BackSpace}")
        SendText(isUpper ? tkUpper : tkLower)
    }
}

; ─── Dizilim 1: Uzun basış ───────────────────────────────────────────────────
; $ = sadece modifier'sız ve Shift kombinasyonunu yakala → Ctrl+C, Alt+G vb. geçer
#HotIf TkLayout = 1 && !GetKeyState("ScrollLock", "T")
$c:: _HandleTurkish("c", "c", "ç", "Ç")
$+c:: _HandleTurkish("c", "c", "ç", "Ç")
$s:: _HandleTurkish("s", "s", "ş", "Ş")
$+s:: _HandleTurkish("s", "s", "ş", "Ş")
$i:: _HandleTurkish("i", "i", "ı", "İ")
$+i:: _HandleTurkish("i", "i", "ı", "İ")
$g:: _HandleTurkish("g", "g", "ğ", "Ğ")
$+g:: _HandleTurkish("g", "g", "ğ", "Ğ")
#HotIf

; ─── Dizilim 2: Direkt remap ─────────────────────────────────────────────────
; sc00D = = / + tuşu (sysCommands bu modda devre dışı kalır)
; ü, ö, ä tuşları klavye düzenine göre vk/sc kodu gerekebilir (Window Spy ile doğrula)
_TkDirect(lower, upper) {
    isShift := GetKeyState("Shift", "P")
    isCaps := GetKeyState("CapsLock", "T")
    SendText((isShift ^ isCaps) ? upper : lower)
}

#HotIf TkLayout = 2 && !GetKeyState("ScrollLock", "T")
$ü:: _TkDirect("ğ", "Ğ")
$+ü:: _TkDirect("ğ", "Ğ")
$sc01B:: _TkDirect("ü", "Ü")
$+sc01B:: _TkDirect("ü", "Ü")
$ö:: _TkDirect("ş", "Ş")
$+ö:: _TkDirect("ş", "Ş")
$ä:: _TkDirect("ı", "İ")
$+ä:: _TkDirect("i", "İ")
$,:: _TkDirect("ö", "Ö")
$+,:: _TkDirect("ö", "Ö")
$.:: _TkDirect("ç", "Ç")
$+.:: _TkDirect("ç", "Ç")
$i:: _TkDirect("ı", "I")
$+i:: _TkDirect("ı", "I")
$y:: _TkDirect("z", "Z")
$z:: _TkDirect("y", "Y")
$sc035:: SendText(".")
$+sc035:: SendText(":")
$sc02b:: SendText(",")
$+sc02b:: SendText(";")
#HotIf