getStatsArray(showMsgBox := false) {
    stats := "Busy status: " State.Busy.get() "`n"
    statsArray := ["Busy status: " State.Busy.get()]

    for key, count in App.KeyCounts.getAll() {
        stats .= key ": " count "`n"
        statsArray.Push(key ": " count)
    }

    recentErrors := App.ErrHandler.getRecentErrors(10) ;0 for all
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
    sinceDateTime := FormatTime(State.Script.getStartTime(), "yyyy-MM-dd HH:mm:ss")
    if (showMsgBox) {
        MsgBox(stats, State.Script.getVersion() " - Stats and errors " sinceDateTime)
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

    menuF13.Add("Repository GUI", (*) => App.Repo.showGui())
    menuF13.Add("Select screenshot", (*) => Send("{LWin down}{Shift down}s{Shift up}{LWin up}"))
    menuF13.Add("Window screenshot", (*) => Send("!{PrintScreen}"))
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
    menuF14.Add("Clipboard history win", (*) => SetTimer(() => Send("#v"), -20))
    menuF14.Add()
    menuF14.Add("Load from slot", App.ClipSlot.buildLoadSlotMenu())
    menuF14.Add("Save to slot", App.ClipSlot.buildSaveSlotMenu())
    local sideLabel := "Side slot" . (App.ClipSlot.defaultGroupName != "" ? " [" . App.ClipSlot.defaultGroupName . "]" : "")
    menuF14.Add(sideLabel, buildSideSlotMenu())
    menuF14.Add("Clipboard history", App.ClipHist.buildHistoryMenu())
    menuF14.Add("Big Clip Deep Search", (*) => App.BigClipHist.showSearch())
    menuF14.Add("Memory clip", (*) => App.MemSlots.start())
    menuF14.Add()
    menuF14.Add("Settings", menuSettings())
    menuF14.Add("Statistics " . State.Script.getVersion() . (App.ErrHandler.lastFullError == "" ? "" : " (error)"), menuStats())
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
        menuStats.Add(stat, ((s) => (*) => A_Clipboard := s)(stat))
    }
    menuStats.Add()

    latestError := ""
    for timestamp, message in App.ErrHandler.getAllErrors() {
        latestError := FormatTime(timestamp, "dd HH:mm:ss") ": " message
    }
    menuStats.Add("Copy last error", (*) => (App.ErrHandler.copyLastError()))

    return menuStats
}

menuAppProfile(targetMenu) {
    profile := App.AppShorts.findProfileByWindow()
    title := State.Window.getTitle()
    hwnd := State.Window.getHwnd()
    className := State.Window.getClass()
    profile := App.AppShorts.findProfileByWindow()

    if (profile) {
        for sc in profile.shortCuts {
            local lambda := sc
            targetMenu.Add("▸" . sc.shortCutName . (sc.keyDescription ? " - " sc.keyDescription : ""), (*) => lambda.play())
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

    if (!State.Window.onTopWindows.Has(hwnd)) {
        targetMenu.Add("📍 Add " . title, (*) => State.Window.toggleAlwaysOnTop(hwnd, title))
    }

    for key, value in State.Window.onTopWindows {
        targetMenu.Add("📌Remove " . value, ((k, v) => (*) => State.Window.toggleAlwaysOnTop(k, v))(key, value))
    }

    return targetMenu
}

DialogPauseGui() {
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
        TipType.Paste, { text: "198754", bg: "F8F9FA" }  ; Yeşil/Açık Yeşil
    )

    ; Varsayılan renk (eğer type yoksa veya hatalıysa)
    colorPair := colors.Has(type) ? colors[type] : colors[TipType.Info]

    tipGui.BackColor := colorPair.bg
    tipGui.SetFont("s10 c" colorPair.text, "Segoe UI")  ; Text color'ı SetFont ile uygula
    tipGui.MarginX := 4, tipGui.MarginY := 4
    tipGui.AddText("ReadOnly -E0x200", msg)

    MouseGetPos(&x, &y)
    tipGui.Show("x" (x + 16) " y" (y + 16) " AutoSize NoActivate")

    SetTimer(() => DestroyTip(), -duration)

    DestroyTip() {
        if (tipGui && IsObject(tipGui)) {
            try tipGui.Destroy()
            tipGui := ""
        }
    } }

; --------------------------------------------------------------

class QuickMenu {
    ; Basit liste göster, callback'e seçilen text ve index döner
    static Show(items, callback, title := "") {
        qm := Menu()

        if (title != "") {
            qm.Add(title, (*) => 0)
            qm.Disable(title)
            qm.Add()
        }

        for i, item in items {
            local text := IsObject(item) && item.HasOwnProp("text") ? item.text : item
            local key := IsObject(item) && item.HasOwnProp("key") ? item.key : i
            local display := key ": " text
            qm.Add(display, ((t, idx) => (*) => callback(t, idx))(text, i))
        }

        qm.Show()
    }
}