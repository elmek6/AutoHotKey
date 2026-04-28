class singleClipHist {
    static instance := ""
    static FILE_VERSION := 2

    static getInstance(maxHistory, maxSaveCount, defaultLoadCount := 40) {
        if (!singleClipHist.instance)
            singleClipHist.instance := singleClipHist(maxHistory, maxSaveCount, defaultLoadCount)
        return singleClipHist.instance
    }

    __New(maxHistory, maxSaveCount, defaultLoadCount) {
        if (singleClipHist.instance)
            throw Error("ClipHist zaten oluşturulmuş! getInstance kullan.")
        this.history := []   ; Array of Map {ts, count, text}
        this.maxHistory := maxHistory
        this.maxSaveCount := maxSaveCount
        this.maxByteSize := 1048576  ; 1MB
        this.lastClip := ""
        this.ignoreNextChange := false
        State.Clipboard.setHistory()
        OnClipboardChange(this.clipboardWatcher.Bind(this))
        this._load(defaultLoadCount)
    }

    ; ── Clipboard watcher ────────────────────────────────────────────────────

    clipboardWatcher(Type) {
        if (!State.Clipboard.isHistory())
            return
        if (this.ignoreNextChange) {
            this.ignoreNextChange := false
            return
        }
        if (Type == 0)
            return
        if (Type == 2) {
            ShowTip("⛵")
            return
        }
        local text := A_Clipboard
        ShowTip(text, TipType.Copy)
        if (StrLen(text) = 0)
            return
        if ((StrPut(text, "UTF-8") - 1) > this.maxByteSize)
            return
        if (text = this.lastClip)
            return
        this.addToHistory(text)
    }

    ; ── Runtime history ──────────────────────────────────────────────────────

    addToHistory(text) {
        local textLen := StrLen(text)
        local nowMs := this._nowMs()
        Loop this.history.Length {
            local item := this.history[A_Index]
            if (StrLen(item["text"]) == textLen && item["text"] == text) {
                item["ts"] := nowMs
                item["count"] := item["count"] + 1
                this.history.RemoveAt(A_Index)
                this.history.InsertAt(1, item)
                this.lastClip := text
                return
            }
        }
        this.history.InsertAt(1, Map("ts", nowMs, "count", 1, "text", text))
        if (this.history.Length > this.maxHistory)
            this.history.RemoveAt(this.history.Length)
        this.lastClip := text
    }

    getHistory() {
        return this.history
    }

    getHistoryItem(index) {
        return (index > 0 && index <= this.history.Length) ? this.history[index]["text"] : ""
    }

    clearHistory() {
        choice := MsgBox("Pano geçmişi silinsin mi?", "Onay", "YesNo")
        if (choice = "Yes") {
            this.history := []
            this.lastClip := ""
            ShowTip("Pano geçmişi temizlendi.", TipType.Info, 1500)
        }
    }

    loadFromHistory(index) {
        try {
            if (index > 0 && index <= this.history.Length) {
                this.ignoreNextChange := true
                A_Clipboard := this.history[index]["text"]
                ClipWait(0.1)
                Send("^v")
                return true
            }
            throw Error("Geçmişte " . index . " numaralı kayıt yok.")
        } catch as err {
            App.ErrHandler.handleError("loadFromHistory! History yükleme başarısız: " . err.Message)
            return false
        }
    }

    ; ── Binary I/O ───────────────────────────────────────────────────────────
    ; Format v2:
    ;   Header 20 bytes: [u32 count][u64 local_timestamp_ms][u32 version or reserved][u32 reserved]
    ;   Record 15+N bytes: [u64 local_timestamp_ms][u16 count][u32 byte_length][u8 ~ marker 0x7E][UTF-8 bytes]

    _readRecords(count) {
        local result := []
        if !FileExist(Path.Clipboard)
            return result
        try {
            local file := FileOpen(Path.Clipboard, "r")
            if (!file)
                return result
            local headerBuf := Buffer(20, 0)
            if (file.RawRead(headerBuf, 20) != 20) {
                file.Close()
                return result
            }
            local totalInFile := NumGet(headerBuf, 0, "UInt")
            local version := NumGet(headerBuf, 12, "UInt")
            if (version != singleClipHist.FILE_VERSION) {
                file.Close()
                return result
            }
            local limit := (count == 0) ? totalInFile : Min(count, totalInFile)
            local i := 0
            while (i < limit && !file.AtEOF) {
                local recHdrBuf := Buffer(14, 0)
                if (file.RawRead(recHdrBuf, 14) != 14)
                    break
                local ts := NumGet(recHdrBuf, 0, "UInt64")
                local cnt := NumGet(recHdrBuf, 8, "UShort")
                local byteLen := NumGet(recHdrBuf, 10, "UInt")
                if (byteLen == 0 || byteLen > this.maxByteSize)
                    break
                local markerBuf := Buffer(1, 0)
                if (file.RawRead(markerBuf, 1) != 1)
                    break
                if (NumGet(markerBuf, 0, "UChar") != 0x7E)
                    break
                local textBuf := Buffer(byteLen + 1, 0)
                if (file.RawRead(textBuf, byteLen) != byteLen)
                    break
                result.Push(Map("ts", ts, "count", cnt, "text", StrGet(textBuf, "UTF-8")))
                i++
            }
            file.Close()
        } catch as err {
            App.ErrHandler.handleError("ClipHist._readRecords: " err.Message)
        }
        return result
    }

    _load(count) {
        local items := this._readRecords(count)
        if (items.Length == 0 && FileExist(Path.Clipboard))
            App.ErrHandler.backupOnError("ClipHist", Path.Clipboard)
        Loop items.Length
            this.history.Push(items[A_Index])
        if (this.history.Length > 0)
            this.lastClip := this.history[1]["text"]
    }

    _writeRecord(file, item) {
        local text := item["text"]
        local reqBytes := StrPut(text, "UTF-8") - 1
        local textBuf := Buffer(reqBytes)
        StrPut(text, textBuf, "UTF-8")
        local recHdrBuf := Buffer(14, 0)
        NumPut("UInt64", item["ts"], recHdrBuf, 0)
        NumPut("UShort", item["count"], recHdrBuf, 8)
        NumPut("UInt", reqBytes, recHdrBuf, 10)
        file.RawWrite(recHdrBuf, 14)
        local markerBuf := Buffer(1)
        NumPut("UChar", 0x7E, markerBuf, 0)
        file.RawWrite(markerBuf, 1)
        file.RawWrite(textBuf, reqBytes)
    }

    _save() {
        try {
            local fileItems := this._readRecords(0)
            local combined := []
            Loop this.history.Length
                combined.Push(this.history[A_Index])

            Loop fileItems.Length {
                local candidate := fileItems[A_Index]
                local candidateLen := StrLen(candidate["text"])
                local isDupe := false
                Loop combined.Length {
                    if (StrLen(combined[A_Index]["text"]) == candidateLen && combined[A_Index]["text"] == candidate["text"]) {
                        isDupe := true
                        break
                    }
                }
                if (!isDupe)
                    combined.Push(candidate)
            }

            local writeCount := Min(combined.Length, this.maxSaveCount)
            local file := FileOpen(Path.Clipboard, "w")
            if (!file)
                return

            local headerBuf := Buffer(20, 0)
            NumPut("UInt", writeCount, headerBuf, 0)
            NumPut("UInt64", this._nowMs(), headerBuf, 4)
            NumPut("UInt", singleClipHist.FILE_VERSION, headerBuf, 12)
            file.RawWrite(headerBuf, 20)

            Loop writeCount
                this._writeRecord(file, combined[A_Index])

            file.Close()
        } catch as err {
            App.ErrHandler.handleError("ClipHist._save: " err.Message)
        }
    }

    ; ── Display ──────────────────────────────────────────────────────────────

    buildHistoryMenu() {
        local historyMenu := Menu()
        historyMenu.Add("Search on history", (*) => this.showHistorySearch())
        historyMenu.Add()
        Loop Min(30, this.history.Length) {
            local item := this.history[A_Index]
            this._addClipToMenu(historyMenu, "Clip " . A_Index . ": ", item["text"])
        }
        historyMenu.Add()
        historyMenu.Add("Clear history", this.clearHistory.Bind(this))
        return historyMenu
    }

    showQuickHistoryMenu(maxItems := 9) {
        if (this.history.Length == 0) {
            ShowTip("Geçmiş boş!", TipType.Warning, 800)
            return
        }
        qm := Menu()
        local count := Min(maxItems, this.history.Length)
        Loop count {
            local item := this.history[A_Index]
            local content := item["text"]
            local preview := StrReplace(SubStr(content, 1, 55), "`n", " ")
            if (StrLen(content) > 55)
                preview .= "..."
            qm.Add(A_Index . ": [" . this._formatLabel(item["ts"], item["count"]) . "] " . preview, ((c) => (*) => this._pasteContent(c))(content))
        }
        qm.Add()
        qm.Add("Clipboard History Search", (*) => this.showHistorySearch())
        qm.Show()
    }

    _pasteContent(content) {
        A_Clipboard := content
        ClipWait(0.2)
        SendInput("^v")
        ShowTip(content, TipType.Paste, 600)
    }

    getHistoryPreviewList() {
        if (this.history.Length = 0)
            return ["(Boş)"]
        local previewList := []
        Loop Min(9, this.history.Length) {
            local item := this.history[A_Index]
            local display := StrReplace(SubStr(item["text"], 1, 100), "`n", " ")
            if (StrLen(item["text"]) > 100)
                display .= "..."
            previewList.Push("Clip " . A_Index . ": " . display)
        }
        return previewList
    }

    showHistorySearch() {
        if (this.history.Length == 0) {
            ShowTip("Geçmiş boş!", TipType.Warning, 1500)
            return
        }
        local historyArray := []
        Loop this.history.Length {
            local item := this.history[A_Index]
            historyArray.Push(Map(
                "slotNumber", A_Index,
                "name", this._formatLabel(item["ts"], item["count"]),
                "content", item["text"]
            ))
        }
        ArrayFilter.getInstance().Show(historyArray, "Clipboard History Search")
    }

    ; ── Helpers ──────────────────────────────────────────────────────────────

    _nowMs() {
        return DateDiff(A_Now, "19700101000000", "S") * 1000 + A_MSec
    }

    _formatLabel(tsMs, count) {
        local secs := tsMs // 1000
        local ahkTime := DateAdd("19700101000000", secs, "S")
        local label := SubStr(ahkTime, 7, 2) . "-" . SubStr(ahkTime, 9, 2) . ":" . SubStr(ahkTime, 11, 2)
        if (count > 1)
            label .= ":" . count
        return label
    }

    _addClipToMenu(menu, prefix, text) {
        local display := SubStr(text, 1, 60)
        if (StrLen(text) > 60)
            display .= "..."
        menu.Add(prefix . display, (*) => (A_Clipboard := text, Send("^v")))
    }

    showClipboardPreview() {
        ShowTip(A_Clipboard, TipType.Info)
    }

    __Delete() {
        if (State.Script.getShouldSaveOnExit())
            this._save()
    }
}