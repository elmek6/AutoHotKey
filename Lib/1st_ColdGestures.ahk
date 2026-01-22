/************************************************************************
 * @description Eksen kilitli mouse slider sistemi - HotGestures mimarisinde
 * @author Assistant
 * @date 2026/01/21
 * @version 1.1
 ***********************************************************************/

class ColdGestures {
    static AXIS_THRESHOLD := 8      ; İlk 8 pixel'de yön belirleme
    static STEP_SIZE := 10            ; Her 10 pixel'de bir callback tetikle

    static Dir := {
        None: 0,
        UpDown: 1,    ; Slider - yukarı/aşağı her hareket bildirilir
        LeftRight: 2, ; Slider - sağ/sol her hareket bildirilir
        Up: 3,        ; Sadece yukarı hareket sayılır
        Down: 4,      ; Sadece aşağı hareket sayılır
        Left: 5,      ; Sadece sola hareket sayılır
        Right: 6      ; Sadece sağa hareket sayılır
    }

    __mouseHook := ""
    __drawingBoard := ""

    __originX := 0
    __originY := 0
    __lastStep := 0
    __axisLocked := false
    __lockedAxis := 0  ; 1=Vertical, 2=Horizontal
    __gesture := ""

    class Gesture {
        __New(direction, callback) {
            this.Direction := direction
            this.Callback := callback
            this.__parent := ColdGestures()
            this.__parent.__Start(this, A_ThisHotkey)
        }
    }

    __Start(gesture, keyName) {
        this.__gesture := gesture
        keyName := RegExReplace(keyName, "[\$\*\~\!\^\+]")

        CoordMode("Mouse", "Screen")
        MouseGetPos(&x, &y)
        this.__originX := x
        this.__originY := y
        this.__lastStep := 0
        this.__axisLocked := false
        this.__lockedAxis := 0

        ; Drawing board oluştur
        this.__drawingBoard := ColdGestures.DrawingBoard(0x00FF88)
        this.__drawingBoard.MoveTo(x, y)
        this.__drawingBoard.Show()

        ; Mouse hook başlat
        this.__mouseHook := ColdGestures.MouseHook(this.__OnMouseMove.Bind(this))

        ; Tuş bırakılana kadar bekle
        KeyWait(keyName)
        this.__Stop()
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

        ; Bu tick'teki değişim miktarı (SON tick'ten bu yana)
        diff := currentStep - this.__lastStep

        ; Gesture yönüne göre kontrol et
        dir := this.__gesture.Direction
        shouldTrigger := false
        label := ""

        switch dir {
            case ColdGestures.Dir.UpDown:
                if (this.__lockedAxis == 1) {
                    shouldTrigger := true
                    label := (currentStep >= 0) ? "UP: " : "DN: "
                }

            case ColdGestures.Dir.LeftRight:
                if (this.__lockedAxis == 2) {
                    shouldTrigger := true
                    label := (currentStep >= 0) ? "RT: " : "LF: "
                }

            case ColdGestures.Dir.Up:
                if (this.__lockedAxis == 1 && diff > 0) {
                    shouldTrigger := true
                    label := "UP: "
                }

            case ColdGestures.Dir.Down:
                if (this.__lockedAxis == 1 && diff < 0) {
                    shouldTrigger := true
                    label := "DN: "
                }

            case ColdGestures.Dir.Left:
                if (this.__lockedAxis == 2 && diff < 0) {
                    shouldTrigger := true
                    label := "LF: "
                }

            case ColdGestures.Dir.Right:
                if (this.__lockedAxis == 2 && diff > 0) {
                    shouldTrigger := true
                    label := "RT: "
                }
        }

        ; Callback'i tetikle - diff son adımdan bu yana değişim
        if (shouldTrigger) {
            this.__gesture.Callback.Call(diff)
            this.__drawingBoard.DrawTip(label . currentStep)
        }

        this.__lastStep := currentStep
        this.__drawingBoard.DrawLineTo(x, y)
    }

    __Stop() {
        this.__mouseHook := ""
        if (this.__drawingBoard) {
            this.__drawingBoard.Hide()
            this.__drawingBoard := ""
        }
        this.__gesture := ""
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