; ════════════════════════════════════════════════════════════════════════
;  incognito.ahk — Windows "Incognito" (Jump List dondurma) modülü
; ────────────────────────────────────────────────────────────────────────
;  ÜÇ KATMAN — jump list kilidi tek başına yetmiyordu (tek bir indirme 5 ayrı
;  depoya iz bırakıyor, kilit bunun 1'ini kapsıyordu):
;   1. ÖNLE   : PolicyGuard, oturum boyunca Explorer'ın izlemesini kapatır.
;   2. DONDUR : jump list kilidi (_lockFile).
;   3. GERİ AL: trace_store snapshot/restore.
;
;  İKİ KURAL — bozarsan sessizce veri kaybedersin:
;   • Kilit flag'i "r-". "w-" ASLA — AHK'da "w" dosyayı SIFIRLAR (bkz.
;     _lockFile). Tiresiz "rw" ise hiç kilitlemez; tire şart.
;   • Snapshot KİLİTLEMEDEN ÖNCE, restore KİLİT AÇILDIKTAN SONRA — kilitli
;     dosya kopyalanamaz (FileShare.None okumayı da keser).
;
;  Hız çalışmasının ölçümleri ve gerekçeleri: incognito-hizlandirma-plani.md
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
        ; Critical değiliz: ProcessWaitClose sırasında AHK timer/GUI olaylarına
        ; ara veriyor, yani uzun süren enable()/disable()'ın ORTASINDA ikinci
        ; bir çağrı gelebiliyor. Bu bayrak onu no-op yapar; iş yapan HER giriş
        ; noktası (enable, disable, setDeepMode, _closeFromBadge) bakmak zorunda.
        this._busy := false
        this.handles := Map()           ; fullPath -> FileObject (açık kilit handle'ları)
        this.handles.CaseSense := "Off"
        this._timer := 0
        this.watchPeriod := 700         ; ms — yeni dosyaları yakalama sıklığı
        this._badge := 0                ; taskbar gösterge penceresi (aktifken)
        this._badgeList := 0
        this._badgeInfo := 0
        this._cbVlc := 0
        this._cbRestore := 0
        this._cbDeep := 0
        this._btnClose := 0
        this._hIconSmall := 0           ; bkz. _setWinIcon / _freeWinIcons
        this._hIconBig := 0

        local recent := A_AppData "\Microsoft\Windows\Recent\"
        this.dirs := [
            { path: recent "AutomaticDestinations\", ext: "automaticDestinations-ms" },
            { path: recent "CustomDestinations\", ext: "customDestinations-ms" }
        ]

        ; "Son dosyalar" kısayolları. Kilitlemek Explorer'ı bozuyor -> sürekli
        ; SİL, ama yalnız oturumda oluşanları (eski geçmiş korunsun).
        this.recentDir := recent
        this._sessionStart := 0

        ; ── Katman 3: iz depoları (snapshot + geri yükle) ────────────────
        ; SIRA ÖNEMLİ — EN AĞIR DEPO EN ÖNDE; başlatma sırası bu. Yeni depo
        ; eklerken ölçüp ağırlığına göre yerleştir, sona ekleme.
        ;
        ; KADEME: core = DOSYA ADI taşıyan izler (varsayılan açık).
        ;         deep = klasör gezinme + program çalıştırma izleri, dosya adı
        ;                tutmaz; maliyetin büyük kısmı burada (varsayılan
        ;                kapalı, rozetteki "Derin izler" kutusundan açılır).
        ;
        ; BİLEREK KAPSAM DIŞI (araştırıldı, ölçüldü, elendi):
        ;  • Thumbcache (thumbcache_*.db) — MODÜLÜN EN BÜYÜK AÇIĞI. Önizlenen
        ;    her görselin küçük resmi orada kalıyor, DOSYA SİLİNSE BİLE
        ;    (~1,1 GB). Explorer açık tuttuğu için ne kilitlenebiliyor ne
        ;    silinebiliyor; önleme kolu Explorer restart istiyor olabilir.
        ;  • Windows Timeline — CDPUserSvc'de kilitli, politika HKLM, Win11'de yok.
        ;  • Prefetch / SRUM / ShimCache / BAM / olay günlükleri — admin ister;
        ;    bu modül bilinçli HKCU-only.
        ;  • MountPoints2 — var ama bu makinede USB kullanılmıyor.
        local E := "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer"
        local SH := "HKCU\Software\Microsoft\Windows\Shell"                                  ; Shellbags (NTUSER.DAT)
        local SC := "HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell"   ; Shellbags + MUICache (UsrClass.dat)
        this.allStores := [
            ; Shellbags çifti: BagMRU = gezinilen klasör sırası (asıl kanıt, tam
            ; snapshot şart), Bags = yalnız görünüm ayarı ama maliyetin ~%90'ıydı
            ; -> delta yoluna alındı.
            RegStore("ShellBagMRU_UsrClass", SC "\BagMRU", "deep"),         ; 2.75 MB — en ağır, klasör izi
            RegStore("OpenSavePidlMRU", E "\ComDlg32\OpenSavePidlMRU"),     ; "Farklı kaydet"te seçilen DOSYA adları — 1.70 MB
            RegStore("RecentDocs", E "\RecentDocs"),                        ; Explorer "son dosyalar" — 1.28 MB
            RegStore("UserAssist", E "\UserAssist", "deep"),                ; çalıştırılan programlar (ROT13) — 231 KB
            RegDeltaStore("ShellBags_UsrClass", SC "\Bags", "deep"),        ; BagMRU_UsrClass ile EŞLİ, bkz. this.coupled
            ; ComDlg32'nin DÖRDÜ birden kapsamda: ikisini bırakmak kapıyı yarı
            ; kapatmak oluyordu.
            RegStore("LastVisitedPidlMRU", E "\ComDlg32\LastVisitedPidlMRU"), ; uygulama başına son klasör — 55 KB
            RegStore("CIDSizeMRU", E "\ComDlg32\CIDSizeMRU", "deep"),       ; Aç/Kaydet penceresi açan programlar — 199 KB
            RegStore("FirstFolder", E "\ComDlg32\FirstFolder", "deep"),     ; Aç/Kaydet'te ilk gösterilen klasör
            RegStore("FeatureUsage", E "\FeatureUsage", "deep"),            ; hangi program kaç kez öne getirildi
            RegStore("ShellBags", SH "\Bags", "deep"),                      ; NTUSER tarafı; küçük ama kapsamda
            RegStore("ShellBagMRU", SH "\BagMRU", "deep"),
            RegStore("WordWheelQuery", E "\WordWheelQuery", "deep"),        ; Explorer arama kutusu
            RegStore("TypedPaths", E "\TypedPaths", "deep"),                ; adres çubuğuna yazılanlar
            RegStore("RunMRU", E "\RunMRU", "deep"),                        ; Win+R geçmişi
            ; DİKKAT: kaynaklarda geçen ShellNoRoam\MUICache XP'ye ait, burada
            ; yok; Local Settings\MuiCache\<n>\<hash> ise BAŞKA bir şey.
            RegStore("MUICache", SC "\MuiCache", "deep"),                   ; Explorer'dan başlatılan program adları
            FileGlobStore("RecentLnk", recent, "*.lnk"),
            FileGlobStore("JumpListAuto", recent "AutomaticDestinations\", "*.automaticDestinations-ms"),
            FileGlobStore("JumpListCustom", recent "CustomDestinations\", "*.customDestinations-ms")
        ]

        ; EŞLİ DEPOLAR — birlikte geri yüklenmek ZORUNDA. Delta silmesi boş
        ; NodeSlot bırakıyor; slotun yeniden kullanılmaması NodeSlots bitmap'ini
        ; İÇEREN BagMRU deposunun tam geri yüklenmesine bağlı. Üyeler aynı
        ; kademede olmalı, yoksa delta deposu kardeşsiz çalışıp sızdırır.
        this.coupled := [["ShellBags_UsrClass", "ShellBagMRU_UsrClass"]]
        this.snapDir := A_ScriptDir "\Files\incognito_snapshot\"
        this.optFile := A_ScriptDir "\Files\incognito.ini"
        this.restoreOnClose := true     ; badge'daki [x] Geri yükle checkbox'u
        this.deepMode := this._readOpt("deep", false)   ; varsayılan KAPALI
        this.stores := this._selectStores()
        this._lastSkipped := 0          ; son disable()'da dokunulmamış depo sayısı
        this._snapGen := 0              ; ertelenmiş yedek silmesini geçersiz kılan sayaç
        this._pendingSnap := 0          ; beklenmemiş yedek; bkz. _finishSnapshot
        this._pendingPid := 0           ; toplu reg export'un cmd.exe pid'i (yoklama için)

        ; Adım adım süreyi Files\incognito_perf.log'a yazar; kapalıyken maliyet sıfır.
        this.perfLog := true
        this._perfBuf := ""
        this._perfT := 0
        this._perfT0 := 0

        ; ── Katman 1: önleme ────────────────────────────────────────────
        ; Explorer listeyi bellekte tutup geri yazabildiği için izlemeyi
        ; kaynağında kapatmak snapshot/restore'u güvenilir kılan parça.
        this.policy := PolicyGuard([
            { key: E "\Advanced", value: "Start_TrackDocs", data: 0 },
            { key: E "\Advanced", value: "Start_TrackProgs", data: 0 },
            { key: "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer",
              value: "NoRecentDocsHistory", data: 1 }
        ])

        ; Uygulama-içi geçmiş dosyaları. Kilitlemek uygulamayı bozabildiği için
        ; varsayılan BOŞ; addExtraTarget() ile eklenir.
        this.extraTargets := []

        ; VLC: kilit yerine "sürekli boşalt" (kilitlemek VLC'yi bozuyor).
        this.coverVlc := true
        this.vlcIni := A_AppData "\vlc\vlc-qt-interface.ini"

        this.appIds := this._loadAppIds()   ; hex(lower) -> friendly name
    }

    ; ── Kademe ──────────────────────────────────────────────────────────
    ; Oturumda kapsanacak depolar. Sıra korunur (en ağır önde).
    _selectStores() {
        if (this.deepMode)
            return this.allStores.Clone()
        local sel := []
        for s in this.allStores {
            if (s.tier = "core")
                sel.Push(s)
        }
        return sel
    }

    ; Derin izleri aç/kapat. AKTİFKEN de çağrılabilir: açarken yedek O AN
    ; alınır (öncesi kapsam dışı kalır — yedek geçmişe gidemez), kapatırken
    ; o depolardaki oturum izleri KALIR.
    setDeepMode(on) {
        ; _busy ŞART (bkz. __New): enable/disable ProcessWaitClose'ta beklerken
        ; GUI olayları araya giriyor. Korumasız kalırsa bu metod this.stores'u
        ; _restoreAll'ın iki döngüsü arasında değiştirip changed[] aramasını
        ; patlatıyor — hem de disable()'ın try/finally'sinde catch yok.
        if (this._busy) {
            if (this._cbDeep)                       ; kutuyu gerçek duruma geri al
                try this._cbDeep.Value := this.deepMode ? 1 : 0
            return
        }
        on := !!on
        if (on = this.deepMode)
            return
        this.deepMode := on
        this._writeOpt("deep", on)
        if (!this.active) {
            this.stores := this._selectStores()
            return
        }
        ; Kapsam değişiyor; bekleyen yedek yarım kalmasın.
        this._finishSnapshot()
        local before := Map()
        for s in this.stores
            before[s.name] := true
        local next := this._selectStores()
        if (on) {
            local added := []
            for s in next {
                if (!before.Has(s.name))
                    added.Push(s)
            }
            this.stores := next
            this._snapshotStores(added)
        } else {
            local dropped := []
            for s in this.stores {
                if (s.tier = "deep")
                    dropped.Push(s)
            }
            this.stores := next
            ; Her depo tipinin yedek uzantısı — yeni tip eklenirse buraya da
            ; eklenmeli, yoksa kapsam dışına çıkan depo yedek sızdırır.
            for s in dropped {
                try s.endWatch()
                for ext in [".reg", ".hwm", ".absent", ".pack"]
                    try FileDelete(this.snapDir s.name ext)
                try DirDelete(this.snapDir s.name, true)
            }
        }
        this._refreshBadgeList()
    }

    ; Oturum ORTASINDA kapsama giren depoları yedekle. Bekleme senkron: iş
    ; birkaç depo, kullanıcı da kutuyu az önce tıkladı.
    _snapshotStores(list) {
        if (!list.Length)
            return
        try DirCreate(this.snapDir)
        for s in list {
            try s.beginWatch()
        }
        local pending := Map()
        for s in list {
            try pending[s.name] := s.beginSnapshot(this.snapDir)
        }
        for s in list {
            try s.endSnapshot(this.snapDir, pending.Has(s.name) ? pending[s.name] : 0)
        }
    }

    ; ── Ayar kalıcılığı (Files\incognito.ini) ───────────────────────────
    _readOpt(name, def) {
        local v := ""
        try {
            v := IniRead(this.optFile, "opts", name, def ? "1" : "0")
        } catch {
            return def
        }
        return (v = "1")
    }
    _writeOpt(name, val) {
        try IniWrite(val ? "1" : "0", this.optFile, "opts", name)
    }

    ; ── Durum ───────────────────────────────────────────────────────────
    isActive() => this.active
    lockedCount() => this.handles.Count

    ; ── Aç / Kapa ───────────────────────────────────────────────────────
    toggle() {
        ; v2.1-alpha: çıplak ternary-statement syntax error verir -> if/else.
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
            this._perfStart("ENABLE")
            this._recoverStaleSnapshot()         ; önceki oturum çökmüşse önce onu çöz
            this._perfMark("recoverStale")
            this.active := true
            this.stores := this._selectStores()  ; kademe her açılışta yeniden okunur
            this._sessionStart := A_Now          ; bu andan sonra oluşan .lnk'ler silinecek
            try DirCreate(this.snapDir)
            this.policy.apply()                  ; 1) önle
            this._perfMark("policy.apply")
            this.policy.saveTo(this.snapDir "POLICY.tsv")  ; çökme kurtarma için diske yaz
            this._perfMark("policy.saveTo")
            ; 2) yedekle — İKİ PARÇA, arada kilitleme. KASITLI: kilitlemenin
            ;    beklemesi gereken tek şey DOSYA yedekleri (kilitli jump list
            ;    kopyalanamaz) ve onlar _snapshotBegin içinde senkron bitiyor;
            ;    registry export'larının kilitle ilgisi yok, ikisi örtüşüyor.
            ;    YENİ DEPO EKLERKEN: beginSnapshot'ı asenkron olan bir depo
            ;    DOSYAYA dokunuyorsa bu sıra bozulur — o depoyu senkron yap.
            this._pendingSnap := this._snapshotBegin()
            this._perfMark("snapshotBegin")
            this._lockAllExisting()              ; 3) dondur
            this._perfMark("lockAllExisting")
            ; Export'ları BEKLEMEDEN dönüyoruz; bitişi _watchTick yokluyor,
            ; yedeğe DOKUNAN her yol da _finishSnapshot() ile garantiliyor.
            this._clearVlcRecents()
            this._perfMark("clearVlcRecents")
            this._timer := ObjBindMethod(this, "_watchTick")
            SetTimer(this._timer, this.watchPeriod)
            this._applyIcon(true)
            this._perfMark("applyIcon")
            this._perfEnd()
            ; Rozet (47 ms) ve ses (78 ms) kritik yolda değil. EN SONDA: -1
            ; timer bu thread'i kesebiliyor, kesilecek kod az kalsın.
            SetTimer(() => this._afterEnable(notify), -1)
        } finally {
            this._busy := false
        }
    }

    disable(notify := false) {
        if (!this.active || this._busy)
            return
        this._busy := true
        try {
            this._perfStart("DISABLE")
            if (this._timer) {
                SetTimer(this._timer, 0)
                this._timer := 0
            }
            ; Yarım yedekle geri yükleme = o depoların oturum izini kalıcı bırakmak.
            this._finishSnapshot()
            this._perfMark("finishSnapshot")
            this._unlockAll()                    ; kilit önce açılmalı, yoksa restore kopyalayamaz
            this._perfMark("unlockAll")
            local restored := 0
            if (this.restoreOnClose) {
                ; true = yedeği silmeyi ERTELE (bkz. _discardSnapshotLater).
                ; Kurtarma yolunda false kalır: orada hemen yeni yedek alınıyor.
                restored := this._restoreAll(true)
                this._perfMark("restoreAll")
                this._refreshShell()
                this._perfMark("refreshShell")
            } else {
                this._closeAllWatches()
                this._discardSnapshot()
                this._perfMark("discardSnapshot")
            }
            this.policy.revert()
            this._perfMark("policy.revert")
            this.active := false
            this._applyIcon(false)
            this._perfMark("applyIcon")
            this._destroyBadge()
            this._perfMark("destroyBadge")
            if (notify) {
                if (this.restoreOnClose) {
                    local skipNote := this._lastSkipped ? " (" this._lastSkipped " depoya hiç dokunulmamış)" : ""
                    ShowTip("🔓 Incognito kapalı — " restored " iz deposu geri yüklendi" skipNote, TipType.Success, 1400)
                } else {
                    ShowTip("🔓 Incognito kapalı (geri yükleme atlandı, izler duruyor)", TipType.Warning, 1600)
                }
                SetTimer(() => SoundBeep(500, 90), -1)   ; senkron 78 ms blokluyor
                this._perfMark("tip")
            }
            this._perfEnd()
        } finally {
            this._busy := false
        }
    }

    ; enable() DÖNDÜKTEN sonra. Yalnız kozmetik iş konur — koruma adımı
    ; buraya taşınırsa açıkta pencere kalır.
    _afterEnable(notify) {
        if (!this.active)                        ; arada kapatıldıysa rozet açma
            return
        this._showBadge()
        if (notify) {
            ShowTip("🔒 Incognito AÇIK — " this.handles.Count " jump list + " this.stores.Length " iz deposu"
                . (this.deepMode ? " (derin)" : ""), TipType.Success, 1300)
            SoundBeep(900, 90)
        }
    }

    ; ── Süre ölçümü (bkz. this.perfLog) ─────────────────────────────────
    ; _perfStart -> _perfMark × N -> _perfEnd. _perfSub faz saatini SIFIRLAMADAN
    ; alt satır ekler. A_TickCount çözünürlüğü ~15.6 ms: 15/16/31 tek bir "tick"
    ; demek — küçük satırları tek tek yorumlama, TOPLAM'a bak.
    _perfStart(phase) {
        if (!this.perfLog)
            return
        this._perfT0 := A_TickCount
        this._perfT := this._perfT0
        this._perfBuf := "=== " phase " @ " FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss") " ===`r`n"
    }
    _perfMark(label) {
        if (!this.perfLog)
            return
        local now := A_TickCount
        this._perfBuf .= Format("  {:-22} {:6} ms`r`n", label, now - this._perfT)
        this._perfT := now
    }
    _perfSub(label, ms) {
        if (!this.perfLog || this._perfBuf = "")
            return
        this._perfBuf .= Format("      - {:-18} {:6} ms`r`n", label, ms)
    }
    ; Süre değil, sayı/durum bilgisi için (ms yazmasın).
    _perfNote(text) {
        if (!this.perfLog || this._perfBuf = "")
            return
        this._perfBuf .= "      - " text "`r`n"
    }
    _perfEnd() {
        if (!this.perfLog)
            return
        this._perfBuf .= Format("  {:-22} {:6} ms`r`n`r`n", "TOPLAM", A_TickCount - this._perfT0)
        try FileAppend(this._perfBuf, A_ScriptDir "\Files\incognito_perf.log", "UTF-8")
        this._perfBuf := ""
    }

    ; Tek parçalı yedek (cleanNow ve kurtarma yolları için). enable() bunu
    ; KULLANMAZ — orada begin/end ayrı çağrılıp araya kilitleme giriyor.
    _snapshotAll() {
        this._pendingSnap := this._snapshotBegin()
        this._finishSnapshot()
    }

    ; Bekleyen yedeği TAMAMLA (idempotent). enable() export'ları beklemeden
    ; döndüğü için, yedeğin İÇERİĞİNE bakan her giriş noktası (disable / audit /
    ; setDeepMode / cleanNow) önce bunu beklemeli çağırmalı.
    ; wait=false: yalnız yokla, koşuyorsa bloklamadan çık.
    _finishSnapshot(wait := true) {
        if (!this._pendingSnap)
            return
        if (!wait && this._pendingPid && ProcessExist(this._pendingPid))
            return                           ; export sürüyor, sonraki tura bırak
        local pending := this._pendingSnap
        this._pendingSnap := 0               ; önce temizle: yeniden girişte döngü olmasın
        local t := A_TickCount
        this._snapshotEnd(pending)
        if (!this.perfLog)
            return
        ; Açık bir fazın içindeysek ona satır ekle; _perfStart burada tamponu ezerdi.
        if (this._perfBuf != "") {
            this._perfMark("endSnapshot(ertelenmis)")
        } else {
            try FileAppend(Format("  [arka plan] endSnapshot (ertelenmis) : {} ms`r`n`r`n", A_TickCount - t)
                , A_ScriptDir "\Files\incognito_perf.log", "UTF-8")
        }
    }

    ; ── Yedeğin BAŞLATMA yarısı ─────────────────────────────────────────
    ; Dönüş: depo adı -> endSnapshot'a verilecek "pending" değeri.
    _snapshotBegin() {
        ; Ertelenmiş yedek silmesini (bkz. _discardSnapshotLater) iptal edip işini
        ; burada senkron yapıyoruz: yoksa 400 ms sonraki timer TAZE yedeği siler.
        ; Atlamak da olmaz — eski dosyalar yenileriyle karışır.
        local _pt := A_TickCount
        this._snapGen++
        this._clearSnapPayload()
        try DirCreate(this.snapDir)
        this._perfSub("clearSnapPayload", A_TickCount - _pt)

        ; SESSION = "açık bir oturumun yedeği duruyor"; çökme sonrası kurtarmayı
        ; bu tetikliyor. EN BAŞTA yazılmalı — sonda yazılırsa export ortasındaki
        ; çökme "yedek yok" gibi görünüp POLICY.tsv okunmuyor ve Start_TrackDocs
        ; kapalı takılı kalıyordu.
        try FileDelete(this.snapDir "SESSION")   ; cleanNow() ikinci kez çağırabilir
        try FileAppend(A_Now, this.snapDir "SESSION")

        ; Gözcüler export'tan ÖNCE kurulur — sıralama şart, bkz. RegStore.beginWatch.
        _pt := A_TickCount
        for s in this.stores {
            try s.beginWatch()
        }
        this._perfSub("beginWatch×" this.stores.Length, A_TickCount - _pt)

        local pending := Map()

        ; 1) reg.exe'li depolar: hepsi TEK cmd.exe'de. Her ayrı `Run` bizim
        ;    thread'imizde ~17 ms tutuyor (14 depo = 235 ms), tek cmd 16 ms.
        _pt := A_TickCount
        local batch := []
        this._pendingPid := 0
        for s in this.stores {
            if (s.usesRegExport())
                batch.Push(s)
        }
        this._launchRegBatch(batch, pending)
        this._perfSub("regBatch×" batch.Length, A_TickCount - _pt)

        ; 2) kalanlar (dosya kopyası, delta) — senkron, süreç başlatmıyorlar.
        _pt := A_TickCount
        for s in this.stores {
            if (s.usesRegExport())
                continue
            local _st := A_TickCount
            try {
                pending[s.name] := s.beginSnapshot(this.snapDir)
            } catch as e {
                try App.ErrHandler.handleError("incognito snapshot begin (" s.name "): " e.Message)
            }
            if (A_TickCount - _st >= 30)
                this._perfSub("  kopyaladi: " s.name, A_TickCount - _st)
        }
        this._perfSub("beginSnapshot(yerel)", A_TickCount - _pt)
        return pending
    }

    ; ── Yedeğin BEKLEME yarısı ──────────────────────────────────────────
    _snapshotEnd(pending) {
        local _pt := A_TickCount
        for s in this.stores {
            local _st := A_TickCount
            try {
                s.endSnapshot(this.snapDir, pending.Has(s.name) ? pending[s.name] : 0)
            } catch as e {
                try App.ErrHandler.handleError("incognito snapshot end (" s.name "): " e.Message)
            }
            ; Yalnız gerçekten bekleten depoyu yaz — 18 satır gürültü olmasın.
            if (A_TickCount - _st >= 30)
                this._perfSub("  bekledi: " s.name, A_TickCount - _st)
        }
        this._perfSub("endSnapshot×" this.stores.Length, A_TickCount - _pt)
        ; Taban sayımı burada YAPILMAZ; audit() yedekten türetiyor (bkz.
        ; TraceStore.baselineCount).
    }

    ; Export'ları TEK cmd.exe'de zincirler, pid'i her depo için `pending`e
    ; yazar (ilk bekleyiş süreci kapattığı için sonrakiler anında döner).
    ;
    ; TIRNAKLAMA: dış tırnak YOK (`cmd /c a & b`). `cmd /c "a & b"` biçiminde
    ; cmd dış tırnağı soyup yeniden ayrıştırıyor ve "Local Settings" gibi
    ; boşluklu yollardaki iç tırnaklar bozuluyor.
    _launchRegBatch(list, pending) {
        if (!list.Length)
            return
        local cmd := ""
        local queued := []
        for s in list {
            local one := ""
            try {
                one := s.prepareExport(this.snapDir)
            } catch as e {
                ; pending'e HİÇ girmesin: endSnapshot "yedek alınamadı" sayar
                ; ve restore dokunmaz — sessizce silinmesinden iyidir.
                try App.ErrHandler.handleError("incognito prepareExport (" s.name "): " e.Message)
                continue
            }
            cmd .= (cmd = "" ? "" : " & ") one
            queued.Push(s)
        }
        if (!queued.Length)
            return
        ; cmd /c satır sınırı ~8191 karakter. Bu listeyle ~3,3 KB; yine de
        ; aşılırsa toplu yoldan vazgeçip depo depo başlat (yavaş ama doğru).
        if (StrLen(cmd) > 7500) {
            this._perfNote("regBatch: komut cok uzun, depo depo baslatiliyor")
            local solo := 0
            for s in queued {
                solo := 0
                try solo := s.beginSnapshot(this.snapDir)
                pending[s.name] := solo
                ; _pendingPid burada da DOLDURULMALI: _finishSnapshot(false)
                ; yoklayacak bir pid bulamazsa bloklamama sözünü tutamıyor ve
                ; _watchTick timer'ının içinde depo başına 5 sn bekliyor.
                if (solo)
                    this._pendingPid := solo
            }
            return
        }
        local pid := 0
        try Run(A_ComSpec ' /c ' cmd, , "Hide", &pid)
        this._pendingPid := pid          ; _finishSnapshot(false) bunu yoklar
        for s in queued
            pending[s.name] := pid
    }

    ; Silme senkron (RegDeleteKey, süreç başlatmıyor); İÇE AKTARMA beklemeden
    ; başlatılıp sonra hep birlikte bekleniyor.
    ;
    ; ASIL HIZLANMA: önce her depoya "oturumda sana hiç dokunuldu mu?" diye
    ; soruluyor (RegStore.hasChanged); dokunulmadıysa sil+geri yaz TAMAMEN
    ; atlanıyor. Kanıt yoksa hasChanged() true döner ve tam yol işler.
    _restoreAll(deferDiscard := false) {
        if (!DirExist(this.snapDir))
            return 0

        ; 1) Soruyu SOR ve gözcüyü KAPAT. Kapatmak silmeden önce olmalı:
        ;    silinecek anahtarın üzerinde açık KEY_NOTIFY handle'ı kalmasın.
        local changed := Map()
        for s in this.stores {
            local ch := true
            try ch := s.hasChanged()
            try s.endWatch()
            changed[s.name] := ch
        }

        ; 1b) EŞLİ DEPOLARI HİZALA (bkz. this.coupled). Gözcü her depoyu bağımsız
        ;     değerlendiriyor; ama delta silme ile kardeşinin NodeSlots bitmap'i
        ;     aynı anda eski hale dönmezse boşalan slot yeniden kullanılır ve
        ;     delta o bag'i kaçırır. Biri değiştiyse hepsi değişmiş sayılır.
        for grp in this.coupled {
            local any := false
            for nm in grp {
                if (changed.Has(nm) && changed[nm])
                    any := true
            }
            if (!any)
                continue
            for nm in grp {
                if (changed.Has(nm))
                    changed[nm] := true
            }
        }

        local skipped := 0
        for s in this.stores {
            if (!changed[s.name])
                skipped++
        }
        this._lastSkipped := skipped
        this._perfNote("dokunulmamis (atlanan) depo: " skipped " / " this.stores.Length)

        ; 2) Değişmiş depolar için işi beklemeden başlat.
        local pending := Map()
        local _pt := A_TickCount
        for s in this.stores {
            if (!changed[s.name])
                continue
            local _st := A_TickCount
            try {
                pending[s.name] := s.beginRestore(this.snapDir)
            } catch as e {
                try App.ErrHandler.handleError("incognito restore begin (" s.name "): " e.Message)
            }
            if (A_TickCount - _st >= 30)
                this._perfSub("  sildi: " s.name, A_TickCount - _st)
        }
        this._perfSub("beginRestore", A_TickCount - _pt)
        _pt := A_TickCount
        ; 3) Hepsini birlikte bekle.
        local n := 0
        for s in this.stores {
            if (!pending.Has(s.name))
                continue
            local _st := A_TickCount
            try {
                if (s.endRestore(this.snapDir, pending[s.name]))
                    n++
            } catch as e {
                try App.ErrHandler.handleError("incognito restore end (" s.name "): " e.Message)
            }
            if (A_TickCount - _st >= 30)
                this._perfSub("  bekledi: " s.name, A_TickCount - _st)
        }
        this._perfSub("endRestore", A_TickCount - _pt)
        if (deferDiscard)
            this._discardSnapshotLater()
        else
            this._discardSnapshot()
        return n
    }

    _discardSnapshot() {
        try DirDelete(this.snapDir, true)
    }

    ; Yedek klasörünü boşalt ama POLICY.tsv'YE DOKUNMA — enable() sırası
    ; "policy.saveTo -> _snapshotBegin" olduğu için düz _discardSnapshot() az
    ; önce yazılan POLICY.tsv'yi de siliyordu; çökme sonrası revertFrom()
    ; dosyayı bulamıyor ve Start_TrackDocs kapalı takılı kalıyordu.
    _clearSnapPayload() {
        if (!DirExist(this.snapDir))
            return
        Loop Files, this.snapDir "*.*", "FD" {
            if (A_LoopFileName = "POLICY.tsv")
                continue
            ; Süslü parantez ŞART: parantezsiz `try` gövdesinden sonra gelen
            ; `else` v2'de "Unexpected Else" veriyor.
            if (InStr(A_LoopFileAttrib, "D")) {
                try DirDelete(A_LoopFileFullPath, true)
            } else {
                try FileDelete(A_LoopFileFullPath)
            }
        }
    }

    ; Yedeği silmenin disable()'ın kritik yolunda işi yok. İki incelik:
    ;  • SESSION SENKRON silinir; ertelenirse arada bir çökme sıradaki
    ;    enable()'da gereksiz "kurtarayım mı?" sorusu çıkarır.
    ;  • Kuşak sayacı: bu arada yeniden enable() edilirse timer TAZE yedeği
    ;    silmeden geri çekilir.
    _discardSnapshotLater() {
        try FileDelete(this.snapDir "SESSION")
        local gen := ++this._snapGen
        SetTimer(() => (gen = this._snapGen ? this._discardSnapshot() : 0), -400)
    }

    ; Geri yükleme yapılmayan yollar için (restore yolunda _restoreAll zaten depo
    ; depo kapatıyor). Her enable() depo başına anahtar+event açıyor.
    _closeAllWatches() {
        for s in this.stores {
            try s.endWatch()
        }
    }

    ; Script çökmesi / zorla kapatma sonrası kalan yedek
    _recoverStaleSnapshot() {
        if (!FileExist(this.snapDir "SESSION"))
            return
        ; Politika geri alma kullanıcının kararından BAĞIMSIZ ve ÖNCE yapılır:
        ; "Hayır" dese bile Start_TrackDocs kapalı takılı kalmasın — ayrıca
        ; _discardSnapshot() az sonra POLICY.tsv'yi de silecek.
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
    ; enable() anındaki sayımla şimdikini karşılaştırır. Taban YEDEKTEN
    ; türetiliyor (bkz. TraceStore.baselineCount), yani maliyet enable()'a
    ; değil bu çağrıya yazılıyor: 6,2 MB .reg ayrıştırmak ~330 ms.
    audit() {
        local lines := []
        this._finishSnapshot()          ; taban yedekten okunuyor -> yedek tam olmalı
        if (!DirExist(this.snapDir))
            return ["Yedek klasörü yok — denetim yapılamıyor."]
        for s in this.stores {
            local ln := ""
            try {
                ln := s.auditLine(this.snapDir)
            } catch as e {
                ln := s.name ": denetlenemedi (" e.Message ")"
            }
            if (ln != "")
                lines.Push(ln)
        }
        return lines
    }

    ; ── Kilit primitive'leri ────────────────────────────────────────────
    _lockFile(path) {
        if (this.handles.Has(path))
            return false
        local f := ""
        try {
            ; "r-" : r = salt okuma, "-" = dış süreçlere KAPALI (dwShareMode=0).
            ; Dışlamayı erişim modu değil PAYLAŞIM modu ("-") sağlıyor; tiresiz
            ; "rw" hiç kilitlemez.
            ; "w-" KULLANMA: AHK'da "w" dosyayı TRUNCATE eder — ölçerken 49 jump
            ; list dosyası bu yüzden sıfırlandı.
            f := FileOpen(path, "r-")
        } catch {
            return false                 ; o an Windows tutuyor olabilir; timer tekrar dener
        }
        if (!IsObject(f))
            return false
        this.handles[path] := f
        return true
    }

    _lockAllExisting() {
        local _n := 0, _slow := 0, _worst := 0, _worstName := ""
        for d in this.dirs {
            if (!DirExist(d.path))
                continue
            Loop Files, d.path "*." d.ext {
                local _st := A_TickCount
                this._lockFile(A_LoopFileFullPath)
                local _d := A_TickCount - _st
                _n++
                if (_d >= 30)
                    _slow++
                if (_d > _worst) {
                    _worst := _d
                    _worstName := A_LoopFileName
                }
            }
        }
        ; Dağılım sorunun cinsini söyler: hepsi yavaşsa sistemik (AV), tekse o dosya.
        this._perfNote(_n " dosya, 30ms+ suren: " _slow ", en yavas: " _worst " ms (" _worstName ")")
        for t in this.extraTargets {
            if (FileExist(t))
                this._lockFile(t)
        }
    }

    _watchTick() {
        this._finishSnapshot(false)   ; ertelenmiş yedeği YOKLA (bloklamadan)
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

    ; onlySession=true: yalnız oturumda oluşanlar (eski geçmiş korunur).
    ; Oturum SIRASINDA da görünmesin diye; asıl güvence kapanıştaki restore.
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

    ; ── Tam temizlik ────────────────────────────────────────────────────
    ; DİKKAT: geri dönüşü olmayan tek işlem — snapshot/restore'un aksine ESKİ
    ; geçmişi de siler. Öncesinde Files\incognito_backup_<zaman>\ altına kalıcı
    ; yedek alınır. Aktifken de çağrılabilir: aç, temizle, tekrar kilitle.
    cleanNow() {
        local wasActive := this.active
        this._finishSnapshot()      ; yarım export'lar silinenleri yedeğe sokmasın
        if (wasActive)
            this._unlockAll()

        local bak := A_ScriptDir "\Files\incognito_backup_" FormatTime(A_Now, "yyyyMMdd_HHmmss") "\"
        try DirCreate(bak)
        local count := 0
        ; KADEMEYE BAKMAZ — allStores. Kademe hız içindi; "her şeyi sil" açık bir
        ; kullanıcı eylemi, kapsamı daraltmanın anlamı yok.
        for s in this.allStores {
            try {
                s.archive(bak)
                count += s.purge()
            } catch as e {
                try App.ErrHandler.handleError("incognito cleanNow (" s.name "): " e.Message)
            }
        }
        this._clearVlcRecents()
        this._refreshShell()

        if (wasActive) {
            ; Canlı yedek YENİLENMEZSE az önce kalıcı silinen kayıtları hâlâ
            ; içerir ve disable() onları geri yazıp cleanNow'u boşa çıkarır.
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
                    ; CaseSense yalnızca BOŞ Map'te değiştirilebilir -> kopyalıyoruz.
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
    ; Taskbar'da buton olarak durur (yüzmez); pencereyi kapatmak incognito'yu kapatır.
    _showBadge() {
        if (this._badge)
            return
        local g := Gui("-MaximizeBox", "🔒 Incognito açık")
        g.SetFont("s9", "Segoe UI")
        g.MarginX := 12, g.MarginY := 10
        this._badgeInfo := g.AddText("xm ym w300", "")
        this._badgeList := g.AddListBox("xm y+6 w300 r12", [])
        this._cbDeep := g.AddCheckbox("xm y+12", "Derin izler (klasör + program geçmişi — yavaşlatır)")
        this._cbDeep.Value := this.deepMode ? 1 : 0
        this._cbDeep.OnEvent("Click", (cb, *) => this.setDeepMode(cb.Value))
        this._cbDeep.ToolTip := "Kapalıyken kapsam: açılan/kaydedilen DOSYA adları"
            . " (RecentDocs, Aç/Kaydet geçmişi, Recent kısayolları, jump list).`n"
            . "Açıkken ayrıca: gezilen klasörler (ShellBags), çalıştırılan programlar"
            . " (UserAssist/MUICache/FeatureUsage), adres çubuğu ve Win+R geçmişi.`n`n"
            . "Incognito AÇIKKEN işaretlersen yedek O AN alınır — o ana kadar"
            . " oluşmuş derin izler geri alınamaz."
        this._cbVlc := g.AddCheckbox("xm y+8", "VLC")
        this._cbVlc.Value := this.coverVlc ? 1 : 0
        this._cbVlc.OnEvent("Click", (cb, *) => (this.coverVlc := !!cb.Value))
        this._cbRestore := g.AddCheckbox("x+24 yp", "Kapanışta geri yükle")
        this._cbRestore.Value := this.restoreOnClose ? 1 : 0
        this._cbRestore.OnEvent("Click", (cb, *) => (this.restoreOnClose := !!cb.Value))
        g.AddButton("xm y+10 w95 h30", "🔍 Denetle").OnEvent("Click", (*) => this._showAudit())
        g.AddButton("x+8 yp w95 h30", "🔄 Yenile").OnEvent("Click", (*) => this._refreshBadgeList())
        this._btnClose := g.AddButton("x+8 yp w95 h30", "🔒 Kapat")
        this._btnClose.OnEvent("Click", (*) => this._closeFromBadge())
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
            this._badgeInfo.Value := "Donduruldu: " this.handles.Count " jump list dosyası   ·   "
                . this.stores.Length "/" this.allStores.Length " iz deposu"
            local names := this.getLockedNames(300)
            this._badgeList.Delete()
            if (names.Length)
                this._badgeList.Add(names)
        }
    }

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
        ; Kapsamı her zaman yaz: "iz yok" ile "zaten kapsam dışı" karışmasın.
        msg .= "`n──────────`nKapsam: " this.stores.Length " / " this.allStores.Length " depo"
            . (this.deepMode ? " (derin izler AÇIK)" : " (derin izler kapalı — klasör/program geçmişi kapsam dışı)")
        MsgBox(msg, "🔍 Incognito denetim", "Iconi")
    }

    ; Pencere event'inin İÇİNDE Destroy riskli -> timer'a ertele. Düğmeyi anında
    ; devre dışı bırakmak "takıldı mı?" hissini önlüyor.
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
            this._freeWinIcons()        ; pencere gitti, ikon handle'ları da gitsin
            this._badge := 0
            this._cbVlc := 0
            this._cbRestore := 0
            this._cbDeep := 0
            this._btnClose := 0
        }
    }

    ; Pencereye (dolayısıyla taskbar butonuna) özel ikon ver — best-effort.
    ; WM_SETICON SAHİPLİĞİ DEVRALMAZ: LR_SHARED'siz LoadImage ile gelen handle
    ; bizim, pencere yok edilirken DestroyIcon etmek zorundayız. Yoksa her
    ; açılış 2 ikon handle'ı sızdırıyor. Handle'lar pencere yaşadığı sürece
    ; canlı kalmalı -> hemen değil, _destroyBadge()'te bırakılıyorlar.
    _setWinIcon(hwnd, icoPath) {
        static WM_SETICON := 0x0080, ICON_SMALL := 0, ICON_BIG := 1
        static IMAGE_ICON := 1, LR_LOADFROMFILE := 0x10
        if (!FileExist(icoPath))
            return
        local hSmall := DllCall("LoadImage", "ptr", 0, "str", icoPath, "uint", IMAGE_ICON, "int", 16, "int", 16, "uint", LR_LOADFROMFILE, "ptr")
        local hBig := DllCall("LoadImage", "ptr", 0, "str", icoPath, "uint", IMAGE_ICON, "int", 32, "int", 32, "uint", LR_LOADFROMFILE, "ptr")
        if (hSmall) {
            SendMessage(WM_SETICON, ICON_SMALL, hSmall, , "ahk_id " hwnd)
            this._hIconSmall := hSmall
        }
        if (hBig) {
            SendMessage(WM_SETICON, ICON_BIG, hBig, , "ahk_id " hwnd)
            this._hIconBig := hBig
        }
    }

    _freeWinIcons() {
        for prop in ["_hIconSmall", "_hIconBig"] {
            if (this.%prop%) {
                try DllCall("user32\DestroyIcon", "ptr", this.%prop%)
                this.%prop% := 0
            }
        }
    }

}
