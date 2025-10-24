#Include <HotGestures>

getPressType(fn, key := "", shortTime := 300, longTime := 3000) {
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


; detectPressType((pressType) => OutputDebug("Press type: " pressType "`n"))
; short press: 0, medium press: 1, long press: 2, double press: -1
detectPressType(fn, key := "", short := 300, long := 1000, gap := 100) {
    if (key = "") {
        key := SubStr(A_ThisHotkey, -1) ; sondan kesiyor diyor ama ?
    }
    result := KeyWait(key, "T" (short / 1000))

    if (result) {
        ; Short süre içinde bırakıldı -> Kısa basım, double kontrolü yap
        result := KeyWait(key, "D T" (gap / 1000))

        if (result) {
            KeyWait(key)
            fn.Call(-1)
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

class FKeyBuilder {
    __New() {
        this._mainStart := ""
        this._mainDefault := ""
        this._mainEnd := ""
        this.gestures := []
        this.comboActions := []
        this.tips := [A_ThisHotkey]
    }

    mainStart(fn) {
        this._mainStart := fn
        return this
    }

    mainDefault(fn) {
        this._mainDefault := fn
        return this
    }

    mainEnd(fn) {
        this._mainEnd := fn
        return this
    }

    setPreview(list := []) {
        this.tips := list
        return this.tips
    }

    mainGesture(gesture, fn) {
        this.gestures.Push({ gesture: gesture, action: fn })
        return this
    }

    combos(key, desc, fn) { ; key, description, callback
        this.comboActions.Push({ key: key, desc: desc, action: fn })
        this.tips.Push(key ": " desc) ;n buraya mi eklesek?
        return this
    }

    ; titles { ; titles property: key ve description listesi döner
    ;     get {
    ;         result := []
    ;         for c in this.comboActions {
    ;             result.Push(c.key ": " c.desc)
    ;         }
    ;         return result
    ;     }
    ; }

}

class singleHotkeyHandler {
    static instance := ""

    static getInstance() {
        if (!singleHotkeyHandler.instance) {
            singleHotkeyHandler.instance := singleHotkeyHandler()
        }
        return singleHotkeyHandler.instance
    }

    __New() {
        if (singleHotkeyHandler.instance) {
            throw Error("HotkeyHandler zaten oluşturulmuş! getInstance kullan.")
        }
        this.hgsRight := ""
    }

    _getPressType(duration, shortTime := 300, longTime := 1000) {
        if (duration < shortTime) {
            return 0  ; short
        } else if (duration < longTime) {
            SoundBeep(800, 50)
            return 1  ; medium
        } else {
            SoundBeep(800, 50)
            SoundBeep(800, 30)
            return 2  ; long
        }
    }

    handleFKey(builder) {
        mainStart := builder._mainStart
        mainDefault := builder._mainDefault
        mainEnd := builder._mainEnd
        gestures := builder.gestures
        comboActions := builder.comboActions
        previewList := builder.tips
        startTime := A_TickCount

        _checkCombo(comboActions) {
            for c in comboActions {
                if (GetKeyState(c.key, "P")) {
                    gState.setBusy(2)
                    KeyWait c.key
                    gKeyCounts.inc(c.key)
                    c.action.Call()
                    ; return true yanci basildigi sürece tekrar calissin
                }
            }
            return false
        }

        if (gState.getBusy() > 0) {
            return
        }

        try {
            gState.setBusy(1)
            key := A_ThisHotkey
            if (SubStr(key, 1, 1) == "~") {
                key := SubStr(key, 2)  ; İlk karakteri at
            }

            gKeyCounts.inc(key)

            if (previewList.Length > 0) { ;belki long press ile cikmasi daha iyi olur?
                text := ""
                for i, item in previewList
                    text .= item "`n"
                ToolTip(text)
            }

            if (mainStart != "" && IsObject(mainStart)) {
                mainStart.Call()
            }

            if (gestures.Length > 0) {
                this.hgsRight := HotGestures()
                for g in gestures {
                    this.hgsRight.Register(g.gesture, g.gesture.Name, g.action)
                }
                this.hgsRight.Start()
            }

            startTime := A_TickCount
            while GetKeyState(key, "P") {
                if (_checkCombo(comboActions)) {
                    if (gestures.Length > 0) {
                        this.hgsRight.Stop()
                    }
                    break
                }
                Sleep 10
            }

            KeyWait key

            if (gestures.Length > 0) {
                this.hgsRight.Stop()
                if (this.hgsRight.Result.Valid) {
                    detectedGesture := this.hgsRight.Result.MatchedGesture
                    for g in gestures {
                        if (detectedGesture == g.gesture) {
                            g.action.Call()
                            return  ; Gesture valid (finally bloğu çalışacak)
                        }
                    }
                }
            }

            if (gState.getBusy() == 1 && mainDefault != "" && IsObject(mainDefault)) {
                mainPressType := this._getPressType(A_TickCount - startTime)
                mainDefault.Call(mainPressType)   ; Gesture yok/invalid, default çalış
            }

            if (mainEnd != "" && IsObject(mainEnd)) {
                mainEnd.Call()
            }
        } catch Error as err {
            gErrHandler.handleError(err.Message " " key)
        } finally {
            if (previewList.Length > 0) {
                ToolTip()
            }
            if (gestures.Length > 0 && IsObject(this.hgsRight)) {
                this.hgsRight.Stop()
            }
            gState.setBusy(0)
        }
    }

    handleLButton() {
        static builder := FKeyBuilder()
            .combos("F14", "LB+F14() => Send('L F14')", () => Send("L F14"))
            .combos("F15", "LB+F15() => Send('L 15')", () => Send("L 15"))
            .combos("F16", "LB+F16() => Send('L 16')", () => Send("L 16"))
            .combos("F17", "LB+F17() => Send('L 17')", () => Send("L 17"))
            .combos("F18", "LB+F18() => Send('L 18')", () => Send("L 18"))
            .combos("F19", "All+Paste", () => gClipManager.press(["^a^v", "{Enter}"]))
            .combos("F20", "Enter", () => Send("{Enter}"))
        builder.setPreview([])
        this.handleFKey(builder)
    }

    handleMButton() {
        static builder := FKeyBuilder()
            .mainDefault((pressType) => {})
            .combos("F15", "Delete Word", () => Send("{RControl down}{vkBF}{RControl up}"))
            .combos("F16", "Find & Paste", () => gClipManager.press(["^f", "{Sleep 100}", "^a^v"]))
            .combos("F17", "Send F17", () => Send("F17"))
            .combos("F18", "Send F18", () => Send("F18"))
            .combos("F19", "Paste & Enter", () => gClipManager.press(["^v", "{Enter}"]))
            .combos("F20", "Enter", () => Send("{Enter}"))
            .combos("F14", "Show History Search", () => gClipManager.showHistorySearch())
        builder.setPreview([])
        this.handleFKey(builder)
    }

    handleF13() {
        static builder := FKeyBuilder()
            ; .mainStart(() => (ToolTip("F13 Paste Mode"), SetTimer(() => ToolTip(), -800)))
            .mainDefault((pressType) {
                pressType == 0
                    ? showF13menu()
                    : Send("abc")
            })
            .mainGesture(HotGestures.Gesture("Right-right:1,0"), () => Send("{Enter}"))
            .mainGesture(HotGestures.Gesture("Right-left:-1,0"), () => Send("{Escape}"))
            .mainGesture(HotGestures.Gesture("Right-up:0,-1"), () => Send("{Home}"))
            .mainGesture(HotGestures.Gesture("Right-down:0,1"), () => Send("{End}"))
            .mainGesture(HotGestures.Gesture("Right-diagonal-down-left:-1,1"), () => WinMinimize("A"))
            .combos("F14", "Click & Paste", () => (Click("Left", 1), gClipManager.press("^v")))
            .combos("F18", "Delete", () => Send("{Delete}"))
        builder.setPreview([])
        this.handleFKey(builder)
    }

    handleF14() {
        static builder := FKeyBuilder()
            .mainDefault((pressType) => showF14menu())
            .mainGesture(HotGestures.Gesture("Right-up:0,-1"), () => Send("{Delete}"))
            .mainGesture(HotGestures.Gesture("Right-down:0,1"), () => Send("{Backspace}"))
            .combos("F15", "Select All", () => Send("^a"))
            .combos("F16", "Select All", () => Send("^a"))
            .combos("F17", "Home", () => Send("{Home}"))
            .combos("F18", "End", () => Send("{End}"))
            .combos("F19", "Select All", () => Send("^a"))
            .combos("F20", "Select All", () => Send("^a"))
            .combos("RButton", "Show Slots Search", () => gClipManager.showSlotsSearch())
        builder.setPreview([])
        this.handleFKey(builder)
    }

    handleF15() {
        static builder := FKeyBuilder()
            .mainDefault((pressType) {
                pressType == 0
                    ? Send("^y")
                    : Send("{Escape}")
            })
            .combos("F13", "Send F13", () => Send("F13 bos"))
            .combos("LButton", "Send F15 L", () => Send("F15 L bos"))
        this.handleFKey(builder)
    }

    handleF16() {
        static builder := FKeyBuilder()
            .mainDefault((pressType) {
                pressType == 0
                    ? Send("^z")
                    : Send("{Enter}")
            })
            .combos("F13", "Send F13", () => Send("F13 bos"))
            .combos("LButton", "Send F16 L", () => Send("F16 L bos"))
        this.handleFKey(builder)
    }

    handleF17() {
        static builder := FKeyBuilder()
            .mainDefault((pressType) {
                pressType == 0
                    ? Send("!{Right}")
                    : Send("{Home}")
            })
            .combos("F14", "3x Click + Delete", () => (Click("Left", 3), Send("{Delete}"), ToolTip("3x Click + Delete"), SetTimer(() => ToolTip(), -800), SoundBeep(600)))
            .combos("F18", "Delete", () => Send("{Delete}"))
            .combos("LButton", "2x Click + Delete", () => (Click("Left", 2), Send("{Delete}")))
            .combos("MButton", "3x Click + Delete", () => (Click("Left", 3), Send("{Delete}")))
        this.handleFKey(builder)
    }

    handleF18() {
        static builder := FKeyBuilder()
            .mainDefault((pressType) {
                pressType == 0
                    ? Send("!{Left}")
                    : Send("{End}")
            })
            .combos("F17", "Cut", () => Send("^x"))
            .combos("F20", "3x Click + Copy", () => (Click("Left", 3), gClipManager.press("^c")))
            .combos("LButton", "Del line VSCode", () => SendInput("^+k"))
        this.handleFKey(builder)
    }

    handleF19() {
        static builder := FKeyBuilder()
            .mainDefault((pressType) {
                switch pressType {
                    case 0: gMemSlots.smartPaste()
                    case 1: Send("^a^v")
                }
            })
            .mainEnd(() => gClipManager.showClipboardPreview())
            .combos("F13", "Select All & Paste", () => gClipManager.press("^a^v"))
            .combos("F14", "3x Click + Paste", () => (Click("Left", 3), gClipManager.press("^v"), ToolTip("3x Click + Paste"), SetTimer(() => ToolTip(), -800)))
            .combos("F20", "Select All & Paste", () => gClipManager.press("^a^v"))
            .combos("LButton", "Click & Paste", () => (Click("Left", 1), gClipManager.press("^v")))
            .combos("MButton", "3x Click + Paste", () => (Click("Left", 3), gClipManager.press("^v")))
        builder.setPreview([])
        this.handleFKey(builder)
    }

    handleF20() {
        static builder := FKeyBuilder()
            .mainDefault((pressType) {
                switch pressType {
                    case 0: gMemSlots.smartCopy()
                    case 1: Send("^x")
                    case 2: gMemSlots.start() ; gState.setAutoClip(1)
                }
            })
            .mainEnd(() => (ClipWait(1), Sleep(50), gClipManager.showClipboardPreview()))
            .combos("F13", "Select All & Copy", () => gClipManager.press("^a^c"))
            .combos("F14", "3x Click + Copy", () => (Click("Left", 3), gClipManager.press("^c"), ToolTip("3x Click + Copy"), SetTimer(() => ToolTip(), -800)))
            .combos("F19", "Select All & Copy", () => gClipManager.press("^a^c"))
            .combos("F18", "3x Click + Copy", () => (Click("Left", 3), gClipManager.press("^c")))
            .combos("LButton", "Click & Copy", () => (Click("Left", 1), gMemSlots.smartCopy()))
            .combos("MButton", "3x Click + Copy", () => (Click("Left", 3), gClipManager.press("^c")))
        builder.setPreview([])
        this.handleFKey(builder)
    }
    /*
        handleNums(number) {
            builder := FKeyBuilder()
                .mainDefault((pressType) => Send(number))
                .combos("SC029", number, () => clipManager.saveToSlot(number))
                .combos("Tab", number, () => Sleep(number * 100))
                .combos("CapsLock", number, () => clipManager.loadFromSlot(number))
            builder.setPreview([])
            this.handleFKey(builder)
        }
    */
}