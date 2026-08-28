#Include <gdip_mini>
; ═══════════════════════════════════════════════════════════
; singleClipImageStore — Pano görsellerinin kalıcı deposu.
;
; İki dosya:
;   clipimg.idx  Sabit boyutlu slot dizisi (7.84 MB). Metadata + 64x64 ham thumb.
;                Slot no = fiziksel konum, offset = 32 + slot * 16448.
;                Hiç büyümez, hiç compaction istemez.
;   clipimg.dat  500 MB DAİRESEL log. Sadece PNG blob'ları, append-only.
;                Dolunca en eski kayıtlardan (tail) yer açılana kadar yenir.
;
; Görsel ASLA ham saklanmaz — DIB yalnızca yakalama/geri koyma anında,
; GdipMini içinden geçerken var olur. Tek ham istisna: thumb'lar (sabit
; slot boyutu için, decode maliyetini sıfırlamak adına).
;
; Yazma sırası (crash güvenliği): önce blob → sonra slot → EN SON header.
; Header commit noktasıdır; yarıda kalan yazımda header eski durumu gösterir,
; yazılmış yetim baytlar bir sonraki turda üzerine yazılır.
;
; Slot düzeni (v2) — 64 B metadata + 16384 B thumb:
;    0 u8  state (0=boş 1=dolu)   1 u8  type (1=PNG)   2 u16 count
;    4 u32 id                     8 u64 ts (son kullanım)
;   16 u32 hash (ham DIB crc32)  20 u32 datOffset     24 u32 datSize
;   28 u32 w                     32 u32 h             36 u16 bpp
;   40 u64 createdTs (ilk yakalama)                   48..63 rezerve
; ═══════════════════════════════════════════════════════════
class singleClipImageStore {
    static instance := ""

