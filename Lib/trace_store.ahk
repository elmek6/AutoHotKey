; ════════════════════════════════════════════════════════════════════════
;  trace_store.ahk — Windows iz depoları (incognito.ahk için altyapı)
; ────────────────────────────────────────────────────────────────────────
;  Bir dosyanın izi tek yerde durmuyor: aynı indirme Recent\*.lnk'te,
;  RecentDocs'ta, ComDlg32 MRU'larında ve jump list'te kayıt bırakıyor.
;  Her kaynağı tek tip arayüzle temsil eden modül.
;
;  ÇEKİRDEK FİKİR: açılırken yedek al, kapanırken aynen geri yaz. Oturumda
;  ne oluştuysa yok olur, ÖNCEKİ geçmiş hiç bozulmaz — "hepsini sil"den
;  farkı bu.
;
;  KURALLAR:
;   • Registry hive'ı FileOpen ile kilitlenemez -> snapshot/restore şart.
;   • reg.exe import MERGE yapar. Geri yüklemeden ÖNCE anahtarı silmek
;     ZORUNLU; yoksa oturumda eklenenler yerinde kalır.
;   • Jump list dosyaları aktifken kilitli: snapshot kilitlemeden ÖNCE,
;     restore kilit açıldıktan SONRA.
;   • Maliyet depolara eşit dağılmıyor — 18 deponun 1'i işin ~%90'ıydı.
;     Hız işi "genel olarak hızlandırmak" değil, o depoya dokunmamak:
;     beginWatch (dokunulmamışı atla) + RegDeltaStore (tam yedek yerine
;     delta) + en ağır depo en önce başlasın sıralaması.
; ════════════════════════════════════════════════════════════════════════

; ── Soyut taban ─────────────────────────────────────────────────────────
class TraceStore {
    ; tier: "core" = dosya adı taşıyan izler (varsayılan açık),
    ;       "deep" = klasör/program izleri (varsayılan kapalı).
    ; Seçim incognito.ahk _selectStores() içinde.
    __New(name, tier := "core") {
        this.name := name
        this.tier := tier
    }
    count() => 0                ; kaç kayıt var (audit / diff için)
    snapshot(root) => false     ; root klasörüne yedekle
    restore(root) => false      ; root klasöründeki yedeği geri yaz
    purge() => 0                ; tamamen sil, silinen sayısını döndür

    ; cleanNow()'un aldığı KALICI yedek. Varsayılan olarak snapshot() ile
    ; aynı; farkı olan tek depo FileGlobStore (oturum yedeği hız için tek
    ; dosyalık pakete yazılıyor, kalıcı yedek ise elle karıştırılabilsin
    ; diye düz klasör kopyası kalıyor).
    archive(root) => this.snapshot(root)

    ; ── Paralel toplu snapshot/restore arayüzü ──────────────────────────
    ; Varsayılan: senkron snapshot()/restore() zaten hızlı (dış süreç yok),
    ; beklenecek async iş yok. Süreç başlatan depolar (RegStore) override eder.
    beginSnapshot(root) {
        this.snapshot(root)
        return 0
    }
    endSnapshot(root, pending) {
        return true
    }

    beginRestore(root) {
        return { pid: 0, done: this.restore(root) }
    }
    endRestore(root, pending) {
        return pending.done
    }

    ; Denetim satırı (boş = gösterilecek bir şey yok). Varsayılan: yedekten
    ; türetilen taban ile şimdiki sayıyı karşılaştır. Taban türetilemiyorsa
    ; (baselineCount = -1) depo denetimde sessizce atlanır.
    auditLine(root) {
        local base := this.baselineCount(root)
        if (base < 0)
            return ""
        local now := this.count()
        local diff := now - base
        if (!diff)
            return ""
        return Format("{1}: {2}{3}   ({4} → {5})", this.name, (diff > 0 ? "+" : ""), diff, base, now)
    }

    ; Taban sayımı YEDEKTEN türetilir. "enable() ANINDAKİ sayı" sonradan
    ; registry'den okunamaz — ama yedek tanım gereği o anın kopyası, sayı
    ; zaten içinde. Böylece enable()'a maliyet yazılmıyor.
    ; Dönüş: -1 = türetilemedi (denetimde o depo atlanır).
    baselineCount(root) => -1

