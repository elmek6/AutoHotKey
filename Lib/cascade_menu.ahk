class CascadeBuilder {
    __New(shortTime := 500, longTime := 1500) {
        this._mainKey := ""
        this._sideKey := ""
        this._exitOnPressThreshold := longTime
        this.shortTime := shortTime  ; Kısa basma: <500ms
        this.longTime := longTime    ; Uzun basma: >1500ms
        this.pairsActions := []
        this.tips := []
    }

    mainKey(fn) {
        this._mainKey := fn
        return this
    }

    sideKey(fn) {
        this._sideKey := fn
        return this
    }

    exitOnPressThreshold(ms) {
        this._exitOnPressThreshold := ms
        return this
    }

    pairs(key, desc, fn) {
        this.pairsActions.Push({ key: key, desc: desc, action: fn })
        this.tips.Push(key ": " desc)
        return this
    }

    setPreview(list := []) {
        this.tips := list
        return this.tips
    }
}

class CascadeMenu {
    static instance := ""

    static getInstance() {
        if (!CascadeMenu.instance) {
            CascadeMenu.instance := CascadeMenu()
        }
        return CascadeMenu.instance
    }

    __New() {
        if (CascadeMenu.instance) {
            throw Error("CascadeMenu zaten oluşturulmuş! getInstance kullan.")
        }
    }

    cascadeKey(builder, key) {
        mainKey := builder._mainKey
        sideKey := builder._sideKey
        exitOnPressThreshold := builder._exitOnPressThreshold
        pairsActions := builder.pairsActions
        previewList := builder.tips
        shortTime := builder.shortTime
        longTime := builder.longTime

        _checkPairs(pairsActions, yanSüre) {
            for p in pairsActions {
                if (GetKeyState(p.key, "P")) {
                    state.setBusy(2)
                    KeyWait p.key
                    keyCounts.inc(p.key)
                    p.action.Call(yanSüre)
                    return true
                }
            }
            return false
        }

        if (state.getBusy() > 0) {
            OutputDebug("Busy state, ignoring key: " key "`n")
            return
        }

        try {
            state.setBusy(1)
            keyCounts.inc(key)

            ; Ana tuş süresi ölçümü
            startTime := A_TickCount
            beepCount := 2
            mediumTriggered := false
            longTriggered := false
            while (GetKeyState(key, "P")) {
                duration := A_TickCount - startTime

                ; Orta basma (500-1500ms)
                if (duration >= shortTime && beepCount == 2) {
                    SoundBeep(800, 50)
                    beepCount--
                    mediumTriggered := true
                    OutputDebug("MEDIUM press detected (" duration " ms)`n")
                }
                ; Uzun basma (≥ 1500ms)
                if (duration >= longTime && beepCount == 1) {
                    SoundBeep(800, 50)
                    beepCount--
                    longTriggered := true
                    OutputDebug("LONG press detected (" duration " ms)`n")
                }

                ; Ana tuş basılıyken yancı tuş kontrolü
                for p in pairsActions {
                    if (GetKeyState(p.key, "P")) {
                        if (p.key = key) {
                            OutputDebug("Same key pressed, exiting`n")
                            ToolTip()
                            return
                        }
                        OutputDebug("Pressed together with key: " key "_" p.key "`n")
                        KeyWait p.key
                        ToolTip()
                        return
                    }
                }
                Sleep(10)
            }
            anaSüre := A_TickCount - startTime
            OutputDebug("Ana tuş süresi: " anaSüre "ms`n")

            ; Ana tuş aksiyonu
            if (mainKey != "" && IsObject(mainKey)) {
                mainKey.Call(anaSüre)
            }

            ; Exit threshold kontrolü
            if (anaSüre >= exitOnPressThreshold) {
                OutputDebug("Ana tuş süresi exitOnPressThreshold (" exitOnPressThreshold "ms) aşıldı, yan tuş dinlenmiyor`n")
                return
            }

            ; Menü göster
            if (previewList.Length > 0) {
                text := ""
                for i, item in previewList {
                    text .= item "`n"
                }
                ToolTip(text)
            }

            ; Yan tuş dinle (GetKeyState ile, 5s süre sınırı)
            yanStartTime := A_TickCount
            yanSüre := 0
            pressedKey := ""
            beepCount := 2
            while (A_TickCount - yanStartTime < 5000) { ; 5s bekle
                for p in pairsActions {
                    if (GetKeyState(p.key, "P")) {
                        pressedKey := p.key
                        if (pressedKey = key) {
                            OutputDebug("Same key pressed after release, exiting`n")
                            ToolTip()
                            return
                        }
                        ; Yan tuş süresi ölç
                        yanStartTime := A_TickCount
                        while (GetKeyState(pressedKey, "P")) {
                            yanSüre := A_TickCount - yanStartTime
                            if (yanSüre >= shortTime && beepCount == 2) {
                                SoundBeep(800, 50)
                                beepCount--
                            }
                            if (yanSüre >= longTime && beepCount == 1) {
                                SoundBeep(800, 50)
                                beepCount--
                            }
                            Sleep(10)
                        }
                        OutputDebug("Yan tuş: " pressedKey "`n")
                        OutputDebug("Yan tuş süresi: " yanSüre "ms`n")
                        break
                    }
                }
                if (pressedKey != "") {
                    break
                }
                Sleep(10)
            }

            ; Yan tuş varsa aksiyonları çalıştır
            if (pressedKey != "" && _checkPairs(pairsActions, yanSüre)) {
                ToolTip()
                return
            }

            ; Yan tuş için sideKey callback
            if (pressedKey != "" && sideKey != "" && IsObject(sideKey)) {
                ; HotIf ile yancı tuşu blokla
                HotIf (*) => GetKeyState(key, "P") ? 0 : 1
                Hotkey pressedKey, (*) => 0, "On"
                sideKey.Call(yanSüre)
                Hotkey pressedKey, "Off"
                HotIf
            }

            ; Süre aşımı: 5s sonunda menü kapanır
            if (A_TickCount - yanStartTime >= 5000 && previewList.Length > 0) {
                OutputDebug("Menü süre aşımı (5000ms), kapanıyor`n")
                ToolTip()
            }

        } catch Error as err {
            errHandler.handleError(err.Message " " key)
        } finally {
            state.setBusy(0)
        }
    }
}