    static MAGIC        := 0x474D4943   ; 'CIMG'
    static VERSION      := 2             ; v2: srcExe alanı kaldırıldı, yerine createdTs
    static HDR_BYTES    := 32
    static META_BYTES   := 64
    static SLOT_BYTES   := 64 + 16384   ; 16448 — GdipMini.THUMB_BYTES ile eşleşir
    static MAX_SLOTS    := 500
    static MAX_DAT      := 500 * 1024 * 1024
    static MAX_PNG      := 8 * 1024 * 1024    ; kodlanmış üst sınır
    static MAX_RAW      := 64 * 1024 * 1024   ; ham DIB akıl sağlığı sınırı
    static BLOB_HDR     := 8                  ; [u32 totalLen][u32 tag]
    static TAG_PAD      := 0xFFFFFFFF
    ; Relocate eşikleri: ring %80 dolmadan tahliye riski yok, boşuna kopyalama yapma.
    ; Doluysa ve kayıttan DAHA ESKİ 50'den az kayıt kaldıysa head'e taşı.
    ; Ölçü bayt değil KAYIT SAYISI — küçük görsellerde bayt eşiği yanıltıcı olur
    ; (50 MB, 100 KB'lık görsellerde 500 kayıt eder, yani "yakında" demez).
    static RELOCATE_FULL   := 0.80
    static RELOCATE_MARGIN := 50      ; kayıt

    static getInstance() {
        if (!singleClipImageStore.instance)
            singleClipImageStore.instance := singleClipImageStore()
        return singleClipImageStore.instance
    }

    __New() {
        if (singleClipImageStore.instance)
            throw Error("ClipImageStore zaten oluşturulmuş! getInstance kullan.")
        this.slots    := []      ; 1..MAX_SLOTS, her biri Map veya ""  (1-tabanlı: slot no = index-1)
        this.byHash   := Map()   ; hash -> slot no (0-tabanlı)
        this.nextId   := 1
        this.datHead  := 0
        this.datTail  := 0
        this.datUsed  := 0
        this.idxFile  := 0
        this.datFile  := 0
        this.rev      := 0       ; her değişiklikte artar; dialog bunu yoklar
        GdipMini.startup()
        this._open()
    }

    ; ── Açılış / dosya kurulumu ──────────────────────────────────────────────

    _open() {
        try {
            if (!FileExist(Path.ClipImgIdx) || !FileExist(Path.ClipImgDat))
                this._createFiles()
            else if (!this._versionOk())
                this._resetForNewVersion()
            this.idxFile := FileOpen(Path.ClipImgIdx, "rw")
            this.datFile := FileOpen(Path.ClipImgDat, "rw")
            if (!this.idxFile || !this.datFile)
                throw Error("ClipImgStore: dosyalar açılamadı")
            this._loadMeta()
            this._alignRingHead()
        } catch as err {
            App.ErrHandler.handleError("ClipImgStore._open: " err.Message, err, true)
            this._closeFiles()
        }
    }

    ; Header'ın ilk 8 baytı (magic + version) beklediğimizle uyuşuyor mu?
    _versionOk() {
        local file := FileOpen(Path.ClipImgIdx, "r")
        if (!file)
            return false
        local hdr := Buffer(8, 0)
        local read := file.RawRead(hdr, 8)
        file.Close()
        return (read == 8
             && NumGet(hdr, 0, "UInt") == singleClipImageStore.MAGIC
             && NumGet(hdr, 4, "UInt") == singleClipImageStore.VERSION)
    }

    ; Slot düzeni değiştiğinde eski veri okunamaz. Sessizce silmiyoruz: iki dosyayı
    ; da yedekleyip sıfırdan kuruyoruz (repodaki backupOnError deseni).
    _resetForNewVersion() {
        App.ErrHandler.handleError("ClipImgStore: format sürümü değişti, depo sıfırlanıyor", , true)
        App.ErrHandler.backupOnError("ClipImgStore.idx", Path.ClipImgIdx)
        App.ErrHandler.backupOnError("ClipImgStore.dat", Path.ClipImgDat)
        this._createFiles()
    }

    ; Boş idx (7.84 MB sıfır) + boş dat (sparse, ilk yazımda büyür).
    _createFiles() {
        FileIO.writeBinary(Path.ClipImgIdx, (file) => (
            hdr := Buffer(singleClipImageStore.HDR_BYTES, 0),
            NumPut("UInt", singleClipImageStore.MAGIC, hdr, 0),
            NumPut("UInt", singleClipImageStore.VERSION, hdr, 4),
            NumPut("UInt", singleClipImageStore.MAX_SLOTS, hdr, 8),
            NumPut("UInt", 1, hdr, 12),          ; nextId
            file.RawWrite(hdr, singleClipImageStore.HDR_BYTES),
            this._writeBlankSlots(file)
        ))
        ; .dat'ı sıfır uzunlukta oluştur; ring imleci ilerledikçe büyür,
        ; 500 MB'ı baştan ayırmıyoruz (çoğu kullanıcıda hiç dolmayacak)
        FileOpen(Path.ClipImgDat, "w").Close()
    }

    _writeBlankSlots(file) {
        local blank := Buffer(singleClipImageStore.SLOT_BYTES, 0)
        Loop singleClipImageStore.MAX_SLOTS
            file.RawWrite(blank, singleClipImageStore.SLOT_BYTES)
    }

    ; Açılışta SADECE metadata okunur (500 × 64 B, strided seek).
    ; Thumb'lar (8 MB) dialog açılana kadar diskte kalır.
    _loadMeta() {
        local hdr := Buffer(singleClipImageStore.HDR_BYTES, 0)
        this.idxFile.Seek(0)
        if (this.idxFile.RawRead(hdr, singleClipImageStore.HDR_BYTES) != singleClipImageStore.HDR_BYTES)
            throw Error("ClipImgStore: header okunamadı")
        if (NumGet(hdr, 0, "UInt") != singleClipImageStore.MAGIC)
            throw Error("ClipImgStore: geçersiz magic")
        if (NumGet(hdr, 4, "UInt") != singleClipImageStore.VERSION)
            throw Error("ClipImgStore: desteklenmeyen sürüm")
        local slotCount := Min(NumGet(hdr, 8, "UInt"), singleClipImageStore.MAX_SLOTS)
        this.nextId  := NumGet(hdr, 12, "UInt")
        this.datHead := NumGet(hdr, 16, "UInt")
        this.datTail := NumGet(hdr, 20, "UInt")
        this.datUsed := NumGet(hdr, 24, "UInt")
        ; Header bozuksa ring imleçlerine güvenmek felaket olur (devasa Buffer,
        ; sonsuz tahliye döngüsü). Ring'i boşaltıyoruz — VE slot'ları da: imleçler
        ; olmadan blob'ların nerede yaşadığını bilemeyiz, kayıtları tutmak onları
        ; birazdan üzerine yazılacak baytları gösterir halde bırakırdı.
        local ringLost := (this.datHead >= singleClipImageStore.MAX_DAT
                        || this.datTail >= singleClipImageStore.MAX_DAT
                        || this.datUsed > singleClipImageStore.MAX_DAT)
        if (ringLost) {
            App.ErrHandler.handleError("ClipImgStore: ring imleçleri sınır dışı (head="
                this.datHead " tail=" this.datTail " used=" this.datUsed
                "), depo sıfırlanıyor", , true)
            this.datHead := 0, this.datTail := 0, this.datUsed := 0
        }

        this.slots := []
        this.byHash := Map()
        local meta := Buffer(singleClipImageStore.META_BYTES, 0)
        Loop slotCount {
            local slot := A_Index - 1
            this.idxFile.Seek(this._slotOffset(slot))
            if (this.idxFile.RawRead(meta, singleClipImageStore.META_BYTES) != singleClipImageStore.META_BYTES)
                break
            if (NumGet(meta, 0, "UChar") == 0) {
                this.slots.Push("")
                continue
            }
            local rec := this._parseMeta(meta, slot)
            ; Bozuk kaydı yükleme: datSize'a körü körüne güvenip _readBlob'da
            ; devasa Buffer ayırmayalım. Slot boş sayılır, ilk yazımda geri kazanılır.
            if (ringLost || !this._recValid(rec)) {
                this.slots.Push("")
                this._clearMeta(slot)      ; diskte de kalmasın
                continue
            }
            this.slots.Push(rec)
            this.byHash[rec["hash"]] := slot
        }
        while (this.slots.Length < singleClipImageStore.MAX_SLOTS)
            this.slots.Push("")
    }

    _parseMeta(meta, slot) {
        return Map(
            "slot",      slot,
            "state",     NumGet(meta, 0, "UChar"),
            "type",      NumGet(meta, 1, "UChar"),
            "count",     NumGet(meta, 2, "UShort"),
            "id",        NumGet(meta, 4, "UInt"),
            "ts",        NumGet(meta, 8, "UInt64"),     ; son kullanım
            "hash",      NumGet(meta, 16, "UInt"),
            "datOffset", NumGet(meta, 20, "UInt"),
            "datSize",   NumGet(meta, 24, "UInt"),
            "w",         NumGet(meta, 28, "UInt"),
            "h",         NumGet(meta, 32, "UInt"),
            "bpp",       NumGet(meta, 36, "UShort"),
            "createdTs", NumGet(meta, 40, "UInt64"))    ; ilk yakalama
    }

    _slotOffset(slot) {
        return singleClipImageStore.HDR_BYTES + slot * singleClipImageStore.SLOT_BYTES
    }

    ; Diskten okunan kayıt akla yatkın mı? (idx bozulmasına karşı tek savunma)
    _recValid(rec) {
        return rec["datSize"] > 0
            && rec["datSize"] <= singleClipImageStore.MAX_PNG
            && rec["datOffset"] < singleClipImageStore.MAX_DAT
            && rec["w"] > 0 && rec["h"] > 0
    }

    ; ── Yakalama ─────────────────────────────────────────────────────────────

    ; pano CF_DIB bloğu → depoya. Dönen: slot no, veya -1.
    ; thumbBuf/pngBuf üretimi burada; çağıran sadece DIB pointer'ı verir.
    save(pDib, dibSize) {
        try {
            if (dibSize > singleClipImageStore.MAX_RAW)
                return -1
            local w := NumGet(pDib, 4, "Int")
            local h := Abs(NumGet(pDib, 8, "Int"))
            local bpp := NumGet(pDib, 14, "UShort")

            ; Hash HAM piksellerden — PNG kodlaması deterministik değil
            local hash := GdipMini.crc32(pDib, dibSize)

            ; Dedupe: aynı görsel zaten varsa blob'a hiç dokunma.
            ; -1 dönerse kayıt geçersizdi (veya CRC çakışması) → normal akış devam eder.
            if (this.byHash.Has(hash)) {
                local dup := this._touchDuplicate(hash, w, h, bpp)
                if (dup >= 0)
                    return dup
            }

            local png := GdipMini.dibToPng(pDib, dibSize)
            if (!png || png.Size == 0 || png.Size > singleClipImageStore.MAX_PNG)
                return -1
            local thumb := GdipMini.dibToThumb(pDib, dibSize)
            if (!thumb)
                return -1

            local offset := this._appendBlob(png, png.Size, 0)   ; tag sonra damgalanır
            if (offset < 0)
                return -1
            local slot := this._allocSlot()
            if (slot < 0)
                return -1
            this._stampTag(offset, slot)

            local now := this._nowMs()
            local rec := Map(
                "slot", slot, "state", 1, "type", 1, "count", 1,
                "id", this.nextId, "ts", now, "createdTs", now, "hash", hash,
                "datOffset", offset, "datSize", png.Size,
                "w", w, "h", h, "bpp", bpp)
            this.nextId += 1
            this.slots[slot + 1] := rec
            this.byHash[hash] := slot
            this._writeMeta(rec, thumb)
            this._writeHeader()
            return slot
        } catch as err {
            App.ErrHandler.handleError("ClipImgStore.save: " err.Message, err)
            return -1
        }
    }

    ; Zaten depoda olan görselin sayaç/zaman damgasını tazeler. Dönen: slot veya -1.
    ; -1 = "bu bir kopya değil" (kayıt ölmüş ya da CRC32 çakışması) → yeniden kaydet.
    _touchDuplicate(hash, w, h, bpp) {
        local slot := this.byHash[hash]
        local rec := (slot >= 0 && slot < singleClipImageStore.MAX_SLOTS) ? this.slots[slot + 1] : ""
        if (rec == "" || rec["state"] == 0) {
            this.byHash.Delete(hash)
            return -1
        }
        ; CRC32 çakışması nadir ama mümkün — boyutlar tutmuyorsa aynı görsel değil.
        ; (byHash girdisi silinmez; yeni kayıt onu zaten üzerine yazacak.)
        if (rec["w"] != w || rec["h"] != h || rec["bpp"] != bpp)
            return -1
        rec["count"] := Min(65535, rec["count"] + 1)
        rec["ts"] := this._nowMs()
        local moved := this._isNearTail(rec)
        if (moved && !this._relocate(rec))
            return -1                 ; baytları yenmiş, kayıt düştü → yeniden kaydet
        this._writeMeta(rec)
        if (moved)                    ; ring imleçleri yalnız taşımada değişir
            this._writeHeader()
        return slot
    }

    ; ── Pano giriş / çıkış ───────────────────────────────────────────────────

    ; Panoda CF_DIB var mı?
    static clipboardHasImage() {
        return DllCall("IsClipboardFormatAvailable", "UInt", 8) ? true : false   ; CF_DIB
    }

    ; Panodaki görseli depoya al. Dönen: slot no veya -1.
    ; Pano kilidini MÜMKÜN OLAN EN KISA süre tutuyoruz: baytları kendi buffer'ımıza
    ; kopyalayıp panoyu hemen kapatıyoruz, PNG kodlaması ondan sonra.
    ; (clip_hist'teki Win+V / cbdhsvc dersi burada da geçerli.)
    saveFromClipboard() {
        local copy := 0, size := 0
        if (!singleClipImageStore.clipboardHasImage())
            return -1
        if (!DllCall("OpenClipboard", "Ptr", 0))
            return -1
        try {
            local hMem := DllCall("GetClipboardData", "UInt", 8, "Ptr")
            if (!hMem)
                return -1
            size := DllCall("GlobalSize", "Ptr", hMem, "UPtr")
            if (size == 0 || size > singleClipImageStore.MAX_RAW)
                return -1
            local src := DllCall("GlobalLock", "Ptr", hMem, "Ptr")
            if (!src)
                return -1
            copy := Buffer(size)
            DllCall("RtlMoveMemory", "Ptr", copy, "Ptr", src, "Ptr", size)
            DllCall("GlobalUnlock", "Ptr", hMem)
        } catch as err {
            App.ErrHandler.handleError("ClipImgStore.saveFromClipboard: " err.Message, err)
            return -1
        } finally {
            DllCall("CloseClipboard")
        }
        return copy ? this.save(copy.Ptr, size) : -1
    }

    ; Kaydı panoya geri koy (CF_DIB). Başarılıysa true.
    toClipboard(slot) {
        local dib := this.loadAsDib(slot)
        if (!dib)
            return false
        ; GMEM_MOVEABLE — SetClipboardData sahipliği devralır, BİZ SERBEST BIRAKMAYIZ
        local hMem := DllCall("GlobalAlloc", "UInt", 0x2, "Ptr", dib.Size, "Ptr")
        if (!hMem)
            return false
        local dst := DllCall("GlobalLock", "Ptr", hMem, "Ptr")
        if (!dst) {                       ; kilitlenemedi → null'a kopyalamak çökertir
            DllCall("GlobalFree", "Ptr", hMem)
            return false
        }
        DllCall("RtlMoveMemory", "Ptr", dst, "Ptr", dib, "Ptr", dib.Size)
        DllCall("GlobalUnlock", "Ptr", hMem)

        if (!DllCall("OpenClipboard", "Ptr", 0)) {
            DllCall("GlobalFree", "Ptr", hMem)
            return false
        }
        DllCall("EmptyClipboard")
        local ok := DllCall("SetClipboardData", "UInt", 8, "Ptr", hMem, "Ptr")
        DllCall("CloseClipboard")
        if (!ok) {
            DllCall("GlobalFree", "Ptr", hMem)
            return false
        }
        return true
    }

    ; ── Ring yönetimi ────────────────────────────────────────────────────────

    ; Blob'u head'e yazar, gerekirse tail'dan yiyerek yer açar. Dönen: offset veya -1.
    ;
    ; Uzunluk 8'in (BLOB_HDR) katına yuvarlanır. Yuvarlamasak ring sonunda 1..7
    ; baytlık, header'ı SIĞMAYAN bir boşluk kalabiliyordu: ne pad kaydı yazılabilir
    ; ne de tail o boşluğu geçebilirdi — ring okunamaz hale gelirdi. Hizalı yazımda
    ; her boşluk ya 0 ya da >= 8 bayttır. Fazladan baytlar hiç okunmaz; gerçek
    ; uzunluğu kaydın datSize alanı tutar.
    _appendBlob(buf, size, tag) {
        local total := this._align(size + singleClipImageStore.BLOB_HDR)
        if (total > singleClipImageStore.MAX_DAT)
            return -1

        ; Kayıt dosya sonunda İKİYE BÖLÜNMEZ: sığmıyorsa oraya pad bırak, başa dön
        local tailRoom := singleClipImageStore.MAX_DAT - this.datHead
        if (tailRoom < total && tailRoom > 0) {
            if (tailRoom < singleClipImageStore.BLOB_HDR) {
                ; Hizalama düzeltmesinden ÖNCE yazılmış bir dosyada olabilir
                ; (_alignRingHead yer bulamadıysa). Tarif edilemez boşluk.
                App.ErrHandler.handleError("ClipImgStore: ring sonunda tarif edilemez "
                    tailRoom " baytlık boşluk — yeni görsel kaydedilemiyor", , true)
                return -1
            }
            if (!this._ensureSpace(tailRoom))
                return -1
            this._writeBlobHeader(this.datHead, tailRoom, singleClipImageStore.TAG_PAD)
            this.datUsed += tailRoom
            this.datHead := 0
        }
        if (!this._ensureSpace(total))
            return -1

        local offset := this.datHead
        this._writeBlobHeader(offset, total, tag ? tag : singleClipImageStore.TAG_PAD)
        local c := this._ioBegin()
        this.datFile.Seek(offset + singleClipImageStore.BLOB_HDR)
        this.datFile.RawWrite(buf, size)
        this._ioEnd(c)
        this.datHead := Mod(offset + total, singleClipImageStore.MAX_DAT)
        this.datUsed += total
        return offset
    }

    _align(n) {
        local rest := Mod(n, singleClipImageStore.BLOB_HDR)
        return rest ? n + (singleClipImageStore.BLOB_HDR - rest) : n
    }

    ; Tek seferlik göç: hizalama kuralından önce yazılmış dosyalarda datHead 8'in
    ; katı olmayabilir. 9..15 baytlık ÖLÜ bir pad kaydı yazıp head'i katına
    ; getiriyoruz (8'den kısa pad header'a sığmaz, o yüzden bir tam header ekliyoruz).
    ; Bundan sonra tüm yazımlar hizalı kalır. Veri kaybı yok.
    _alignRingHead() {
        if (!this.datFile)
            return
        local rest := Mod(this.datHead, singleClipImageStore.BLOB_HDR)
        if (rest == 0)
            return
        local padLen := 2 * singleClipImageStore.BLOB_HDR - rest
        local tailRoom := singleClipImageStore.MAX_DAT - this.datHead
        if (tailRoom < padLen)
            padLen := tailRoom                    ; sona çok yakınsa kalanı tamamen yut
        if (padLen < singleClipImageStore.BLOB_HDR || !this._ensureSpace(padLen))
            return                                ; _appendBlob zaten hata verecek
        this._writeBlobHeader(this.datHead, padLen, singleClipImageStore.TAG_PAD)
        this.datUsed += padLen
        this.datHead := Mod(this.datHead + padLen, singleClipImageStore.MAX_DAT)
        this._writeHeader()
    }

    ; free < need olduğu sürece tail'daki kaydı yer. Kayıt kendini tarif ettiği
    ; için index'e bakmaya gerek yok — 8 baytlık blob header yeter.
    _ensureSpace(need) {
        local guard := 0
        while (singleClipImageStore.MAX_DAT - this.datUsed < need) {
            if (this.datUsed == 0 || ++guard > singleClipImageStore.MAX_SLOTS * 2)
                return false
            local hdrBuf := Buffer(singleClipImageStore.BLOB_HDR, 0)
            local c := this._ioBegin()
            this.datFile.Seek(this.datTail)
            local n := this.datFile.RawRead(hdrBuf, singleClipImageStore.BLOB_HDR)
            this._ioEnd(c)
            if (n != singleClipImageStore.BLOB_HDR)
                return false
            local len := NumGet(hdrBuf, 0, "UInt")
            local tag := NumGet(hdrBuf, 4, "UInt")
            if (len == 0 || len > this.datUsed)
                return false                    ; bozuk ring — yutmayı durdur
            if (tag != singleClipImageStore.TAG_PAD)
                this._freeSlot(tag, false)      ; blob öldü → slot da boşalır
            this.datTail := Mod(this.datTail + len, singleClipImageStore.MAX_DAT)
            this.datUsed -= len
        }
        return true
    }

    ; Sık çağrılan görsel tahliye sırasına yaklaştıysa head'e taşı (LRU'ya yaklaşır).
    ; Ring dolmamışsa hiç tetiklenmez; dolduktan sonra da sadece en eski 50 kayıt
    ; taşınır, yani kopyalama pratikte nadir.
    _isNearTail(rec) {
        if (this.datUsed < singleClipImageStore.MAX_DAT * singleClipImageStore.RELOCATE_FULL)
            return false
        return this._olderCount(rec) < singleClipImageStore.RELOCATE_MARGIN
    }

    ; rec'ten daha eski (tail'a daha yakın) kaç yaşayan kayıt var?
    ; Tahliye sırası bu — kaç kayıt sonra rec'in yeneceğini doğrudan söyler.
    _olderCount(rec) {
        local myDist := this._distFromTail(rec["datOffset"])
        local n := 0
        Loop singleClipImageStore.MAX_SLOTS {
            local other := this.slots[A_Index]
            if (other == "" || other["slot"] == rec["slot"])
                continue
            if (this._distFromTail(other["datOffset"]) < myDist)
                n += 1
        }
        return n
    }

