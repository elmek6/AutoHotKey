class SingleMacroRec {
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
        if (!SingleMacroRec.instance) {
            SingleMacroRec.instance := SingleMacroRec(maxRecordTime, maxLines)
        }
        return SingleMacroRec.instance
    }

    __New(maxRecordTime, maxLines) {
        if (SingleMacroRec.instance) {
            throw Error("MacroRecorder zaten oluşturulmuş! getInstance kullan.")
        }
        this.maxRecordTime := maxRecordTime
        this.maxLines := maxLines
        this.isStrokeOnlyMode := false
        this.recordType := SingleMacroRec.recType.key
        this.outputFile := "rec1.ahk"
        this.logFile := Path.Dir . this.outputFile
        this.recording := false
        this.playing := false
        this.status := SingleMacroRec.macroStatusType.ready
        this.logArr := []
        this.oldid := ""
        this.oldtitle := ""
        this.relativeX := 0
        this.relativeY := 0
        this.mouseMode := "screen"
        this.prmSleepEnabled := 0
        this.prmSetKeyDelay := 30
        this.prmSpeedUp := 0.0
        ; Cached timer callbacks - tek seferlik BoundFunc oluştur
        this._boundStopRecording := ObjBindMethod(this, "stopRecording")
        this._boundShowTipChangeColor := ObjBindMethod(this, "showTipChangeColor")
        this._boundLogWindow := ObjBindMethod(this, "logWindow")
    }

    recordAction(fileNumber, recordType) {
        this.isStrokeOnlyMode := false
        this.outputFile := "rec" . fileNumber . ".ahk"
        this.recordType := recordType
        this.logFile := Path.Dir . this.outputFile
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
        this.status := SingleMacroRec.macroStatusType.record
        this.catchPressedHotkey(true, isStrokeOnly)
        CoordMode("Mouse", "Screen")
        MouseGetPos(&x, &y)
        this.relativeX := x
        this.relativeY := y
        tipMsg := isStrokeOnly ? "Recording strokes..." : "Recording"
        this.showCustomTip(tipMsg)
        SetTimer(this._boundStopRecording, -this.maxRecordTime * 1000)
    }

    playPause() {
        if (this.status == SingleMacroRec.macroStatusType.record) {
            this.recording := false
            this.status := SingleMacroRec.macroStatusType.pause
            this.catchPressedHotkey(false, this.isStrokeOnlyMode)
            SetTimer(this._boundStopRecording, 0)
            this.showCustomTip("Paused")
        } else if (this.status == SingleMacroRec.macroStatusType.pause) {
            this.recording := true
            this.status := SingleMacroRec.macroStatusType.record
            this.catchPressedHotkey(true, this.isStrokeOnlyMode)
            this.showCustomTip(this.isStrokeOnlyMode ? "Recording strokes..." : "Recording")
            SetTimer(this._boundStopRecording, -this.maxRecordTime * 1000)
        }
    }

    stopRecording(returnOnly := false) {
        if (!this.recording)
            return ""

        this.recording := false
        this.status := SingleMacroRec.macroStatusType.ready
        this.catchPressedHotkey(false, this.isStrokeOnlyMode)
        SetTimer(this._boundShowTipChangeColor, 0)
        this.showCustomTip()

        if (this.logArr.Length = 0 || this.logArr.Length > this.maxLines) {
            return ""
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
        coordMode := this.mouseMode == "window" ? "Window" : "Screen"
        lines := []
        lines.Push("; Generated: " FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss"))
        lines.Push("; run sample.ahk --repeat=1{1 to n} --speedUp=0.0{sleep * n} --keyDelay=30")
        lines.Push("#SingleInstance Force")
        lines.Push("prnRepeatCount := 1")
        lines.Push("prmSpeedUp := " this.prmSpeedUp)
        lines.Push("prmSetKeyDelay := " this.prmSetKeyDelay)
        lines.Push("for _, arg in A_Args {")
        lines.Push("    if (RegExMatch(arg, `"(?:-r|--repeat)=(\\d+)`", &m))")
        lines.Push("        prnRepeatCount := m[1]")
        lines.Push("    else if (RegExMatch(arg, `"--keyDelay=(\d+)`", &m))")
        lines.Push("        prmSetKeyDelay := m[1]")
        lines.Push("    else if (RegExMatch(arg, `"--speedUp=([\d\.]+)`", &m))")
        lines.Push("        prmSpeedUp := m[1]")
        lines.Push("}")
        lines.Push("")
        lines.Push("#HotIf")
        lines.Push("^C:: {")
        lines.Push("    ExitApp(3)")
        lines.Push("}")
        lines.Push("")
        lines.Push("Loop (prnRepeatCount) {")
        lines.Push("SetKeyDelay(30)")
        lines.Push("SendMode(`"Event`")")
        lines.Push("SetTitleMatchMode(2)")
        lines.Push("CoordMode(`"Mouse`", `"" coordMode "`")")
        For k, v in this.logArr {
            if (InStr(v, "Sleep(")) {
                sleepValue := RegExMatch(v, "Sleep\((\d+)\)", &m) ? m[1] : 0
                lines.Push("    Sleep( " sleepValue "* prmSpeedUp )")
            } else {
                lines.Push(v)
            }
        }
        lines.Push("}")
        lines.Push("ExitApp")
        fullScript := ""
        for line in lines {
            fullScript .= line "`n"
        }

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
        this.logFile := Path.Dir . this.outputFile
        if (!FileExist(this.logFile)) {
            this.showCustomTip()
            ShowTip("Dosya bulunamadı: " . this.logFile, TipType.Error, 2000)
            return
        }
        this.playing := true
        this.status := SingleMacroRec.macroStatusType.play
        this.showCustomTip("Playing " . this.outputFile, "y35", "Green|00FFFF")
        ahk := A_AhkPath
        if (!FileExist(ahk)) {
            this.showCustomTip()
            MsgBox("AutoHotkey bulunamadı: " ahk "!", "Hata", 4096)
            this.playing := false
            this.status := SingleMacroRec.macroStatusType.ready
            return
        }
        ; command := A_IsCompiled ? (ahk . " /script /restart `"" . this.logFile . "`" " . params) : (ahk . " /restart `"" . this.logFile . "`" " . params)
        prnRepeatCount := 1
        params := Format(" --repeat={} --speedUp={} --keyDelay={}", prnRepeatCount, this.prmSpeedUp, this.prmSetKeyDelay)
        command := ahk . " `"" . this.logFile . "`" " . params
        scriptExitCode := RunWait(command)
        this.playing := false
        this.status := SingleMacroRec.macroStatusType.ready
        this.showCustomTip()
        if (scriptExitCode != 0) {
            App.ErrHandler.handleError("Script Error in " this.outputFile ": - Exit code :" scriptExitCode)
        }
    }

    catchPressedHotkey(enable := false, isStrokeOnly := false) {
        state := enable ? "On" : "Off"
        keyFn := enable ? (*) => this.logKey() : (*) => 0

        ; Klavye hotkey'leri
        Loop 254 {
            k := GetKeyName(vk := Format("vk{:X}", A_Index))
            if (!(k ~= "^(?i:|Control|Alt|Shift|LButton|RButton|MButton)$"))
                Hotkey("~*" vk, keyFn, state)
        }
        For i, k in StrSplit("NumpadEnter|Home|End|PgUp|PgDn|Left|Right|Up|Down|Delete|Insert", "|") {
            sc := Format("sc{:03X}", GetKeySC(k))
            if (!(k ~= "^(?i:|Control|Alt|Shift)$"))
                Hotkey("~*" sc, keyFn, state)
        }

        ; Fare hotkey'leri: açarken koşullu, kapatırken her zaman kapat
        if (enable && !isStrokeOnly && this.recordType != SingleMacroRec.recType.key) {
            Hotkey("$~*LButton", (*) => this.logKeyMouse("LButton"), "On")
            Hotkey("$~*RButton", (*) => this.logKeyMouse("RButton"), "On")
            Hotkey("$~*MButton", (*) => this.logKeyMouse("MButton"), "On")
        } else {
            Hotkey("$~*LButton", (*) => 0, "Off")
            Hotkey("$~*RButton", (*) => 0, "Off")
            Hotkey("$~*MButton", (*) => 0, "Off")
        }

        ; Pencere takibi
        if (enable && !isStrokeOnly) {
            SetTimer(this._boundLogWindow, 100)
            this.logWindow()
        } else {
            SetTimer(this._boundLogWindow, 0)
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
            if (this.recordType != SingleMacroRec.recType.key && !this.isStrokeOnlyMode)
                this.logKeyMouse(k)
        } else {
            if (this.recordType != SingleMacroRec.recType.mouse)
                this.logKeyboard(k, vksc)
        }
    }

    logKeyControl(key) {
        if (this.recordType = SingleMacroRec.recType.mouse || this.isStrokeOnlyMode)
            return
        k := InStr(key, "Win") ? key : SubStr(key, 2)
        this.log("{" k " Down}", true)
        Critical("Off")
        KeyWait(key)
        Critical()
        this.log("{" k " Up}", true)
    }

    ; MouseClick string builder: mode = "screen"|"window"|"relative", updown = "D"|"U"|""
    _mouseStr(key, x, y, mode, updown := "") {
        prefix := this.mouseMode == mode ? "" : ";"
        if (mode == "relative") {
            if (updown)
                return prefix "MouseClick(`"" key "`", " x ", " y ",,, `"" updown "`", `"R`") `;" mode
            return prefix "MouseClick(`"" key "`", " x ", " y ",,,, `"R`") `;" mode
        }
        if (updown)
            return prefix "MouseClick(`"" key "`", " x ", " y ",,, `"" updown "`") `;" mode
        return prefix "MouseClick(`"" key "`", " x ", " y ") `;" mode
    }

    logKeyMouse(key) {
        if (this.recordType = SingleMacroRec.recType.key || this.isStrokeOnlyMode)
            return
        k := SubStr(key, 1, 1)

        ; Down eventlerini logla ve index'lerini sakla
        CoordMode("Mouse", "Screen")
        MouseGetPos(&X, &Y, &id)
        this.log(this._mouseStr(k, X, Y, "screen", "D"))
        screenIdx := this.logArr.Length

        CoordMode("Mouse", "Window")
        MouseGetPos(&WindowX, &WindowY, &id)
        this.log(this._mouseStr(k, WindowX, WindowY, "window", "D"))
        windowIdx := this.logArr.Length

        CoordMode("Mouse", "Screen")
        MouseGetPos(&tempRelativeX, &tempRelativeY, &id)
        relX := tempRelativeX - this.relativeX
        relY := tempRelativeY - this.relativeY
        this.log(this._mouseStr(k, relX, relY, "relative", "D"))
        relativeIdx := this.logArr.Length
        this.relativeX := tempRelativeX
        this.relativeY := tempRelativeY

        ; Tuş bırakılmasını bekle
        CoordMode("Mouse", "Screen")
        MouseGetPos(&X1, &Y1)
        t1 := A_TickCount
        Critical("Off")
        KeyWait(key)
        Critical()
        t2 := A_TickCount
        if (t2 - t1 <= 200)
            X2 := X1, Y2 := Y1
        else
            MouseGetPos(&X2, &Y2)

        noDrag := Abs(X2 - X1) + Abs(Y2 - Y1) < 5

        ; Screen
        if (noDrag) {
            this.logArr[screenIdx] := this._mouseStr(k, X, Y, "screen")
            this.log()
        } else {
            this.log(this._mouseStr(k, X + X2 - X1, Y + Y2 - Y1, "screen", "U"))
        }

        ; Window
        if (noDrag) {
            this.logArr[windowIdx] := this._mouseStr(k, WindowX, WindowY, "window")
            this.log()
        } else {
            this.log(this._mouseStr(k, WindowX + X2 - X1, WindowY + Y2 - Y1, "window", "U"))
        }

        ; Relative
        if (noDrag) {
            this.logArr[relativeIdx] := this._mouseStr(k, relX, relY, "relative")
            this.log()
        } else {
            this.log(this._mouseStr(k, X2 - X1, Y2 - Y1, "relative", "U"))
        }
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
        if (this.logArr.Length >= this.maxLines && this.recordType != SingleMacroRec.recType.mouse) {
            this.stopRecording()
            return
        }
        if (Delay > 250)
            this.logArr.Push("    Sleep(" Delay ")")
        this.logArr.Push(keyboard ? "    Send `"{Blind}" str "`"" : str)
    }

    showCustomTip(s := "", pos := "y35", color := "Red|00FFFF") {
        static ShowTip := ""
        if (SingleMacroRec.bak = color "," pos "," s)
            return
        SetTimer(this._boundShowTipChangeColor, 0)
        SingleMacroRec.bak := color "," pos "," s
        if (IsObject(ShowTip))
            ShowTip.Destroy()
        SingleMacroRec.RecordingControl := ""
        if (s = "")
            return
        ShowTip := Gui("+LastFound +AlwaysOnTop +ToolWindow -Caption +E0x08000020", "ShowTip")
        WinSetTransColor("FFFFF0 150")
        ShowTip.BackColor := "cFFFFF0"
        ShowTip.MarginX := 10
        ShowTip.MarginY := 5
        ShowTip.SetFont("q3 s20 bold c" . (InStr(s, "Playing") ? "Green" : "Red"))
        SingleMacroRec.RecordingControl := ShowTip.Add("Text", , s)
        ShowTip.Show("NA " . pos)
        SetTimer(this._boundShowTipChangeColor, 1000)
    }

    showTipChangeColor() {
        if (!SingleMacroRec.RecordingControl || !IsObject(SingleMacroRec.RecordingControl)) {
            SetTimer(this._boundShowTipChangeColor, 0)
            return
        }
        r := StrSplit(SubStr(SingleMacroRec.bak, 1, InStr(SingleMacroRec.bak, ",") - 1), "|")
        SingleMacroRec.RecordingControl.SetFont("q3 c" r[SingleMacroRec.idx := Mod(Round(SingleMacroRec.idx), r.Length) + 1])
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
            recordType := typeCombo.Text = "key" ? SingleMacroRec.recType.key : (typeCombo.Text = "mouse" ? SingleMacroRec.recType.mouse : SingleMacroRec.recType.hybrid),
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