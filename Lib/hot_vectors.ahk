/************************************************************************
 * @description Eksen kilitli mouse vector sistemi - 4-way direction detection
 * Fare sabit tutulur (polling, hook YOK). Vektör bilgisi Gui ile gösterilir.
 *
 * Callback: fn(pos)
 *   pos = +1 veya -1  (ivme kaldırıldı, her tetiklemede tek çağrı)
 *   +1 → sağ / yukarı
 *   -1 → sol / aşağı  (iki yönlü gesture'larda)
 *
 * bDir flag'leri:
 *   none      — hiçbir şey
 *   once      — modifier: gesture sadece bir kez tetiklenir (key bırakılınca)
 *   unlock    — modifier: bu yön kilitliyken dik hareket yapılırsa yön değişir
 *   up, down, left, right — tek yönlü
 *   upDown, leftRight     — çift yönlü (her iki yön aynı callback)
 *
 * @version 3.0
 ***********************************************************************/

class HotVectors {

    ; ── Sabitler ────────────────────────────────────────────────────────
    static DIRECTION_THRESHOLD := 8    ; px — yön kilidi eşiği
    static STEP_SIZE           := 14   ; px — bir tetiklenme eşiği
    static MAX_TOTAL_DISTANCE  := 9000 ; px — toplam hareket güvenlik limiti
    static POLL_INTERVAL       := 14   ; ms — while döngüsü uyku süresi
    static ACCELERATION_ENABLE := true ; İvme çarpanı aktif/pasif
    static MAX_SPEED_MULTIPLIER:= 20   ; Maksimum hız çarpanı (1-20 arası önerilir)

    ; ── Public API: direction flag'leri ─────────────────────────────────
    static bDir := {
        none:      0,
        once:      1,   ; modifier: bir kez tetikle
        unlock:    2,   ; modifier: dik harekette yön değişimine izin ver
        up:        4,
        down:      8,
        left:      16,
        right:     32,
        upDown:    4 | 8,     ; 12
        leftRight: 16 | 32    ; 48
    }

    ; ── modifier mask (once | unlock) ───────────────────────────────────
    static __modMask := 1 | 2   ; once | unlock

    ; ── İç enum: kilitli yön ────────────────────────────────────────────
    static __dirType := {
        none:       0,
        up:         1,
        down:       2,
        left:       3,
        right:      4
    }

    ; ════════════════════════════════════════════════════════════════════
    __New() {
        this.__originX         := 0
        this.__originY         := 0
        this.__directionLocked := false
        this.__lockedDirection := HotVectors.__dirType.none
        this.__registrations   := []
        this.__activeGestures  := []
        this.__onceTriggered   := Map()
        this.__gestureFired    := false
        this.__tip             := HotVectors.VectorTip()
    }

    ; ── Kayıt yönetimi ──────────────────────────────────────────────────
    ClearRegistrations() {
        this.__registrations := []
    }

    Register(direction, callback) {
        cleanDir := direction & ~HotVectors.__modMask
        for reg in this.__registrations {
            if ((reg.direction & ~HotVectors.__modMask) == cleanDir)
                throw Error("HotVectors: çakışan yön '" direction "' zaten kayıtlı!")
        }
        this.__registrations.Push({ direction: direction, callback: callback })
    }

    WasGestureFired() => this.__gestureFired

