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

    closeGuiAndHotkeys(myGui, listBox, SelectAndClose) {
        try myGui.Destroy()
        this.changeHotKeyMode(false, listBox, SelectAndClose)
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

    changeHotKeyMode(sw, listBox, SelectAndClose) {
        mode := sw ? "On" : "Off"
        Hotkey("Enter", sw ? (*) => SelectAndClose(listBox.Value) : "", mode)
        Hotkey("F1", sw ? (*) => SelectAndClose(1) : "", mode)
        Hotkey("F2", sw ? (*) => SelectAndClose(2) : "", mode)
        Hotkey("F3", sw ? (*) => SelectAndClose(3) : "", mode)
        Hotkey("F4", sw ? (*) => SelectAndClose(4) : "", mode)
        Hotkey("F5", sw ? (*) => SelectAndClose(5) : "", mode)
        Hotkey("F6", sw ? (*) => SelectAndClose(6) : "", mode)
        Hotkey("F7", sw ? (*) => SelectAndClose(7) : "", mode)
        Hotkey("F8", sw ? (*) => SelectAndClose(8) : "", mode)
        Hotkey("F9", sw ? (*) => SelectAndClose(9) : "", mode)
        Hotkey("F10", sw ? (*) => SelectAndClose(10) : "", mode)
        Hotkey("F11", sw ? (*) => SelectAndClose(11) : "", mode)
        Hotkey("F12", sw ? (*) => SelectAndClose(12) : "", mode)
    }

    Show(arrayData, title) {
        local results := []
        local myGui := Gui("+AlwaysOnTop +ToolWindow", title)
        myGui.SetFont("s10")

        local searchBox := myGui.AddEdit("x70 y8 w300", "")
        local listBox := myGui.AddListBox("x10 y40 w360 h200")

        SelectAndClose(index) {
            if (index < 1 || index > results.Length)
                return
            local textToSend := results[index]
            this.closeGuiAndHotkeys(myGui, listBox, SelectAndClose)
            Sleep(50)
            this.sendText(textToSend)
        }

        UpdateList() {
            local search := searchBox.Value
            listBox.Delete()
            results := []
            local idx := 1
            for text in arrayData {
                if (!search || InStr(StrLower(text), StrLower(search))) {
                    local displayText := SubStr(text, 1, 100)
                    if (StrLen(text) > 100)
                        displayText .= "..."
                    listBox.Add(["F" idx ". " displayText])
                    results.Push(text)
                    idx++
                }
            }
        }

        searchBox.OnEvent("Change", (*) => UpdateList())
        listBox.OnEvent("DoubleClick", (*) => SelectAndClose(listBox.Value))

        myGui.OnEvent("Escape", (*) => (
            searchBox.Value ? (searchBox.Value := "", UpdateList())
            : this.closeGuiAndHotkeys(myGui, listBox, SelectAndClose)
        ))

        myGui.OnEvent("Close", (*) => this.closeGuiAndHotkeys(myGui, listBox, SelectAndClose))

        this.changeHotKeyMode(true, listBox, SelectAndClose)

        UpdateList()
        myGui.Show("w400 h260")
    }
}