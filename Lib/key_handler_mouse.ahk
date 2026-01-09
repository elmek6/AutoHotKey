#Include <HotGestures>

class EM {    ;Enhancements for KeyBuilder
    static tVisual := 1, tGesture := 2, tOnCombo := 3, tDBClick := 4, tTriggerPressType := 5, tRepeatKey := 6

    ; Factory: Tek satırda objeyi damgalayıp döner
    static Create(type, data) => { base: EM.Prototype, type: type, data: data }

    ; kısa yazmak için yardımcı metodlar
    static visual(v) => EM.Create(EM.tVisual, v)
    static gesture(p, a) => EM.Create(EM.tGesture, { pattern: p, action: a })
    static enableDoubleClick(v := true) => EM.Create(EM.tDBClick, v)
    static workOnlyOnCombo(v) => EM.Create(EM.tOnCombo, v)
    static triggerByPressType(v := 0) => EM.Create(EM.tTriggerPressType, v)
    static repeatKey(interval := 500) => EM.Create(EM.tRepeatKey, interval)
}

class singleKeyHandlerMouse {
    static instance := ""

    static getInstance() {
        if (!singleKeyHandlerMouse.instance) {
            singleKeyHandlerMouse.instance := singleKeyHandlerMouse()
        }
        return singleKeyHandlerMouse.instance
    }

    __New() {
        if (singleKeyHandlerMouse.instance) {
            throw Error("singleKeyHandlerMouse zaten oluşturulmuş! getInstance kullan.")
        }
        this.hgsRight := ""
    }

