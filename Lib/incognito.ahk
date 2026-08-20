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
;  ÜÇ KATMAN (ölçüm sonucu eklendi — jump list tek başına yetmiyordu):
;   1. ÖNLE   : PolicyGuard, oturum boyunca Explorer'ın izlemesini kapatır.
;   2. DONDUR : jump list kilidi (aşağıdaki _lockFile).
;   3. GERİ AL: trace_store snapshot/restore — oturumda oluşan registry ve
;               dosya izleri enable() anındaki haline döndürülür.
;  Tek bir indirme ölçümde 5 ayrı depoya iz bırakıyordu; kilit bunun yalnızca
;  1'ini kapsıyordu. Kapsam listesi için bkz. this.stores.
;
; ────────────────────────────────────────────────────────────────────────
;  GELİŞTİRME NOTLARI (acı çekerek öğrenildi):
;   • Kilit flag'i "rw-": exclusive (FileShare.None), dosyayı truncate ETMEZ.
;     Ampirik test: "rw" tiresiz = paylaşımlı (kilitlemez); tire şart.
;   • Sıralama kritik: snapshot KİLİTLEMEDEN ÖNCE, restore KİLİT AÇILDIKTAN
;     SONRA olmalı — kilitli dosya kopyalanamaz (FileShare.None okumayı da keser).
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
        ; enable()/disable() reg.exe'ye RunWait/ProcessWaitClose ile beklerken
        ; AHK diğer timer/GUI olaylarına ARA VERİR (Critical değiliz) — yani
        ; "Kapat" düğmesine üst üste basmak, ilk disable() daha bitmeden İKİNCİ
        ; bir disable()'ı ÜSTÜNE başlatabiliyordu (this.active henüz false
        ; olmadığı için erken-çıkış kontrolü işe yaramıyordu). Sonuç: aynı
        ; registry anahtarlarına çakışan reg delete/import'lar, "takılmış"
        ; görünüm, gereksiz uzayan süre. Bu bayrak ikinci çağrıyı no-op yapar.
        this._busy := false
        this.handles := Map()           ; fullPath -> FileObject (açık kilit handle'ları)
        this.handles.CaseSense := "Off"
        this._timer := 0
        this.watchPeriod := 700         ; ms — yeni dosyaları yakalama sıklığı
        this._badge := 0                ; taskbar gösterge penceresi (aktifken)
        this._badgeList := 0            ; pencere içindeki kilitli-liste kontrolü
        this._badgeInfo := 0            ; pencere içindeki sayaç metni
        this._cbVlc := 0               ; checkbox kontrolü
        this._cbRestore := 0           ; checkbox kontrolü
        this._btnClose := 0            ; "Kapat" düğmesi — tıklanınca anında devre dışı bırakılır

        local recent := A_AppData "\Microsoft\Windows\Recent\"
        this.dirs := [
            { path: recent "AutomaticDestinations\", ext: "automaticDestinations-ms" },
            { path: recent "CustomDestinations\", ext: "customDestinations-ms" }
        ]

        ; "Son dosyalar" kısayolları (.lnk). Açtığın her dosya buraya kısayol bırakır
        ; (Hızlı Erişim'de görünür). Kilitlemek Explorer'ı bozar -> sürekli SİL.
        ; Eski geçmişi korumak için yalnız oturumda oluşanlar silinir (zaman filtresi).
        ; Bu, oturum SIRASINDA da görünmemesini sağlar; kapanıştaki asıl temizlik
        ; snapshot/restore ile yapılır.
        this.recentDir := recent
        this._sessionStart := 0

        ; ── Katman 3: iz depoları (snapshot + geri yükle) ────────────────
        ; Ölçüm: tek bir indirme bu depoların 5'ine birden yazıyor.
        local E := "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer"
        local SH := "HKCU\Software\Microsoft\Windows\Shell"                                  ; Shellbags (NTUSER.DAT)
        local SC := "HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell"   ; Shellbags + MUICache (UsrClass.dat)
        this.stores := [
            RegStore("RecentDocs", E "\RecentDocs"),                        ; Explorer "son dosyalar"
            RegStore("OpenSavePidlMRU", E "\ComDlg32\OpenSavePidlMRU"),     ; "Farklı kaydet" geçmişi
            RegStore("LastVisitedPidlMRU", E "\ComDlg32\LastVisitedPidlMRU"), ; uygulama başına son klasör
            RegStore("TypedPaths", E "\TypedPaths"),                        ; adres çubuğuna yazılanlar
            RegStore("WordWheelQuery", E "\WordWheelQuery"),                ; Explorer arama kutusu
            RegStore("RunMRU", E "\RunMRU"),                                ; Win+R geçmişi
            ; UserAssist: çalıştırılan GUI programların adı (ROT13) + çalışma
            ; sayısı/son çalışma zamanı — klasik "evidence of execution" izi.
            ; reg export/import ham veriyle çalışır, ROT13 çözmemize gerek yok.
            RegStore("UserAssist", E "\UserAssist"),
            ; MUICache: Explorer'dan başlatılan her programın adı. DİKKAT — çoğu
            ; kaynakta geçen ShellNoRoam\MUICache yolu XP dönemine ait; Win10/11'de
            ; burası (UsrClass.dat hive'ı içinde). Ampirik: eski yol hiç yok, bu 214 kayıt.
            RegStore("MUICache", SC "\MuiCache"),
            ; Shellbags: gezinilen klasörlerin görünüm/boyut/konum geçmişi —
            ; RecentDocs/MRU'nun KAPSAMADIĞI, adli bilişimde ayrıca aranan bir
            ; iz kaynağı (EricZimmerman'ın ShellBags Explorer'ının konusu).
            ; İki hive'da da var: NTUSER.DAT (SH) ve UsrClass.dat (SC), her
            ; ikisinde de BagMRU (gezinilen sıra) + Bags (görünüm ayarları) çifti.
            RegStore("ShellBagMRU", SH "\BagMRU"),
            RegStore("ShellBags", SH "\Bags"),
            RegStore("ShellBagMRU_UsrClass", SC "\BagMRU"),
            RegStore("ShellBags_UsrClass", SC "\Bags"),
            FileGlobStore("RecentLnk", recent, "*.lnk"),
            FileGlobStore("JumpListAuto", recent "AutomaticDestinations\", "*.automaticDestinations-ms"),
            FileGlobStore("JumpListCustom", recent "CustomDestinations\", "*.customDestinations-ms")
        ]
        this.snapDir := A_ScriptDir "\Files\incognito_snapshot\"
        this.restoreOnClose := true     ; badge'daki [x] Geri yükle checkbox'u
        this._baseline := Map()         ; store adı -> enable() anındaki kayıt sayısı

        ; ── Katman 1: önleme ────────────────────────────────────────────
        ; Snapshot/restore'u güvenilir kılan parça: Explorer listeyi bellekte
        ; tutup geri yazabildiği için izlemeyi kaynağında kapatıyoruz.
        this.policy := PolicyGuard([
            { key: E "\Advanced", value: "Start_TrackDocs", data: 0 },
            { key: E "\Advanced", value: "Start_TrackProgs", data: 0 },
            { key: "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer",
              value: "NoRecentDocsHistory", data: 1 }
        ])

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
        if (this.active || this._busy)
            return
        this._busy := true
        try {
            this._recoverStaleSnapshot()         ; önceki oturum çökmüşse önce onu çöz
            this.active := true
            this._sessionStart := A_Now          ; bu andan sonra oluşan .lnk'ler silinecek
            try DirCreate(this.snapDir)
            this.policy.apply()                  ; 1) önle
            this.policy.saveTo(this.snapDir "POLICY.tsv")  ; çökme kurtarma için diske yaz
            this._snapshotAll()                  ; 2) yedekle — KİLİTLEMEDEN ÖNCE olmalı
            this._lockAllExisting()              ; 3) dondur
            this._clearVlcRecents()
            this._timer := ObjBindMethod(this, "_watchTick")
            SetTimer(this._timer, this.watchPeriod)
            this._applyIcon(true)
            this._showBadge()
            if (notify) {
                ShowTip("🔒 Incognito AÇIK — " this.handles.Count " jump list + " this.stores.Length " iz deposu", TipType.Success, 1300)
                SoundBeep(900, 90)
            }
        } finally {
            this._busy := false
        }
    }

    disable(notify := false) {
        if (!this.active || this._busy)
            return
        this._busy := true
        try {
            if (this._timer) {
                SetTimer(this._timer, 0)
                this._timer := 0
            }
            this._unlockAll()                    ; kilit önce açılmalı, yoksa restore kopyalayamaz
            local restored := 0
            if (this.restoreOnClose) {
                restored := this._restoreAll()
                this._refreshShell()
            } else {
                this._discardSnapshot()
            }
            this.policy.revert()
            this.active := false
            this._applyIcon(false)
            this._destroyBadge()
            if (notify) {
                if (this.restoreOnClose)
                    ShowTip("🔓 Incognito kapalı — " restored " iz deposu geri yüklendi", TipType.Success, 1400)
                else
                    ShowTip("🔓 Incognito kapalı (geri yükleme atlandı, izler duruyor)", TipType.Warning, 1600)
                SoundBeep(500, 90)
            }
        } finally {
            this._busy := false
        }
    }

    ; ── Snapshot yaşam döngüsü ──────────────────────────────────────────
    ; SESSION işaret dosyası: varlığı "açık bir oturumun yedeği duruyor"
    ; demek. Script çökerse bir sonraki enable() bunu görüp kurtarma sunar.
    ;
    ; MALİYET (ölçüldü, ilk 7 depoluk sürümde): ~710 ms / ~4 MB — reg export
    ; 343 ms, dosya kopyası 367 ms. enable() bu süre boyunca bloklardı.
    ; Depo sayısı 7'den 12'ye çıkınca (UserAssist + Shellbags) ardışık export
    ; ~600ms'e çıkardı — o yüzden artık iki geçişli: 1) tüm depolar için
    ; işlemi BEKLEMEDEN başlat (RegStore.beginSnapshot -> Run, non-blocking),
    ; 2) hepsini TEK TEK bekle (endSnapshot). Bu noktada reg.exe'ler OS'te
    ; zaten paralel çalışmış oluyor; toplam süre "N × tekil süre" yerine
    ; "en yavaş tekilin süresi"ne yakınsıyor. Snapshot yine de KİLİTLEMEDEN
    ; (_lockAllExisting) ÖNCE tamamen bitmiş olur — yarış riski yok, yalnız
    ; N ayrı bekleme yerine N ayrı BAŞLATMA + tek bir bekleme turu var.
    _snapshotAll() {
        try DirCreate(this.snapDir)
        local pending := Map()
        for s in this.stores {
            try {
                pending[s.name] := s.beginSnapshot(this.snapDir)
            } catch as e {
                try App.ErrHandler.handleError("incognito snapshot begin (" s.name "): " e.Message)
            }
        }
        this._baseline := Map()
        for s in this.stores {
            try {
                s.endSnapshot(this.snapDir, pending.Has(s.name) ? pending[s.name] : 0)
                this._baseline[s.name] := s.count()
            } catch as e {
                try App.ErrHandler.handleError("incognito snapshot end (" s.name "): " e.Message)
            }
        }
        try FileDelete(this.snapDir "SESSION")   ; cleanNow() sırasında ikinci kez çağrılabilir
        try FileAppend(A_Now, this.snapDir "SESSION")
    }

    ; _snapshotAll ile aynı iki-geçişli desen: depo sayısı 7'den 12'ye
    ; çıkınca (UserAssist + Shellbags) ardışık delete+import disable()'ı
    ; ~1-2 saniyeye kadar yavaşlatabiliyordu — bu da "Kapat"a üst üste
    ; basılmasına (ve _busy koruması olmadan çakışan ikinci bir disable()
    ; çağrısına) yol açan asıl sebepti. Silme senkron kalır (zaten hızlı);
    ; İÇE AKTARMA (asıl ağır iş) tüm depolar için BEKLEMEDEN başlatılır,
    ; sonra hepsi TEK TEK beklenir.
    _restoreAll() {
        if (!DirExist(this.snapDir))
            return 0
        local pending := Map()
        for s in this.stores {
            try {
                pending[s.name] := s.beginRestore(this.snapDir)
            } catch as e {
                try App.ErrHandler.handleError("incognito restore begin (" s.name "): " e.Message)
            }
        }
        local n := 0
        for s in this.stores {
            try {
                if (pending.Has(s.name) && s.endRestore(this.snapDir, pending[s.name]))
                    n++
            } catch as e {
                try App.ErrHandler.handleError("incognito restore end (" s.name "): " e.Message)
            }
        }
        this._discardSnapshot()
        return n
    }

    _discardSnapshot() {
        try DirDelete(this.snapDir, true)
    }

    ; Script çökmesi / zorla kapatma sonrası kalan yedek
    _recoverStaleSnapshot() {
        if (!FileExist(this.snapDir "SESSION"))
            return
        ; Politika geri alma, kullanıcının izleri geri yükleyip yüklemeyeceği
        ; kararından BAĞIMSIZ ve önce yapılır: "Hayır" (izler kalsın) derse
        ; bile Start_TrackDocs/Start_TrackProgs kalıcı kapalı takılı kalmasın.
        ; Ayrıca _discardSnapshot() az sonra snapDir'i komple sildiği için
        ; POLICY.tsv'yi okumadan önce davranmak şart.
        PolicyGuard.revertFrom(this.snapDir "POLICY.tsv")
        local ans := MsgBox("Önceki incognito oturumu düzgün kapanmamış — yedek duruyor.`n`n"
            . "Geri yükleyeyim mi? (Hayır = yedeği at, izler kalır)", "Incognito", "YesNo Icon!")
        if (ans = "Yes")
            this._restoreAll()
        else
            this._discardSnapshot()
    }

    ; Explorer son-dosya listesini bellekte tutuyor; geri yükleme sonrası
    ; kabuğu tazelemezsek eski liste ekranda kalmaya devam ediyor.
    _refreshShell() {
        static SHCNE_ASSOCCHANGED := 0x08000000, SHCNF_IDLIST := 0x0000
        try DllCall("shell32\SHChangeNotify", "int", SHCNE_ASSOCCHANGED, "uint", SHCNF_IDLIST, "ptr", 0, "ptr", 0)
    }

    ; ── Denetim ─────────────────────────────────────────────────────────
    ; enable() anındaki sayımla şimdiki sayımı karşılaştırır. Kapsamın
    ; gerçekten çalıştığını ölçmenin tek yolu — yeni hedef eklerken de bu kullanılır.
    audit() {
        local lines := []
        for s in this.stores {
            local now := s.count()
            local base := this._baseline.Has(s.name) ? this._baseline[s.name] : 0
            local diff := now - base
            if (diff != 0)
                lines.Push(Format("{1}: {2}{3}   ({4} → {5})", s.name, (diff > 0 ? "+" : ""), diff, base, now))
        }
        return lines
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
    ; Oturum SIRASINDA da görünmemesi için; kapanıştaki asıl güvence restore.
    _clearRecentLnk(onlySession := true) {
        if (!DirExist(this.recentDir))
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

    ; ── Tam temizlik (cleaner mantığı: sonradan sil) ────────────────────
    ; DİKKAT: geri dönüşü olmayan tek işlem — snapshot/restore'un aksine ESKİ
    ; geçmişi de siler. Bu yüzden öncesinde Files\incognito_backup_<zaman>\
    ; altına kalıcı yedek alınır; istenirse reg dosyaları elle import edilebilir.
    ; Aktifken de çağrılabilir: kilitler açılır, temizlenir, tekrar kilitlenir.
    cleanNow() {
        local wasActive := this.active
        if (wasActive)
            this._unlockAll()

        local bak := A_ScriptDir "\Files\incognito_backup_" FormatTime(A_Now, "yyyyMMdd_HHmmss") "\"
        try DirCreate(bak)
        local count := 0
        for s in this.stores {
            try {
                s.snapshot(bak)
                count += s.purge()
            } catch as e {
                try App.ErrHandler.handleError("incognito cleanNow (" s.name "): " e.Message)
            }
        }
        this._clearVlcRecents()
        this._refreshShell()

        if (wasActive) {
            ; BUG NOTU: oturumun canlı yedeği (this.snapDir, enable() anında
            ; alındı) burada YENİLENMEZSE az önce KALICI silinen kayıtları
            ; hâlâ içerir. disable() → restoreOnClose bunu geri yazar ve
            ; cleanNow()'un "kalıcı temizlik" sözünü boşa çıkarır. Purge
            ; sonrası (artık temiz) durumu yeni taban olarak kaydediyoruz.
            this._snapshotAll()
            this._lockAllExisting()   ; Windows yeniden yaratırsa "boş" halde donsun
        }
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
        ; Checkbox sırası: [x] VLC | [x] Kapanışta geri yükle
        this._cbVlc := g.AddCheckbox("xm y+12", "VLC")
        this._cbVlc.Value := this.coverVlc ? 1 : 0
        this._cbVlc.OnEvent("Click", (cb, *) => (this.coverVlc := !!cb.Value))
        this._cbRestore := g.AddCheckbox("x+24 yp", "Kapanışta geri yükle")
        this._cbRestore.Value := this.restoreOnClose ? 1 : 0
        this._cbRestore.OnEvent("Click", (cb, *) => (this.restoreOnClose := !!cb.Value))
        ; Buton sırası: Denetle | Yenile | Kapat
        g.AddButton("xm y+10 w95 h30", "🔍 Denetle").OnEvent("Click", (*) => this._showAudit())
        g.AddButton("x+8 yp w95 h30", "🔄 Yenile").OnEvent("Click", (*) => this._refreshBadgeList())
        this._btnClose := g.AddButton("x+8 yp w95 h30", "🔒 Kapat")
        this._btnClose.OnEvent("Click", (*) => this._closeFromBadge())
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

    ; Oturum boyunca hangi depoya kaç yeni iz düştüğünü gösterir
    _showAudit() {
        local lines := this.audit()
        local msg := ""
        if (!lines.Length) {
            msg := "Oturum başından beri yeni iz oluşmadı.`n`n"
                . "(Önleme katmanı çalışıyor demektir.)"
        } else {
            msg := "Oturumda oluşan izler — kapanışta geri alınacak:`n`n"
            for l in lines
                msg .= l "`n"
        }
        MsgBox(msg, "🔍 Incognito denetim", "Iconi")
    }

    ; Rozet/pencere event'i İÇİNDE Destroy riskli -> timer ile ertele.
    ; BUG NOTU: disable() artık 12 registry deposu yüzünden ~1-2sn sürebiliyor;
    ; bu süre boyunca düğme tıklanabilir kalırsa her tıklama yeni bir timer
    ; kuruyordu — disable() içindeki _busy koruması bunları artık no-op
    ; yapıyor, ama düğme görsel olarak "tepki vermiyor" gibi durmaya devam
    ; ederdi. Anında devre dışı bırakıp metni değiştirmek, "takılı kaldı mı?"
    ; hissini önlüyor.
    _closeFromBadge() {
        if (this._busy || !this.active)
            return
        if (this._btnClose) {
            try this._btnClose.Enabled := false
            try this._btnClose.Text := "Kapanıyor…"
        }
        SetTimer(() => this.disable(true), -10)
    }

    _destroyBadge() {
        if (this._badge) {
            try this._badge.Destroy()
            this._badge := 0
            this._cbVlc := 0
            this._cbRestore := 0
            this._btnClose := 0
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
