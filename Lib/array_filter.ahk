class ArrayFilter {
    static instance := ""

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

    Show(arrayData, title) {
        local results := []  ; Filtrelenmiş sonuçlar
        local myGui := Gui("+AlwaysOnTop", title)
        myGui.SetFont("s10")

        myGui.AddText("x10 y10", "Search:")
        local searchBox := myGui.AddEdit("x70 y8 w300")
        local listBox := myGui.AddListBox("x10 y40 w360 h200")

        UpdateList() {
            local search := searchBox.Value
            listBox.Delete()
            results := []  ; Array'i temizle
            local idx := 1
            for text in arrayData {
                if (!search || InStr(StrLower(text), StrLower(search))) {
                    local displayText := SubStr(text, 1, 100)  ; Uzun text'leri kısalt
                    if (StrLen(text) > 100) {
                        displayText .= "..."
                    }
                    listBox.Add(["F" idx ". " displayText])
                    results.Push(text)  ; Orijinal metni ekle
                    idx++
                }
            }
        }

        SelectAndClose(index) {
            if (index < 1 || index > results.Length)
                return
            
            local textToSend := results[index]
            myGui.Destroy()
            ; Hotkey’leri kapat
            Hotkey("Enter", "Off")
            Hotkey("F1", "Off")
            Hotkey("F2", "Off")
            Hotkey("F3", "Off")
            Hotkey("F4", "Off")
            Hotkey("F5", "Off")
            Hotkey("F6", "Off")
            Hotkey("F7", "Off")
            Hotkey("F8", "Off")
            Hotkey("F9", "Off")
            Hotkey("F10", "Off")
            Hotkey("F11", "Off")
            Hotkey("F12", "Off")
            Sleep(50)            
            if (StrLen(textToSend) > 200) {
                local prevClip := A_ClipBoard
                A_ClipBoard := textToSend
                Sleep(50)
                SendInput("^v")
                Sleep(50)
                A_ClipBoard := prevClip
            } else {
                SendInput(textToSend)
            }
        }

        ; Güncelleme ve olay bağlama
        searchBox.OnEvent("Change", (*) => UpdateList())
        listBox.OnEvent("DoubleClick", (*) => SelectAndClose(listBox.Value))

        ; ESC: önce search temizle, sonra kapat
        myGui.OnEvent("Escape", (*) => (searchBox.Value ? (searchBox.Value := "", UpdateList()) : (myGui.Destroy(), Hotkey("Enter", "Off"), Hotkey("F1", "Off"), Hotkey("F2", "Off"), Hotkey("F3", "Off"), Hotkey("F4", "Off"), Hotkey("F5", "Off"), Hotkey("F6", "Off"), Hotkey("F7", "Off"), Hotkey("F8", "Off"), Hotkey("F9", "Off"), Hotkey("F10", "Off"), Hotkey("F11", "Off"), Hotkey("F12", "Off"))))

        myGui.OnEvent("Close", (*) => (myGui.Destroy(), Hotkey("Enter", "Off"), Hotkey("F1", "Off"), Hotkey("F2", "Off"), Hotkey("F3", "Off"), Hotkey("F4", "Off"), Hotkey("F5", "Off"), Hotkey("F6", "Off"), Hotkey("F7", "Off"), Hotkey("F8", "Off"), Hotkey("F9", "Off"), Hotkey("F10", "Off"), Hotkey("F11", "Off"), Hotkey("F12", "Off")))

        ; Hotkey’ler: F1-F12 ve Enter
        Hotkey("Enter", (*) => (listBox.Value >= 1 && listBox.Value <= results.Length ? SelectAndClose(listBox.Value) : ""), "On")
        Hotkey("F1", (*) => (1 <= results.Length ? SelectAndClose(1) : ""), "On")
        Hotkey("F2", (*) => (2 <= results.Length ? SelectAndClose(2) : ""), "On")
        Hotkey("F3", (*) => (3 <= results.Length ? SelectAndClose(3) : ""), "On")
        Hotkey("F4", (*) => (4 <= results.Length ? SelectAndClose(4) : ""), "On")
        Hotkey("F5", (*) => (5 <= results.Length ? SelectAndClose(5) : ""), "On")
        Hotkey("F6", (*) => (6 <= results.Length ? SelectAndClose(6) : ""), "On")
        Hotkey("F7", (*) => (7 <= results.Length ? SelectAndClose(7) : ""), "On")
        Hotkey("F8", (*) => (8 <= results.Length ? SelectAndClose(8) : ""), "On")
        Hotkey("F9", (*) => (9 <= results.Length ? SelectAndClose(9) : ""), "On")
        Hotkey("F10", (*) => (10 <= results.Length ? SelectAndClose(10) : ""), "On")
        Hotkey("F11", (*) => (11 <= results.Length ? SelectAndClose(11) : ""), "On")
        Hotkey("F12", (*) => (12 <= results.Length ? SelectAndClose(12) : ""), "On")

        UpdateList()
        myGui.Show("w400 h260")
    }
}