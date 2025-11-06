getStatsArray(showMsgBox := false) {
    stats := "Busy status: " gState.getBusy() "`n"
    statsArray := ["Busy status: " gState.getBusy()]

    for key, count in gKeyCounts.getAll() {
        stats .= key ": " count "`n"
        statsArray.Push(key ": " count)
    }

    recentErrors := gErrHandler.getRecentErrors(10) ;0 for all
    if (recentErrors == "") {
        stats .= "no new error (log.txt save all)"
        statsArray.Push("no new error (log.txt save all)")
    } else {
        stats .= recentErrors
        errors := StrSplit(recentErrors, "`n")
        for err in errors {
            if (Trim(err) != "" && Trim(err) != "Errors:") {
                statsArray.Push(err)
            }
        }
    }
    sinceDateTime := FormatTime(gScriptStartTime, "yyyy-MM-dd HH:mm:ss")
    if (showMsgBox) {
        MsgBox(stats, gState.getVersion() " - Stats and errors " sinceDateTime)
    }
    return statsArray
}

showF13menu() {
    Click("Middle", 1)
    gState.updateActiveWindow()

    menuF13 := Menu()
    menuAppProfile(menuF13)
    menuF13.Add()
    ; mySwitchMenu.Add("Active Class: " WinGetClass("A"), (*) => (A_Clipboard := WinGetClass("A"), ToolTip("Copied: "), SetTimer(() => ToolTip(), -2000)))

    subKeyMenu := Menu()
    subKeyMenu.Add("⏎ Enter (Right to left)", (*) => Send("{Enter}"))
    subKeyMenu.Add("⌫ Backspace", (*) => Send("{Backspace}"))
    subKeyMenu.Add("⌦ Delete", (*) => SendInput("{Delete}"))
    subKeyMenu.Add("⎋ Esc", (*) => Send("{Esc}"))
    menuF13.Add("Special keys", subKeyMenu)

    menuF13.Add("Repository GUI", (*) => gRepo.showGui())
    menuF13.Add("Select screenshot", (*) => Send("{LWin down}{Shift down}s{Shift up}{LWin up}"))
    menuF13.Add("Window screenshot", (*) => Send("!{PrintScreen}"))
    menuF13.Add()
    menuAlwaysOnTop(menuF13)

    menuF13.Show()
}

showF14menu() {
    Click("Middle", 1)

    menuF14 := Menu()
    menuF14.Add("Paste enter", (*) => gClipManager.press("^v{Enter}"))
    menuF14.Add("Cut", (*) => gClipManager.press("^x"))
    menuF14.Add("Select All + Cut", (*) => gClipManager.press("^a^x"))
    menuF14.Add("Unformatted paste", (*) => gClipManager.press("^+v"))
    menuF14.Add()

    menuF14.Add("Load clip", gClipManager.buildSlotMenu())
    menuF14.Add("Save clip", gClipManager.buildSaveSlotMenu())
    menuF14.Add("Clipboard history", gClipManager.buildHistoryMenu())
    menuF14.Add("Memory clip", (*) => gMemSlots.start())
    menuF14.Add()

    menuF14.Add("Settings", menuSettings())
    menuF14.Add("Statistics " . gState.getVersion(), menuStats())
    menuF14.Show()
}

CheckIdle(*) {
    gState.setIdleCount(gState.getIdleCount() > 0 ? gState.getIdleCount() : 60)
    if (A_TimeIdlePhysical < 60000) {
        gState.setIdleCount(60)
    } else {
        gState.setIdleCount(gState.getIdleCount() - 1)
        if (gState.getIdleCount() > 0) {
            MouseMove(-1, -1, 0, "R") ;5 dakikada bir 1 piksel yukarı ve sola hareket
            SetTimer(CheckIdle, 5 * 60 * 1000) ;5 dakikada bir kontrol
        } else {
            SetTimer(CheckIdle, 0)
        }
    }
}

hookCommands() {
    actions := Map(
        "1", { dsc: "Reload", fn: (*) => reloadScript() },
        "2", { dsc: "Show stats", fn: (*) => getStatsArray(true) },
        "3", { dsc: "Profil manager", fn: (*) => gAppShorts.showManagerGui() },
        "4", { dsc: "Show KeyHistoryLoop", fn: (*) => ShowKeyHistoryLoop() },
        "5", { dsc: "Memory slot swap", fn: (*) => gMemSlots.start() },
        "6", { dsc: "Makro...", fn: (*) => gRecorder.showButtons() },
        "7", { dsc: "F13 menü", fn: (*) => showF13menu() },
        "8", { dsc: "F14 menü", fn: (*) => showF14menu() },
        "9", { dsc: "Pause script", fn: (*) => DialogPauseGui() },
        "0", { dsc: "Exit to script", fn: (*) => ExitApp() },
        "r", { dsc: "Repository GUI", fn: (*) => gRepo.showGui() },
        "a", { dsc: "TrayTip", fn: (*) => TrayTip("Başlık", "Mesaj içeriği", 1) },
        "q", { dsc: "", fn: (*) => Sleep(10) },
    )

    menu := "Commands (Esc:exit)`n"
    for k, v in actions
        menu .= k ": " v.dsc "`n"
    ToolTip(menu)
    OutputDebug ("....")

    ih := InputHook("L1 T30", "{Esc}")
    ih.Start(), ih.Wait()
    key := ih.Input != "" ? ih.Input : ih.EndKey
    ToolTip()

    pressedTogether := GetKeyState(A_ThisHotkey, "P")
    OutputDebug (pressedTogether)

    if actions.Has(key)
        actions[key].fn()
    else
        SoundBeep(800)
}


