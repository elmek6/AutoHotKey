class ArrayFilter {
    static instance := ""
    ; Arama modu diyalog örnekleri arasında korunur. Instance alanına koysaydık
    ; Cleanup() her kapanışta instance'ı öldürdüğü için mod sıfırlanırdı.
    static lastMode := 1        ; 1=Metin  2=Joker  3=RegExp
    static hoverPreview := true ; fare ile gezerken önizleme (oturum boyu kalıcı)

    myGui := ""
    listView := ""
    searchBox := ""
    previewBox := ""
    caseChk := ""
    hoverChk := ""
    modeDdl := ""
    baseTitle := ""
    patternError := false
    CheckFocus := ""
    results := []
    arrayData := []
    lastTopIndex := -1
    lastHoveredRow := -1  ; Flicker önlemek için

    static getInstance() {
        if (!ArrayFilter.instance) {
            ArrayFilter.instance := ArrayFilter()
        }
        return ArrayFilter.instance
    }

    __New() {
        if (ArrayFilter.instance) {
            throw Error("ArrayFilter zaten oluşturulmuş! getInstance kullan.")
        }
        ; OnMessage kayıt VE kaldırma aynı nesneyle yapılmalı — her seferinde yeni
        ; ObjBindMethod üretmek kaldırmayı sessizce başarısız kılıp handler biriktiriyordu
        this._hoverHandler := ObjBindMethod(this, "OnMouseHover")
    }

    __Delete() {
        this.Cleanup()
    }

    Cleanup() {
        ; 1. Mesaj dinlemeyi durdur (EN KRİTİK ADIM). Kaldırma, kayıtta
        ;    kullanılan AYNI nesneyle yapılmalı — bu yüzden this._hoverHandler
        ;    saklanıyor; her seferinde yeni bir bound üretmek sessizce
        ;    başarısız olup handler biriktiriyordu.
        try OnMessage(0x200, this._hoverHandler, 0)

        ; 2. Timer'ları durdur
        if (this.CheckFocus) {
            SetTimer this.CheckFocus, 0
            this.CheckFocus := ""
        }

        ; 3. Hotkeyleri kapat
        this.changeHotKeyMode(false)
        try Hotkey("Up", "Off")
        try Hotkey("Down", "Off")

        ; 4. GUI'yi yok et
        if (this.myGui) {
            try this.myGui.Destroy()
            this.myGui := ""
        }

        ; 5. Static Instance'ı öldür
        ArrayFilter.instance := ""
    }

    closeGuiAndHotkeys() {
        this.Cleanup()
    }

    sendText(text) {
        A_Clipboard := text
        Sleep(50)
        SendInput("^v")
    }

    changeHotKeyMode(sw) {
        mode := sw ? "On" : "Off"

        ; Enter ve NumpadEnter
        try Hotkey("Enter", sw ? (*) => this.SelectFocused() : "", mode)
        try Hotkey("NumpadEnter", sw ? (*) => this.SelectFocused() : "", mode)

        Loop 12 {
            ; IIFE: kod tabanındaki ortak closure-yakalama deyimi
            try Hotkey("F" A_Index, sw ? ((i) => (*) => this.SelectByFKey(i))(A_Index) : "", mode)
        }
    }

    ; --- SEÇİM MANTIĞI ---
    SelectFocused() {
        if (!this.listView)
            return
        focusedRow := this.listView.GetNext(0, "F")
        if (focusedRow > 0)
            this.SelectAndClose(focusedRow)
    }

    SelectByFKey(fKeyIndex) {
        if (!this.listView)
            return

        ; LVM_GETTOPINDEX (0x1027): En üstteki görünür satırın indexini (0-based) verir.
        ; AHK Listview 1-based olduğu için, matematik şu:
        ; TopIndex(0-based) + F_Tuşu(1-based) = HedefSatır(1-based)

        try {
            topIndex := SendMessage(0x1027, 0, 0, this.listView.Hwnd)
            targetIndex := topIndex + fKeyIndex

            if (targetIndex <= this.results.Length) {
                this.SelectAndClose(targetIndex)
            }
        }
    }

    SelectAndClose(index) {
        if (index < 1 || index > this.results.Length)
            return

        local selectedSlot := this.results[index]
        this.closeGuiAndHotkeys()
        Sleep(50)
        this.sendText(selectedSlot["content"])
    }

    UpdateList() {
        local search := this.searchBox.Value
        this.patternError := false
        try this.listView.Opt("-Redraw")
        this.listView.Delete()
        this.results := []
        this.lastTopIndex := -1
        this.lastHoveredRow := -1 ; Liste değişince hover resetlenmeli

        for slot in this.arrayData {
            local contentPreview := SubStr(slot["content"], 1, 120)
            if (StrLen(slot["content"]) > 120)
                contentPreview .= "..."

            if (this.MatchItem(search, slot)) {
                this.listView.Add("", "", slot["name"], contentPreview)
                this.results.Push(slot)
            }
        }

        ; İlk satırı seçili yap
        if (this.results.Length > 0) {
            this.listView.Modify(1, "Select Focus")
            this.UpdatePreviewContent(1)
        } else {
            this.previewBox.Value := ""
        }
        try this.listView.Opt("+Redraw")
        this._updateTitle()
        this.UpdateVisibleLabels()
    }

    ; Sonuç sayısı / pattern hatası pencere başlığında gösterilir.
    ; DİKKAT: WatchDog() WinActive(this.myGui.Title) ile odak kontrolü yapıyor;
    ; başlığı değiştirdiğimiz için orada SABİT bir başlık cache'lenmemeli —
    ; myGui.Title her çağrıda taze okunduğu sürece sorun yok.
    _updateTitle() {
        if (!this.myGui)
            return
        local suffix := this.patternError ? " (pattern?)" : " (" this.results.Length ")"
        try this.myGui.Title := this.baseTitle suffix
    }

    ; Arama eşleştirme: mod DDL'i + Case checkbox'ına göre davranır.
    ; Üç mod BİRBİRİNİ DIŞLADIĞI için checkbox değil dropdown: iki checkbox'la
    ; "RegExp + Joker ikisi de işaretli" gibi geçersiz durum oluşuyor ve kodda
    ; bastırmak gerekiyordu. Case ortogonal (üç modla da birleşir) → checkbox kaldı.
    MatchItem(search, slot) {
        if (!search)
            return true
        local caseSensitive := this.caseChk.Value
        local mode := this.modeDdl.Value

        if (mode == 1)   ; düz metin
            return InStr(slot["name"], search, caseSensitive) || InStr(slot["content"], search, caseSensitive)

        local pattern := (mode == 2) ? this._wildToRegex(search) : search
        ; Joker modunda ek "s" (DOTALL) bayragi: PCRE'de "." varsayilan olarak
        ; SATIR SONUNU eslestirmez, oysa pano kayitlarinin cogu cok satirli.
        ; Onsuz "SELECT*FROM" iki ayri satirdaki kelimeleri bulamazdi.
        ; RegExp modunda EKLENMEZ: orada bayragi kullanici kendi yazar.
        local flags := (caseSensitive ? "" : "i") (mode == 2 ? "s" : "")
        local opts := (flags == "") ? "" : flags ")"
        try {
            return RegExMatch(slot["name"], opts pattern) || RegExMatch(slot["content"], opts pattern)
        } catch {
            ; Geçersiz pattern: kullanıcı yazmayı bitirene kadar eşleşme yok.
            ; Bayrak başlıkta "(pattern?)" göstermek için — eskiden sessizce 0 sonuç
            ; dönüyordu ve "kayıt mı yok, pattern mi bozuk" ayırt edilemiyordu.
            this.patternError := true
            return false
        }
    }

    ; Joker (* ve ?) → regex çevirisi.
    ; SIRA KRİTİK: önce TÜM regex metakarakterleri kaçırılır, SONRA yalnız joker
    ; olan ikisi geri açılır. Ters yapılırsa kullanıcının yazdığı "." de joker olur.
    ; Bilerek anchor YOK: arama kutusu semantiği alt-dize aramasıdır, yani
    ; "abc*def" metnin ortasında da eşleşmeli (^...$ eklersek tam eşleşme olurdu).
    _wildToRegex(pat) {
        local esc := RegExReplace(pat, "([\\.^$|()\[\]{}*+?\/-])", "\$1")
        esc := StrReplace(esc, "\*", ".*")
        esc := StrReplace(esc, "\?", ".")
        return esc
    }

    UpdatePreviewContent(rowIndex) {
        if (!this.listView)
            return
        if (rowIndex < 1 || rowIndex > this.results.Length)
            try rowIndex := this.listView.GetNext(0, "F")   ; -1/0 geldiyse odağa sor
        if (rowIndex > 0 && rowIndex <= this.results.Length) {
            this.lastHoveredRow := rowIndex                 ; hover bunu ezmesin
            try this.previewBox.Value := this.results[rowIndex]["content"]
        }
    }

    UpdateVisibleLabels() {
        if (!this.listView)
            return

        try {
            if !WinExist("ahk_id " . this.listView.Hwnd)
                return

            ; LVM_GETTOPINDEX + 1 (AHK 1-based uyumu için)
            currentTop := SendMessage(0x1027, 0, 0, this.listView.Hwnd) + 1

            if (currentTop == this.lastTopIndex)
                return

            this.listView.Opt("-Redraw")

            ; 1. Önceki F yazılarını temizle
            if (this.lastTopIndex != -1) {
                Loop 12 {
                    rIdx := this.lastTopIndex + (A_Index - 1)
                    if (rIdx <= this.results.Length)
                        this.listView.Modify(rIdx, "Col1", "")
                }
            }

            ; 2. Yeni F yazılarını ekle
            Loop 12 {
                rIdx := currentTop + (A_Index - 1)
                if (rIdx <= this.results.Length)
                    this.listView.Modify(rIdx, "Col1", "F" . A_Index)
            }

            this.lastTopIndex := currentTop
            this.listView.Opt("+Redraw")
        }
    }

    Show(arrayData, title) {
        ; Her ihtimale karşı temiz başla
        if (this.myGui)
            this.Cleanup()

        this.arrayData := arrayData
        this.baseTitle := title
        this.results := []
        this.lastTopIndex := -1
        this.lastHoveredRow := -1

        ; Genişlik: Ekranın %50'si
        local guiWidth := A_ScreenWidth * 0.40
        this.myGui := Gui("+AlwaysOnTop +ToolWindow", title)
        this.myGui.SetFont("s10", "Segoe UI")
        this.searchBox := this.myGui.AddEdit("x10 y10 w" . (guiWidth - 20 - 185), "")
        this.caseChk := this.myGui.AddCheckbox("x+10 yp+4 w60", "Case")
        ; yp-4: checkbox Edit'e göre 4px indirilmişti, DDL daha uzun olduğu için geri alınıyor
        this.modeDdl := this.myGui.AddDropDownList("x+5 yp-4 w110 Choose" . ArrayFilter.lastMode,
            ["Metin", "Joker *?", "RegExp"])
        ; r12: Sabit 12 satır yüksekliği
        this.listView := this.myGui.AddListView("x10 y+10 w" . (guiWidth - 20) . " r12 Grid -Multi Count100", ["F#", "İsim", "İçerik"])
        this.hoverChk := this.myGui.AddCheckbox("x10 y+8", "Hover preview")
        this.hoverChk.Value := ArrayFilter.hoverPreview ? 1 : 0
        this.previewBox := this.myGui.AddEdit("x10 y+6 w" . (guiWidth - 20) . " h150 ReadOnly Multi +VScroll", "")
        this.listView.ModifyCol(1, 40)              ; F#
        this.listView.ModifyCol(2, guiWidth * 0.18) ; İsim (grup-slotAdı sığsın)
        this.listView.ModifyCol(3, guiWidth * 0.70) ; İçerik (Geriye kalanı kapla)
        ; --- EVENTLER ---
        this.searchBox.OnEvent("Change", (*) => this.UpdateList())
        this.caseChk.OnEvent("Click", (*) => this.UpdateList())
        this.hoverChk.OnEvent("Click", (*) => (ArrayFilter.hoverPreview := !!this.hoverChk.Value))
        this.modeDdl.OnEvent("Change", (*) => (ArrayFilter.lastMode := this.modeDdl.Value, this.UpdateList()))
        this.listView.OnEvent("DoubleClick", (*) => this.SelectFocused())
        this.listView.OnEvent("ItemSelect", (guiCtrl, item, selected) => selected ? this.UpdatePreviewContent(item) : "")
        this.listView.OnEvent("Click", (guiCtrl, item) => this.UpdatePreviewContent(item))
        this.myGui.OnEvent("Escape", (*) => (this.searchBox.Value ? (this.searchBox.Value := "", this.UpdateList()) : this.closeGuiAndHotkeys()))
        this.myGui.OnEvent("Close", (*) => this.closeGuiAndHotkeys())

        ; YÖN TUŞLARI
        Hotkey("Up", (*) => this.MoveSelection(-1), "On")
        Hotkey("Down", (*) => this.MoveSelection(1), "On")

        ; MOUSE HOVER - Her Show() çağrısında yeniden kaydet
        ; ObjBindMethod ile instance method'a bağla (__New'de bir kez oluşturuldu)
        OnMessage(0x200, this._hoverHandler)

        this.changeHotKeyMode(true)
        this.UpdateList()
        this.myGui.Show("AutoSize")
        this.CheckFocus := (*) => this.WatchDog()
        SetTimer this.CheckFocus, 50
    }

    MoveSelection(direction) {
        if (!this.listView)
            return
        try {
            currentRow := this.listView.GetNext(0, "F")
            newRow := currentRow + direction
            if (newRow > 0 && newRow <= this.results.Length) {
                this.listView.Modify(currentRow, "-Select")
                this.listView.Modify(newRow, "Select Focus Vis")
                this.UpdatePreviewContent(newRow)
            }
        }
    }

    WatchDog() {
        if (!this.myGui)
            return
        if (this.myGui.Title && !WinActive(this.myGui.Title)) {
            this.closeGuiAndHotkeys()
            return
        }
        this.UpdateVisibleLabels()
    }

    OnMouseHover(wParam, lParam, msg, hwnd) {
        ; Güvenlik: GUI veya Listview yoksa çık
        if (!this.myGui || !IsObject(this.listView))
            return

        try {
            if (hwnd != this.listView.Hwnd)
                return
        } catch {
            return
        }
        if (!ArrayFilter.hoverPreview)
            return
        MouseGetPos(&mouseX, &mouseY)

        ; Koordinat Hesabı
        try WinGetPos(&winX, &winY, , , this.listView.Hwnd)
        catch
            return

        relX := mouseX - winX
        relY := mouseY - winY
        pointBuf := Buffer(24, 0)
        NumPut("Int", relX, "Int", relY, pointBuf)

        try {
            ; 0-based index döner, -1 boşluktur
            rowIndex := SendMessage(0x1012, 0, pointBuf, this.listView.Hwnd)
            ; Eğer satır geçerliyse VE (önemli) son baktığımız satırdan farklıysa güncelle
            ; Bu sayede flicker (titreme) engellenir.
            if (rowIndex != -1 && rowIndex < this.results.Length) {
                targetRow := rowIndex + 1 ; 1-based yap
                if (targetRow != this.lastHoveredRow) {
                    this.UpdatePreviewContent(targetRow)
                    this.lastHoveredRow := targetRow
                }
            }
        }
    }
}