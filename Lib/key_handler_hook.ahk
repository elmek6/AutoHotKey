; hookkey_handler.ahk - InputHook tabanlı sırayla tuş bekleyen menü sistemi
; Ana tuş basım süresi ölçülür, ardından tek tuş beklenir (combo değil, sequential)

class singleKeyHandlerHook {
    static instance := ""

    static getInstance() {
        if (!singleKeyHandlerHook.instance) {
            singleKeyHandlerHook.instance := singleKeyHandlerHook()
        }
        return singleKeyHandlerHook.instance
    }

    __New() {
        if (singleKeyHandlerHook.instance) {
            throw Error("singleKeyHandlerHook zaten oluşturulmuş! getInstance kullan.")
        }
    }

    handle(builder, key := A_ThisHotkey) {
        if (gState.getBusy() > 0) {
            return
        }

        mainKey := builder.main_key
        exitOnPressType := builder.exitOnPressType
        combos := builder.combos
        shortTime := builder.shortTime
        longTime := builder.longTime
        gapTime := builder.gapTime
        previewCallback := builder.previewCallback
        mainKeyExecuted := false
        pressType := 0

        try {
            gState.setBusy(1)

            ; Double click kontrolü (gap varsa)
            if (gapTime != "") {
                result := KeyWait(key, "D T" (gapTime / 1000))
                if (!result) {  ; İkinci basım geldi → double click
                    KeyWait(key)
                    if (mainKey && IsObject(mainKey)) {
                        mainKey.Call(3)  ; pressType = 3 → double click
                    }
                    ; OutputDebug("Double click detected on key: " key "`n")  ; Comment: Debug için double click tespit
                    return
                }
            }

            startTime := A_TickCount
            ; beepCount := (longTime != "") ? 2 : 1  ; Comment: Beep devre dışı
            mediumTriggered := false
            longTriggered := false

            while (GetKeyState(key, "P")) {
                duration := A_TickCount - startTime

                ; Nullable long mod: short geçince orta çalışsın
                if (longTime == "" && duration >= shortTime && !mainKeyExecuted) {
                    if (mainKey && IsObject(mainKey)) {
                        mainKey.Call(1)
                        mainKeyExecuted := true
                    }
                    if (exitOnPressType == 1) {
                        return
                    }
                    break
                }

                ; Beep feedback
                if (longTime != "" && duration >= shortTime && !mediumTriggered) {
                    ;SoundBeep(800, 50)
                    beepCount--
                    mediumTriggered := true
                }
                if (longTime != "" && duration >= longTime && !longTriggered) {
                    ;SoundBeep(800, 50)
                    beepCount--
                    longTriggered := true
                }

                Sleep(40)  ; While döngüsünde Sleep güncellendi
            }

            ; Ana tuş bırakıldı → pressType hesapla ve mainKey çalıştır
            if (!mainKeyExecuted) {
                holdTime := A_TickCount - startTime
                pressType := KeyBuilder.getPressType(holdTime, shortTime, longTime)

                if (mainKey && IsObject(mainKey)) {
                    mainKey.Call(pressType)
                }

                if (pressType == exitOnPressType) {
                    return
                }
            }

            ; Preview göster (ToolTip ile menü gibi)
            gState.setBusy(2)
            previewText := ""
            if (IsObject(previewCallback)) {
                finalPressType := mainKeyExecuted ? 1 : pressType
                previewList := previewCallback.Call(builder, finalPressType)
                if (previewList && previewList.Length > 0) {
                    for item in previewList {
                        previewText .= item "`n"
                    }
                    ToolTip(previewText, , , 1)  ; Stil 1 ile sabit konumda gösterebilirsin
                }
            } else if (combos.Length > 0) {
                ; Default preview: tuş + açıklama
                for p in combos {
                    previewText .= p.key ": " p.desc "`n"
                }
                ToolTip(previewText)
            }

            ; InputHook ile tek tuş bekle
            ih := InputHook("V")  ; Visible off, sadece tuş yakala
            ih.VisibleNonText := false
            ih.KeyOpt("{All}", "N")  ; Notify (EndKey ile yakala)

            ; Sadece tanımlı tuşları kabul et + Esc
            allowedKeys := ["Escape"]
            for p in combos {
                allowedKeys.Push(p.key)
            }

            ; ✅ FIX: Her tuşu ayrı ayrı EndKey yap
            for k in allowedKeys {
                ih.KeyOpt("{" k "}", "E")
            }

            ih.Start()
            ih.Wait()

            ToolTip("")  ; Her durumda kapat

            if (ih.EndKey = "Escape") {
                return
            }

            ; Ana tuş tekrar basıldıysa iptal
            if (ih.EndKey = key) {
                return
            }

            ; Eşleşen action'ı çalıştır
            for p in combos {
                if (p.key = ih.EndKey) {
                    finalPressType := mainKeyExecuted ? 1 : pressType
                    p.action.Call(finalPressType)
                    return
                }
            }

            ; Bilinmeyen tuş → uyarı beep - Comment: Beep devre dışı
            ; SoundBeep(1000, 100)

        } catch as err {
            gErrHandler.handleError("HookKeyHandler hata: " key, err)
        } finally {
            ToolTip("")
            gState.setBusy(0)
        }
    }

