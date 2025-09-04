#Include <key_counter>

class ErrorHandler {
    static instance := ""

    static getInstance(maxErrors := 500) {
        if (!ErrorHandler.instance) {
            ErrorHandler.instance := ErrorHandler(maxErrors)
        }
        return ErrorHandler.instance
    }

    __New(maxErrors) {
        if (ErrorHandler.instance) {
            throw Error("ErrorHandler zaten oluÅŸturulmuÅŸ! getInstance kullan.")
        }
        this.keyCounter := KeyCounter.getInstance()
        this.maxErrors := maxErrors
        this.errorMap := Map()
        this.scriptStartTime := A_Now
    }

    handleError(errorMessage) {
        this.keyCounter.inc("ErrorCount")

        ; Eski hatalarÄ± temizle
        if (this.errorMap.Count > this.maxErrors) {
            this._cleanOldErrors()
        }

        this.errorMap[A_Now] := errorMessage ; Yeni hatayÄ± ekle
        this.showError(errorMessage) ; KullanÄ±cÄ±ya gÃ¶ster
    }


    showError(errorMessage) {
        ;ToolTip("ðŸ’¥ Error: ðŸ‘½`n" errorMessage)         SetTimer(() => ToolTip(), -5000)
        TrayTip("ðŸ’¥ Script Error", errorMessage, 10) ; 10 saniye gÃ¶rÃ¼nÃ¼r, bilgi ikonu
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
        ; En eski hatayÄ± bul ve sil
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

    ; Test iÃ§in hata olustur
    testError(message := "Test Error") {
        this.handleError(message)
    }

}