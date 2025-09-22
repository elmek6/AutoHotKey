; #Requires AutoHotkey v2.0
#Requires AutoHotkey >= 2.1-alpha.18
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

;Json dosyasi olusturma F14 ile basilan menü icin özel tuslar

; FileAppend(FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss") " - Resumed recording`n", AppConst.FILES_DIR "debug.log")
; TraySetIcon("shell32.dll", 300) ; 177 win10 win11 ikonlari degisik! degismesi lazim
TraySetIcon("arrow.ico")
A_TrayMenu.Add("Pause script...", (*) => DialogPauseGui())
A_TrayMenu.Add("Çıkış", (*) => ExitApp())


OutputDebug "Started... " FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss") "`n"
global state := ScriptState.getInstance("ver_b123")
global keyCounts := KeyCounter.getInstance()
global errHandler := ErrorHandler.getInstance()
global clipManager := ClipboardManager.getInstance(20, 100000)
global keyHandler := HotkeyHandler.getInstance()
global cascade := CascadeMenu.getInstance()
global recorder := MacroRecorder.getInstance(300)
global scriptStartTime := A_Now
; global RelativeX := 0, RelativeY := 0  ; Macro recorder için global
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
SC029:: handleCaret()  ;caret VKDC SC029  ^ != ^
handleCaret() {
    loadSave(dt, number) {
        if (dt = 2) {
            clipManager.promptAndSaveSlot(number)
        } else {
            clipManager.loadFromSlot(number)
        }
    }

    builder := CascadeBuilder(400, 2500)
        .mainKey((dt) {
            if (dt = 1)
                SendInput("{SC029}" dt)
        })
        .setExitOnPressType(1)
        .pairs("s", "Search...", (dt) => clipManager.showSlotsSearch())
        .pairs("1", "Test 1", (dt) => loadSave(dt, 1))
        .pairs("2", "Test 2", (dt) => loadSave(dt, 2))
        .pairs("3", "Test 3", (dt) => loadSave(dt, 3))
        .pairs("4", "Test 4", (dt) => loadSave(dt, 4))
        .pairs("5", "Test 5", (dt) => loadSave(dt, 5))
        .pairs("6", "Test 6", (dt) => loadSave(dt, 6))
        .pairs("7", "Test 7", (dt) => loadSave(dt, 7))
        .pairs("8", "Test 8", (dt) => loadSave(dt, 8))
        .pairs("9", "Test 9", (dt) => loadSave(dt, 9))
        .pairs("0", "Test 0", (dt) => loadSave(dt, 13))
        .setPreview((b, pressType) {
            if (pressType == 0) {
                ; return builder.getPairsTips()
                return clipManager.getSlotsPreviewText()
            } else if (pressType == 1) {
                return []
            } else {
                result := []
                result.Push("-------------------- SAVE --------------------")
                result.Push("----------------------------------------------")
                for v in clipManager.getSlotsPreviewText()
                    result.Push(v)
                result.Push("kisa basma (" pressType "ms): Daha fazla seçenek")
                return result
            }
        })
    cascade.cascadeKey(builder, "^")
}

; Pause & 1:: recorder.recordAction(1, MacroRecorder.recType.key)
; Pause & 2:: recorder.stop()  ; Kayıt durdur
; Pause & 3:: recorder.playKeyAction(1, 1)  ; rec1.ahk’yı 1 kez oynat

; Tab::Tab
SC00F:: handleTab() ;TAB VK09 SC00F
handleTab() {
    loadSaveMacro(dt, number) {
        if (dt = 2) {
            recorder.recordAction(number, MacroRecorder.recType.key)
        } else {
            recorder.playKeyAction(number, 1)
        }
    }

    builder := CascadeBuilder(400, 2500)
        .mainKey((dt) {
            if (dt = 0)
                SendInput("{Tab}")
        })
        .setExitOnPressType(0)
        .pairs("s", "Search...", (dt) => clipManager.showSlotsSearch())
        .pairs("1", "rec1.ahk", (dt) => loadSaveMacro(dt, 1))
        .pairs("2", "rec2.ahk", (dt) => loadSaveMacro(dt, 2))
        .pairs("3", "rec3.ahk", (dt) => loadSaveMacro(dt, 3))
        .pairs("4", "rec4.ahk", (dt) => loadSaveMacro(dt, 4))
        .pairs("5", "rec5.ahk", (dt) => loadSaveMacro(dt, 5))
        .pairs("6", "rec6.ahk", (dt) => loadSaveMacro(dt, 6))
        .pairs("7", "rec7.ahk", (dt) => loadSaveMacro(dt, 7))
        .pairs("8", "rec8.ahk", (dt) => loadSaveMacro(dt, 8))
        .pairs("9", "rec9.ahk", (dt) => loadSaveMacro(dt, 9))
        .pairs("0", "rec0.ahk", (dt) => loadSaveMacro(dt, 13))
        .setPreview((b, pressType) {
            if (pressType = 1) {
                return clipManager.getSlotsPreviewText()
            } else {
                return []
            }

        })
    cascade.cascadeKey(builder, "Tab")
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
        statsMenu.Add(stat, (*) => A_Clipboard := stat)
    }
    statsMenu.Add()
    latestError := ""
    for timestamp, message in errHandler.getAllErrors() {
        latestError := FormatTime(timestamp, "dd HH:mm:ss") ": " message
    }
    statsMenu.Add("Copy last error", (*) => (errHandler.copyLastError()))
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
*0:: return
; *RButton:: return
#HotIf

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
; Tab:: {
;     TapOrHold(
;         () => ToolTip("Short F2"),
;         () => ToolTip("Medium F2"),
;         () => ToolTip("Long F2")
;         :aranan tuslar 1234567890s
;     )
;     Sleep(1000)
;     ToolTip()
; }


/*
    builder.setPreview((builder) {
        return builder.getPairsTips()
    })

handleCaret_() {
    static builder := FKeyBuilder()
        .mainDefault(() => Send("{^}"))
        .combos("q", "-", Sleep(50))
        .combos("1", "Load Slot 1", () => clipManager.loadFromSlot(1))
        .combos("2", "Load Slot 2", () => clipManager.loadFromSlot(2))
        .combos("3", "Load Slot 3", () => clipManager.loadFromSlot(3))
        .combos("4", "Load Slot 4", () => clipManager.loadFromSlot(4))
        .combos("5", "Load Slot 5", () => clipManager.loadFromSlot(5))
        .combos("6", "Load Slot 6", () => clipManager.loadFromSlot(6))
        .combos("7", "Load Slot 7", () => clipManager.loadFromSlot(7))
        .combos("8", "Load Slot 8", () => clipManager.loadFromSlot(8))
        .combos("9", "Load Slot 9", () => clipManager.loadFromSlot(9))
        .combos("0", "Load Slot 0", () => clipManager.loadFromSlot(0))
        .combos("PgDn", "Show Stats", () => ShowStats())
        .combos("s", "Show Slots Search", () => clipManager.showSlotsSearch())
    ; builder.setPreview(["Özel 1", "Özel 2"])
    builder.setPreview(builder.tips)
    this.handleFKey(builder)
}*/
