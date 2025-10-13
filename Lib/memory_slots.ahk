class MemorySlotsManager {
    static instance := ""
   
    static getInstance() {
        if (!MemorySlotsManager.instance) {
            MemorySlotsManager.instance := MemorySlotsManager()
        }
        return MemorySlotsManager.instance
    }
   
    __New() {
        if (MemorySlotsManager.instance) {
            throw Error("MemorySlotsManager zaten oluşturulmuş! getInstance kullan.")
        }
       
        ; Slot verilerini başlat
        this.slots := []
        Loop 10 {
            this.slots.Push("")
        }
       
        ; GUI kontrol referansları
        this.slotControls := []
        this.gui := ""
        this.listBox := ""
       
        ; Clipboard history
        this.clipHistory := []
        this.clipListenerActive := false
        this.lastClipContent := ""  ; Tekrar kaydı önlemek için
       
        ; GUI oluştur ve göster
        this._createGui()
        this._setupHotkeys()
        this.gui.Show("x10 y10 w420 h520")
        this._startClipListener()
    }
   
    _createGui() {
        try {
            this.gui := Gui("+AlwaysOnTop +ToolWindow -MinimizeBox", "💾 Hafıza Slotları")
            this.gui.OnEvent("Close", (*) => this._destroy())
            this.gui.OnEvent("Escape", (*) => this._destroy())
            this.gui.SetFont("s9", "Segoe UI")
           
            ; Başlık
            this.gui.Add("Text", "x10 y10 w400 Center", "🔹 F1-F10: Kısa=Slot Yapıştır | Uzun=History Paste 🔹")
           
            ; Copy butonu ekle (tüm slotlara copy için, optional)
            copyBtn := this.gui.Add("Button", "x10 y25 w100 h20", "💾 Slot'a Kopyala")
            copyBtn.OnEvent("Click", (*) => this._copyToSlotPrompt())
           
            ; 10 Slot gösterimi
            Loop 10 {
                slotNum := A_Index
                yPos := 50 + (A_Index - 1) * 26
                fKey := "F" . slotNum
               
                textCtrl := this.gui.Add("Text", "x10 y" . yPos . " w400 h22 Border",
                    fKey . " [Slot " . slotNum . "]: (Boş)")
                textCtrl.SetFont("s8", "Consolas")
                this.slotControls.Push(textCtrl)
            }
           
            ; Clipboard History bölümü
            this.gui.Add("Text", "x10 y320 w400 Center",
                "📋 Clipboard Geçmişi (Çift Tıkla Detay | Uzun F= Paste)")
           
            this.listBox := this.gui.Add("ListBox", "x10 y345 w400 h160")
            this.listBox.OnEvent("DoubleClick", (*) => this._showHistoryDetail())  ; Yeni: Detay aç
           
            ; Transparan ayarı
            WinSetTransparent(220, this.gui.hwnd)
           
        } catch as err {
            errHandler.handleError("GUI oluşturma hatası", err)
        }
    }
   
    _setupHotkeys() {
        Loop 10 {
            num := A_Index
            Hotkey("F" . num, (*) => this._handleSlotPress(num), "On")
        }
    }
   
    _handleSlotPress(slotNum) {
        ; Pencere açıkken çalış (ama global hotkey, her yerden)
        if (!WinExist("ahk_id " . this.gui.hwnd)) {
            return
        }
         
        this._tapOrHold(
            () => this._pasteSlot(slotNum),          ; Kısa basma: Slot yapıştır
            () => this._pasteFromHistory(slotNum),   ; Uzun basma: History'den paste (yeni)
            300,  ; Kısa threshold (ms)
            800   ; Uzun threshold (ms)
        )
    }
   
    ; Kısa basma: Slottan yapıştır
    _pasteSlot(slotNum) {
        if (this.slots[slotNum] == "") {
            this._showTooltip("⚠️ Slot " . slotNum . " boş!")
            return
        }
         
        savedClip := A_Clipboard  ; Mevcut clipboard'u sakla
        A_Clipboard := this.slots[slotNum]
         
        if (ClipWait(0.5)) {
            Send("^v")
            this._showTooltip("✅ Slot " . slotNum . " yapıştırıldı", 1000)
        } else {
            this._showTooltip("❌ Yapıştırma başarısız!")
        }
         
        ; Eski clipboard'u geri yükle
        Sleep(100)
        A_Clipboard := savedClip
    }
   
    ; Yeni: Uzun basma: History'den o numaralı item'ı paste
    _pasteFromHistory(slotNum) {
        if (this.clipHistory.Length < slotNum) {
            this._showTooltip("⚠️ History'de " . slotNum . ". item yok!")
            return
        }
        realIdx := this.clipHistory.Length - slotNum + 1  ; En yeni üstte
        content := this.clipHistory[realIdx]
        if (content == "") {
            this._showTooltip("⚠️ History " . slotNum . " boş!")
            return
        }
        savedClip := A_Clipboard
        A_Clipboard := content
        if (ClipWait(0.5)) {
            Send("^v")
            this._showTooltip("✅ History " . slotNum . " yapıştırıldı", 1000)
        } else {
            this._showTooltip("❌ History paste başarısız!")
        }
        Sleep(100)
        A_Clipboard := savedClip
    }
   
    ; Eski copyToSlot'u buton için ayırdım (prompt ile slot seç)
    _copyToSlotPrompt() {
        input := InputBox("Hangi slota kopyala? (1-10)", "Slot Seç", , "1")
        if (input.Result != "OK" || !IsInteger(input.Value) || input.Value < 1 || input.Value > 10) {
            this._showTooltip("❌ Geçersiz slot!")
            return
        }
        slotNum := input.Value
        this._copyToSlot(slotNum)
    }
   
    ; Uzun basma için eski copy (şimdi butonla)
    _copyToSlot(slotNum) {
        if (A_Clipboard == "") {
            this._showTooltip("⚠️ Clipboard boş!")
            return
        }
        this.slots[slotNum] := A_Clipboard
        this._updateSlotDisplay(slotNum)
        this._showTooltip("💾 Slot " . slotNum . " kaydedildi", 1000)
        SoundBeep(1000, 100)
    }
   
    ; Slot görünümünü güncelle
    _updateSlotDisplay(slotNum) {
        content := this.slots[slotNum]
        fKey := "F" . slotNum
         
        if (content == "") {
            preview := "(Boş)"
        } else {
            ; Tek satır yap ve kısalt
            preview := StrReplace(StrReplace(content, "`r`n", " "), "`n", " ")
            preview := StrReplace(preview, "`t", " ")
            preview := RegExReplace(preview, "\s+", " ")  ; Çoklu boşlukları tek yap
            preview := Trim(preview)
           
            if (StrLen(preview) > 45) {
                preview := SubStr(preview, 1, 45) . "..."
            }
        }
         
        this.slotControls[slotNum].Text := fKey . " [Slot " . slotNum . "]: " . preview
    }
   
    ; Clipboard dinleyici başlat
    _startClipListener() {
        if (!this.clipListenerActive) {
            OnClipboardChange(this._onClipChange.Bind(this))
            this.clipListenerActive := true
            this.lastClipContent := A_Clipboard
        }
    }
   
    ; Clipboard değiştiğinde
    _onClipChange(clipType) {
        if (clipType != 1 || !WinExist("ahk_id " . this.gui.hwnd)) {
            return  ; Sadece text ve pencere açıkken
        }
         
        newClip := A_Clipboard
         
        ; Boş veya aynı içerik ise kaydetme
        if (newClip == "" || newClip == this.lastClipContent) {
            return
        }
         
        this.lastClipContent := newClip
        this.clipHistory.Push(newClip)
         
        ; Max 50 kayıt tut
        if (this.clipHistory.Length > 50) {
            this.clipHistory.RemoveAt(1)
        }
         
        this._refreshHistoryList()
    }
   
    ; History listesini yenile
    _refreshHistoryList() {
        this.listBox.Delete()
         
        ; En yeni üstte göster
        Loop this.clipHistory.Length {
            idx := this.clipHistory.Length - A_Index + 1
            content := this.clipHistory[idx]
           
            ; Önizleme oluştur
            preview := StrReplace(StrReplace(content, "`r`n", " "), "`n", " ")
            preview := RegExReplace(preview, "\s+", " ")
            preview := Trim(preview)
           
            if (StrLen(preview) > 60) {
                preview := SubStr(preview, 1, 60) . "..."
            }
           
            this.listBox.Add("#" . A_Index . ": " . preview)  ; Düzelt: Tek string
        }
    }
   
    ; History detay penceresi
    _showHistoryDetail() {
        sel := this.listBox.Value
        if (!sel || sel < 1 || sel > this.clipHistory.Length) {
            return
        }
         
        ; Liste tersinden seçim yap (en yeni üstte)
        realIdx := this.clipHistory.Length - sel + 1
        content := this.clipHistory[realIdx]
         
        ; Detay GUI
        detailGui := Gui("+AlwaysOnTop +ToolWindow", "📄 Clipboard Detay #" . sel)
        detailGui.SetFont("s9", "Consolas")
         
        ; İçerik gösterimi
        detailGui.Add("Edit", "x10 y10 w500 h300 ReadOnly Multi", content)
         
        ; Bilgi
        detailGui.Add("Text", "x10 y320 w500",
            "Uzunluk: " . StrLen(content) . " karakter | Satırlar: " . StrSplit(content, "`n").Length)
         
        ; Butonlar
        btnPaste := detailGui.Add("Button", "x10 y350 w150 h30", "📋 Yapıştır")
        btnPaste.OnEvent("Click", (*) => (
            A_Clipboard := content,
            ClipWait(0.5),
            Send("^v"),
            detailGui.Destroy(),
            this._showTooltip("✅ Yapıştırıldı", 1000)
        ))
         
        btnCopy := detailGui.Add("Button", "x170 y350 w150 h30", "📄 Kopyala")
        btnCopy.OnEvent("Click", (*) => (
            A_Clipboard := content,
            this._showTooltip("📋 Clipboard'a kopyalandı", 1000)
        ))
         
        btnClose := detailGui.Add("Button", "x330 y350 w150 h30", "❌ Kapat")
        btnClose.OnEvent("Click", (*) => detailGui.Destroy())
         
        detailGui.OnEvent("Close", (*) => detailGui.Destroy())
        detailGui.OnEvent("Escape", (*) => detailGui.Destroy())
         
        detailGui.Show("w520 h400")
    }
   
    ; Tooltip yardımcı fonksiyon
    _showTooltip(msg, duration := 1200) {
        ToolTip(msg, , , 1)
        SetTimer(() => ToolTip(), -duration)
    }
   
    ; Basitleştirilmiş TapOrHold
    _tapOrHold(shortFn, longFn, shortTime, longTime) {
        startTime := A_TickCount
        key := A_ThisHotkey
         
        ; Bip sayacı
        beepDone := false
         
        ; Tuş basılı kaldığı sürece bekle
        while (GetKeyState(key, "P")) {
            elapsed := A_TickCount - startTime
           
            ; Uzun basma eşiğine ulaşınca bir kez bip
            if (elapsed >= longTime && !beepDone) {
                SoundBeep(800, 80)
                beepDone := true
            }
           
            Sleep(20)  ; Düzelt: Daha responsive
        }
         
        ; Tuş bırakıldığında toplam süreye göre karar ver
        elapsed := A_TickCount - startTime
         
        if (elapsed < longTime) {
            shortFn.Call()  ; Kısa basma
        } else {
            longFn.Call()   ; Uzun basma
        }
    }
   
    ; Temizlik
    _destroy() {
        ; Hotkey'leri kapat
        Loop 10 {
            try {
                Hotkey("F" . A_Index, "Off")
            }
        }
         
        ; Clipboard listener'ı durdur
        OnClipboardChange(this._onClipChange.Bind(this), 0)
        this.clipListenerActive := false
         
        ; GUI'yi yok et
        if (this.gui) {
            this.gui.Destroy()
        }
         
        ; Singleton'ı sıfırla
        MemorySlotsManager.instance := ""
    }
}