; tus icin 3 basim türüne izin verir (süreleri ayrıca belirtilmelidir)
; kisa basım: 0, orta basım: 1, (uzun basım: 2 opsiyonel)
class CascadeBuilder {
    __New(shortTime := 500, longTime := "") {
        this.shortTime := shortTime
        this.longTime := (longTime != "") ? longTime : ""
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

class singleCascadeHandler {
    static instance := ""

    static getInstance() {
        if (!singleCascadeHandler.instance) {
            singleCascadeHandler.instance := singleCascadeHandler()
        }
        return singleCascadeHandler.instance
    }

    __New() {
        if (singleCascadeHandler.instance) {
            throw Error("CascadeMenu zaten oluşturulmuş! getInstance kullan.")
        }
    }

    getPressType(duration, shortTime, longTime) {
        if (longTime == "") {
            ; Nullable long - sadece 0 ve 1 döner
            return (duration <= shortTime) ? 0 : 1
        }

        ; Normal mod - 0, 1, 2 döner
        if (duration <= shortTime) {
            return 0
        } else if (duration < longTime) {
            return 1
        } else {
            return 2
        }
    }

    cascadeKey(builder, key := A_ThisHotkey) { ;key opsioynel (gönderen özel tus ise belirtmek icin)
        if (gState.getBusy() > 0) {
            return
        }

        mainKey := builder._mainKey
        exitOnPressType := builder.exitOnPressType
        pairsActions := builder.pairsActions
        previewList := builder.tips
        shortTime := builder.shortTime
        longTime := builder.longTime
        mainKeyExecuted := false

        try {
            gState.setBusy(1)
            startTime := A_TickCount
            beepCount := (longTime != "") ? 2 : 1
            mediumTriggered := false
            longTriggered := false

            while (GetKeyState(key, "P")) {
                duration := A_TickCount - startTime

                ; NULLABLE LONG MODE: Short geçtiğinde hemen mainKey(1) çağır
                if (longTime == "" && duration >= shortTime && !mainKeyExecuted) {
                    if (mainKey != "" && IsObject(mainKey)) {
                        mainKey.Call(1)
                        mainKeyExecuted := true
                    }

                    if (exitOnPressType = 1) {
                        return
                    }
                    break  ; While'dan çık, pairs'e geç
                }

                ; Medium beep (normal 3-level mode)
                if (longTime != "" && duration >= shortTime && beepCount >= 1 && !mediumTriggered) {
                    SoundBeep(800, 50)
                    beepCount--
                    mediumTriggered := true
                    ; OutputDebug("MEDIUM press detected (" duration " ms)`n")
                }

                ; Long beep (sadece longTime varsa)
                if (longTime != "" && duration >= longTime && beepCount >= 1 && !longTriggered) {
                    SoundBeep(800, 50)
                    beepCount--
                    longTriggered := true
                    ; OutputDebug("LONG press detected (" duration " ms)`n")
                }

                ; Ana tuş basılıyken yancı tuş kontrolü
                ; Inputhook ta ölcebiliyor ama tusun süresini dinledigimiz icin iptal
                gState.setBusy(2)
                for p in pairsActions {
                    if (GetKeyState(p.key, "P")) {
                        KeyWait p.key
                        p.action.Call(this.getPressType(A_TickCount - startTime, shortTime, longTime))
                        return
                    }
                }
                Sleep(30)
            }

            ; NORMAL MODE veya SHORT PRESS
            if (!mainKeyExecuted) {
                mainHoldTime := A_TickCount - startTime
                mainPressType := this.getPressType(mainHoldTime, shortTime, longTime)

                ; Ana tuş aksiyonu
                if (mainKey != "" && IsObject(mainKey)) {
                    mainKey.Call(mainPressType)
                }

                ; Exit threshold kontrolü
                if (mainPressType = exitOnPressType) {
                    return
                }
            }

            ; Preview göster
            gState.setBusy(1)
            previewText := ""
            if (IsObject(builder.previewCallback)) {
                currentPressType := mainKeyExecuted ? 1 : this.getPressType(A_TickCount - startTime, shortTime, longTime)
                previewList := builder.previewCallback.Call(this, currentPressType)
                if (previewList.Length > 0) {
                    for item in previewList {
                        previewText .= item "`n"
                    }
                    ToolTip(previewText)
                }
            }

            ; InputHook ile pair bekle
            ih := InputHook()
            ih.VisibleNonText := false
            ih.KeyOpt("{All}", "E")
            ih.Start()
            ih.Wait()

            ; Tooltip'i kapat (ESC veya tekrar basma durumu)
            if (ih.EndKey = "Escape" || ih.EndKey = key) {
                ToolTip("")
                return
            }

            ; Pair action çalıştır
            for p in pairsActions {
                if (p.key = ih.EndKey) {
                    p.action.Call(mainKeyExecuted ? 1 : this.getPressType(A_TickCount - startTime, shortTime, longTime))
                    ToolTip("")
                    return
                }
            }

            SoundBeep(800)
            ToolTip("")

        } catch Error as err {
            gErrHandler.handleError(err.Message " " key, err)
        } finally {
            gState.setBusy(0)
        }
    }

    cascadeCaret() {
        loadSave(dt, number) {
            gClipManager.loadFromSlot(number)
        }

        builder := CascadeBuilder(350)  ; 2 level mode
            .mainKey((dt) {
                switch (dt) {
                    case 0:
                        SendInput("{SC029}")
                    case 1:
                        gClipManager.showSlotsSearch()
                }
            })
            .setExitOnPressType(0)
            .pairs("1", "Slot 1", (dt) => loadSave(dt, 1))
            .pairs("2", "Slot 2", (dt) => loadSave(dt, 2))
            .pairs("3", "Slot 3", (dt) => loadSave(dt, 3))
            .pairs("4", "Slot 4", (dt) => loadSave(dt, 4))
            .pairs("5", "Slot 5", (dt) => loadSave(dt, 5))
            .pairs("6", "Slot 6", (dt) => loadSave(dt, 6))
            .pairs("7", "Slot 7", (dt) => loadSave(dt, 7))
            .pairs("8", "Slot 8", (dt) => loadSave(dt, 8))
            .pairs("9", "Slot 9", (dt) => loadSave(dt, 9))
            .pairs("0", "Slot 0", (dt) => loadSave(dt, 13))
        ; .setPreview((b, pressType) => gClipManager.getSlotsPreviewText())

        gCascade.cascadeKey(builder, "^")
    }

    cascadeTab() {
        builder := CascadeBuilder(350)  ; 2 level mode
            .mainKey((dt) {
                switch (dt){
                    case 0:
                        SendInput("{Tab}")
                    case 1:
                        gClipManager.showHistorySearch()

                }
            })
            .setExitOnPressType(0)
            .pairs("1", "History 1", (dt) => gClipManager.loadFromHistory(1))
            .pairs("2", "History 2", (dt) => gClipManager.loadFromHistory(2))
            .pairs("3", "History 3", (dt) => gClipManager.loadFromHistory(3))
            .pairs("4", "History 4", (dt) => gClipManager.loadFromHistory(4))
            .pairs("5", "History 5", (dt) => gClipManager.loadFromHistory(5))
            .pairs("6", "History 6", (dt) => gClipManager.loadFromHistory(6))
            .pairs("7", "History 7", (dt) => gClipManager.loadFromHistory(7))
            .pairs("8", "History 8", (dt) => gClipManager.loadFromHistory(8))
            .pairs("9", "History 9", (dt) => gClipManager.loadFromHistory(9))
        ; .setPreview((b, pressType) => gClipManager.getHistoryPreviewList())

        gCascade.cascadeKey(builder, "Tab")
    }

    cascadeCaps() {
        gState.updateActiveWindow()
        profile := gAppShorts.findProfileByWindow()

        if (!profile) {
            ; Profile yoksa normal CapsLock toggle
            SetCapsLockState(!GetKeyState("CapsLock", "T"))
            return
        }

        loadMacro(number) {
            if (number > profile.shortCuts.Length) {
                ToolTip("Slot boş"), SetTimer(() => ToolTip(), -1000)
                return
            }
            profile.playAt(number)
        }

        builder := CascadeBuilder(350)  ; 2 level mode
            .mainKey((dt) {
                if (dt = 0) {
                    local caps := !GetKeyState("CapsLock", "T")
                    ShowTip(caps ? "CAPSLOCK " : "capsLock")
                    SetCapsLockState(caps)
                }
            })
            .setExitOnPressType(0)
            .pairs("1", "Action 1", (dt) => loadMacro(1))
            .pairs("2", "Action 2", (dt) => loadMacro(2))
            .pairs("3", "Action 3", (dt) => loadMacro(3))
            .pairs("4", "Action 4", (dt) => loadMacro(4))
            .pairs("5", "Action 5", (dt) => loadMacro(5))
            .pairs("6", "Action 6", (dt) => loadMacro(6))
            .pairs("7", "Action 7", (dt) => loadMacro(7))
            .pairs("8", "Action 8", (dt) => loadMacro(8))
            .pairs("9", "Action 9", (dt) => loadMacro(9))
            .setPreview((b, pressType) => profile.getShortCutsPreview())

        gCascade.cascadeKey(builder, "CapsLock")
    }
}