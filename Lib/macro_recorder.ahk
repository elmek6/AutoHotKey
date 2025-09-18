class MacroRecorder {
    static instance := ""
    static RecordingControl := ""
    static bak := ""
    static idx := 0

    class recType {
        static key := 1
        static mouse := 2
        static hybrid := 3
    }

    class macroStatusType {
        static ready := 1
        static record := 2
        static pause := 3
        static play := 4
        static stop := 5
    }

    static getInstance(maxRecordTime := 300, maxLines := 500) {
        if (!MacroRecorder.instance) {
            MacroRecorder.instance := MacroRecorder(maxRecordTime, maxLines)
        }
        return MacroRecorder.instance
    }

    __New(maxRecordTime, maxLines) {
        if (MacroRecorder.instance) {
            throw Error("MacroRecorder zaten oluşturulmuş! getInstance kullan.")
        }
        this.maxRecordTime := maxRecordTime
        this.maxLines := maxLines
        this.baseFileName := "rec1.ahk"
        this.recordType := MacroRecorder.recType.key  ; Varsayılan: key
        this.logFile := AppConst.FILES_DIR . this.baseFileName
        this.recording := false
        this.playing := false
        this.status := MacroRecorder.macroStatusType.ready
        this.logArr := []
        this.oldid := ""
        this.oldtitle := ""
        this.relativeX := 0
        this.relativeY := 0
        this.mouseMode := "screen"
        this.recordSleep := "false"
        this.speed := 100
        this.updateSettings()
        OutputDebug("MacroRecorder initialized, recordType: " this.recordType)
    }

    recordAction(fileNumber, recordType) {
        this.baseFileName := "rec" . fileNumber . ".ahk"
        this.recordType := recordType
        this.logFile := AppConst.FILES_DIR . this.baseFileName
        if (this.recording) {
            this.playPause()  ; Kayıt varsa pause/stop
            return
        }
        this.recordScreen()
        OutputDebug("recordAction called, file: " this.logFile ", recordType: " recordType)
    }

    recordScreen() {
        this.logArr := []
        this.oldid := ""
        this.oldtitle := ""
        this.recording := true
        this.status := MacroRecorder.macroStatusType.record
        this.setHotkey(true)
        CoordMode("Mouse", "Screen")
        MouseGetPos(&x, &y)
        this.relativeX := x
        this.relativeY := y
        this.showTip("Recording")
        SetTimer(ObjBindMethod(this, "stop"), -this.maxRecordTime * 1000)
        OutputDebug("recordScreen started, mouse at: (" x ", " y ")")
    }

    playPause() {
        if (this.status == MacroRecorder.macroStatusType.record) {
            this.recording := false
            this.status := MacroRecorder.macroStatusType.pause
            this.setHotkey(false)
            SetTimer(ObjBindMethod(this, "stop"), 0)
            this.showTip("Paused")
            OutputDebug("Paused recording")
        } else if (this.status == MacroRecorder.macroStatusType.pause) {
            this.recording := true
            this.status := MacroRecorder.macroStatusType.record
            this.setHotkey(true)
            this.showTip("Recording")
            SetTimer(ObjBindMethod(this, "stop"), -this.maxRecordTime * 1000)
            this.showTip("Recording")
            ; Debug
            OutputDebug("Resumed recording")
        }
    }

    updateSettings() {
        if (FileExist(this.logFile)) {
            logFileObject := FileOpen(this.logFile, "r")
            Loop 3 {
                logFileObject.ReadLine()
            }
            this.mouseMode := RegExReplace(logFileObject.ReadLine(), ".*=")
            logFileObject.ReadLine()
            this.recordSleep := RegExReplace(logFileObject.ReadLine(), ".*=")
            logFileObject.Close()
        } else {
            this.mouseMode := "screen"
            this.recordSleep := "false"
        }
        if (this.mouseMode != "screen" && this.mouseMode != "window" && this.mouseMode != "relative")
            this.mouseMode := "screen"
        if (this.recordSleep != "true" && this.recordSleep != "false")
            this.recordSleep := "false"
        OutputDebug("updateSettings: mouseMode=" this.mouseMode ", recordSleep=" this.recordSleep)
    }

    stop() {
        if (this.recording) {
            if (this.logArr.Length > 0 && this.logArr.Length <= this.maxLines) {
                this.updateSettings()
                this.speed := 100
                for _, arg in A_Args {
                    if (RegExMatch(arg, "(?:-r|--repeat)=(\d+)", &m))
                        repeatCount := m[1]
                    else if (RegExMatch(arg, "--sleep=([0-1])", &m))
                        sleepEnabled := m[1]
                    else if (RegExMatch(arg, "--speed=(\d+)", &m))
                        this.speed := m[1]
                }
                s := "; Generated: " FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss") "`n"
                s .= ";Press Pause & 3 to play. Press Pause & 1 to record. Press Pause & 2 to stop.`n;Parameters: --repeat=N (default 1), --sleep=0/1 (default 0), --speed=N (default 100)`n;#####SETTINGS#####`n;MouseMode=" this.mouseMode "`n;RecordSleep=" this.recordSleep "`n"
                s .= "repeatCount := 1`nsleepEnabled := 0`nspeed := " this.speed "`nfor _, arg in A_Args {`n    if (RegExMatch(arg, `"(?:-r|--repeat)=(\\d+)`", &m))`n        repeatCount := m[1]`n    else if (RegExMatch(arg, `"--sleep=([0-1])`", &m))`n        sleepEnabled := m[1]`n    else if (RegExMatch(arg, `"--speed=(\\d+)`", &m))`n        speed := m[1]`n}`n"
                s .= "#HotIf`n^C:: {`n    FileAppend('" FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss") " - User interrupted: " A_ScriptName "', '" AppConst.FILES_DIR "errors.log')`n    ExitApp(3)`n}`n"
                s .= "Loop(repeatCount)`n{`n`nStartingValue := 0`ni := RegRead(`"HKEY_CURRENT_USER\SOFTWARE\`" A_ScriptName, `"i`", StartingValue)`nRegWrite(i + 1, `"REG_DWORD`", `"HKEY_CURRENT_USER\SOFTWARE\`" A_ScriptName, `"i`")`n`nSetKeyDelay(30)`nSendMode(`"Event`")`nSetTitleMatchMode(2)`n"
                if (this.mouseMode == "window") {
                    s .= "`n;CoordMode(`"Mouse`", `"Screen`")`nCoordMode(`"Mouse`", `"Window`")`n"
                } else {
                    s .= "`nCoordMode(`"Mouse`", `"Screen`")`n;CoordMode(`"Mouse`", `"Window`")`n"
                }
                For k, v in this.logArr {
                    if (InStr(v, "Sleep(") && this.recordSleep = "false") {
                        s .= "`n;" v "`n"
                    } else if (InStr(v, "Sleep(")) {
                        sleepValue := RegExMatch(v, "Sleep\((\d+)\)", &m) ? m[1] : 0
                        scaledSleep := Round(sleepValue * 100 / this.speed)
                        s .= "`nSleep(" scaledSleep ")`n"
                    } else {
                        s .= "`n" v "`n"
                    }
                }
                s .= "`n`n}`nExitApp()`n`nPause & 3::ExitApp()`n"
                s := RegExReplace(s, "\R", "`n")
                if (FileExist(this.logFile))
                    FileDelete(this.logFile)
                FileAppend(s, this.logFile)
                OutputDebug("stop: Wrote " this.logArr.Length " actions to " this.logFile)
            }
            this.recording := false
            this.status := MacroRecorder.macroStatusType.stop
            this.logArr := []
            this.setHotkey(false)
            OutputDebug("stop: Recording stopped, status: " this.status)
        }
        SetTimer(ObjBindMethod(this, "showTipChangeColor"), 0)
        this.showTip()
        Suspend(false)
        Pause(false)
    }

    playKeyAction(fileNumber, params := "") {
        if (this.recording || this.playing)
            this.stop()
        this.baseFileName := "rec" . fileNumber . ".ahk"
        this.logFile := AppConst.FILES_DIR . this.baseFileName
        if (!FileExist(this.logFile)) {
            this.showTip()
            MsgBox("Dosya bulunamadı: " this.logFile ". Önce kayıt yapın!", "Hata", 4096)
            return
        }
        this.playing := true
        this.status := MacroRecorder.macroStatusType.play
        this.showTip("Playing " . this.baseFileName, "y35", "Green|00FFFF")
        ahk := A_AhkPath
        if (!FileExist(ahk)) {
            this.showTip()
            MsgBox("AutoHotkey bulunamadı: " ahk "!", "Hata", 4096)
            this.playing := false
            this.status := MacroRecorder.macroStatusType.ready
            return
        }
        command := A_IsCompiled ? (ahk . " /script /restart `"" . this.logFile . "`" " . params) : (ahk . " /restart `"" . this.logFile . "`" " . params)
        ErrorLevel := RunWait(command)
        this.playing := false
        this.status := MacroRecorder.macroStatusType.ready
        this.showTip()
        if (ErrorLevel != 0) {
            this.errorHandler(this.baseFileName, ErrorLevel)
        }
        OutputDebug("playKeyAction: Played " this.logFile ", exitCode: " ErrorLevel)
    }

    errorHandler(fileName, exitCode) {
        logFile := AppConst.FILES_DIR . "errors.log"
        errorMsg := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss") . " - Error in " . fileName . ": Exit code " . exitCode . "`n"
        OutputDebug("errorHandler: " errorMsg)
        FileAppend(errorMsg, logFile)
    }

    setHotkey(f := false) {
        f := f ? "On" : "Off"
        OutputDebug("setHotkey: Setting hotkeys " f ", recordType: " this.recordType)
        Loop 254 {
            k := GetKeyName(vk := Format("vk{:X}", A_Index))
            if (!(k ~= "^(?i:|Control|Alt|Shift|LButton|RButton|MButton)$"))
                Hotkey("~*" vk, (*) => this.logKey(), f)
        }
        For i, k in StrSplit("NumpadEnter|Home|End|PgUp|PgDn|Left|Right|Up|Down|Delete|Insert", "|") {
            sc := Format("sc{:03X}", GetKeySC(k))
            if (!(k ~= "^(?i:|Control|Alt|Shift)$"))
                Hotkey("~*" sc, (*) => this.logKey(), f)
        }
        ; Explicit mouse hotkey'leri, override önlemek için $
        if (this.recordType != MacroRecorder.recType.key) {
            Hotkey("$~*LButton", (*) => this.logKeyMouse("LButton"), f)
            Hotkey("$~*RButton", (*) => this.logKeyMouse("RButton"), f)
            Hotkey("$~*MButton", (*) => this.logKeyMouse("MButton"), f)
        }
        if (f = "On") {
            SetTimer(ObjBindMethod(this, "logWindow"), 100)
            this.logWindow()
        } else {
            SetTimer(ObjBindMethod(this, "logWindow"), 0)  ; Timer'ı garanti kapat
            ; Tüm hotkey'leri explicit kapat
            Loop 254 {
                k := GetKeyName(vk := Format("vk{:X}", A_Index))
                if (!(k ~= "^(?i:|Control|Alt|Shift|LButton|RButton|MButton)$"))
                    Hotkey("~*" vk, (*) => 0, "Off")
            }
            For i, k in StrSplit("NumpadEnter|Home|End|PgUp|PgDn|Left|Right|Up|Down|Delete|Insert", "|") {
                sc := Format("sc{:03X}", GetKeySC(k))
                if (!(k ~= "^(?i:|Control|Alt|Shift)$"))
                    Hotkey("~*" sc, (*) => 0, "Off")
            }
            Hotkey("$~*LButton", (*) => 0, "Off")
            Hotkey("$~*RButton", (*) => 0, "Off")
            Hotkey("$~*MButton", (*) => 0, "Off")
            OutputDebug("setHotkey: All hotkeys turned off")
        }
    }

    logKey() {
        Critical()
        k := GetKeyName(vksc := SubStr(A_ThisHotkey, 3))
        k := StrReplace(k, "Control", "Ctrl"), r := SubStr(k, 2)
        OutputDebug("logKey: Key detected: " k ", vksc: " vksc ", recordType: " this.recordType)
        if (r ~= "^(?i:Alt|Ctrl|Shift|Win)$")
            this.logKeyControl(k)
        else if (k ~= "^(?i:LButton|RButton|MButton)$") {
            if (this.recordType != MacroRecorder.recType.key)
                this.logKeyMouse(k)
        } else {
            if (this.recordType != MacroRecorder.recType.mouse)
                this.logKeyboard(k, vksc)
        }
    }

    logKeyControl(key) {
        if (this.recordType = MacroRecorder.recType.mouse)
            return
        k := InStr(key, "Win") ? key : SubStr(key, 2)
        this.log("{" k " Down}", true)
        Critical("Off")
        ErrorLevel := !KeyWait(key)
        Critical()
        this.log("{" k " Up}", true)
        OutputDebug("logKeyControl: Control key: " k)
    }

    logKeyMouse(key) {
        if (this.recordType = MacroRecorder.recType.key)
            return
        OutputDebug("logKeyMouse: Mouse: " key ", logArr: " this.logArr.Length)
        k := SubStr(key, 1, 1)
        CoordMode("Mouse", "Screen")
        MouseGetPos(&X, &Y, &id)
        this.log((this.mouseMode == "window" || this.mouseMode == "relative" ? ";" : "") "MouseClick(`"" k "`", " X ", " Y ",,, `"D`") `;screen")

        CoordMode("Mouse", "Window")
        MouseGetPos(&WindowX, &WindowY, &id)
        this.log((this.mouseMode != "window" ? ";" : "") "MouseClick(`"" k "`", " WindowX ", " WindowY ",,, `"D`") `;window")

        CoordMode("Mouse", "Screen")
        MouseGetPos(&tempRelativeX, &tempRelativeY, &id)
        this.log((this.mouseMode != "relative" ? ";" : "") "MouseClick(`"" k "`", " (tempRelativeX - this.relativeX) ", " (tempRelativeY - this.relativeY) ",,, `"D`", `"R`") `;relative")
        this.relativeX := tempRelativeX
        this.relativeY := tempRelativeY

        CoordMode("Mouse", "Screen")
        MouseGetPos(&X1, &Y1)
        t1 := A_TickCount
        Critical("Off")
        ErrorLevel := !KeyWait(key)
        Critical()
        t2 := A_TickCount
        if (t2 - t1 <= 200)
            X2 := X1, Y2 := Y1
        else
            MouseGetPos(&X2, &Y2)

        i := this.logArr.Length - 2, r := this.logArr[i]
        if (InStr(r, ",,, `"D`")") && Abs(X2 - X1) + Abs(Y2 - Y1) < 5)
            this.logArr[i] := SubStr(r, 1, -16) ") `;screen", this.log()
        else
            this.log((this.mouseMode == "window" || this.mouseMode == "relative" ? ";" : "") "MouseClick(`"" k "`", " (X + X2 - X1) ", " (Y + Y2 - Y1) ",,, `"U`") `;screen")

        i := this.logArr.Length - 1, r := this.logArr[i]
        if (InStr(r, ",,, `"D`")") && Abs(X2 - X1) + Abs(Y2 - Y1) < 5)
            this.logArr[i] := SubStr(r, 1, -16) ") `;window", this.log()
        else
            this.log((this.mouseMode != "window" ? ";" : "") "MouseClick(`"" k "`", " (WindowX + X2 - X1) ", " (WindowY + Y2 - Y1) ",,, `"U`") `;window")

        i := this.logArr.Length, r := this.logArr[i]
        if (InStr(r, ",,, `"D`", `"R`")") && Abs(X2 - X1) + Abs(Y2 - Y1) < 5)
            this.logArr[i] := SubStr(r, 1, -23) ",,,, `"R`") `;relative", this.log()
        else
            this.log((this.mouseMode != "relative" ? ";" : "") "MouseClick(`"" k "`", " (X2 - X1) ", " (Y2 - Y1) ",,, `"U`", `"R`") `;relative")
    }

    logKeyboard(k, vksc) {
        if (k = "NumpadLeft" || k = "NumpadRight") && !GetKeyState(k, "P")
            return
        k := StrLen(k) > 1 ? "{" k "}" : k ~= "\w" ? k : "{" vksc "}"
        this.log(k, true)
        OutputDebug("logKeyboard: Key: " k ", vksc: " vksc)
    }

    logWindow() {
        id := WinExist("A")
        if (!id)  ; Aktif pencere yoksa çık
            return
        title := WinGetTitle()
        class := WinGetClass()
        if (title = "" && class = "")
            return
        if (id = this.oldid && title = this.oldtitle)
            return
        this.oldid := id
        this.oldtitle := title
        title := SubStr(title, 1, 50)
        title .= class ? " ahk_class " class : ""
        title := RegExReplace(Trim(title), "[``%;]", "``$0")
        CommentString := ""
        if (this.mouseMode != "window")
            CommentString := ";"
        s := CommentString "tt := `"" title "`"`n" CommentString "WinWait(tt)" . "`n" CommentString "if (!WinActive(tt))`n" CommentString "  WinActivate(tt)"
        i := this.logArr.Length
        r := i = 0 ? "" : this.logArr[i]
        if (InStr(r, "tt = ") = 1)
            this.logArr[i] := s, this.log()
        else
            this.log(s)
        OutputDebug("logWindow: Title: " title ", id: " id)
    }

    log(str := "", keyboard := false) {
        static LastTime := 0
        t := A_TickCount
        Delay := (LastTime ? t - LastTime : 0)
        LastTime := t
        if (str = "")
            return
        i := this.logArr.Length
        r := i = 0 ? "" : this.logArr[i]
        if (keyboard && InStr(r, "Send") && Delay < 1000) {
            this.logArr[i] := SubStr(r, 1, -1) . str "`""
            return
        }
        if (this.logArr.Length >= this.maxLines && this.recordType != MacroRecorder.recType.mouse) {
            this.stop()
            return
        }
        if (Delay > 200)
            this.logArr.Push((this.recordSleep == "false" ? ";" : "") "Sleep(" (Delay // 2) ")")
        this.logArr.Push(keyboard ? "Send `"{Blind}" str "`"" : str)
        OutputDebug("log: Added " (keyboard ? "keyboard" : "mouse") " action: " str ", logArr: " this.logArr.Length)
    }

    showTip(s := "", pos := "y35", color := "Red|00FFFF") {
        static ShowTip := Gui()
        if (MacroRecorder.bak = color "," pos "," s)
            return
        SetTimer(ObjBindMethod(this, "showTipChangeColor"), 0)
        MacroRecorder.bak := color "," pos "," s
        ShowTip.Destroy()
        MacroRecorder.RecordingControl := ""
        if (s = "")
            return
        ShowTip := Gui("+LastFound +AlwaysOnTop +ToolWindow -Caption +E0x08000020", "ShowTip")
        WinSetTransColor("FFFFF0 150")
        ShowTip.BackColor := "cFFFFF0"
        ShowTip.MarginX := 10
        ShowTip.MarginY := 5
        ShowTip.SetFont("q3 s20 bold c" . (InStr(s, "Playing") ? "Green" : "Red"))
        MacroRecorder.RecordingControl := ShowTip.Add("Text", , s)
        ShowTip.Show("NA " . pos)
        SetTimer(ObjBindMethod(this, "showTipChangeColor"), 1000)
        OutputDebug("showTip: Displayed: " s)
    }

    showTipChangeColor() {
        if (!MacroRecorder.RecordingControl || !IsObject(MacroRecorder.RecordingControl)) {
            SetTimer(ObjBindMethod(this, "showTipChangeColor"), 0)
            return
        }
        r := StrSplit(SubStr(MacroRecorder.bak, 1, InStr(MacroRecorder.bak, ",") - 1), "|")
        MacroRecorder.RecordingControl.SetFont("q3 c" r[MacroRecorder.idx := Mod(Round(MacroRecorder.idx), r.Length) + 1])
    }

    showButtons() {
        static pauseGui := ""
        _destroyGui() {
            pauseGui.Destroy()
            pauseGui := ""
        }

        if (IsObject(pauseGui) && pauseGui.Hwnd) {
            pauseGui.Show()  ; Zaten varsa sadece göster
            return
        }

        pauseGui := Gui("+ToolWindow +AlwaysOnTop", "Macro Recorder")
        pauseGui.SetFont("s10")

        ; Dosya seçimi (read-only)
        fileCombo := pauseGui.Add("ComboBox", "w100 x10 y10 +ReadOnly", ["rec1.ahk", "rec2.ahk"])
        fileCombo.Value := 1

        ; Tür seçimi (key, mouse, hybrid)
        typeCombo := pauseGui.Add("ComboBox", "w100 x120 y10", ["key", "mouse", "hybrid"])
        typeCombo.Value := 1  ; Varsayılan: key

        ; Yatay butonlar
        recordBtn := pauseGui.Add("Button", "w80 h25 x10 y40", "Record/Pause")
        recordBtn.OnEvent("Click", (*) => (
            fileNumber := SubStr(fileCombo.Text, 4, 1),
            recordType := typeCombo.Text = "key" ? MacroRecorder.recType.key : (typeCombo.Text = "mouse" ? MacroRecorder.recType.mouse : MacroRecorder.recType.hybrid),
            this.recordAction(fileNumber, recordType)
        ))

        stopBtn := pauseGui.Add("Button", "w80 h25 x95 y40", "Stop")
        stopBtn.OnEvent("Click", (*) => (
            this.stop()
        ))

        playBtn := pauseGui.Add("Button", "w80 h25 x180 y40", "Play")
        playBtn.OnEvent("Click", (*) => (
            fileNumber := SubStr(fileCombo.Text, 4, 1),
            this.playKeyAction(fileNumber, "")
            _destroyGui()
        ))

        exitBtn := pauseGui.Add("Button", "w80 h25 x265 y40", "Exit")
        exitBtn.OnEvent("Click", (*) => (
            this.stop(),  ; Kayıt varsa durdur
            _destroyGui(),
            ExitApp
        ))

        pauseGui.OnEvent("Close", (*) => (
            this.stop(),  ; Kayıt varsa durdur
            _destroyGui()
        ))
        pauseGui.OnEvent("Escape", (*) => (
            this.stop(),  ; Kayıt varsa durdur
            _destroyGui()
        ))

        pauseGui.Show("xCenter yCenter")
        SoundBeep(750)
    }
}