    ; ════════════════════════════════════════════════════════════════════
    ; Ana döngü — hook YOK, sade polling
    ; ════════════════════════════════════════════════════════════════════
    Start(keyName) {
        if (this.__registrations.Length == 0)
            return

        keyName := RegExReplace(keyName, "[\$\*\~\!\^\+]")

        CoordMode("Mouse", "Screen")
        MouseGetPos(&x, &y)

        this.__originX         := x
        this.__originY         := y
        this.__directionLocked := false
        this.__lockedDirection := HotVectors.__dirType.none
        this.__activeGestures  := []
        this.__onceTriggered   := Map()
        this.__gestureFired    := false

        totalDistance := 0
        runningPos    := 0

        while (GetKeyState(keyName, "P")) {
            MouseGetPos(&cx, &cy)
            dx := cx - this.__originX
            dy := this.__originY - cy  ; pozitif = yukarı

            ; ── Yön henüz kilitlenmedi ────────────────────────────────
            if (!this.__directionLocked) {
                absDx := Abs(dx)
                absDy := Abs(dy)
                if (absDx > HotVectors.DIRECTION_THRESHOLD
                 || absDy > HotVectors.DIRECTION_THRESHOLD) {
                    this.__lockedDirection := this.__Detect4WayDirection(dx, dy)
                    this.__directionLocked := true
                    this.__FilterGesturesByDirection()
                }
                Sleep(HotVectors.POLL_INTERVAL)
                continue
            }

            ; ── unlock: dik eksende hareket eşiği aşıldıysa yön değiştir ─
            if (this.__HasUnlockGesture()) {
                absDx := Abs(dx)
                absDy := Abs(dy)
                newDir := this.__Detect4WayDirection(dx, dy)
                if (newDir != this.__lockedDirection
                 && (absDx > HotVectors.DIRECTION_THRESHOLD
                  || absDy > HotVectors.DIRECTION_THRESHOLD)) {
                    this.__lockedDirection := newDir
                    this.__FilterGesturesByDirection()
                    MouseMove(this.__originX, this.__originY, 0)
                    runningPos := 0
                    Sleep(HotVectors.POLL_INTERVAL)
                    continue
                }
            }

            ; ── Kilitli eksende büyüklük ──────────────────────────────
            rawValue := this.__GetAxisValue(dx, dy)
            absMag   := Abs(rawValue)

            if (absMag < HotVectors.STEP_SIZE) {
                Sleep(HotVectors.POLL_INTERVAL)
                continue
            }

            sign := rawValue >= 0 ? 1 : -1

            ; ── İvme çarpanı hesapla ─────────────────────────────────
            speed := 1
            if (HotVectors.ACCELERATION_ENABLE) {
                speed := Min(Floor(absMag / HotVectors.STEP_SIZE), HotVectors.MAX_SPEED_MULTIPLIER)
            }

            ; ── Güvenlik limiti ───────────────────────────────────────
            totalDistance += absMag
            if (totalDistance > HotVectors.MAX_TOTAL_DISTANCE) {
                SoundBeep(1000, 200)
                break
            }

            ; ── Gesture'ları tetikle ─────────────────────────────────
            for g in this.__activeGestures {
                if (!this.__CheckDirection(g.direction, sign))
                    continue

                if (g.direction & HotVectors.bDir.once) {
                    gKey := ObjPtr(g)
                    if (!this.__onceTriggered.Has(gKey))
                        this.__onceTriggered[gKey] := g.callback
                } else {
                    Loop speed {
                        g.callback.Call(sign > 0 ? A_Index : -A_Index)
                    }
                    this.__gestureFired := true
                }
            }

            ; ── Kümülatif pos ve görsel ──────────────────────────────
            runningPos += (sign * speed)
            this.__tip.Update(
                this.__BuildLabel(sign, runningPos),
                this.__originX,
                this.__originY + 22
            )

            ; ── Fareyi origin'e sıfırla ───────────────────────────────
            MouseMove(this.__originX, this.__originY, 0)

            Sleep(HotVectors.POLL_INTERVAL)
        }

        this.Stop()
    }

    Stop() {
        for _, callback in this.__onceTriggered {
            callback.Call(1)
            this.__gestureFired := true
        }
        this.__tip.Hide()
    }

    ; ════════════════════════════════════════════════════════════════════
    ; Yardımcı metodlar
    ; ════════════════════════════════════════════════════════════════════

    __Detect4WayDirection(dx, dy) {
        if (Abs(dy) > Abs(dx))
            return dy > 0 ? HotVectors.__dirType.up   : HotVectors.__dirType.down
        return     dx > 0 ? HotVectors.__dirType.right : HotVectors.__dirType.left
    }

    __GetAxisValue(dx, dy) {
        switch this.__lockedDirection {
            case HotVectors.__dirType.up,    HotVectors.__dirType.down:  return dy
            case HotVectors.__dirType.right, HotVectors.__dirType.left:  return dx
        }
        return 0
    }

    ; ── Kayıtlı gesture'lardan herhangi biri unlock flag'i taşıyor mu? ──
    __HasUnlockGesture() {
        for reg in this.__registrations {
            if (reg.direction & HotVectors.bDir.unlock)
                return true
        }
        return false
    }

    ; ── Aktif gesture'lardan herhangi biri çift yönlü mü? ───────────────
    __IsBidirectional() {
        for g in this.__activeGestures {
            dir := g.direction & ~HotVectors.__modMask
            if (dir == HotVectors.bDir.upDown || dir == HotVectors.bDir.leftRight)
                return true
        }
        return false
    }

