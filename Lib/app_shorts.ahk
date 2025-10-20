SetTitleMatchMode(2)  ; Title'da kısmi eşleşme için
class ShortCut {
    __New(name, keyDescription := "", keyStrokes := []) {
        this.shortCutName := name
        this.keyDescription := keyDescription  ; Serbest metin, hotkey bağlamı yok
        this.keyStrokes := keyStrokes
    }
    play() {
        Sleep(100)
        for stroke in this.keyStrokes {
            try {
                Send(stroke)
            } catch as err {
                errHandler.handleError("AppProfile.play! hatali satir: " stroke, err)
            }
        }
    }
}
class AppProfile {
    __New(name, className := "", title := "", shortCuts := []) {
        this.profileName := name
        this.className := className
        this.title := title
        this.shortCuts := shortCuts
    }
    addShortCut(shortCut) {
        this.shortCuts.Push(shortCut)
    }
    getCondition() {
        condition := ""
        if (this.className != "") {
            condition .= "ahk_class " . this.className
        }
        if (this.title != "") {
            condition .= (condition ? " " : "") . this.title
        }
        return condition
    }
    playAt(index) {
        if (index < 1 || index > this.shortCuts.Length) {
            errHandler.handleError("Geçersiz shortCut index: " . index)
            SoundBeep(800)  ; Uyarı sesi
            return false
        }
        shortCut := this.shortCuts[index]
        shortCut.play()
        return true
    }
    getShortCutsPreview(maxLen := 100) {
        result := []
        title := "ESC Profile menu : " . this.profileName
        result.Push(title)
        Loop this.shortCuts.Length {
            sc := this.shortCuts[A_Index]
            preview := A_Index . ": " . sc.shortCutName
            strokesSummary := ""
            if (sc.keyStrokes.Length > 0) {
                strokesSummary := sc.keyStrokes[1]
                Loop sc.keyStrokes.Length - 1 {
                    strokesSummary .= ", " . sc.keyStrokes[A_Index + 1]
                }
            }
            preview .= " [" . (strokesSummary != "" ? strokesSummary : "") . "]"
            if (StrLen(preview) > maxLen) {
                preview := SubStr(preview, 1, maxLen - 3) . "..."
            }
            result.Push(preview)
        }
        return result
    }
}
class ProfileManager {
    static instance := ""
    static getInstance() {
        if (!ProfileManager.instance) {
            ProfileManager.instance := ProfileManager()
        }
        return ProfileManager.instance
    }
    __New() {
        if (ProfileManager.instance) {
            throw Error("ProfileManager zaten oluşturulmuş! getInstance kullan.")
        }
        this.profiles := []
        this.currentProfile := ""
        this.load()
        ; Yeni: GUI referansları (garbage için property'ler)
        this._gui := ""
        this._profileList := ""
        this._actionList := ""
        this._profileNameEdit := ""
        this._classNameEdit := ""
        this._titleEdit := ""
        this._actionNameEdit := ""
        this._keyDescEdit := ""
        this._keyStrokesEdit := ""
        this._selectedProfileIndex := 0
        this._selectedActionIndex := 0
    }
    showManagerGui(selectedProfile := "") {
        if (this._gui && WinExist("ahk_id " this._gui.hwnd)) {
            this._gui.Show()  ; Zaten açıksa getir
            return
        }
        this._gui := Gui("+AlwaysOnTop -MaximizeBox", "Profile and Action Manager")
        this._gui.SetFont("s9", "Segoe UI")
        this._gui.OnEvent("Close", (*) => this._onGuiClose())
        this._gui.AddText("x10 y10 w270", "Profiles:")
        this._profileList := this._gui.AddListBox("x10 y30 w270 h240 Sort", this._getProfileNames())
        this._profileList.OnEvent("Change", (*) => this._onProfileSelect())
        this._gui.AddText("x10 y280 w270", "Profile Name:")
        this._profileNameEdit := this._gui.AddEdit("x10 y300 w270")
        this._gui.AddText("x10 y330 w270", "Class Name:")
        this._classNameEdit := this._gui.AddEdit("x10 y350 w270")
        this._gui.AddText("x10 y380 w270", "Title (part):")
        this._titleEdit := this._gui.AddEdit("x10 y400 w270")
        btnNewProfile := this._gui.AddButton("x10 y440 w80 h30", "New")
        btnNewProfile.OnEvent("Click", (*) => this._newProfile())
        btnUpdateProfile := this._gui.AddButton("x100 y440 w80 h30", "Update")
        btnUpdateProfile.OnEvent("Click", (*) => this._updateProfile())
        btnDeleteProfile := this._gui.AddButton("x190 y440 w80 h30", "Delete")
        btnDeleteProfile.OnEvent("Click", (*) => this._deleteProfile())
        this._gui.AddText("x290 y10 w280", "Actions:")
        this._actionList := this._gui.AddListBox("x290 y30 w280 h320", [])
        this._actionList.OnEvent("Change", (*) => this._onActionSelect())
        btnUpAction := this._gui.AddButton("x290 y360 w130 h30", "Up")
        btnUpAction.OnEvent("Click", (*) => this._moveAction(-1))
        btnDownAction := this._gui.AddButton("x430 y360 w140 h30", "Down")
        btnDownAction.OnEvent("Click", (*) => this._moveAction(1))
        this._gui.AddText("x580 y10 w290", "Action Name:")
        this._actionNameEdit := this._gui.AddEdit("x580 y30 w290")
        this._gui.AddText("x580 y60 w290", "Key Description:")
        this._keyDescEdit := this._gui.AddEdit("x580 y80 w290 h50 Multi")
        this._gui.AddText("x580 y140 w290", "Key Strokes:")
        this._keyStrokesEdit := this._gui.AddEdit("x580 y160 w290 h150 Multi")
        btnRecordMacro := this._gui.AddButton("x580 y320 w290 h30", "Record Macro")
        btnRecordMacro.OnEvent("Click", (*) => this._recordMacro())
        btnNewAction := this._gui.AddButton("x580 y440 w90 h30", "New")
        btnNewAction.OnEvent("Click", (*) => this._newAction())
        btnUpdateAction := this._gui.AddButton("x680 y440 w90 h30", "Update")
        btnUpdateAction.OnEvent("Click", (*) => this._updateAction())
        btnDeleteAction := this._gui.AddButton("x780 y440 w90 h30", "Delete")
        btnDeleteAction.OnEvent("Click", (*) => this._deleteAction())
        this._gui.Show("w880 h480")
        ; Seçili profil varsa yükle, yoksa yeni mod (hiçbir şey seçme)
        if (selectedProfile) {
            this._selectProfileByName(selectedProfile.profileName)
        } else {
            this._profileList.Choose(0)  ; Hiçbir şey seçme
            this._clearProfileFields()
            this._actionList.Delete()  ; Aksiyonları temizle
        }
    }
    ; Yeni: Aktif pencere için düzenle
    editProfileForActiveWindow() {
        profile := this.findProfileByWindow()
        if (profile) {
            this.showManagerGui(profile)
        } else {
            ; Yoksa yeni profil moduyla aç
            this.showManagerGui()
            ; Aktif pencere bilgilerini otomatik doldur
            try {
                local title := state.getActiveTitle()
                local className := state.getActiveClassName()
                this._classNameEdit.Value := className
                this._titleEdit.Value := title
                this._profileNameEdit.Value := "New Profile"
                this._profileNameEdit.Focus()
                this._clearActionFields()  ; Yeni modda aksiyonları temizle
                this._actionList.Delete()
            }
        }
    }
    ; Helper: Profil isimlerini al
    _getProfileNames() {
        names := []
        for profile in this.profiles {
            names.Push(profile.profileName)
        }
        return names
    }
    ; Event: Profil seçildiğinde
    _onProfileSelect() {
        this._selectedProfileIndex := this._profileList.Value
        if (this._selectedProfileIndex < 1) {
            this._clearProfileFields()
            this._actionList.Delete()
            this._clearActionFields()
            return
        }
        profile := this.profiles[this._selectedProfileIndex]
        this._profileNameEdit.Value := profile.profileName
        this._classNameEdit.Value := profile.className
        this._titleEdit.Value := profile.title
        this._refreshActionList()
        this._clearActionFields()  ; Seçim değişince aksiyon alanlarını temizle
    }
    ; Event: Aksiyon seçildiğinde
    _onActionSelect() {
        this._selectedActionIndex := this._actionList.Value
        if (this._selectedActionIndex < 1 || this._selectedProfileIndex < 1) {
            return
        }
        profile := this.profiles[this._selectedProfileIndex]
        if (this._selectedActionIndex > profile.shortCuts.Length) {
            return
        }
        sc := profile.shortCuts[this._selectedActionIndex]
        this._actionNameEdit.Value := sc.shortCutName
        this._keyDescEdit.Value := sc.keyDescription
        strokesStr := ""
        for stroke in sc.keyStrokes {
            strokesStr .= (strokesStr ? "`n" : "") . stroke
        }
        this._keyStrokesEdit.Value := strokesStr
    }
    ; Yeni profil
    _newProfile() {
        newName := this._profileNameEdit.Value
        newClass := this._classNameEdit.Value
        newTitle := this._titleEdit.Value
        if (newName == "") {
            MsgBox("Profil adı zorunlu!")
            return
        }
        newProfile := AppProfile(newName, newClass, newTitle)
        this.addProfile(newProfile)
        this._refreshProfileList()
        this._selectProfileByName(newName)
        this._actionList.Delete()  ; Yeni ek: Aksiyon listesini temizle
        this._clearActionFields()  ; Yeni profilde aksiyon alanlarını temizle
        this._selectedActionIndex := 0  ; Yeni ek: Aksiyon seçimini sıfırla
        this.save()
    }
    ; Profil güncelle
    _updateProfile() {
        if (this._selectedProfileIndex < 1) {
            MsgBox("Profil seçin! (Yeni profil için 'New' kullanın)")
            return
        }
        profile := this.profiles[this._selectedProfileIndex]
        profile.profileName := this._profileNameEdit.Value
        profile.className := this._classNameEdit.Value
        profile.title := this._titleEdit.Value
        this._refreshProfileList()
        this.save()
    }
    ; Profil sil
    _deleteProfile() {
        if (this._selectedProfileIndex < 1) {
            MsgBox("Profil seçin!")
            return
        }
        this.profiles.RemoveAt(this._selectedProfileIndex)
        this._refreshProfileList()
        this._clearProfileFields()
        this._clearActionFields()
        this._actionList.Delete()
        this.save()  ; Çalışırken kaydet
    }
    ; Aksiyon listesini yenile
    _refreshActionList() {
        this._actionList.Delete()
        if (this._selectedProfileIndex < 1) {
            return
        }
        profile := this.profiles[this._selectedProfileIndex]
        for sc in profile.shortCuts {
            this._actionList.Add([sc.shortCutName])
        }
    }
    ; Yeni aksiyon
    _newAction() {
        if (this._selectedProfileIndex < 1) {
            MsgBox("Önce profil seçin!")
            return
        }
        name := this._actionNameEdit.Value
        desc := this._keyDescEdit.Value
        strokes := StrSplit(this._keyStrokesEdit.Value, "`n", "`r")
        filteredStrokes := []
        for stroke in strokes {
            if (Trim(stroke) != "") {
                filteredStrokes.Push(stroke)
            }
        }
        if (name == "") {
            MsgBox("Aksiyon adı zorunlu!")
            return
        }
        newShortCut := ShortCut(name, desc, filteredStrokes)
        profile := this.profiles[this._selectedProfileIndex]
        profile.addShortCut(newShortCut)
        this._refreshActionList()
        this._actionList.Choose(profile.shortCuts.Length)
        this._onActionSelect()
        this.save()  ; Çalışırken kaydet
    }
    ; Aksiyon güncelle
    _updateAction() {
        if (this._selectedProfileIndex < 1 || this._selectedActionIndex < 1) {
            MsgBox("Aksiyon seçin!")
            return
        }
        profile := this.profiles[this._selectedProfileIndex]
        sc := profile.shortCuts[this._selectedActionIndex]
        sc.shortCutName := this._actionNameEdit.Value
        sc.keyDescription := this._keyDescEdit.Value
        strokes := StrSplit(this._keyStrokesEdit.Value, "`n", "`r")
        filteredStrokes := []
        for stroke in strokes {
            if (Trim(stroke) != "") {
                filteredStrokes.Push(stroke)
            }
        }
        sc.keyStrokes := filteredStrokes
        this._refreshActionList()
        this._actionList.Choose(this._selectedActionIndex)
        this.save()  ; Çalışırken kaydet
    }
    ; Aksiyon sil
    _deleteAction() {
        if (this._selectedProfileIndex < 1 || this._selectedActionIndex < 1) {
            MsgBox("Aksiyon seçin!")
            return
        }
        profile := this.profiles[this._selectedProfileIndex]
        profile.shortCuts.RemoveAt(this._selectedActionIndex)
        this._refreshActionList()
        this._clearActionFields()
        this.save()  ; Çalışırken kaydet
    }
    ; Aksiyon yukarı/aşağı taşı
    _moveAction(direction) {
        if (this._selectedProfileIndex < 1 || this._selectedActionIndex < 1) {
            MsgBox("Aksiyon seçin!")
            return
        }
        profile := this.profiles[this._selectedProfileIndex]
        newIndex := this._selectedActionIndex + direction
        if (newIndex < 1 || newIndex > profile.shortCuts.Length) {
            return
        }
        ; Swap
        temp := profile.shortCuts[this._selectedActionIndex]
        profile.shortCuts[this._selectedActionIndex] := profile.shortCuts[newIndex]
        profile.shortCuts[newIndex] := temp
        this._refreshActionList()
        this._actionList.Choose(newIndex)
        this._selectedActionIndex := newIndex
        this._onActionSelect()
        this.save()  ; Çalışırken kaydet
    }
    ; Makro kaydet
    _recordMacro() {
        recorder := MacroRecorder.getInstance()
        ToolTip("Kayıt başladı, durdurmak için Ctrl+Esc kullan")
        SetTimer(() => ToolTip(), -3000)
        recorder.recordScreen(true)  ; Strokes modunda kaydet
        while (recorder.recording || recorder.status == MacroRecorder.macroStatusType.pause) {
            Sleep(100)
        }
        keyStrokes := recorder.stop(true)  ; logArr al
        this._keyStrokesEdit.Value .= (this._keyStrokesEdit.Value ? "`n" : "") . keyStrokes.Join("`n")  ; Append et
    }
    ; Profil listesini yenile
    _refreshProfileList() {
        this._profileList.Delete()
        this._profileList.Add(this._getProfileNames())
    }
    ; Profil seç by name
    _selectProfileByName(name) {
        names := this._getProfileNames()
        Loop names.Length {
            if (names[A_Index] = name) {
                this._profileList.Choose(A_Index)
                this._onProfileSelect()
                break
            }
        }
    }
    ; Alanları temizle
    _clearProfileFields() {
        this._profileNameEdit.Value := ""
        this._classNameEdit.Value := ""
        this._titleEdit.Value := ""
    }
    _clearActionFields() {
        this._actionNameEdit.Value := ""
        this._keyDescEdit.Value := ""
        this._keyStrokesEdit.Value := ""
    }
    ; GUI kapanınca temizle
    _onGuiClose() {
        this.save()  ; Son kaydet
        this._gui.Destroy()
        this._gui := ""
        this._profileList := ""
        this._actionList := ""
        this._profileNameEdit := ""
        this._classNameEdit := ""
        this._titleEdit := ""
        this._actionNameEdit := ""
        this._keyDescEdit := ""
        this._keyStrokesEdit := ""
        this._selectedProfileIndex := 0
        this._selectedActionIndex := 0
    }
    ; Mevcut metodlar (değişmedi)
    findProfileByWindow() {
        local title := state.getActiveTitle()
        local hwnd := state.getActiveHwnd()
        local className := state.getActiveClassName()
        try {
            if (title == "") {
                return
            }
            for profile in this.profiles {
                if (profile.className && profile.className != className) {
                    continue
                }
                if (profile.title && !InStr(title, profile.title)) {
                    continue
                }
                return profile
            }
        } catch as err {
            errHandler.handleError("Pencere bilgisi alınamadı", err)
        }
        return false
    }
    addProfile(profile) {
        this.profiles.Push(profile)
        this.save()
    }
    save() {
        try {
            jsonStruct := Map("projectName", "ProfileManager", "profiles", [])
            for profile in this.profiles {
                profMap := Map("profileName", profile.profileName, "className", profile.className,
                    "title", profile.title, "shortCuts", [])
                for sc in profile.shortCuts {
                    profMap["shortCuts"].Push(Map("shortCutName", sc.shortCutName,
                        "keyDescription", sc.keyDescription, "keyStrokes", sc.keyStrokes))
                }
                jsonStruct["profiles"].Push(profMap)
            }
            local jsonData := jsongo.Stringify(jsonStruct)
            local file := FileOpen(AppConst.FILE_PROFILE, "w", "UTF-8")
            if (!file) {
                throw
            }
            file.Write(jsonData)
            file.Close()
        } catch as err {
            errHandler.handleError("save! Profil kaydetme hatası: " . err.Message, err)
        }
    }
    load() {
        if (!FileExist(AppConst.FILE_PROFILE)) {
            return
        }
        try {
            file := FileOpen(AppConst.FILE_PROFILE, "r", "UTF-8")
            if (!file) {
                throw
            }
            local data := file.Read()
            file.Close()
            local loaded := jsongo.Parse(data)
            this.profiles := []
            for profData in loaded["profiles"] {
                shortCuts := []
                if (profData.Has("shortCuts")) {
                    for scData in profData["shortCuts"] {
                        shortCuts.Push(ShortCut(scData["shortCutName"], scData["keyDescription"], scData["keyStrokes"]))
                    }
                }
                profile := AppProfile(profData["profileName"], profData["className"], profData["title"], shortCuts)
                this.profiles.Push(profile)
            }
        } catch as err {
            this.profiles := []
            errHandler.backupOnError("load!" . AppConst.FILE_PROFILE)
        }
    }
    ; Garbage için
    __Delete() {
        if (this._gui) {
            this._onGuiClose()
        }
    }
}