menuSettings() {
    local menuSettings := Menu()
    menuSettings.Add("Reload", (*) => reloadScript())
    menuSettings.Add("Pause script", (*) => DialogPauseGui())
    menuSettings.Add("Show KeyHistoryLoop", (*) => ShowKeyHistoryLoop())
    ; menuSettings.Add("Awake ...", (*) => InputAwake())
    return menuSettings
}

menuStats() {
    local menuStats := Menu()
    menuStats.Add("Show stats", (*) => (getStatsArray(true)))
    menuStats.Add()

    statsArray := getStatsArray()
    for stat in statsArray {
        menuStats.Add(stat, (*) => A_Clipboard := stat)
    }
    menuStats.Add()

    latestError := ""
    for timestamp, message in gErrHandler.getAllErrors() {
        latestError := FormatTime(timestamp, "dd HH:mm:ss") ": " message
    }
    menuStats.Add("Copy last error", (*) => (gErrHandler.copyLastError()))

    return menuStats
}

menuAppProfile(targetMenu) {
    profile := gAppShorts.findProfileByWindow()
    title := gState.getActiveTitle()
    hwnd := gState.getActiveHwnd()
    className := gState.getActiveClassName()
    profile := gAppShorts.findProfileByWindow()

    if (profile) {
        for sc in profile.shortCuts {
            local lambda := sc
            targetMenu.Add("▸" . sc.shortCutName . (sc.keyDescription ? " - " sc.keyDescription : ""), (*) => lambda.play())
        }
        targetMenu.Add("Profili düzenle", (*) => gAppShorts.showManagerGui(profile))
    } else {
        targetMenu.Add("▸ Ekle (" className ")", (*) => gAppShorts.editProfileForActiveWindow())
        targetMenu.Add("Profiller", (*) => gAppShorts.showManagerGui())
    }
}

menuAlwaysOnTop(targetMenu) {
    title := gState.getActiveTitle()
    hwnd := gState.getActiveHwnd()

    if (!gState.onTopWindowsList.Has(hwnd)) {
        targetMenu.Add("📍 Add " . title, (*) => gState.toggleOnTopWindow(hwnd, title))
    }

    for key, value in gState.onTopWindowsList {
        targetMenu.Add("📌Remove " . value, ((k, v) => (*) => gState.toggleOnTopWindow(k, v))(key, value))
    }

    return targetMenu
}

DialogPauseGui() {
    Suspend(1)
    _destryoGui() {
        pauseGui.Destroy()
        pauseGui := ""
    }

    pauseGui := Gui("-MinimizeBox -MaximizeBox +AlwaysOnTop", "Script Durduruldu")
    pauseGui.Add("Button", "w200 h40", "Play Script").OnEvent("Click", (*) => (
        _destryoGui(),
        Suspend(0) ; Script'i devam ettir
    ))
    pauseGui.Add("Button", "w200 h40", "Restart without save").OnEvent("Click", (*) => (
        _destryoGui(),
        gState.setShouldSaveOnExit(false),
        Reload,
        Suspend(0)
    ))
    pauseGui.Add("Button", "w200 h40", "Reload").OnEvent("Click", (*) => (
        _destryoGui(),
        reloadScript()
    ))
    pauseGui.Add("Button", "w200 h40", "Exit").OnEvent("Click", (*) => (
        _destryoGui(),
        ExitApp
    ))
    pauseGui.OnEvent("Close", (*) => (
        Suspend(0) ; pencere kapanınca script devam etsin
    ))

    pauseGui.OnEvent("Escape", (*) => (
        _destryoGui(),
        Suspend(0)
    ))

    pauseGui.Show("xCenter yCenter")
    SoundBeep(750)
}

; Enum tipi (class olarak)
class TipType {
    static Info := "info"
    static Warning := "warning"
    static Error := "error"
    static Success := "success"
    static Cut := "cut"
    static Copy := "copy"
    static Paste := "paste"
}

ShowTip(msg, type := TipType.Info, duration := 800) {
    static tipGui := ""
    if (tipGui) {
        tipGui.Destroy()
    }

    tipGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20", "CustomTip")
    
    ; Type'a göre renkler (text/bg)
    colors := Map(
        TipType.Info, {text: "007BFF", bg: "FFFFE0"},  ; Mavi/Sarı
        TipType.Warning, {text: "FD7E14", bg: "FFFFFF"},  ; Turuncu/Beyaz
        TipType.Error, {text: "DC3545", bg: "FFFFFF"},  ; Kırmızı/Beyaz
        TipType.Success, {text: "28A745", bg: "E6FFE6"},  ; Yeşil/Açık Yeşil
        TipType.Cut, {text: "6F42C1", bg: "F8F9FA"},  ; Mor/Gri
        TipType.Copy, {text: "17A2B8", bg: "E3F2FD"},  ; Mavi/Açık Mavi
        TipType.Paste, {text: "198754", bg: "D1E7DD"}  ; Yeşil/Açık Yeşil
    )

    ; Varsayılan renk (eğer type yoksa veya hatalıysa)
    colorPair := colors.Has(type) ? colors[type] : colors[TipType.Info]
    
    tipGui.BackColor := colorPair.bg
    tipGui.SetFont("s10 c" colorPair.text, "Segoe UI")  ; Text color'ı SetFont ile uygula
    tipGui.MarginX := 6, tipGui.MarginY := 6

    tipGui.AddText("ReadOnly -E0x200", msg)

    MouseGetPos(&x, &y)
    tipGui.Show("x" (x + 16) " y" (y + 16) " AutoSize NoActivate")

    SetTimer(() => (tipGui.Destroy(), tipGui := ""), -duration)
}