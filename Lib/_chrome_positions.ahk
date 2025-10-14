/*
class WindowData {
    __New(index, cleanTitle, x, y, w, h, isMinimized, monitor) {
        this.index := index
        this.cleanTitle := cleanTitle
        this.x := x
        this.y := y
        this.w := w
        this.h := h
        this.isMinimized := isMinimized
        this.monitor := monitor  ; 0 = unknown (minimized - DEĞİŞTİ, artık 0 sadece hata durumunda olmalı)
    }

    ToString() {
        min := this.isMinimized ? "[MIN]" : "[NORMAL]"
        monStr := (this.monitor = 0) ? "[??]" : this.monitor
        pos := Format("Pos: ({}, {}) Size: ({}x{})", this.x, this.y, this.w, this.h)
        titleShort := StrLen(this.cleanTitle) > 40 ? SubStr(this.cleanTitle, 1, 37) "..." : this.cleanTitle
        return Format("#{} Mon:{} {} {}`n    {}", this.index, monStr, min, titleShort, pos)
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


    ; Tüm Chrome pencerelerinin mevcut pozisyonlarını, monitörlerini ve durumlarını kaydeder.
    ; Minimize edilmiş pencerelerin doğru konumunu almak için _GetMonitorFromHwnd içindeki WinRestore kullanılır.

    saveState() {
        debugTime := FormatTime(A_Now, "HH:mm:ss")
        OutputDebug(debugTime . " [DEBUG] saveState başladı.")

        SetTitleMatchMode(2)
        hwndList := WinGetList("ahk_exe chrome.exe")
        this.windows := []
        index := 0
        minimizedCount := 0
        OutputDebug(debugTime . " [DEBUG] Chrome pencere sayısı: " . hwndList.Length)

        ; Tüm monitörleri listele (sadece debug amaçlı)
        Loop MonitorGetCount() {
            MonitorGet(A_Index, &L, &T, &R, &B)
            OutputDebug(debugTime . Format(" [DEBUG] Mon{}: L={} T={} R={} B={}", A_Index, L, T, R, B))
        }

        for hwnd in hwndList {
            debugTime := FormatTime(A_Now, "HH:mm:ss")
            try {
                title := WinGetTitle("ahk_id " hwnd)

                if (title = "") {
                    OutputDebug(debugTime . " [DEBUG] Boş title, atlanıyor")
                    continue
                }
                cleanTitle := RegExReplace(title, " - Google Chrome.*$", "")
                index++
                minMax := WinGetMinMax("ahk_id " hwnd)
                isMinimized := (minMax = -1)

                ; Burası kritik: Monitörü ve gerçek pozisyonu al
                monitor := this._GetMonitorAndPosFromHwnd(hwnd, isMinimized, &x, &y, &w, &h)

                if (isMinimized) minimizedCount++
                    winData := WindowData(index, cleanTitle, x, y, w, h, isMinimized, monitor)
                this.windows.Push(winData)
                OutputDebug(debugTime . " [DEBUG] Kaydedildi: " . winData.ToString())
            } catch as err {
                OutputDebug(debugTime . " [DEBUG] Hata hwnd=" . hwnd . ": " . err.Message)
            }
        }

        ; Kaydetme işlemi
        try {
            jsonData := jsongo.Stringify(this.windows)
            file := FileOpen(AppConst.FILE_POS, "w", "UTF-8")
            if (!file) {
                throw Error(AppConst.FILE_POS . " yazılamadı")
            }
            file.Write(jsonData)
            file.Close()
            OutputDebug(debugTime . " [DEBUG] saveState tamamlandı: " . this.windows.Length . " pencere kaydedildi.")
            MsgBox(Format("Chrome pozisyonları kaydedildi!`nToplam: {} (Minimize: {})", index, minimizedCount), "Pozisyon Kaydedildi")
        } catch as err {
            OutputDebug(debugTime . " [DEBUG] JSON yazma hatası: " . err.Message)
            errHandler.handleError("Chrome positions kaydetme hatası", err)
        }
    }

    ; Diğer metotlar (restore, loadPositions, _MatchByTitle, _MoveToMonitorFullScreen, _GetVisibleWindows)
    ; kullanıcı tarafından sağlandığı şekliyle kalabilir, ancak tam çalışması için jsongo kütüphanesi gereklidir.
    ; Basitlik ve odaklanma için sadece kritik monitör bulma metodunu ekliyorum.


    ; * SADECE minimize edilmiş pencereler için WinRestore yaparak gerçek monitör konumunu bulur.
    ; * x, y, w, h değişkenlerini referans ile doldurur.
    ; * @return Monitör Numarası (1, 2, 3...)

    _GetMonitorAndPosFromHwnd(hwnd, isMinimized, &x, &y, &w, &h) {
        debugTime := FormatTime(A_Now, "HH:mm:ss")

        ; SADECE MINIMIZE EDİLMİŞSE: Konumu bulmak için geri yükle
        if (isMinimized) {
            WinRestore("ahk_id " hwnd)
            Sleep(50) ; Windows'a tepki süresi ver
            OutputDebug(debugTime . " [DEBUG] MINIMIZED: Geçici WinRestore yapıldı.")
        }

        ; Pencere konumunu al (Minimize edilmişse artık doğru konum alınmıştır)
        WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)
        OutputDebug(debugTime . Format(" [DEBUG] Pozisyon: x={}, y={}, w={}, h={}", x, y, w, h))

        ; Monitör Numarasını Hesapla (Pencerenin merkezine göre)
        centerX := x + (w // 2)
        centerY := y + (h // 2)

        mon := 0
        Loop MonitorGetCount() {
            MonitorGet(A_Index, &L, &T, &R, &B)
            if (centerX >= L && centerX < R && centerY >= T && centerY < B) {
                mon := A_Index
                break
            }
        }

        ; Eğer başlangıçta minimize edilmişse: Tekrar minimize et
        if (isMinimized) {
            WinMinimize("ahk_id " hwnd)
            OutputDebug(debugTime . " [DEBUG] MINIMIZED: Tekrar WinMinimize yapıldı.")
        }

        OutputDebug(debugTime . " [DEBUG] Monitör sonucu: " . mon)
        return mon
    }

    ; Aşağıdaki metotlar orijinal kodunuzdan alındı. Eksik dependency'ler (jsongo, errHandler) için yukarıda stub tanımlanmıştır.

    restore() {
        debugTime := FormatTime(A_Now, "HH:mm:ss")
        OutputDebug(debugTime . " [DEBUG] restore başladı. Kaydedilmiş pencere: " . this.windows.Length . " (mon=0 unknown'lar fallback'e gidecek)")

        if (this.windows.Length = 0) {
            OutputDebug(debugTime . " [DEBUG] restore atlandı: Boş windows")
            ToolTip("Kaydedilmiş pozisyon yok.")
            return 0
        }

        SetTitleMatchMode(2)
        currentHwndList := this._GetVisibleWindows("ahk_exe chrome.exe")
        OutputDebug(debugTime . " [DEBUG] Mevcut visible Chrome: " . currentHwndList.Length)
        if (currentHwndList.Length = 0) {
            OutputDebug(debugTime . " [DEBUG] restore atlandı: Mevcut pencere yok")
            ToolTip("Mevcut Chrome penceresi yok.")
            return 0
        }

        matched := 0
        currentIndex := 0
        for savedWin in this.windows {
            debugTime := FormatTime(A_Now, "HH:mm:ss")
            currentIndex++
            OutputDebug(debugTime . " [DEBUG] SavedWin işleniyor: index=" . savedWin.index . ", cleanTitle=" . savedWin.cleanTitle . ", monitor=" . savedWin.monitor . " (0=fallback)")

            matchedHwnd := 0
            targetMonitor := savedWin.monitor
            if (targetMonitor != 0) {
                matchedHwnd := this._MatchByTitle(savedWin.cleanTitle, currentHwndList)
                if (matchedHwnd) {
                    OutputDebug(debugTime . " [DEBUG] Title match bulundu: hwnd=" . matchedHwnd)
                }
            }

            if (!matchedHwnd && currentIndex <= currentHwndList.Length) {
                matchedHwnd := currentHwndList[currentIndex]
                targetMonitor := Mod(savedWin.index - 1, MonitorGetCount()) + 1
                OutputDebug(debugTime . " [DEBUG] Fallback match: hwnd=" . matchedHwnd . ", targetMonitor=" . targetMonitor . " (index-based)")
            }

            if (matchedHwnd) {
                this._MoveToMonitorFullScreen(matchedHwnd, targetMonitor)
                matched++
            } else {
                OutputDebug(debugTime . " [DEBUG] Match/fallback başarısız: index=" . currentIndex)
            }
        }
        OutputDebug(debugTime . " [DEBUG] restore tamamlandı: " . matched . " matched")
        ToolTip(Format("{} pencere restore edildi (unknown mon'lar index'e göre dağıtıldı).", matched))
        return matched
    }

    loadPositions() {
        debugTime := FormatTime(A_Now, "HH:mm:ss")
        OutputDebug(debugTime . " [DEBUG] loadPositions başladı")

        if (!FileExist(AppConst.FILE_POS)) {
            OutputDebug(debugTime . " [DEBUG] loadPositions atlandı: Dosya yok")
            return
        }
        try {
            file := FileOpen(AppConst.FILE_POS, "r", "UTF-8")
            if (!file) {
                throw Error(AppConst.FILE_POS . " okunamadı")
            }
            data := file.Read()
            file.Close()
            OutputDebug(debugTime . " [DEBUG] Dosya okundu, uzunluk: " . StrLen(data))
            parsedMaps := jsongo.Parse(data)
            OutputDebug(debugTime . " [DEBUG] Parse tamamlandı, map sayısı: " . parsedMaps.Length)
            this.windows := []
            for mapData in parsedMaps {
                debugTime := FormatTime(A_Now, "HH:mm:ss")
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
            OutputDebug(debugTime . " [DEBUG] loadPositions tamamlandı: " . this.windows.Length . " pencere yüklendi")
        } catch as err {
            OutputDebug(debugTime . " [DEBUG] Parse hatası: " . err.Message)
            errHandler.handleError("Chrome positions yükleme hatası", err)
        }
    }

    _MatchByTitle(cleanTitle, currentHwndList) {
        debugTime := FormatTime(A_Now, "HH:mm:ss")
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
        debugTime := FormatTime(A_Now, "HH:mm:ss")
        MonitorGetWorkArea(monitorNum, &monL, &monT, &monR, &monB)
        WinRestore("ahk_id " hwnd)
        WinMaximize("ahk_id " hwnd)
        WinMove(monL, monT, monR - monL, monB - monT, "ahk_id " hwnd)
    }

    _GetVisibleWindows(WinTitle) {
        debugTime := FormatTime(A_Now, "HH:mm:ss")
        visibleList := []
        for hwnd in WinGetList(WinTitle) {
            isVisible := DllCall("IsWindowVisible", "Ptr", hwnd)
            title := WinGetTitle("ahk_id " hwnd)
            if isVisible && (title != "") {
                visibleList.Push(hwnd)
            }
        }
        return visibleList
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
*/
