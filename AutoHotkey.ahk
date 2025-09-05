#Requires AutoHotkey v2.0
; Ctrl^ RCtrl>^ Alt! Win# Shift+ RShift>+

#SingleInstance Force
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
global keyHandler := HotkeyHandler.getInstance() ;GROK_AI: Parametreler kaldırıldı
global scriptStartTime := A_Now
global pauseGui := "" ; Global GUI değişkeni

class AppConst { ;GROK_AI: Const yerine AppConst kullanıldı, çakışmayı önlemek için
    static FILES_DIR := "Files\"
    static FILE_CLIPBOARD := "Files\clipboards.json"
    static FILE_LOG := "Files\log.txt"
}

CoordMode("Mouse", "Screen")
OnExit HandleExit
HandleExit(ExitReason, ExitCode) {
    state.saveStats(scriptStartTime)
    clipManager.__Delete()
    if (pauseGui != "") {
        pauseGui.Destroy() ; Çıkışta GUI'yi temizle
    }
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
    CreatePauseGui()
}
Pause & End:: {
    reloadScript()
}
#SuspendExempt False

CreatePauseGui() {
    global pauseGui
    pauseGui := Gui("-MinimizeBox -MaximizeBox +AlwaysOnTop", "Script Durduruldu")
    pauseGui.Add("Button", "w200 h40", "Play Script").OnEvent("Click", ResumeScript)
    pauseGui.Show("xCenter yCenter")
    Suspend(1)
    SoundBeep(1000)
}

ResumeScript(*) {
    global pauseGui
    pauseGui.Destroy() ; Düğmeyi kaldır
    pauseGui := ""
    Suspend(0) ; Script'i devam ettir
    SoundBeep(1000)
}

;^::^ ;tus halen islevsel SC029  vkC0

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


; ^ & PgDn::ShowStats()
ShowStats() {
    stats := "Busy status: " state.getBusy() "`n"

    for key, count in keyCounts.getAll() {
        stats .= key ": " count "`n"
    }

    recentErrors := errHandler.getRecentErrors(10) ;0 for all
    if (recentErrors == "") {
        stats .= "no new error (log.txt save all)"
    } else {
        stats .= recentErrors
    }
    sinceDateTime := FormatTime(scriptStartTime, "yyyy-MM-dd HH:mm:ss")
    MsgBox(stats, state.getVersion() " - Stats and errors " sinceDateTime)
}

^ & Del:: DisableLog()
DisableLog() {
    choice := MsgBox("Disable Logging in this session YES?", "New error click NO", "YesNoCancel")
    if (choice = "No") {
        errHandler.testError("Test")
    } else if (choice = "Yes") {
        state.setDisableLogging(true)
    }
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
Tab & 6:: clipManager.saveToSlot(7)
Tab & 6:: clipManager.saveToSlot(6)
Tab & 6:: clipManager.saveToSlot(9)


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
    settingsMenu.Add("Disable Log", (*) => DisableLog())
    settingsMenu.Add("Show KeyHistoryLoop", (*) => ShowKeyHistoryLoop())
    settingsMenu.Add("Show Stats : " state.getVersion(), (*) => ShowStats())
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

#HotIf (A_PriorKey != "" && A_TimeSincePriorHotkey != "" && A_TimeSincePriorHotkey < 60)
LButton:: {
    keyCounts.inc("DoubleCount")
    errHandler.handleError("double click: " A_TimeSincePriorHotkey)
    Return
}
#HotIf
#HotIf state.getBusy() > 0
*1:: return
*2:: return
*3:: return
*4:: return
*5:: return
*6:: return
*7:: return
*8:: return
*9:: return
*q:: return
*RButton:: return
#HotIf


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

´:: { ;´= VKDD  SC00D
    ToolTip("
    (
    1: Reload
    2: Show stats
    3: Disable log
    4: Show KeyHistoryLoop
    5: Awake ...
    9: Pause script
    Esc to exit
    )")
    ih := InputHook("L1", "{Esc}")
    ih.Start()
    ih.Wait()

    key := ih.Input != "" ? ih.Input : ih.EndKey
    ToolTip()
    Switch key {
        ; Case "´": Send(key)         Case "`n": Send("{sc00D}")
        Case "1": reloadScript()
        Case "2": ShowStats()
        case "3": DisableLog()
        case "4": ShowKeyHistoryLoop()
        case "5": InputAwake()
        case "9": CreatePauseGui()
        Case "a": TrayTip("Başlık", "Mesaj içeriği", 1)
        Default: SoundBeep(800) ; Default: MsgBox ("pressed scan value " key)
    }
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