class EC {    ;Enhancements for KeyBuilder
    static tSetExitOnPress := 1

    ; Factory: Tek satırda objeyi damgalayıp döner
    static Create(type, data) => { base: EC.Prototype, type: type, data: data }

    ; kısa yazmak için yardımcı metodlar
    static setExitOnPressType(v) => EC.Create(EC.tSetExitOnPress, v)
}

; mainStart mainEnd bu yapida yok

; tus icin 3 basim türüne izin verir (süreleri ayrıca belirtilmelidir)
; kisa basım: 0, orta basım: 1, (uzun basım: 2 opsiyonel)
class singleKeyHandlerCascade {
    static instance := ""

    static getInstance() {
        if (!singleKeyHandlerCascade.instance) {
            singleKeyHandlerCascade.instance := singleKeyHandlerCascade()
        }
        return singleKeyHandlerCascade.instance
    }

    __New() {
        if (singleKeyHandlerCascade.instance) {
            throw Error("CascadeMenu zaten oluşturulmuş! getInstance kullan.")
        }
    }


    _checkCombo(pairs) {
        for p in pairs {
            if (GetKeyState(p.key, "P")) {
                gState.setBusy(2)
                KeyWait p.key
                p.action.Call()
                return true
            }
        }
        return false
    }


    handle(b, key := A_ThisHotkey) { ;key opsioynel (gönderen özel tus ise belirtmek icin)
        if (gState.getBusy() > 0) {
            return
        }
        /*
                mainKey := b.main_key
                exitOnPressType := b.exitOnPressType
                combos := b.combos
                previewList := b.tips
                shortTime := b.shortTime
                longTime := b.longTime
        */
        mainKeyExecuted := false

        try {
            gState.setBusy(1)
            startTime := A_TickCount
            beepCount := (b.longTime != "") ? 2 : 1
            mediumTriggered := false
            longTriggered := false

            while (GetKeyState(key, "P")) {
                duration := A_TickCount - startTime

                ; NULLABLE LONG MODE: Short geçtiğinde hemen mainKey(1) çağır
                ; if (longTime == "" && duration >= shortTime && !mainKeyExecuted) {
                ;     if (mainKey != "" && IsObject(mainKey)) {
                ;         OutputDebug("NULLABLE LONG MODE: SHORT press detected (" duration " ms), calling mainKey(1)`n")
                ;         mainKey.Call(1)
                ;         mainKeyExecuted := true
                ;     }

                ;     if (exitOnPressType == 1) {
                ;         return
                ;     }
                ;     break  ; While'dan çık, pairs'e geç
                ; }

                ; Medium beep (normal 3-level mode)
                if (b.longTime != "" && duration >= b.shortTime && beepCount >= 1 && !mediumTriggered) {
                    SoundBeep(800, 50)
                    beepCount--
                    mediumTriggered := true
                    OutputDebug("MEDIUM press detected (" duration " ms)`n")
                }

                ; Long beep (sadece longTime varsa)
                if (b.longTime != "" && duration >= b.longTime && beepCount >= 1 && !longTriggered) {
                    SoundBeep(800, 50)
                    beepCount--
                    longTriggered := true
                    OutputDebug("LONG press detected (" duration " ms)`n")
                }

                ; Ana tuş basılıyken yancı tuş kontrolü
                ; Inputhook ta ölcebiliyor ama tusun süresini dinledigimiz icin iptal
                OutputDebug("set busy 2`n")
                gState.setBusy(2)
                if (this._checkCombo(b.combos)) {
                    return
                }
                Sleep(30)
            }

            ; NORMAL MODE veya SHORT PRESS
            if (!mainKeyExecuted) {
                mainHoldTime := A_TickCount - startTime
                mainPressType := KeyBuilder.getPressType(mainHoldTime, b.shortTime, b.longTime)

                ; Ana tuş aksiyonu
                if (b.main_key != "" && IsObject(b.main_key)) {
                    b.main_key.Call(mainPressType)
                }

                ; Exit threshold kontrolü
                if (mainPressType == b.exitOnPressType) {
                    return
                }
            }

            ; Preview göster
            gState.setBusy(1)
            previewText := ""
            if (IsObject(b.previewCallback)) {
                currentPressType := mainKeyExecuted ? 1 : KeyBuilder.getPressType(A_TickCount - startTime, b.shortTime, b.longTime)
                previewList := b.previewCallback.Call(this, currentPressType)
                if (previewList.Length > 0) {
                    for item in previewList {
                        previewText .= item "`n"
                    }
                    ToolTip(previewText)
                }
            }


            ; ; Süre aşımı: timeOut sonunda menü kapanır
            ; if (previewList.Length > 0) {
            ;     ; OutputDebug("Menü süre aşımı (" timeOut "ms), kapanıyor`n")
            ;     ToolTip()
            ; }

        } catch Error as err {
            gErrHandler.handleError(err.Message " " key, err)
        } finally {
            gState.setBusy(0)
        }
    }

