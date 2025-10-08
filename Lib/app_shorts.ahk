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
                ; if (InStr(stroke, "Send")) {
                ;     Send(SubStr(stroke, 7))  ; "Send `{Blind}a`" -> `{Blind}a`
                ; } else if (InStr(stroke, "Sleep")) {
                ;     sleepTime := RegExReplace(stroke, ".*Sleep\((\d+)\).*", "$1")
                ;     Sleep(sleepTime)
                ; } else {
                ;     errHandler.handleError("Geçersiz makro komutu: " stroke)
                ; }
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
}

class ProfileBuilder {
    __New(profileManager) {
        this.profileManager := profileManager
    }

    buildMenu() {
        menuItems := []
        profile := this.profileManager.findProfileByWindow()
        if (!profile) {
            ; OutputDebug("Profil bulunamadı, sadece 'Yeni Profil Ekle' gösteriliyor.")
            menuItems.Push({ key: "p", desc: "Yeni Profil Ekle", action: (*) => this.profileManager.createNewProfile() })
            return menuItems
        }

        ; OutputDebug("Profil bulundu: " profile.profileName ", shortCuts ekleniyor.")
        for shortCut in profile.shortCuts {
            key := shortCut.keyDescription ? shortCut.keyDescription : shortCut.shortCutName
            desc := shortCut.shortCutName . (shortCut.keyDescription ? " - " . shortCut.keyDescription : "")
            menuItems.Push({
                key: key,
                desc: desc,
                action: (*) => shortCut.play()
            })
        }
        menuItems.Push({
            key: "a",
            desc: "Aksiyon Ekle (" . profile.profileName . ")",
            action: (*) => this.profileManager.addShortCutToProfile(profile)
        })
        return menuItems
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
    }

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

    createNewProfile(profile := "") {  ; Optional profile parametresi eklendi
        try {
            local title := state.getActiveTitle()
            local hwnd := state.getActiveHwnd()
            local className := state.getActiveClassName()

            profileGui := Gui("+AlwaysOnTop", profile ? "Profil Düzenle" : "Yeni Profil Ekle")
            profileGui.Add("Text", , "Profil Adı:")
            nameEdit := profileGui.Add("Edit", "w300 vProfileName", profile ? profile.profileName : "")

            profileGui.Add("Text", , "Class Adı (boş bırakılabilir):")
            classEdit := profileGui.Add("Edit", "w300 vClassName", profile ? profile.className : className)

            profileGui.Add("Text", , "Title (kısmi eşleşme, boş bırakılabilir):")
            titleEdit := profileGui.Add("Edit", "w300", profile ? profile.title : title)

            okBtn := profileGui.Add("Button", "Default", "OK")
            okBtn.OnEvent("Click", (*) {
                newName := nameEdit.Value
                newClass := classEdit.Value ? classEdit.Value : ""
                newTitle := titleEdit.Value ? titleEdit.Value : ""
                if (profile) {  ; Edit modu
                    profile.profileName := newName
                    profile.className := newClass
                    profile.title := newTitle
                    ; Shortcuts aynı kalır, sadece profil bilgileri güncellenir
                } else {  ; Yeni ekleme
                    newProfile := AppProfile(newName, newClass, newTitle)
                    this.addProfile(newProfile)
                }
                this.save()
                profileGui.Destroy()
            })

            profileGui.Show()
        } catch as err {
            errHandler.handleError("Profil GUI hatası", err)
        }
    }

    editProfile(profile) {  ; Yeni metod: createNewProfile'ı çağırır
        if (!profile) {
            errHandler.handleError("Düzenlenecek profil yok")
            return
        }
        this.createNewProfile(profile)
    }

    addShortCutToProfile(profile) {
        try {
            macroGui := Gui("+AlwaysOnTop", "Yeni Aksiyon Ekle")
            macroGui.Add("Text", , "Aksiyon Adı:")
            nameEdit := macroGui.Add("Edit", "w300")

            macroGui.Add("Text", , "Kısayol Açıklaması (bilgi amaçlı, örn: F1):")
            keyDescEdit := macroGui.Add("Edit", "w300")

            macroGui.Add("Text", , "Aksiyonlar (her satır bir komut, örn: Send ^f`nSleep(100)):")
            macroGui.Add("Text", , "Makro kaydetmek için tuşlara basın, durdurmak için Esc kullanın.")
            strokesEdit := macroGui.Add("Edit", "w400 h200 Multi")

            recordBtn := macroGui.Add("Button", "w150", "Makro Kaydet")
            recordBtn.OnEvent("Click", (*) {
                recorder := MacroRecorder.getInstance()
                ToolTip("Kayıt başladı, durdurmak için Ctrl+Esc kullan")
                SetTimer(() => ToolTip(), -3000)
                recorder.recordScreen(true)  ; Strokes modunda kaydet
                while (recorder.recording || recorder.status == MacroRecorder.macroStatusType.pause) {
                    Sleep(100)
                }
                keyStrokes := recorder.stop(true)  ; logArr al
                strokesEdit.Value .= (strokesEdit.Value ? "`n" : "") . keyStrokes.Join("`n")  ; Append et
            })

            okBtn := macroGui.Add("Button", "Default", "OK")
            okBtn.OnEvent("Click", (*) {
                strokesArr := StrSplit(strokesEdit.Value, "`n", "`r")
                ; Boş satırları filtrele
                filteredStrokes := []
                for stroke in strokesArr {
                    if (Trim(stroke) != "") {
                        filteredStrokes.Push(stroke)
                    }
                }
                newShortCut := ShortCut(nameEdit.Value, keyDescEdit.Value, filteredStrokes)
                profile.addShortCut(newShortCut)
                this.save()
                macroGui.Destroy()
            })

            macroGui.Show()
        }
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
                throw Error("slots.json yazılamadı")
            }
            file.Write(jsonData)
            file.Close()
        } catch as err {
            errHandler.handleError("Profil kaydetme hatası: " . err.Message, err)
        }
    }

    load() {
        if (!FileExist(AppConst.FILE_PROFILE)) {
            return
        }
        try {
            file := FileOpen(AppConst.FILE_PROFILE, "r", "UTF-8")
            if (!file) {
                throw Error("slots.json okunamadı")
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
            errHandler.backupOnError(AppConst.FILE_PROFILE)
            ; OutputDebug("Profil yükleme hatası: " err.Message)
        }
    }
}