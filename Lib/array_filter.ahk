class ArrayFilter {
    static instance := ""
    static mouseMessageHandler := ""

    myGui := ""
    listView := ""
    searchBox := ""
    previewBox := ""
    CheckFocus := ""
    results := []
    arrayData := []

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

    ; Cleanup metodu - tüm referansları temizle
    __Delete() {
        ; Safety net: Instance silinirken GUI'yi temizle
        if (this.myGui) {
            try this.myGui.Destroy()
        }
        if (this.CheckFocus) {
            SetTimer this.CheckFocus, 0
        }
    }

    closeGuiAndHotkeys() {
        ; 1. TÜM HOTKEY'LERİ KAPAT
        this.changeHotKeyMode(false)
        try Hotkey("Up", "Off")
        try Hotkey("Down", "Off")

        ; 2. TIMER'I DURDUR
        if (this.CheckFocus) {
            SetTimer this.CheckFocus, 0
            this.CheckFocus := ""
        }

        ; 3. FARE MESAJINI KALDIR
        if (ArrayFilter.mouseMessageHandler) {
            OnMessage(0x200, ArrayFilter.mouseMessageHandler, 0)
            ArrayFilter.mouseMessageHandler := ""
        }

        ; 4. GUI'YI YOK ET
        if (this.myGui) {
            try this.myGui.Destroy()
        }

        ; 5. INSTANCE'I SIFIRLA
        ArrayFilter.instance := ""
        ArrayFilter.mouseMessageHandler := ""
    }

    sendText(text) {
        A_Clipboard := text
        Sleep(50)
        SendInput("^v")
    }

    changeHotKeyMode(sw) {
        mode := sw ? "On" : "Off"
        Hotkey("Enter", sw ? (*) => this.SelectAndClose(this.listView.GetNext(0, "F")) : "", mode)
        Hotkey("NumpadEnter", sw ? (*) => this.SelectAndClose(this.listView.GetNext(0, "F")) : "", mode)

        CreateHotkeyHandler(idx) {
            return (*) => this.SelectAndClose(idx)
        }

        Loop 12 {
            Hotkey("F" A_Index, sw ? CreateHotkeyHandler(A_Index) : "", mode)
        }
    }

    SelectAndClose(index) {
        if (index < 1 || index > this.results.Length) {
            ShowTip("Geçersiz değer!", TipType.Warning, 1500)            
            return
        }
        local selectedSlot := this.results[index]
        this.closeGuiAndHotkeys()
        Sleep(50)
        this.sendText(selectedSlot["content"])
    }

    UpdateList() {
        local search := this.searchBox.Value
        this.listView.Delete()
        this.results := []
        local idx := 1

        for slot in this.arrayData {
            local contentPreview := SubStr(slot["content"], 1, 120)
            if (StrLen(slot["content"]) > 120) {
                contentPreview .= "..."
            }
            if (!search || InStr(StrLower(slot["name"]), StrLower(search)) || InStr(StrLower(slot["content"]), StrLower(search))) {
                fKey := idx <= 12 ? "F" . idx : ""
                this.listView.Add("", fKey, slot["name"], contentPreview)
                this.results.Push(slot)
                idx++
            }
        }

        ; İlk satırı seçili yap
        if (this.results.Length > 0) {
            this.listView.Modify(1, "Select Focus")
        }
    }

    Show(arrayData, title) {
        ; Veriyi sakla
        this.arrayData := arrayData
        this.results := []

        local guiWidth := A_ScreenWidth * 0.4
        local guiHeight := A_ScreenHeight * 0.5

        ; GUI'yi oluştur
        this.myGui := Gui("+AlwaysOnTop +ToolWindow", title)
        this.myGui.SetFont("s10")

        ; Kontrolleri oluştur
        this.searchBox := this.myGui.AddEdit("x10 y8 w" . (guiWidth - 20), "")
        this.listView := this.myGui.AddListView("x10 y40 w" . (guiWidth - 20) . " h" . (guiHeight * 0.55) . " Grid", ["F#", "İsim", "İçerik"])
        this.previewBox := this.myGui.AddEdit("x10 y" . (guiHeight * 0.55 + 50) . " w" . (guiWidth - 20) . " h" . (guiHeight * 0.35) . " ReadOnly Multi +VScroll", "")

        ; Sütun genişliklerini ayarla
        this.listView.ModifyCol(1, guiWidth * 0.10)
        this.listView.ModifyCol(2, guiWidth * 0.15)
        this.listView.ModifyCol(3, guiWidth * 0.75)

        ; Yukarı/Aşağı tuşları için hotkey'ler
        Hotkey("Up", (*) => (
            currentRow := this.listView.GetNext(0, "F"),
            currentRow > 1 ? (
                this.listView.Modify(currentRow, "-Select"),
                this.listView.Modify(currentRow - 1, "Select Focus Vis")
            ) : ""
        ), "On")

        Hotkey("Down", (*) => (
            currentRow := this.listView.GetNext(0, "F"),
            currentRow > 0 && currentRow < this.results.Length ? (
                this.listView.Modify(currentRow, "-Select"),
                this.listView.Modify(currentRow + 1, "Select Focus Vis")
            ) : ""
        ), "On")

        ; ListView seçim eventi
        this.listView.OnEvent("ItemSelect", (*) => (
            index := this.listView.GetNext(0, "F"),
            index > 0 && index <= this.results.Length ? this.previewBox.Value := this.results[index]["content"] : this.previewBox.Value := ""
        ))

        ; Fareyle gezinirken previewBox'ı güncelle
        static lastRowIndex := 0

        ArrayFilter.mouseMessageHandler := (wParam, lParam, msg, hwnd) => (
            hwnd = this.listView.Hwnd ? (
                MouseGetPos(&mouseX, &mouseY),
                WinGetPos(&winX, &winY, , , "ahk_id " . this.listView.Hwnd),
                rowHeight := 26,
                headerHeight := 2,
                relativeY := mouseY - winY - headerHeight - 40,
                rowIndex := Floor((relativeY + (rowHeight / 2)) / rowHeight) + 1,
                rowIndex > 0 && rowIndex <= this.results.Length && rowIndex != lastRowIndex ? (
                    this.previewBox.Value := this.results[rowIndex]["content"],
                    lastRowIndex := rowIndex
                ) : (rowIndex <= 0 || rowIndex > this.results.Length ? (
                    this.previewBox.Value := "",
                    lastRowIndex := 0
                ) : "")
            ) : ""
        )

        OnMessage(0x200, ArrayFilter.mouseMessageHandler)

        ; Event'ler
        this.searchBox.OnEvent("Change", (*) => this.UpdateList())
        this.listView.OnEvent("DoubleClick", (*) => this.SelectAndClose(this.listView.GetNext(0, "F")))

        this.myGui.OnEvent("Escape", (*) => (
            this.searchBox.Value ? (this.searchBox.Value := "", this.UpdateList())
            : this.closeGuiAndHotkeys()
        ))

        this.myGui.OnEvent("Close", (*) => this.closeGuiAndHotkeys())

        ; Hotkey'leri aktif et
        this.changeHotKeyMode(true)

        ; Listeyi doldur
        this.UpdateList()

        ; GUI'yi göster
        this.myGui.Show("w" . guiWidth . " h" . guiHeight)

        ; Focus kontrolü
        this.CheckFocus := (*) => (
            IsObject(this.myGui) && this.myGui.Title && !WinActive(this.myGui.Title) ? this.closeGuiAndHotkeys() : ""
        )
        SetTimer this.CheckFocus, 100
    }
}