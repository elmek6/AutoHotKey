class singleMacroRecorder {
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
        if (!singleMacroRecorder.instance) {
            singleMacroRecorder.instance := singleMacroRecorder(maxRecordTime, maxLines)
        }
        return singleMacroRecorder.instance
    }

    __New(maxRecordTime, maxLines) {
        if (singleMacroRecorder.instance) {
            throw Error("MacroRecorder zaten oluşturulmuş! getInstance kullan.")
        }
        this.maxRecordTime := maxRecordTime
        this.maxLines := maxLines
        this.isStrokeOnlyMode := false
        this.recordType := singleMacroRecorder.recType.key
        this.outputFile := "rec1.ahk"
        this.logFile := AppConst.FILES_DIR . this.outputFile
        this.recording := false
        this.playing := false
        this.status := singleMacroRecorder.macroStatusType.ready
        this.logArr := []
        this.oldid := ""
        this.oldtitle := ""
        this.relativeX := 0
        this.relativeY := 0
        this.mouseMode := "screen"
        this.prmSleepEnabled := 0
        this.prmSetKeyDelay := 30
        this.prmSpeedUp := 0.0
    }

    recordAction(fileNumber, recordType) {
        this.isStrokeOnlyMode := false
        this.outputFile := "rec" . fileNumber . ".ahk"
        this.recordType := recordType
        this.logFile := AppConst.FILES_DIR . this.outputFile
        if (this.recording) {
            this.playPause()  ; Kayıt varsa pause/stop
            return
        }
        this.recordScreen(false)
    }

    recordStrokes(recordType) {
        this.isStrokeOnlyMode := true
        this.recordType := recordType
        this.recordScreen(true)
    }

    recordScreen(isStrokeOnly) {
        this.logArr := []
        this.oldid := ""
        this.oldtitle := ""
        this.recording := true
        this.status := singleMacroRecorder.macroStatusType.record
        this.catchPressedHotkey(true, isStrokeOnly)
        CoordMode("Mouse", "Screen")
        MouseGetPos(&x, &y)
        this.relativeX := x
        this.relativeY := y
        tipMsg := isStrokeOnly ? "Recording strokes..." : "Recording"
        this.showTip(tipMsg)
        SetTimer(ObjBindMethod(this, "stopRecording"), -this.maxRecordTime * 1000)
    }

    playPause() {
        if (this.status == singleMacroRecorder.macroStatusType.record) {
            this.recording := false
            this.status := singleMacroRecorder.macroStatusType.pause
            this.catchPressedHotkey(false, this.isStrokeOnlyMode)
            SetTimer(ObjBindMethod(this, "stopRecording"), 0)
            this.showTip("Paused")
        } else if (this.status == singleMacroRecorder.macroStatusType.pause) {
            this.recording := true
            this.status := singleMacroRecorder.macroStatusType.record
            this.catchPressedHotkey(true, this.isStrokeOnlyMode)
            this.showTip(this.isStrokeOnlyMode ? "Recording strokes..." : "Recording")
            SetTimer(ObjBindMethod(this, "stopRecording"), -this.maxRecordTime * 1000)
        }
    }

    getStrokeCommands() {
        if (!this.recording || !this.isStrokeOnlyMode)
            return ""
        return this.stopRecording(true)
    }

    stopRecording(returnOnly := false) {
        if (!this.recording)
            return returnOnly ? "" : ""

        this.recording := false
        this.status := singleMacroRecorder.macroStatusType.ready
        this.catchPressedHotkey(false, this.isStrokeOnlyMode)
        SetTimer(ObjBindMethod(this, "showTipChangeColor"), 0)
        this.showTip()

        if (this.logArr.Length = 0 || this.logArr.Length > this.maxLines) {
            return returnOnly ? "" : ""
        }

        ;-> Sadece Send ve Sleep içeren satırları filtrele
        s := ""
        For k, v in this.logArr {
            if (InStr(v, "Sleep(") || InStr(v, "Send(")) {
                s .= v "`n" ;yalnizca tus degerlerini al
            }
        }
        if (returnOnly) {
            return s
        }
        ;-> Sadece Send ve Sleep içeren satırları filtrele

        ; Dosyaya yaz (normal kayıt modu için)
        prnRepeatCount := 1
        fullScript := "; Generated: " FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss") "`n"
        fullScript .= "; run sample.ahk --repeat=1{1 to n} --speedUp=0.0{sleep * n} --keyDelay=30`n"
        fullScript .= "#SingleInstance Force`n"
        fullScript .= "prnRepeatCount := " prnRepeatCount "`n"
        fullScript .= "prmSpeedUp := " this.prmSpeedUp "`n"
        fullScript .= "prmSetKeyDelay := " this.prmSetKeyDelay "`n"
        fullScript .= "for _, arg in A_Args {`n"
        fullScript .= "    if (RegExMatch(arg, `"(?:-r|--repeat)=(\\d+)`", &m))`n"
        fullScript .= "        prnRepeatCount := m[1]`n"
        fullScript .= "    else if (RegExMatch(arg, `"--keyDelay=(\d+)`", &m))`n"
        fullScript .= "        prmSetKeyDelay := m[1]`n"
        fullScript .= "    else if (RegExMatch(arg, `"--speedUp=([\d\.]+)`", &m))`n"
        fullScript .= "        prmSpeedUp := m[1]`n"
        fullScript .= "}`n`n"
        fullScript .= "#HotIf`n"
        fullScript .= "^C:: {`n"
        fullScript .= "    ExitApp(3)`n"
        fullScript .= "}`n`n"
        fullScript .= "Loop (prnRepeatCount) {`n"
        fullScript .= "SetKeyDelay(30)`n"
        fullScript .= "SendMode(`"Event`")`n"
        fullScript .= "SetTitleMatchMode(2)`n"
        if (this.mouseMode == "window") {
            fullScript .= "CoordMode(`"Mouse`", `"Window`")`n"
        } else {
            fullScript .= "CoordMode(`"Mouse`", `"Screen`")`n"
        }
        For k, v in this.logArr {
            if (InStr(v, "Sleep(")) {
                sleepValue := RegExMatch(v, "Sleep\((\d+)\)", &m) ? m[1] : 0
                fullScript .= "    Sleep( " sleepValue "* prmSpeedUp )`n"
            } else {
                fullScript .= v "`n"
            }
        }
        fullScript .= "}`n"
        fullScript .= "ExitApp"
        fullScript := RegExReplace(fullScript, "\R", "`n")

        if (FileExist(this.logFile))
            FileDelete(this.logFile)
        FileAppend(fullScript, this.logFile)

        return ""
    }

    stop() {
        ; Normal kayıt için stop, dosyaya yazar
        this.stopRecording(false)
    }

    playKeyAction(fileNumber, params := "") {
        if (this.recording || this.playing)
            this.stop()
        this.outputFile := "rec" . fileNumber . ".ahk"
        this.logFile := AppConst.FILES_DIR . this.outputFile
        if (!FileExist(this.logFile)) {
            this.showTip()
            ToolTip("Dosya bulunamadı: " this.logFile), SetTimer(() => ToolTip(), -2000)
            return
        }
        this.playing := true
        this.status := singleMacroRecorder.macroStatusType.play
        this.showTip("Playing " . this.outputFile, "y35", "Green|00FFFF")
        ahk := A_AhkPath
        if (!FileExist(ahk)) {
            this.showTip()
            MsgBox("AutoHotkey bulunamadı: " ahk "!", "Hata", 4096)
            this.playing := false
            this.status := singleMacroRecorder.macroStatusType.ready
            return
        }
        ; command := A_IsCompiled ? (ahk . " /script /restart `"" . this.logFile . "`" " . params) : (ahk . " /restart `"" . this.logFile . "`" " . params)
        prnRepeatCount := 1
        params := Format(" --repeat={} --speedUp={} --keyDelay={}", prnRepeatCount, this.prmSpeedUp, this.prmSetKeyDelay)
        command := ahk . " `"" . this.logFile . "`" " . params
        scriptExitCode := RunWait(command)
        this.playing := false
        this.status := singleMacroRecorder.macroStatusType.ready
        this.showTip()
        if (scriptExitCode != 0) {
            gErrHandler.handleError("Script Error in " this.outputFile ": - Exit code :" scriptExitCode)
        }
    }

    catchPressedHotkey(f := false, isStrokeOnly := false) {
        f := f ? "On" : "Off"
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

        ; Fare hotkey'leri sadece stroke-only DEĞİLSE aktif
        if (!isStrokeOnly && this.recordType != singleMacroRecorder.recType.key) {
            Hotkey("$~*LButton", (*) => this.logKeyMouse("LButton"), f)
            Hotkey("$~*RButton", (*) => this.logKeyMouse("RButton"), f)
            Hotkey("$~*MButton", (*) => this.logKeyMouse("MButton"), f)
        }

        if (f = "On") {
            ; Stroke-only modda pencere değişikliği KAYDEDİLMEZ
            if (!isStrokeOnly) {
                SetTimer(ObjBindMethod(this, "logWindow"), 100)
                this.logWindow()
            }
        } else {
            SetTimer(ObjBindMethod(this, "logWindow"), 0)
            ; Hotkey temizliği
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
        }
    }

    logKey() {
        Critical()
        k := GetKeyName(vksc := SubStr(A_ThisHotkey, 3))
        k := StrReplace(k, "Control", "Ctrl"), r := SubStr(k, 2)
        ;OutputDebug("logKey: Key detected: " k ", vksc: " vksc ", recordType: " this.recordType)
        if (r ~= "^(?i:Alt|Ctrl|Shift|Win)$")
            this.logKeyControl(k)
        else if (k ~= "^(?i:LButton|RButton|MButton)$") {
            if (this.recordType != singleMacroRecorder.recType.key && !this.isStrokeOnlyMode)
                this.logKeyMouse(k)
        } else {
            if (this.recordType != singleMacroRecorder.recType.mouse)
                this.logKeyboard(k, vksc)
        }
    }

    logKeyControl(key) {
        if (this.recordType = singleMacroRecorder.recType.mouse || this.isStrokeOnlyMode)
            return
        k := InStr(key, "Win") ? key : SubStr(key, 2)
        this.log("{" k " Down}", true)
        Critical("Off")
        ErrorLevel := !KeyWait(key)
        Critical()
        this.log("{" k " Up}", true)
    }

    logKeyMouse(key) {
        if (this.recordType = singleMacroRecorder.recType.key || this.isStrokeOnlyMode)
            return
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
        ;OutputDebug("logKeyboard: Key: " k ", vksc: " vksc)
    }

    logWindow() {
        if (this.isStrokeOnlyMode)
            return  ; Stroke-only modda pencere kaydı YOK
        id := WinExist("A")
        if (!id)
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
        ;OutputDebug("logWindow: Title: " title ", id: " id)
    }

    log(str := "", keyboard := false) {
        static LastTime := 0
        t := A_TickCount
        Delay := (LastTime ? t - LastTime : 0)
        LastTime := t
        if (str = "")
            return

        ; Stroke-only modda sadece klavye girdileri ve Sleep kaydedilir
        if (this.isStrokeOnlyMode && !keyboard && !InStr(str, "Sleep("))
            return

        i := this.logArr.Length
        r := i = 0 ? "" : this.logArr[i]
        if (keyboard && InStr(r, "Send") && Delay < 1000) {
            this.logArr[i] := SubStr(r, 1, -1) . str "`""
            return
        }
        if (this.logArr.Length >= this.maxLines && this.recordType != singleMacroRecorder.recType.mouse) {
            this.stopRecording()
            return
        }
        if (Delay > 250)
            this.logArr.Push("    Sleep(" Delay ")")
        this.logArr.Push(keyboard ? "    Send `"{Blind}" str "`"" : str)
    }

    showTip(s := "", pos := "y35", color := "Red|00FFFF") {
        static ShowTip := Gui()
        if (singleMacroRecorder.bak = color "," pos "," s)
            return
        SetTimer(ObjBindMethod(this, "showTipChangeColor"), 0)
        singleMacroRecorder.bak := color "," pos "," s
        ShowTip.Destroy()
        singleMacroRecorder.RecordingControl := ""
        if (s = "")
            return
        ShowTip := Gui("+LastFound +AlwaysOnTop +ToolWindow -Caption +E0x08000020", "ShowTip")
        WinSetTransColor("FFFFF0 150")
        ShowTip.BackColor := "cFFFFF0"
        ShowTip.MarginX := 10
        ShowTip.MarginY := 5
        ShowTip.SetFont("q3 s20 bold c" . (InStr(s, "Playing") ? "Green" : "Red"))
        singleMacroRecorder.RecordingControl := ShowTip.Add("Text", , s)
        ShowTip.Show("NA " . pos)
        SetTimer(ObjBindMethod(this, "showTipChangeColor"), 1000)
    }

    showTipChangeColor() {
        if (!singleMacroRecorder.RecordingControl || !IsObject(singleMacroRecorder.RecordingControl)) {
            SetTimer(ObjBindMethod(this, "showTipChangeColor"), 0)
            return
        }
        r := StrSplit(SubStr(singleMacroRecorder.bak, 1, InStr(singleMacroRecorder.bak, ",") - 1), "|")
        singleMacroRecorder.RecordingControl.SetFont("q3 c" r[singleMacroRecorder.idx := Mod(Round(singleMacroRecorder.idx), r.Length) + 1])
    }

    showButtons() {
        static pauseGui := ""
        _destroyGui() {
            pauseGui.Destroy()
            pauseGui := ""
        }

        if (IsObject(pauseGui) && pauseGui.Hwnd) {
            pauseGui.Show()
            return
        }

        pauseGui := Gui("+ToolWindow +AlwaysOnTop", "Macro Recorder")
        pauseGui.SetFont("s10")

        fileCombo := pauseGui.Add("ComboBox", "w100 x10 y10 +ReadOnly", ["rec1.ahk", "rec2.ahk"])
        fileCombo.Value := 1

        typeCombo := pauseGui.Add("ComboBox", "w100 x120 y10", ["key", "mouse", "hybrid"])
        typeCombo.Value := 1

        recordBtn := pauseGui.Add("Button", "w80 h25 x10 y40", "🛑")
        recordBtn.OnEvent("Click", (*) => (
            fileNumber := SubStr(fileCombo.Text, 4, 1),
            recordType := typeCombo.Text = "key" ? singleMacroRecorder.recType.key : (typeCombo.Text = "mouse" ? singleMacroRecorder.recType.mouse : singleMacroRecorder.recType.hybrid),
            this.recordAction(fileNumber, recordType)
        ))

        stopBtn := pauseGui.Add("Button", "w80 h25 x95 y40", "⏹️")
        stopBtn.OnEvent("Click", (*) => (
            this.stop()
        ))

        playBtn := pauseGui.Add("Button", "w80 h25 x180 y40", "▶️")
        playBtn.OnEvent("Click", (*) => (
            fileNumber := SubStr(fileCombo.Text, 4, 1),
            this.playKeyAction(fileNumber, "")
            _destroyGui()
        ))

        exitBtn := pauseGui.Add("Button", "w80 h25 x265 y40", "🚪")
        exitBtn.OnEvent("Click", (*) => (
            this.stop(),
            _destroyGui(),
            ExitApp
        ))

        pauseGui.OnEvent("Close", (*) => (
            this.stop(),
            _destroyGui()
        ))
        pauseGui.OnEvent("Escape", (*) => (
            this.stop(),
            _destroyGui()
        ))

        pauseGui.Show("xCenter yCenter")
        SoundBeep(750)
    }
}