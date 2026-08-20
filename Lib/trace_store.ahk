; ════════════════════════════════════════════════════════════════════════
;  trace_store.ahk — Windows iz depoları (incognito.ahk için altyapı)
; ────────────────────────────────────────────────────────────────────────
;  Bir dosyanın izi Windows'ta tek yerde durmuyor: aynı indirme hem
;  Recent\*.lnk'te, hem RecentDocs registry'sinde, hem ComDlg32 MRU'larında,
;  hem de jump list'te kayıt bırakıyor. Her kaynağı tek tip arayüzle temsil
;  edip toplu snapshot / restore / purge yapabilmek için bu modül var.
;
;  ÇEKİRDEK FİKİR — snapshot + geri yükle:
;    incognito AÇILIRKEN  : tüm depoların tam yedeği alınır
;    incognito KAPANIRKEN : yedek aynen geri yazılır
;  Sonuç: oturumda ne oluştuysa yok olur, ÖNCEKİ geçmiş hiç bozulmaz.
;  "Hepsini sil" yaklaşımından farkı bu — kullanıcının eski geçmişi durur.
;
; ────────────────────────────────────────────────────────────────────────
;  GELİŞTİRME NOTLARI:
;   • Registry hive'ı FileOpen ile kilitlenemez (incognito.ahk'daki jump list
;     kilidi burada işe yaramaz), o yüzden snapshot/restore mekanizması.
;   • reg.exe import MERGE yapar, replace etmez. Geri yüklemeden önce anahtarı
;     silmek ŞART; yoksa oturumda eklenen kayıtlar yerinde kalır.
;   • Jump list dosyaları incognito aktifken kilitli olduğundan (FileShare.None)
;     snapshot kilitlemeden ÖNCE, restore kilit açıldıktan SONRA yapılmalı.
; ════════════════════════════════════════════════════════════════════════

; ── Soyut taban ─────────────────────────────────────────────────────────
class TraceStore {
    __New(name) {
        this.name := name
    }
    count() => 0                ; kaç kayıt var (audit / diff için)
    snapshot(root) => false     ; root klasörüne yedekle
    restore(root) => false      ; root klasöründeki yedeği geri yaz
    purge() => 0                ; tamamen sil, silinen sayısını döndür

    ; ── Paralel toplu snapshot arayüzü ──────────────────────────────────
    ; bkz. RegStore.beginSnapshot / incognito.ahk _snapshotAll. Varsayılan:
    ; alt sınıfın senkron snapshot()'ı zaten yeterince hızlı (ör. FileGlobStore
    ; — yalnız yerel FileCopy, dış süreç başlatmıyor), beklenecek async iş yok.
    beginSnapshot(root) {
        this.snapshot(root)
        return 0
    }
    endSnapshot(root, pending) {
        return true
    }

    ; ── Paralel toplu restore arayüzü (bkz. RegStore.beginRestore) ──────
    ; Varsayılan: alt sınıfın senkron restore()'ı zaten yeterince hızlı
    ; (ör. FileGlobStore — yalnız yerel FileCopy/FileDelete, dış süreç yok).
    beginRestore(root) {
        return { pid: 0, done: this.restore(root) }
    }
    endRestore(root, pending) {
        return pending.done
    }
}

; ── Registry anahtarı ───────────────────────────────────────────────────
class RegStore extends TraceStore {
    __New(name, key) {
        super.__New(name)
        this.key := key
    }

    _file(root) => root this.name ".reg"
    ; Anahtar enable() anında hiç yoktu (reg export dosya üretmedi) işareti.
    ; BUG NOTU: Bu marker olmadan restore() "yedek dosyası yok -> dokunma"
    ; diyordu; ama "yedek yok" iki farklı durumu ayırt edemiyordu: (a) hiç
    ; snapshot alınmadı (dokunma, doğru) vs (b) anahtar o an yoktu (oturumda
    ; SIFIRDAN oluşmuşsa silinmesi lazım). (b) sessizce (a) gibi ele alınınca
    ; örn. RunMRU/TypedPaths gibi hiç kullanılmamış bir anahtar oturumda ilk
    ; kez oluşuyor ve restore hiç dokunmadığı için kalıcı olarak yerinde
    ; kalıyordu — "eski geçmiş bozulmasın" sözü tutuluyor ama "oturum izi
    ; silinsin" sözü tutulmuyordu.
    _absentFile(root) => root this.name ".absent"

    ; Değer + alt anahtar sayısı (özyinelemeli). Anahtar yoksa Loop Reg
    ; sessizce hiç dönmez -> 0 döner, ayrı bir varlık kontrolü gerekmiyor.
    count() {
        local n := 0
        try {
            Loop Reg this.key, "KVR"
                n++
        }
        return n
    }

