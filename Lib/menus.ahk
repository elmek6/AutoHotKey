getStatsArray(showMsgBox := false) {
    statsArray := ["Busy status: " State.Busy.get()]

    for key, count in App.KeyCounts.getAll() {
        statsArray.Push(key ": " count)
    }

    for line in App.ClipHist.getStatsInfo() {
        statsArray.Push(line)
    }

    recentErrors := App.ErrHandler.getRecentErrors(10) ;0 for all
    if (recentErrors == "") {
        statsArray.Push("no new error (log.txt save all)")
    } else {
        for err in StrSplit(recentErrors, "`n") {
            if (Trim(err) != "" && Trim(err) != "Errors:") {
                statsArray.Push(err)
            }
        }
    }
    if (showMsgBox) {
        sinceDateTime := FormatTime(State.Script.getStartTime(), "yyyy-MM-dd HH:mm:ss")
        MsgBox(StrJoin(statsArray, "`n"), State.Script.getVersion() " - Stats and errors " sinceDateTime)
    }
    return statsArray
}

showF13menu() {
    Click("Middle", 1)
    State.window.update()

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

    menuF13.Add("Clipboard history win", (*) => SetTimer(() => Send("#v"), -20))
    menuF13.Add("Clipboard history", App.ClipHist.buildHistoryMenu())

    menuF13.Add("Repository GUI", (*) => App.Repo.showGui())
    menuF13.Add("Select screenshot", (*) => Send("{LWin down}{Shift down}s{Shift up}{LWin up}"))
    menuF13.Add("Window screenshot", (*) => Send("!{PrintScreen}"))
    menuF13.Add("Incognito modu", (*) => App.Incognito.toggle())
    if (App.Incognito.isActive())
        menuF13.Check("Incognito modu")

    menuF13.Add()
    menuAlwaysOnTop(menuF13)

    menuF13.Show()
}

showF14menu() {
    Click("Middle", 1)

    menuF14 := Menu()
    menuF14.Add("Paste enter", (*) => Send("^v{Enter}"))
    menuF14.Add("Select All + Cut", (*) => Send("^a^x"))
    menuF14.Add("Unformatted paste", (*) => Send("^+v"))
    menuF14.Add()
    menuF14.Add("Load from slot", App.ClipSlot.buildLoadSlotMenu())
    menuF14.Add("Save to slot", App.ClipSlot.buildSaveSlotMenu())
    local sideLabel := "Side slot" . (App.ClipSlot.defaultGroupName != "" ? " [" . App.ClipSlot.defaultGroupName . "]" : "")
    menuF14.Add(sideLabel, buildSideSlotMenu())
    menuF14.Add("Memory clip", (*) => App.MemSlots.start())
    menuF14.Add()
    menuF14.Add("System " . State.Script.getVersion() . (App.ErrHandler.lastFullError == "" ? "" : " (error)"), menuStats())
    menuF14.Show()
}


buildSideSlotMenu() {
    local m := Menu()
    m.Add("Yeni grup ekle", (*) => App.ClipSlot.promptNewGroup())
    m.Add("Notepad ile aç", (*) => Run("notepad.exe " Path.Slot))
    m.Add()
    m.Add("No side slot", (*) => App.ClipSlot.setDefaultGroup(""))
    local allGroups := App.ClipSlot.getGroupsName()
    for name in allGroups {
        local sub := Menu()
        sub.Add("Select this group", ((n) => (*) => App.ClipSlot.setDefaultGroup(n))(name))
        sub.Add()
        Loop 10 {
            local idx := A_Index
            local slotKey := idx == 10 ? "0" : String(idx)
            local slotName := App.ClipSlot.getName(name, idx)
            local preview := App.ClipSlot.getSlotPreview(name, idx)
            local label := slotKey . " " . slotName . ": " . preview
            sub.Add(label, ((n, i) => (*) => (A_Clipboard := App.ClipSlot.getContent(n, i)))(name, idx))
        }
        sub.Add()
        sub.Add("Delete this group", ((n) => (*) => (
            MsgBox("'" . n . "' grubunu silmek istiyor musun?", "Grup sil", "YesNo") == "Yes"
                ? App.ClipSlot.deleteGroup(n)
            : 0
        ))(name))
        local groupLabel := name . (App.ClipSlot.defaultGroupName == name ? " ✓" : "")
        m.Add(groupLabel, sub)
    }
    return m
}

