#Include <HotGestures>

class FKeyBuilder {
    __New() {
        this._mainStart := ""
        this._mainDefault := ""
        this._mainEnd := ""
        this._preview := ""
        this.gestures := []
        this.comboActions := []
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

    preview(fn) {
        this._preview := fn
        return this
    }

    mainGesture(gesture, fn) {
        this.gestures.Push({ gesture: gesture, action: fn })
        return this
    }

    combo(key, fn) {
        this.comboActions.Push({ key: key, action: fn })
        return this
    }
}

class HotkeyHandler {
    static instance := ""

    static getInstance() {
        if (!HotkeyHandler.instance) {
            HotkeyHandler.instance := HotkeyHandler()
        }
        return HotkeyHandler.instance
    }

    __New() {
        if (HotkeyHandler.instance) {
            throw Error("HotkeyHandler zaten oluşturulmuş! getInstance kullan.")
        }
        this.hgsRight := ""
    }

    ; Not: ExecuteActions, aksiyon zincirlerini (click, send, tooltip, vb.) yÃ¶netmek iÃ§in kullanÄ±lÄ±yordu.
    ; ArtÄ±k .combo callback'leri iÃ§inde doÄŸrudan aksiyonlar tanÄ±mlanabilir. Ã–rnek:
    ; .combo("F14", () => (this.clicks(3, () => {}), Send("{Delete}"), ToolTip("3x Click + Delete"), SetTimer(() => ToolTip(), -800), SoundBeep(600)))
    ; Bu, ExecuteActions'Ä±n yerini alÄ±r ve daha esnek bir yapÄ± saÄŸlar.
    ; ExecuteActions ileride gerekirse FKeyBuilder'a aksiyon metodlarÄ± (ClickTimes, Send, vb.) eklenerek tamamen kaldÄ±rÄ±labilir.
    handleFKey(builder) {
        mainStart := builder._mainStart
        mainDefault := builder._mainDefault
        mainEnd := builder._mainEnd
        gestures := builder.gestures
        comboActions := builder.comboActions
        previewFn := builder._preview

        _checkCombo(comboActions) {
            for c in comboActions {
                if (GetKeyState(c.key, "P")) {
                    state.setBusy(2)
                    KeyWait c.key
                    keyCounts.inc(c.key)
                    c.action.Call()
                    return true
                }
            }
            return false
        }


        if (state.getBusy() > 0) {
            return
        }

        try {
            state.setBusy(1)
            key := A_ThisHotkey
            if (SubStr(key, 1, 1) == "~") {
                key := SubStr(key, 2)  ; İlk karakteri at
            }

            keyCounts.inc(key)

            if (previewFn != "" && IsObject(previewFn)) { ; YENİ: Preview mantığı
                ToolTip(previewFn.Call())
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

            while GetKeyState(key, "P") {
                if (_checkCombo(comboActions)) {
                    if (gestures.Length > 0) {
                        this.hgsRight.Stop()
                    }
                    break
                }
                Sleep 50
            }
            ; while GetKeyState(key, "P") {
            ;     for c in comboActions {
            ;         if (GetKeyState(c.key, "P")) {
            ;             state.setBusy(2)
            ;             KeyWait c.key
            ;             keyCounts.inc(c.key)
            ;             c.action.Call()
            ;             if (gestures.Length > 0) {
            ;                 this.hgsRight.Stop()
            ;             }
            ;             break(2) ; persist veya checkCombo gibi metod yap
            ;         }
            ;     }
            ;     Sleep 50
            ; }

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

            if (state.getBusy() == 1 && mainDefault != "" && IsObject(mainDefault)) {
                mainDefault.Call()   ; Gesture yok/invalid, default çalış
            }

            if (mainEnd != "" && IsObject(mainEnd)) {
                mainEnd.Call()
            }
        } catch Error as err {
            errHandler.handleError(err.Message " " key)
        } finally {
            if (previewFn != "" && IsObject(previewFn)) {
                ToolTip()
            }
            if (gestures.Length > 0 && IsObject(this.hgsRight)) {
                this.hgsRight.Stop()
            }
            state.setBusy(0)
        }
    }

    ; YENİ: CapsLock için merkezi handler
    handleCapsLock() {
        static builder := FKeyBuilder()
            .preview(() => clipManager.getHistoryPreviewText())
            .mainDefault(() => SetCapsLockState(!GetKeyState("CapsLock", "T")))
            .combo("a", () => Send("^a{BackSpace}"))
            .combo("x", () => clipManager.press("^a^x"))
            .combo("c", () => clipManager.press("^a^c"))
            .combo("v", () => clipManager.press("^a^v"))
            .combo("Q", () => clipManager.press("TEST"))
            .combo("1", () => clipManager.loadFromHistory(1))
            .combo("2", () => clipManager.loadFromHistory(2))
            .combo("3", () => clipManager.loadFromHistory(3))
            .combo("4", () => clipManager.loadFromHistory(4))
            .combo("5", () => clipManager.loadFromHistory(5))
            .combo("6", () => clipManager.loadFromHistory(6))
            .combo("7", () => clipManager.loadFromHistory(7))
            .combo("8", () => clipManager.loadFromHistory(8))
            .combo("9", () => clipManager.loadFromHistory(9)) ;buildHistoryMenu
            .combo("s", () => clipManager.showHistorySearch())  ; YENİ: History search (klavye)
        this.handleFKey(builder)
    }

    handleCaret() {
        static builder := FKeyBuilder()
            .preview(() => clipManager.getSlotsPreviewText())
            .mainDefault(() => Send("{^}"))
            .combo("q", () => clipManager.press("test"))
            .combo("1", () => clipManager.loadFromSlot(1)) ;buildSlotMenu
            .combo("2", () => clipManager.loadFromSlot(2))
            .combo("3", () => clipManager.loadFromSlot(3))
            .combo("4", () => clipManager.loadFromSlot(4))
            .combo("5", () => clipManager.loadFromSlot(5))
            .combo("6", () => clipManager.loadFromSlot(6))
            .combo("0", () => clipManager.loadFromSlot(0))
            .combo("PgDn", () => ShowStats())
            .combo("s", () => clipManager.showSlotsSearch())
        this.handleFKey(builder)
    }

    handleLButton() {
        static builder := FKeyBuilder()
            .mainDefault(() => {})
            .combo("F14", () => Send("L F14"))
            .combo("F15", () => Send("L 15"))
            .combo("F16", () => Send("L 16"))
            .combo("F17", () => Send("L 17"))
            .combo("F18", () => Send("L 18"))
            .combo("F19", () => clipManager.press(["^a^v", "{Enter}"]))
            .combo("F20", () => Send("{Enter}"))
        this.handleFKey(builder)
    }

    handleMButton() {
        static builder := FKeyBuilder()
            .mainDefault(() => {})
            .combo("F15", () => Send("{RControl down}{vkBF}{RControl up}"))
            .combo("F16", () => clipManager.press(["^f", "{Sleep 100}", "^a^v"]))
            .combo("F17", () => Send("F17"))
            .combo("F18", () => Send("F18"))
            .combo("F19", () => clipManager.press(["^v", "{Enter}"]))
            .combo("F20", () => Send("{Enter}"))
            .combo("F14", () => clipManager.showHistorySearch())  ; YENİ: History search (fare MButton & F14)
        this.handleFKey(builder)
    }

    handleF13() {
        static builder := FKeyBuilder()
            .mainStart(() => (ToolTip("F13 Paste Mode"), SetTimer(() => ToolTip(), -800)))
            .mainDefault(() => showF13menu())
            .mainGesture(HotGestures.Gesture("Right-right:1,0"), () => Send("{Enter}"))
            .mainGesture(HotGestures.Gesture("Right-left:-1,0"), () => Send("{Escape}"))
            .mainGesture(HotGestures.Gesture("Right-up:0,-1"), () => Send("{Home}"))
            .mainGesture(HotGestures.Gesture("Right-down:0,1"), () => Send("{End}"))
            .mainGesture(HotGestures.Gesture("Right-diagonal-down-left:-1,1"), () => WinMinimize("A"))
            .combo("F14", () => (Click("Left", 1), clipManager.press("^v")))
            .combo("F18", () => Send("{Delete}"))
        this.handleFKey(builder)
    }

    handleF14() {
        static builder := FKeyBuilder()
            .mainDefault(() => showF14menu())
            .mainGesture(HotGestures.Gesture("Right-up:0,-1"), () => Send("{Delete}"))
            .mainGesture(HotGestures.Gesture("Right-down:0,1"), () => Send("{Backspace}"))
            .combo("F15", () => Send("^a"))
            .combo("F16", () => Send("^a"))
            .combo("F17", () => Send("{Home}"))
            .combo("F18", () => Send("{End}"))
            .combo("F19", () => Send("^a"))
            .combo("F20", () => Send("^a"))
            .combo("RButton", () => clipManager.showSlotsSearch())  ; YENİ: Slots search (fare RButton & F14)
        this.handleFKey(builder)
    }

    handleF15() {
        static builder := FKeyBuilder()
            .mainDefault(() => Send("^y"))
            .combo("F13", () => Send("F13 bos"))
            .combo("LButton", () => Send("F15 L bos"))
        this.handleFKey(builder)
    }

    handleF16() {
        static builder := FKeyBuilder()
            .mainDefault(() => Send("^z"))
            .combo("F13", () => Send("F13 bos"))
            .combo("LButton", () => Send("F16 L bos"))
        this.handleFKey(builder)
    }

    handleF17() {
        static builder := FKeyBuilder()
            .mainDefault(() => Send("!{Right}"))
            .combo("F14", () => (Click("Left", 3), Send("{Delete}"), ToolTip("3x Click + Delete"), SetTimer(() => ToolTip(), -800), SoundBeep(600)))
            .combo("F18", () => Send("{Delete}"))
            .combo("LButton", () => (Click("Left", 2), Send("{Delete}")))
            .combo("MButton", () => (Click("Left", 3), Send("{Delete}")))
        this.handleFKey(builder)
    }

    handleF18() {
        static builder := FKeyBuilder()
            .mainDefault(() => Send("!{Left}"))
            .combo("F17", () => Send("^x"))
            .combo("F20", () => (Click("Left", 3), clipManager.press("^c"))) ;her ikiside
            .combo("LButton", () => Send("^x"))
            .combo("MButton", () => Send("^x"))
        this.handleFKey(builder)
    }

    handleF19() {
        static builder := FKeyBuilder()
            .mainDefault(() => Send("^v"))
            .combo("F13", () => clipManager.press("^a^v"))
            .combo("F14", () => (Click("Left", 3), clipManager.press("^v"), ToolTip("3x Click + Paste"), SetTimer(() => ToolTip(), -800)))
            .combo("F20", () => clipManager.press("^a^v"))
            .combo("LButton", () => (Click("Left", 1), clipManager.press("^v")))
            .combo("MButton", () => (Click("Left", 3), clipManager.press("^v")))
        this.handleFKey(builder)
    }

    handleF20() {
        static builder := FKeyBuilder()
            .mainDefault(() => Send("^c"))
            .mainEnd(() => (ClipWait, Sleep(50), clipManager.showClipboardPreview()))
            .combo("F13", () => clipManager.press("^a^c"))
            .combo("F14", () => (Click("Left", 3), clipManager.press("^c"), ToolTip("3x Click + Copy"), SetTimer(() => ToolTip(), -800)))
            .combo("F19", () => clipManager.press("^a^c"))
            .combo("F18", () => (Click("Left", 3), clipManager.press("^c")))
            .combo("LButton", () => (Click("Left", 1), clipManager.press("^c")))
            .combo("MButton", () => (Click("Left", 3), clipManager.press("^c")))
        this.handleFKey(builder)
    }
}