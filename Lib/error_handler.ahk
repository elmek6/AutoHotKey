#Include <key_counter>

class singleErrorHandler {
    static instance := ""

    static getInstance(maxErrors := 500) {
        if (!singleErrorHandler.instance) {
            singleErrorHandler.instance := singleErrorHandler(maxErrors)
        }
        return singleErrorHandler.instance
    }

    __New(maxErrors) {
        if (singleErrorHandler.instance) {
            throw Error("ErrorHandler zaten oluşturulmuş! getInstance kullan.")
        }
        this.keyCounter := singleKeyCounter.getInstance()
        this.maxErrors := maxErrors
        this.errorMap := Map()
        this.scriptStartTime := A_Now
        this.lastFullError := ""  ; Yeni: Son hatanın tam detaylarını tutacak string
    }

    handleError(errorMessage, err := unset) {
        this.keyCounter.inc("ErrorCount")

        ; Eski hataları temizle
        if (this.errorMap.Count > this.maxErrors) {
            this._cleanOldErrors()
        }

        this.errorMap[A_Now] := errorMessage

        if (IsSet(err) && IsObject(err)) {
            this.lastFullError := this._formatFullError(err, errorMessage)
        } else {
            ; err yoksa, sadece mesajı lastFullError olarak ata (geriye uyumluluk için)
            this.lastFullError := errorMessage
        }
        OutputDebug (this.lastFullError)

        this.showError(errorMessage)
    }


    showError(errorMessage) {
        TrayTip("Script Error", errorMessage, 10)
    }

    copyLastError() {
        if (this.lastFullError == "") {
            MsgBox("Son hata bilgisi yok!")
            return
        }
        A_Clipboard := this.lastFullError
        MsgBox(this.lastFullError, "Son Hata Detayları (Panoya Kopyalandı)", "OK Iconi")
    }
    ; Yeni: Hatayı formatla (Message, What, File, Line, Stack vs.)
    _formatFullError(err, customMessage := "") {
        formatted := (customMessage ? customMessage : err.Message) . "`n"
        formatted .= "WHAT: " . (err.What ? err.What : "N/A") . "`n"
        formatted .= "EXTRA: " . (err.Extra ? err.Extra : "N/A") . "`n"
        formatted .= "FILE: " . (err.File ? err.File : "N/A") . "`n"
        formatted .= "LINE: " . (err.Line ? err.Line : "N/A") . "`n"
        formatted .= "STACK TRACE:`n" . (err.Stack ? err.Stack : "N/A")
        return formatted
    }

    getRecentErrors(limit := 0, sinceTime := "") {
        if (sinceTime == "") {
            sinceTime := this.scriptStartTime
        }

        recentErrors := "Errors:`n"
        hasErrors := false
        count := 0

        for timestamp, message in this.errorMap {
            if (timestamp > sinceTime) {
                if (limit == 0 || count < limit) {
                    formattedTimestamp := FormatTime(timestamp, "dd HH:mm:ss")
                    recentErrors .= formattedTimestamp ": " message "`n"
                    hasErrors := true
                    count++
                }
            }
        }

        return hasErrors ? recentErrors : ""
    }

    getAllErrors() {
        return this.errorMap
    }

    getErrorCount() {
        return this.keyCounter.get("ErrorCount")
    }

    clearErrors() {
        this.errorMap.Clear()
        this.keyCounter.set("ErrorCount", 0)
    }

    _cleanOldErrors() {
        oldest := ""
        for timestamp, _ in this.errorMap {
            if (!oldest || timestamp < oldest) {
                oldest := timestamp
            }
        }
        if (oldest != "") {
            this.errorMap.Delete(oldest)
        }
    }

    ; Test için hata oluştur
    testError(message := "Test Error") {
        this.handleError(message)
    }

    backupOnError(title, filePath) {
        errorMsg := filePath . ": dosyada okuma hatası oldu, baska isimle yedeklendi "
        try {
            timestamp := FormatTime(A_Now, "dd-MM_HHmmss")
            backupPath := filePath . "." . timestamp
            FileMove(filePath, backupPath, 1)
            this.handleError(title . " Dosya yedeklendi (" . backupPath . ")")
            OutputDebug(errorMsg)
            MsgBox(errorMsg, title, "OK Iconi")
        } catch as err {
            MsgBox(errorMsg, title . " Yedekleme başarısız", "OK Iconi")
            this.handleError(title . " Yedekleme başarısız: " . err.Message, err)
        }
    }
}