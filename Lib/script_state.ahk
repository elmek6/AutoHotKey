class ScriptState {
    static instance := ""

    static getInstance(version) {
        if (!ScriptState.instance) {
            ScriptState.instance := ScriptState(version)
        }
        return ScriptState.instance
    }

    __New(version) {
        if (ScriptState.instance) {
            throw Error("ScriptState zaten oluşturulmuş! getInstance kullan.")
        }
        this.version := version
        this.busy := 0
        this.shouldSaveStats := false
        this.rightClickActive := false
        this.idleCount := 60
        this.onTopWindowsList := Map()
        this.activeHwnd := ""
        this.activeTitle := ""
        this.activeClassName := ""
        this.lastWheelTime := 0
        this._wheelcount := 0
    }

    setBusy(status) => this.busy := status
    getBusy() => this.busy

    getLastWheelTime() {
        diff := A_TickCount - this.lastWheelTime
        if (diff > 200) {  ; 100ms'den fazla geçtiyse resetle (yeni tekerlek serisi)
            this.lastWheelTime := A_TickCount
            this._wheelcount := 0
            return false
        }
        this._wheelcount++
        this.lastWheelTime := A_TickCount
        if (Mod(this._wheelcount, 2) = 0) {
            return true
        } else {
            return false
        }
    }

    setRightClickActive(status) => this.rightClickActive := status
    getRightClickActive() => this.rightClickActive
    setIdleCount(count) => this.idleCount := count

    updateActiveWindow() {
        try {
            this.activeHwnd := WinGetID("A")
            this.activeTitle := WinGetTitle("ahk_id " . this.activeHwnd)
            this.activeClassName := WinGetClass("ahk_id " . this.activeHwnd)
        } catch {
            this.activeHwnd := ""
            this.activeTitle := ""
            this.activeClassName := ""
        }
    }

    getActiveHwnd() => this.activeHwnd
    getActiveTitle() => this.activeTitle
    getActiveClassName() => this.activeClassName
    getIdleCount() => this.idleCount
    getVersion() => this.version
    getShouldSaveOnExit() => this.shouldSaveStats

    setShouldSaveOnExit(status) {
        this.shouldSaveStats := status
    }


    isActiveClass(className) {
        activeClass := WinGetClass("A")
        return activeClass == className
    }

    loadStats() {
        if (keyCounts.get("DayCount") == "") {
            keyCounts.set("DayCount", FormatTime(A_Now, "yyyyMMdd"))
            ToolTip(keyCounts.get("DayCount"))
            SetTimer(() => ToolTip(), -3800)
        }

        if !FileExist(AppConst.FILE_LOG)
            return
        file := FileOpen(AppConst.FILE_LOG, "r")
        if !file
            return
        while !file.AtEOF {
            line := file.ReadLine()
            if (line == "*") {
                break
            }
            parts := StrSplit(line, "=")
            key := Trim(parts[1])
            val := Trim(parts[2])
            if (keyCounts.has(key)) {
                keyCounts.set(key, val)
            }
        }

        while !file.AtEOF {
            line := file.ReadLine()
            parts := StrSplit(line, "=")
            if (parts.Length < 2)
                continue
            timestamp := Trim(parts[1])
            errorMessage := Trim(parts[2])
            errHandler.errorMap[timestamp] := errorMessage
        }
        file.Close()
    }

    saveStats(scriptStartTime) {
        if (!this.shouldSaveStats)
            return

        keyCounts.inc("WriteCount")

        local startDate := FormatTime(scriptStartTime, "yyyyMMdd")
        local currentSince := FormatTime(A_Now, "yyyyMMdd")
        keyCounts.set("DayCount", keyCounts.get("DayCount") + DateDiff(currentSince, startDate, "Days"))

        file := FileOpen(AppConst.FILE_LOG, "w")
        if !file
            return
        for k, v in keyCounts.getAll() {
            file.WriteLine(k "=" v)
        }
        file.WriteLine("*")
        for timestamp, errorMessage in errHandler.errorMap {
            file.WriteLine(timestamp "=" errorMessage)
        }
        file.Close()
    }

    toggleOnTopWindow(hwnd, title) {
        try {
            ; if (!WinExist(title))
            ;     return
            if (this.onTopWindowsList.Has(hwnd)) {
                WinSetAlwaysOnTop 0, title
                this.onTopWindowsList.Delete(hwnd)
            } else {
                this.onTopWindowsList[hwnd] := title
                WinSetAlwaysOnTop 1, title ;prantez kullanma
            }
        } catch as err {
            errHandler.handleError("Always on top toggle hatası", err)
        }
    }

    clearAllOnTopWindows() {
        try {
            for k, v in this.onTopWindowsList {
                if (WinExist(v)) {
                    this.toggleOnTopWindow(k, v)
                }
            }
            this.onTopWindowsList.Clear()
        } catch as err {
            errHandler.handleError("Tüm always on top kaldırma hatası", err)
        }
    }

    getCountTopWindows() {
        return this.onTopWindowsList.Count
    }

    cleanClosedOnTopWindows() {
        try {
            for hwnd, _ in this.onTopWindowsList.Clone() {  ; Clone ile döngüde silme güvenli
                if (!WinExist("ahk_id " hwnd)) {
                    this.onTopWindowsList.Delete(hwnd)
                }
            }
        } catch as err {
            errHandler.handleError("Kapalı always on top temizleme hatası", err)
        }
    }
}