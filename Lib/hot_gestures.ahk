/************************************************************************
 * @description Eksen kilitli mouse slider sistemi - 8-way direction detection
 * @author Benim Assistan
 * @date 2026/01/23
 * @version 3.2
 ***********************************************************************/

class HotGestures {
    static DIRECTION_THRESHOLD := 10    ; İlk 10 pixel'de yön belirleme
    static STEP_SIZE := 10              ; Her 10 pixel'de bir callback tetikle
    static MAX_DRAW_LENGTH := 2000      ; Maksimum çizim uzunluğu (güvenlik)

    ; Binary direction flags (public API)
    static bDir := {
        none: 0,
        once: 1,        ; Bir kere tetikle
        up: 2,
        down: 4,
        left: 8,
        right: 16,
        upDown: 2 | 4,      ; 6
        leftRight: 8 | 16,  ; 24
        upRight: 32,
        upLeft: 64,
        downRight: 128,
        downLeft: 256
    }

    ; Internal direction types (8-way detection result)
    static __dirType := {
        none: 0,
        strictUp: 1,
        strictDown: 2,
        strictLeft: 3,
        strictRight: 4,
        upRight: 5,
        upLeft: 6,
        downRight: 7,
        downLeft: 8
    }

    __mouseHook := ""
    __drawingBoard := ""

    __originX := 0
    __originY := 0
    __lastStep := 0
    __directionLocked := false
    __lockedDirection := 0      ; __dirType enum value
    __registrations := []
    __activeGestures := []      ; Direction belirlenince sadece uygun olanlar
    __onceTriggered := Map()    ; Once flag'li gesture'lar için
    __gestureFired := false     ; Gesture tetiklendi mi?
    __totalDrawLength := 0      ; Toplam çizim uzunluğu (güvenlik)

    __New(penColor := 0x00FF88) {
        this.__penColor := penColor
    }

    Register(direction, callback) {
        ; Basitleştirilmiş çakışma kontrolü: Aynı direction sadece bir kere kayıt edilebilir
        cleanDir := direction & ~HotGestures.bDir.once

        for reg in this.__registrations {
            existingDir := reg.direction & ~HotGestures.bDir.once
            if (existingDir == cleanDir) {
                throw Error("Duplicate gesture: Direction '" direction "' already registered!")
            }
        }

        this.__registrations.Push({ direction: direction, callback: callback })
    }

    Clear() {
        this.__registrations := []
    }

    WasGestureFired() => this.__gestureFired

    Start(keyName) {
        if (this.__registrations.Length == 0)
            return

        keyName := RegExReplace(keyName, "[\$\*\~\!\^\+]")

        CoordMode("Mouse", "Screen")
        MouseGetPos(&x, &y)
        this.__originX := x
        this.__originY := y
        this.__lastStep := 0
        this.__directionLocked := false
        this.__lockedDirection := HotGestures.__dirType.none
        this.__activeGestures := []
        this.__onceTriggered := Map()
        this.__gestureFired := false
        this.__totalDrawLength := 0  ; Çizim sayacını sıfırla

        ; Drawing board oluştur
        this.__drawingBoard := HotGestures.DrawingBoard(this.__penColor)
        this.__drawingBoard.MoveTo(x, y)
        this.__drawingBoard.Show()

        ; Mouse hook başlat
        this.__mouseHook := HotGestures.MouseHook(this.__OnMouseMove.Bind(this))

        ; Tuş bırakılana kadar bekle
        KeyWait(keyName)
        this.Stop()
    }

    Stop() {
        ; Tuş bırakıldığında once ile işaretlenmiş gesture'ları çalıştır
        for objPtr, callback in this.__onceTriggered {
            callback.Call(1)
            this.__gestureFired := true
        }

        this.__mouseHook := ""
        if (this.__drawingBoard) {
            this.__drawingBoard.Hide()
            this.__drawingBoard := ""
        }
    }

