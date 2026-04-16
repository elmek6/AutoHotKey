class singleBigClipHist {
    static instance := ""

    static getInstance() {
        if (!singleBigClipHist.instance)
            singleBigClipHist.instance := singleBigClipHist()
        return singleBigClipHist.instance
    }

    __New() {
        if (singleBigClipHist.instance)
            throw Error("BigClipHist zaten oluşturulmuş! getInstance kullan.")
        this.bigClips := []
        this.maxItems := 2500
        this.maxByteSize := 1048576  ; 1MB
    }

    addClip(text) {
        local byteLen := StrPut(text, "UTF-8") - 1
        if (byteLen > this.maxByteSize)
            return
        local textLen := StrLen(text)
        Loop this.bigClips.Length {
            if (StrLen(this.bigClips[A_Index]) == textLen && this.bigClips[A_Index] == text) {
                this.bigClips.RemoveAt(A_Index)
                break
            }
        }
        this.bigClips.Push(text)
        if (this.bigClips.Length > this.maxItems)
            this.bigClips.RemoveAt(1)
    }

    saveAndLoad() {
        this._loadAndMerge()
        this._save()
    }

    _loadAndMerge() {
        if !FileExist(Path.BigClips)
            return
        try {
            local file := FileOpen(Path.BigClips, "r")
            if (!file)
                return
            while (!file.AtEOF) {
                local lenBuf := Buffer(4, 0)
                if (file.RawRead(lenBuf, 4) != 4)
                    break
                local byteLen := NumGet(lenBuf, 0, "UInt")
                if (byteLen == 0 || byteLen > this.maxByteSize)
                    break
                local textBuf := Buffer(byteLen + 1, 0)
                if (file.RawRead(textBuf, byteLen) != byteLen)
                    break
                local text := StrGet(textBuf, "UTF-8")
                local textLen := StrLen(text)
                local isDupe := false
                Loop this.bigClips.Length {
                    if (StrLen(this.bigClips[A_Index]) == textLen && this.bigClips[A_Index] == text) {
                        isDupe := true
                        break
                    }
                }
                if (!isDupe)
                    this.bigClips.Push(text)
            }
            file.Close()
            while (this.bigClips.Length > this.maxItems)
                this.bigClips.RemoveAt(1)
        } catch as err {
            App.ErrHandler.handleError("BigClipHist._loadAndMerge: " err.Message)
        }
    }

    _save() {
        try {
            local file := FileOpen(Path.BigClips, "w")
            if (!file)
                return
            Loop this.bigClips.Length {
                local text := this.bigClips[A_Index]
                local reqBytes := StrPut(text, "UTF-8")
                local buf := Buffer(reqBytes)
                StrPut(text, buf, "UTF-8")
                local lenBuf := Buffer(4)
                NumPut("UInt", reqBytes - 1, lenBuf, 0)
                file.RawWrite(lenBuf, 4)
                file.RawWrite(buf, reqBytes - 1)
            }
            file.Close()
        } catch as err {
            App.ErrHandler.handleError("BigClipHist._save: " err.Message)
        }
    }

    showSearch() {
        this.saveAndLoad()
        if (this.bigClips.Length == 0) {
            ShowTip("Büyük clip geçmişi boş!", TipType.Warning, 1500)
            return
        }
        local histArray := []
        Loop this.bigClips.Length {
            local reverseIndex := this.bigClips.Length - A_Index + 1
            local text := this.bigClips[reverseIndex]
            histArray.Push(Map(
                "slotNumber", A_Index,
                "name", "Big " A_Index " (" StrLen(text) "c)",
                "content", text
            ))
        }
        ArrayFilter.getInstance().Show(histArray, "Big Clip Deep Search")
    }

    __Delete() {
        if (State.Script.getShouldSaveOnExit())
            this.saveAndLoad()
    }
}
