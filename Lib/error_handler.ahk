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

    handleError(errorMessage, err := unset, writeNow := false) {
        this.keyCounter.inc("ErrorCount")

        ; Eski hataları temizle
        if (this.errorMap.Count > this.maxErrors) {
            this._cleanOldErrors()
        }

        this.errorMap[FormatTime(A_Now, "yyyy_MM_dd-HH_mm_ss") "_" Format("{:03}", A_MSec)] := errorMessage

        if (IsSet(err) && IsObject(err)) {
            this.lastFullError := this._formatFullError(err, errorMessage)
        } else {
            ; err yoksa, sadece mesajı lastFullError olarak ata (geriye uyumluluk için)
            this.lastFullError := errorMessage
        }
        OutputDebug(this.lastFullError)
        if (writeNow)
            this._logNow(this.lastFullError)
        this.showError(errorMessage)
    }

    ; Kritik hatayı anında log.txt'e yazar (kapanış beklenmez)
    ; Format: yyyy_MM_dd-HH_mm_ss_mmm=message
    _logNow(message) {
        local line := FormatTime(A_Now, "yyyy_MM_dd-HH_mm_ss") "_" Format("{:03}", A_MSec) "=" message "`n"
        try {
            FileAppend(line, Path.Log, "UTF-8")
        } catch as err {
            OutputDebug("_logNow: dosyaya yazılamadı [" Path.Log "]: " err.Message "`n")
            TrayTip("Log Hatası", "Kritik hata dosyaya yazılamadı: " err.Message, 5)
        }
    }


    showError(errorMessage) {
        TrayTip("Script Error", errorMessage, 10)
    }

    copyLastError() {
        if (this.lastFullError == "") {
            ShowTip("Son hata bilgisi yok!", TipType.Warning, 2000)            
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
            sinceTime := FormatTime(this.scriptStartTime, "yyyy_MM_dd-HH_mm_ss") "_000"
        }

        recentErrors := "Errors:`n"
        hasErrors := false
        count := 0

        for timestamp, message in this.errorMap {
            if (StrCompare(timestamp, sinceTime) > 0) {
                if (limit == 0 || count < limit) {
                    recentErrors .= timestamp ": " message "`n"
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
        ; Map insertion order = ekleme sırası → ilk 20 kayıt en eskiler. Önce topla, sonra sil.
        local toRemove := []
        for ts, _ in this.errorMap {
            if (toRemove.Length >= 20)
                break
            toRemove.Push(ts)
        }
        for ts in toRemove
            this.errorMap.Delete(ts)
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

; ═══════════════════════════════════════════════════════════
; FileIO — Güvenli dosya yazma yardımcıları.
; writeText/writeBinary: önce .tmp'ye yaz, sonra rename (OS-atomik aynı diskte).
; Yarıda kalan yazımda hedef dosya bozulmaz.
; ═══════════════════════════════════════════════════════════
class FileIO {
    static writeText(targetPath, content, encoding := "UTF-8") {
        local tmpPath := targetPath ".tmp"
        local file := FileOpen(tmpPath, "w", encoding)
        if (!file)
            throw Error("FileIO.writeText: dosya açılamadı: " tmpPath)
        file.Write(content)
        file.Close()
        if (FileExist(targetPath))
            FileDelete(targetPath)
        FileMove(tmpPath, targetPath, 1)
    }

    static writeBinary(targetPath, writeCallback) {
        local tmpPath := targetPath ".tmp"
        local file := FileOpen(tmpPath, "w")
        if (!file)
            throw Error("FileIO.writeBinary: dosya açılamadı: " tmpPath)
        try {
            writeCallback.Call(file)
        } finally {
            file.Close()
        }
        if (FileExist(targetPath))
            FileDelete(targetPath)
        FileMove(tmpPath, targetPath, 1)
    }
}