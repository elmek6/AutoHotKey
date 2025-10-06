; #Include <jsongo.v2>

class WindowData {
    __New(index, cleanTitle, x, y, w, h, isMinimized, monitor) {
        this.index := index
        this.cleanTitle := cleanTitle
        this.x := x
        this.y := y
        this.w := w
        this.h := h
        this.isMinimized := isMinimized
        this.monitor := monitor
    }

    ToString() {
        min := this.isMinimized ? "[MIN]" : "[NORMAL]"
        pos := Format("Pos: ({}, {}) Size: ({}x{})", this.x, this.y, this.w, this.h)
        titleShort := StrLen(this.cleanTitle) > 40 ? SubStr(this.cleanTitle, 1, 37) "..." : this.cleanTitle
        return Format("#{} Mon:{} {} {}`n    {}", this.index, this.monitor, min, titleShort, pos)
    }
}

class ChromePositions {
    static instance := ""

    static getInstance() {
        if (!ChromePositions.instance) {
            ChromePositions.instance := ChromePositions()
        }
        return ChromePositions.instance
    }

    __New() {
        if (ChromePositions.instance) {
            throw Error("ChromePositions zaten oluşturulmuş! getInstance kullan.")
        }
        this.windows := []
        this.loadPositions()
    }

    saveState() {
        monitorCount := MonitorGetCount()
        if (monitorCount = 1) {
            return
        }

        chromeCount := WinGetList("ahk_exe chrome.exe").Length
        if (chromeCount = 0) {
            return
        }

        SetTitleMatchMode(2)
        hwndList := WinGetList("ahk_exe chrome.exe")
        this.windows := []
        index := 0

        for hwnd in hwndList {
            if !DllCall("IsWindowVisible", "Ptr", hwnd) {
                continue
            }
            try {
                title := WinGetTitle("ahk_id " hwnd)
                if (title = "") {
                    continue
                }
                cleanTitle := RegExReplace(title, " - Google Chrome.*$", "")  ; Suffix temizle
                index++
                minMax := WinGetMinMax("ahk_id " hwnd)
                monitor := this._GetMonitorFromHwnd(hwnd)
                WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)

                winData := WindowData(index, cleanTitle, x, y, w, h, minMax = -1, monitor)
                this.windows.Push(winData)
            }
        }

        try {
            jsonData := jsongo.Stringify(this.windows)
            file := FileOpen(AppConst.FILE_POS, "w", "UTF-8")
            if (!file) {
                throw Error(AppConst.FILE_POS . " yazılamadı")
            }
            file.Write(jsonData)
            file.Close()
            ; OutputDebug(Format("Chrome positions kaydedildi: {} pencere.", this.windows.Length))
        } catch as err {
            errHandler.handleError("Chrome positions kaydetme hatası", err)
        }
    }

    restore() {
        if (this.windows.Length = 0) {
            ToolTip("Kaydedilmiş pozisyon yok.")
            return 0
        }

        SetTitleMatchMode(2)
        currentHwndList := this._GetVisibleWindows("ahk_exe chrome.exe")
        if (currentHwndList.Length = 0) {
            ToolTip("Mevcut Chrome penceresi yok.")
            return 0
        }

        matched := 0
        currentIndex := 0  ; Mevcut pencere index'i takip et
        for savedWin in this.windows {
            currentIndex++  ; Her saved için mevcut index artır
            matchedHwnd := this._MatchByTitle(savedWin.cleanTitle, currentHwndList)
            if (matchedHwnd) {
                targetMonitor := savedWin.monitor  ; Match varsa kaydedilen monitöre
                this._MoveToMonitorFullScreen(matchedHwnd, targetMonitor)
                matched++
            } else if (currentIndex <= currentHwndList.Length) {
                ; Fallback: Index'e göre mevcut monitörlere ata
                targetMonitor := Mod(savedWin.index - 1, MonitorGetCount()) + 1
                fallbackHwnd := currentHwndList[currentIndex]
                this._MoveToMonitorFullScreen(fallbackHwnd, targetMonitor)
                matched++
            }
        }
        ToolTip(Format("{} pencere restore edildi.", matched))
        return matched
    }

    loadPositions() {
        if (!FileExist(AppConst.FILE_POS)) {
            return
        }
        try {
            file := FileOpen(AppConst.FILE_POS, "r", "UTF-8")
            if (!file) {
                throw Error(AppConst.FILE_POS . " okunamadı")
            }
            data := file.Read()
            file.Close()
            parsedMaps := jsongo.Parse(data)
            this.windows := []  ; Temizle
            for mapData in parsedMaps {
                ; Map'i WindowData instance'ına dönüştür
                winData := WindowData(
                    mapData["index"],
                    mapData["cleanTitle"],
                    mapData["x"],
                    mapData["y"],
                    mapData["w"],
                    mapData["h"],
                    mapData["isMinimized"],
                    mapData["monitor"]
                )
                this.windows.Push(winData)
            }
        } catch as err {
            errHandler.handleError("Chrome positions yükleme hatası", err)
        }
    }

    _MatchByTitle(cleanTitle, currentHwndList) {
        for hwnd in currentHwndList {
            currentTitle := WinGetTitle("ahk_id " hwnd)
            currentClean := RegExReplace(currentTitle, " - Google Chrome.*$", "")
            if (InStr(currentClean, cleanTitle) || InStr(cleanTitle, currentClean)) {
                return hwnd
            }
        }
        return 0
    }

    _MoveToMonitorFullScreen(hwnd, monitorNum) {
        MonitorGetWorkArea(monitorNum, &monL, &monT, &monR, &monB)
        WinRestore("ahk_id " hwnd)  ; Minimize ise normale döndür
        WinMaximize("ahk_id " hwnd)  ; Tam ekran
        ; Workarea'ya sığdırma için ekstra WinMove (maximize bazen kenar boşluk bırakır)
        WinMove(monL, monT, monR - monL, monB - monT, "ahk_id " hwnd)
    }

    _GetVisibleWindows(WinTitle) {
        visibleList := []
        for hwnd in WinGetList(WinTitle) {
            if DllCall("IsWindowVisible", "Ptr", hwnd) && (WinGetTitle("ahk_id " hwnd) != "") {
                visibleList.Push(hwnd)
            }
        }
        return visibleList
    }

    _GetMonitorFromHwnd(hwnd) {
        WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)
        centerX := x + (w // 2)
        centerY := y + (h // 2)

        Loop MonitorGetCount() {
            MonitorGet(A_Index, &L, &T, &R, &B)
            if (centerX >= L && centerX < R && centerY >= T && centerY < B) {
                return A_Index
            }
        }
        return 1
    }

    getSummary() {
        if (this.windows.Length = 0) {
            return "Kaydedilmiş Chrome pozisyonu yok!"
        }
        s := Format("=== TOPLAM: {} ===`n`n", this.windows.Length)
        for win in this.windows {
            s .= win.ToString() "`n"
        }
        return s
    }
}