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
        SetTimer this.CheckFocus, 0
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

        CreateHotkeyHandler(idx) {
            return (*) => SelectAndClose(idx)
        }

        Loop 12 {
            Hotkey("F" A_Index, sw ? CreateHotkeyHandler(A_Index) : "", mode)
        }
    }

    Show(arrayData, title) {
        local results := []
        local myGui := Gui("+AlwaysOnTop +ToolWindow", title)
        myGui.SetFont("s10")

        local searchBox := myGui.AddEdit("x70 y8 w300", "")
        local listBox := myGui.AddListBox("x10 y40 w360 h200")

        SelectAndClose(index) {
            if (index < 1 || index > results.Length)
                MsgBox ("Gecersiz deger return kullan burda")
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

        this.CheckFocus := (*) => (
            IsObject(myGui) && myGui.Title && !WinActive(myGui.Title) ? this.closeGuiAndHotkeys(myGui, listBox, SelectAndClose) : ""
        )
        SetTimer this.CheckFocus, 100
    }
}