menuStats() {
    local menuStats := Menu()
    menuStats.Add("Reload", (*) => reloadScript())
    menuStats.Add("Pause script", (*) => DialogPauseGui())
    menuStats.Add("Show KeyHistoryLoop", (*) => ShowKeyHistoryLoop())
    menuStats.Add()
    menuStats.Add("Show stats", (*) => (getStatsArray(true)))
    menuStats.Add("Copy last error", (*) => (App.ErrHandler.copyLastError()))

    return menuStats
}

menuAppProfile(targetMenu) {
    profile := App.AppShorts.findProfileByWindow()
    className := State.Window.getClass()

    if (profile) {
        for sc in profile.shortCuts {
            ; IIFE şart: closure değişkeni referansla yakalar, tek 'lambda' değişkeni
            ; kullanılınca tüm menü öğeleri SON kısayolu oynatıyordu
            targetMenu.Add("▸" . sc.shortCutName . (sc.keyDescription ? " - " sc.keyDescription : ""), ((s) => (*) => s.play())(sc))
        }
        targetMenu.Add("Profili düzenle", (*) => App.AppShorts.showManagerGui(profile))
    } else {
        targetMenu.Add("▸ Ekle (" className ")", (*) => App.AppShorts.editProfileForActiveWindow())
        targetMenu.Add("Profiller", (*) => App.AppShorts.showManagerGui())
    }
}

menuAlwaysOnTop(targetMenu) {
    title := State.Window.getTitle()
    hwnd := State.Window.getHwnd()

    if (!State.Window.onTopWindows.Has(hwnd))
        targetMenu.Add("📍 Add " . title, (*) => State.Window.toggleAlwaysOnTop(hwnd, title))

    for key, value in State.Window.onTopWindows {
        targetMenu.Add("📌 " . value, ((k, v) => (*) => State.Window.toggleAlwaysOnTop(k, v))(key, value))
        targetMenu.Check("📌 " . value)
    }

    return targetMenu
}

DialogPauseGui(criticalMsg := "") {
    Suspend(1)
    _destroyGui() {
        pauseGui.Destroy()
        pauseGui := ""
    }

    pauseGui := Gui("-MinimizeBox -MaximizeBox +AlwaysOnTop", "Script Durduruldu")
    pauseGui.Add("Button", "w200 h40", "Play Script").OnEvent("Click", (*) => (
        _destroyGui(),
        Suspend(0) ; Script'i devam ettir
    ))
    pauseGui.Add("Button", "w200 h40", "Restart without save").OnEvent("Click", (*) => (
        _destroyGui(),
        State.Script.setShouldSaveOnExit(false),
        Reload,
        Suspend(0)
    ))
    pauseGui.Add("Button", "w200 h40", "Reload").OnEvent("Click", (*) => (
        _destroyGui(),
        reloadScript()
    ))
    pauseGui.Add("Button", "w200 h40", "Exit").OnEvent("Click", (*) => (
        _destroyGui(),
        ExitApp
    ))
    if (criticalMsg != "") {
        pauseGui.SetFont("s9 cRed", "Segoe UI")
        pauseGui.Add("Text", "w380 y+16 Wrap", "⚠ KRİTİK HATA:`n" criticalMsg)
        pauseGui.SetFont("s10", "Segoe UI")
    }
    pauseGui.OnEvent("Close", (*) => (
        Suspend(0) ; pencere kapanınca script devam etsin
    ))

    pauseGui.OnEvent("Escape", (*) => (
        _destroyGui(),
        Suspend(0)
    ))

    pauseGui.Show("xCenter yCenter")
    SoundBeep(750)
}