    _distFromTail(offset) {
        return Mod(offset - this.datTail + singleClipImageStore.MAX_DAT, singleClipImageStore.MAX_DAT)
    }

    ; Dönen: KAYIT HÂLÂ GEÇERLİ Mİ? (taşındı ya da yerinde bırakıldı → true;
    ; baytları bu arada yenildiği için düşürüldü → false)
    _relocate(rec) {
        local png := this._readBlob(rec)
        if (!png)
            return true                    ; okunamadı; kayda dokunmadık, duruyor
        local oldOffset := rec["datOffset"]
        ; Eski kopyayı ÖNCE ölü damgala: yeni yazım tail'ı ilerletirse eski kayıt
        ; slot'u yanlışlıkla boşaltmasın
        this._stampTag(oldOffset, singleClipImageStore.TAG_PAD)
        local offset := this._appendBlob(png, png.Size, 0)
        if (offset >= 0) {
            this._stampTag(offset, rec["slot"])
            rec["datOffset"] := offset
            return true
        }
        ; Yazım başarısız. Eski kopya hâlâ ring'de duruyorsa tag'ini geri koy —
        ; yoksa tail oraya varınca slot'u boşaltmaz, kayıt ölü baytları gösterirdi.
        if (this._distFromTail(oldOffset) < this.datUsed) {
            this._stampTag(oldOffset, rec["slot"])
            return true
        }
        this._freeSlot(rec["slot"], false)   ; baytlar gitti → kaydı düşür
        return false
    }

