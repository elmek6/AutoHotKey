#Requires AutoHotkey >= 2.1-alpha.18
#SingleInstance Force
; Ctrl^ RCtrl>^ Alt! Win# Shift+ RShift>+
; SC kodu 1 key, VK ve tus cok kez okunuyor ??
#Include <jsongo.v2>
#Include <error_handler>
#Include <script_state>
#Include <menus>
#Include <key_counter>
#Include <hotkey_handler>
#Include <clip_handler>
#Include <memory_slots>
#Include <cascade_menu>
#Include <macro_recorder>
#Include <app_shorts>
; #Include <array_filter>

; https://github.com/ahkscript/awesome-AutoHotkey

global state := ScriptState.getInstance("ver_133_b")
global keyCounts := KeyCounter.getInstance()
global errHandler := ErrorHandler.getInstance()
global clipManager := ClipboardManager.getInstance(200, 30000)
global keyHandler := HotkeyHandler.getInstance()
global cascade := CascadeMenu.getInstance()
global recorder := MacroRecorder.getInstance(300)
global appShorts := ProfileManager.getInstance()
global memSlots := MemorySlotsManager.getInstance()

global scriptStartTime := A_Now
global stateConfig := { none: 0, home: 1, work: 2 }
global currentConfig := stateConfig.none


