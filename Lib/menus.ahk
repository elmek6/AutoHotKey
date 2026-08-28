getStatsArray(showMsgBox := false) {
    statsArray := ["Busy status: " State.Busy.get()]

    for key, count in App.KeyCounts.getAll() {
        statsArray.Push(key ": " count)
    }

    for line in App.ClipHist.getStatsInfo() {
        statsArray.Push(line)
    }

    for line in App.ClipImages.getStatsInfo() {
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

; ── Menü kolonları ─────────────────────────────────────────────────────
; Win32 menüsü dikeyde ekran boyuyla sınırlı: sığmayınca Windows kolon
; açmaz, üste/alta kaydırma oku koyar (Win95 dönemindeki otomatik kolona
; sarma davranışı Win2000'de kaldırıldı). Kolonu ELLE istemek gerekiyor.
;
; Bunun bayrağı MFT_MENUBARBREAK / MFT_MENUBREAK: bayrağı taşıyan öğe YENİ
; BİR KOLONUN ilk öğesi olur. AHK v2 bunu Menu.Add'in 3. parametresinden
; veriyor — GetMenuItemInfo ile doğrulandı (BarBreak -> fType 0x20,
; Break -> 0x40), yani DllCall'a gerek yok.
;
;   MENU_COL     "BarBreak" : yeni kolon + araya dikey ayraç çizgisi
;   MENU_COL_NL  "Break"    : yeni kolon, çizgisiz
;
; Kullanımı: bölünecek öğenin Add çağrısına 3. argüman olarak ver —
;   menu.Add("Yeni kolonun ilk öğesi", cb, MENU_COL)
; Alt menülerde de çalışır. Kolon başına satır sayısını Windows değil sen
; belirlersin; ekrana sığmayan kolon yine kaydırma oku alır.
global MENU_COL := "BarBreak"
global MENU_COL_NL := "Break"

; ── Menü ikonları ──────────────────────────────────────────────────────
; Numara = 1-TABANLI ikon sırası (SetIcon sayımı).
; İKONLU ÖĞEYE Check() VERME: onay işareti ikonun oluğuna çiziliyor, çakışır.
global ICO_SHELL := A_WinDir "\System32\shell32.dll"
global ICO_RES := A_WinDir "\System32\imageres.dll"

; İkon yoksa/DLL değişmişse menü yine açılmalı — bu yüzden try.
menuIcon(targetMenu, itemName, file, iconNum) {
    try targetMenu.SetIcon(itemName, file, iconNum, 16)
}

; ── Kalın öğe (Win32 "default item") ───────────────────────────────────
; Menüde kalın öğe TEKTİR; adaylar sıralı, küçük sayı kazanır:
;   1 sabitlenmiş aktif pencere   2 profilsiz pencerede "Ekle"   3 boş "Add"
global MENU_DEF_NONE := 99
global menuDefRank := MENU_DEF_NONE

setMenuDefault(targetMenu, itemName, rank) {
    global menuDefRank
    if (rank >= menuDefRank)
        return
    menuDefRank := rank
    try targetMenu.Default := itemName
}

showF13menu() {
    Click("Middle", 1)
    State.window.update()

    global menuDefRank               ; v2 assume-local: bildirmezsek yerel değişken açar
    menuDefRank := MENU_DEF_NONE     ; her menü kendi kalın öğesini yeniden seçer
    menuF13 := Menu()
    ; mySwitchMenu.Add("Active Class: " WinGetClass("A"), (*) => (A_Clipboard := WinGetClass("A"), ToolTip("Copied: "), SetTimer(() => ToolTip(), -2000)))


    ; ── 1. KOLON: pano · ekran görüntüsü · OCR ──────────────────────
    menuF13.Add("Clipboard history", App.ClipHist.buildHistoryMenu())
    menuF13.Add("Clipboard history win", (*) => SetTimer(() => Send("#v"), -20))
    menuIcon(menuF13, "Clipboard history win", ICO_RES, 243)        ; panodan pencereye
    menuF13.Add()
    menuF13.Add("Select screenshot", (*) => Send("{LWin down}{Shift down}s{Shift up}{LWin up}"))
    menuIcon(menuF13, "Select screenshot", ICO_SHELL, 260)          ; makas (kırpma)
    menuF13.Add("Window screenshot", (*) => Send("!{PrintScreen}"))
    menuIcon(menuF13, "Window screenshot", ICO_SHELL, 196)          ; fotoğraf makinesi
    menuF13.Add("Select text with OCR", (*) => Send("{LWin down}{Shift down}t{Shift up}{LWin up}"))
    menuF13.Add("OCR Gelismis", (*) => App.ScreenOcr.snipInteractive())
    menuF13.Add("OCR Basit", (*) => App.ScreenOcr.snip("plain"))
    menuF13.Add()
    menuF13.Add("Clipboard images", (*) => App.ClipImageDlg.show())
    menuIcon(menuF13, "Clipboard images", ICO_RES, 109)             ; görsel

    ; ── 2. KOLON: aktif pencere profili · araçlar · hep üstte ───────
    ; Kolon ayracını MENU_COL çiziyor; bu yüzden 1. kolonun sonunda
    ; ayrıca menuF13.Add() ayracı YOK — olsaydı kolon dibinde boşta
    ; asılı bir yatay çizgi kalırdı.
    menuAppProfile(menuF13, MENU_COL)
    menuF13.Add()
    menuF13.Add("Repository GUI", (*) => App.Repo.showGui())
    ; Durum metinde: ikonlu öğede Check() ikonla çakışıyor.
    local incoLabel := App.Incognito.isActive() ? "Incognito modu — AÇIK" : "Incognito modu"
    menuF13.Add(incoLabel, (*) => App.Incognito.toggle())
    menuIcon(menuF13, incoLabel, ICO_SHELL, App.Incognito.isActive() ? 48 : 45)   ; kilit / anahtar
    menuF13.Add()
    menuAlwaysOnTop(menuF13)

    State.Busy.setFree()
    menuF13.Show()
}

showF14menu() {
    Click("Middle", 1)

    subKeyMenu := Menu()
    subKeyMenu.Add("⏎ Enter (Right to left)", (*) => Send("{Enter}"))
    subKeyMenu.Add("⌫ Backspace", (*) => Send("{Backspace}"))
    subKeyMenu.Add("⌦ Delete", (*) => SendInput("{Delete}"))
    subKeyMenu.Add("Select All + Cut", (*) => Send("^a^x"))
    subKeyMenu.Add("⎋ Esc", (*) => Send("{Esc}"))

    menuF14 := Menu()
    menuF14.Add("Unformatted paste", (*) => Send("^+v"))
    menuF14.Add()
    menuF14.Add("Memory clip", (*) => App.MemSlots.start())
    menuIcon(menuF14, "Memory clip", ICO_RES, 30)                   ; bellek çubuğu
    menuF14.Add()
    menuF14.Add("System " . State.Script.getVersion() . (App.ErrHandler.lastFullError == "" ? "" : " (error)"), menuStats())
    menuF14.Add("Special keys", subKeyMenu)

    ; 2. kolon: base grup slotları (eski "Load from slot" alt menüsü yerine)
    menuF14.Add("Search in slots", (*) => App.ClipSlot.showSlotsSearch(), MENU_COL)
    menuF14.Add()
    App.ClipSlot.addSlotItems(menuF14, "")
    menuF14.Add()
    menuF14.Add("Save to ^ slot", App.ClipSlot.buildSaveSlotMenu(""))

    ; 3. kolon: grup seçili olmasa da HEP açılır; kolonu Side slot başlatır.
    local sideName := App.ClipSlot.defaultGroupName
    local sideLabel := "Side slot" . (sideName != "" ? " [" . sideName . "]" : "")
    menuF14.Add(sideLabel, buildSideSlotMenu(), MENU_COL)
    if (sideName != "") {
        menuF14.Add()
        App.ClipSlot.addSlotItems(menuF14, sideName)
        menuF14.Add()
        menuF14.Add("Save to ⇥" . sideName, App.ClipSlot.buildSaveSlotMenu(sideName))
    }

    State.Busy.setFree()
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
        m.Add(name, sub)
        if (App.ClipSlot.defaultGroupName == name)
            try m.Default := name
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

; firstOpt : bu bloğun İLK öğesine verilecek Menu.Add seçeneği. MENU_COL
;            geçilirse blok yeni bir kolondan başlar. Blok boş olamaz —
;            profil yoksa "Ekle" öğesi ilk sırayı alır — yani bayrak hep
;            bir yere düşer, kolon sessizce kaybolmaz.
; colEvery : kaç kısayolda bir yeni kolona geçilsin (0 = hiç bölme).
;            Kısayol sayısı profile göre değişiyor; sabit bir yere kolon
;            koymak yerine sayarak bölmek gerekiyor, yoksa kalabalık bir
;            profil yine ekranı taşırıp kaydırma okuna düşürür.
menuAppProfile(targetMenu, firstOpt := "", colEvery := 20) {
    profile := App.AppShorts.findProfileByWindow()
    className := State.Window.getClass()

    if (profile) {
        for sc in profile.shortCuts {
            ; IIFE şart: closure değişkeni referansla yakalar, tek 'lambda' değişkeni
            ; kullanılınca tüm menü öğeleri SON kısayolu oynatıyordu
            local opt := firstOpt
            firstOpt := ""
            if (colEvery && A_Index > 1 && Mod(A_Index - 1, colEvery) = 0)
                opt := MENU_COL
            targetMenu.Add("▸" . sc.shortCutName . (sc.keyDescription ? " - " sc.keyDescription : ""), ((s) => (*) => s.play())(sc), opt)
        }
        ; Kısayolu olmayan profilde döngü hiç dönmez; bayrak buraya düşer.
        targetMenu.Add("Profili düzenle", (*) => App.AppShorts.showManagerGui(profile), firstOpt)
    } else {
        local addLabel := "▸ Ekle (" className ")"
        targetMenu.Add(addLabel, (*) => App.AppShorts.editProfileForActiveWindow(), firstOpt)
        setMenuDefault(targetMenu, addLabel, 2)
        targetMenu.Add("Profiller", (*) => App.AppShorts.showManagerGui())
    }
}

; firstOpt: bu bloğun İLK öğesine verilecek Menu.Add seçeneği. MENU_COL
; geçilirse blok yeni bir kolondan başlar (bkz. dosya başındaki not).
; Bayrak sonraki öğelere DEĞİL yalnız ilkine gitmeli — hepsine verilirse
; her satır kendi kolonunu açar.
menuAlwaysOnTop(targetMenu, firstOpt := "") {
    title := State.Window.getTitle()
    hwnd := State.Window.getHwnd()

    if (!State.Window.onTopWindows.Has(hwnd)) {
        local addLabel := "📍 Add " . SubStr(title, 1, 60)
        targetMenu.Add(addLabel, (*) => State.Window.toggleAlwaysOnTop(hwnd, title), firstOpt)
        firstOpt := ""
        if (!State.Window.onTopWindows.Count)   ; blok tek satırdan ibaret
            setMenuDefault(targetMenu, addLabel, 3)
    }

    for key, value in State.Window.onTopWindows {
        local pinLabel := "📌 " . value
        targetMenu.Add(pinLabel, ((k, v) => (*) => State.Window.toggleAlwaysOnTop(k, v))(key, value), firstOpt)
        firstOpt := ""
        targetMenu.Check(pinLabel)
        if (key == hwnd)   ; üstünde durduğun pencere zaten sabitlenmiş
            setMenuDefault(targetMenu, pinLabel, 1)
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
        local byteCount := StrPut(msg, "UTF-8") - 1
        msg := byteCount " B ➡️" . SubStr(msg, 1, 5000) . "`n[..................]"
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