    _writeBlobHeader(offset, len, tag) {
        local hdrBuf := Buffer(singleClipImageStore.BLOB_HDR, 0)
        NumPut("UInt", len, hdrBuf, 0)
        NumPut("UInt", tag, hdrBuf, 4)
        local c := this._ioBegin()
        this.datFile.Seek(offset)
        this.datFile.RawWrite(hdrBuf, singleClipImageStore.BLOB_HDR)
        this._ioEnd(c)
    }

    _stampTag(offset, tag) {
        local tagBuf := Buffer(4, 0)
        NumPut("UInt", tag, tagBuf, 0)
        local c := this._ioBegin()
        this.datFile.Seek(offset + 4)
        this.datFile.RawWrite(tagBuf, 4)
        this._ioEnd(c)
    }

    ; ── Slot yönetimi ────────────────────────────────────────────────────────

    ; Boş slot bul. Yoksa slot tavanı dolmuş demektir → tail'dan bir kayıt ye.
    _allocSlot() {
        Loop singleClipImageStore.MAX_SLOTS {
            if (this.slots[A_Index] == "")
                return A_Index - 1
        }
        ; .dat'ta yer var ama 500 slot dolu: en eski blob'u yiyerek slot aç
        local before := this.datTail
        if (!this._evictOne() || this.datTail == before)
            return -1
        Loop singleClipImageStore.MAX_SLOTS {
            if (this.slots[A_Index] == "")
                return A_Index - 1
        }
        return -1
    }