    cascadeCaret() {
        loadSave(no) {
            gClipSlot.loadFromSlot("", no)
        }

        builder := KeyBuilder(350)  ; 2 level mode
            .mainKey((dt) {
                switch (dt) {
                    case 1: SendInput("{SC029}")
                    case 2: gClipSlot.showSlotsSearch()
                }
            })
            .setExitOnPressType(1)
            .combo("1", "Slot 1", () => loadSave(1))
            .combo("2", "Slot 2", () => loadSave(2))
            .combo("3", "Slot 3", () => loadSave(3))
            .combo("4", "Slot 4", () => loadSave(4))
            .combo("5", "Slot 5", () => loadSave(5))
            .combo("6", "Slot 6", () => loadSave(6))
            .combo("7", "Slot 7", () => loadSave(7))
            .combo("8", "Slot 8", () => loadSave(8))
            .combo("9", "Slot 9", () => loadSave(9))
            .combo("0", "Slot 0", () => loadSave(10))
            .build()
        this.handle(builder, "^")
    }

    cascadeTab() {
        loadSave(no) {
            gClipSlot.loadFromSlot(gClipSlot.defaultGroupName, no)
        }

        builder := KeyBuilder(350)
            .mainKey((dt) {
                switch (dt) {
                    case 1: SendInput("{Tab}")
                    case 2: gClipHist.showHistorySearch()
                }
            })
            .setExitOnPressType(1)
            .combo("1", "History 1", () => loadSave(1))
            .combo("2", "History 2", () => loadSave(2))
            .combo("3", "History 3", () => loadSave(3))
            .combo("4", "History 4", () => loadSave(4))
            .combo("5", "History 5", () => loadSave(5))
            .combo("6", "History 6", () => loadSave(6))
            .combo("7", "History 7", () => loadSave(7))
            .combo("8", "History 8", () => loadSave(8))
            .combo("9", "History 9", () => loadSave(9))
            .build()
        this.handle(builder, "Tab")
    }


    cascadeCaps() {
        builder := KeyBuilder(350)
            .mainKey((dt) {
                switch (dt) {
                    case 1:
                        local caps := !GetKeyState("CapsLock", "T")
                        ShowTip(caps ? "CAPSLOCK" : "capslock", TipType.Info)
                        SetCapsLockState(caps)
                    case 2:
                        gClipHist.showHistorySearch()
                }
            })
            .setExitOnPressType(1)
            .combo("1", "History 1", () => gClipHist.loadFromHistory(1))
            .combo("2", "History 2", () => gClipHist.loadFromHistory(2))
            .combo("3", "History 3", () => gClipHist.loadFromHistory(3))
            .combo("4", "History 4", () => gClipHist.loadFromHistory(4))
            .combo("5", "History 5", () => gClipHist.loadFromHistory(5))
            .combo("6", "History 6", () => gClipHist.loadFromHistory(6))
            .combo("7", "History 7", () => gClipHist.loadFromHistory(7))
            .combo("8", "History 8", () => gClipHist.loadFromHistory(8))
            .combo("9", "History 9", () => gClipHist.loadFromHistory(9))
            .build()
        this.handle(builder, "CapsLock")
    }
}

