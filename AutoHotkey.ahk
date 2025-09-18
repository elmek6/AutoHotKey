; #Requires AutoHotkey v2.0
#Requires AutoHotkey >= 2.1-alpha.10
#SingleInstance Force
; Ctrl^ RCtrl>^ Alt! Win# Shift+ RShift>+
; SC kodu 1 key, VK ve tus cok kez okunuyor ??
#Include <Jxon> ;Lib klasörünün icindeyse böyle yaziliyor
#Include <script_state>
#Include <key_counter>
#Include <error_handler>
#Include <clip_handler>
#Include <hotkey_handler>
#Include <macro_recorder>
#Include <cascade_menu>
; #Include <array_filter>

; https://github.com/ahkscript/awesome-AutoHotkey

; FileAppend(FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss") " - Resumed recording`n", AppConst.FILES_DIR "debug.log")
TraySetIcon("shell32.dll", 300) ; 177

OutputDebug "Started... " FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss") "`n"
global state := ScriptState.getInstance("ver_h122")
global keyCounts := KeyCounter.getInstance()
global errHandler := ErrorHandler.getInstance()
global clipManager := ClipboardManager.getInstance(20, 100000)
global keyHandler := HotkeyHandler.getInstance()
global cascade := CascadeMenu.getInstance()
global recorder := MacroRecorder.getInstance(300)
global scriptStartTime := A_Now
global RelativeX := 0, RelativeY := 0  ; Macro recorder için global
; global appProfil = auto;

; Örnek: Dinamik ayar değiştirme
; recorder.settings := ["rec2.ahk", "F2", "keyboard", 600]  ; İstersen böyle çağır


class AppConst {
    static FILES_DIR := "Files\"
    static FILE_CLIPBOARD := "Files\clipboards.json"
    static FILE_LOG := "Files\log.txt"
}

CoordMode("Mouse", "Screen")
OnExit HandleExit
HandleExit(ExitReason, ExitCode) {
    state.saveStats(scriptStartTime)
    clipManager.__Delete()
}

state.loadStats()
LoadPCSettings()
LoadPCSettings() {
    if (A_ComputerName = "LAPTOP-UTN6L5PA") { ;bus
        SetTimer(checkIdle, 1000)
        ;MsgBox(A_ComputerName, A_UserName) ; LAPTOP-UTN6L5PA
        ToolTip("Bus timer kuruldu")
        SetTimer(() => ToolTip(), -1000)
    } else {
        ; ToolTip("Home")
        ; SetTimer(() => ToolTip(), -1000)
        TrayTip("AHK", "Home profile", 1)
    }
}

#SuspendExempt
Pause & Home:: {
    DialogPauseGui()
}
Pause & End:: {
    reloadScript()
}
#SuspendExempt False

A_TrayMenu.Add("Ayarlar", (*) => MsgBox("Ayarlar açıldı"))
A_TrayMenu.Add("Çıkış", (*) => ExitApp())


Pause & 1:: recorder.recordAction(1, MacroRecorder.recType.key)
Pause & 2:: recorder.stop()  ; Kayıt durdur
Pause & 3:: recorder.playKeyAction(1, 1)  ; rec1.ahk’yı 1 kez oynat


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


;^::^ ;caret tuşu halen işlevsel SC029  vkC0
CapsLock:: keyHandler.handleCapsLock()
; SC029:: keyHandler.handleCaret() ;caret SC029  ^ != ^
SC029::  ;caret VKDC SC029  ^ != ^
{
    startTime := A_TickCount
    KeyWait A_ThisHotkey
    if (A_TickCount - startTime < 500) {
        ; nothing
    } else {
        SoundBeep(900, 100)
        Send("{^}")
        return
    }


    loadSave(number) {
        if (pressedTogether) {
            clipManager.loadFromSlot(number)
        } else {
            clipManager.saveToSlot(number)
        }
    }

    actions := Map(
        "1", { dsc: "Load Slot 1", fn: (*) => loadSave(1) },
        "2", { dsc: "Load Slot 2", fn: (*) => loadSave(2) },
        "3", { dsc: "Load Slot 3", fn: (*) => loadSave(3) },
        "4", { dsc: "Load Slot 4", fn: (*) => loadSave(4) },
        "5", { dsc: "Load Slot 5", fn: (*) => loadSave(5) },
        "7", { dsc: "Load Slot 7", fn: (*) => loadSave(7) },
        "8", { dsc: "Load Slot 8", fn: (*) => loadSave(8) },
        "9", { dsc: "Load Slot 9", fn: (*) => loadSave(9) },
        "0", { dsc: "Load Slot 0", fn: (*) => loadSave(0) },
        "s", { dsc: "Search", fn: (*) => clipManager.showSlotsSearch() },
        "VKDC", { dsc: "^", fn: (*) => SendInput("Ö") },
    )

    local list := []
    list := "Clipboard Slots`n"
    list .= "s search `n"
    list .= "----------------`n"
    list .= clipManager.getSlotsPreviewText()
    ToolTip(list)

    ih := InputHook("L1 T30", "{Esc}")
    ih.Start(), ih.Wait()
    key := ih.Input != "" ? ih.Input : ih.EndKey
    ToolTip()

    pressedTogether := GetKeyState(A_ThisHotkey, "P")

    if actions.Has(key)
        actions[key].fn()

}


;Slota saklamak için (rakam suppress ile sindiliriliyor yan menüye alinabilir)
; 1 & SC029:: clipManager.saveToSlot(1)
; 2 & SC029:: clipManager.saveToSlot(2)
; 3 & SC029:: clipManager.saveToSlot(3)
; 4 & SC029:: clipManager.saveToSlot(4)
; 5 & SC029:: clipManager.saveToSlot(5)
; 6 & SC029:: clipManager.saveToSlot(6)
; 7 & SC029:: clipManager.saveToSlot(7)
; 8 & SC029:: clipManager.saveToSlot(8)
; 9 & SC029:: clipManager.saveToSlot(9)


; 1:: keyHandler.handleNums(1) ;command menünün calismasina engel oluyor
; 2:: keyHandler.handleNums(2)
; 3:: keyHandler.handleNums(3)
; 4:: keyHandler.handleNums(4)
; 5:: keyHandler.handleNums(5)
; 6:: keyHandler.handleNums(6)
; 7:: keyHandler.handleNums(7)
; 8:: keyHandler.handleNums(8)
; 9:: keyHandler.handleNums(9)

reloadScript() {
    state.saveStats(scriptStartTime)
    SoundBeep(500)
    Reload
}

^ & PgUp:: ShowKeyHistoryLoop()
ShowKeyHistoryLoop() {
    Loop {
        KeyHistory
        Sleep 100  ; Gözlemlenen olayları güncellemek için kısa bir bekleme
        if GetKeyState("Escape", "P") {
            Return
        }
    }
}

ShowStats(showMsgBox := false) {
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

Tab::Tab

~LButton:: keyHandler.handleLButton()
~MButton:: keyHandler.handleMButton()
~RButton:: keyCounts.inc("RButton")

;~LButton & RButton::RButton & LButton:: {}

~MButton & WheelUp:: Send("#{NumpadAdd}")
~MButton & WheelDown:: Send("#{NumpadSub}")

; ##### (4) Ses İşlemleri
RButton & WheelUp:: {
    state.setRightClickActive(true)
    Send("{Volume_Up}")
}
RButton & WheelDown:: {
    state.setRightClickActive(true)
    Send("{Volume_Down}")
}
~RButton Up:: {
    if (state.getRightClickActive()) {
        Sleep 50
        ;Send ("{ESC}")
        PostMessage(0x001F, 0, 0, , "A")     ;context i kapaiyor
        state.setRightClickActive(false)
    }
}

;Makro oynatma
; Tab & 1:: clipManager.saveToSlot(1)
; Tab & 2:: clipManager.saveToSlot(2)
; Tab & 3:: clipManager.saveToSlot(3)
; Tab & 4:: clipManager.saveToSlot(4)
; Tab & 5:: clipManager.saveToSlot(5)
; Tab & 6:: clipManager.saveToSlot(6)
; Tab & 7:: clipManager.saveToSlot(7)
; Tab & 8:: clipManager.saveToSlot(8)
; Tab & 9:: clipManager.saveToSlot(9)
;Makro kaydetme
; 1 & Tab:: clipManager.saveToSlot(9)


showF13menu() {
    mySwitchMenu := Menu()
    mySwitchMenu.Add("⏎ Enter (Right to left)", (*) => Send("{Enter}"))
    mySwitchMenu.Add("⌫ Backspace", (*) => Send("{Backspace}"))
    mySwitchMenu.Add("⌦ Delete", (*) => SendInput("{Delete}"))
    mySwitchMenu.Add("␣ Space", (*) => Send("{Space}"))
    mySwitchMenu.Add("⎋ Esc", (*) => Send("{Esc}"))
    mySwitchMenu.Add("⇱ Home", (*) => Send("{Home}"))
    mySwitchMenu.Add("␣ Space", (*) => Send("{Space}"))
    mySwitchMenu.Add("⇲ End", (*) => Send("{End}"))
    mySwitchMenu.Add()
    mySwitchMenu.Add("Select screenshot", (*) => Send("{LWin down}{Shift down}s{Shift up}{LWin up}"))
    mySwitchMenu.Add("Window screenshot", (*) => Send("!{PrintScreen}"))
    mySwitchMenu.Add("Delete line", (*) => Send("{Home}{Home}+{End}{Delete}{Delete}"))
    mySwitchMenu.Add("Find 'clipboard'", (*) => clipManager.press(["^f", "{Sleep 100}", "^a^v"]))
    mySwitchMenu.Add("Always on top'", (*) => AlwaysOnTop())
    mySwitchMenu.Show()
}

showF14menu() {
    mySwitchMenu := Menu()
    mySwitchMenu.Add("Paste enter", (*) => clipManager.press("^v{Enter}"))
    mySwitchMenu.Add("Cut", (*) => clipManager.press("^x"))
    mySwitchMenu.Add("Select All + Cut", (*) => clipManager.press("^a^x"))
    mySwitchMenu.Add("Unformatted paste", (*) => clipManager.press("^+v"))
    mySwitchMenu.Add()

    ;belki tüm slotlar listelenip her birinin alt menüsü olarak load, save, rename, clear gelebiliri
    mySwitchMenu.Add("Load clip", clipManager.buildSlotMenu())
    mySwitchMenu.Add("Save clip", clipManager.buildSaveSlotMenu())
    mySwitchMenu.Add("Rename slot", clipManager.buildRenameSlotMenu())

    historyMenu := clipManager.buildHistoryMenu()
    mySwitchMenu.Add("Clipboard history", historyMenu)
    mySwitchMenu.Add()

    settingsMenu := Menu()
    settingsMenu.Add("Reload", (*) => reloadScript())
    settingsMenu.Add("Pause script", (*) => DialogPauseGui())
    settingsMenu.Add("Show KeyHistoryLoop", (*) => ShowKeyHistoryLoop())

    statsMenu := Menu()
    statsMenu.Add("Show stats", (*) => (ShowStats(true)))
    statsMenu.Add()
    statsArray := ShowStats()
    for stat in statsArray {
        statsMenu.Add(stat, (*) => (A_Clipboard := stat))
    }
    statsMenu.Add()
    latestError := ""
    for timestamp, message in errHandler.getAllErrors() {
        latestError := FormatTime(timestamp, "dd HH:mm:ss") ": " message
    }
    statsMenu.Add("Copy last error", (*) => (A_Clipboard := latestError))
    settingsMenu.Add("Show Stats", statsMenu)

    settingsMenu.Add("Awake ...", (*) => InputAwake())
    mySwitchMenu.Add("Settings", settingsMenu)

    mySwitchMenu.Show()
}

InputAwake() {
    ;buraya awakei iptal et yazabilir
    input := InputBox("Dakika gir:", "Uyku Engelle")
    if (input.result = "OK") {
        mins := input.value * 60000
        if (mins is integer && mins > 0) {
            DllCall("SetThreadExecutionState", "UInt", 0x80000002)
            SetTimer(ResetSleep, -mins)
        } else {
            MsgBox("Geçersiz değer")
        }
    }
}

#a:: MouseMove(-10, 0, 0, "R")
#s:: MouseMove(0, 10, 0, "R")
#d:: MouseMove(10, 0, 0, "R")
#w:: MouseMove(0, -10, 0, "R")
#q:: Click("Left")
#e:: Click("Right")
#y:: Send("{Enter}")

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

ResetSleep(*) {
    DllCall("SetThreadExecutionState", "UInt", 0x80000000) ; varsayılan
    ; 1 saat dolunca yeniden idle takibine başla
    SetTimer(CheckIdle, 1000)
}

AlwaysOnTop() {
    activeWindow := WinGetTitle("A")
    try {
        WinSetAlwaysOnTop -1, activeWindow
        ToolTip "Switched 'Always-On-Top' state:`n" activeWindow
        SetTimer () => ToolTip(), -2000
    } catch Error as err {
        ToolTip "Unable to set 'Always-On-Top' state:`n" err.Message
        SetTimer () => ToolTip(), -2000
    }
}


SC00D:: {    ; backtick ´ SC00D VKDD
    actions := Map(
        "1", { dsc: "Reload", fn: (*) => reloadScript() },
        "2", { dsc: "Show stats", fn: (*) => ShowStats(true) },
        "3", { dsc: "", fn: (*) => Sleep(10) },
        "4", { dsc: "Show KeyHistoryLoop", fn: (*) => ShowKeyHistoryLoop() },
        "5", { dsc: "Awake ...", fn: (*) => InputAwake() },
        "6", { dsc: "Makro...", fn: (*) => recorder.showButtons() },
        "7", { dsc: "F13 menü", fn: (*) => showF13menu() },
        "8", { dsc: "F14 menü", fn: (*) => showF14menu() },
        "9", { dsc: "Pause script", fn: (*) => DialogPauseGui() },
        "a", { dsc: "TrayTip", fn: (*) => TrayTip("Başlık", "Mesaj içeriği", 1) }
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

SC121:: { ;home pc?
    Run "calc.exe"
    WinWait "Calculator"
    WinActivate
}

AppsKey:: { ;bus hom ?
    id := []
    id := WinGetList("ahk_class MozillaWindowClass")
    for index, this_id in id {
        title := WinGetTitle("ahk_id " this_id)
        if InStr(title, "Hekimo") {
            WinMinimize("ahk_id " this_id)
        }
    }
}

^!+#Space:: Send("+{F10}") ;    SendInput("{AppsKey}") suppreme edilmiyor windows engelleiyor

;{ ; bus gülen adam tusu ;    MsgBox(A_ComputerName, A_UserName) ; LAPTOP-UTN6L5PA }

;Pause:: { SendInput("{vk5B down}v("{vk5B up}")}
ScrollLock:: { ;test
    global ScrollState := GetKeyState("ScrollLock", "T")
    ToolTip(ScrollState ? "NumLock ON" : "NumLock OFF")
    SetTimer(() => ToolTip(), -800)
    Send "{ScrollLock}"
}

;hom
NumpadIns & NumpadDel:: Send("!{Tab}")
NumpadDel & NumpadIns:: Send("!+{Tab}")
NumpadIns:: Send("J")
NumpadDel:: Send("L")
NumpadClear:: Send("K")

F13:: keyHandler.handleF13()
F14:: keyHandler.handleF14()
F15:: keyHandler.handleF15()
F16:: keyHandler.handleF16()
F17:: keyHandler.handleF17()
F18:: keyHandler.handleF18()
F19:: keyHandler.handleF19()
F20:: keyHandler.handleF20()

#HotIf (A_PriorKey != "" && A_TimeSincePriorHotkey != "" && A_TimeSincePriorHotkey < 70)
LButton:: {
    keyCounts.inc("DoubleCount")
    errHandler.handleError("double click: " A_TimeSincePriorHotkey)
    SoundBeep(1000, 100)
    Return
}
#HotIf

#HotIf state.getBusy() > 0 ; combo tuşu suppress ediyoruz
*1:: return
*2:: return
*3:: return
*4:: return
*5:: return
*6:: return
*7:: return
*8:: return
*9:: return
; *RButton:: return
#HotIf
/*
#::  ; Windows + # scancode değil direkt #
{
    startTime := A_TickCount

    ih := InputHook("L1 T5", "{Esc}") ; 5 saniye boyunca 1 tuş bekler
    ih.Start(), ih.Wait()
    key := ih.Input != "" ? ih.Input : ih.EndKey

    pressedTogether := GetKeyState(A_ThisHotkey, "P")
    holdDuration := A_TickCount - startTime

    ; --- 1 & 2: kısa/uzun basma bilgisi ---
    if (holdDuration < 300)
        OutputDebug "SHORT press (" holdDuration " ms)`n"
    else
        OutputDebug "LONG press (" holdDuration " ms)`n"

    ; --- 3: basılıyken başka tuşa basma ---
    if (pressedTogether && key != "")
        OutputDebug "Pressed together with key: " key "`n"

    ; --- 4: bırakıp sonra başka tuşa basma ---
    if (!pressedTogether && key != "")
        OutputDebug "Pressed after release: " key "`n"
}
*/
/*
#:: {
    startTime := A_TickCount
    KeyWait A_ThisHotkey ; # tuşu bırakılana kadar bekler
    holdDuration := A_TickCount - startTime

    if (holdDuration < 300) {
        OutputDebug "SHORT press (" holdDuration " ms)`n"
    } else {
        OutputDebug "LONG press (" holdDuration " ms)`n"
        return
    }

    ; Şimdi diğer tuşu bekleyelim (basılıyken veya bırakıldıktan sonra)
    ih := InputHook("L1 T5", "{Esc}")
    ih.Start(), ih.Wait()
    key := ih.Input != "" ? ih.Input : ih.EndKey

    if (key != "") {
        pressedTogether := GetKeyState(A_ThisHotkey, "P")
        if (pressedTogether)
            OutputDebug "Pressed together with key: " key "`n"
        else
            OutputDebug "Pressed after release: " key "`n"
    }
}
*/

/*
#::
{
    cascade.builder := CascadeBuilder() ;short, long
        .shortPress(()=> ())
        .betweenPress(SoundBeep(1000)) ;
        .longPress(SoundBeep(1000))
        .exitOnPressThreshold(hold.mid) ;long press inpuhook calismasin
        .pairs("1", "aciklama", (holdType) => ())
    cascade.builder.setPreview([])
    cascade.cascadeKey(builder)

}
*/
; ß:: {
;     TapOrHold(
;         () => showX(), ;ToolTip("Short F2"),
;         () => ToolTip("Medium F2"),
;         () => ToolTip("Long F2")
;     )
;     Sleep(1000)
;     ToolTip()
; }


+:: {
    builder := CascadeBuilder(500, 1500)
        .mainKey((ms) => OutputDebug("Ana tuş: " ms "ms"))
        .exitOnPressThreshold(1500)
        .sideKey((ms) => OutputDebug("Yan tuş süresi: " ms "ms"))
        .pairs("1", "Test 1", (ms) => OutputDebug("Slot 1: " ms "ms`n"))
        .pairs("2", "Test 2", (ms) => OutputDebug("Slot 2: " ms " ms`n"))
    builder.setPreview(["1: Slot 1 Yükle/Kaydet", "s: Arama Menüsü"])
    cascade.cascadeKey(builder, A_ThisHotkey)
}