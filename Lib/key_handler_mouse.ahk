#Include <hot_vectors> ; #Include <hot_gestures>

; Yeni fikir tusu basili tutarken gesture
; F18 basili tutarken sag sol yaparsan back ve del

class EM {    ; Enhancements for KeyBuilder
    static tVisual := 1, tGesture := 2, tOnCombo := 3, tDBClick := 4, tTriggerPressType := 5, tRepeatKey := 6, tStationaryPress := 7

    ; Factory: Tek satırda objeyi damgalayıp döner
    static Create(type, data) => { base: EM.Prototype, type: type, data: data }

    ; kısa yazmak için yardımcı metodlar
    static visual(v) => EM.Create(EM.tVisual, v)
    static gesture(gestureObj) => EM.Create(EM.tGesture, gestureObj)
    static enableDoubleClick(v := true) => EM.Create(EM.tDBClick, v)
    static workOnlyOnCombo(v) => EM.Create(EM.tOnCombo, v)
    static triggerByPressType(v := 0) => EM.Create(EM.tTriggerPressType, v)
    static repeatKey(interval := 500) => EM.Create(EM.tRepeatKey, interval)
    static detectStaticHold(v := 3) => EM.Create(EM.tStationaryPress, v) ;tolerance olabilir simdilik kullanmiyorum
}

class singleHotMouse {
    static instance := ""

    static getInstance() {
        if (!singleHotMouse.instance) {
            singleHotMouse.instance := singleHotMouse()
        }
        return singleHotMouse.instance
    }

    __New() {
        if (singleHotMouse.instance) {
            throw Error("singleKeyHandlerMouse zaten oluşturulmuş! getInstance kullan.")
        }
        this.hgs := HotVectors() ; this.hgs := HotGestures()
    }

