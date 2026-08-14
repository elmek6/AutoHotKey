; ═══════════════════════════════════════════════════════════
; GdipMini — Görsel dönüşümleri için minimal GDI+ sarmalayıcı.
;
; Sadece clip_image_store'un ihtiyacı olan 4 işi yapar:
;   CF_DIB  → PNG byte'ları   (yakalama)
;   PNG     → HBITMAP         (dialog önizleme)
;   PNG     → CF_DIB byte'ları(panoya geri koyma)
;   herhangi→ 64x64 ham thumb (dialog listesi)
;
; Kodlama/çözme DOSYAYA DEĞİL BELLEĞE yapılır (IStream over HGLOBAL);
; blob'lar clipimg.dat içine gömüleceği için ara dosya istemiyoruz.
;
; Ömür yönetimi: her fonksiyon kendi ürettiği ara nesneleri (pBitmap,
; pStream, hGlobal) kendi temizler. Çağırana DÖNEN kaynaklar:
;   pngToHbitmap → HBITMAP  : çağıran DeleteObject etmeli
;   Buffer dönenler         : AHK GC halleder
; ═══════════════════════════════════════════════════════════
class GdipMini {
    static token := 0
    static clsidPng := ""

    ; PixelFormat32bppARGB — alfa korunur (şeffaf kopyalarda siyah kutu olmasın)
    static PXF_32ARGB := 0x0026200A
    static THUMB_SIZE := 64
    static THUMB_BYTES := 64 * 64 * 4   ; 16384 — clipimg.idx slot'undaki sabit alan

    ; ── Ömür ─────────────────────────────────────────────────────────────────

    static startup() {
        if (GdipMini.token)
            return true
        try {
            if (!DllCall("GetModuleHandle", "Str", "gdiplus", "Ptr"))
                DllCall("LoadLibrary", "Str", "gdiplus", "Ptr")
            local si := Buffer(24, 0)
            NumPut("UInt", 1, si, 0)   ; GdiplusVersion
            local status := DllCall("gdiplus\GdiplusStartup", "Ptr*", &token := 0, "Ptr", si, "Ptr", 0, "UInt")
            if (status != 0)
                throw Error("GdiplusStartup başarısız, status=" status)
            GdipMini.token := token
            GdipMini.clsidPng := GdipMini._clsid("{557CF406-1A04-11D3-9A73-0000F81EF32E}")
            return true
        } catch as err {
            App.ErrHandler.handleError("GdipMini.startup: " err.Message, err)
            return false
        }
    }

    static shutdown() {
        if (!GdipMini.token)
            return
        DllCall("gdiplus\GdiplusShutdown", "Ptr", GdipMini.token)
        GdipMini.token := 0
    }

    ; ── Genel API ────────────────────────────────────────────────────────────

    ; CF_DIB bellek bloğu → PNG byte'ları (Buffer) | başarısızsa 0
    static dibToPng(pDib, dibSize) {
        local pBitmap := 0
        try {
            pBitmap := GdipMini._bitmapFromDib(pDib, dibSize)
            return GdipMini._bitmapToPng(pBitmap)
        } catch as err {
            App.ErrHandler.handleError("GdipMini.dibToPng: " err.Message, err)
            return 0
        } finally {
            if (pBitmap)
                DllCall("gdiplus\GdipDisposeImage", "Ptr", pBitmap)
        }
    }

    ; PNG byte'ları → HBITMAP | başarısızsa 0.  ÇAĞIRAN DeleteObject ETMELİ.
    static pngToHbitmap(pngBuf, pngSize := 0) {
        local pBitmap := 0
        try {
            pBitmap := GdipMini._bitmapFromPng(pngBuf, pngSize ? pngSize : pngBuf.Size)
            local hbm := 0
            ; Arka plan rengi 0 (şeffaf) — Gui Picture kontrolünde doğal görünür
            DllCall("gdiplus\GdipCreateHBITMAPFromBitmap", "Ptr", pBitmap, "Ptr*", &hbm, "UInt", 0)
            return hbm
        } catch as err {
            App.ErrHandler.handleError("GdipMini.pngToHbitmap: " err.Message, err)
            return 0
        } finally {
            if (pBitmap)
                DllCall("gdiplus\GdipDisposeImage", "Ptr", pBitmap)
        }
    }

