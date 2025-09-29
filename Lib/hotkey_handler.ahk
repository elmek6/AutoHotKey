#Include <HotGestures>

TapOrHold(shortFn, mediumFn, longFn := "", shortTime := 400, longTime := 1400) {
    startTime := A_TickCount
    thisHotkey := A_ThisHotkey
    beepCount := 2

    while (GetKeyState(thisHotkey, "P")) {
        duration := A_TickCount - startTime

        if (duration < shortTime) {
            ;     OutputDebug("short tap`n")
        } else
            if (duration < longTime && beepCount > 1) {
                ; OutputDebug("mid tap`n")
                SoundBeep(800, 70)
                beepCount--
            } else
                if (duration > longTime && longFn != "" && beepCount > 0) {
                    ; OutputDebug("long tap`n")
                    SoundBeep(600, 100)
                    beepCount--
                }

        Sleep(40)
    }

    duration := A_TickCount - startTime

    if (duration < shortTime) {
        shortFn.Call()
    }
    else if (duration < longTime || longFn == "") {
        mediumFn.Call()
    }
    else if (longFn != "") {
        longFn.Call()
    }
}

class FKeyBuilder {
    __New() {
        this._mainStart := ""
        this._mainDefault := ""
        this._mainEnd := ""
        this.gestures := []
        this.comboActions := []
        this.tips := []
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
        previewList := builder.tips  ; Artık her zaman tips kullan
        startTime := A_TickCount

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

            if (previewList.Length > 0) { ;belki belirli bir süre basinca cikmasi daha iyi olur??
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

            while GetKeyState(key, "P") {
                if (_checkCombo(comboActions)) {
                    if (gestures.Length > 0) {
                        this.hgsRight.Stop()
                    }
                    break
                }
                ; else If (key >= "0" && key <= "9" && !combo.contains(key) startTime + 300 < A_TickCount) { ;tekrar testi icin sonuc basarisiz kendini cagiriyor!!
                ;     ; OutputDebug ("1")
                ;     SendInput(key)
                ; }
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

            if (state.getBusy() == 1 && mainDefault != "" && IsObject(mainDefault)) {
                mainDefault.Call()   ; Gesture yok/invalid, default çalış
            }

            if (mainEnd != "" && IsObject(mainEnd)) {
                mainEnd.Call()
            }
        } catch Error as err {
            errHandler.handleError(err.Message " " key)
        } finally {
            if (previewList.Length > 0) {
                ToolTip()
            }
            if (gestures.Length > 0 && IsObject(this.hgsRight)) {
                this.hgsRight.Stop()
            }
            state.setBusy(0)
        }
    }

__handleCapsLock() {
    static builder := FKeyBuilder()
        .mainDefault(() => SetCapsLockState(!GetKeyState("CapsLock", "T")))
        .combos("a", "Select All & Delete", () => Send("^a{BackSpace}"))
        .combos("x", "Cut All", () => clipManager.press("^a^x"))
        .combos("c", "Copy All", () => clipManager.press("^a^c"))
        .combos("v", "Paste All", () => clipManager.press("^a^v"))
        .combos("q", "-", Sleep(50))
        .combos("1", "Load History 1", () => clipManager.loadFromHistory(1))
        .combos("2", "Load History 2", () => clipManager.loadFromHistory(2))
        .combos("3", "Load History 3", () => clipManager.loadFromHistory(3))
        .combos("4", "Load History 4", () => clipManager.loadFromHistory(4))
        .combos("5", "Load History 5", () => clipManager.loadFromHistory(5))
        .combos("6", "Load History 6", () => clipManager.loadFromHistory(6))
        .combos("7", "Load History 7", () => clipManager.loadFromHistory(7))
        .combos("8", "Load History 8", () => clipManager.loadFromHistory(8))
        .combos("9", "Load History 9", () => clipManager.loadFromHistory(9))
        .combos("s", "Show History Search", () => clipManager.showHistorySearch())
    builder.setPreview(clipManager.getHistoryPreviewList())
    this.handleFKey(builder)
}

handleLButton() {
    static builder := FKeyBuilder()
        ; .mainEnd(() => (
        ;     ;if appProfile == auto
        ;     Sleep(50)
        ;     MouseGetPos(&x, &y, &hWnd),
        ;     ; title := WinGetTitle(hWnd)
        ;     class := WinGetClass(hWnd),
        ;     ; text := WinGetText(hWnd)
        ;     ; OutputDebug("Title: " title "`nClass: " class "`nText: " SubStr(text, 1, 100))
        ;     OutputDebug("Class: " class "`n")
        ;     ; Qt5QWindowIcon
        ; ))
        .combos("F14", "LB+F14() => Send('L F14')", () => Send("L F14"))
        .combos("F15", "LB+F15() => Send('L 15')", () => Send("L 15"))
        .combos("F16", "LB+F16() => Send('L 16')", () => Send("L 16"))
        .combos("F17", "LB+F17() => Send('L 17')", () => Send("L 17"))
        .combos("F18", "LB+F18() => Send('L 18')", () => Send("L 18"))
        .combos("F19", "All+Paste", () => clipManager.press(["^a^v", "{Enter}"]))
        .combos("F20", "Enter", () => Send("{Enter}"))
    builder.setPreview([])
    this.handleFKey(builder)
}

handleMButton() {
    static builder := FKeyBuilder()
        .mainDefault(() => {})
        .combos("F15", "Delete Word", () => Send("{RControl down}{vkBF}{RControl up}"))
        .combos("F16", "Find & Paste", () => clipManager.press(["^f", "{Sleep 100}", "^a^v"]))
        .combos("F17", "Send F17", () => Send("F17"))
        .combos("F18", "Send F18", () => Send("F18"))
        .combos("F19", "Paste & Enter", () => clipManager.press(["^v", "{Enter}"]))
        .combos("F20", "Enter", () => Send("{Enter}"))
        .combos("F14", "Show History Search", () => clipManager.showHistorySearch())
    builder.setPreview([])
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
        .combos("F14", "Click & Paste", () => (Click("Left", 1), clipManager.press("^v")))
        .combos("F18", "Delete", () => Send("{Delete}"))
    builder.setPreview([])
    this.handleFKey(builder)
}

handleF14() {
    static builder := FKeyBuilder()
        .mainDefault(() => showF14menu())
        .mainGesture(HotGestures.Gesture("Right-up:0,-1"), () => Send("{Delete}"))
        .mainGesture(HotGestures.Gesture("Right-down:0,1"), () => Send("{Backspace}"))
        .combos("F15", "Select All", () => Send("^a"))
        .combos("F16", "Select All", () => Send("^a"))
        .combos("F17", "Home", () => Send("{Home}"))
        .combos("F18", "End", () => Send("{End}"))
        .combos("F19", "Select All", () => Send("^a"))
        .combos("F20", "Select All", () => Send("^a"))
        .combos("RButton", "Show Slots Search", () => clipManager.showSlotsSearch())
    builder.setPreview([])
    this.handleFKey(builder)
}

handleF15() {
    static builder := FKeyBuilder()
        .mainDefault(() => Send("^y"))
        .combos("F13", "Send F13", () => Send("F13 bos"))
        .combos("LButton", "Send F15 L", () => Send("F15 L bos"))
    this.handleFKey(builder)
}

handleF16() {
    static builder := FKeyBuilder()
        .mainDefault(() => Send("^z"))
        .combos("F13", "Send F13", () => Send("F13 bos"))
        .combos("LButton", "Send F16 L", () => Send("F16 L bos"))
    this.handleFKey(builder)
}

handleF17() {
    static builder := FKeyBuilder()
        .mainDefault(() => Send("!{Right}"))
        .combos("F14", "3x Click + Delete", () => (Click("Left", 3), Send("{Delete}"), ToolTip("3x Click + Delete"), SetTimer(() => ToolTip(), -800), SoundBeep(600)))
        .combos("F18", "Delete", () => Send("{Delete}"))
        .combos("LButton", "2x Click + Delete", () => (Click("Left", 2), Send("{Delete}")))
        .combos("MButton", "3x Click + Delete", () => (Click("Left", 3), Send("{Delete}")))
    this.handleFKey(builder)
}

handleF18() {
    static builder := FKeyBuilder()
        .mainDefault(() => Send("!{Left}"))
        .combos("F17", "Cut", () => Send("^x"))
        .combos("F20", "3x Click + Copy", () => (Click("Left", 3), clipManager.press("^c")))
        .combos("LButton", "Cut", () => Send("^x"))
        .combos("MButton", "Cut", () => Send("^x"))
    this.handleFKey(builder)
}

handleF19() {
    static builder := FKeyBuilder()
        .mainDefault(() => Send("^v"))
        .combos("F13", "Select All & Paste", () => clipManager.press("^a^v"))
        .combos("F14", "3x Click + Paste", () => (Click("Left", 3), clipManager.press("^v"), ToolTip("3x Click + Paste"), SetTimer(() => ToolTip(), -800)))
        .combos("F20", "Select All & Paste", () => clipManager.press("^a^v"))
        .combos("LButton", "Click & Paste", () => (Click("Left", 1), clipManager.press("^v")))
        .combos("MButton", "3x Click + Paste", () => (Click("Left", 3), clipManager.press("^v")))
    this.handleFKey(builder)
}

handleF20() {
    static builder := FKeyBuilder()
        .mainDefault(() => Send("^c"))
        .mainEnd(() => (ClipWait, Sleep(50), clipManager.showClipboardPreview()))
        .combos("F13", "Select All & Copy", () => clipManager.press("^a^c"))
        .combos("F14", "3x Click + Copy", () => (Click("Left", 3), clipManager.press("^c"), ToolTip("3x Click + Copy"), SetTimer(() => ToolTip(), -800)))
        .combos("F19", "Select All & Copy", () => clipManager.press("^a^c"))
        .combos("F18", "3x Click + Copy", () => (Click("Left", 3), clipManager.press("^c")))
        .combos("LButton", "Click & Copy", () => (Click("Left", 1), clipManager.press("^c")))
        .combos("MButton", "3x Click + Copy", () => (Click("Left", 3), clipManager.press("^c")))
    builder.setPreview([])
    this.handleFKey(builder)
}
/*
    handleNums(number) {
        builder := FKeyBuilder()
            .mainDefault(() => Send(number))
            .combos("SC029", number, () => clipManager.saveToSlot(number))
            .combos("Tab", number, () => Sleep(number * 100))
            .combos("CapsLock", number, () => clipManager.loadFromSlot(number))
        builder.setPreview([])
        this.handleFKey(builder)
    }
*/
}