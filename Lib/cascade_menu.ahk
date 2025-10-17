class CascadeBuilder {
    __New(shortTime := 500, longTime := 1500) {
        this.shortTime := shortTime
        this.longTime := longTime
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

    setPreview(callback) {
        if (IsObject(callback)) {
            this.previewCallback := callback ; Callback'i sakla
        } else {
            throw Error("setPreview: Callback bir fonksiyon olmalı!")
        }
        return this
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
                ; Inputhook ta ölcebiliyor ama tusun süresini dinledigimiz icin iptal
                state.setBusy(2)
                for p in pairsActions {
                    if (GetKeyState(p.key, "P")) {
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

            state.setBusy(1)
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

            ; state.setBusy(1)
            Hotkey("SC001", "Off")

            ih := InputHook()
            ih.VisibleNonText := false
            ih.KeyOpt("{All}", "E") ; 
            ih.Start()
            ih.Wait()

            ; if (ih.EndKey = "Escape") { ; Escape
            ;     ToolTip()
            ;     return
            ; }
            Hotkey("SC001", "On")
            ; pressedTogether := GetKeyState(A_ThisHotkey, "P")
            ; OutputDebug (pressedTogether)

            for p in pairsActions {
                if (p.key = ih.EndKey) {
                    p.action.Call(mainPressType)
                    ToolTip("")
                    return
                }
            }

            SoundBeep(800)
            ToolTip("")

        } catch Error as err {
            errHandler.handleError(err.Message " " key, err)
        } finally {
            state.setBusy(0)
            OutputDebug "0`r"

        }
    }

    cascadeCaret() {
        loadSave(dt, number) {
            if (dt = 2) {
                clipManager.promptAndSaveSlot(number)
            } else {
                clipManager.loadFromSlot(number)
            }
        }

        builder := CascadeBuilder(400, 2500)
            .mainKey((dt) {
                if (dt = 0)
                    SendInput("{SC029}")
            })
            .setExitOnPressType(0)
            .pairs("s", "Search...", (dt) => clipManager.showSlotsSearch())
            .pairs("1", "Test 1", (dt) => loadSave(dt, 1))
            .pairs("2", "Test 2", (dt) => loadSave(dt, 2))
            .pairs("3", "Test 3", (dt) => loadSave(dt, 3))
            .pairs("4", "Test 4", (dt) => loadSave(dt, 4))
            .pairs("5", "Test 5", (dt) => loadSave(dt, 5))
            .pairs("6", "Test 6", (dt) => loadSave(dt, 6))
            .pairs("7", "Test 7", (dt) => loadSave(dt, 7))
            .pairs("8", "Test 8", (dt) => loadSave(dt, 8))
            .pairs("9", "Test 9", (dt) => loadSave(dt, 9))
            .pairs("0", "Test 0", (dt) => loadSave(dt, 13))
            .setPreview((b, pressType) {
                if (pressType == 0) {
                    return []
                } else if (pressType == 1) {
                    ; return builder.getPairsTips()
                    return clipManager.getSlotsPreviewText()
                } else {
                    result := []
                    result.Push("-------------------- SAVE --------------------")
                    result.Push("----------------------------------------------")
                    for v in clipManager.getSlotsPreviewText()
                        result.Push(v)
                    result.Push("kisa basma (" pressType "ms): Daha fazla seçenek")
                    return result
                }
            })
        cascade.cascadeKey(builder, "^")
    }


    cascadeTab() {
        builder := CascadeBuilder(400, 2500)
            .mainKey((dt) {
                if (dt = 0)
                    SendInput("{Tab}")
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
        cascade.cascadeKey(builder, "Tab")
    }


    cascadeEsc() {
        state.updateActiveWindow()
        profile := appShorts.findProfileByWindow()
        if (!profile || profile.shortCuts.Length == 0) {
            ToolTip("yok yok yok"), SetTimer(() => ToolTip(), -1000)
            return
        }
        loadSaveMacro(number) {
            if (number > profile.shortCuts.Length) {
                ToolTip("yok yok"), SetTimer(() => ToolTip(), -1000)
                return
            }
            ; profile.shortCuts.play
            profile.playAt(number)
        }

        builder := CascadeBuilder(400, 2000)
            .mainKey((dt) {
                if (dt = 0)
                    SendInput("{Esc}")
            })
            .setExitOnPressType(0)
            ; .pairs("s", "Search...", (dt) => clipManager.showSlotsSearch())
            ; .pairs("Esc", "Cancel", (dt) => SendInput("{Esc}"))
            .pairs("1", profile.shortCuts[1].shortCutName, (dt) => loadSaveMacro(1))
            .pairs("2", "rec2.ahk", (dt) => loadSaveMacro(2))
            .pairs("3", "rec3.ahk", (dt) => loadSaveMacro(3))
            .pairs("4", "rec4.ahk", (dt) => loadSaveMacro(4))
            .pairs("5", "rec5.ahk", (dt) => loadSaveMacro(5))
            .pairs("6", "rec6.ahk", (dt) => loadSaveMacro(6))
            .pairs("7", "rec7.ahk", (dt) => loadSaveMacro(7))
            .pairs("8", "rec8.ahk", (dt) => loadSaveMacro(8))
            .pairs("9", "rec9.ahk", (dt) => loadSaveMacro(9))
            .setPreview((b, pressType) {
                ; Profile shortCuts preview'larını döndür (ad + kısa açıklama)
                if (pressType = 1) {
                    return profile.getShortCutsPreview()
                } else {
                    return []
                }
            })
        cascade.cascadeKey(builder, "Esc")
    }
}