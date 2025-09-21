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
            throw Error("ErrorHandler zaten oluşturulmuş! getInstance kullan.")
        }
        this.keyCounter := KeyCounter.getInstance()
        this.maxErrors := maxErrors
        this.errorMap := Map()
        this.scriptStartTime := A_Now
        this.lastFullError := ""  ; Yeni: Son hatanın tam detaylarını tutacak string
    }

    ; Mevcut handleError'ı genişletiyoruz: Artık opsiyonel 'err' parametresi ekliyoruz
    ; Eğer 'err' nesnesi geçilirse (try-catch'ten), full detayları lastFullError'a ata
    ; Yoksa sadece mesajı kullan
    handleError(errorMessage, err := unset) {
        this.keyCounter.inc("ErrorCount")

        ; Eski hataları temizle
        if (this.errorMap.Count > this.maxErrors) {
            this._cleanOldErrors()
        }

        this.errorMap[A_Now] := errorMessage ; Yeni hatayı ekle
        
        ; Eğer err nesnesi varsa, full detayları hazırla ve sakla
        if (IsSet(err) && IsObject(err)) {
            this.lastFullError := this._formatFullError(err, errorMessage)
        } else {
            ; err yoksa, sadece mesajı lastFullError olarak ata (geriye uyumluluk için)
            this.lastFullError := errorMessage
        }
        OutputDebug (this.lastFullError)

        this.showError(errorMessage) ; Kullanıcıya göster
    }


    showError(errorMessage) {
        ;ToolTip("ðŸ’¥ Error: ðŸ‘½`n" errorMessage)         SetTimer(() => ToolTip(), -5000)
        TrayTip("ðŸ’¥ Script Error", errorMessage, 10) ; 10 saniye gÃ¶rÃ¼nÃ¼r, bilgi ikonu
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