    _evictOne() {
        local hdrBuf := Buffer(singleClipImageStore.BLOB_HDR, 0)
        local c := this._ioBegin()
        this.datFile.Seek(this.datTail)
        local n := this.datFile.RawRead(hdrBuf, singleClipImageStore.BLOB_HDR)
        this._ioEnd(c)
        if (n != singleClipImageStore.BLOB_HDR)
            return false
        local len := NumGet(hdrBuf, 0, "UInt")
        local tag := NumGet(hdrBuf, 4, "UInt")
        if (len == 0 || len > this.datUsed)
            return false
        if (tag != singleClipImageStore.TAG_PAD)
            this._freeSlot(tag, false)
        this.datTail := Mod(this.datTail + len, singleClipImageStore.MAX_DAT)
        this.datUsed -= len
        return true
    }

    ; stampPad=true → blob hâlâ ringde yaşıyor, tag'i ölü damgala (elle silme).
    ; stampPad=false → blob zaten tail'da yenildi, damgaya gerek yok.
    _freeSlot(slot, stampPad := true) {
        if (slot < 0 || slot >= singleClipImageStore.MAX_SLOTS)
            return
        local rec := this.slots[slot + 1]
        if (rec == "")
            return
        if (stampPad)
            this._stampTag(rec["datOffset"], singleClipImageStore.TAG_PAD)
        if (this.byHash.Has(rec["hash"]) && this.byHash[rec["hash"]] == slot)
            this.byHash.Delete(rec["hash"])
        this.slots[slot + 1] := ""
        this._clearMeta(slot)
    }

