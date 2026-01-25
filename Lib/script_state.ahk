class singleState {
    static instance := ""

    static getInstance(version) {
        if (!singleState.instance) {
            singleState.instance := singleState(version)
        }
        return singleState.instance
    }

    __New(version) {
        if (singleState.instance) {
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

        this.clipStatusEnum := {
            none: 0,
            clipHist: 1,
            memSlot: 2,
        }
        this.clipHandleStatus := this.clipStatusEnum.none
    }

    setBusy(status) => this.busy := status
    getBusy() => this.busy

    setClipHandler(mode) {
        this.clipHandleStatus := mode
    }
    getClipHandler() => this.clipHandleStatus

    getLastWheelTime() {
        diff := A_TickCount - this.lastWheelTime
        if (diff > 600) {  ; ms'den fazla geçtiyse resetle (yeni tekerlek serisi)
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
        if (App.KeyCounts.get("DayCount") == "") {
            App.KeyCounts.set("DayCount", FormatTime(A_Now, "yyyyMMdd"))
            ShowTip(App.KeyCounts.get("DayCount"), TipType.Info, 3000)
            ; ToolTip(App.KeyCounts.get("DayCount")), SetTimer(() => ToolTip(), -3800)
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
            if (App.KeyCounts.has(key)) {
                App.KeyCounts.set(key, val)
            }
        }

        while !file.AtEOF {
            line := file.ReadLine()
            parts := StrSplit(line, "=")
            if (parts.Length < 2)
                continue
            timestamp := Trim(parts[1])
            errorMessage := Trim(parts[2])
            App.ErrHandler.errorMap[timestamp] := errorMessage
        }
        file.Close()
    }

    saveStats(scriptStartTime) {
        if (!this.shouldSaveStats)
            return

        App.KeyCounts.inc("WriteCount")

        local startDate := FormatTime(scriptStartTime, "yyyyMMdd")
        local currentSince := FormatTime(A_Now, "yyyyMMdd")
        App.KeyCounts.set("DayCount", App.KeyCounts.get("DayCount") + DateDiff(currentSince, startDate, "Days"))

        try {
            file := FileOpen(AppConst.FILE_LOG, "w")
            if !file
                throw Error("Dosya açılamadı: " . AppConst.FILE_LOG)  ; catch'e düş

            for k, v in App.KeyCounts.getAll() {
                file.WriteLine(k "=" v)
            }
            file.WriteLine("*")
            for timestamp, errorMessage in App.ErrHandler.errorMap {
                file.WriteLine(timestamp "=" errorMessage)
            }
            file.Close()
        } catch as err {
            ; Verdiğiniz koda benzer hata yönetimi: Yedekle ve hatayı işle
            App.ErrHandler.backupOnError("scriptState.saveStats! Log dosyası yazılamadı", AppConst.FILE_LOG)
        }

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
            App.ErrHandler.handleError("Always on top toggle hatası", err)
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
            App.ErrHandler.handleError("Tüm always on top kaldırma hatası", err)
        }
    }

}