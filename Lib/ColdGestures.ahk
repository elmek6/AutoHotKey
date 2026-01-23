/************************************************************************
 * @description Eksen kilitli mouse slider sistemi - 8-way direction detection
 * @author Benim Assistan
 * @date 2026/01/23
 * @version 3.1
 ***********************************************************************/

class ColdGestures {
    static DIRECTION_THRESHOLD := 10    ; İlk 10 pixel'de yön belirleme
    static STEP_SIZE := 10              ; Her 10 pixel'de bir callback tetikle

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

    __New(penColor := 0x00FF88) {
        this.__penColor := penColor
    }

    Register(direction, callback) {
        ; Çakışma kontrolü: Aynı direction için birden fazla gesture YASAK
        cleanDir := direction & ~ColdGestures.bDir.once

        for reg in this.__registrations {
            existingDir := reg.direction & ~ColdGestures.bDir.once

            ; Tam eşleşme kontrolü
            if (existingDir == cleanDir) {
                throw Error("Duplicate gesture registration: Direction already registered!")
            }

            ; Çakışma kontrolü: up ve upDown birlikte olamaz
            if (this.__CheckDirectionConflict(cleanDir, existingDir)) {
                throw Error("Conflicting gesture directions: Cannot register overlapping directions!")
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
        this.__lockedDirection := ColdGestures.__dirType.none
        this.__activeGestures := []
        this.__onceTriggered := Map()
        this.__gestureFired := false

        ; Drawing board oluştur
        this.__drawingBoard := ColdGestures.DrawingBoard(this.__penColor)
        this.__drawingBoard.MoveTo(x, y)
        this.__drawingBoard.Show()

        ; Mouse hook başlat
        this.__mouseHook := ColdGestures.MouseHook(this.__OnMouseMove.Bind(this))

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

            if (absDx > ColdGestures.DIRECTION_THRESHOLD || absDy > ColdGestures.DIRECTION_THRESHOLD) {
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
            case ColdGestures.__dirType.strictUp, ColdGestures.__dirType.strictDown:
                value := dy
            case ColdGestures.__dirType.strictLeft, ColdGestures.__dirType.strictRight:
                value := dx
            case ColdGestures.__dirType.upRight:
                value := (dx + dy) // 2  ; Diagonal ortalama
            case ColdGestures.__dirType.upLeft:
                value := (-dx + dy) // 2
            case ColdGestures.__dirType.downRight:
                value := (dx - dy) // 2
            case ColdGestures.__dirType.downLeft:
                value := (-dx - dy) // 2
        }

        ; Kaç adım (step) geçildi?
        currentStep := value // ColdGestures.STEP_SIZE

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
                isOnce := (g.direction & ColdGestures.bDir.once)
                gestureKey := ObjPtr(g)

                if (isOnce) {
                    ; Once ise hemen çalıştırma, listeye ekle (Stop'ta çalışacak)
                    if (!this.__onceTriggered.Has(gestureKey)) {
                        this.__onceTriggered[gestureKey] := g.callback
                    }
                } else {
                    ; Normal gesture ise hemen çalıştır
                    g.callback.Call(diff)
                    this.__gestureFired := true
                }

                ; Etiket için o anki diff'e göre yön belirle
                label := this.__GetDirectionLabel(this.__lockedDirection, diff, currentStep)
            }
        }

        if (label != "") {
            this.__drawingBoard.DrawTip(label)
        }

        this.__lastStep := currentStep
        this.__drawingBoard.DrawLineTo(x, y)
    }

    __Detect8WayDirection(dx, dy, absDx, absDy) {
        ; STRICT HORIZONTAL (< 3 pixel dikey sapma)
        if (absDy < 3 && absDx > 6) {
            return (dx > 0) ? ColdGestures.__dirType.strictRight : ColdGestures.__dirType.strictLeft
        }

        ; STRICT VERTICAL (< 3 pixel yatay sapma)
        if (absDx < 3 && absDy > 6) {
            return (dy > 0) ? ColdGestures.__dirType.strictUp : ColdGestures.__dirType.strictDown
        }

        ; DIAGONAL (45° civarı, her iki eksen de 4+ pixel)
        if (absDx > 4 && absDy > 4) {
            if (dx > 0 && dy > 0)
                return ColdGestures.__dirType.upRight
            if (dx < 0 && dy > 0)
                return ColdGestures.__dirType.upLeft
            if (dx > 0 && dy < 0)
                return ColdGestures.__dirType.downRight
            if (dx < 0 && dy < 0)
                return ColdGestures.__dirType.downLeft
        }

        ; BIASED durumlar: Dominant eksen kazanır
        if (absDy > absDx) {
            ; Vertical dominant
            return (dy > 0) ? ColdGestures.__dirType.strictUp : ColdGestures.__dirType.strictDown
        } else {
            ; Horizontal dominant
            return (dx > 0) ? ColdGestures.__dirType.strictRight : ColdGestures.__dirType.strictLeft
        }
    }

    __FilterGesturesByDirection() {
        ; STRICT MATCHING: Direction flag TAMAMEN eşleşmeli
        for reg in this.__registrations {
            dir := reg.direction & ~ColdGestures.bDir.once  ; Once flag'i çıkar

            if (this.__IsDirectionMatch(dir, this.__lockedDirection)) {
                this.__activeGestures.Push(reg)
            }
        }
    }

    __IsDirectionMatch(bDirFlags, detectedDir) {
        ; Detected direction'a göre hangi flag'ler kabul edilir?
        switch detectedDir {
            case ColdGestures.__dirType.strictUp:
                return (bDirFlags == ColdGestures.bDir.up) || (bDirFlags == ColdGestures.bDir.upDown)

            case ColdGestures.__dirType.strictDown:
                return (bDirFlags == ColdGestures.bDir.down) || (bDirFlags == ColdGestures.bDir.upDown)

            case ColdGestures.__dirType.strictLeft:
                return (bDirFlags == ColdGestures.bDir.left) || (bDirFlags == ColdGestures.bDir.leftRight)

            case ColdGestures.__dirType.strictRight:
                return (bDirFlags == ColdGestures.bDir.right) || (bDirFlags == ColdGestures.bDir.leftRight)

            case ColdGestures.__dirType.upRight:
                return (bDirFlags == ColdGestures.bDir.upRight)

            case ColdGestures.__dirType.upLeft:
                return (bDirFlags == ColdGestures.bDir.upLeft)

            case ColdGestures.__dirType.downRight:
                return (bDirFlags == ColdGestures.bDir.downRight)

            case ColdGestures.__dirType.downLeft:
                return (bDirFlags == ColdGestures.bDir.downLeft)
        }
        return false
    }

    __CheckDirectionConflict(dir1, dir2) {
        ; Çakışma kontrolü: Aynı temel yönleri paylaşıyorlar mı?

        ; up ve upDown çakışır
        if ((dir1 == ColdGestures.bDir.up || dir1 == ColdGestures.bDir.upDown) &&
            (dir2 == ColdGestures.bDir.up || dir2 == ColdGestures.bDir.upDown)) {
            return true
        }

        ; down ve upDown çakışır
        if ((dir1 == ColdGestures.bDir.down || dir1 == ColdGestures.bDir.upDown) &&
            (dir2 == ColdGestures.bDir.down || dir2 == ColdGestures.bDir.upDown)) {
            return true
        }

        ; left ve leftRight çakışır
        if ((dir1 == ColdGestures.bDir.left || dir1 == ColdGestures.bDir.leftRight) &&
            (dir2 == ColdGestures.bDir.left || dir2 == ColdGestures.bDir.leftRight)) {
            return true
        }

        ; right ve leftRight çakışır
        if ((dir1 == ColdGestures.bDir.right || dir1 == ColdGestures.bDir.leftRight) &&
            (dir2 == ColdGestures.bDir.right || dir2 == ColdGestures.bDir.leftRight)) {
            return true
        }

        return false
    }

    __CheckDirection(direction, diff, currentStep) {
        dir := direction & ~ColdGestures.bDir.once

        switch this.__lockedDirection {
            case ColdGestures.__dirType.strictUp, ColdGestures.__dirType.strictDown:
                ; upDown her hareketi kabul eder, up sadece pozitif, down sadece negatif diff kabul eder
                if (dir == ColdGestures.bDir.upDown) {
                    return true
                }
                if (dir == ColdGestures.bDir.up) {
                    return diff > 0
                }
                if (dir == ColdGestures.bDir.down) {
                    return diff < 0
                }

            case ColdGestures.__dirType.strictLeft, ColdGestures.__dirType.strictRight:
                ; leftRight her hareketi kabul eder
                if (dir == ColdGestures.bDir.leftRight) {
                    return true
                }
                if (dir == ColdGestures.bDir.right) {
                    return diff > 0
                }
                if (dir == ColdGestures.bDir.left) {
                    return diff < 0
                }
            default:
                ; Çapraz gesture'lar (sadece ileri yönde tetiklenir)
                return diff > 0
        }
        return false
    }

    __GetDirectionLabel(lockedDir, diff, currentStep) {
        absStep := Abs(currentStep)

        ; Eğer dikey bir eksendeysek, o anki diff'e göre UP/DN yaz
        if (lockedDir == ColdGestures.__dirType.strictUp || lockedDir == ColdGestures.__dirType.strictDown) {
            return (diff > 0 ? "UP: " : "DN: ") . absStep
        }

        ; Eğer yatay bir eksendeysek, o anki diff'e göre RT/LF yaz
        if (lockedDir == ColdGestures.__dirType.strictLeft || lockedDir == ColdGestures.__dirType.strictRight) {
            return (diff > 0 ? "RT: " : "LF: ") . absStep
        }

        ; Çaprazlar için sabit kilitli yönü yaz (çünkü çaprazda ters yön kontrolü yapmıyoruz)
        switch lockedDir {
            case ColdGestures.__dirType.upRight: return "UR: " . absStep
            case ColdGestures.__dirType.upLeft: return "UL: " . absStep
            case ColdGestures.__dirType.downRight: return "DR: " . absStep
            case ColdGestures.__dirType.downLeft: return "DL: " . absStep
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

    ; Mouse Hook
    class MouseHook {
        __New(callback) {
            this.__proc := CallbackCreate(LowLevelMouseHookProc, "F")
            this.__hook := DllCall("SetWindowsHookEx", "int", 14, "ptr", this.__proc, "ptr", 0, "uint", 0, "ptr")

            LowLevelMouseHookProc(nCode, wParam, lParam) {
                if (nCode == 0 && wParam == 0x0200)
                    callback(NumGet(lParam, "int"), NumGet(lParam, 4, "int"))
                return DllCall("CallNextHookEx", "ptr", 0, "int", nCode, "ptr", wParam, "ptr", lParam)
            }
        }

        __Delete() {
            DllCall("UnhookWindowsHookEx", "ptr", this.__hook)
            CallbackFree(this.__proc)
        }
    }

    ; Drawing Board
    class DrawingBoard extends Gui {
        __New(penColor) {
            super.__New("+LastFound +AlwaysOnTop +ToolWindow +E0x00000020 -Caption -DPIScale")
            this.BackColor := 0
            WinSetTransColor(0)
            this.SetFont("S24 Bold", "Segoe UI")

            ; Çizim için DC
            this.__dc := DllCall("GetDC", "ptr", this.Hwnd, "ptr")
            this.__pen := DllCall("CreatePen", "int", 0, "int", 4, "int", penColor, "ptr")
            DllCall("SelectObject", "ptr", this.__dc, "ptr", this.__pen)

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
            super.Show("NoActivate x0 y0 w" A_ScreenWidth " h" A_ScreenHeight - 1)
        }

        Hide() {
            super.Hide()
        }

        MoveTo(x, y) => DllCall("MoveToEx", "ptr", this.__dc, "int", x, "int", y, "ptr", 0)

        DrawLineTo(x, y) => DllCall("LineTo", "ptr", this.__dc, "int", x, "int", y)

        DrawTip(text) {
            this.__tip.Value := text
            MouseGetPos(&mx, &my)
            this.__tip.Move(mx + 25, my - 40)
        }
    }
}