    ; ── Silme / geri alma ────────────────────────────────────────────────────

    ; Tek kayıt silme — deleteMany'nin kısayolu.
    delete(slot) {
        return this.deleteMany([slot]) > 0
    }

    ; Toplu silme. Dönen: silinen kayıt sayısı.
    ; Blob baytları .dat'ta fiziksel olarak kalır; alanları tail oraya varınca
    ; geri kazanılır. Slot ise hemen boşalır.
    deleteMany(slots) {
        local n := 0
        for slot in slots {
            local rec := (slot >= 0 && slot < singleClipImageStore.MAX_SLOTS) ? this.slots[slot + 1] : ""
            if (rec == "")
                continue
            this._freeSlot(slot, true)
            n += 1
        }
        if (n > 0)
            this._writeHeader()
        return n
    }

    ; ── Okuma ────────────────────────────────────────────────────────────────

    ; Tam çözünürlüklü PNG byte'ları — SADECE seçili kayıt için, tembel.
    _readBlob(rec) {
        local buf := Buffer(rec["datSize"])
        local c := this._ioBegin()
        this.datFile.Seek(rec["datOffset"] + singleClipImageStore.BLOB_HDR)
        local n := this.datFile.RawRead(buf, rec["datSize"])
        this._ioEnd(c)
        return (n == rec["datSize"]) ? buf : 0
    }