    __OnMouseMove(x, y) {
        ; Başlangıç noktasından fark
        dx := x - this.__originX
        dy := this.__originY - y  ; Y ekseni ters (yukarı pozitif)

        ; Direction kilidi yoksa, ilk 10 pixel'de yönü belirle
        if (!this.__directionLocked) {
            absDx := Abs(dx)
            absDy := Abs(dy)

            if (absDx > HotGestures.DIRECTION_THRESHOLD || absDy > HotGestures.DIRECTION_THRESHOLD) {
                ; 8-way direction detection
                this.__lockedDirection := this.__Detect8WayDirection(dx, dy, absDx, absDy)
                this.__directionLocked := true

                ; Sadece bu direction'a uygun gesture'ları filtrele
                this.__FilterGesturesByDirection()

                if (this.__activeGestures.Length == 0) {
                    ; Uygun gesture yok, çık
                    return
                }
            }
            return
        }

        ; Hangi eksende ilerliyoruz?
        value := 0
        switch this.__lockedDirection {
            case HotGestures.__dirType.strictUp, HotGestures.__dirType.strictDown:
                value := dy
            case HotGestures.__dirType.strictLeft, HotGestures.__dirType.strictRight:
                value := dx
            case HotGestures.__dirType.upRight:
                value := (dx + dy) // 2  ; Diagonal ortalama
            case HotGestures.__dirType.upLeft:
                value := (-dx + dy) // 2
            case HotGestures.__dirType.downRight:
                value := (dx - dy) // 2
            case HotGestures.__dirType.downLeft:
                value := (-dx - dy) // 2
        }

        ; Kaç adım (step) geçildi?
        currentStep := value // HotGestures.STEP_SIZE

        ; Adım değişmediyse işlem yapma
        if (currentStep == this.__lastStep)
            return

        ; Bu tick'teki değişim miktarı
        diff := currentStep - this.__lastStep

        ; Tüm aktif gesture'ları kontrol et
        label := ""
        for g in this.__activeGestures {
            shouldTrigger := this.__CheckDirection(g.direction, diff, currentStep)

            if (shouldTrigger) {
                ; Once flag kontrolü
                isOnce := (g.direction & HotGestures.bDir.once)
                gestureKey := ObjPtr(g)

                if (isOnce) {
                    ; Once ise hemen çalıştırma, listeye ekle (Stop'ta çalışacak)
                    if (!this.__onceTriggered.Has(gestureKey)) {
                        this.__onceTriggered[gestureKey] := g.callback
                    }
                } else {
                    ; Normal gesture ise hemen çalış
                    g.callback.Call(Abs(currentStep)*diff)
                    ; OutputDebug("step: " . currentStep . ", diff: " . diff . "`n")
                    this.__gestureFired := true
                }

                ; Etiket için o anki diff
                label := this.__GetDirectionLabel(this.__lockedDirection, diff, currentStep)
            }
        }

        if (label != "") {
            this.__drawingBoard.DrawTip(label)
        }

        this.__lastStep := currentStep
        
        ; GÜVENLIK: 2000 pixel limitini aşma kontrolü (loop koruma)
        this.__totalDrawLength += Abs(diff * HotGestures.STEP_SIZE)
        if (this.__totalDrawLength > HotGestures.MAX_DRAW_LENGTH) {
            SoundBeep(1000, 200)  ; Uyarı sesi
            this.Stop()           ; Gesture'ı sonlandır
            return
        }
        
        this.__drawingBoard.DrawLineTo(x, y)
    }

    __Detect8WayDirection(dx, dy, absDx, absDy) {
        ; STRICT HORIZONTAL - yatay eksende minimal dikey sapma (< 3px)
        if (absDy < 3 && absDx > 6) {
            return (dx > 0) ? HotGestures.__dirType.strictRight : HotGestures.__dirType.strictLeft
        }

        ; STRICT VERTICAL - dikey eksende minimal yatay sapma (< 3px)
        if (absDx < 3 && absDy > 6) {
            return (dy > 0) ? HotGestures.__dirType.strictUp : HotGestures.__dirType.strictDown
        }

        ; DIAGONAL - her iki eksen de aktif (4+ pixel), ~45° açı
        if (absDx > 4 && absDy > 4) {
            if (dy > 0) {
                return (dx > 0) ? HotGestures.__dirType.upRight : HotGestures.__dirType.upLeft
            } else {
                return (dx > 0) ? HotGestures.__dirType.downRight : HotGestures.__dirType.downLeft
            }
        }

        ; BIASED - dominant eksen kazanır
        if (absDy > absDx) {
            return (dy > 0) ? HotGestures.__dirType.strictUp : HotGestures.__dirType.strictDown
        }
        return (dx > 0) ? HotGestures.__dirType.strictRight : HotGestures.__dirType.strictLeft
    }

    __FilterGesturesByDirection() {
        ; STRICT MATCHING: Direction flag TAMAMEN eşleşmeli
        for reg in this.__registrations {
            dir := reg.direction & ~HotGestures.bDir.once  ; Once flag'i çıkar

            if (this.__IsDirectionMatch(dir, this.__lockedDirection)) {
                this.__activeGestures.Push(reg)
            }
        }
    }

    __IsDirectionMatch(bDirFlags, detectedDir) {
        ; Detected direction'a göre hangi flag'ler kabul edilir?
        switch detectedDir {
            case HotGestures.__dirType.strictUp:
                return (bDirFlags == HotGestures.bDir.up || bDirFlags == HotGestures.bDir.upDown)
            case HotGestures.__dirType.strictDown:
                return (bDirFlags == HotGestures.bDir.down || bDirFlags == HotGestures.bDir.upDown)
            case HotGestures.__dirType.strictLeft:
                return (bDirFlags == HotGestures.bDir.left || bDirFlags == HotGestures.bDir.leftRight)
            case HotGestures.__dirType.strictRight:
                return (bDirFlags == HotGestures.bDir.right || bDirFlags == HotGestures.bDir.leftRight)
            case HotGestures.__dirType.upRight:
                return (bDirFlags == HotGestures.bDir.upRight)
            case HotGestures.__dirType.upLeft:
                return (bDirFlags == HotGestures.bDir.upLeft)
            case HotGestures.__dirType.downRight:
                return (bDirFlags == HotGestures.bDir.downRight)
            case HotGestures.__dirType.downLeft:
                return (bDirFlags == HotGestures.bDir.downLeft)
        }
        return false
    }

    __CheckDirection(direction, diff, currentStep) {
        dir := direction & ~HotGestures.bDir.once

        switch this.__lockedDirection {
            case HotGestures.__dirType.strictUp, HotGestures.__dirType.strictDown:
                ; upDown her hareketi kabul eder
                if (dir == HotGestures.bDir.upDown)
                    return true
                ; up sadece pozitif, down sadece negatif diff kabul eder
                return (dir == HotGestures.bDir.up && diff > 0) || (dir == HotGestures.bDir.down && diff < 0)

            case HotGestures.__dirType.strictLeft, HotGestures.__dirType.strictRight:
                ; leftRight her hareketi kabul eder
                if (dir == HotGestures.bDir.leftRight)
                    return true
                ; right sadece pozitif, left sadece negatif diff kabul eder
                return (dir == HotGestures.bDir.right && diff > 0) || (dir == HotGestures.bDir.left && diff < 0)

            default:
                ; Çapraz gesture'lar sadece ileri yönde tetiklenir
                return diff > 0
        }
    }

    __GetDirectionLabel(lockedDir, diff, currentStep) {
        absStep := Abs(currentStep)

        ; Dikey eksen - o anki diff'e göre UP/DN
        if (lockedDir == HotGestures.__dirType.strictUp || lockedDir == HotGestures.__dirType.strictDown) {
            return (diff > 0 ? "UP: " : "DN: ") . absStep
        }

        ; Yatay eksen - o anki diff'e göre RT/LF
        if (lockedDir == HotGestures.__dirType.strictLeft || lockedDir == HotGestures.__dirType.strictRight) {
            return (diff > 0 ? "RT: " : "LF: ") . absStep
        }

        ; Çaprazlar - kilitli yön (çaprazda ters yön yok)
        switch lockedDir {
            case HotGestures.__dirType.upRight: return "UR: " . absStep
            case HotGestures.__dirType.upLeft: return "UL: " . absStep
            case HotGestures.__dirType.downRight: return "DR: " . absStep
            case HotGestures.__dirType.downLeft: return "DL: " . absStep
        }
        return ""
    }

    ; Gesture class - Fluent interface için
    class Gesture {
        __New(direction, callback) {
            this.Direction := direction
            this.Callback := callback
        }
    }

    ; Mouse Hook - Windows API ile low-level mouse event yakalama
    class MouseHook {
        __New(callback) {
            this.__proc := CallbackCreate(LowLevelMouseHookProc, "F")
            this.__hook := DllCall("SetWindowsHookEx", "int", 14, "ptr", this.__proc, "ptr", 0, "uint", 0, "ptr")

            LowLevelMouseHookProc(nCode, wParam, lParam) {
                if (nCode == 0 && wParam == 0x0200)  ; WM_MOUSEMOVE
                    callback(NumGet(lParam, "int"), NumGet(lParam, 4, "int"))
                return DllCall("CallNextHookEx", "ptr", 0, "int", nCode, "ptr", wParam, "ptr", lParam)
            }
        }

        __Delete() {
            DllCall("UnhookWindowsHookEx", "ptr", this.__hook)
            CallbackFree(this.__proc)
        }
    }

    ; Drawing Board - MULTI-MONITOR destekli görsel feedback
    class DrawingBoard extends Gui {
        __New(penColor) {
            super.__New("+LastFound +AlwaysOnTop +ToolWindow +E0x00000020 -Caption -DPIScale")
            this.BackColor := 0
            WinSetTransColor(0)
            this.SetFont("S24 Bold", "Segoe UI")

            ; Çizim için DC (Device Context)
            this.__dc := DllCall("GetDC", "ptr", this.Hwnd, "ptr")
            this.__pen := DllCall("CreatePen", "int", 0, "int", 4, "int", penColor, "ptr")
            DllCall("SelectObject", "ptr", this.__dc, "ptr", this.__pen)

            ; Virtual screen boyutları - tüm monitörleri kapsar
            this.__virtualLeft := SysGet(76)    ; SM_XVIRTUALSCREEN
            this.__virtualTop := SysGet(77)     ; SM_YVIRTUALSCREEN
            this.__virtualWidth := SysGet(78)   ; SM_CXVIRTUALSCREEN
            this.__virtualHeight := SysGet(79)  ; SM_CYVIRTUALSCREEN

            ; Tip için text kontrolü
            this.__tip := this.AddText("Background0 c00FF88 x0 y0 w200 Center")
            WinSetTransColor("0 200", this.__tip)
        }

        __Delete() {
            try DllCall("DeleteObject", "ptr", this.__pen)
            try DllCall("ReleaseDC", "ptr", this.__dc)
        }

        Show() {
            this.Opt("AlwaysOnTop")
            ; Virtual screen koordinatlarına göre GUI'yi konumlandır
            super.Show("NoActivate x" this.__virtualLeft " y" this.__virtualTop 
                . " w" this.__virtualWidth " h" this.__virtualHeight - 1)
        }

        Hide() {
            super.Hide()
        }

        MoveTo(x, y) {
            ; Virtual screen offset'ini hesaba kat
            adjustedX := x - this.__virtualLeft
            adjustedY := y - this.__virtualTop
            DllCall("MoveToEx", "ptr", this.__dc, "int", adjustedX, "int", adjustedY, "ptr", 0)
        }

        DrawLineTo(x, y) {
            ; Virtual screen offset'ini hesaba kat
            adjustedX := x - this.__virtualLeft
            adjustedY := y - this.__virtualTop
            DllCall("LineTo", "ptr", this.__dc, "int", adjustedX, "int", adjustedY)
        }

        DrawTip(text) {
            this.__tip.Value := text
            MouseGetPos(&mx, &my)
            ; Virtual screen offset'ini hesaba kat
            adjustedX := mx - this.__virtualLeft + 25
            adjustedY := my - this.__virtualTop - 40
            this.__tip.Move(adjustedX, adjustedY)
        }
    }
}