    ; PNG byte'ları → verilen kutuya SIĞDIRILMIŞ HBITMAP (oran korunur).
    ; Görsel kutudan küçükse büyütülmez. ÇAĞIRAN DeleteObject ETMELİ.
    static pngToHbitmapFit(pngBuf, pngSize, maxW, maxH) {
        local pBitmap := 0, pFit := 0
        try {
            pBitmap := GdipMini._bitmapFromPng(pngBuf, pngSize ? pngSize : pngBuf.Size)
            local w := 0, h := 0
            DllCall("gdiplus\GdipGetImageWidth", "Ptr", pBitmap, "UInt*", &w)
            DllCall("gdiplus\GdipGetImageHeight", "Ptr", pBitmap, "UInt*", &h)
            local scale := Min(maxW / w, maxH / h, 1.0)
            local hbm := 0
            if (scale >= 1.0) {
                DllCall("gdiplus\GdipCreateHBITMAPFromBitmap", "Ptr", pBitmap, "Ptr*", &hbm, "UInt", 0xFFFFFFFF)
                return hbm
            }
            pFit := GdipMini._scaleBitmap(pBitmap, Max(1, Round(w * scale)), Max(1, Round(h * scale)))
            DllCall("gdiplus\GdipCreateHBITMAPFromBitmap", "Ptr", pFit, "Ptr*", &hbm, "UInt", 0xFFFFFFFF)
            return hbm
        } catch as err {
            App.ErrHandler.handleError("GdipMini.pngToHbitmapFit: " err.Message, err)
            return 0
        } finally {
            if (pFit)
                DllCall("gdiplus\GdipDisposeImage", "Ptr", pFit)
            if (pBitmap)
                DllCall("gdiplus\GdipDisposeImage", "Ptr", pBitmap)
        }
    }

    ; ── Zoom/pan için görüntü alanı (viewport) çizimi ────────────────────────
    ; PNG'yi her tekerlek adımında yeniden çözmek pahalı; bir kez pBitmap'e çözüp
    ; onu saklıyoruz, her karede sadece renderView çağrılıyor.

    ; PNG → pBitmap. ÇAĞIRAN releaseBitmap ETMELİ. Başarısızsa 0.
    static bitmapFromPng(pngBuf, pngSize := 0) {
        try {
            return GdipMini._bitmapFromPng(pngBuf, pngSize ? pngSize : pngBuf.Size)
        } catch as err {
            App.ErrHandler.handleError("GdipMini.bitmapFromPng: " err.Message, err)
            return 0
        }
    }

    static releaseBitmap(pBitmap) {
        if (pBitmap)
            DllCall("gdiplus\GdipDisposeImage", "Ptr", pBitmap)
    }

    static imageSize(pBitmap, &w, &h) {
        w := 0, h := 0
        DllCall("gdiplus\GdipGetImageWidth", "Ptr", pBitmap, "UInt*", &w)
        DllCall("gdiplus\GdipGetImageHeight", "Ptr", pBitmap, "UInt*", &h)
    }

