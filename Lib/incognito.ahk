; ════════════════════════════════════════════════════════════════════════
;  incognito.ahk — Windows "Incognito" (Jump List dondurma) modülü
; ────────────────────────────────────────────────────────────────────────
;  Orijinal fikir: RemiGC/WindowsIncognito (C#/WPF, 2015 — terk edilmiş).
;  O program %APPDATA%\...\Recent\AutomaticDestinations\*.automaticDestinations-ms
;  dosyalarını FileShare.None ile açıp handle'ı açık tutarak Windows'un jump
;  list geçmişini güncellemesini engelliyordu.
;
;  Bu port (Win10/11 için güçlendirilmiş):
;   • AutomaticDestinations + CustomDestinations klasörlerini birlikte kapsar.
;   • "rw-" flag'i ile dosyaları exclusive (yazma+silme dış süreçlere kapalı)
;     açar; dosya truncate EDİLMEZ, mevcut içerik korunur.
;   • Canlı izleme: aktifken bir timer yeni oluşan jump list dosyalarını da
;     anında kilitler (yeni açılan uygulamalar da yakalanır).
;   • cleanNow(): CCleaner/PrivaZer mantığı — dosyaları sonradan siler.
;   • Friendly-name eşlemesi: Files\incognito_appids.json (EricZimmerman listesi).
;
; ────────────────────────────────────────────────────────────────────────
;  GELİŞTİRME NOTLARI (acı çekerek öğrenildi):
;   • Kilit flag'i "rw-": exclusive (FileShare.None), dosyayı truncate ETMEZ.
;     Ampirik test: "rw" tiresiz = paylaşımlı (kilitlemez); tire şart.
; ════════════════════════════════════════════════════════════════════════

class singleIncognito {
    static instance := ""

    static getInstance() {
        if (!singleIncognito.instance) {
            singleIncognito.instance := singleIncognito()
        }
        return singleIncognito.instance
    }

    __New() {
        if (singleIncognito.instance) {
            throw Error("singleIncognito zaten oluşturuldu! getInstance kullan.")
        }
        this.active := false
        this.handles := Map()           ; fullPath -> FileObject (açık kilit handle'ları)
        this.handles.CaseSense := "Off"
        this._timer := 0
        this.watchPeriod := 700         ; ms — yeni dosyaları yakalama sıklığı
        this._badge := 0                ; taskbar gösterge penceresi (aktifken)
        this._badgeList := 0            ; pencere içindeki kilitli-liste kontrolü
        this._badgeInfo := 0            ; pencere içindeki sayaç metni
        this._cbVlc := 0               ; checkbox kontrolü
        this._cbTemizle := 0           ; checkbox kontrolü

        local recent := A_AppData "\Microsoft\Windows\Recent\"
        this.dirs := [
            { path: recent "AutomaticDestinations\", ext: "automaticDestinations-ms" },
            { path: recent "CustomDestinations\", ext: "customDestinations-ms" }
        ]

        ; "Son dosyalar" kısayolları (.lnk). Açtığın her dosya buraya kısayol bırakır
        ; (Hızlı Erişim'de görünür). Kilitlemek Explorer'ı bozar -> sürekli SİL.
        ; Eski geçmişi korumak için yalnız oturumda oluşanlar silinir (zaman filtresi).
        this.coverRecentLnk := false    ; badge'daki [ ] Temizle checkbox'u ile açılır
        this.recentDir := recent
        this._sessionStart := 0

        ; Uygulama-içi geçmiş tutan programlar (VLC vb.) için ek hedefler.
        ; Jump list değil; bu dosyaları kilitlemek uygulamayı bozabilir, bu yüzden
        ; varsayılan olarak BOŞ. İstenirse addExtraTarget() ile eklenebilir.
        ; Örn (VLC son medya listesi):
        ;   this.addExtraTarget(A_AppData "\vlc\vlc-qt-interface.ini")
        this.extraTargets := []

        ; VLC son-medya geçmişi (jump list değil, uygulama-içi). Kilitlemek VLC'yi
        ; bozabileceği için kilit yerine "sürekli boşalt" yöntemi kullanılır.
        this.coverVlc := true
        this.vlcIni := A_AppData "\vlc\vlc-qt-interface.ini"

        this.appIds := this._loadAppIds()   ; hex(lower) -> friendly name
    }

    ; ── Durum ───────────────────────────────────────────────────────────
    isActive() => this.active
    lockedCount() => this.handles.Count

    ; ── Aç / Kapa ───────────────────────────────────────────────────────
    toggle() {
        ; NOT: v2.1-alpha'da çıplak ternary-statement ("a ? b : c") syntax error verir;
        ; '?' postfix maybe-operatörüyle çakışıyor. Statement konumunda if/else kullan.
        if (this.active)
            this.disable(true)
        else
            this.enable(true)
    }

    enable(notify := false) {
        if (this.active)
            return
        this.active := true
        this._sessionStart := A_Now          ; bu andan sonra oluşan .lnk'ler silinecek
        this._lockAllExisting()
        this._clearVlcRecents()
        this._timer := ObjBindMethod(this, "_watchTick")
        SetTimer(this._timer, this.watchPeriod)
        this._applyIcon(true)
        this._showBadge()
        if (notify) {
            ShowTip("🔒 Incognito AÇIK — " this.handles.Count " jump list donduruldu", TipType.Success, 1300)
            SoundBeep(900, 90)
        }
    }

    disable(notify := false) {
        if (!this.active)
            return
        if (this._timer) {
            SetTimer(this._timer, 0)
            this._timer := 0
        }
        this._unlockAll()
        this.active := false
        this._applyIcon(false)
        this._destroyBadge()
        if (notify) {
            ShowTip("🔓 Incognito kapalı (kilitler serbest)", TipType.Info, 1000)
            SoundBeep(500, 90)
        }
    }

    ; ── Kilit primitive'leri ────────────────────────────────────────────
    _lockFile(path) {
        if (this.handles.Has(path))
            return false
        local f := ""
        try {
            f := FileOpen(path, "rw-")   ; rw = aç (truncate yok), "-" = dış süreçlere kapalı
        } catch {
            return false                 ; o an Windows tutuyor olabilir; timer tekrar dener
        }
        if (!IsObject(f))
            return false
        this.handles[path] := f
        return true
    }

    _lockAllExisting() {
        for d in this.dirs {
            if (!DirExist(d.path))
                continue
            Loop Files, d.path "*." d.ext
                this._lockFile(A_LoopFileFullPath)
        }
        for t in this.extraTargets {
            if (FileExist(t))
                this._lockFile(t)
        }
    }

    _watchTick() {
        ; Aktifken periyodik: yeni oluşan dosyaları kilitle.
        for d in this.dirs {
            if (!DirExist(d.path))
                continue
            Loop Files, d.path "*." d.ext {
                if (!this.handles.Has(A_LoopFileFullPath))
                    this._lockFile(A_LoopFileFullPath)
            }
        }
        for t in this.extraTargets {
            if (FileExist(t) && !this.handles.Has(t))
                this._lockFile(t)
        }
        this._clearVlcRecents()       ; VLC kapanışta yazarsa ≤1 tick içinde temizle
        this._clearRecentLnk()        ; oturumda açılan dosyaların .lnk izlerini sil
    }

    ; Recent\*.lnk temizliği. onlySession=true: yalnız incognito oturumunda oluşanlar
    ; (eski geçmiş korunur). onlySession=false: hepsi (tam temizlik / cleanNow).
    _clearRecentLnk(onlySession := true) {
        if (!this.coverRecentLnk || !DirExist(this.recentDir))
            return
        Loop Files, this.recentDir "*.lnk" {
            if (onlySession && A_LoopFileTimeModified < this._sessionStart)
                continue
            try FileDelete(A_LoopFileFullPath)
        }
    }

    ; VLC son-medya listesini boşalt (yalnızca doluysa yaz — gereksiz disk yazımı yok)
    _clearVlcRecents() {
        if (!this.coverVlc || !FileExist(this.vlcIni))
            return
        try {
            if (IniRead(this.vlcIni, "RecentsMRL", "list", "") != "") {
                IniWrite("", this.vlcIni, "RecentsMRL", "list")
                IniWrite("", this.vlcIni, "RecentsMRL", "times")
            }
            if (IniRead(this.vlcIni, "OpenDialog", "netMRL", "") != "")
                IniWrite("", this.vlcIni, "OpenDialog", "netMRL")
        } catch as e {
            OutputDebug("incognito._clearVlcRecents: " e.Message "`n")
        }
    }

    _unlockAll() {
        for path, f in this.handles {
            try f.Close()
        }
        this.handles := Map()
        this.handles.CaseSense := "Off"
    }

    ; ── Temizlik (cleaner mantığı: sonradan sil) ────────────────────────
    ; Aktifken de çağrılabilir: silinen dosyaları Windows yeniden yaratırsa
    ; watch timer tekrar kilitler (yani "boş" halde donar).
    cleanNow() {
        local count := 0
        for d in this.dirs {
            if (!DirExist(d.path))
                continue
            Loop Files, d.path "*." d.ext {
                local p := A_LoopFileFullPath
                if (this.handles.Has(p)) {
                    try this.handles[p].Close()
                    this.handles.Delete(p)
                }
                try {
                    FileDelete(p)
                    count++
                }
            }
        }
        this._clearVlcRecents()
        this._clearRecentLnk(false)   ; tam temizlik: tüm Recent .lnk
        return count
    }

    ; ── Ek hedefler (uygulama-içi geçmiş) ───────────────────────────────
    addExtraTarget(path) {
        for t in this.extraTargets
            if (t = path)
                return
        this.extraTargets.Push(path)
        if (this.active && FileExist(path))
            this._lockFile(path)
    }

    ; ── İsim eşlemesi / bilgi ───────────────────────────────────────────
    _loadAppIds() {
        local m := Map()
        m.CaseSense := "Off"
        try {
            local p := A_ScriptDir "\Files\incognito_appids.json"
            if (FileExist(p)) {
                local f := FileOpen(p, "r", "UTF-8")
                local data := f.Read()
                f.Close()
                local parsed := jsongo.Parse(data)
                if (parsed is Map) {
                    ; CaseSense yalnızca BOŞ Map'te değiştirilebilir; dolu parse
                    ; sonucuna atamak "Map must be empty" fırlatıyordu. Bunun
                    ; yerine girdileri baştan CaseSense=Off kurulmuş m'ye kopyala.
                    for k, v in parsed
                        m[k] := v
                }
            }
        } catch as e {
            try App.ErrHandler.handleError("incognito appids yüklenemedi: " e.Message)
        }
        return m
    }

    getName(hex) {
        return this.appIds.Has(hex) ? this.appIds[hex] : hex
    }

    nameForFile(path) {
        local nameNoExt := ""
        SplitPath(path, , , , &nameNoExt)
        return this.getName(nameNoExt)
    }

    ; Kilitli dosyaların okunur isimleri (menü/tooltip için)
    getLockedNames(maxNames := 12) {
        local names := []
        for path, f in this.handles {
            names.Push(this.nameForFile(path))
            if (names.Length >= maxNames)
                break
        }
        return names
    }

    ; ── Tray ikonu ──────────────────────────────────────────────────────
    _applyIcon(on) {
        if (on) {
            try TraySetIcon(A_ScriptDir "\Files\incognito.ico")
            try A_IconTip := "AHK — Incognito AÇIK (" this.handles.Count " kilit)"
        } else {
            try TraySetIcon(A_ScriptDir "\ahk.ico")
            try A_IconTip := "AHK " State.Script.getVersion()
        }
    }

    ; ── Taskbar göstergesi (tray ikonu gizlenebildiği için) ─────────────
    ; Taskbar'da buton olarak durur (yüzmez). Pencereyi/butonu kapatınca
    ; incognito kapanır. İkon = kahverengi kilit (Files\incognito.ico).
    _showBadge() {
        if (this._badge)
            return
        local g := Gui("-MaximizeBox", "🔒 Incognito açık")
        g.SetFont("s9", "Segoe UI")
        g.MarginX := 12, g.MarginY := 10
        ; Bilgi + kilitli uygulama listesi
        this._badgeInfo := g.AddText("xm ym w300", "")
        this._badgeList := g.AddListBox("xm y+6 w300 r12", [])
        ; Checkbox sırası: [x] VLC | [ ] Temizle
        this._cbVlc := g.AddCheckbox("xm y+12", "VLC")
        this._cbVlc.Value := this.coverVlc ? 1 : 0
        this._cbVlc.OnEvent("Click", (cb, *) => (this.coverVlc := !!cb.Value))
        this._cbTemizle := g.AddCheckbox("x+24 yp", "Temizle (.lnk)")
        this._cbTemizle.Value := this.coverRecentLnk ? 1 : 0
        this._cbTemizle.OnEvent("Click", (cb, *) => (this.coverRecentLnk := !!cb.Value))
        ; Buton sırası: Yenile | Kapat
        g.AddButton("xm y+10 w145 h30", "🔄 Yenile").OnEvent("Click", (*) => this._refreshBadgeList())
        g.AddButton("x+10 yp w145 h30", "🔒 Kapat").OnEvent("Click", (*) => this._closeFromBadge())
        ; Pencereyi kapatmak (X veya taskbar sağ-tık → Kapat) = incognito kapat
        g.OnEvent("Close", (*) => this._closeFromBadge())
        g.OnEvent("Escape", (*) => this._closeFromBadge())
        g.OnEvent("Size", ObjBindMethod(this, "_onBadgeSize"))  ; restore -> listeyi tazele
        try this._setWinIcon(g.Hwnd, A_ScriptDir "\Files\incognito.ico")
        this._badge := g
        this._refreshBadgeList()
        g.Show("AutoSize NoActivate")
        g.Minimize()        ; ekranda yüzmesin; yalnız taskbar'da buton olarak kalsın
    }

    ; Pencere minimize'den geri açılınca (taskbar'a tıklayınca) listeyi tazele
    _onBadgeSize(guiObj, minMax, w, h) {
        if (minMax = 0)
            this._refreshBadgeList()
    }

    _refreshBadgeList() {
        if (!this._badge)
            return
        try {
            this._badgeInfo.Value := "Donduruldu: " this.handles.Count " jump list dosyası"
            local names := this.getLockedNames(300)
            this._badgeList.Delete()
            if (names.Length)
                this._badgeList.Add(names)
        }
    }

    ; Rozet/pencere event'i İÇİNDE Destroy riskli -> timer ile ertele
    _closeFromBadge() {
        SetTimer(() => this.disable(true), -10)
    }

    _destroyBadge() {
        if (this._badge) {
            try this._badge.Destroy()
            this._badge := 0
            this._cbVlc := 0
            this._cbTemizle := 0
        }
    }

    ; Pencereye (dolayısıyla taskbar butonuna) özel ikon ver — best-effort.
    _setWinIcon(hwnd, icoPath) {
        static WM_SETICON := 0x0080, ICON_SMALL := 0, ICON_BIG := 1
        static IMAGE_ICON := 1, LR_LOADFROMFILE := 0x10
        if (!FileExist(icoPath))
            return
        local hSmall := DllCall("LoadImage", "ptr", 0, "str", icoPath, "uint", IMAGE_ICON, "int", 16, "int", 16, "uint", LR_LOADFROMFILE, "ptr")
        local hBig := DllCall("LoadImage", "ptr", 0, "str", icoPath, "uint", IMAGE_ICON, "int", 32, "int", 32, "uint", LR_LOADFROMFILE, "ptr")
        if (hSmall)
            SendMessage(WM_SETICON, ICON_SMALL, hSmall, , "ahk_id " hwnd)
        if (hBig)
            SendMessage(WM_SETICON, ICON_BIG, hBig, , "ahk_id " hwnd)
    }

}
