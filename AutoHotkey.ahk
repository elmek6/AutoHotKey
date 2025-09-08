#Requires AutoHotkey v2.0
#SingleInstance Force
; Ctrl^ RCtrl>^ Alt! Win# Shift+ RShift>+
#Include <Jxon> ;Lib klasörünün icindeyse böyle yaziliyor
#Include <script_state>
#Include <key_counter>
#Include <error_handler>
#Include <clip_handler>
#Include <hotkey_handler>
; #Include <array_filter>

global state := ScriptState.getInstance("ver_b121")
global keyCounts := KeyCounter.getInstance()
global errHandler := ErrorHandler.getInstance()
global clipManager := ClipboardManager.getInstance(20, 100000)
global keyHandler := HotkeyHandler.getInstance()
global scriptStartTime := A_Now

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

#SuspendExempt ;suspend durumunda calisacak kodlar
Pause & Home:: {
    DialogPauseGui()
}
Pause & End:: {
    reloadScript()
}
#SuspendExempt False

DialogPauseGui() {
    Suspend(1) ;Scripti durdur

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

;^::^ ;caret tuss halen islevsel SC029  vkC0
CapsLock:: keyHandler.handleCapsLock()
SC029:: keyHandler.handleCaret()

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

;Slota saklamak icin
Tab & 1:: clipManager.saveToSlot(1)
Tab & 2:: clipManager.saveToSlot(2)
Tab & 3:: clipManager.saveToSlot(3)
Tab & 4:: clipManager.saveToSlot(4)
Tab & 5:: clipManager.saveToSlot(5)
Tab & 6:: clipManager.saveToSlot(6)
Tab & 7:: clipManager.saveToSlot(7)
Tab & 8:: clipManager.saveToSlot(8)
Tab & 9:: clipManager.saveToSlot(9)

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
    mySwitchMenu.Show()
}

showF14menu() {
    mySwitchMenu := Menu()
    mySwitchMenu.Add("Paste enter", (*) => clipManager.press("^v{Enter}"))
    mySwitchMenu.Add("Cut", (*) => clipManager.press("^x"))
    mySwitchMenu.Add("Select All + Cut", (*) => clipManager.press("^a^x"))
    mySwitchMenu.Add("Unformatted paste", (*) => clipManager.press("^+v"))
    mySwitchMenu.Add()

    mySwitchMenu.Add("Load clip", clipManager.buildSlotMenu())
    mySwitchMenu.Add("Save clip", clipManager.buildSaveSlotMenu())

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

´:: {
    actions := Map(
        "1", { dsc: "Reload", fn: (*) => reloadScript() },
        "2", { dsc: "Show stats", fn: (*) => ShowStats(true) },
        "3", { dsc: "", fn: (*) => Sleep(10) },
        "4", { dsc: "Show KeyHistoryLoop", fn: (*) => ShowKeyHistoryLoop() },
        "5", { dsc: "Awake ...", fn: (*) => InputAwake() },
        "7", { dsc: "F13 menü", fn: (*) => showF13menu() },
        "8", { dsc: "F14 menü", fn: (*) => showF14menu() },
        "9", { dsc: "Pause script", fn: (*) => DialogPauseGui() },
        "a", { dsc: "TrayTip", fn: (*) => TrayTip("Başlık", "Mesaj içeriği", 1) }
    )

    menu := "Commands (Esc:exit)`n"
    for k, v in actions
        menu .= k ": " v.dsc "`n"
    ToolTip(menu)

    ih := InputHook("L1 T30", "{Esc}")
    ih.Start(), ih.Wait()
    key := ih.Input != "" ? ih.Input : ih.EndKey
    ToolTip()

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

^!+#Space:: Send("+{F10}")
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

#HotIf state.getBusy() > 0 ; combo tusu supress ediyoruz
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