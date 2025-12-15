#Include <array_filter>
class singleClipSlot {
    static instance := ""
    static getInstance() {
        if (!singleClipSlot.instance) {
            singleClipSlot.instance := singleClipSlot()
        }
        return singleClipSlot.instance
    }
    __New() {
        if (singleClipSlot.instance) {
            throw Error("ClipSlot zaten oluşturulmuş! getInstance kullan.")
        }
        this.groups := []
        this.defaultGroupName := ""
        this.allGroupNames := []
        this.loadSlots()
        if (this.groups.Length == 0) {
            this.initializeDefaultGroups()
        }
    }
    initializeDefaultGroups() {
        this.groups.Push(Map("groupName", "", "values", []))
        Loop 10 {
            this.groups[1]["values"].Push(Map("name", "Slot " . A_Index, "content", ""))
        }
        this.saveSlots()
    }
    getGroupsName() {
        return this.allGroupNames
    }
    setDefaultGroup(newName) {
        try {
            local fullData := this.readFullJson()
            fullData["defaultGroupName"] := newName
            local jsonStr := jsongo.Stringify(fullData)
            local file := FileOpen(AppConst.FILES_DIR . "slots.json", "w", "UTF-8")
            if (!file) {
                throw
            }
            file.Write(jsonStr)
            file.Close()
            this.loadSlots()
            return true
        } catch as err {
            gErrHandler.handleError("Default grup değiştirme başarısız: " . err.Message, err)
            return false
        }
    }
    addGroup(newGroupName) {
        if (newGroupName == "") {
            return
        }
        local newGroup := Map("groupName", newGroupName, "values", [])
        this.groups.Push(newGroup)
        this.saveSlots()
    }
    getName(groupIndex := 1, slotIndex) {
        if (groupIndex < 1 || groupIndex > this.groups.Length) {
            return ""
        }
        values := this.groups[groupIndex]["values"]
        return (slotIndex <= values.Length) ? values[slotIndex]["name"] : ""
    }
    setName(groupIndex := 1, slotIndex, newName) {
        if (groupIndex < 1 || groupIndex > this.groups.Length) {
            return
        }
        values := this.groups[groupIndex]["values"]
        while (slotIndex > values.Length) {
            values.Push(Map("name", "Slot " . (values.Length + 1), "content", ""))
        }
        values[slotIndex]["name"] := newName
    }
    getContent(groupIndex := 1, slotIndex) {
        if (groupIndex < 1 || groupIndex > this.groups.Length) {
            return ""
        }
        values := this.groups[groupIndex]["values"]
        return (slotIndex <= values.Length) ? values[slotIndex]["content"] : ""
    }
    setContent(groupIndex := 1, slotIndex, newContent) {
        if (groupIndex < 1 || groupIndex > this.groups.Length) {
            return
        }
        values := this.groups[groupIndex]["values"]
        while (slotIndex > values.Length) {
            values.Push(Map("name", "Slot " . (values.Length + 1), "content", ""))
        }
        values[slotIndex]["content"] := newContent
    }
    clearContent(groupIndex := 1, slotIndex) {
        this.setContent(groupIndex, slotIndex, "")
    }
    getSlotPreview(groupIndex := 1, slotIndex, maxLength := 200) {
        content := Trim(this.getContent(groupIndex, slotIndex))
        if (content == "") {
            return "(Boş)"
        }
        content := StrReplace(content, "`r`n", " ") ; removes enter
        display := SubStr(content, 1, maxLength)
        if (StrLen(content) > maxLength) {
            display .= "..."
        }
        return display
    }
    saveSlots() {
        try {
            local fullData := this.readFullJson()
            for loadedGroup in this.groups {
                local found := false
                Loop fullData["groups"].Length {
                    if (fullData["groups"][A_Index]["groupName"] == loadedGroup["groupName"]) {
                        fullData["groups"][A_Index] := loadedGroup
                        found := true
                        break
                    }
                }
                if (!found) {
                    fullData["groups"].Push(loadedGroup)
                }
            }
            fullData["defaultGroupName"] := this.defaultGroupName
            local jsonStr := jsongo.Stringify(fullData)
            local file := FileOpen(AppConst.FILES_DIR . "slots.json", "w", "UTF-8")
            if (!file) {
                throw
            }
            file.Write(jsonStr)
            file.Close()
            return true
        } catch as err {
            gErrHandler.handleError("Slot kaydetme başarısız: " . err.Message, err)
            return false
        }
    }
    readFullJson() {
        if !FileExist(AppConst.FILES_DIR . "slots.json") {
            return Map("defaultGroupName", "", "groups", [])
        }
        try {
            local file := FileOpen(AppConst.FILES_DIR . "slots.json", "r", "UTF-8")
            if (!file) {
                throw
            }
            local data := file.Read()
            file.Close()
            return jsongo.Parse(data)
        } catch as err {
            gErrHandler.handleError("JSON okuma başarısız: " . err.Message)
            return Map("defaultGroupName", "", "groups", [])
        }
    }
    loadSlots() {
        if !FileExist(AppConst.FILES_DIR . "slots.json") {
            return false
        }
        try {
            local fullData := this.readFullJson()
            this.defaultGroupName := fullData.Has("defaultGroupName") ? fullData["defaultGroupName"] : ""
            this.allGroupNames := []
            this.groups := []
            local defaultGroup := ""
            local selectedGroup := ""
            for group in fullData["groups"] {
                this.allGroupNames.Push(group["groupName"])
                if (group["groupName"] == "") {
                    defaultGroup := group
                } else if (group["groupName"] == this.defaultGroupName) {
                    selectedGroup := group
                }
            }
            if (defaultGroup != "") {
                this.groups.Push(defaultGroup)
            }
            if (selectedGroup != "") {
                this.groups.Push(selectedGroup)
            }
            for group in fullData["groups"] {
                if (group["groupName"] != "" && group["groupName"] != this.defaultGroupName) {
                    this.groups.Push(group)
                }
            }
            return true
        } catch as err {
            gErrHandler.handleError("loadFromSlot! Slot yükleme başarısız: " . err.Message)
            return false
        }
    }
    buildLoadClipMenu() {
        local slotMenu := Menu()
        slotMenu.Add("Search in slots", (*) => this.showSlotsSearch())
        slotMenu.Add()
        
        local defaultIndex := 1
        local defaultValues := this.groups[defaultIndex]["values"]
        Loop 10 {
            local preview := this.getSlotPreview(defaultIndex, A_Index)
            local displayName := this.getName(defaultIndex, A_Index) || "Slot " . A_Index
            slotMenu.Add(displayName . " (" . A_Index . "): " . preview,
                ((num) => (*) => this.loadFromSlot(defaultIndex, num))(A_Index))
        }
        slotMenu.Add()
        
        if (this.groups.Length > 1) {
            local selectedIndex := 2
            local selectedValues := this.groups[selectedIndex]["values"]
            Loop 10 {
                local preview := this.getSlotPreview(selectedIndex, A_Index)
                local displayName := this.getName(selectedIndex, A_Index) || "Slot " . A_Index
                slotMenu.Add("Tab " . displayName . " (" . A_Index . "): " . preview,
                    ((num) => (*) => this.loadFromSlot(selectedIndex, num))(A_Index))
            }
        }
        
        local selectLabel := "Select group"
        if (this.defaultGroupName != "") {
            selectLabel .= " (" . this.defaultGroupName . ")"
        }
        slotMenu.Add(selectLabel, this.buildGroupMenu())
        
        return slotMenu
    }
    buildSaveClipMenu() {
        local saveSlotMenu := Menu()
        saveSlotMenu.Add("Add new group", (*) => this.promptNewGroup())
        saveSlotMenu.Add()
        
        local defaultIndex := 1
        local defaultValues := this.groups[defaultIndex]["values"]
        Loop 10 {
            local preview := this.getSlotPreview(defaultIndex, A_Index)
            local displayName := this.getName(defaultIndex, A_Index) || "Slot " . A_Index
            saveSlotMenu.Add(displayName . " (" . A_Index . "): " . preview,
                ((num) => (*) => this.promptAndSaveSlot(defaultIndex, num))(A_Index))
        }
        saveSlotMenu.Add()
        
        if (this.groups.Length > 1) {
            local selectedIndex := 2
            local selectedValues := this.groups[selectedIndex]["values"]
            Loop 10 {
                local preview := this.getSlotPreview(selectedIndex, A_Index)
                local displayName := this.getName(selectedIndex, A_Index) || "Slot " . A_Index
                saveSlotMenu.Add("Tab " . displayName . " (" . A_Index . "): " . preview,
                    ((num) => (*) => this.promptAndSaveSlot(selectedIndex, num))(A_Index))
            }
        }
        
        return saveSlotMenu
    }
    getSlotsPreviewText() {
        previews := []
        local groupIndex := 1
        local values := this.groups[groupIndex]["values"]
        Loop 9 {
            local preview := StrReplace(this.getSlotPreview(groupIndex, A_Index, 100), "`n", " ")
            local displayName := this.getName(groupIndex, A_Index)
            previews.Push(displayName . " (" . A_Index . "): " . preview)
        }
        if (values.Length >= 10) {
            previews.Push(this.getName(groupIndex, 10) . " (" . 0 . "): " . "[x]")
        }
        return previews
    }
    showSlotsSearch() {
        local slotsArray := []
        local groupIndex := 1
        local values := this.groups[groupIndex]["values"]
        Loop Min(9, values.Length) {
            if (StrLen(this.getContent(groupIndex, A_Index)) > 0) {
                slotsArray.Push(Map(
                    "slotNumber", A_Index,
                    "name", this.getName(groupIndex, A_Index),
                    "content", this.getContent(groupIndex, A_Index)
                ))
            }
        }
        if (slotsArray.Length == 0) {
            this.showMessage("Slotlar boş!")
            return
        }
        ArrayFilter.getInstance().Show(slotsArray, "Slotlarda Arama")
    }
    press(commands) {
        try {
            if (commands is Array) {
                for cmd in commands {
                    if (InStr(cmd, "{Sleep")) {
                        local sleepTime := RegExReplace(cmd, ".{Sleep (\d+)}.", "$1")
                        Sleep(sleepTime)
                    } else {
                        Send(cmd)
                    }
                }
            } else {
                Send(commands)
            }
        } catch as err {
            gErrHandler.handleError("Komut çalıştırma başarısız: " . err.Message)
        }
    }
    showClipboardPreview() {
        if (StrLen(A_Clipboard) > 8000) {
            ToolTip(SubStr(A_Clipboard, 1, 8000) . "`n[..................]")
            SetTimer(() => ToolTip(), -800)
        } else {
            ToolTip(A_Clipboard)
            SetTimer(() => ToolTip(), -800)
        }
    }
    showMessage(message, duration := 2000) {
        ToolTip(message)
        SetTimer(() => ToolTip(), -duration)
    }
    promptNewGroup() {
        local input := InputBox("What is new group name?")
        if (input.Result == "OK" && input.Value != "") {
            this.addGroup(input.Value)
            this.setDefaultGroup(input.Value)
            this.showMessage("Grup oluşturuldu ve seçildi.")
        }
    }
    buildGroupMenu() {
        local groupMenu := Menu()
        local allGroups := this.getGroupsName()
        for name in allGroups {
            if (name != "") {
                groupMenu.Add(name, (*) => this.setDefaultGroup(name))
            }
        }
        groupMenu.Add()
        groupMenu.Add("Only default slots", (*) => this.setDefaultGroup(""))
        return groupMenu
    }
    __Delete() {
        if (gState.getShouldSaveOnExit) {
            this.saveSlots()
        }
    }
}