    ; Dialog önizlemesi için HBITMAP. ÇAĞIRAN DeleteObject ETMELİ.
    loadFull(slot) {
        try {
            local rec := this.slots[slot + 1]
            if (rec == "")
                return 0
            local png := this._readBlob(rec)
            return png ? GdipMini.pngToHbitmap(png, png.Size) : 0
        } catch as err {
            App.ErrHandler.handleError("ClipImgStore.loadFull: " err.Message, err)
            return 0
        }
    }

    ; Ham PNG byte'ları (Buffer) — dialog zoom/pan için bir kez okuyup pBitmap'e çözer.
    loadPng(slot) {
        try {
            local rec := this.slots[slot + 1]
            return (rec == "") ? 0 : this._readBlob(rec)
        } catch as err {
            App.ErrHandler.handleError("ClipImgStore.loadPng: " err.Message, err)
            return 0
        }
    }

    ; Dialog önizlemesi — kutuya sığdırılmış HBITMAP. ÇAĞIRAN DeleteObject ETMELİ.
    loadFullFit(slot, maxW, maxH) {
        try {
            local rec := this.slots[slot + 1]
            if (rec == "")
                return 0
            local png := this._readBlob(rec)
            return png ? GdipMini.pngToHbitmapFit(png, png.Size, maxW, maxH) : 0
        } catch as err {
            App.ErrHandler.handleError("ClipImgStore.loadFullFit: " err.Message, err)
            return 0
        }
    }

    ; Blob zaten PNG — dosyaya olduğu gibi yazılır, yeniden kodlama yok.
    exportTo(slot, targetPath) {
        try {
            local rec := this.slots[slot + 1]
            if (rec == "")
                return false
            local png := this._readBlob(rec)
            if (!png)
                return false
            FileIO.writeBinary(targetPath, (file) => file.RawWrite(png, png.Size))
            return true
        } catch as err {
            App.ErrHandler.handleError("ClipImgStore.exportTo: " err.Message, err)
            return false
        }
    }

    ; Panoya geri koymak için CF_DIB blob'u.
    loadAsDib(slot) {
        local rec := this.slots[slot + 1]
        if (rec == "")
            return 0
        local png := this._readBlob(rec)
        return png ? GdipMini.pngToDib(png, png.Size) : 0
    }

    _readThumb(slot) {
        local thumb := Buffer(GdipMini.THUMB_BYTES, 0)
        local c := this._ioBegin()
        this.idxFile.Seek(this._slotOffset(slot) + singleClipImageStore.META_BYTES)
        this.idxFile.RawRead(thumb, GdipMini.THUMB_BYTES)
        this._ioEnd(c)
        return thumb
    }

    ; Dialog açılışında tek seferlik ~8 MB okuma, decode yok.
    loadThumbs() {
        local out := []
        Loop singleClipImageStore.MAX_SLOTS {
            local rec := this.slots[A_Index]
            if (rec == "")
                continue
            local item := rec.Clone()
            item["thumb"] := this._readThumb(rec["slot"])
            out.Push(item)
        }
        ; Gösterim sırası ts'e göre — fiziksel slot düzeni kullanıcıya yansımasın
        return this._sortByTsDesc(out)
    }

