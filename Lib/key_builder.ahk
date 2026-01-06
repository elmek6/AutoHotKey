; Ortak KeyBuilder - Hem Cascade hem Hotkey için tek yapı
class KeyBuilder {
    __New(short := 350, long := "", gap := "") {
        this.shortTime := short
        this.longTime := long
        this.gapTime := gap

        this.main_key := ""
        this.main_start := ""
        this.main_end := ""

        this.combos := []
        this._tips := []

        this.previewCallback := ""
        this.exitOnPressType := -1

        ; Hotkey özel alanlar (cascade de kullanılmaz, zararsız)
        this.enableVisual := false
        this.enableMouseProfile := ""
        this.gestures := []
        this._extensions := []
    }

    ; Basım türü ayarları: short, long (opsiyonel), gap (double click için opsiyonel)
    setPressType(short := 350, long := "", gap := "") {
        this.shortTime := short
        this.longTime := long
        this.gapTime := gap
        return this
    }

    mainKey(fn) {
        this.main_key := fn
        return this
    }

    mainStart(fn) {
        this.main_start := fn
        return this
    }

    mainEnd(fn) {
        this.main_end := fn
        return this
    }

    ; Metod adı aynı kaldı: combos() – fluent interface bozulmasın diye
    combo(key, desc, fn) {
        this.combos.Push({ key: key, desc: desc, action: fn })
        this._tips.Push(key ": " desc)
        return this
    }

    setPreview(callback) {
        if (IsObject(callback)) {
            this.previewCallback := callback
        } else {
            throw Error("setPreview: Callback bir fonksiyon olmalı!")
        }
        return this
    }

    setExitOnPressType(type) {
        this.exitOnPressType := type
        return this
    }

    extend(extObj) {
        this._extensions.Push(extObj)
        return this ; Zincirleme kullanım için 'this' dönüyoruz
    }
    extensions => this._extensions

    build() {
        return this
    }

    ; === Dışarıdan erişim için yardımcı property'ler (opsiyonel ama faydalı) ===
    ; Eğer handler'larda builder.combos veya builder.tips'e doğrudan erişim lazımsa:
    combo {
        get => this.combos
    }
    tips {
        get => this._tips
    }

    ; Static metod olarak getPressType
    static getPressType(duration, shortTime, longTime) {
        if (longTime == "") {
            return (duration <= shortTime) ? 0 : 1
        }
        if (duration <= shortTime) {
            return 0
        } else if (duration < longTime) {
            return 1
        } else {
            return 2
        }
    }
}

; Global fonksiyon (backward compatibility için)
; getPressType(duration, shortTime, longTime) {
;     return KeyBuilder.getPressType(duration, shortTime, longTime)
; }

/*
getPressTypeTest(fn, key := "", shortTime := 300, longTime := 3000) {
    key := A_ThisHotkey
    startTime := A_TickCount
    beepCount := 2

    while (GetKeyState(key, "P")) {
        duration := A_TickCount - startTime
        if (duration > shortTime && duration < longTime && beepCount > 1) {
            SoundBeep(800, 70)
            beepCount--
        } else if (duration >= longTime && beepCount > 0) {
            SoundBeep(600, 100)
            beepCount--
        }
        Sleep(20)
    }

    if (duration < shortTime) {
        fn.Call(0)
    } else if (duration < longTime) {
        fn.Call(1)
    } else {
        fn.Call(2)
    }
}
*/


; getPressType(shortFn, mediumFn, longFn := "", shortTime := 400, longTime := 1400) {
;     startTime := A_TickCount
;     thisHotkey := A_ThisHotkey
;     beepCount := 2

;     while (GetKeyState(thisHotkey, "P")) {
;         duration := A_TickCount - startTime

;         if (duration < shortTime) {
;             ;     OutputDebug("short tap`n")
;         } else
;             if (duration < longTime && beepCount > 1) {
;                 ; OutputDebug("mid tap`n")
;                 SoundBeep(800, 70)
;                 beepCount--
;             } else
;                 if (duration > longTime && longFn != "" && beepCount > 0) {
;                     ; OutputDebug("long tap`n")
;                     SoundBeep(600, 100)
;                     beepCount--
;                 }

;         Sleep(40)
;     }

;     duration := A_TickCount - startTime

;     if (duration < shortTime) {
;         shortFn.Call()
;     }
;     else if (duration < longTime || longFn == "") {
;         mediumFn.Call()
;     }
;     else if (longFn != "") {
;         longFn.Call()
;     }
; }

/*
; detectPressType((pressType) => OutputDebug("Press type: " pressType "`n"))
; short press: 0, medium press: 1, long press: 2, double press: 4
detectPressTypeTest(fn, key := "", short := 300, long := 1000, gap := 100) {
    if (key = "") {
        key := SubStr(A_ThisHotkey, -1) ; sondan kesiyor diyor ama ?
    }
    result := KeyWait(key, "T" (short / 1000))

    if (result) {
        ; Short süre içinde bırakıldı -> Kısa basım, double kontrolü yap
        result := KeyWait(key, "D T" (gap / 1000))

        if (result) {
            KeyWait(key)
            fn.Call(4)
        } else {
            fn.Call(0)
        }
        return
    }


    ; Medium timeout oldu, long süre bekle
    result := KeyWait(key, "T" ((long) / 1000))

    if (result) {
        ; Long süre içinde bırakıldı -> Uzun basım
        SoundBeep(800, 70)
        fn.Call(1)
    } else {
        ; Long timeout da oldu -> Çok uzun basım (yine de 2 döndür)
        KeyWait(key)
        SoundBeep(600, 100)

        fn.Call(2)
    }
}

*/

/*
ß:: getPressType((pressType) =>
    OutputDebug("Press type: " pressType "`n")
, "ß")

getPressType(cbFn, key, short := 300, medium := 800, long := 1500) {
    ; Tuşun bırakılmasını bekle (short süresi kadar timeout)
    result := KeyWait(key, "T" (short/1000))

    if (result) {
        ; Short süre içinde bırakıldı -> Kısa basım
        cbFn.Call(0)
        return
    }

    ; Short timeout oldu, medium süre bekle
    result := KeyWait(key, "T" ((medium - short)/1000))

    if (result) {
        ; Medium süre içinde bırakıldı -> Orta basım
        cbFn.Call(1)
        return
    }

    ; Medium timeout oldu, long'a kadar bekle veya bırakılana kadar
    KeyWait(key, "T" ((long - medium)/1000))

    ; Her halükarda artık uzun basım
    KeyWait(key)  ; Bırakılmasını bekle
    cbFn.Call(2)
}
*/