    ; Toplu (tek cmd.exe) başlatma yolu yalnız reg.exe kullanan depolar için;
    ; bkz. incognito._snapshotBegin.
    usesRegExport() => false

    ; ── Değişiklik gözcüsü (bkz. RegStore.beginWatch) ───────────────────
    ; Varsayılan gözcüsüz -> hasChanged() HEP true, hiçbir iş atlanmaz.
    ; Atlamak POZİTİF kanıt ister.
    beginWatch() {
    }
    hasChanged() => true
    endWatch() {
    }
}

; ── Registry anahtarı ───────────────────────────────────────────────────
class RegStore extends TraceStore {
    __New(name, key, tier := "core") {
        super.__New(name, tier)
        this.key := key
        this._hKey := 0             ; KEY_NOTIFY handle'ı (gözcü açıkken dolu)
        this._hEvent := 0           ; alt ağaçta değişiklik olunca sinyallenen event
    }

    _file(root) => root this.name ".reg"
    ; "Anahtar enable() anında hiç yoktu" işareti. Olmadan restore(),
    ; "hiç yedek alınmadı" (dokunma) ile "anahtar yoktu" (oturumda sıfırdan
    ; oluştuysa sil) durumlarını ayıramıyor; RunMRU/TypedPaths gibi ilk kez
    ; oluşan anahtarlar kalıcı olarak yerinde kalıyordu.
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

    ; Beklemeden başlat (Run non-blocking); bekleme endSnapshot'ta.
    beginSnapshot(root) {
        local pid := 0
        try Run(this.prepareExport(root), , "Hide", &pid)
        return pid
    }