; Kritik hata dialogu: "Devam Et" → normal devam, "Durdur" → DialogPauseGui açar
; Dönüş değeri: "continue" veya "stop"
DialogCriticalError(message) {
    local result := "continue"
    local decided := false

    dlg := Gui("+AlwaysOnTop", "⚠ KRİTİK HATA")
    dlg.SetFont("s10", "Segoe UI")
    dlg.Add("Text", "w420", message)
    dlg.Add("Button", "w200 h36 y+16", "Devam Et").OnEvent("Click", (*) => (
        result := "continue", decided := true, dlg.Destroy()
    ))
    dlg.Add("Button", "w200 h36 x+10", "Durdur").OnEvent("Click", (*) => (
        result := "stop", decided := true, dlg.Destroy()
    ))
    dlg.OnEvent("Close", (*) => (decided := true, dlg.Destroy()))  ; X ile kapatınca pencere gizli kalıp sızıyordu
    dlg.Show("xCenter yCenter")
    SoundBeep(400, 600)

    while (!decided)
        Sleep 50

    if (result == "stop")
        DialogPauseGui(message)

    return result
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
    static BigClip := "bigclip"
}

ShowTip(msg, type := TipType.Info, duration := 800) {
    static tipGui := ""
    static hideTimer := ""

    ; Bekleyen eski kapatma timer'ını iptal et — yoksa kısa süreli eski tip'in
    ; timer'ı, yeni gösterilen tip'i süresinden önce yok ediyordu
    if (hideTimer) {
        SetTimer(hideTimer, 0)
        hideTimer := ""
    }

    ; Önceki tip varsa yok et
    if (tipGui && IsObject(tipGui)) {
        try tipGui.Destroy()
        tipGui := ""
    }

    msg := Trim(msg, " `t`n`r") ; yalnizca bas ve sondaki boşlukları ve gereksiz enter'ları kaldırir (cok hizli)
    if (StrLen(msg) > 5000) {
        msg := "➡️" . SubStr(msg, 1, 5000) . "`n[..................]"
    }

    tipGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20", "CustomTip")

    ; Type'a göre renkler (text/bg)
    colors := Map(
        TipType.Info, { text: "007BFF", bg: "FFFFE0" },  ; Mavi/Sarı
        TipType.Warning, { text: "FD7E14", bg: "FFFFFF" },  ; Turuncu/Beyaz
        TipType.Error, { text: "DC3545", bg: "FFFFFF" },  ; Kırmızı/Beyaz
        TipType.Success, { text: "28A745", bg: "E6FFE6" },  ; Yeşil/Açık Yeşil
        TipType.Cut, { text: "6F42C1", bg: "F8F9FA" },  ; Mor/Gri
        TipType.Copy, { text: "0D6EFD", bg: "F8F9FA" },  ; Mavi/Açık Mavi
        TipType.Paste, { text: "198754", bg: "F8F9FA" },  ; Yeşil/Açık Yeşil
        TipType.BigClip, { text: "808080", bg: "F0F0F0" }  ; Gri/Açık Gri (Bellek kısıtlaması)
    )

    ; Varsayılan renk (eğer type yoksa veya hatalıysa)
    colorPair := colors.Has(type) ? colors[type] : colors[TipType.Info]

    tipGui.BackColor := colorPair.bg
    tipGui.SetFont("s10 c" colorPair.text, "Segoe UI")  ; Text color'ı SetFont ile uygula
    tipGui.MarginX := 4, tipGui.MarginY := 4
    tipGui.AddText("ReadOnly -E0x200", msg)

    MouseGetPos(&x, &y)
    tipGui.Show("x" (x + 16) " y" (y + 16) " AutoSize NoActivate")

    hideTimer := DestroyTip
    SetTimer(hideTimer, -duration)

    DestroyTip() {
        if (tipGui && IsObject(tipGui)) {
            try tipGui.Destroy()
            tipGui := ""
        }
        hideTimer := ""
    } }