    ; ── Görsel etiket üret ───────────────────────────────────────────────
    __BuildLabel(sign, runningPos) {
        ld     := this.__lockedDirection
        isBidi := this.__IsBidirectional()
        valStr := (runningPos >= 0 ? "+" : "") . runningPos

        switch ld {
            case HotVectors.__dirType.up, HotVectors.__dirType.down:
                prefix  := isBidi ? "↕" : (sign > 0 ? "↑" : "↓")
                dirName := sign > 0 ? "UP" : "DN"
                return prefix . "  " . dirName . ": " . valStr

            case HotVectors.__dirType.left, HotVectors.__dirType.right:
                prefix  := isBidi ? "↔" : (sign > 0 ? "→" : "←")
                dirName := sign > 0 ? "RT" : "LT"
                return prefix . "  " . dirName . ": " . valStr
        }
        return "? " . valStr
    }

    __FilterGesturesByDirection() {
        this.__activeGestures := []
        for reg in this.__registrations {
            dir := reg.direction & ~HotVectors.__modMask
            if (this.__IsDirectionMatch(dir, this.__lockedDirection))
                this.__activeGestures.Push(reg)
        }
    }

    __IsDirectionMatch(bDirFlags, detectedDir) {
        switch detectedDir {
            case HotVectors.__dirType.up:
                return bDirFlags == HotVectors.bDir.up    || bDirFlags == HotVectors.bDir.upDown
            case HotVectors.__dirType.down:
                return bDirFlags == HotVectors.bDir.down  || bDirFlags == HotVectors.bDir.upDown
            case HotVectors.__dirType.left:
                return bDirFlags == HotVectors.bDir.left  || bDirFlags == HotVectors.bDir.leftRight
            case HotVectors.__dirType.right:
                return bDirFlags == HotVectors.bDir.right || bDirFlags == HotVectors.bDir.leftRight
        }
        return false
    }

    __CheckDirection(direction, sign) {
        dir := direction & ~HotVectors.__modMask
        switch this.__lockedDirection {
            case HotVectors.__dirType.up, HotVectors.__dirType.down:
                if (dir == HotVectors.bDir.upDown)
                    return true
                return (dir == HotVectors.bDir.up   && sign > 0)
                    || (dir == HotVectors.bDir.down  && sign < 0)
            case HotVectors.__dirType.left, HotVectors.__dirType.right:
                if (dir == HotVectors.bDir.leftRight)
                    return true
                return (dir == HotVectors.bDir.right && sign > 0)
                    || (dir == HotVectors.bDir.left  && sign < 0)
        }
        return false
    }

    ; ════════════════════════════════════════════════════════════════════
    ; İç sınıflar
    ; ════════════════════════════════════════════════════════════════════

    ; Gesture — EM.gesture() ile kullanım için
    class Gesture {
        __New(direction, callback) {
            this.Direction := direction
            this.Callback  := callback
        }
    }

    ; VectorTip — unicode destekli, yeniden oluşturmadan güncellenen Gui.
    class VectorTip {
        __New() {
            g := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20 -DPIScale")
            g.BackColor := "1A1A2E"
            WinSetTransColor("1A1A2E 210", g)
            g.MarginX := 10
            g.MarginY := 6
            g.SetFont("s12 Bold c00FF88", "Segoe UI")
            this.__lbl     := g.AddText("w240 Center", "")
            this.__gui     := g
            this.__visible := false
        }

        Update(text, x, y) {
            this.__lbl.Value := text

            monitorIndex := this.__GetMonitorIndexFromCoords(x, y)
            MonitorGetWorkArea(monitorIndex, &monLeft, &monTop, &monRight, )

            guiX := x - 120
            guiY := y

            guiWidth := 240
            if (guiX < monLeft)
                guiX := monLeft
            if (guiX + guiWidth > monRight)
                guiX := monRight - guiWidth
            if (guiY < monTop)
                guiY := monTop

            this.__gui.Move(guiX, guiY)
            if (!this.__visible) {
                this.__gui.Show("NA AutoSize NoActivate")
                this.__visible := true
            }
        }

        __GetMonitorIndexFromCoords(x, y) {
            Loop MonitorGetCount() {
                MonitorGet(A_Index, &mLeft, &mTop, &mRight, &mBottom)
                if (x >= mLeft && x <= mRight && y >= mTop && y <= mBottom)
                    return A_Index
            }
            return 1
        }

        Hide() {
            if (this.__visible) {
                this.__gui.Hide()
                this.__visible := false
            }
        }

        __Delete() {
            try this.__gui.Destroy()
        }
    }
}