    handle(b) { ; builderlerin hepsi b. ile baslıyor
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
                    State.Busy.setCombo("mc")
                    KeyWait p.key
                    App.KeyCounts.inc(p.key)
                    p.action.Call()
                    ; return true ; basıldığı sürece tekrar çalışsın
                }
            }
            return false
        }

        if (!State.Busy.isFree()) {
            return
        }

        try {
            State.Busy.setActive()
            startTime := A_TickCount

            key := A_ThisHotkey
            if (SubStr(key, 1, 1) == "~") {
                key := SubStr(key, 2)
            }

            App.KeyCounts.inc(key)


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

            ; === HotGestures başlat ===
            if (gestures.Length > 0) {
                this.hgs.ClearRegistrations()  ; Önceki gesture'ları temizle

                for g in gestures {
                    this.hgs.Register(g.Direction, g.Callback)
                }
                this.hgs.Start(key)
                if (this.hgs.WasGestureFired()) {
                    return
                }
            }

            lastRepeatTime := 0
            ; visualShown := { medium: false, long: false }

            while GetKeyState(key, "P") {
                duration := A_TickCount - startTime
                pressType := KeyBuilder.getPressType(duration, b.shortTime, b.longTime)

                ; Repeat kontrolü
                if (repeatInterval > 0 && b.main_key != "" && IsObject(b.main_key)) {
                    if (lastRepeatTime == 0 && duration >= b.shortTime) { ; İlk repeat: shortTime 'dan hemen sonra başlasın
                        b.main_key.Call(pressType)
                        lastRepeatTime := A_TickCount
                    }
                    else if (lastRepeatTime > 0) { ; Sonraki repeat 'ler: interval kadar bekle
                        timeSinceLastRepeat := A_TickCount - lastRepeatTime
                        if (timeSinceLastRepeat >= repeatInterval) {
                            b.main_key.Call(pressType)
                            lastRepeatTime := A_TickCount
                        }
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
                    if (gestures.Length > 0 && IsObject(this.hgs)) {
                        this.hgs.Stop()
                    }
                    break
                }
                Sleep 10
            }

            KeyWait key
            totalDuration := A_TickCount - startTime

            ; HotGestures sonuç kontrolü
            if (gestures.Length > 0) {
                this.hgs.Stop() ; HotGestures zaten callback'leri çağırdı
            }

            ; Repeat yoksa veya ilk basımsa normal çalışsın
            if (State.Busy.isActive() && b.main_key != "" && IsObject(b.main_key) && lastRepeatTime == 0) {
                pressType := KeyBuilder.getPressType(totalDuration, b.shortTime, b.longTime)
                ; Double-click kontrolü (sadece short press için)
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
            if (onlyOnCombo == 1 && b.main_end != "" && IsObject(b.main_end) && State.Busy.isCombo()) {
                b.main_end.Call()
            }

        } catch Error as err {
            App.ErrHandler.handleError(err.Message " " key, err)
        } finally {
            if (b.tips.Length > 0) {
                ToolTip()
            }
            if (gestures.Length > 0) {
                this.hgs.Stop()
            }
            State.Busy.setFree()
        }
    }

    handleLButton() {
        builder := KeyBuilder()
            .combo("F14", "LB + F14", () => Send("L F14"))
            .combo("F19", "All + Paste + Enter", () => Send("^a^v{Enter}"))
            .combo("F20", "Copy all", () => Send("^a^c"))
            .combo("F15", "###", () => (App.ClipSlot.loadFromSlot("", 10)) Send("{Sleep 200}{Enter}"))
            .build()
        this.handle(builder)
    }

    handleMButton() {
        smartPaste(no) {
            ; eger memSlot aciksa F20 1 numarali gözü paste yapacak F19 2 ...
            ; normalde F19 paste bu sorunua cözüm lazim
            if (State.Clipboard.isMemSlots()) {
                ; Memory Slots modundaysa direkt slot numarasından paste yap
                App.MemSlots.pasteFromSlot(no)
            } else {
                ; Normal modda ClipSlot'tan yükle
                App.ClipSlot.loadFromSlot(App.ClipSlot.defaultGroupName, no)
            }
        }
        local initialPos := { x: 0, y: 0 }
        builder := KeyBuilder(350, 1000)
            .mainStart((*) {
                MouseGetPos &x, &y
                initialPos.x := x
                initialPos.y := y
            })
            .mainKey((pt) {
                MouseGetPos &endX, &endY
                mouseMoved := (Abs(endX - initialPos.x) > 4) || (Abs(endY - initialPos.y) > 4)
                switch (pt) {
                    case 1:
                        if (State.Clipboard.isMemSlots())
                            App.MemSlots.smartPaste(true)
                    case 2: if (!mouseMoved)
                        App.MemSlots.start()
                    case 3: if (!mouseMoved)
                        App.ClipHist.showHistorySearch()
                }
            })
            .extend(EM.detectStaticHold())
            .combo("F14", "Show History Search", () => App.ClipHist.showHistorySearch())
            .combo("F15", "Smart Paste 6", () => smartPaste(6))
            .combo("F16", "Smart Paste 5", () => smartPaste(5))
            .combo("F17", "Smart Paste 4", () => smartPaste(4))
            .combo("F18", "Smart Paste 3", () => smartPaste(3))
            .combo("F19", "Smart Paste 2", () => smartPaste(2))
            .combo("F20", "Smart Paste 1", () => smartPaste(1))
            .build()

        this.handle(builder)
    }

    handleRButton() {
        builder := KeyBuilder()
            .combo("F13", "Zoom+", () => Send("#{NumpadAdd}"))
            .combo("F14", "Zoom-", () => Send("#{NumpadSub}"))
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
                    case 2: App.ClipHist.showQuickHistoryMenu(40)
                    case 4: App.ClipHist.showHistorySearch() ; App.ClipSlot.showSlotsSearch(App.ClipSlot.defaultGroupName)
                }
            })
            .combo("F15", "Slot 1", () => App.ClipSlot.loadFromSlot(App.ClipSlot.defaultGroupName, 6))
            .combo("F16", "Slot 1", () => App.ClipSlot.loadFromSlot(App.ClipSlot.defaultGroupName, 5))
            .combo("F17", "Slot 1", () => App.ClipSlot.loadFromSlot(App.ClipSlot.defaultGroupName, 4))
            .combo("F18", "Slot 1", () => App.ClipSlot.loadFromSlot(App.ClipSlot.defaultGroupName, 3))
            .combo("F19", "Slot 1", () => App.ClipSlot.loadFromSlot(App.ClipSlot.defaultGroupName, 2))
            .combo("F20", "Slot 1", () => App.ClipSlot.loadFromSlot(App.ClipSlot.defaultGroupName, 1))
            .extend(EM.enableDoubleClick())
            .extend(EM.repeatKey(350))
            .extend(EM.gesture(HotVectors.Gesture(HotVectors.bDir.upDown, (pos) => Send(pos > 0 ? "#{NumpadAdd}" : "#{NumpadSub}"))))
            .extend(EM.gesture(HotVectors.Gesture(HotVectors.bDir.leftRight, (pos) => Send(pos > 0 ? "{Volume_Up}" : "{Volume_Down}"))))
            .extend(EM.gesture(HotVectors.Gesture(HotVectors.bDir.once | HotVectors.bDir.downLeft, (pos) => WinMinimize("A"))))
            .build()
        this.handle(builder)
    }


    handleF14() {
        builder := KeyBuilder(350)
            .mainKey((pt) {
                switch (pt) {
                    case 1: showF14menu()
                    case 2: App.ClipSlot.showQuickSlotsMenu()
                    case 4: App.ClipSlot.showSlotsSearch(App.ClipSlot.defaultGroupName) ; default group varsa onu göster
                }
            })
            .combo("LButton", "test", () => OutputDebug("test"))
            .combo("F15", "Slot 1", () => App.ClipSlot.loadFromSlot("", 6))
            .combo("F16", "Slot 1", () => App.ClipSlot.loadFromSlot("", 5))
            .combo("F17", "Slot 1", () => App.ClipSlot.loadFromSlot("", 4))
            .combo("F18", "Slot 1", () => App.ClipSlot.loadFromSlot("", 3))
            .combo("F19", "Slot 1", () => App.ClipSlot.loadFromSlot("", 2))
            .combo("F20", "Slot 1", () => App.ClipSlot.loadFromSlot("", 1))
            .extend(EM.gesture(HotVectors.Gesture(HotVectors.bDir.leftRight, (pos) => Send(pos < 0 ? "{Left}" : "{Right}"))))
            .extend(EM.gesture(HotVectors.Gesture(HotVectors.bDir.upDown, (pos) => Send(pos > 0 ? "{Up}" : "{Down}"))))
            .extend(EM.gesture(HotVectors.Gesture(HotVectors.bDir.once | HotVectors.bDir.upLeft, (pos) => Send("{Home}"))))
            .extend(EM.gesture(HotVectors.Gesture(HotVectors.bDir.once | HotVectors.bDir.downRight, (pos) => Send("{End}"))))
            .extend(EM.gesture(HotVectors.Gesture(HotVectors.bDir.once | HotVectors.bDir.downLeft, (pos) => Send("{Enter}"))))
            .extend(EM.gesture(HotVectors.Gesture(HotVectors.bDir.once | HotVectors.bDir.upRight, (pos) => Send("{End}"))))
            ; .extend(EM.gesture(HotVectors.Gesture(HotVectors.bDir.leftRight, (diff) => Click( diff > 0 ? "WheelRight" : "WheelLeft")))) mouse click oldugu icin sanirim bozuyor
            ; .extend(EM.gesture(HotVectors.Gesture(HotVectors.bDir.left, (pos) => Mod(pos, 5) == 0 ? Send("{BackSpace}") : Sleep(5))))
            ; .extend(EM.gesture(HotVectors.Gesture(HotVectors.bDir.right, (pos) => Mod(pos, 5) == 0 ? Send("{Delete}") : Sleep(5))))            
            .extend(EM.enableDoubleClick())
            .extend(EM.repeatKey(250))
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
            ; .combo("F13", "Delete", () => Send("{Delete}"))
            ; .combo("LButton", "Send F15 L", () => Send("F15 L bos"))
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
            ; .combo("F13", "Send F13", () => Send("F13 bos"))
            .build()
        this.handle(builder)
    }

    handleF17() {
        builder := KeyBuilder()
            .mainKey((pt) {
                switch (pt) {
                    case 1: Send("!{Right}")
                    case 2: Send("{BackSpace}")
                }
            })
            ; .combo("LButton", "2x Click + Delete", () => (Click("Left", 2), Send("{Delete}")))
            .extend(EM.gesture(HotVectors.Gesture(HotVectors.bDir.leftRight, (pos) => pos > 0 ? Send("{Delete}") : Mod(pos, 5) == 0 ? Send("^z") : Sleep(5))))
            .build()

        this.handle(builder)
    }


    handleF18() {
        builder := KeyBuilder()
            .mainKey((pt) {
                switch (pt) {
                    case 1: Send("!{Left}")
                    case 2: Send("{Delete}")
                }
            })
            ; .combo("F17", "Cut", () => Send("^x"))
            ; .combo("F20", "3x Click + Copy", () => (Click("Left", 3), Send("^c")))
            .combo("LButton", "Del line VSCode", () => SendInput("^+k"))
            .combo("MButton", "tooltip", () => ShowTip("RButton + MButton: Zoom in/out"))            
            ; .extend(EM.gesture(HotVectors.Gesture(HotVectors.bDir.leftRight, (pos) => Mod(pos, 5) == 0 ? Send("{BackSpace}") : Send("{Delete}"))))
            .extend(EM.gesture(HotVectors.Gesture(HotVectors.bDir.leftRight, (pos) => pos < 0 ? Send("{BackSpace}") : Mod(pos, 5) == 0 ? Send("^z") : Sleep(5))))
            ; .extend(EM.gesture(HotVectors.Gesture(HotVectors.bDir.leftRight, (pos) => Send(pos < 0 ? "{Left}" : "{Right}"))))

            ; .extend(EM.gesture(HotVectors.Gesture(HotVectors.bDir.left, (pos) => Mod(pos, 5) == 0 ? Send("{BackSpace}") : Sleep(5))))
            ; .extend(EM.gesture(HotVectors.Gesture(HotVectors.bDir.right, (pos) => Mod(pos, 5) == 0 ? Send("{Delete}") : Sleep(5))))
            .build()
        this.handle(builder)
    }

    handleF19() {
        builder := KeyBuilder()
            .mainKey((pt) {
                switch (pt) {
                    case 1: State.Clipboard.isMemSlots()
                        ? App.MemSlots.smartPaste() : Send("^v")
                    case 2: Send("^a^v")
                }
            })
            .mainEnd(() => ShowTip(A_Clipboard, TipType.Paste))
            ; .combo("F13", "Select All & Paste", () => Send("^a^v"))
            ; .combo("F14", "3x Click + Paste", () => (Click("Left", 3), Send("^v")))
            ; .combo("F20", "Select All & Paste", () => Send("^a^v"))
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
                    case 3: App.MemSlots.start()
                }
            })
            .mainEnd(() => (ShowTip(A_Clipboard, TipType.Copy)))
            ; .combo("F13", "Select All & Copy", () => Send("^a^c"))
            ; .combo("F14", "3x Click + Copy", () => (Click("Left", 3), Send("^c")))
            ; .combo("F19", "Select All & Copy", () => Send("^a^c"))
            ; .combo("F18", "3x Click + Copy", () => (Click("Left", 3), Send("^c")))
            .combo("LButton", "Click & Copy", () => (Click("Left", 1), Send("^c")))
            .combo("MButton", "3x Click + Copy", () => (Click("Left", 3), Send("^c")))
            .build()

        this.handle(builder)
    }
}