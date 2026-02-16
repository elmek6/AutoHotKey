#Requires AutoHotkey >= 2.1-alpha.18
#SingleInstance Force
; Ctrl^ RCtrl>^ Alt! Win# Shift+ RShift>+
; SC kodu 1 key, VK ve tus cok kez okunuyor ??
#Include <jsongo.v2>
#Include <error_handler>
#Include <script_state>
#Include <menus>
#Include <key_counter>
#Include <clip_hist>
#Include <clip_slot>
#Include <memory_slots>
#Include <key_builder>
#Include <key_handler_cascade>
#Include <key_handler_mouse>
#Include <key_handler_hook>
#Include <macro_recorder>
#Include <app_shorts>
#Include <repository>
#Include <quick_menu>
; #Include <array_filter>

; https://github.com/ahkscript/awesome-AutoHotkey

global State := singleState.getInstance("ver_157_h")
class App {
    static ErrHandler := singleErrorHandler.getInstance()
    static KeyCounts := singleKeyCounter.getInstance()
    static HotMouse := singleHotMouse.getInstance()
    static HotCascade := singleHotCascade.getInstance()
    static HotHook := singleHotHook.getInstance()
    static ClipHist := singleClipHist.getInstance(1000, 2000) ; maxHistory, maxClipSize
    static ClipSlot := singleClipSlot.getInstance()
    static MemSlots := singleMemorySlot.getInstance()
    static Recorder := singleMacroRec.getInstance(300) ; maxRecordTime
    static AppShorts := singleProfile.getInstance()
    static Repo := singleRepository.getInstance()
    static qMenu := singleQuickMenu.getInstance()
    static stateConfig := { none: 0, home: 1, work: 2 }
    static currentConfig := App.stateConfig.none
}
SetWorkingDir(A_ScriptDir)
CoordMode("Mouse", "Screen")
TraySetIcon("ahk.ico")
A_TrayMenu.Add("Control menu" . State.Script.getVersion(), (*) => DialogPauseGui())
class Path {
    static Dir := "Files\"
    static Log := Path.Dir "log.txt"
    static Clipboard := Path.Dir "clipboards.json"
    static Slot := Path.Dir "slots.json"
    static Profile := Path.Dir "profiles.json"
    static Repository := Path.Dir "repository.json"
    static initDirectory() {
        if !DirExist(Path.Dir) {
            DirCreate(Path.Dir)
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
Pause & Delete:: {    
    ProcessClose("AutoHotkey64.exe") ; tamamen öldür
    Sleep 300
    ExitApp()
}
#SuspendExempt False

LoadSettings()
OnExit ExitSettings

; ═══════════════════════════════════════════════════════════

LoadSettings() {
    OutputDebug "Script " State.Script.getVersion() " started... " FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss") "`n"
    State.loadStats()
    if (A_ComputerName = "LAPTOP-UTN6L5PA") { ;work
        State.Idle.enable()
        ;MsgBox(A_ComputerName, A_UserName) ; LAPTOP-UTN6L5PA
        ShowTip("Work profile active", TipType.Info, 1000)
        App.currentConfig := App.stateConfig.work
    } else {
        TrayTip("AHK", "Home profile " . State.Script.getVersion(), 1)
        App.currentConfig := App.stateConfig.home
    }
    Path.initDirectory()
}
ExitSettings(ExitReason, ExitCode) {
    State.saveStats(State.Script.getStartTime())
    App.ClipHist.__Delete()
    App.ClipSlot.__Delete()
    State.Window.clearAllOnTop()
}
reloadScript() {
    State.saveStats(State.Script.getStartTime())
    SoundBeep(500)
    Reload
}

; ═══════════════════════════════════════════════════════════

#HotIf (A_PriorKey != "" && A_TimeSincePriorHotkey != "" && A_TimeSincePriorHotkey < 70)
LButton:: {
    App.KeyCounts.inc("DoubleCount")
    App.ErrHandler.handleError("double click: " A_TimeSincePriorHotkey)
    SoundBeep(1000, 100)
    Return
}
#HotIf

#HotIf State.Busy.isCombo() ; combo tuşu suppress ediyoruz *önünde modifier tusu var demek
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

; #HotIf gClipManager.getAutoClip()
; ^c:: gClipManager.copyToClipboard()
; ^x:: gClipManager.copyToClipboard()
; ^v:: gClipManager.pasteFromClipboard()
; #HotIf

; Pause & 1:: recorder.recordAction(1, MacroRecorder.recType.key)
; Pause & 2:: recorder.stop()  ; Kayıt durdur
; Pause & 3:: recorder.playKeyAction(1, 1)  ; rec1.ahk’yı 1 kez oynat

#HotIf App.currentConfig = App.stateConfig.work ; hotif olan tuslari override eder
>#1:: App.Recorder.playKeyAction(1, 1) ;orta basinca kayit //uzun basinca run n olabilir
>#2:: App.Recorder.playKeyAction(2, 1)
; >#3:: getPressTypeTest( ;belki önüne birsey gelince olabilir?
;     (pressType) => pressType == 0
;         ? App.Recorder.playKeyAction(3, 1)
;         : App.Recorder.recordAction(3, singleMacroRecorder.recType.key)
; )
#HotIf

#HotIf App.currentConfig = App.stateConfig.home
SC132:: App.Recorder.playKeyAction(1, 1) ;orta basinca kayit //uzun basinca run n olabilir
SC16C:: App.Recorder.playKeyAction(2, 1)
#HotIf

;Fare tuslari haritasi
F13:: App.HotMouse.handleF13()
F14:: App.HotMouse.handleF14()
F15:: App.HotMouse.handleF15()
F16:: App.HotMouse.handleF16()
F17:: App.HotMouse.handleF17()
F18:: App.HotMouse.handleF18()
F19:: App.HotMouse.handleF19()
F20:: App.HotMouse.handleF20()

;^::^ ;caret tuşu halen işlevsel SC029  vkC0

SC029:: App.HotCascade.cascadeCaret() ; Caret VKDC SC029  ^ != ^
SC00F:: App.HotCascade.cascadeTab()   ; Tab VK09 SC00F  (for not kill  Tab::Tab)
SC03A:: App.HotCascade.cascadeCaps() ; SC03A:: cascade.cascadeCaps()
SC00D:: App.HotHook.sysCommands() ; ´ backtick SC00D VKDD
~LButton:: App.HotMouse.handleLButton()
~MButton:: App.HotMouse.handleMButton()
~RButton:: App.HotMouse.handleRButton()
; ~RButton:: App.KeyCounts.inc("RButton")
;~LButton & RButton::RButton & LButton:: {}
~MButton & WheelUp:: {
    if (State.Mouse.shouldProcessWheel())
        Send("#{NumpadAdd}")
}
~MButton & WheelDown:: {
    if (State.Mouse.shouldProcessWheel())
        Send("#{NumpadSub}")
}

RButton & WheelUp:: {
    State.Mouse.setRightClick(true)
    if (State.Mouse.shouldProcessWheel()) {
        Send("{Volume_Up}")
    }
}

RButton & WheelDown:: {
    State.Mouse.setRightClick(true)
    if (State.Mouse.shouldProcessWheel()) {
        Send("{Volume_Down}")
    }
}

~RButton Up:: {
    if (State.Mouse.isRightClickActive()) {
        Sleep 50
        Send ("{ESC}")
        State.Mouse.setRightClick(false)
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

; ^!+#Space:: return OutputDebug(":-)") ; Send("+{F10}") ;work suppreme edilemiyor (#hotif de olmadı)
^<:: SendInput ("^+k") ;satir sil vscode
!v:: {
    SetKeyDelay (520, 560)
    SendText (A_Clipboard)
}

AppsKey & a:: { ;work
    SetTimer(() => ToolTip("AppsKey + A basıldı"), -80)
}