    ; Örnek kullanım: hookCommands tarzı bir menü (F14 gibi bir tuşla açılan komut merkezi)
    sysCommands() {
        builder := KeyBuilder()
            .setPressType(350)  ; sadece kısa/uzun (2 seviye)
            .mainKey((dt) {
                switch (dt) {
                    ; case 0: SendInput("{Tab}")
                    case 1: SendInput("´")
                }
            })
            .setExitOnPressType(0)  ; kısa basımda hook beklemesin
            .combo("1", "Reload script", () => reloadScript())
            .combo("2", "Show stats", () => getStatsArray(true))
            .combo("3", "Profile manager", () => gAppShorts.showManagerGui())
            .combo("4", "Key history", () => ShowKeyHistoryLoop())
            .combo("5", "Memory slots", () => gMemSlots.start())
            .combo("6", "Macro recorder", () => gRecorder.showButtons())
            .combo("7", "F13 menu", () => showF13menu())
            .combo("8", "F14 menu", () => showF14menu())
            .combo("9", "Pause script", () => DialogPauseGui())
            .combo("0", "Exit script", () => ExitApp())
            .combo("r", "Repository GUI", () => gRepo.showGui())
            .combo("a", "Show TrayTip", () => TrayTip("Başlık", "Mesaj içeriği", 1))
            .combo("q", "quit", () => Sleep(10))
            .setPreview((b, pt) => (
                pt = 0 ? [] : [
                    "🔥 HOOK KOMUT MERKEZİ 🔥",
                    "",
                    "1: Reload",
                    "2: Stats",
                    "3: Profile manager",
                    "4: Key history",
                    "5: Memory slots",
                    "6: Macro recorder",
                    "7: F13 menü",
                    "8: F14 menü",
                    "9: Pause script",
                    "",
                    "ESC: İptal"
                ]
            ))
            .build()
        this.handle(builder)
    }

    ; Başka bir örnek: Uygulama kısayolları için hook (CapsLock + sayı gibi)
    hookAppShortcuts() {
        builder := KeyBuilder(400)
            .mainKey((pt) => (
                pt = 0 ? SetCapsLockState(!GetKeyState("CapsLock", "T"))
                : 0
            ))
            .setExitOnPressType(0)
            .combo("1", "VS Code", () => Run("code"))
            .combo("2", "Chrome", () => Run("chrome"))
            .combo("3", "Explorer", () => Run("explorer"))
            .setPreview((b, pt) => (
                pt = 0 ? [] : [
                    "🚀 Uygulama Kısayolları",
                    "1: Visual Studio Code",
                    "2: Google Chrome",
                    "3: Dosya Gezgini"
                ]
            ))
            .build()

        this.handle(builder, "CapsLock")
    }
}