    ; ── Paralel toplu snapshot (bkz. TraceStore) ────────────────────────
    ; reg.exe başlatma maliyeti (~40-50ms/çağrı) tek tek RunWait ile ardışık
    ; toplanınca ölçülebilir hale geliyordu (7 depo için ~340ms, ölçüldü).
    ; beginSnapshot HEPSİ için sırayla ama BEKLEMEDEN başlatılır (Run,
    ; non-blocking); incognito._snapshotAll sonra hepsini TEK TEK bekler —
    ; o noktada çoğu zaten OS'te paralel bitmiş olur. Toplam süre artık
    ; "N × tekil süre" değil "en yavaş tekilin süresi"ne yakınsar.
    beginSnapshot(root) {
        local f := this._file(root)
        try FileDelete(f)
        try FileDelete(this._absentFile(root))
        local pid := 0
        try Run('reg.exe export "' this.key '" "' f '" /y', , "Hide", &pid)
        return pid
    }

    endSnapshot(root, pid) {
        if (pid)
            try ProcessWaitClose(pid, 5)   ; 5sn üst sınır — tek bir takılan reg.exe enable()'ı sonsuza kilitlemesin
        local f := this._file(root)
        if (FileExist(f))
            return true
        try FileAppend("1", this._absentFile(root))
        return false
    }

    snapshot(root) {
        return this.endSnapshot(root, this.beginSnapshot(root))
    }

    ; ── Paralel toplu restore ────────────────────────────────────────────
    ; delete+import BİR depo İÇİNDE sıralı kalmak ZORUNDA (import merge
    ; yapıyor, önce silmek şart) ama FARKLI depolar birbirinden bağımsız.
    ; Silme adımı zaten hızlı (senkron kalır); asıl ağır iş olan İÇE
    ; AKTARMAYI (özellikle MUICache/Shellbags gibi çok kayıtlı depolarda)
    ; async başlatıp incognito._restoreAll'da hep birlikte bekliyoruz —
    ; disable()'ı depo sayısı arttıkça yavaşlatmayan tek yol bu.
    ; Dönüş: { pid, done } — done, _restoreAll'daki "kaç depo geri yüklendi"
    ; sayacı için restore()'un eski boolean sonucunu taşır.
    beginRestore(root) {
        if (FileExist(this._absentFile(root))) {
            ; enable() anında anahtar yoktu -> oturumda oluştuysa komple sil.
            ; Tek işlem (import yok), async'e gerek yok.
            this._reg('delete "' this.key '" /f')
            return { pid: 0, done: true }
        }
        local f := this._file(root)
        if (!FileExist(f))
            return { pid: 0, done: false }   ; hiç snapshot alınamamış (beklenmedik) — dokunma
        ; import merge yaptığı için önce anahtarı komple sil.
        ; Anahtar zaten yoksa reg.exe hata döner, umursamıyoruz.
        this._reg('delete "' this.key '" /f')
        local pid := 0
        try Run('reg.exe import "' f '"', , "Hide", &pid)
        return { pid: pid, done: true }
    }

    endRestore(root, pending) {
        if (pending.pid)
            try ProcessWaitClose(pending.pid, 8)   ; 8sn üst sınır — takılan tek bir import disable()'ı kilitlemesin
        return pending.done
    }

    restore(root) {
        return this.endRestore(root, this.beginRestore(root))
    }

    purge() {
        local n := this.count()
        if (!n)
            return 0
        return (this._reg('delete "' this.key '" /f') = 0) ? n : 0
    }

    ; reg.exe'yi gizli çalıştır; exit code döndür (-1 = başlatılamadı)
    _reg(args) {
        try {
            return RunWait("reg.exe " args, , "Hide")
        } catch as e {
            try App.ErrHandler.handleError("trace_store reg.exe: " e.Message)
            return -1
        }
    }
}

; ── Klasör + dosya deseni (Recent\*.lnk, jump list klasörleri) ──────────
class FileGlobStore extends TraceStore {
    __New(name, dir, pattern) {
        super.__New(name)
        this.dir := dir
        this.pattern := pattern
    }

    _bak(root) => root this.name "\"

    count() {
        local n := 0
        if (DirExist(this.dir)) {
            Loop Files, this.dir this.pattern
                n++
        }
        return n
    }