CoordMode("Mouse", "Screen")
TraySetIcon("arrow.ico")
A_TrayMenu.Add("SCRIPT...", (*) => DialogPauseGui())
A_TrayMenu.Add("EXIT", (*) => ExitApp())
class AppConst {
    static FILES_DIR := "Files\"
    static FILE_CLIPBOARD := "Files\clipboards.json"
    static FILE_LOG := "Files\log.txt"
    static FILE_PROFILE := "Files\profiles.json"
    static FILE_POS := "Files\positions.json"
    static initDirectory() {
        if !DirExist(AppConst.FILES_DIR) {
            DirCreate(AppConst.FILES_DIR)
        }
        ; FileAppend(FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss") " - Resumed recording`n", AppConst.FILES_DIR "debug.log")
    }
}

#SuspendExempt
Pause & Home:: {
    ; DialogPauseGui()
    reloadScript()
}
Pause & End:: {
    ExitApp()
}
#SuspendExempt False

LoadSettings()
OnExit ExitSettings

;-------------------------------------------------------------------

LoadSettings() {
    OutputDebug "Script " state.getVersion() " started... " FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss") "`n"
    state.loadStats()
    if (A_ComputerName = "LAPTOP-UTN6L5PA") { ;work
        SetTimer(checkIdle, 1000)
        ;MsgBox(A_ComputerName, A_UserName) ; LAPTOP-UTN6L5PA
        ToolTip("Bus timer kuruldu")
        SetTimer(() => ToolTip(), -1000)
        global currentConfig := stateConfig.work
    } else {
        TrayTip("AHK", "Home profile", 1)
        global currentConfig := stateConfig.home
    }
    AppConst.initDirectory()
}

ExitSettings(ExitReason, ExitCode) {
    state.saveStats(scriptStartTime)
    clipManager.__Delete()
    state.clearAllOnTopWindows()
}

reloadScript() {
    state.saveStats(scriptStartTime)
    SoundBeep(500)
    Reload
}

;-------------------------------------------------------------------

#HotIf (A_PriorKey != "" && A_TimeSincePriorHotkey != "" && A_TimeSincePriorHotkey < 70)
LButton:: {
    keyCounts.inc("DoubleCount")
    errHandler.handleError("double click: " A_TimeSincePriorHotkey)
    SoundBeep(1000, 100)
    Return
}
#HotIf

#HotIf state.getBusy() > 1 ; combo tuşu suppress ediyoruz *önünde modifier tusu var demek
*1:: return
*2:: return
*3:: return
*4:: return
*5:: return
*6:: return
*7:: return
*8:: return
*9:: return
*0:: return
*s:: return
; *RButton:: return
#HotIf

; Pause & 1:: recorder.recordAction(1, MacroRecorder.recType.key)
; Pause & 2:: recorder.stop()  ; Kayıt durdur
; Pause & 3:: recorder.playKeyAction(1, 1)  ; rec1.ahk’yı 1 kez oynat

#HotIf currentConfig = stateConfig.work ; hotif olan tuslari override eder
>#1:: recorder.playKeyAction(1, 1) ;orta basinca kayit //uzun basinca run n olabilir
>#2:: recorder.playKeyAction(2, 1)
>#3:: getPressType( ;belki önüne birsey gelince olabilir?
    (pressType) => pressType == 0
        ? recorder.playKeyAction(3, 1)
        : recorder.recordAction(3, MacroRecorder.recType.key)
)
#HotIf

#HotIf currentConfig = stateConfig.home
SC132:: recorder.playKeyAction(1, 1) ;orta basinca kayit //uzun basinca run n olabilir
SC16C:: recorder.playKeyAction(2, 1)
#HotIf

;Fare tuslari haritasi
F13:: keyHandler.handleF13()
F14:: keyHandler.handleF14()
F15:: keyHandler.handleF15()
F16:: keyHandler.handleF16()
F17:: keyHandler.handleF17()
F18:: keyHandler.handleF18()
F19:: keyHandler.handleF19()
F20:: keyHandler.handleF20()

;^::^ ;caret tuşu halen işlevsel SC029  vkC0

SC029:: cascade.cascadeCaret() ; Caret VKDC SC029  ^ != ^
SC00F:: cascade.cascadeTab()   ; Tab VK09 SC00F  (for not kill  Tab::Tab)
SC001:: cascade.cascadeEsc() ; Esc SC001 VK1B
SC00D:: hookCommands() ; ´ backtick SC00D VKDD
; SC03A:: cascade.cascadeCaps()  ; CapsLock:: keyHandler.handleCapsLock()

~LButton:: keyHandler.handleLButton()
~MButton:: keyHandler.handleMButton()
~RButton:: keyCounts.inc("RButton")
;~LButton & RButton::RButton & LButton:: {}
~MButton & WheelUp:: {
    if (state.getLastWheelTime())
        Send("#{NumpadAdd}")
}
~MButton & WheelDown:: {
    if (state.getLastWheelTime())
        Send("#{NumpadSub}")
}

RButton & WheelUp:: {
    state.setRightClickActive(true)
    if (state.getLastWheelTime()) {
        Send("{Volume_Up}")
    }
}
RButton & WheelDown:: {
    state.setRightClickActive(true)
    if (state.getLastWheelTime()) {
        Send("{Volume_Down}")
    }
}

~RButton Up:: {
    if (state.getRightClickActive()) {
        Sleep 50
        Send ("{ESC}")
        state.setRightClickActive(false)
    }
}

Pause & Space:: ShowKeyHistoryLoop()
ShowKeyHistoryLoop() {
    KeyHistory (24)
    Loop {
        KeyHistory
        Sleep 100
        if GetKeyState("Escape", "P") {
            Return
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

;home
NumpadIns & NumpadDel:: Send("!{Tab}")
NumpadDel & NumpadIns:: Send("!+{Tab}")
NumpadIns:: Send("J")
NumpadDel:: Send("L")
NumpadClear:: Send("K")

^!+#Space:: return OutputDebug(":-)") ; Send("+{F10}") ;work suppreme edilemiyor (#hotif de olmadı)
^<:: SendInput ("^+k") ;satir sil vscode
!v:: {
    SetKeyDelay (520, 560)
    SendText (A_Clipboard)
}

AppsKey:: { ;work
    id := []
    id := WinGetList("ahk_class MozillaWindowClass")
    for index, this_id in id {
        title := WinGetTitle("ahk_id " this_id)
        if InStr(title, "Hekim") {
            WinMinimize("ahk_id " this_id)
        }
    }
}


;Pause:: { SendInput("{vk5B down}v("{vk5B up}")}

; ScrollLock:: { ;test
;     global ScrollState := GetKeyState("ScrollLock", "T")
;     ToolTip(ScrollState ? "NumLock ON" : "NumLock OFF")
;     SetTimer(() => ToolTip(), -800)
;     Send "{ScrollLock}"
; }

; ß # #1 #2 #3 #F1 #F2 ^F1
; esc & 1 esc & 2
; esc & f1 esc & f2
; ß:: detectPressType((pressType) =>
;     OutputDebug("Press type: " pressType "`n")
; )
