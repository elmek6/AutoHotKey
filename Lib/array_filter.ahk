class ArrayFilter {
    static instance := ""
    
    myGui := ""
    listView := ""
    searchBox := ""
    previewBox := ""
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
    }

    __Delete() {
        this.Cleanup()
    }

    Cleanup() {
        ; 1. Mesaj Dinlemeyi Durdur (En Kritik Adım)
        ; DÜZELTME: instance method kullan, static değil
        try OnMessage(0x200, ObjBindMethod(this, "OnMouseHover"), 0)

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

        CreateHotkeyHandler(fKeyIndex) {
            return (*) => this.SelectByFKey(fKeyIndex)
        }

        Loop 12 {
            try Hotkey("F" A_Index, sw ? CreateHotkeyHandler(A_Index) : "", mode)
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
            
            ; Listenin sınırları içinde mi?
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
        try this.listView.Opt("-Redraw")
        this.listView.Delete()
        this.results := []
        this.lastTopIndex := -1
        this.lastHoveredRow := -1 ; Liste değişince hover resetlenmeli

        for slot in this.arrayData {
            local contentPreview := SubStr(slot["content"], 1, 120)
            if (StrLen(slot["content"]) > 120)
                contentPreview .= "..."
            
            if (!search || InStr(StrLower(slot["name"]), StrLower(search)) || InStr(StrLower(slot["content"]), StrLower(search))) {
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
        this.UpdateVisibleLabels()
    }

    UpdatePreviewContent(rowIndex) {
        if (rowIndex > 0 && rowIndex <= this.results.Length) {
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
        this.results := []
        this.lastTopIndex := -1
        this.lastHoveredRow := -1

        ; Genişlik: Ekranın %50'si
        local guiWidth := A_ScreenWidth * 0.40
        this.myGui := Gui("+AlwaysOnTop +ToolWindow", title)
        this.myGui.SetFont("s10", "Segoe UI")
        this.searchBox := this.myGui.AddEdit("x10 y10 w" . (guiWidth - 20), "")        
        ; r12: Sabit 12 satır yüksekliği
        this.listView := this.myGui.AddListView("x10 y+10 w" . (guiWidth - 20) . " r12 Grid -Multi Count100", ["F#", "İsim", "İçerik"])
        this.previewBox := this.myGui.AddEdit("x10 y+10 w" . (guiWidth - 20) . " h100 ReadOnly Multi +VScroll", "")
        ; Kolon Genişlikleri
        this.listView.ModifyCol(1, 40)              ; F#
        this.listView.ModifyCol(2, guiWidth * 0.08) ; İsim
        this.listView.ModifyCol(3, guiWidth * 0.80) ; İçerik (Geriye kalanı kapla)
        ; --- EVENTLER ---
        this.searchBox.OnEvent("Change", (*) => this.UpdateList())
        this.listView.OnEvent("DoubleClick", (*) => this.SelectFocused())
        this.listView.OnEvent("ItemSelect", (guiCtrl, item, selected) => selected ? this.UpdatePreviewContent(item) : "")
        this.myGui.OnEvent("Escape", (*) => (this.searchBox.Value ? (this.searchBox.Value := "", this.UpdateList()) : this.closeGuiAndHotkeys()))
        this.myGui.OnEvent("Close", (*) => this.closeGuiAndHotkeys())

        ; YÖN TUŞLARI
        Hotkey("Up", (*) => this.MoveSelection(-1), "On")
        Hotkey("Down", (*) => this.MoveSelection(1), "On")

        ; MOUSE HOVER - Her Show() çağrısında yeniden kaydet
        ; ObjBindMethod ile instance method'a bağla
        OnMessage(0x200, ObjBindMethod(this, "OnMouseHover"))

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