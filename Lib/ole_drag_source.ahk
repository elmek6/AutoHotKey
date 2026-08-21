; ═══════════════════════════════════════════════════════════
; OleDragSource — GUI'den DIŞARI gerçek OLE sürükle-bırak kaynağı.
;
; Notepad'de metni seçip başka bir pencereye sürüklemekle AYNI mekanizma:
; ole32!DoDragDrop(IDataObject, IDropSource, ...). Hedef uygulama caret'i,
; sürükleme imlecini ve "buraya bırakılabilir mi" kararını kendi verir —
; bizim koordinat hesabı yapmamız ya da hedefe tıklayıp ^v basmamız gerekmez.
;
; İki COM arayüzü gerekiyor, ama sadece BİRİNİ elle yazıyoruz:
;   IDataObject  → OleGetClipboard() sistemin hazır nesnesini veriyor.
;                  (Bedeli: metin önce panoya konur. memclip zaten öyle çalışıyor.)
;   IDropSource  → elle kurulan 5 slotluk vtable. Gerçek iş yapan iki metot:
;                  QueryContinueDrag (sol tuş bırakıldı mı / Esc'e basıldı mı)
;                  GiveFeedback      (imleçleri Windows çizsin)
;
; Ömür: vtable, nesne ve callback'ler statik tutulur (script boyunca yaşar),
; bu yüzden AddRef/Release sabit 1 döndürür — gerçek sayaca ihtiyaç yok.
;
; ── Notlar (geliştirirken kaybedilen zamanlar) ───────────────────────────────
; • DRAGDROP_S_USEDEFAULTCURSORS = 0x00040102. Yanlışlıkla 0x00040100 yazarsan
;   DRAGDROP_S_DROP ile aynı değer olur; GiveFeedback "bırakmayı tamamla" demiş
;   olur ve DoDragDrop daha ilk turda, 0 ms'de biter. Belirti: hiçbir şey olmaz,
;   imleç bile değişmez.
; • Windows sürümü fark etmiyor. Bu API Win10 ve Win11'de aynı; sürüm farkı diye
;   araştırılan grfKeyState=0 raporları IE11'in ActiveX barındırmasına özgüymüş,
;   buradaki koda uymuyor (ölçtük: grfKeyState doğru geliyor). Kod Win10'da test
;   edildi, Win11'de ayrı bir iş gerektirmez.
; • Sürükleme sırasında ekrana ToolTip basma — takibi bozuyor. Teşhis gerekirse
;   dosyaya yaz.
; ═══════════════════════════════════════════════════════════
class OleDragSource {
    static DROPEFFECT_NONE := 0
    static DROPEFFECT_COPY := 1

    ; Bunlar HRESULT ama "hata" değil — DoDragDrop'un normal çıkış kodları
    static S_OK              := 0
    static DRAGDROP_S_DROP   := 0x00040100
    static DRAGDROP_S_CANCEL := 0x00040101
    static DRAGDROP_S_USEDEFAULTCURSORS := 0x00040102   ; 0x40100 DEĞİL — başlıktaki nota bak
    static E_NOINTERFACE     := 0x80004002
    static E_POINTER         := 0x80004003

    static MK_LBUTTON := 0x0001
    static MK_RBUTTON := 0x0002

    static _obj := 0          ; IDropSource örneği (Buffer: [vtable ptr])
    static _vtbl := 0         ; Buffer: 5 metot pointer'ı
    static _cb := []          ; CallbackCreate handle'ları — GC almasın diye tutuluyor
    static _iidUnknown := 0
    static _iidDropSource := 0
    static _ready := false
    static busy := false      ; DoDragDrop bloklarken tekrar girişi engeller

    ; ── Kurulum ──────────────────────────────────────────────────────────────

    ; Tek sefer çalışır (_ready). Ürettiği hiçbir şey serbest bırakılmaz ve
    ; bırakılmamalı: 5 callback + 3 Buffer script ömrü boyunca yaşar, OLE her
    ; sürüklemede aynı nesneyi kullanır. Sabit maliyet, sızıntı değil.
    static _init() {
        if (OleDragSource._ready)
            return true

        ; OleInitialize STA ister. AHK ana thread'i zaten STA; S_FALSE (zaten
        ; başlatılmış) de kabul. Uninitialize etmiyoruz — script boyunca açık.
        local hr := DllCall("ole32\OleInitialize", "Ptr", 0, "Int")
        if (hr < 0)
            throw Error("OleInitialize başarısız, hr=" Format("0x{:08X}", hr))

        OleDragSource._iidUnknown    := OleDragSource._guid("{00000000-0000-0000-C000-000000000046}")
        OleDragSource._iidDropSource := OleDragSource._guid("{00000121-0000-0000-C000-000000000046}")

        ; ObjBindMethod: statik metodu düz property gibi almak `this`'i belirsiz
        ; bırakıyor (parametre sayısı 1 kayar). Açıkça bağla.
        OleDragSource._cb := [
            CallbackCreate(ObjBindMethod(OleDragSource, "_QueryInterface"),    "F", 3),
            CallbackCreate(ObjBindMethod(OleDragSource, "_AddRef"),            "F", 1),
            CallbackCreate(ObjBindMethod(OleDragSource, "_Release"),           "F", 1),
            CallbackCreate(ObjBindMethod(OleDragSource, "_QueryContinueDrag"), "F", 3),
            CallbackCreate(ObjBindMethod(OleDragSource, "_GiveFeedback"),      "F", 2)
        ]

        OleDragSource._vtbl := Buffer(A_PtrSize * 5, 0)
        for i, cb in OleDragSource._cb
            NumPut("Ptr", cb, OleDragSource._vtbl, (i - 1) * A_PtrSize)

        ; COM nesnesi = ilk alanı vtable'ı gösteren bir bellek bloğu
        OleDragSource._obj := Buffer(A_PtrSize, 0)
        NumPut("Ptr", OleDragSource._vtbl.Ptr, OleDragSource._obj, 0)

        OleDragSource._ready := true
        return true
    }

    static _guid(str) {
        local buf := Buffer(16, 0)
        if (DllCall("ole32\CLSIDFromString", "WStr", str, "Ptr", buf, "UInt") != 0)
            throw Error("CLSIDFromString başarısız: " str)
        return buf
    }

    ; ── IDropSource (fast-mode callback'ler: gövdeler minik, yield etmiyor) ───

    static _QueryInterface(pThis, riid, ppv) {
        if (!ppv)
            return OleDragSource.E_POINTER
        ; IDropSourceNotify gibi bilmediğimiz arayüzlere körü körüne S_OK dönmek
        ; tehlikeli: çağıran 3./4. slotu bambaşka anlamda çağırır. IID'yi karşılaştır.
        if (OleDragSource._iidEq(riid, OleDragSource._iidUnknown)
            || OleDragSource._iidEq(riid, OleDragSource._iidDropSource)) {
            NumPut("Ptr", OleDragSource._obj.Ptr, ppv, 0)
            return OleDragSource.S_OK
        }
        NumPut("Ptr", 0, ppv, 0)
        return OleDragSource.E_NOINTERFACE
    }

    static _iidEq(a, b) {
        return NumGet(a, 0, "Int64") == NumGet(b, 0, "Int64")
            && NumGet(a, 8, "Int64") == NumGet(b, 8, "Int64")
    }

    ; Nesne statik, sayaç tutmuyoruz — sabit 1
    static _AddRef(pThis) => 1
    static _Release(pThis) => 1

    static _QueryContinueDrag(pThis, fEscapePressed, grfKeyState) {
        if (fEscapePressed || (grfKeyState & OleDragSource.MK_RBUTTON))
            return OleDragSource.DRAGDROP_S_CANCEL
        if (!(grfKeyState & OleDragSource.MK_LBUTTON))
            return OleDragSource.DRAGDROP_S_DROP    ; sol tuş bırakıldı → bırak
        return OleDragSource.S_OK                   ; hâlâ sürükleniyor
    }

    static _GiveFeedback(pThis, dwEffect) {
        return OleDragSource.DRAGDROP_S_USEDEFAULTCURSORS
    }

    ; ── Genel API ────────────────────────────────────────────────────────────

    ; Metni sürüklemeye başlat. Fare zaten BASILI olmalı (LVN_BEGINDRAG içinden
    ; çağrılır); bırakılana kadar bloklar. Bırakıldıysa true döner.
    ; onBefore: A_Clipboard'a yazmadan hemen önce çalışacak callback — memclip'in
    ; kendi pano watcher'ını susturması için.
    static dragText(text, onBefore := "") {
        if (text == "" || OleDragSource.busy)
            return false

        try {
            OleDragSource._init()
        } catch as err {
            App.ErrHandler.handleError("OLE sürükleme kurulamadı", err)
            return false
        }

        if (onBefore)
            onBefore.Call()
        A_Clipboard := text
        if (!ClipWait(0.5))
            return false

        ; Panonun içeriği için sistemin ürettiği IDataObject — CF_UNICODETEXT
        ; dahil tüm formatları hedefe sunar, elle IDataObject yazmaya gerek yok.
        local pData := 0
        if (DllCall("ole32\OleGetClipboard", "Ptr*", &pData, "UInt") != 0 || !pData)
            return false

        OleDragSource.busy := true
        local effect := 0, hr := 0
        try {
            hr := DllCall("ole32\DoDragDrop"
                , "Ptr",   pData
                , "Ptr",   OleDragSource._obj.Ptr
                , "UInt",  OleDragSource.DROPEFFECT_COPY   ; sadece KOPYALA — hedef
                , "UInt*", &effect                         ; kaynağı silmeye kalkmasın
                , "UInt")
        } finally {
            ObjRelease(pData)              ; tek sahibi biziz, burada ölmeli
            OleDragSource.busy := false
        }

        return (hr == OleDragSource.DRAGDROP_S_DROP && effect != OleDragSource.DROPEFFECT_NONE)
    }

    ; Bir ListView'ı sürükleme kaynağı yap.
    ;   lv       : GuiControl (ListView)
    ;   getText  : (row) => sürüklenecek metin ("" ise sürükleme başlamaz)
    ;   onBefore : opsiyonel, panoya yazmadan önce çağrılır
    static attachListView(lv, getText, onBefore := "") {
        ; LVN_BEGINDRAG (-109): ListView'ın "sol tuşla sürükleme başladı" bildirimi.
        ; AHK v2'de hazır bir event'i yok, OnNotify ile yakalanıyor.
        lv.OnNotify(-109, (ctrl, lParam) => OleDragSource._onBeginDrag(lParam, getText, onBefore))
    }

    static _onBeginDrag(lParam, getText, onBefore) {
        ; NMLISTVIEW.iItem — NMHDR'dan hemen sonra (x64'te 24, x86'da 12 bayt)
        local row := NumGet(lParam, A_PtrSize * 3, "Int") + 1
        if (row < 1)
            return

        local text := ""
        try {
            text := getText.Call(row)
        } catch as err {
            App.ErrHandler.handleError("Sürüklenecek içerik alınamadı", err)
            return
        }
        if (text == "")
            return

        OleDragSource.dragText(text, onBefore)
    }
}