/*
class CascadeBuilder {
    __New(shortTime := 500, longTime := "") {
        this.shortTime := shortTime
        this.longTime := (longTime != "") ? longTime : ""
        this.exitOnPressType := -1
        this.durationType := -1
        this._mainKey := ""
        this.previewCallback := ""
        this.combos := []
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

    combo(key, desc, fn) {
        this.combos.Push({ key: key, desc: desc, action: fn })
        this.tips.Push(key ": " desc)
        return this
    }

    getDurationType() => this.durationType

    getPairsTips() {
        currentTips := []
        for pair in this.combos {
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
*/


/*
    cascadeCaret() {
        loadSave(number) {
            gClipSlot.loadFromSlot(gClipSlot.defaultGroupName, number)
        }

        builder := CascadeBuilder(350)  ; 2 level mode
            .mainKey((dt) {
                switch (dt) {
                    case 0:
                        SendInput("{SC029}")
                    case 1:
                        gClipSlot.showSlotsSearch()
                }
            })
            .setExitOnPressType(0)
            .combos("1", "Slot 1", () => loadSave(1))
            .combos("2", "Slot 2", () => loadSave(2))
            .combos("3", "Slot 3", () => loadSave(3))
            .combos("4", "Slot 4", () => loadSave(4))
            .combos("5", "Slot 5", () => loadSave(5))
            .combos("6", "Slot 6", () => loadSave(6))
            .combos("7", "Slot 7", () => loadSave(7))
            .combos("8", "Slot 8", () => loadSave(8))
            .combos("9", "Slot 9", () => loadSave(9))
            .combos("0", "Slot 0", () => loadSave(10))
        ; .setPreview((b, pressType) => gClipManager.getSlotsPreviewText())

        gCascade.cascadeKey(builder, "^")
    }

        cascadeTab() {
            builder := CascadeBuilder(350)  ; 2 level mode
                .mainKey((dt) {
                    switch (dt) {
                        case 0:
                            SendInput("{Tab}")
                        case 1:
                            gClipHist.showHistorySearch()
                    }
                })
                .setExitOnPressType(0)
                .combo("1", "History 1", () => gClipHist.loadFromHistory(1))
                .combo("2", "History 2", () => gClipHist.loadFromHistory(2))
                .combo("3", "History 3", () => gClipHist.loadFromHistory(3))
                .combo("4", "History 4", () => gClipHist.loadFromHistory(4))
                .combo("5", "History 5", () => gClipHist.loadFromHistory(5))
                .combo("6", "History 6", () => gClipHist.loadFromHistory(6))
                .combo("7", "History 7", () => gClipHist.loadFromHistory(7))
                .combo("8", "History 8", () => gClipHist.loadFromHistory(8))
                .combo("9", "History 9", () => gClipHist.loadFromHistory(9))
            ; .setPreview((b, pressType) => gClipHist.getHistoryPreviewList())

            this.handle(builder, "Tab")
        }

    cascadeCaps() {
        builder := CascadeBuilder(350)  ; 2 level mode
            .mainKey((dt) {
                switch (dt) {
                    case 0:
                        local caps := !GetKeyState("CapsLock", "T")
                        ShowTip(caps ? "CAPSLOCK " : "capsLock")
                        SetCapsLockState(caps)
                    case 1:
                        gClipHist.showHistorySearch()
                }
            })
            .setExitOnPressType(0)
            .combo("1", "History 1", () => gClipHist.loadFromHistory(1))
            .combo("2", "History 2", () => gClipHist.loadFromHistory(2))
            .combo("3", "History 3", () => gClipHist.loadFromHistory(3))
            .combo("4", "History 4", () => gClipHist.loadFromHistory(4))
            .combo("5", "History 5", () => gClipHist.loadFromHistory(5))
            .combo("6", "History 6", () => gClipHist.loadFromHistory(6))
            .combo("7", "History 7", () => gClipHist.loadFromHistory(7))
            .combo("8", "History 8", () => gClipHist.loadFromHistory(8))
            .combo("9", "History 9", () => gClipHist.loadFromHistory(9))

        this.handle(builder, "CapsLock")
    }
}
*/