    ; Eski yedeği temizler ve export komutunu METİN olarak döndürür — süreci
    ; BAŞLATMAZ. incognito._launchRegBatch bunları tek cmd.exe'de zincirliyor
    ; (her ayrı `Run` bizim thread'imizde ~17 ms).
    prepareExport(root) {
        try FileDelete(this._file(root))
        try FileDelete(this._absentFile(root))
        return 'reg.exe export "' this.key '" "' this._file(root) '" /y'
    }

    usesRegExport() => true

    ; Taban: .reg dosyasını say. count() ile BİREBİR aynı şeyi saymalı,
    ; yoksa denetim her depoda sabit bir sapma gösterir. count() =
    ; `Loop Reg key,"KVR"` = kökün ALTINDAKİLER; export kök için de bir
    ; `[...]` satırı yazdığından anahtar sayısından 1 düşüyoruz.
    ; Satır başları: `\n[` anahtar, `\n"` adlı değer, `\n@=` varsayılan.
    ; (Hex devam satırları iki boşlukla başlıyor, REG_SZ içinde ham satır
    ; sonu olmuyor — çok satırlı veri hex(2)/hex(7) yazılıyor.)
    baselineCount(root) {
        if (FileExist(this._absentFile(root)))
            return 0            ; enable() anında anahtar hiç yoktu
        local f := this._file(root)
        if (!FileExist(f))
            return -1           ; yedek alınamamış — türetemeyiz
        local txt := ""
        try {
            txt := FileRead(f, "UTF-16")
        } catch {
            return -1
        }
        local nKey := 0, nVal := 0, nDef := 0
        StrReplace(txt, "`n[", , , &nKey)
        StrReplace(txt, '`n"', , , &nVal)
        StrReplace(txt, "`n@=", , , &nDef)
        return (nKey > 0 ? nKey - 1 : 0) + nVal + nDef
    }

    endSnapshot(root, pid) {
        if (pid)
            try ProcessWaitClose(pid, 5)   ; 5sn üst sınır — tek bir takılan reg.exe enable()'ı sonsuza kilitlemesin
        local f := this._file(root)
        if (FileExist(f))
            return true
        ; Dosya yok. İKİ AYRI DURUM, karıştırmak VERİ KAYBI demek:
        ;  (a) anahtar gerçekten yoktu       -> ".absent" koy
        ;  (b) reg.exe patladı / zaman aşımı -> marker KOYMA; koyarsak
        ;      restore, duran DOLU bir anahtarı "oturumda doğmuş" sanıp siler.
        if (!this._keyExists())
            try FileAppend("1", this._absentFile(root))
        return false
    }

    snapshot(root) {
        return this.endSnapshot(root, this.beginSnapshot(root))
    }

    ; delete+import BİR depo İÇİNDE sıralı kalmak ZORUNDA (import merge
    ; yapıyor), ama farklı depolar bağımsız: silme senkron, asıl ağır iş
    ; olan import async başlatılıp _restoreAll'da hep birlikte bekleniyor.
    ; Dönüş: { pid, done }.
    beginRestore(root) {
        if (FileExist(this._absentFile(root))) {
            ; enable() anında anahtar yoktu -> oturumda oluştuysa komple sil.
            ; Tek işlem (import yok), async'e gerek yok.
            this._deleteKey()
            return { pid: 0, done: true }
        }
        local f := this._file(root)
        if (!FileExist(f))
            return { pid: 0, done: false }   ; hiç snapshot alınamamış (beklenmedik) — dokunma
        ; import merge yaptığı için önce anahtarı komple sil.
        ; Anahtar zaten yoksa RegDeleteKey fırlatır, umursamıyoruz.
        this._deleteKey()
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
        return this._deleteKey() ? n : 0
    }

    ; Anahtarı alt anahtarlarıyla sil. RegDeleteKey özyinelemeli çalışıyor
    ; (ampirik: 3 seviyeli test ağacı kökü dahil tek çağrıda silindi) ve
    ; reg.exe'nin aksine süreç başlatmıyor — 12 depoda ~1.2 sn -> ~0.4 sn.
    ; Dönüş: silindi mi (anahtar zaten yoksa false).
    _deleteKey() {
        try {
            RegDeleteKey(this.key)
            return true
        } catch {
            return false
        }
    }

    ; ── Değişiklik gözcüsü ───────────────────────────────────────────────
    ; RegNotifyChangeKeyValue = çekirdeğin alt-ağaç bildirimi. enable()'da
    ; anahtar başına bir event kurulur (maliyeti ~0), disable()'da 0
    ; timeout'lu WaitForSingleObject ile "bu ağaca hiç dokunuldu mu?" diye
    ; sorulur. Dokunulmadıysa sil+geri yaz TAMAMEN atlanır — aynı içeriği
    ; silip aynen geri yazmakla birebir aynı sonuç.
    ;
    ; TEK YÖNLÜ: yalnız iş ATLAR, asla iş EKSİLTMEZ. Gözcü kurulamadıysa,
    ; event sinyallendiyse ya da script yeniden başladıysa hasChanged()
    ; true döner ve tam sil+geri yükle yolu işler.
    ;
    ; SIRALAMA ŞART: gözcü export'tan ÖNCE kurulur (bkz. _snapshotBegin) —
    ; export sürerken düşen bir iz yedeğe karışabilir, o zaman depo
    ; "değişti" işaretlenip tam geri yükleme yapılsın.
    beginWatch() {
        static KEY_NOTIFY := 0x0010
        ; NAME | ATTRIBUTES | LAST_SET | SECURITY
        static FILTER := 0x1 | 0x2 | 0x4 | 0x8
        this.endWatch()
        local parts := this._splitKey()
        if (!parts)
            return
        local hKey := 0
        if (DllCall("advapi32\RegOpenKeyExW", "ptr", parts.root, "str", parts.sub
                  , "uint", 0, "uint", KEY_NOTIFY, "ptr*", &hKey, "int") != 0)
            return                  ; anahtar yok -> gözcüsüz; hasChanged() true kalır
        local hEvent := DllCall("kernel32\CreateEventW", "ptr", 0, "int", 1, "int", 0, "ptr", 0, "ptr")
        if (!hEvent) {
            DllCall("advapi32\RegCloseKey", "ptr", hKey)
            return
        }
        ; bWatchSubtree=1, fAsynchronous=1 -> ayrı iş parçacığı gerekmez,
        ; çekirdek event'i biz meşgulken bile sinyaller.
        if (DllCall("advapi32\RegNotifyChangeKeyValue", "ptr", hKey, "int", 1
                  , "uint", FILTER, "ptr", hEvent, "int", 1, "int") != 0) {
            DllCall("kernel32\CloseHandle", "ptr", hEvent)
            DllCall("advapi32\RegCloseKey", "ptr", hKey)
            return
        }
        this._hKey := hKey
        this._hEvent := hEvent
    }

    ; Event bir kez sinyallenir ve öyle kalır — bize "en az bir değişiklik
    ; oldu mu?" yeterli olduğu için yeniden kurmaya gerek yok.
    hasChanged() {
        if (!this._hEvent)
            return true             ; kanıt yok -> değişmiş say (eski yol)
        return DllCall("kernel32\WaitForSingleObject", "ptr", this._hEvent, "uint", 0, "uint") = 0
    }

    endWatch() {
        if (this._hEvent) {
            DllCall("kernel32\CloseHandle", "ptr", this._hEvent)
            this._hEvent := 0
        }
        if (this._hKey) {
            DllCall("advapi32\RegCloseKey", "ptr", this._hKey)
            this._hKey := 0
        }
    }

    ; Anahtar VAR MI? `Loop Reg` anahtar yoksa da boşsa da sessizce hiç
    ; dönmüyor; ikisini ayırmak ".absent" sözleşmesi için şart (bkz.
    ; endSnapshot). RegDeltaStore da bunu kullanır.
    _keyExists() {
        static KEY_READ := 0x20019
        local parts := this._splitKey()
        if (!parts)
            return false
        local hKey := 0
        if (DllCall("advapi32\RegOpenKeyExW", "ptr", parts.root, "str", parts.sub
                  , "uint", 0, "uint", KEY_READ, "ptr*", &hKey, "int") != 0)
            return false
        DllCall("advapi32\RegCloseKey", "ptr", hKey)
        return true
    }

    ; "HKCU\Software\..." -> { root: HKEY handle, sub: "Software\..." }
    ; RegOpenKeyEx yol dizesini değil kök HANDLE'ı + alt yolu ister.
    _splitKey() {
        static roots := Map(
            "HKEY_CURRENT_USER", 0x80000001, "HKCU", 0x80000001,
            "HKEY_LOCAL_MACHINE", 0x80000002, "HKLM", 0x80000002,
            "HKEY_CLASSES_ROOT", 0x80000000, "HKCR", 0x80000000,
            "HKEY_USERS", 0x80000003, "HKU", 0x80000003,
            "HKEY_CURRENT_CONFIG", 0x80000005, "HKCC", 0x80000005)
        local p := InStr(this.key, "\")
        if (!p)
            return 0
        local rootName := StrUpper(SubStr(this.key, 1, p - 1))
        if (!roots.Has(rootName))
            return 0
        return { root: roots[rootName], sub: SubStr(this.key, p + 1) }
    }
}

; ── Registry anahtarı — DELTA ("yalnız oturumda eklenenleri sil") ───────
; Tam snapshot/restore bir depoda saçma kaçıyordu: ShellBags_UsrClass
; 8.2 MB / 47k kayıt, export 812 + silme 650 + import 1808 ms. Oysa bir
; oturumda eklenen şey birkaç alt anahtar. Bu sınıf tam yedek yerine yalnız
; en yüksek sayısal alt anahtar numarasını (high-water mark) not eder ve
; geri yüklemede sadece onun ÜSTÜNDEKİLERİ siler.
;
; NEDEN DOĞRU: Bags alt anahtarları tam sayı ve tahsis SIRALI (ölçüm:
; 1..2427, boşluk yok) — yeni klasör her zaman max+1 alıyor. Sayısal
; olmayan kardeşler ("AllFolders") dikkate alınmaz.
;
; SADECE HIZ DEĞİL: reg.exe import anahtarları yeniden yazdığı için 8.882
; anahtarın LastWriteTime'ını içe aktarma anına çekiyordu — yıllara yayılmış
; bir geçmiş tek 5 saniyelik pencereye sıkışıyordu. Delta yolunda eski
; anahtarlara dokunulmuyor.
;
; DİKKAT — TEK BAŞINA DOĞRU DEĞİL: silme boş NodeSlot bırakıyor ve Windows
; onu yeniden kullanabilir (bitmap BagMRU kökünde). Reuse olursa yeni bag
; hwm'in ALTINDA doğar ve delta onu kaçırır. Engelleyen şey kardeş BagMRU
; deposunun TAM geri yüklenmesi; incognito.ahk `this.coupled` bunu zorluyor.
; O listeyi bozarsan bu depo sessizce sızdırır.
class RegDeltaStore extends RegStore {
    ; Yedek "dosyası" tek satırlık bir sayı; .reg değil.
    _file(root) => root this.name ".hwm"

    usesRegExport() => false        ; süreç başlatmıyor -> toplu yola girmez

    ; Yedek bir sayım değil high-water mark; kayıt diffi üretilemez. Onun
    ; yerine auditLine "oturumda kaç yeni kayıt doğdu"yu doğrudan veriyor.
    baselineCount(root) => -1

    auditLine(root) {
        local f := this._file(root)
        if (FileExist(this._absentFile(root)))
            return this.name ": anahtar oturum basinda yoktu — kapanista silinecek"
        if (!FileExist(f))
            return ""
        local hwm := -1
        try hwm := Integer(Trim(FileRead(f), " `t`r`n"))
        if (hwm < 0)
            return ""
        local mx := this._maxChild()
        if (mx <= hwm)
            return ""
        return Format("{1}: +{2} yeni kayit   ({3} → {4})", this.name, mx - hwm, hwm, mx)
    }

    ; Dış süreç yok -> beklenecek pid yok, iş burada bitiyor (ölçüm: <5 ms).
    beginSnapshot(root) {
        try FileDelete(this._file(root))
        try FileDelete(this._absentFile(root))
        if (!this._keyExists()) {
            ; Anahtar enable() anında hiç yoktu -> oturumda oluştuysa komple
            ; silinmeli. RegStore ile aynı ".absent" sözleşmesi.
            try FileAppend("1", this._absentFile(root))
            return 0
        }
        try FileAppend(this._maxChild(), this._file(root))
        return 0
    }

    endSnapshot(root, pending) {
        return FileExist(this._file(root)) ? true : false
    }

    beginRestore(root) {
        if (FileExist(this._absentFile(root))) {
            this._deleteKey()
            return { pid: 0, done: true }
        }
        local f := this._file(root)
        if (!FileExist(f))
            return { pid: 0, done: false }   ; snapshot alınamamış — DOKUNMA
        ; Okunamayan/bozuk marker'da da dokunmuyoruz: yanlış bir high-water
        ; mark, kullanıcının eski kayıtlarını silmek demek olurdu.
        local hwm := -1
        try hwm := Integer(Trim(FileRead(f), " `t`r`n"))
        if (hwm < 0)
            return { pid: 0, done: false }
        return { pid: 0, done: this._deleteAbove(hwm) }
    }

    ; En yüksek SAYISAL alt anahtar. Anahtar boşsa 0 döner — o durumda
    ; oturumda oluşan her şey (1, 2, ...) silinir, doğru davranış.
    _maxChild() {
        local mx := 0
        try {
            Loop Reg this.key, "K" {
                if (!RegExMatch(A_LoopRegName, "^\d+$"))
                    continue
                local n := Integer(A_LoopRegName)
                if (n > mx)
                    mx := n
            }
        }
        return mx
    }

    ; Numaralandırırken silmek güvensiz (enumerator kayar) -> önce topla, sonra sil.
    _deleteAbove(hwm) {
        local victims := []
        try {
            Loop Reg this.key, "K" {
                if (RegExMatch(A_LoopRegName, "^\d+$") && Integer(A_LoopRegName) > hwm)
                    victims.Push(A_LoopRegName)
            }
        }
        for v in victims {
            try RegDeleteKey(this.key "\" v)
        }
        return true
    }

}

; ── Klasör + dosya deseni (Recent\*.lnk, jump list klasörleri) ──────────
class FileGlobStore extends TraceStore {
    __New(name, dir, pattern, tier := "core") {
        super.__New(name, tier)
        this.dir := dir
        this.pattern := pattern
    }

    ; Yedek KLASÖR DEĞİL, TEK DOSYA (".pack").
    ; Recent\*.lnk'te 156 dosya var ama toplamı 152 KB; maliyet veri
    ; hacminden değil DOSYA ADEDİNDEN geliyordu (156 dosya yaratmak 229 ms,
    ; aynı baytları okumak 31 ms). Tek pakete yazınca 51 ms, üstelik bir
    ; sonraki enable()'ın sildiği de ~200 dosya değil 1 dosya oluyor.
    ;
    ; BİÇİM (küçük-endian, hepsi ham):
    ;   "AHKGLOB1"          8 bayt imza
    ;   u32                 kayıt sayısı
    ;   kayıt × N:
    ;     u32 adUzunluk     (UTF-8 bayt)
    ;     ad                UTF-8, NUL yok
    ;     u32 veriUzunluk
    ;     i64 sonYazma      (YYYYMMDDHHMISS — FileSetTime ile geri konur)
    ;     veri              ham bayt
    _pack(root) => root this.name ".pack"
    _bak(root) => root this.name "\"        ; yalnız archive() (cleanNow) kullanır

    ; Taban = başlıktaki u32; paketi açmaya gerek yok. Paket YOKSA gerçekten
    ; "yedek alınamamış" demek (-1), "klasör boştu" değil — snapshot()
    ; paketi her durumda yazıyor.
    baselineCount(root) {
        local p := this._pack(root)
        if (!FileExist(p))
            return -1
        local f := ""
        try {
            f := FileOpen(p, "r")
        } catch {
            return -1
        }
        if (!IsObject(f) || f.Length < 12) {
            try f.Close()
            return -1
        }
        f.RawRead(Buffer(8), 8)             ; imzayı atla
        local n := f.ReadUInt()
        f.Close()
        return n
    }

    count() {
        local n := 0
        if (DirExist(this.dir)) {
            Loop Files, this.dir this.pattern
                n++
        }
        return n
    }

    ; Paket HER durumda yazılır (this.dir yok olsa bile): boş paket,
    ; restore()'a "enable() anında burada hiçbir şey yoktu" bilgisini taşır.
    ; Atlanırsa, oturum sırasında ilk kez yaratılan klasörde restore "yedek
    ; yok" deyip dokunmuyor ve oturum izi kalıcı kalıyor.
    snapshot(root) {
        local p := this._pack(root)
        try FileDelete(p)
        local f := ""
        try {
            f := FileOpen(p, "w")
        } catch {
            return false
        }
        if (!IsObject(f))
            return false
        try {
            f.RawWrite(FileGlobStore._buf("AHKGLOB1"), 8)
            f.WriteUInt(0)                  ; sayı: sona geldiğimizde düzeltilecek
            local n := 0
            if (DirExist(this.dir)) {
                Loop Files, this.dir this.pattern {
                    if (this._packOne(f, A_LoopFileFullPath, A_LoopFileName, A_LoopFileTimeModified))
                        n++
                }
            }
            f.Pos := 8
            f.WriteUInt(n)
        } catch as e {
            try f.Close()
            try FileDelete(p)
            return false
        }
        f.Close()
        return true
    }

    ; OKUNAMAYAN DOSYA (başka süreç kilitlemiş olabilir) yine de ADIYLA
    ; pakete girer ama mtime=0 ile: adı olmazsa restore onu "oturumda
    ; doğmuş" sanıp SİLER, verisi olursa yanlış içerik yazar.
    _packOne(f, path, name, mtime) {
        local data := 0, sz := 0, readable := true
        local src := ""
        try {
            src := FileOpen(path, "r")
        } catch {
            readable := false
        }
        if (readable && IsObject(src)) {
            sz := src.Length
            if (sz > 0) {
                data := Buffer(sz, 0)
                try {
                    src.RawRead(data, sz)
                } catch {
                    readable := false
                }
            }
            src.Close()
        } else {
            readable := false
        }
        local nb := FileGlobStore._buf(name)
        f.WriteUInt(nb.Size)
        f.RawWrite(nb, nb.Size)
        f.WriteUInt(readable ? sz : 0)
        f.WriteInt64(readable ? Integer(mtime) : 0)   ; 0 = veri yok, dokunma
        if (readable && sz > 0)
            f.RawWrite(data, sz)
        return true
    }

    ; Paketi oku -> Map(ad -> { size, mtime, data })
    _unpack(root) {
        local m := Map()
        m.CaseSense := "Off"
        local p := this._pack(root)
        if (!FileExist(p))
            return 0                        ; 0 = yedek YOK (Map() = boş yedek)
        local f := ""
        try {
            f := FileOpen(p, "r")
        } catch {
            return 0
        }
        if (!IsObject(f))
            return 0
        try {
            local sig := Buffer(8, 0)
            f.RawRead(sig, 8)
            if (StrGet(sig, 8, "UTF-8") != "AHKGLOB1") {
                f.Close()
                return 0
            }
            local n := f.ReadUInt()
            Loop n {
                local nameLen := f.ReadUInt()
                local nb := Buffer(nameLen + 1, 0)
                if (nameLen)
                    f.RawRead(nb, nameLen)
                local name := StrGet(nb, nameLen, "UTF-8")
                local sz := f.ReadUInt()
                local mt := f.ReadInt64()
                local data := 0
                if (sz > 0) {
                    data := Buffer(sz, 0)
                    f.RawRead(data, sz)
                }
                m[name] := { size: sz, mtime: mt, data: data }
            }
        } catch {
            f.Close()
            return 0                        ; bozuk paket -> "yedek yok" say, DOKUNMA
        }
        f.Close()
        return m
    }

    ; İki aşama: (1) oturumda DOĞAN dosyaları sil, (2) oturumda DEĞİŞENLERİ
    ; yedekten geri yaz. İkisi birlikte klasörü enable() anındaki haline döndürür.
    restore(root) {
        local bak := this._unpack(root)
        if (!IsObject(bak))
            return false           ; hiç snapshot alınamamış / paket bozuk — dokunma
        if (!DirExist(this.dir))
            return true            ; klasör hâlâ yok -> yapacak bir şey kalmadı
        ; Hedefteki durumu topla; yedekte OLMAYAN dosya oturumda doğmuştur.
        local live := Map()
        live.CaseSense := "Off"
        Loop Files, this.dir this.pattern {
            if (!bak.Has(A_LoopFileName)) {
                try FileDelete(A_LoopFileFullPath)   ; oturumda DOĞDU -> sil
                continue
            }
            live[A_LoopFileName] := { size: A_LoopFileSize, mtime: Integer(A_LoopFileTimeModified) }
        }
        for name, e in bak {
            ; mtime=0 -> yedek alınırken okunamamıştı; içeriğini bilmiyoruz,
            ; dokunmak veriyi bozmak olur.
            if (!e.mtime)
                continue
            ; Birebir aynıysa yazma — oturumda .lnk'lerin çoğuna hiç
            ; dokunulmuyor, bu kontrol disable()'ı sıfıra yakın tutuyor.
            if (live.Has(name) && live[name].size = e.size && live[name].mtime = e.mtime)
                continue
            try {
                local out := FileOpen(this.dir name, "w")
                if (e.size > 0)
                    out.RawWrite(e.data, e.size)
                out.Close()
                ; Damga da geri konmalı (FileCopy kendiliğinden koruyordu,
                ; ham yazma korumaz): "şimdi" kalması başlı başına iz.
                FileSetTime(e.mtime, this.dir name, "M")
            }
        }
        return true
    }

    ; cleanNow()'un KALICI yedeği: orada hız değil elle karıştırılabilirlik
    ; önemli -> paket değil düz klasör kopyası.
    archive(root) {
        local dst := this._bak(root)
        try DirCreate(dst)
        if (DirExist(this.dir)) {
            Loop Files, this.dir this.pattern
                try FileCopy(A_LoopFileFullPath, dst A_LoopFileName, true)
        }
        return true
    }

    ; Dizeyi NUL'suz UTF-8 Buffer'a çevir.
    static _buf(s) {
        local need := StrPut(s, "UTF-8") - 1
        local b := Buffer(need < 0 ? 0 : need, 0)
        if (need > 0) {
            local tmp := Buffer(need + 1, 0)
            StrPut(s, tmp, "UTF-8")
            DllCall("RtlMoveMemory", "ptr", b, "ptr", tmp, "uptr", need)
        }
        return b
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
    ; apply() durumu yalnız bellekte tutuyor; script çökerse yeni instance'ın
    ; applied'ı false olur, revert() no-op kalır ve politikalar KALICI olarak
    ; takılı kalırdı (Explorer'ın "Son kullanılanlar"ı bir daha dönmezdi).
    ; Bu ikili eski değerleri diske yazıp instance'tan bağımsız geri yüklüyor.
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
