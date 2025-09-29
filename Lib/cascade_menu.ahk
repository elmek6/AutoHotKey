class CascadeBuilder {
    __New(shortTime := 500, longTime := 1500) {
        this.shortTime := shortTime
        this.longTime := longTime
        this.timeOut := 30000
        this.exitOnPressType := -1
        this.durationType := -1

        this._mainKey := ""
        this.previewCallback := ""
        this.pairsActions := []
        this.tips := []
    }

    mainKey(fn) {
        this._mainKey := fn
        return this
    }

    setExitOnPressType(ms) { ;0 hata mi?
        this.exitOnPressType := ms
        return this
    }

    setTimeOut(ms) { ;no action will close popup default 30sec
        this.timeOut := ms
        return this
    }

    pairs(key, desc, fn) {
        this.pairsActions.Push({ key: key, desc: desc, action: fn })
        this.tips.Push(key ": " desc)
        return this
    }

    getDurationType() => this.durationType

    getPairsTips() {
        currentTips := []
        for pair in this.pairsActions {
            currentTips.Push(pair.key ": " pair.desc)
        }
        return currentTips
    }

    ; setPreview(prelist) {this.tips := prelist}
    setPreview(callback) {
        if (IsObject(callback)) {
            this.previewCallback := callback ; Callback'i sakla
            ; this.tips := callback.Call(this) ; Direkt çağır ve tips'e ata
        } else {
            throw Error("setPreview: Callback bir fonksiyon olmalı!")
        }
        return this
    }
    /*
        setPreview(callback) {
            if (IsObject(callback)) {
                this.tips := callback.Call(this) ; Fonksiyonu çağır ve builder'ı parametre olarak geçir
            } else {
                throw Error("setPreview: Callback bir fonksiyon olmalı!")
            }
            return this
        }
    */
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

    ;short 500 medium 1500 long 0 1 2
    ;short medium 2000 2ßßß long 0 0 2
    getPressType(duration, shortTime, longTime) {
        if (duration <= shortTime) {
            result := 0
        } else if (duration > shortTime && duration < longTime) {
            result := 1
        } else {
            result := 2
        }
        this.durationType := result
        return result
    }

    cascadeKey(builder, key := A_ThisHotkey) { ;key opsioynel (gönderen özel tus ise belirtmek icin)
        if (state.getBusy() > 0) {
            return
        }

        mainKey := builder._mainKey
        exitOnPressType := builder.exitOnPressType
        pairsActions := builder.pairsActions
        previewList := builder.tips
        shortTime := builder.shortTime
        longTime := builder.longTime
        timeOut := builder.timeOut
        senderKey := key
        durationType := -1

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
                Sleep(30)
            }
            mainHoldTime := A_TickCount - startTime
            mainPressType := this.getPressType(mainHoldTime, shortTime, longTime)

            ; Ana tuş aksiyonu
            if (mainKey != "" && IsObject(mainKey)) {
                mainKey.Call(mainPressType)
            }

            ; Exit threshold kontrolü, yoksa -1
            if (mainPressType = exitOnPressType) {
                if (previewList.Length > 0) {
                    ToolTip ("")
                }
                return
            }

            state.setBusy(2)
            if (IsObject(builder.previewCallback)) {
                previewList := builder.previewCallback.Call(this, mainPressType)
                if (previewList.Length > 0) {
                    text := ""
                    for i, item in previewList {
                        text .= item "`n"
                    }
                    ToolTip(text)
                }
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
                        p.action.Call(this.getPressType(sideHoldTime, shortTime, longTime))
                        ToolTip("")
                        break
                    } else if GetKeyState(senderKey, "P") || GetKeyState("Esc", "P") {
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
            errHandler.handleError(err.Message " " key, err)
        } finally {
            state.setBusy(0)
        }
    }

    handleCaps() { ;VK14  SC03A
        builder := CascadeBuilder(400, 2500)
            .mainKey((dt) {
                if (dt = 0)
                    SetCapsLockState(!GetKeyState("CapsLock", "T"))
            })
            .setExitOnPressType(0)
            .pairs("1", "Load History 1", (dt) => clipManager.loadFromHistory(1))
            .pairs("2", "Load History 2", (dt) => clipManager.loadFromHistory(2))
            .pairs("3", "Load History 3", (dt) => clipManager.loadFromHistory(3))
            .pairs("4", "Load History 4", (dt) => clipManager.loadFromHistory(4))
            .pairs("5", "Load History 5", (dt) => clipManager.loadFromHistory(5))
            .pairs("6", "Load History 6", (dt) => clipManager.loadFromHistory(6))
            .pairs("7", "Load History 7", (dt) => clipManager.loadFromHistory(7))
            .pairs("8", "Load History 8", (dt) => clipManager.loadFromHistory(8))
            .pairs("9", "Load History 9", (dt) => clipManager.loadFromHistory(9))
            .pairs("s", "Show History Search", (dt) => clipManager.showHistorySearch())
            .setPreview((b, pressType) {
                if (pressType = 1) {
                    return clipManager.getHistoryPreviewList()
                } else {
                    return []
                }
            })
        cascade.cascadeKey(builder, "CapsLock")
    }


}