    ; Sadece metadata (thumb'sız) — menü/istatistik için.
    list() {
        local out := []
        Loop singleClipImageStore.MAX_SLOTS {
            if (this.slots[A_Index] != "")
                out.Push(this.slots[A_Index])
        }
        return this._sortByTsDesc(out)
    }

    ; ── Disk yazımı ──────────────────────────────────────────────────────────

    ; 64 B metadata; thumb yalnız yeni kayıtta yazılır (16 KB boşuna yazılmasın).
    _writeMeta(rec, thumb := 0) {
        this.rev += 1
        local meta := Buffer(singleClipImageStore.META_BYTES, 0)
        NumPut("UChar",  rec["state"],     meta, 0)
        NumPut("UChar",  rec["type"],      meta, 1)
        NumPut("UShort", rec["count"],     meta, 2)
        NumPut("UInt",   rec["id"],        meta, 4)
        NumPut("UInt64", rec["ts"],        meta, 8)
        NumPut("UInt",   rec["hash"],      meta, 16)
        NumPut("UInt",   rec["datOffset"], meta, 20)
        NumPut("UInt",   rec["datSize"],   meta, 24)
        NumPut("UInt",   rec["w"],         meta, 28)
        NumPut("UInt",   rec["h"],         meta, 32)
        NumPut("UShort", rec["bpp"],       meta, 36)
        NumPut("UInt64", rec["createdTs"], meta, 40)
        ; 48..63 rezerve (sıfır)

        local c := this._ioBegin()
        this.idxFile.Seek(this._slotOffset(rec["slot"]))
        this.idxFile.RawWrite(meta, singleClipImageStore.META_BYTES)
        if (thumb)
            this.idxFile.RawWrite(thumb, GdipMini.THUMB_BYTES)
        this._ioEnd(c)
    }

    ; state=0 yeterli; thumb baytları yerinde kalır (yeni kayıt üzerine yazar).
    _clearMeta(slot) {
        this.rev += 1
        local zero := Buffer(singleClipImageStore.META_BYTES, 0)
        local c := this._ioBegin()
        this.idxFile.Seek(this._slotOffset(slot))
        this.idxFile.RawWrite(zero, singleClipImageStore.META_BYTES)
        this._ioEnd(c)
    }

    ; Commit noktası — her zaman EN SON çağrılır.
    _writeHeader() {
        local hdr := Buffer(singleClipImageStore.HDR_BYTES, 0)
        NumPut("UInt", singleClipImageStore.MAGIC, hdr, 0)
        NumPut("UInt", singleClipImageStore.VERSION, hdr, 4)
        NumPut("UInt", singleClipImageStore.MAX_SLOTS, hdr, 8)
        NumPut("UInt", this.nextId, hdr, 12)
        NumPut("UInt", this.datHead, hdr, 16)
        NumPut("UInt", this.datTail, hdr, 20)
        NumPut("UInt", this.datUsed, hdr, 24)
        local c := this._ioBegin()
        this.idxFile.Seek(0)
        this.idxFile.RawWrite(hdr, singleClipImageStore.HDR_BYTES)
        this._ioEnd(c)
    }

    ; ── Yardımcılar ──────────────────────────────────────────────────────────

    ; Seek + Raw ÇİFTİ BÖLÜNEMEZ: handle tüm thread'lerde ortak, araya giren
    ; timer başka offset'e Seek ederse okuma yanlış yerden gelir. Ağır iş
    ; (PNG/GDI+) bölgenin dışında kalmalı.
    _ioBegin() {
        local prev := A_IsCritical
        Critical "On"
        return prev
    }
    _ioEnd(prev) {
        Critical prev
    }


    ; Depo özeti — TEK geçiş. Dialog her karede değil, yalnız açılışta/silmede çağırır.
    getStats() {
        local count := 0, liveBytes := 0, copies := 0
        local oldest := 0, newest := 0
        Loop singleClipImageStore.MAX_SLOTS {
            local rec := this.slots[A_Index]
            if (rec == "")
                continue
            count += 1
            liveBytes += rec["datSize"] + singleClipImageStore.BLOB_HDR
            copies += rec["count"]
            if (oldest == 0 || rec["createdTs"] < oldest)
                oldest := rec["createdTs"]
            if (rec["ts"] > newest)
                newest := rec["ts"]
        }
        return Map(
            "count",     count,
            "maxCount",  singleClipImageStore.MAX_SLOTS,
            "liveBytes", liveBytes,                          ; yaşayan kayıtlar
            "ringUsed",  this.datUsed,                       ; ölü baytlar dahil
            "ringMax",   singleClipImageStore.MAX_DAT,
            "deadBytes", Max(0, this.datUsed - liveBytes),   ; silinmiş/taşınmış artık
            "datBytes",  FileExist(Path.ClipImgDat) ? FileGetSize(Path.ClipImgDat) : 0,
            "idxBytes",  FileExist(Path.ClipImgIdx) ? FileGetSize(Path.ClipImgIdx) : 0,
            "copies",    copies,
            "oldestTs",  oldest,
            "newestTs",  newest,
            "nextId",    this.nextId)
    }

    getStatsInfo() {
        local s := this.getStats()
        return ["Clip image: " s["count"] "/" s["maxCount"] " görsel, "
              . singleClipImageStore.fmtSize(s["liveBytes"]) " veri, ring %"
              . Round(s["ringUsed"] * 100 / s["ringMax"]) " ("
              . singleClipImageStore.fmtSize(s["ringUsed"]) "/"
              . singleClipImageStore.fmtSize(s["ringMax"]) ")"]
    }

    getRev() => this.rev

    static fmtSize(bytes) {
        if (bytes >= 1073741824)
            return Round(bytes / 1073741824, 2) " GB"
        if (bytes >= 1048576)
            return Round(bytes / 1048576, 1) " MB"
        if (bytes >= 1024)
            return Round(bytes / 1024, 1) " KB"
        return bytes " B"
    }

    _sortByTsDesc(arr) {
        ; Ekleme sıralaması — n <= 500, karşılaştırma ucuz
        Loop arr.Length {
            local i := A_Index, j := i - 1
            local cur := arr[i]
            while (j >= 1 && arr[j]["ts"] < cur["ts"]) {
                arr[j + 1] := arr[j]
                j -= 1
            }
            arr[j + 1] := cur
        }
        return arr
    }

    _nowMs() {
        return DateDiff(A_Now, "19700101000000", "S") * 1000 + A_MSec
    }

    _closeFiles() {
        if (this.idxFile)
            this.idxFile.Close(), this.idxFile := 0
        if (this.datFile)
            this.datFile.Close(), this.datFile := 0
    }

    __Delete() {
        this._closeFiles()
        GdipMini.shutdown()
    }
}
