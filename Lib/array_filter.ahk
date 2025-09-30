class ArrayFilter {
    static instance := ""
    static mouseMessageHandler := ""  ; Fare mesajı handler'ını saklamak için

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

    closeGuiAndHotkeys(myGui, listView, SelectAndClose) {
        SetTimer this.CheckFocus, 0
        ; Fare mesajını tamamen kaldır
        if (ArrayFilter.mouseMessageHandler) {
            OnMessage(0x200, ArrayFilter.mouseMessageHandler, 0)  ; Handler'ı kaldır
            ArrayFilter.mouseMessageHandler := ""
        }
        try myGui.Destroy()
        this.changeHotKeyMode(false, listView, SelectAndClose)
    }

    sendText(text) {
        if (StrLen(text) > 200) {
            local prevClip := A_Clipboard
            A_Clipboard := text
            Sleep(50)
            SendInput("^v")
            Sleep(50)
            A_Clipboard := prevClip
        } else {
            SendInput(text)
        }
    }

    changeHotKeyMode(sw, listView, SelectAndClose) {
        mode := sw ? "On" : "Off"
        Hotkey("Enter", sw ? (*) => SelectAndClose(listView.GetNext(0, "F")) : "", mode)

        CreateHotkeyHandler(idx) {
            return (*) => SelectAndClose(idx)
        }

        Loop 12 {
            Hotkey("F" A_Index, sw ? CreateHotkeyHandler(A_Index) : "", mode)
        }
    }

    Show(arrayData, title) {
        local results := []
        local guiWidth := A_ScreenWidth * 0.4  ; Ekranın %40'ı
        local guiHeight := A_ScreenHeight * 0.5 ; Ekranın %50'si
        local myGui := Gui("+AlwaysOnTop +ToolWindow", title)
        myGui.SetFont("s10")

        local searchBox := myGui.AddEdit("x10 y8 w" . (guiWidth - 20), "")
        local listView := myGui.AddListView("x10 y40 w" . (guiWidth - 20) . " h" . (guiHeight * 0.55) . " Grid", ["F#", "İsim", "İçerik"])
        local previewBox := myGui.AddEdit("x10 y" . (guiHeight * 0.55 + 50) . " w" . (guiWidth - 20) . " h" . (guiHeight * 0.35) . " ReadOnly Multi +VScroll", "")

        ; Sütun genişliklerini oranlara göre ayarla
        listView.ModifyCol(1, guiWidth * 0.10) ; %10 F# (F tuşu + slot no)
        listView.ModifyCol(2, guiWidth * 0.15) ; %15 İsim
        listView.ModifyCol(3, guiWidth * 0.75) ; %75 İçerik (kalanı doldur)

        SelectAndClose(index) {
            if (index < 1 || index > results.Length) {
                MsgBox("Geçersiz değer!")
                return
            }
            local selectedSlot := results[index]
            this.closeGuiAndHotkeys(myGui, listView, SelectAndClose)
            Sleep(50)
            this.sendText(selectedSlot["content"])  ; Sadece içeriği gönder
        }

        UpdateList() {
            local search := searchBox.Value
            listView.Delete() ; ListView'ı temizle
            results := []
            local idx := 1
            for slot in arrayData {
                local contentPreview := SubStr(slot["content"], 1, 120)
                if (StrLen(slot["content"]) > 120) {
                    contentPreview .= "..." ; Uzun içerik için kes
                }
                if (!search || InStr(StrLower(slot["name"]), StrLower(search)) || InStr(StrLower(slot["content"]), StrLower(search))) {
                    local fKey := idx <= 12 ? "F" . idx . " #" . slot["slotNumber"] : "#" . slot["slotNumber"]
                    listView.Add("", fKey, slot["name"], contentPreview)
                    results.Push(slot)
                    idx++
                }
            }
            ; İlk satırı seçili yap
            if (results.Length > 0) {
                listView.Modify(1, "Select Focus")
            }
        }

        ; Seçili satır değişince previewBox'ı güncelle
        listView.OnEvent("ItemSelect", (*) => (
            index := listView.GetNext(0, "F"),
            index > 0 && index <= results.Length ? previewBox.Value := results[index]["content"] : previewBox.Value := ""
        ))

        ; Fareyle gezinirken previewBox'ı güncelle
        static lastRowIndex := 0
        
        ; Fare mesajı handler'ını tanımla ve sakla
        ArrayFilter.mouseMessageHandler := (wParam, lParam, msg, hwnd) => (
            hwnd = listView.Hwnd ? (
                MouseGetPos(&mouseX, &mouseY),
                WinGetPos(&winX, &winY,,, "ahk_id " . listView.Hwnd),
                rowHeight := 20,
                headerHeight := 30,
                relativeY := mouseY - winY - headerHeight - 40,
                rowIndex := Floor(relativeY / rowHeight) + 1,
                rowIndex > 0 && rowIndex <= results.Length && rowIndex != lastRowIndex ? (
                    previewBox.Value := results[rowIndex]["content"],
                    lastRowIndex := rowIndex
                ) : (rowIndex <= 0 || rowIndex > results.Length ? (
                    previewBox.Value := "",
                    lastRowIndex := 0
                ) : "")
            ) : ""
        )
        
        ; Fare mesajını kaydet
        OnMessage(0x200, ArrayFilter.mouseMessageHandler)

        searchBox.OnEvent("Change", (*) => UpdateList())
        listView.OnEvent("DoubleClick", (*) => SelectAndClose(listView.GetNext(0, "F")))

        myGui.OnEvent("Escape", (*) => (
            searchBox.Value ? (searchBox.Value := "", UpdateList())
            : this.closeGuiAndHotkeys(myGui, listView, SelectAndClose)
        ))

        myGui.OnEvent("Close", (*) => this.closeGuiAndHotkeys(myGui, listView, SelectAndClose))

        this.changeHotKeyMode(true, listView, SelectAndClose)

        UpdateList()
        myGui.Show("w" . guiWidth . " h" . guiHeight)
        this.CheckFocus := (*) => (
            IsObject(myGui) && myGui.Title && !WinActive(myGui.Title) ? this.closeGuiAndHotkeys(myGui, listView, SelectAndClose) : ""
        )
        SetTimer this.CheckFocus, 100
    }
}