    ; dst HER durumda oluşturulur (this.dir o an yok olsa bile) — boş dst,
    ; restore()'a "enable() anında burada hiçbir şey yoktu" bilgisini taşır.
    ; Bunu atlarsak (eski davranış) klasör oturum SIRASINDA ilk kez
    ; yaratılırsa restore() "yedek yok" deyip dokunmuyor, oturum izi kalıcı
    ; kalıyordu — RegStore'daki ".absent" bugıyla aynı sınıf hata.
    snapshot(root) {
        local dst := this._bak(root)
        try DirCreate(dst)
        if (DirExist(this.dir)) {
            Loop Files, this.dir this.pattern
                try FileCopy(A_LoopFileFullPath, dst A_LoopFileName, true)
        }
        return true
    }

    ; İki aşama: (1) oturumda DOĞAN dosyaları sil, (2) oturumda DEĞİŞENLERİ
    ; yedekten geri yaz. İkisi birlikte klasörü enable() anındaki haline döndürür.
    restore(root) {
        local src := this._bak(root)
        if (!DirExist(src))
            return false           ; hiç snapshot alınamamış (beklenmedik) — dokunma
        if (!DirExist(this.dir))
            return true            ; klasör hâlâ yok -> yapacak bir şey kalmadı
        Loop Files, this.dir this.pattern {
            if (!FileExist(src A_LoopFileName))
                try FileDelete(A_LoopFileFullPath)
        }
        Loop Files, src this.pattern
            try FileCopy(A_LoopFileFullPath, this.dir A_LoopFileName, true)
        return true
    }

    purge() {
        local n := 0
        if (!DirExist(this.dir))
            return 0
        Loop Files, this.dir this.pattern {
            try {
                FileDelete(A_LoopFileFullPath)
                n++
            }
        }
        return n
    }
}

; ── Politika koruması (önleme katmanı) ──────────────────────────────────
;  Explorer son-doküman listesini bellekte tutup geri yazabildiği için,
;  yalnızca "sonradan temizlemek" yetmiyor — oturum boyunca izlemenin
;  kaynağında kapatılması gerekiyor. Hepsi HKCU: yönetici hakkı gerekmez.
;
;  NOT: ClearRecentDocsOnExit bilinçli olarak DIŞARIDA. Oturum kapanışında
;  eski geçmişi de siler; "önceki geçmiş korunsun" kararıyla çelişir.
class PolicyGuard {
    __New(items) {
        this.items := items     ; [{ key, value, data }]
        this.saved := []
        this.applied := false
    }

    apply() {
        if (this.applied)
            return
        this.saved := []
        for it in this.items {
            local had := true, old := ""
            try {
                old := RegRead(it.key, it.value)
            } catch {
                had := false
            }
            this.saved.Push({ key: it.key, value: it.value, had: had, old: old })
            try RegWrite(it.data, "REG_DWORD", it.key, it.value)
        }
        this.applied := true
    }

    revert() {
        if (!this.applied)
            return
        for s in this.saved
            PolicyGuard._revertOne(s.key, s.value, s.had, s.old)
        this.saved := []
        this.applied := false
    }

    ; ── Çökme kurtarma ───────────────────────────────────────────────────
    ; BUG NOTU: apply() sadece bellekte (this.saved/this.applied) tutulduğu
    ; için script çökerse (OnExit hiç tetiklenmeden) bir sonraki başlatmada
    ; kurulan YENİ instance'ın this.applied'ı hep false'tur -> revert() no-op
    ; kalır ve Start_TrackDocs/Start_TrackProgs/NoRecentDocsHistory KALICI
    ; olarak kapalı/açık takılı kalırdı (Explorer'ın "Son kullanılanlar"
    ; özelliği bir daha kendiliğinden dönmezdi). saveTo()/revertFrom() eski
    ; değerleri diske yazıp instance'tan bağımsız geri yükleyebiliyor.
    saveTo(path) {
        try FileDelete(path)
        for s in this.saved
            try FileAppend(s.key "`t" s.value "`t" (s.had ? "1" : "0") "`t" s.old "`n", path)
    }

    static revertFrom(path) {
        if (!FileExist(path))
            return
        try {
            local f := FileOpen(path, "r", "UTF-8")
            local data := f.Read()
            f.Close()
            for line in StrSplit(data, "`n") {
                line := Trim(line, "`r`n")
                if (!line)
                    continue
                local p := StrSplit(line, "`t")
                if (p.Length < 3)
                    continue
                PolicyGuard._revertOne(p[1], p[2], p[3] = "1", p.Length >= 4 ? p[4] : "")
            }
        } catch as e {
            try App.ErrHandler.handleError("PolicyGuard.revertFrom: " e.Message)
        }
        try FileDelete(path)
    }

    static _revertOne(key, value, had, old) {
        try {
            if (had)
                RegWrite(old, "REG_DWORD", key, value)
            else
                RegDelete(key, value)
        }
    }
}
