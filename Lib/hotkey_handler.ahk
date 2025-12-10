#Include <HotGestures>

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
        this._enableVisual := true
        this._enableDoubleClick := false
        this._mainEndOnlyCombo := false
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

    combos(key, desc, fn) {
        this.comboActions.Push({ key: key, desc: desc, action: fn })
        this.tips.Push(key ": " desc)
        return this
    }

    enableVisual(value := true) {
        this._enableVisual := value
        return this
    }

    enableDoubleClick(value := false) {
        this._enableVisual := value
        return this
    }

    mainEndOnlyCombo(value := false) {
        this._mainEndOnlyCombo := value
        return this
    }
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

    ; duration, pressType ve görsel feedback'i birlikte yönet
    _detectPressWithVisual(duration, enableVisual, &visualShown) {
        pressType := -1

        ; Short press (0-300ms)
        if (duration < 300) {
            pressType := 0
        }
        ; Medium press (300-1000ms) - Sarı göster
        else if (duration < 1000) {
            pressType := 1
            if (enableVisual && !visualShown.medium) {
                this._showVisual("d4ff00")  ; Sarı
                visualShown.medium := true
            }
        }
        ; Long press (1000ms+) - Turuncu göster
        else {
            pressType := 2
            if (enableVisual && !visualShown.long) {
                this._showVisual("00ff9d")  ; Turuncu
                visualShown.long := true
            }
        }

        return pressType
    }

    _showVisual(color) {
        static feedbackGui := ""

        ; Önceki GUI'yi temizle
        if (feedbackGui) {
            try feedbackGui.Destroy()
        }

        MouseGetPos(&x, &y)
        feedbackGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20")
        feedbackGui.BackColor := color
        feedbackGui.Add("Text", "x3 y0 w14 h14 Center BackgroundTrans", "●")
        feedbackGui.Show("x" (x + 22) " y" (y + 22) " w20 h20 NoActivate")

        ; 300ms sonra temizle (flicker'ı azalt)
        SetTimer(() => (feedbackGui.Destroy(), feedbackGui := ""), -300)
    }

    handleFKey(builder) {
        mainStart := builder._mainStart
        mainDefault := builder._mainDefault
        mainEnd := builder._mainEnd
        gestures := builder.gestures
        comboActions := builder.comboActions
        previewList := builder.tips
        enableVisual := builder._enableVisual
        onlyOnCombo := builder._mainEndOnlyCombo
        enabledDoubleClick := builder._enableDoubleClick

        _checkCombo(comboActions) {
            for c in comboActions {
                if (GetKeyState(c.key, "P")) {
                    gState.setBusy(2)
                    KeyWait c.key
                    gKeyCounts.inc(c.key)
                    c.action.Call()
                    ; return true ; basıldığı sürece tekrar çalışsın
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
                key := SubStr(key, 2)
            }

            gKeyCounts.inc(key)

            if (previewList.Length > 0) {
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
            visualShown := { medium: false, long: false }

            while GetKeyState(key, "P") {
                duration := A_TickCount - startTime

                ; Press type ve görsel feedback'i birlikte kontrol et
                this._detectPressWithVisual(duration, enableVisual, &visualShown)

                if (_checkCombo(comboActions)) {
                    if (gestures.Length > 0 && IsObject(this.hgsRight)) {
                        this.hgsRight.Stop()
                    }
                    break
                }
                Sleep 10
            }

            KeyWait key
            totalDuration := A_TickCount - startTime

            if (gestures.Length > 0) {
                this.hgsRight.Stop()
                if (this.hgsRight.Result.Valid) {
                    detectedGesture := this.hgsRight.Result.MatchedGesture
                    for g in gestures {
                        if (detectedGesture == g.gesture) {
                            g.action.Call()
                            return
                        }
                    }
                }
            }

            if (gState.getBusy() == 1 && mainDefault != "" && IsObject(mainDefault)) {
                ; Final press type belirleme
                pressType := (totalDuration < 300) ? 0 : (totalDuration < 1000) ? 1 : 2

                ; Double-click kontrolü (sadece short press için)
                if (pressType == 0 && enabledDoubleClick) {
                    result := KeyWait(key, "D T0.1")
                    if (result) {
                        KeyWait(key)
                        pressType := 4
                    }
                }

                mainDefault.Call(pressType)
            }

            if (mainEnd != "" && IsObject(mainEnd) && onlyOnCombo == 1 && gState.getBusy() == 2) {
                mainEnd.Call()
            }
        } catch Error as err {
            gErrHandler.handleError(err.Message " " key, err)
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
            .enableVisual(false)
            .combos("F14", "LB+F14() => Send('L F14')", () => Send("L F14"))
            .combos("F15", "LB+F15() => Send('L 15')", () => Send("L 15"))
            .combos("F16", "LB+F16() => Send('L 16')", () => Send("L 16"))
            .combos("F17", "LB+F17() => Send('L 17')", () => Send("L 17"))
            .combos("F18", "LB+F18() => Send('L 18')", () => Send("L 18"))
            .combos("F19", "All+Paste", () => Send("^a^v{Enter}"))
            .combos("F20", "Enter", () => Send("{Enter}"))
        builder.setPreview([])
        this.handleFKey(builder)
    }

    handleMButton() {
        static builder := FKeyBuilder()
            .mainDefault((pressType) {
                ; OutputDebug ("MButton: " pressType "`n")
                switch (pressType) {
                    case 4: SendInput("{LWin down}-{Sleep 500}-{Sleep 500}-{LWin up}")
                }
            })
            .combos("F15", "Delete Word", () => Send("{RControl down}{vkBF}{RControl up}"))
            .combos("F16", "Find & Paste", () => Send(["^f{Sleep 100}^a^v"]))
            .combos("F17", "Send F17", () => Send("F17"))
            .combos("F18", "Send F18", () => Send("F18"))
            .combos("F19", "Paste & Enter", () => Send("^v{Enter}"))
            .combos("F20", "Enter", () => Send("{Enter}"))
            .combos("F14", "Show History Search", () => gClipHist.showHistorySearch())
            .enableVisual(false)
        builder.setPreview([])
        this.handleFKey(builder)
    }

    handleRButton() {
        static builder := FKeyBuilder()
            .enableVisual(false)
            .combos("F13", "Zoom+", () => Send("#{NumpadAdd}"))
            .combos("F14", "Zoom-", () => Send("#{NumpadSub}"))
            ; .combos("WheelUp", "vol", () => Send("#{NumpadAdd}"))
            ; .combos("WheelDown", "vol", () => Send("#{NumpadSub}"))
            .mainEndOnlyCombo(true)
            .mainEnd(() => Send("{Sleep 100}{Escape}"))
        builder.setPreview([])
        this.handleFKey(builder)
    }

    handleF13() {
        static builder := FKeyBuilder()
            ; .mainStart(() => (ToolTip("F13 Paste Mode"), SetTimer(() => ToolTip(), -800)))
            .mainDefault((pressType) {
                switch (pressType) {
                    case 0: showF13menu()
                    case 1: Send("abc")
                }
            })
            .mainGesture(HotGestures.Gesture("Right-right:1,0"), () => Send("{Enter}"))
            .mainGesture(HotGestures.Gesture("Right-left:-1,0"), () => Send("{Escape}"))
            .mainGesture(HotGestures.Gesture("Right-up:0,-1"), () => Send("{Home}"))
            .mainGesture(HotGestures.Gesture("Right-down:0,1"), () => Send("{End}"))
            .mainGesture(HotGestures.Gesture("Right-diagonal-down-left:-1,1"), () => WinMinimize("A"))
            .combos("F14", "Click & Paste", () => (Click("Left", 1), Send("^v")))
            .combos("F18", "Delete", () => Send("{Delete}"))
        builder.setPreview([])
        this.handleFKey(builder)
    }

    handleF14() {
        static builder := FKeyBuilder()
            .mainDefault((pressType) {
                switch (pressType) {
                    case 0: showF14menu()
                    case 1: showF14menu()
                }
            })
            .mainGesture(HotGestures.Gesture("Right-up:0,-1"), () => Send("{Delete}"))
            .mainGesture(HotGestures.Gesture("Right-down:0,1"), () => Send("{Backspace}"))
            .combos("F15", "Select All", () => Send("^a"))
            .combos("F16", "Select All", () => Send("^a"))
            .combos("F17", "Home", () => Send("{Home}"))
            .combos("F18", "End", () => Send("{End}"))
            .combos("F19", "Select All", () => Send("^a"))
            .combos("F20", "Select All", () => Send("^a"))
            .combos("RButton", "Show Slots Search", () => gClipSlot.showSlotsSearch())
        builder.setPreview([])
        this.handleFKey(builder)
    }

    handleF15() {
        static builder := FKeyBuilder()
            .mainDefault((pressType) {
                switch (pressType) {
                    case 0: Send("^y")
                    case 1: Send("{Escape}")
                }
            })
            .combos("F13", "Send F13", () => Send("F13 bos"))
            .combos("LButton", "Send F15 L", () => Send("F15 L bos"))
        this.handleFKey(builder)
    }

    handleF16() {
        static builder := FKeyBuilder()
            .enableDoubleClick(false)
            .mainDefault((pressType) {
                switch (pressType) {
                    case 0: Send("^z")
                    case 1: Send("{Enter}")
                }
            })
            .combos("F13", "Send F13", () => Send("F13 bos"))
            .combos("LButton", "Send F16 L", () => Send("F16 L bos"))
        this.handleFKey(builder)
    }

    handleF17() {
        static builder := FKeyBuilder()
            .mainDefault((pressType) {
                switch (pressType) {
                    case 0: Send("!{Right}")
                    case 1: Send("{Home}")
                }
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
                switch (pressType) {
                    case 0: Send("!{Left}")
                    case 1: Send("{End}")
                }
            })
            .combos("F17", "Cut", () => Send("^x"))
            .combos("F20", "3x Click + Copy", () => (Click("Left", 3), gClipSlot.press("^c")))
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
            .mainEnd(() => gClipSlot.showClipboardPreview())
            .combos("F13", "Select All & Paste", () => gClipSlot.press("^a^v"))
            .combos("F14", "3x Click + Paste", () => (Click("Left", 3), gClipSlot.press("^v"), ToolTip("3x Click + Paste"), SetTimer(() => ToolTip(), -800)))
            .combos("F20", "Select All & Paste", () => gClipSlot.press("^a^v"))
            .combos("LButton", "Click & Paste", () => (Click("Left", 1), gClipSlot.press("^v")))
            .combos("MButton", "3x Click + Paste", () => (Click("Left", 3), gClipSlot.press("^v")))
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
            .mainEnd(() => (ClipWait(1), Sleep(50), gClipSlot.showClipboardPreview()))
            .combos("F13", "Select All & Copy", () => gClipSlot.press("^a^c"))
            .combos("F14", "3x Click + Copy", () => (Click("Left", 3), gClipSlot.press("^c"), ToolTip("3x Click + Copy"), SetTimer(() => ToolTip(), -800)))
            .combos("F19", "Select All & Copy", () => gClipSlot.press("^a^c"))
            .combos("F18", "3x Click + Copy", () => (Click("Left", 3), gClipSlot.press("^c")))
            .combos("LButton", "Click & Copy", () => (Click("Left", 1), gMemSlots.smartCopy()))
            .combos("MButton", "3x Click + Copy", () => (Click("Left", 3), gClipSlot.press("^c")))
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