    ; viewW x viewH boyutunda bir kare üretir; görsel (dstX,dstY,dstW,dstH)
    ; dikdörtgenine çizilir. Dikdörtgen kutunun dışına taşabilir — GDI+ kırpar,
    ; pan/zoom bu sayede ek hesap istemez. Dönen HBITMAP kontrole verilir.
    static renderView(pBitmap, viewW, viewH, dstX, dstY, dstW, dstH, bgArgb := 0xFF1E1E1E) {
        local pView := 0, pGraphics := 0, hbm := 0
        try {
            local srcW := 0, srcH := 0
            GdipMini.imageSize(pBitmap, &srcW, &srcH)
            DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", viewW, "Int", viewH, "Int", 0,
                    "Int", GdipMini.PXF_32ARGB, "Ptr", 0, "Ptr*", &pView, "UInt")
            if (!pView)
                throw Error("renderView: hedef bitmap oluşturulamadı")
            DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", pView, "Ptr*", &pGraphics)
            if (!pGraphics)
                throw Error("renderView: graphics alınamadı")
            DllCall("gdiplus\GdipGraphicsClear", "Ptr", pGraphics, "UInt", bgArgb)
            ; 1:1 ve büyütmede NearestNeighbor daha dürüst (piksel bulanmasın),
            ; küçültmede bicubic daha temiz
            DllCall("gdiplus\GdipSetInterpolationMode", "Ptr", pGraphics, "Int", (dstW >= srcW) ? 5 : 7)
            DllCall("gdiplus\GdipSetPixelOffsetMode", "Ptr", pGraphics, "Int", 2)
            DllCall("gdiplus\GdipDrawImageRectRectI", "Ptr", pGraphics, "Ptr", pBitmap,
                    "Int", dstX, "Int", dstY, "Int", dstW, "Int", dstH,
                    "Int", 0, "Int", 0, "Int", srcW, "Int", srcH,
                    "Int", 2, "Ptr", 0, "Ptr", 0, "Ptr", 0)
            DllCall("gdiplus\GdipFlush", "Ptr", pGraphics, "Int", 1)
            DllCall("gdiplus\GdipCreateHBITMAPFromBitmap", "Ptr", pView, "Ptr*", &hbm, "UInt", bgArgb)
            return hbm
        } catch as err {
            App.ErrHandler.handleError("GdipMini.renderView: " err.Message, err)
            return 0
        } finally {
            if (pGraphics)
                DllCall("gdiplus\GdipDeleteGraphics", "Ptr", pGraphics)
            if (pView)
                DllCall("gdiplus\GdipDisposeImage", "Ptr", pView)
        }
    }

    ; PNG byte'ları → CF_DIB byte'ları (Buffer: BITMAPINFOHEADER + piksel).
    ; Panoya SetClipboardData(CF_DIB) için doğrudan kullanılabilir.
    static pngToDib(pngBuf, pngSize := 0) {
        local pBitmap := 0
        try {
            pBitmap := GdipMini._bitmapFromPng(pngBuf, pngSize ? pngSize : pngBuf.Size)
            local w := 0, h := 0
            DllCall("gdiplus\GdipGetImageWidth", "Ptr", pBitmap, "UInt*", &w)
            DllCall("gdiplus\GdipGetImageHeight", "Ptr", pBitmap, "UInt*", &h)

            ; 32bpp top-down DIB: stride hizalaması derdi yok (w*4 zaten 4'ün katı)
            local stride := w * 4
            local dib := Buffer(40 + stride * h, 0)
            NumPut("UInt", 40, dib, 0)          ; biSize
            NumPut("Int", w, dib, 4)            ; biWidth
            NumPut("Int", -h, dib, 8)           ; biHeight negatif = top-down
            NumPut("UShort", 1, dib, 12)        ; biPlanes
            NumPut("UShort", 32, dib, 14)       ; biBitCount
            NumPut("UInt", 0, dib, 16)          ; biCompression = BI_RGB
            NumPut("UInt", stride * h, dib, 20) ; biSizeImage

            GdipMini._copyPixels(pBitmap, w, h, dib.Ptr + 40, stride)
            return dib
        } catch as err {
            App.ErrHandler.handleError("GdipMini.pngToDib: " err.Message, err)
            return 0
        } finally {
            if (pBitmap)
                DllCall("gdiplus\GdipDisposeImage", "Ptr", pBitmap)
        }
    }

    ; CF_DIB → 64x64 ham BGRA thumb (Buffer, tam olarak THUMB_BYTES).
    ; Oran korunur, artan alan şeffaf kalır. clipimg.idx slot'una olduğu gibi yazılır.
    static dibToThumb(pDib, dibSize) {
        local pBitmap := 0
        try {
            pBitmap := GdipMini._bitmapFromDib(pDib, dibSize)
            return GdipMini._bitmapToThumb(pBitmap)
        } catch as err {
            App.ErrHandler.handleError("GdipMini.dibToThumb: " err.Message, err)
            return 0
        } finally {
            if (pBitmap)
                DllCall("gdiplus\GdipDisposeImage", "Ptr", pBitmap)
        }
    }

    ; 64x64 ham BGRA thumb → HBITMAP (dialog ImageList'i için).
    ; ÇAĞIRAN DeleteObject ETMELİ.
    static thumbToHbitmap(thumbBuf) {
        local size := GdipMini.THUMB_SIZE
        local bi := Buffer(40, 0)
        NumPut("UInt", 40, bi, 0)
        NumPut("Int", size, bi, 4)
        NumPut("Int", -size, bi, 8)      ; top-down
        NumPut("UShort", 1, bi, 12)
        NumPut("UShort", 32, bi, 14)
        NumPut("UInt", 0, bi, 16)
        local ppvBits := 0
        local hbm := DllCall("gdi32\CreateDIBSection", "Ptr", 0, "Ptr", bi, "UInt", 0,
                             "Ptr*", &ppvBits, "Ptr", 0, "UInt", 0, "Ptr")
        if (!hbm)
            return 0
        DllCall("RtlMoveMemory", "Ptr", ppvBits, "Ptr", thumbBuf, "Ptr", GdipMini.THUMB_BYTES)
        return hbm
    }

    ; Ham DIB pikselleri üzerinden CRC32 — dedupe anahtarı.
    ; PNG byte'ları DETERMİNİSTİK DEĞİL (encoder sürümü değişebilir), o yüzden
    ; hash her zaman sıkıştırılmamış veri üzerinden alınır.
    static crc32(ptr, size, seed := 0) {
        return DllCall("ntdll\RtlComputeCrc32", "UInt", seed, "Ptr", ptr, "UInt", size, "UInt")
    }

    ; ── İç yardımcılar ───────────────────────────────────────────────────────

    ; CF_DIB = BITMAPINFO + piksel verisi. GdipCreateBitmapFromGdiDib tam da bunu
    ; bekler; ikisini ayıran tek şey piksellerin nerede başladığı.
    static _bitmapFromDib(pDib, dibSize) {
        local offset := GdipMini._dibPixelOffset(pDib)
        if (offset >= dibSize)
            throw Error("Geçersiz DIB: piksel offset (" offset ") boyutu (" dibSize ") aşıyor")
        local pBitmap := 0
        local status := DllCall("gdiplus\GdipCreateBitmapFromGdiDib", "Ptr", pDib,
                                "Ptr", pDib + offset, "Ptr*", &pBitmap, "UInt")
        if (status != 0 || !pBitmap)
            throw Error("GdipCreateBitmapFromGdiDib başarısız, status=" status)
        return pBitmap
    }

    ; BITMAPINFOHEADER sonrası piksellerin başladığı offset.
    ; Üç tuzak: BI_BITFIELDS'in 3 DWORD maskesi, palet (<=8bpp), biClrUsed.
    static _dibPixelOffset(pDib) {
        local biSize := NumGet(pDib, 0, "UInt")
        local bitCount := NumGet(pDib, 14, "UShort")
        local compression := NumGet(pDib, 16, "UInt")
        local clrUsed := NumGet(pDib, 32, "UInt")
        local offset := biSize
        ; BI_BITFIELDS(3) yalnız 40 baytlık header'da maskeleri DIŞARIDA taşır;
        ; V4(108)/V5(124) header'ında maskeler zaten header'ın içinde.
        if (compression == 3 && biSize == 40)
            offset += 12
        if (bitCount <= 8)
            offset += (clrUsed ? clrUsed : (1 << bitCount)) * 4
        else if (clrUsed)
            offset += clrUsed * 4
        return offset
    }

    static _bitmapFromPng(pngBuf, pngSize) {
        local hg := DllCall("GlobalAlloc", "UInt", 0x2, "Ptr", pngSize, "Ptr")  ; GMEM_MOVEABLE
        if (!hg)
            throw Error("GlobalAlloc başarısız (" pngSize " bayt)")
        local dst := DllCall("GlobalLock", "Ptr", hg, "Ptr")
        DllCall("RtlMoveMemory", "Ptr", dst, "Ptr", pngBuf, "Ptr", pngSize)
        DllCall("GlobalUnlock", "Ptr", hg)

        local pStream := 0
        ; fDeleteOnRelease=true → stream release edilince hGlobal da serbest kalır
        if (DllCall("ole32\CreateStreamOnHGlobal", "Ptr", hg, "Int", true, "Ptr*", &pStream, "UInt") != 0) {
            DllCall("GlobalFree", "Ptr", hg)
            throw Error("CreateStreamOnHGlobal başarısız")
        }
        try {
            local pBitmap := 0
            local status := DllCall("gdiplus\GdipCreateBitmapFromStream", "Ptr", pStream, "Ptr*", &pBitmap, "UInt")
            if (status != 0 || !pBitmap)
                throw Error("GdipCreateBitmapFromStream başarısız, status=" status)
            return pBitmap
        } finally {
            ObjRelease(pStream)
        }
    }

    static _bitmapToPng(pBitmap) {
        local pStream := 0
        if (DllCall("ole32\CreateStreamOnHGlobal", "Ptr", 0, "Int", true, "Ptr*", &pStream, "UInt") != 0)
            throw Error("CreateStreamOnHGlobal başarısız")
        try {
            local status := DllCall("gdiplus\GdipSaveImageToStream", "Ptr", pBitmap, "Ptr", pStream,
                                    "Ptr", GdipMini.clsidPng, "Ptr", 0, "UInt")
            if (status != 0)
                throw Error("GdipSaveImageToStream başarısız, status=" status)

            local hg := 0
            DllCall("ole32\GetHGlobalFromStream", "Ptr", pStream, "Ptr*", &hg, "UInt")
            local size := DllCall("GlobalSize", "Ptr", hg, "UPtr")
            if (size == 0)
                throw Error("PNG kodlaması boş sonuç verdi")
            local src := DllCall("GlobalLock", "Ptr", hg, "Ptr")
            local out := Buffer(size)
            DllCall("RtlMoveMemory", "Ptr", out, "Ptr", src, "Ptr", size)
            DllCall("GlobalUnlock", "Ptr", hg)
            return out
        } finally {
            ObjRelease(pStream)   ; fDeleteOnRelease → hGlobal da burada serbest kalır
        }
    }

    ; Hedef pikselleri DOĞRUDAN bizim buffer'ımıza çizdiriyoruz (scan0 = buf.Ptr),
    ; böylece LockBits/UnlockBits kopyalama turuna gerek kalmıyor.
    static _bitmapToThumb(pBitmap) {
        local size := GdipMini.THUMB_SIZE
        local srcW := 0, srcH := 0
        DllCall("gdiplus\GdipGetImageWidth", "Ptr", pBitmap, "UInt*", &srcW)
        DllCall("gdiplus\GdipGetImageHeight", "Ptr", pBitmap, "UInt*", &srcH)
        if (srcW == 0 || srcH == 0)
            throw Error("Kaynak görsel boyutu sıfır")

        ; Oranı koru, kutuya sığdır, ortala
        local scale := Min(size / srcW, size / srcH)
        local dstW := Max(1, Round(srcW * scale))
        local dstH := Max(1, Round(srcH * scale))
        local dstX := (size - dstW) // 2
        local dstY := (size - dstH) // 2

        local out := Buffer(GdipMini.THUMB_BYTES, 0)
        local pThumb := 0, pGraphics := 0
        DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", size, "Int", size, "Int", size * 4,
                "Int", GdipMini.PXF_32ARGB, "Ptr", out, "Ptr*", &pThumb, "UInt")
        if (!pThumb)
            throw Error("GdipCreateBitmapFromScan0 başarısız")
        try {
            DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", pThumb, "Ptr*", &pGraphics)
            if (!pGraphics)
                throw Error("GdipGetImageGraphicsContext başarısız")
            DllCall("gdiplus\GdipGraphicsClear", "Ptr", pGraphics, "UInt", 0x00000000)
            DllCall("gdiplus\GdipSetInterpolationMode", "Ptr", pGraphics, "Int", 7)  ; HighQualityBicubic
            DllCall("gdiplus\GdipSetPixelOffsetMode", "Ptr", pGraphics, "Int", 2)    ; Half — kenar kırpılmasını önler
            DllCall("gdiplus\GdipDrawImageRectRectI", "Ptr", pGraphics, "Ptr", pBitmap,
                    "Int", dstX, "Int", dstY, "Int", dstW, "Int", dstH,
                    "Int", 0, "Int", 0, "Int", srcW, "Int", srcH,
                    "Int", 2, "Ptr", 0, "Ptr", 0, "Ptr", 0)   ; UnitPixel
            DllCall("gdiplus\GdipFlush", "Ptr", pGraphics, "Int", 1)  ; FlushIntentionSync
            return out
        } finally {
            if (pGraphics)
                DllCall("gdiplus\GdipDeleteGraphics", "Ptr", pGraphics)
            ; scan0 bizim buffer'ımız; bitmap'i bırakmak pikselleri etkilemez
            DllCall("gdiplus\GdipDisposeImage", "Ptr", pThumb)
        }
    }

    ; Yeni boyutta bir pBitmap üretir. ÇAĞIRAN GdipDisposeImage ETMELİ.
    static _scaleBitmap(pBitmap, dstW, dstH) {
        local srcW := 0, srcH := 0
        DllCall("gdiplus\GdipGetImageWidth", "Ptr", pBitmap, "UInt*", &srcW)
        DllCall("gdiplus\GdipGetImageHeight", "Ptr", pBitmap, "UInt*", &srcH)
        local pOut := 0, pGraphics := 0
        DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", dstW, "Int", dstH, "Int", 0,
                "Int", GdipMini.PXF_32ARGB, "Ptr", 0, "Ptr*", &pOut, "UInt")
        if (!pOut)
            throw Error("GdipCreateBitmapFromScan0 (scale) başarısız")
        try {
            DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", pOut, "Ptr*", &pGraphics)
            if (!pGraphics)
                throw Error("GdipGetImageGraphicsContext (scale) başarısız")
            DllCall("gdiplus\GdipSetInterpolationMode", "Ptr", pGraphics, "Int", 7)
            DllCall("gdiplus\GdipSetPixelOffsetMode", "Ptr", pGraphics, "Int", 2)
            DllCall("gdiplus\GdipDrawImageRectRectI", "Ptr", pGraphics, "Ptr", pBitmap,
                    "Int", 0, "Int", 0, "Int", dstW, "Int", dstH,
                    "Int", 0, "Int", 0, "Int", srcW, "Int", srcH,
                    "Int", 2, "Ptr", 0, "Ptr", 0, "Ptr", 0)
            DllCall("gdiplus\GdipFlush", "Ptr", pGraphics, "Int", 1)
            return pOut
        } catch as err {
            DllCall("gdiplus\GdipDisposeImage", "Ptr", pOut)
            throw err
        } finally {
            if (pGraphics)
                DllCall("gdiplus\GdipDeleteGraphics", "Ptr", pGraphics)
        }
    }

    ; pBitmap piksellerini hedef belleğe 32bpp olarak kopyalar (LockBits).
    static _copyPixels(pBitmap, w, h, destPtr, destStride) {
        local rect := Buffer(16, 0)
        NumPut("Int", 0, rect, 0), NumPut("Int", 0, rect, 4)
        NumPut("Int", w, rect, 8), NumPut("Int", h, rect, 12)
        local bmpData := Buffer(32, 0)
        ; ImageLockModeRead=1, ImageLockModeUserInputBuffer=4 → GDI+ doğrudan
        ; bizim tamponumuza yazsın diye stride/scan0'ı önceden dolduruyoruz
        NumPut("UInt", w, bmpData, 0)
        NumPut("UInt", h, bmpData, 4)
        NumPut("Int", destStride, bmpData, 8)
        NumPut("Int", GdipMini.PXF_32ARGB, bmpData, 12)
        NumPut("Ptr", destPtr, bmpData, 16)
        local status := DllCall("gdiplus\GdipBitmapLockBits", "Ptr", pBitmap, "Ptr", rect,
                                "UInt", 1 | 4, "Int", GdipMini.PXF_32ARGB, "Ptr", bmpData, "UInt")
        if (status != 0)
            throw Error("GdipBitmapLockBits başarısız, status=" status)
        DllCall("gdiplus\GdipBitmapUnlockBits", "Ptr", pBitmap, "Ptr", bmpData)
    }

    static _clsid(guidStr) {
        local clsid := Buffer(16, 0)
        if (DllCall("ole32\CLSIDFromString", "WStr", guidStr, "Ptr", clsid, "UInt") != 0)
            throw Error("CLSIDFromString başarısız: " guidStr)
        return clsid
    }
}