    handle(b) { ; builderlerin hepsi b. ile baslıyor
        /*
            builder yapisini kullanmak daha mantikli
            mainStart := builder.main_start
            main_key := builder.main_key
            mainEnd := builder.main_end
            shortTime := builder.shortTime
            longTime := builder.longTime
            gapTime := builder.gapTime
            combos := builder.combos
            previewList := builder.tips
        */

        enableVisual := false
        onlyOnCombo := false
        gestures := []
        enabledDoubleClick := false
        triggerPressType := 0
        repeatInterval := 0

        for item in b.extensions {
            if (item is EM) {
                switch item.type {
                    case EM.tVisual: enableVisual := item.data
                    case EM.tOnCombo: onlyOnCombo := item.data
                    case EM.tDBClick: enabledDoubleClick := item.data
                    case EM.tGesture: gestures.Push(item.data)
                    case EM.tTriggerPressType: triggerPressType := item.data
                    case EM.tRepeatKey: repeatInterval := item.data
                }
            }
        }


        _checkCombo(comboActions) {
            for p in comboActions {
                if (GetKeyState(p.key, "P")) {
                    gState.setBusy(2)
                    KeyWait p.key
                    gKeyCounts.inc(p.key)
                    p.action.Call()
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


            ; simdilik kapattim calisiyor mouse icin basilan tuslarin
            ; combolarini liste olarak veriyor
            ; if (builder.tips.Length > 0) {
            ;     text := ""
            ;     for i, item in builder.tips
            ;         text .= item "`n"
            ;     ToolTip(text)
            ; }

            if (b.main_start != "" && IsObject(b.main_start)) {
                b.main_start.Call()
            }

            if (gestures.Length > 0) {
                this.hgsRight := HotGestures()
                for g in gestures {
                    this.hgsRight.Register(g.pattern, g.pattern.Name, g.action)
                }
                this.hgsRight.Start()
            }

            startTime := A_TickCount
            lastRepeatTime := 0
            visualShown := { medium: false, long: false }

            while GetKeyState(key, "P") {
                duration := A_TickCount - startTime
                pressType := KeyBuilder.getPressType(duration, b.shortTime, b.longTime)

                ; Repeat kontrolü
                if (repeatInterval > 0 && duration > repeatInterval) {
                    timeSinceLastRepeat := A_TickCount - lastRepeatTime
                    ; İlk repeat veya interval geçtiyse
                    if (lastRepeatTime == 0 || timeSinceLastRepeat >= repeatInterval) {
                        if (b.main_key != "" && IsObject(b.main_key)) {
                            b.main_key.Call(pressType)
                        }
                        lastRepeatTime := A_TickCount
                    }
                }

                ; Trigger kontrolü
                if (pressType == triggerPressType) {
                    if (b.main_key != "" && IsObject(b.main_key)) {
                        b.main_key.Call(pressType) ; Tuşu bırakmadan çalıştır
                    }
                    break
                }

                if (_checkCombo(b.combos)) {
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
                        if (detectedGesture == g.pattern) {
                            g.action.Call()
                            return
                        }
                    }
                }
            }

            ; Repeat yoksa veya ilk basımsa normal çalışsın
            if (gState.getBusy() == 1 && b.main_key != "" && IsObject(b.main_key) && lastRepeatTime == 0) {
                pressType := KeyBuilder.getPressType(totalDuration, b.shortTime, b.longTime)

                ;Double-click kontrolü (sadece short press için)
                if (pressType == 1 && enabledDoubleClick) {
                    result := KeyWait(key, "D T0.1")
                    if (result) {
                        KeyWait(key)
                        pressType := 4
                    }
                }

                b.main_key.Call(pressType)
            }

            ; only on combo -> handleRButton icin sag tusu iptal etmeye yariyor
            if (onlyOnCombo == 1 && b.main_end != "" && IsObject(b.main_end) && gState.getBusy() == 2) {
                b.main_end.Call()
            }

        } catch Error as err {
            gErrHandler.handleError(err.Message " " key, err)
        } finally {
            if (b.tips.Length > 0) {
                ToolTip()
            }
            if (gestures.Length > 0 && IsObject(this.hgsRight)) {
                this.hgsRight.Stop()
            }
            gState.setBusy(0)
        }
    }

    handleLButton() {
        builder := KeyBuilder()
            .combo("F14", "LB + F14", () => Send("L F14"))
            .combo("F19", "All + Paste + Enter", () => Send("^a^v{Enter}"))
            .combo("F20", "Enter", () => Send("{Enter}"))
            .combo("F15", "###", () => (gClipSlot.loadFromSlot("", 10)) Send("{Sleep 200}^v{Enter}"))
            .build()
        this.handle(builder)
    }

    handleMButton() {
        builder := KeyBuilder()
            .mainKey((pt) {
                switch (pt) {
                    case 1:
                        if (gState.getClipHandler() == gState.clipStatusEnum.memSlot)
                            gMemSlots.smartPaste(true)
                        ; case 3: SendInput("{LWin down}-{Sleep 500}-{Sleep 500}-{LWin up}")
                    default: ShowTip("Middle Button pressed. Press type: " . pt, TipType.Info)
                }
            })
            .extend(EM.enableDoubleClick())
            .combo("F14", "Show History Search", () => gClipHist.showHistorySearch())
            .combo("F15", "Delete Word", () => Send("{RControl down}{vkBF}{RControl up}"))
            .combo("F16", "Find & Paste", () => Send("^f{Sleep 100}^a^v"))
            .combo("F17", "Send F17", () => Send("F17"))
            .combo("F18", "Send F18", () => Send("F18"))
            .combo("F19", "Paste & Enter", () => Send("^v{Enter}"))
            .combo("F20", "Enter", () => Send("{Enter}"))
            .build()

        this.handle(builder)
    }

    handleRButton() {
        builder := KeyBuilder()
            .combo("F13", "Zoom+", () => Send("#{NumpadAdd}"))
            .combo("F14", "Zoom-", () => Send("#{NumpadSub}"))
            ; .combo("WheelUp", "Volume Up", () => Send("#{NumpadAdd}"))
            ; .combo("WheelDown", "Volume Down", () => Send("#{NumpadSub}"))
            .mainEnd(() => (Sleep(100), Send("{Escape}")))
            .extend(EM.workOnlyOnCombo(true))
            .build()

        this.handle(builder)
    }

    handleF13() {
        builder := KeyBuilder(350)
            .mainKey((pt) {
                switch (pt) {
                    case 1: showF13menu()
                    case 2: Send("#{NumpadAdd}")  ; Repeat ile çalışacak
                    case 4: Send("#{NumpadAdd}")
                }
            })
            .combo("F19", "Paste", () => Send("^v"))
            .combo("F20", "Copy", () => Send("^c"))
            .extend(EM.visual(true))
            .extend(EM.enableDoubleClick())
            .extend(EM.repeatKey(500))
            .extend(EM.gesture(HotGestures.Gesture("Right-right:1,0"), () => Send("{Enter}")))
            .extend(EM.gesture(HotGestures.Gesture("Right-left:-1,0"), () => Send("{Escape}")))
            .extend(EM.gesture(HotGestures.Gesture("Right-up:0,-1"), () => Send("{Home}")))
            .extend(EM.gesture(HotGestures.Gesture("Right-down:0,1"), () => Send("{End}")))
            .extend(EM.gesture(HotGestures.Gesture("Right-diagonal-down-left:-1,1"), () => WinMinimize("A")))
            .build()
        this.handle(builder)
    }


    handleF14() {
        builder := KeyBuilder(350)
            .mainKey((pt) {
                switch (pt) {
                    case 1: showF14menu()
                    case 2: Send("#{NumpadSub}")  ; Repeat ile çalışacak
                    case 4: Send("#{NumpadSub}")
                }
            })
            .combo("F19", "Paste", () => Send("^v"))
            .combo("F20", "Copy", () => Send("^c"))
            .extend(EM.enableDoubleClick())
            .extend(EM.repeatKey(500))
            .extend(EM.gesture(HotGestures.Gesture("Right-up:0,-1"), () => Send("{Delete}")))
            .extend(EM.gesture(HotGestures.Gesture("Right-down:0,1"), () => Send("{Backspace}")))
            .build()
        this.handle(builder)
    }

    handleF15() {
        builder := KeyBuilder()
            .mainKey((pt) {
                switch (pt) {
                    case 1: Send("^y")
                    case 2: Send("{Escape}")
                }
            })
            .combo("F13", "Delete", () => Send("{Delete}"))
            .combo("LButton", "Send F15 L", () => Send("F15 L bos"))
            .extend((b) => b.enableVisual := true)
            .build()

        this.handle(builder)
    }

    handleF16() {
        builder := KeyBuilder()
            .mainKey((pt) {
                switch (pt) {
                    case 1: Send("^z")
                    case 2: Send("{Enter}")
                }
            })
            .combo("F13", "Send F13", () => Send("F13 bos"))
            .extend((b) => b.enableVisual := true)
            .build()
        this.handle(builder)
    }

    handleF17() {
        builder := KeyBuilder()
            .mainKey((pt) {
                switch (pt) {
                    case 1: Send("!{Right}")
                    case 2: Send("{Home}")
                }
            })
            .combo("F14", "3x Click + Delete", () => (Click("Left", 3), Send("{Delete}")))
            .combo("F18", "Delete", () => Send("{Delete}"))
            .combo("LButton", "2x Click + Delete", () => (Click("Left", 2), Send("{Delete}")))
            .combo("MButton", "3x Click + Delete", () => (Click("Left", 3), Send("{Delete}")))
            .build()

        this.handle(builder)
    }


    handleF18() {
        builder := KeyBuilder()
            .mainKey((pt) {
                switch (pt) {
                    case 1: Send("!{Left}")
                    case 2: Send("{End}")
                }
            })
            ; .combo("WheelUp", "Volume Up", () => Send("{Volume_Up}"))
            ; .combo("WheelDown", "Volume Down", () => Send("{Volume_Down}"))
            .combo("F17", "Cut", () => Send("^x"))
            .combo("F20", "3x Click + Copy", () => (Click("Left", 3), Send("^c")))
            .combo("LButton", "Del line VSCode", () => SendInput("^+k"))
            .combo("MButton", "tooltip", () => ShowTip("RButton + MButton: Zoom in/out"))
            .build()
        this.handle(builder)
    }

    handleF19() {
        builder := KeyBuilder()
            .mainKey((pt) {
                switch (pt) {
                    case 1: gState.getClipHandler() == gState.clipStatusEnum.memSlot
                        ? gMemSlots.smartPaste() : Send("^v")
                    case 2: Send("^a^v")
                }
            })
            .mainEnd(() => ShowTip(A_Clipboard, TipType.Paste))
            .combo("F13", "Select All & Paste", () => Send("^a^v"))
            .combo("F14", "3x Click + Paste", () => (Click("Left", 3), Send("^v")))
            .combo("F20", "Select All & Paste", () => Send("^a^v"))
            .combo("LButton", "Click & Paste", () => (Click("Left", 1), Send("^v")))
            .combo("MButton", "3x Click + Paste", () => (Click("Left", 3), Send("^v")))
            .build()

        this.handle(builder)
    }

    handleF20() {
        builder := KeyBuilder()
            .setPressType(300, 800)
            .mainKey((pt) {
                switch (pt) {
                    case 1: Send("^c")
                    case 2: Send("^x")
                    case 3: gMemSlots.start()
                }
            })
            .mainEnd(() => (ShowTip(A_Clipboard, TipType.Copy)))
            .combo("F13", "Select All & Copy", () => Send("^a^c"))
            .combo("F14", "3x Click + Copy", () => (Click("Left", 3), Send("^c")))
            .combo("F19", "Select All & Copy", () => Send("^a^c"))
            .combo("F18", "3x Click + Copy", () => (Click("Left", 3), Send("^c")))
            .combo("LButton", "Click & Copy", () => (Click("Left", 1), Send("^c")))
            .combo("MButton", "3x Click + Copy", () => (Click("Left", 3), Send("^c")))
            .build()

        this.handle(builder)
    }
}
/*

class FKeyBuilder {
    __New(short := 350, long := "", gap := "") {
        this.shortTime := short
        this.longTime := long
        this.gapTime := gap
        this.main_start := ""
        this.main_key := ""
        this.main_end := ""
        this.gestures := []
        this.combos := []
        this.tips := [A_ThisHotkey]
        this._enableVisual := true
        this._enableDoubleClick := false
        ; this._mainEndOnlyCombo := false handleRButton
    }

    mainStart(fn) {
        this.main_start := fn
        return this
    }

    mainKey(fn) {
        this.main_key := fn
        return this
    }

    mainEnd(fn) {
        this.main_end := fn
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

    combo(key, desc, fn) {
        this.combos.Push({ key: key, desc: desc, action: fn })
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
*/

/*
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

*/

/*
    handleLButton() {
        static builder := FKeyBuilder()
            .enableVisual(false)
            .combo("F14", "LB+F14() => Send('L F14')", () => Send("L F14"))
            .combo("F15", "LB+F15() => Send('L 15')", () => Send("L 15"))
            .combo("F16", "LB+F16() => Send('L 16')", () => Send("L 16"))
            .combo("F17", "LB+F17() => Send('L 17')", () => Send("L 17"))
            .combo("F18", "LB+F18() => Send('L 18')", () => Send("L 18"))
            .combo("F19", "All+Paste", () => Send("^a^v{Enter}"))
            .combo("F20", "Enter", () => Send("{Enter}"))
        builder.setPreview([])
        this.handle(builder)
    }
*/

/*
    handleMButton() {
        static builder := FKeyBuilder()
            .mainKey((pressType) {
                ; OutputDebug ("MButton: " pressType "`n")
                switch (pressType) {
                    case 0: ;test
                        if (gState.getClipHandler() == gState.clipStatusEnum.memSlot) {
                            gMemSlots.smartPaste(true)
                        }
                    case 4: SendInput("{LWin down}-{Sleep 500}-{Sleep 500}-{LWin up}")
                }
            })
            .combo("F15", "Delete Word", () => Send("{RControl down}{vkBF}{RControl up}"))
            .combo("F16", "Find & Paste", () => Send(["^f{Sleep 100}^a^v"]))
            .combo("F17", "Send F17", () => Send("F17"))
            .combo("F18", "Send F18", () => Send("F18"))
            .combo("F19", "Paste & Enter", () => Send("^v{Enter}"))
            .combo("F20", "Enter", () => Send("{Enter}"))
            .combo("F14", "Show History Search", () => gClipHist.showHistorySearch())
            .enableVisual(false)
        builder.setPreview([])
        this.handle(builder)
    }
*/

/*
    handleRButton() {
        static builder := FKeyBuilder()
            .enableVisual(false)
            .combo("F13", "Zoom+", () => Send("#{NumpadAdd}"))
            .combo("F14", "Zoom-", () => Send("#{NumpadSub}"))
            ; .combos("WheelUp", "vol", () => Send("#{NumpadAdd}"))
            ; .combos("WheelDown", "vol", () => Send("#{NumpadSub}"))
            ;² .mainEndOnlyCombo(true)
            .mainEnd(() => Send("{Sleep 100}{Escape}"))
        builder.setPreview([])
        this.handle(builder)
    }
*/

/*
    handleF13() {
        static builder := FKeyBuilder()
            ; .mainStart(() => (ToolTip("F13 Paste Mode"), SetTimer(() => ToolTip(), -800)))
            .mainKey((pressType) {
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
            .combo("F14", "Click & Paste", () => (Click("Left", 1), Send("^v")))
            .combo("F18", "Delete", () => Send("{Delete}"))
        builder.setPreview([])
        this.handle(builder)
    }

    handleF14() {
        static builder := FKeyBuilder()
            .mainKey((pressType) {
                switch (pressType) {
                    case 0: showF14menu()
                    case 1: showF14menu()
                }
            })
            .mainGesture(HotGestures.Gesture("Right-up:0,-1"), () => Send("{Delete}"))
            .mainGesture(HotGestures.Gesture("Right-down:0,1"), () => Send("{Backspace}"))
            .combo("F15", "Select All", () => Send("^a"))
            .combo("F16", "Select All", () => Send("^a"))
            .combo("F17", "Home", () => Send("{Home}"))
            .combo("F18", "End", () => Send("{End}"))
            .combo("F19", "Select All", () => Send("^a"))
            .combo("F20", "Select All", () => Send("^a"))
            .combo("RButton", "Show Slots Search", () => gClipSlot.showSlotsSearch())
        builder.setPreview([])
        this.handle(builder)
    }
*/

/*
    handleF15() {
        static builder := FKeyBuilder()
            .mainDefault((pressType) {
                switch (pressType) {
                    case 0: Send("^y")
                    case 1: Send("{Escape}")
                }
            })
            .combo("F13", "Send F13", () => Send("F13 bos"))
            .combo("LButton", "Send F15 L", () => Send("F15 L bos"))
        this.handle(builder)
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
        .combo("F13", "Send F13", () => Send("F13 bos"))
        .combo("LButton", "Send F16 L", () => Send("F16 L bos"))
    this.handle(builder)
}
*/

/*
    handleF17() {
        static builder := FKeyBuilder()
            .mainKey((pressType) {
                switch (pressType) {
                    case 0: Send("!{Right}")
                    case 1: Send("{Home}")
                }
            })
            .combo("F14", "3x Click + Delete", () => (Click("Left", 3), Send("{Delete}"), ToolTip("3x Click + Delete"), SetTimer(() => ToolTip(), -800), SoundBeep(600)))
            .combo("F18", "Delete", () => Send("{Delete}"))
            .combo("LButton", "2x Click + Delete", () => (Click("Left", 2), Send("{Delete}")))
            .combo("MButton", "3x Click + Delete", () => (Click("Left", 3), Send("{Delete}")))
        this.handle(builder)
    }

    handleF18() {
        static builder := FKeyBuilder()
            .mainKey((pressType) {
                switch (pressType) {
                    case 0: Send("!{Left}")
                    case 1: Send("{End}")
                }
            })
            .combo("F17", "Cut", () => Send("^x"))
            .combo("F20", "3x Click + Copy", () => (Click("Left", 3), Send("^c")))
            .combo("LButton", "Del line VSCode", () => SendInput("^+k"))
        this.handle(builder)
    }
*/

/*
    handleF19() {
        static builder := FKeyBuilder()
            .mainKey((pressType) {
                switch pressType {
                    case 0:
                        if (gState.getClipHandler() == gState.clipStatusEnum.memSlot) {
                            gMemSlots.smartPaste()
                        } else {
                            Send("^v")
                        }
                    case 1: Send("^a^v")
                }
            })
            .mainEnd(() => gClipSlot.showClipboardPreview())
            .combo("F13", "Select All & Paste", () => Send("^a^v"))
            .combo("F14", "3x Click + Paste", () => (Click("Left", 3), Send("^v"), ToolTip("3x Click + Paste"), SetTimer(() => ToolTip(), -800)))
            .combo("F20", "Select All & Paste", () => Send("^a^v"))
            .combo("LButton", "Click & Paste", () => (Click("Left", 1), Send("^v")))
            .combo("MButton", "3x Click + Paste", () => (Click("Left", 3), Send("^v")))
        builder.setPreview([])
        this.handle(builder)
    }

    handleF20() {
        static builder := FKeyBuilder()
            .mainKey((pressType) {
                switch pressType {
                    case 0: Send("^c")
                    case 1: Send("^x")
                    case 2: gMemSlots.start() ; gState.setAutoClip(1)
                }
            })
            .mainEnd(() => (ClipWait(1), Sleep(50), gClipSlot.showClipboardPreview()))
            .combo("F13", "Select All & Copy", () => Send("^a^c"))
            .combo("F14", "3x Click + Copy", () => (Click("Left", 3), Send("^c"), ToolTip("3x Click + Copy"), SetTimer(() => ToolTip(), -800)))
            .combo("F19", "Select All & Copy", () => Send("^a^c"))
            .combo("F18", "3x Click + Copy", () => (Click("Left", 3), Send("^c")))
            .combo("LButton", "Click & Copy", () => (Click("Left", 1), Send("^c")))
            .combo("MButton", "3x Click + Copy", () => (Click("Left", 3), Send("^c")))
        builder.setPreview([])
        this.handle(builder)
    }
*/
