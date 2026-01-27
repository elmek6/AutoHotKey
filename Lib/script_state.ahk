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

        ; ===== SUB-STATE MODULES =====
        this.Script := singleState.ScriptModule(version)
        this.Busy := singleState.BusyModule()
        this.Mouse := singleState.MouseModule()
        this.Clipboard := singleState.ClipboardModule()
        this.Window := singleState.WindowModule()
        this.Idle := singleState.IdleModule()
    }

    ; ═══════════════════════════════════════════════════════════

    class ScriptModule {
        version := "?"
        startTime := A_Now
        shouldSaveOnExit := true

        __New(version) {
            this.version := version
        }

        getVersion() => this.version
        getStartTime() => this.startTime
        getShouldSaveOnExit() => this.shouldSaveOnExit
        setShouldSaveOnExit(value) => this.shouldSaveOnExit := value
    }

    ; ═══════════════════════════════════════════════════════════

    class BusyModule {
        current := 0
        caller := ""

        get() => this.current
        set(level) => this.current := level

        isFree() => this.current == 0
        isActive() => this.current == 1
        isCombo() => this.current == 2

        setFree() => this.set(0)
        setActive() => this.set(1)
        setCombo(caller := "") {
            this.lastCaller := caller
            this.set(2)
            OutputDebug("BLOCKED by: " caller "`n")
        }
        ; getLastCaller() => this.lastCaller
    }

    ; ═══════════════════════════════════════════════════════════

    class MouseModule {
        rightClickActive := false
        lastWheelTime := 0
        _wheelCount := 0

        setRightClick(active) => this.rightClickActive := active
        isRightClickActive() => this.rightClickActive

        shouldProcessWheel(throttleMs := 600) {
            diff := A_TickCount - this.lastWheelTime

            if (diff > throttleMs) {
                this.lastWheelTime := A_TickCount
                this._wheelCount := 0
                return false
            }

            this._wheelCount++
            this.lastWheelTime := A_TickCount
            return Mod(this._wheelCount, 2) == 0
        }

        reset() {
            this.rightClickActive := false
            this.lastWheelTime := 0
            this._wheelCount := 0
        }
    }

    ; ═══════════════════════════════════════════════════════════

    class ClipboardModule {
        ; None := 0, History := 1, MemSlots := 2
        current := 0

        setMode(mode) => this.current := mode
        getMode() => this.current

        isNone() => this.current == 0
        isHistory() => this.current == 1
        isMemSlots() => this.current == 2

        setNone() => this.setMode(0)
        setHistory() => this.setMode(1)
        setMemSlots() => this.setMode(2)
    }

    ; ═══════════════════════════════════════════════════════════

    class WindowModule {
        hwnd := ""
        title := ""
        className := ""
        onTopWindows := Map()

        update() {
            try {
                this.hwnd := WinGetID("A")
                this.title := WinGetTitle("ahk_id " . this.hwnd)
                this.className := WinGetClass("ahk_id " . this.hwnd)
            } catch {
                this.hwnd := ""
                this.title := ""
                this.className := ""
            }
        }

        getHwnd() => this.hwnd
        getTitle() => this.title
        getClass() => this.className

        isClass(className) {
            activeClass := WinGetClass("A")
            return activeClass == className
        }

        toggleAlwaysOnTop(hwnd := "", title := "") {
            if (hwnd == "") {
                this.update()
                hwnd := this.hwnd
                title := this.title
            }

            if (!hwnd)
                return

            if (this.onTopWindows.Has(hwnd)) {
                try WinSetAlwaysOnTop(0, "ahk_id " hwnd)
                this.onTopWindows.Delete(hwnd)
            } else {
                try WinSetAlwaysOnTop(1, "ahk_id " hwnd)
                this.onTopWindows[hwnd] := title
            }
        }

        clearAllOnTop() {
            for hwnd in this.onTopWindows {
                try WinSetAlwaysOnTop(0, "ahk_id " hwnd)
            }
            this.onTopWindows.Clear()
        }

        ; isOnTop(hwnd := "") {
        ;     if (hwnd == "")
        ;         hwnd := this.hwnd
        ;     return this.onTopWindows.Has(hwnd)
        ; }
    }

    ; ═══════════════════════════════════════════════════════════
    class IdleModule {
        count := 60
        enabled := false
        timer := ""

        enable(intervalMs := 5 * 60 * 1000) {
            this.enabled := true
            this.count := 60
            this.timer := ObjBindMethod(this, "tick")
            SetTimer this.timer, intervalMs
        }

        disable() {
            this.enabled := false
            if (this.timer) {
                SetTimer this.timer, 0
                this.timer := ""
            }
        }

        isEnabled() => this.enabled
        setCount(value) => this.count := value
        getCount() => this.count

        tick() {
            if (!this.enabled)
                return

            if (A_TimeIdlePhysical < 60000) {
                this.count := 60
                return
            }

            this.count--

            if (this.count > 0) {
                MouseMove(-1, -1, 0, "R")
            } else {
                this.disable()
            }
        }
    }

    ; ═══════════════════════════════════════════════════════════

    loadStats() {
        if (App.KeyCounts.get("DayCount") == "") {
            App.KeyCounts.set("DayCount", FormatTime(A_Now, "yyyyMMdd"))
            ShowTip(App.KeyCounts.get("DayCount"), TipType.Info, 3000)
        }

        if !FileExist(Path.Log)
            return
        file := FileOpen(Path.Log, "r")
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
        App.KeyCounts.inc("WriteCount")

        local startDate := FormatTime(scriptStartTime, "yyyyMMdd")
        local currentSince := FormatTime(A_Now, "yyyyMMdd")
        App.KeyCounts.set("DayCount", App.KeyCounts.get("DayCount") + DateDiff(currentSince, startDate, "Days"))

        try {
            file := FileOpen(Path.Log, "w")
            if !file
                throw Error("Dosya açılamadı: " . Path.Log)  ; catch'e düş

            for k, v in App.KeyCounts.getAll() {
                file.WriteLine(k "=" v)
            }
            file.WriteLine("*")
            for timestamp, errorMessage in App.ErrHandler.errorMap {
                file.WriteLine(timestamp "=" errorMessage)
            }
            file.Close()
        } catch as err {
            App.ErrHandler.backupOnError("scriptState.saveStats! Log dosyası yazılamadı", Path.Log)
        }

    }
}