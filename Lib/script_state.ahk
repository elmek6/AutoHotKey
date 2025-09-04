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
            throw Error("ScriptState zaten oluÅŸturulmuÅŸ! getInstance kullan.")
        }
        this.version := version
        this.busy := 0
        this.disableLogging := false
        this.rightClickActive := false
        this.idleCount := 60
    }

    setBusy(status) {
        this.busy := status
    }

    getBusy() {
        return this.busy
    }

    setRightClickActive(status) {
        this.rightClickActive := status
    }

    getRightClickActive() {
        return this.rightClickActive
    }

    setIdleCount(count) {
        this.idleCount := count
    }

    getIdleCount() {
        return this.idleCount
    }

    getVersion() {
        return this.version
    }

    setDisableLogging(status) {
        this.disableLogging := status
    }

    getDisableLogging() {
        return this.disableLogging
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
        if (this.getDisableLogging()) {
            return
        }
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
}