/*
class CascadeBuilder {
    __New(shortTime := 500, longTime := 1500) {
        this._mainKey := ""
        this._sideKey := ""
        this._exitOnPressThreshold := longTime
        this.shortTime := shortTime  ; Kısa basma: <500ms
        this.longTime := longTime    ; Uzun basma: >1500ms
        this.pairsActions := []
        this.tips := []
    }

    mainKey(fn) {
        this._mainKey := fn
        return this
    }

    sideKey(fn) {
        this._sideKey := fn
        return this
    }

    exitOnPressThreshold(ms) {
        this._exitOnPressThreshold := ms
        return this
    }

    pairs(key, desc, fn) {
        this.pairsActions.Push({ key: key, desc: desc, action: fn })
        this.tips.Push(key ": " desc)
        return this
    }

    setPreview(list := []) {
        this.tips := list
        return this.tips
    }
}

class CascadeMenu {
    static instance := ""

    static getInstance() {
        if (!CascadeMenu.instance) {
            CascadeMenu.instance := CascadeMenu()
        }
        return CascadeMenu.instance
    }

    __New() {
        if (CascadeMenu.instance) {
            throw Error("CascadeMenu zaten oluşturulmuş! getInstance kullan.")
        }
    }

    cascadeKey(builder, key) {
        mainKey := builder._mainKey
        sideKey := builder._sideKey
        exitOnPressThreshold := builder._exitOnPressThreshold
        pairsActions := builder.pairsActions
        previewList := builder.tips
        shortTime := builder.shortTime
        longTime := builder.longTime

        _checkPairs(pairsActions, yanSüre) {
            for p in pairsActions {
                if (GetKeyState(p.key, "P")) {
                    state.setBusy(2)
                    KeyWait p.key
                    keyCounts.inc(p.key)
                    p.action.Call(yanSüre)
                    return true
                }
            }
            return false
        }

        if (state.getBusy() > 0) {
            OutputDebug("Busy state, ignoring key: " key "`n")
            return
        }

        try {
            state.setBusy(1)
            keyCounts.inc(key)

            ; Preview göster
            if (previewList.Length > 0) {
                text := ""
                for i, item in previewList {
                    text .= item "`n"
                }
                ToolTip(text)
            }

            ; Ana tuş süresi ölçümü
            startTime := A_TickCount
            beepCount := 2  ; Kısa ve uzun için 2 beep
            while (GetKeyState(key, "P")) {
                duration := A_TickCount - startTime
                ; Orta basma (shortTime)
                if (duration >= shortTime && beepCount == 2) {
                    SoundBeep(800, 50)
                    beepCount--
                    OutputDebug("MEDIUM press detected (" duration " ms)`n")
                }
                ; Uzun basma (longTime)
                if (duration >= longTime && beepCount == 1) {
                    SoundBeep(800, 50)
                    beepCount--
                    OutputDebug("LONG press detected (" duration " ms)`n")
                }
                ; Ana tuş basılıyken yancı tuş kontrolü
                ih := InputHook("L1 T0.1", "{Esc}") ; Kısa süreli kontrol
                ih.Start()
                if (ih.Input != "" || ih.EndKey != "") {
                    pressedKey := ih.Input != "" ? ih.Input : ih.EndKey
                    ih.Stop()
                    if (pressedKey = key) {
                        OutputDebug("Same key pressed, exiting`n")
                        return
                    }
                    OutputDebug("Pressed together with key: " key "_" pressedKey "`n")
                    if (_checkPairs(pairsActions, 0)) {
                        return
                    }
                    if (sideKey != "" && IsObject(sideKey)) {
                        sideKey.Call(0) ; Birlikte basmada süre 0
                    }
                    return
                }
                ih.Stop()
                Sleep(10)
            }
            anaSüre := A_TickCount - startTime
            OutputDebug("Ana tuş süresi: " anaSüre "ms`n")

            ; Ana tuş aksiyonu
            if (mainKey != "" && IsObject(mainKey)) {
                mainKey.Call(anaSüre)
            }

            ; Exit threshold kontrolü
            if (anaSüre >= exitOnPressThreshold) {
                OutputDebug("Ana tuş süresi exitOnPressThreshold (" exitOnPressThreshold "ms) aşıldı, yan tuş dinlenmiyor`n")
                return
            }

            ; Yan tuş dinle (InputHook ile, tüm tuşları consume et)
            ih := InputHook("L1 T0.2") ; 0.2s bekle
            ih.Start()
            yanSüre := 0
            pressedKey := ""
            yanStartTime := A_TickCount
            beepCount := 2  ; Yan tuş için 2 beep

            while (ih.Input == "" && ih.EndKey == "" && GetKeyState(key, "P") == 0) {
                if (ih.Input != "" || ih.EndKey != "") {
                    pressedKey := ih.Input != "" ? ih.Input : ih.EndKey
                    OutputDebug("Yan tuş: " pressedKey "`n")
                    if (pressedKey = key) {
                        OutputDebug("Same key pressed after release, exiting`n")
                        ih.Stop()
                        return
                    }
                    ; Yan tuş süresi ölç
                    HotIf (*) => GetKeyState(key, "P") ? 0 : 1
                    Hotkey pressedKey, (*) => 0, "On" ; Yancı tuşu blokla
                    while (GetKeyState(pressedKey, "P")) {
                        yanSüre := A_TickCount - yanStartTime
                        if (yanSüre >= shortTime && beepCount == 2) {
                            SoundBeep(800, 50)
                            beepCount--
                        }
                        if (yanSüre >= longTime && beepCount == 1) {
                            SoundBeep(800, 50)
                            beepCount--
                        }
                        Sleep(10)
                    }
                    Hotkey pressedKey, "Off"
                    HotIf
                    OutputDebug("Yan tuş süresi: " yanSüre "ms`n")
                    break
                }
                Sleep(10)
            }
            ih.Stop()

            ; Yan tuş aksiyonu
            if (pressedKey != "" && _checkPairs(pairsActions, yanSüre)) {
                return  ; Pairs bulundu, çık
            }

            ; Yan tuş varsa sideKey çalıştır
            if (pressedKey != "" && sideKey != "" && IsObject(sideKey)) {
                sideKey.Call(yanSüre)
            }

        } catch Error as err {
            errHandler.handleError(err.Message " " key)
        } finally {
            if (previewList.Length > 0) {
                ToolTip()
            }
            state.setBusy(0)
        }
    }
}
*/