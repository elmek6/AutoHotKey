getStatsArray(showMsgBox := false) {
    stats := "Busy status: " state.getBusy() "`n"
    statsArray := ["Busy status: " state.getBusy()]

    for key, count in keyCounts.getAll() {
        stats .= key ": " count "`n"
        statsArray.Push(key ": " count)
    }

    recentErrors := errHandler.getRecentErrors(10) ;0 for all
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
    sinceDateTime := FormatTime(scriptStartTime, "yyyy-MM-dd HH:mm:ss")
    if (showMsgBox) {
        MsgBox(stats, state.getVersion() " - Stats and errors " sinceDateTime)
    }
    return statsArray
}

showF13menu() {
    Click("Middle", 1)
    state.updateActiveWindow()

    menuF13 := Menu()
    ; menuF13.Add("Add profile :", menuAppProfile())
    menuAppProfile(menuF13)
    menuF13.Add()
    ; mySwitchMenu.Add("Active Class: " WinGetClass("A"), (*) => (A_Clipboard := WinGetClass("A"), ToolTip("Copied: "), SetTimer(() => ToolTip(), -2000)))
    menuF13.Add("⏎ Enter (Right to left)", (*) => Send("{Enter}"))
    menuF13.Add("⌫ Backspace", (*) => Send("{Backspace}"))
    menuF13.Add("⌦ Delete", (*) => SendInput("{Delete}"))
    menuF13.Add("␣ Space", (*) => Send("{Space}"))
    menuF13.Add("⎋ Esc", (*) => Send("{Esc}"))
    menuF13.Add("⇱ Home", (*) => Send("{Home}"))
    menuF13.Add("␣ Space", (*) => Send("{Space}"))
    menuF13.Add("⇲ End", (*) => Send("{End}"))
    menuF13.Add()
    menuF13.Add("Select screenshot", (*) => Send("{LWin down}{Shift down}s{Shift up}{LWin up}"))
    menuF13.Add("Window screenshot", (*) => Send("!{PrintScreen}"))
    menuF13.Add()
    menuAlwaysOnTop(menuF13)

    menuF13.Show()
}

showF14menu() {
    Click("Middle", 1)

    menuF14 := Menu()
    menuF14.Add("Paste enter", (*) => clipManager.press("^v{Enter}"))
    menuF14.Add("Cut", (*) => clipManager.press("^x"))
    menuF14.Add("Select All + Cut", (*) => clipManager.press("^a^x"))
    menuF14.Add("Unformatted paste", (*) => clipManager.press("^+v"))
    menuF14.Add()

    ;fikir; move, rename, clear gelebiLlir
    menuF14.Add("Load clip", clipManager.buildSlotMenu())
    menuF14.Add("Save clip", clipManager.buildSaveSlotMenu())
    menuF14.Add("Clipboard history", clipManager.buildHistoryMenu())
    menuF14.Add("Memory clip", (*) => memSlots.start(true))
    menuF14.Add()

    menuF14.Add("Settings", menuSettings())
    menuF14.Add("Statistics " . state.getVersion(), menuStats())
    menuF14.Show()
}

CheckIdle(*) {
    state.setIdleCount(state.getIdleCount() > 0 ? state.getIdleCount() : 60)
    if (A_TimeIdlePhysical < 60000) {
        state.setIdleCount(60)
    } else {
        state.setIdleCount(state.getIdleCount() - 1)
        if (state.getIdleCount() > 0) {
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
        "3", { dsc: "Profil manager", fn: (*) => appShorts.showManagerGui() },
        "4", { dsc: "Show KeyHistoryLoop", fn: (*) => ShowKeyHistoryLoop() },
        "5", { dsc: "Memory slot swap", fn: (*) => memSlots.start(false) },
        "6", { dsc: "Makro...", fn: (*) => recorder.showButtons() },
        "7", { dsc: "F13 menü", fn: (*) => showF13menu() },
        "8", { dsc: "F14 menü", fn: (*) => showF14menu() },
        "9", { dsc: "Pause script", fn: (*) => DialogPauseGui() },
        "0", { dsc: "Exit to script", fn: (*) => ExitApp() },
        "a", { dsc: "TrayTip", fn: (*) => TrayTip("Başlık", "Mesaj içeriği", 1) },
        "q", { dsc: "", fn: (*) => Sleep(10) },
        ; "s", { dsc: "Save chrome position", fn: (*) => chromePos.saveState() }
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
    for timestamp, message in errHandler.getAllErrors() {
        latestError := FormatTime(timestamp, "dd HH:mm:ss") ": " message
    }
    menuStats.Add("Copy last error", (*) => (errHandler.copyLastError()))

    return menuStats
}

menuAppProfile(targetMenu) {
    profile := appShorts.findProfileByWindow()
    title := state.getActiveTitle()
    hwnd := state.getActiveHwnd()
    className := state.getActiveClassName()
    profile := appShorts.findProfileByWindow()


    if (profile) {
        for sc in profile.shortCuts {
            local lambda := sc
            targetMenu.Add("▸" . sc.shortCutName . (sc.keyDescription ? " - " sc.keyDescription : ""), (*) => lambda.play())
        }
        targetMenu.Add("Profili düzenle", (*) => appShorts.showManagerGui(profile))
        ; targetMenu.Add("App> " . profile.profileName, subMenu)
    } else {
        targetMenu.Add("▸ Ekle (" className ")", (*) => appShorts.editProfileForActiveWindow())
        targetMenu.Add("Profiller", (*) => appShorts.showManagerGui())
    }
}

menuAlwaysOnTop(targetMenu) {
    ; menuTops := Menu()
    title := state.getActiveTitle()
    hwnd := state.getActiveHwnd()

    if (!state.onTopWindowsList.Has(hwnd)) {
        targetMenu.Add("📍 Add " . title, (*) => state.toggleOnTopWindow(hwnd, title))
    }

    for key, value in state.onTopWindowsList {
        targetMenu.Add("📌Remove " . value, ((k, v) => (*) => state.toggleOnTopWindow(k, v))(key, value))
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
        state.setShouldSaveOnExit(false),
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

    ; Esc = pencereyi kapat + script devam
    pauseGui.OnEvent("Escape", (*) => (
        _destryoGui(),
        Suspend(0)
    ))

    pauseGui.Show("xCenter yCenter")
    SoundBeep(750)
}