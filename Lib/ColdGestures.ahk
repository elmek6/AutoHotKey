/************************************************************************
 * @description Eksen kilitli mouse slider sistemi - Register destekli
 * @author Assistant
 * @date 2026/01/21
 * @version 2.0
 ***********************************************************************/

class ColdGestures {
    static AXIS_THRESHOLD := 8      ; İlk 8 pixel'de yön belirleme
    static STEP_SIZE := 10            ; Her 10 pixel'de bir callback tetikle

    ; Binary direction flags
    static bDir := {
        none: 0,
        once: 1,      ; Bir kere tetikle
        up: 2,
        down: 4,
        left: 8,
        right: 16
    }

    __mouseHook := ""
    __drawingBoard := ""

    __originX := 0
    __originY := 0
    __lastStep := 0
    __axisLocked := false
    __lockedAxis := 0  ; 1=Vertical, 2=Horizontal
    __registrations := []
    __activeGestures := []  ; Axis belirlenince sadece uygun olanlar
    __onceTriggered := Map()  ; Once flag'li gesture'lar için

    __New(penColor := 0x00FF88) {
        this.__penColor := penColor
    }

    Register(direction, callback) {
        this.__registrations.Push({ direction: direction, callback: callback })
    }

    Clear() {
        this.__registrations := []
    }

    Start(keyName) {
        if (this.__registrations.Length == 0)
            return

        keyName := RegExReplace(keyName, "[\$\*\~\!\^\+]")

        CoordMode("Mouse", "Screen")
        MouseGetPos(&x, &y)
        this.__originX := x
        this.__originY := y
        this.__lastStep := 0
        this.__axisLocked := false
        this.__lockedAxis := 0
        this.__activeGestures := []
        this.__onceTriggered := Map()

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

        ; Eksen kilidi yoksa, ilk 8 pixel'de yönü belirle
        if (!this.__axisLocked) {
            if (Abs(dx) > ColdGestures.AXIS_THRESHOLD || Abs(dy) > ColdGestures.AXIS_THRESHOLD) {
                ; Hangi eksen daha baskın?
                this.__lockedAxis := (Abs(dy) >= Abs(dx)) ? 1 : 2
                this.__axisLocked := true

                ; Sadece bu axis'e uygun gesture'ları filtrele
                this.__FilterGesturesByAxis()

                if (this.__activeGestures.Length == 0) {
                    ; Uygun gesture yok, çık
                    return
                }
            }
            return
        }

        ; Kilitli eksendeki değeri al
        value := (this.__lockedAxis == 1) ? dy : dx

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

                if (isOnce && this.__onceTriggered.Has(gestureKey)) {
                    continue  ; Zaten tetiklendi, atla
                }

                g.callback.Call(diff)
                label := this.__GetDirectionLabel(g.direction, currentStep)

                if (isOnce) {
                    this.__onceTriggered[gestureKey] := true
                }
            }
        }

        if (label != "") {
            this.__drawingBoard.DrawTip(label)
        }

        this.__lastStep := currentStep
        this.__drawingBoard.DrawLineTo(x, y)
    }

    __FilterGesturesByAxis() {
        ; Axis'e göre uygun gesture'ları filtrele
        for reg in this.__registrations {
            dir := reg.direction & ~ColdGestures.bDir.once  ; Once flag'i çıkar

            isVertical := (dir & (ColdGestures.bDir.up | ColdGestures.bDir.down))
            isHorizontal := (dir & (ColdGestures.bDir.left | ColdGestures.bDir.right))

            ; Vertical axis kilitliyse sadece vertical gesture'lar
            if (this.__lockedAxis == 1 && isVertical) {
                this.__activeGestures.Push(reg)
            }
            ; Horizontal axis kilitliyse sadece horizontal gesture'lar
            else if (this.__lockedAxis == 2 && isHorizontal) {
                this.__activeGestures.Push(reg)
            }
        }
    }

    __CheckDirection(direction, diff, currentStep) {
        dir := direction & ~ColdGestures.bDir.once  ; Once flag'i çıkar

        ; Vertical kontrolü
        if (this.__lockedAxis == 1) {
            hasUp := (dir & ColdGestures.bDir.up)
            hasDown := (dir & ColdGestures.bDir.down)

            if (hasUp && hasDown) {
                return true  ; Her iki yön de kabul
            }
            if (hasUp && diff > 0) {
                return true
            }
            if (hasDown && diff < 0) {
                return true
            }
        }

        ; Horizontal kontrolü
        if (this.__lockedAxis == 2) {
            hasRight := (dir & ColdGestures.bDir.right)
            hasLeft := (dir & ColdGestures.bDir.left)

            if (hasRight && hasLeft) {
                return true  ; Her iki yön de kabul
            }
            if (hasRight && diff > 0) {
                return true
            }
            if (hasLeft && diff < 0) {
                return true
            }
        }

        return false
    }

    __GetDirectionLabel(direction, currentStep) {
        dir := direction & ~ColdGestures.bDir.once

        if (this.__lockedAxis == 1) {
            hasUp := (dir & ColdGestures.bDir.up)
            hasDown := (dir & ColdGestures.bDir.down)

            if (hasUp && hasDown) {
                return (currentStep >= 0) ? "UP: " . currentStep : "DN: " . currentStep
            }
            if (hasUp) {
                return "UP: " . currentStep
            }
            if (hasDown) {
                return "DN: " . currentStep
            }
        }

        if (this.__lockedAxis == 2) {
            hasRight := (dir & ColdGestures.bDir.right)
            hasLeft := (dir & ColdGestures.bDir.left)

            if (hasRight && hasLeft) {
                return (currentStep >= 0) ? "RT: " . currentStep : "LF: " . currentStep
            }
            if (hasRight) {
                return "RT: " . currentStep
            }
            if (hasLeft) {
                return "LF: " . currentStep
            }
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