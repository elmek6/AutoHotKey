class CascadeBuilder {
    __New(shortTime := 500, longTime := 1500) {
        this._mainKey := ""
        this._exitOnPressThreshold := longTime
        this.shortTime := shortTime  ; Kısa basma: <500ms
        this.longTime := longTime    ; Uzun basma: >1500ms
        this.timeOut := 30000
        this.pairsActions := []
        this.tips := []
    }

    mainKey(fn) {
        this._mainKey := fn
        return this
    }

    exitOnPressThreshold(ms) {
        this._exitOnPressThreshold := ms
        return this
    }

    setTimeOut(ms) { ;no action will close popup default 30sec
        this.timeOut := ms
    }

    pairs(key, desc, fn) {
        this.pairsActions.Push({ key: key, desc: desc, action: fn })
        this.tips.Push(key ": " desc)
        return this
    }
    /*
    setPreview(prelist) {
        currentTips := []
        for pair in this.pairsActions {
            currentTips.Push(pair.key ": " pair.desc)
        }
        this.tips := currentTips
        return this.tips
    }
    */

    getPairsTips() {
        currentTips := []
        for pair in this.pairsActions {
            currentTips.Push(pair.key ": " pair.desc)
        }
        return currentTips
    }

    setPreview(prelist) {
        this.tips := prelist
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

    ;short 500 medium 1500 long
    ;short medium 2000 2ßßß long
    getPressType(duration, shortTime, longTime) {
        if (duration <= shortTime) {
            return 0
        } else if (duration > shortTime && duration < longTime) {
            return 1
        } else {
            return 2
        }
    }

    cascadeKey(builder, key := A_ThisHotkey) { ;key opsioynel (gönderen özel tus ise belirtmek icin)
        if (state.getBusy() > 0) {
            return
        }

        mainKey := builder._mainKey
        exitOnPressThreshold := builder._exitOnPressThreshold
        pairsActions := builder.pairsActions
        previewList := builder.tips
        shortTime := builder.shortTime
        longTime := builder.longTime
        timeOut := builder.timeOut
        senderKey := key

        try {
            state.setBusy(1)
            startTime := A_TickCount
            beepCount := 2
            mediumTriggered := false
            longTriggered := false
            while (GetKeyState(key, "P")) {
                duration := A_TickCount - startTime

                if (duration >= shortTime && beepCount == 2) {
                    SoundBeep(800, 50)
                    beepCount--
                    mediumTriggered := true
                    ; OutputDebug("MEDIUM press detected (" duration " ms)`n")
                }
                if (duration >= longTime && beepCount == 1) {
                    SoundBeep(800, 50)
                    beepCount--
                    longTriggered := true
                    ; OutputDebug("LONG press detected (" duration " ms)`n")
                }

                ; Ana tuş basılıyken yancı tuş kontrolü
                for p in pairsActions {
                    if (GetKeyState(p.key, "P")) {
                        OutputDebug("Pressed together with key: " key "_" p.key "`n")
                        KeyWait p.key
                        p.action.Call(this.getPressType(A_TickCount - startTime, shortTime, longTime))
                        ToolTip()
                        return
                    }
                }
                Sleep(10)
            }
            mainHoldTime := A_TickCount - startTime
            ; OutputDebug("Ana tuş süresi: " mainHoldTime "ms`n")

            ; Ana tuş aksiyonu
            if (mainKey != "" && IsObject(mainKey)) {
                mainKey.Call(this.getPressType(mainHoldTime, shortTime, longTime))
            }

            ; Exit threshold kontrolü
            if (mainHoldTime >= exitOnPressThreshold) {
                ; OutputDebug("Ana tuş süresi exitOnPressThreshold (" exitOnPressThreshold "ms) aşıldı, yan tuş dinlenmiyor`n")
                if (previewList.Length > 0) {
                    ToolTip ("")
                }
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
            sideStartTime := A_TickCount
            sideHoldTime := 0
            pressedKey := ""
            beepCount := 2
            while (A_TickCount - sideStartTime < 5000) { ; 5s bekle
                for p in pairsActions {
                    if (GetKeyState(p.key, "P")) {
                        pressedKey := p.key
                        ; Yan tuş süresi ölç
                        sideStartTime := A_TickCount
                        while (GetKeyState(pressedKey, "P")) {
                            sideHoldTime := A_TickCount - sideStartTime
                            if (sideHoldTime >= shortTime && beepCount == 2) {
                                SoundBeep(800, 50)
                                beepCount--
                            }
                            if (sideHoldTime >= longTime && beepCount == 1) {
                                SoundBeep(800, 50)
                                beepCount--
                            }
                            Sleep(10)
                        }
                        ; OutputDebug("Yan tuş: " pressedKey " ms: " sideHoldTime "ms`n")
                        p.action.Call(this.getPressType(sideHoldTime, shortTime, longTime))
                        ToolTip("")
                        break
                    } else if GetKeyState(senderKey, "P") || GetKeyState("Esc", "P") {
                        ; OutputDebug("Same key pressed after release, exiting`n")
                        ToolTip()
                        return
                    }
                }
                if (pressedKey != "") {
                    break
                }
                Sleep(10)
            }

            ; Süre aşımı: 5s sonunda menü kapanır
            if (A_TickCount - sideStartTime >= timeOut && previewList.Length > 0) {
                ; OutputDebug("Menü süre aşımı (5000ms), kapanıyor`n")
                ToolTip()
            }

        } catch Error as err {
            errHandler.handleError(err.Message " " key)
        } finally {
            state.setBusy(0)
        }
    }
}