class EH {    ; Enhancements for Hook KeyBuilder
    static tPreviewAuto := 1, tExitOnPress := 2, tTimeOut := 3

    static Create(type, data) => { base: EH.Prototype, type: type, data: data }

    static autoPreview(v := true) => EH.Create(EH.tPreviewAuto, v)
    static setExitOnPressType(v) => EH.Create(EH.tExitOnPress, v)
    static setTimeOut(v := 5000) => EH.Create(EH.tTimeOut, v)
}

class singleHotHook {
    static instance := ""

    static getInstance() {
        if (!singleHotHook.instance) {
            singleHotHook.instance := singleHotHook()
        }
        return singleHotHook.instance
    }

    __New() {
        if (singleHotHook.instance) {
            throw Error("singleKeyHandlerHook zaten oluşturulmuş! getInstance kullan.")
        }
    }

    handle(b, key := A_ThisHotkey) {
        if (App.state.getBusy() > 0) {
            return
        }

        /*
                mainKey := b.main_key
                exitOnPressType := b.exitOnPressType
                combos := b.combos
                shortTime := b.shortTime
                longTime := b.longTime
                gapTime := b.gapTime
                previewCallback := b.previewCallback
        */

        exitOnPressType := b.exitOnPressType ; y adisarcan gelsin ya burdan
        autoPreview := false
        timeOut := 5000
        for item in b.extensions {
            if (item is EH) {
                switch item.type {
                    case EH.tPreviewAuto: autoPreview := item.data
                    case EH.tExitOnPress: exitOnPressType := item.data
                    case EH.tTimeOut: timeOut := item.data
                }
            }
        }

        mainKeyExecuted := false
        pressType := 0

        try {
            App.state.setBusy(1)

            ; Double click kontrolü (gap varsa)
            if (b.gapTime != "") {
                result := KeyWait(key, "D T" (b.gapTime / 1000))
                if (!result) {  ; İkinci basım geldi → double click
                    KeyWait(key)
                    if (b.main_key && IsObject(b.main_key)) {
                        b.main_key.Call(4)  ; pressType = 4 → double click
                    }
                    ; OutputDebug("Double click detected on key: " key "`n")  ; Comment: Debug için double click tespit
                    return
                }
            }

            ; Ana tuş consume et (ilk tuş basımını yutmak için)
            KeyWait(key)

            startTime := A_TickCount
            mediumTriggered := false
            longTriggered := false

            ; ilk tus basimini while ile al tusun basim tipini belirle
            ; kisa basim, orta basim, uzun basim ve cift basim icin farkli fonksiyonlar calistir
            ; menü acilinca while döngüsü bitip hook devreye girer
            while (GetKeyState(key, "P")) {
                duration := A_TickCount - startTime

                ; Nullable long mod: short geçince orta çalışsın, menü açılsın
                if (b.longTime == "" && duration >= b.shortTime && !mainKeyExecuted) {
                    if (b.main_key && IsObject(b.main_key)) {
                        b.main_key.Call(1)
                        mainKeyExecuted := true
                    }

                    ; Kısa basımda çık modundaysa return
                    if (exitOnPressType == 1) {
                        return
                    }
                    break  ; Menüye geç
                }

                ; Medium beep (3-level mode)
                if (b.longTime != "" && duration >= b.shortTime && !mediumTriggered) {
                    SoundBeep(800, 50)
                    mediumTriggered := true
                }

                ; Long beep
                if (b.longTime != "" && duration >= b.longTime && !longTriggered) {
                    SoundBeep(600, 50)
                    longTriggered := true
                }

                Sleep(40)
            }

            ; Ana tuş bırakıldı → pressType hesapla ve mainKey çalıştır
            if (!mainKeyExecuted) {
                holdTime := A_TickCount - startTime
                pressType := KeyBuilder.getPressType(holdTime, b.shortTime, b.longTime)

                if (b.main_key && IsObject(b.main_key)) {
                    b.main_key.Call(pressType)
                }

                ; Exit threshold kontrolü
                if (pressType == exitOnPressType) {
                    return
                }
            }

            ; Eğer combo yoksa menü açmaya gerek yok
            if (b.combos.Length == 0) {
                return
            }

            ; Preview göster (busy 2 kaldırıldı - hook zaten consume ediyor)
            previewText := ""

            ; Otomatik preview oluştur
            if (autoPreview) {
                previewText := "━━━ MENÜ ━━━`n`n"
                for p in b.combos {
                    previewText .= p.key ": " p.desc "`n"
                }
                previewText .= "`nESC: İptal"
            }
            ; Özel preview callback varsa onu kullan
            else if (IsObject(b.previewCallback)) {
                finalPressType := mainKeyExecuted ? 1 : pressType
                previewList := b.previewCallback.Call(b, finalPressType)
                if (previewList && previewList.Length > 0) {
                    for item in previewList {
                        previewText .= item "`n"
                    }
                }
            }

            ; Preview göster
            if (previewText != "") {
                ToolTip(previewText, , , 1)
            }

            ; InputHook ile tek tuş bekle
            ih := InputHook("L1 T" (timeOut / 1000), "{Esc}")
            ih.KeyOpt("{All}", "E")  ; Tüm tuşları yakalayabilmek için
            ih.Start()
            ih.Wait()
            key := ih.Input != "" ? ih.Input : ih.EndKey

            ToolTip()  ; Preview'ı kapat

            ; Timeout kontrolü
            if (ih.EndReason == "Timeout") {
                return
            }

            ; ESC kontrolü
            if (key == "Escape") {
                return
            }

            ; Eşleşen action'ı çalıştır
            for p in b.combos {
                if (p.key = key) {
                    p.action.Call()
                    return
                }
            }

            ; Tanımsız tuş basıldı
            SoundBeep(1000, 100)

        } catch as err {
            App.ErrHandler.handleError("HookKeyHandler hata: " key, err)
        } finally {
            ToolTip("")
            App.state.setBusy(0)
        }
    }

