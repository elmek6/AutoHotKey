SetTitleMatchMode(2)  ; Title'da kısmi eşleşme için

class ShortCut {
    __New(name, keyStrokes := []) {
        this.shortCutName := name
        this.keyStrokes := keyStrokes  ; ["Send `{Ctrl down}`", "Send `a`", "Send `{Ctrl up}`"]
    }

    play() {
        for stroke in this.keyStrokes {
            try {
                if (InStr(stroke, "Send")) {
                    ; Send komutlarını direkt çalıştır
                    Send(SubStr(stroke, 7))  ; "Send `{Blind}a`" -> `{Blind}a`
                } else if (InStr(stroke, "Sleep")) {
                    ; Sleep komutlarını ayrıştır
                    sleepTime := RegExReplace(stroke, ".*Sleep\((\d+)\).*", "$1")
                    Sleep(sleepTime)
                } else {
                    errHandler.handleError("Geçersiz makro komutu: " stroke)
                }
            } catch as err {
                errHandler.handleError("Makro çalıştırma hatası: " stroke, err)
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
        ; this.load()
    }

    findProfileByWindow() {
        try {
            activeWin := WinGetID("A")
            className := WinGetClass("ahk_id " . activeWin)
            title := WinGetTitle("ahk_id " . activeWin)

            for profile in this.profiles {
                if (profile.className && profile.className != className)
                    continue
                if (profile.title && !InStr(title, profile.title))
                    continue
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

    createNewProfile() {
        try {
            activeWin := WinGetID("A")
            className := WinGetClass("ahk_id " . activeWin)
            title := WinGetTitle("ahk_id " . activeWin)

            profileGui := Gui("+AlwaysOnTop", "Yeni Profil Ekle")
            profileGui.Add("Text", , "Profil Adı:")
            nameEdit := profileGui.Add("Edit", "w300 vProfileName")

            profileGui.Add("Text", , "Class Adı (boş bırakılabilir):")
            classEdit := profileGui.Add("Edit", "w300 vClassName", className)

            profileGui.Add("Text", , "Title (kısmi eşleşme, boş bırakılabilir):")
            titleEdit := profileGui.Add("Edit", "w300", title)

            okBtn := profileGui.Add("Button", "Default", "OK")
            okBtn.OnEvent("Click", (*) {
                newProfile := AppProfile(nameEdit.Value, classEdit.Value ? classEdit.Value : "", titleEdit.Value ? titleEdit.Value : "")
                this.addProfile(newProfile)
                profileGui.Destroy()
            })

            profileGui.Show()
        }
    }

    addShortCutToProfile(profile) {
        try {
            ; MacroRecorder ile kayıt başlat
            recorder := MacroRecorder.getInstance()
            recorder.recordScreen()

            while (recorder.recording || recorder.status == MacroRecorder.macroStatusType.pause) {
                Sleep(100)
            }

            keyStrokes := recorder.stop(true)  ; logArr al

            macroGui := Gui("+AlwaysOnTop", "Yeni Makro Ekle")
            macroGui.Add("Text", , "Makro İçeriği:")
            contentText := macroGui.Add("Edit", "w400 h200 ReadOnly Multi", keyStrokes.Join("`n"))
            macroGui.Add("Text", , "Makro Adı:")
            nameEdit := macroGui.Add("Edit", "w300")
            macroGui.Add("Text", , "Kısayol Tuşu (ör: #F1, Ctrl+F2):")


            okBtn := macroGui.Add("Button", "Default", "OK")
            okBtn.OnEvent("Click", (*) {
                newShortCut := ShortCut(nameEdit.Value, keyStrokes),
                    profile.addShortCut(newShortCut)
                this.save()
                macroGui.Destroy()
            })

            macroGui.Show()
        }

        save() {
            try {
                jsonStruct := Map("projectName", "ProfileManager", "profiles", [])
                for profile in this.profiles {
                    profMap := Map("profileName", profile.profileName, "className", profile.className,
                        "title", profile.title, "shortCuts", [])
                    for sc in profile.shortCuts {
                        profMap["shortCuts"].Push(Map("shortCutName", sc.shortCutName,
                            "keyStrokes", sc.keyStrokes))
                    }
                    jsonStruct["profiles"].Push(profMap)
                }
                FileAppend(jsongo.Stringify(jsonStruct), AppConst.FILE_PROFILE, "UTF-8")
            } catch as err {
                errHandler.handleError("Profil kaydetme hatası: " . err.Message, err)
            }
        }

        load() {
            if (!FileExist(AppConst.FILE_PROFILE))
                return
            try {
                data := FileRead(AppConst.FILE_PROFILE, "UTF-8")
                loaded := jsongo.Parse(data)
                this.profiles := []
                for profData in loaded["profiles"] {
                    shortCuts := []
                    for scData in profData["shortCuts"] {
                        shortCuts.Push(ShortCut(scData["shortCutName"], Data["keyStrokes"]))
                    }
                    profile := AppProfile(profData["profileName"], profData["className"], profData["title"], shortCuts)
                    this.profiles.Push(profile)
                }

            } catch as err {
                errHandler.handleError("Profil yükleme hatası: " . err.Message, err)
            }
        }

        showProfileList() {
            listGui := Gui("+AlwaysOnTop", "Profil Listesi")

            if (this.profiles.Length == 0) {
                listGui.Add("Text", , "Henüz profil oluşturulmamış.")
                newBtn := listGui.Add("Button", "w100", "Yeni Profil")
                newBtn.OnEvent("Click", (*) => (listGui.Destroy(), this.createNewProfile()))
            } else {
                listGui.Add("Text", , "Mevcut Profiller:")

                for i, profile in this.profiles {
                    profileText := profile.profileName . " (" . profile.shortCuts.Length . " kısayol)"
                    listGui.Add("Text", "w300", profileText)

                    addBtn := listGui.Add("Button", "w80 x+10", "Kısayol Ekle")
                    addBtn.OnEvent("Click", ((p) => (*) => this.addShortCutToProfile(p))(profile))
                }

                listGui.Add("Text", "w300 xm", "")  ; Spacer
                newBtn := listGui.Add("Button", "w100", "Yeni Profil")
                newBtn.OnEvent("Click", (*) => (listGui.Destroy(), this.createNewProfile()))
            }

            closeBtn := listGui.Add("Button", "w80 x+10", "Kapat")
            closeBtn.OnEvent("Click", (*) => listGui.Destroy())

            listGui.Show("xCenter yCenter")
        }


    }
}