    ; Örnek: hookCommands tarzı bir menü (backtick ile açılan komut merkezi)
    sysCommands() {
        builder := KeyBuilder(350)  ; 2-level mode
            .mainKey((dt) {
                switch (dt) {
                    case 1: SendInput("´")  ; Kısa basım: normal karakter
                        ; case 2: ; Uzun basım: menüyü aç (otomatik)
                }
            })
            .setExitOnPressType(2)  ; Kısa basımda hook beklemesin
            .combo("1", "Reload script", () => reloadScript())
            .combo("2", "Show stats", () => getStatsArray(true))
            .combo("3", "Profile manager", () => App.AppShorts.showManagerGui())
            .combo("4", "Key history", () => ShowKeyHistoryLoop())
            .combo("5", "Memory slots", () => App.MemSlots.start())
            .combo("6", "Macro recorder", () => App.Recorder.showButtons())
            .combo("7", "F13 menu", () => showF13menu())
            .combo("8", "F14 menu", () => showF14menu())
            .combo("9", "Pause script", () => DialogPauseGui())
            .combo("0", "Exit script", () => ExitApp())
            .combo("r", "Repository GUI", () => App.Repo.showGui())
            .combo("a", "TrayTip test", () => TrayTip("Başlık", "Mesaj içeriği", 1))
            .extend(EH.autoPreview(true))  ; Otomatik preview oluştur
            .extend(EH.setTimeOut(30000))  ; 30 saniye timeout
            .build()

        this.handle(builder)
    }

    ; Örnek 2: Uygulama kısayolları (CapsLock gibi bir tuşla)
    hookAppShortcuts() {
        builder := KeyBuilder(400)
            .mainKey((pt) {
                if (pt == 1) {  ; Kısa basım: CapsLock toggle
                    caps := !GetKeyState("CapsLock", "T")
                    SetCapsLockState(caps)
                    ShowTip(caps ? "CAPSLOCK" : "capslock", TipType.Info)
                }
                ; pt == 2: Uzun basım → menü aç (otomatik)
            })
            .setExitOnPressType(1)
            .combo("1", "VS Code", () => Run("code"))
            .combo("2", "Chrome", () => Run("chrome"))
            .combo("3", "Explorer", () => Run("explorer"))
            .combo("4", "Terminal", () => Run("wt.exe"))
            .combo("5", "Notepad", () => Run("notepad"))
            .extend(EH.autoPreview(true))
            .build()

        this.handle(builder, "CapsLock")
    }

    ; Örnek 3
    hookTabMenu() {
        builder := KeyBuilder(350)
            .mainKey((dt) {
                switch (dt) {
                    case 1: SendInput("{Tab}")
                        ; case 2: menü aç (otomatik)
                }
            })
            .setExitOnPressType(1)
            .combo("1", "History 1", () => App.ClipHist.loadFromHistory(1))
            .combo("2", "History 2", () => App.ClipHist.loadFromHistory(2))
            .combo("3", "History 3", () => App.ClipHist.loadFromHistory(3))
            .combo("4", "History 4", () => App.ClipHist.loadFromHistory(4))
            .combo("5", "History 5", () => App.ClipHist.loadFromHistory(5))
            .combo("6", "History 6", () => App.ClipHist.loadFromHistory(6))
            .combo("7", "History 7", () => App.ClipHist.loadFromHistory(7))
            .combo("8", "History 8", () => App.ClipHist.loadFromHistory(8))
            .combo("9", "History 9", () => App.ClipHist.loadFromHistory(9))
            .combo("h", "Show history GUI", () => App.ClipHist.showHistorySearch())
            .extend(EH.autoPreview(true))
            .build()

        this.handle(builder, "Tab")
    }

    hookCaretSlots() {
        builder := KeyBuilder(350)
            .mainKey((dt) {
                if (dt == 1) {
                    SendInput("^")
                }
            })
            .setExitOnPressType(1)
            .combo("1", "Slot 1", () => App.ClipSlot.loadFromSlot("", 1))
            .combo("2", "Slot 2", () => App.ClipSlot.loadFromSlot("", 2))
            .combo("3", "Slot 3", () => App.ClipSlot.loadFromSlot("", 3))
            .combo("4", "Slot 4", () => App.ClipSlot.loadFromSlot("", 4))
            .combo("5", "Slot 5", () => App.ClipSlot.loadFromSlot("", 5))
            .combo("6", "Slot 6", () => App.ClipSlot.loadFromSlot("", 6))
            .combo("7", "Slot 7", () => App.ClipSlot.loadFromSlot("", 7))
            .combo("8", "Slot 8", () => App.ClipSlot.loadFromSlot("", 8))
            .combo("9", "Slot 9", () => App.ClipSlot.loadFromSlot("", 9))
            .combo("0", "Slot 10", () => App.ClipSlot.loadFromSlot("", 10))
            .combo("s", "Slot GUI", () => App.ClipSlot.showSlotsSearch())
            .extend(EH.autoPreview(true))
            .build()

        this.handle(builder, "^")
    }
}