/************************************************************************
 * @description Eksen kilitli mouse vector sistemi - 8-way direction detection
 * Fare sabit tutulur (polling ile sıfırlanır), hook YOK.
 * Vektör yönü + değeri + ivme bilgisi inline Gui ile gösterilir.
 * 
 * HotGestures ile birebir API uyumlu:
 *   bDir, Register, ClearRegistrations, Start, Stop, WasGestureFired, Gesture
 * 
 * Callback: fn(pos)
 *   pos > 0  → sağ / yukarı / çapraz-ileri
 *   pos < 0  → sol / aşağı / çapraz-geri  (iki yönlü gesture'larda)
 *   Abs(pos) → ivme birimi (kaç STEP ilerlendi)
 *   Loop speed { cb(sign * A_Index) } → Mod(pos, N) throttle'lar eski gibi çalışır
 * 
 * @version 1.0
 ***********************************************************************/

class HotVectors {

    ; ── Sabitler ────────────────────────────────────────────────────────
    static DIRECTION_THRESHOLD := 8    ; px — yön kilidi eşiği
    static STEP_SIZE := 10   ; px — bir ivme birimi
    static MAX_SPEED := 20   ; tek burst'te max callback tekrarı
    static MAX_TOTAL_DISTANCE := 3000 ; px — toplam hareket güvenlik limiti
    static POLL_INTERVAL := 10   ; ms — while döngüsü uyku süresi

    ; ── Public API: binary direction flag'leri (HotGestures uyumlu) ─────
    static bDir := {
        none: 0,
        once: 1,
        up: 2,
        down: 4,
        left: 8,
        right: 16,
        upDown: 2 | 4,    ; 6
        leftRight: 8 | 16,   ; 24
        upRight: 32,
        upLeft: 64,
        downRight: 128,
        downLeft: 256
    }

    ; ── İç enum: kilitli yön ────────────────────────────────────────────
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

    ; ── Görsel etiketler (Gui unicode'u destekler) ──────────────────────
    static __dirLabel := Map(
        1, { pos: "↑ Up", neg: "↓ Down" },
        2, { pos: "↓ Down", neg: "↑ Up" },
        3, { pos: "← Left", neg: "→ Right" },
        4, { pos: "→ Right", neg: "← Left" },
        5, { pos: "↗ UpRight", neg: "↙ DownLeft" },
        6, { pos: "↖ UpLeft", neg: "↘ DownRight" },
        7, { pos: "↘ DownRight", neg: "↖ UpLeft" },
        8, { pos: "↙ DownLeft", neg: "↗ UpRight" }
    )

    ; ════════════════════════════════════════════════════════════════════
    __New() {
        this.__originX := 0
        this.__originY := 0
        this.__directionLocked := false
        this.__lockedDirection := HotVectors.__dirType.none
        this.__registrations := []
        this.__activeGestures := []
        this.__onceTriggered := Map()
        this.__gestureFired := false
        this.__tip := HotVectors.VectorTip()
    }

    ; ── Kayıt yönetimi ──────────────────────────────────────────────────
    ClearRegistrations() {
        this.__registrations := []
    }

    Register(direction, callback) {
        cleanDir := direction & ~HotVectors.bDir.once
        for reg in this.__registrations {
            if ((reg.direction & ~HotVectors.bDir.once) == cleanDir)
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

        this.__originX := x
        this.__originY := y
        this.__directionLocked := false
        this.__lockedDirection := HotVectors.__dirType.none
        this.__activeGestures := []
        this.__onceTriggered := Map()
        this.__gestureFired := false

        totalDistance := 0

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
                    this.__lockedDirection := this.__Detect8WayDirection(dx, dy, absDx, absDy)
                    this.__directionLocked := true
                    this.__gestureFired := true
                    this.__FilterGesturesByDirection()
                }
                Sleep(HotVectors.POLL_INTERVAL)
                continue
            }

            ; ── Kilitli eksende büyüklük ──────────────────────────────
            rawValue := this.__GetAxisValue(dx, dy)
            absMag := Abs(rawValue)

            if (absMag < HotVectors.STEP_SIZE) {
                Sleep(HotVectors.POLL_INTERVAL)
                continue
            }

            speed := Min(Floor(absMag / HotVectors.STEP_SIZE), HotVectors.MAX_SPEED)
            sign := rawValue >= 0 ? 1 : -1

            ; ── Güvenlik limiti ───────────────────────────────────────
            totalDistance += absMag
            if (totalDistance > HotVectors.MAX_TOTAL_DISTANCE) {
                SoundBeep(1000, 200)
                break
            }

            ; ── Gesture'ları tetikle ──────────────────────────────────
            for g in this.__activeGestures {
                if (!this.__CheckDirection(g.direction, sign))
                    continue

                if (g.direction & HotVectors.bDir.once) {
                    gKey := ObjPtr(g)
                    if (!this.__onceTriggered.Has(gKey))
                        this.__onceTriggered[gKey] := g.callback
                } else {
                    ; speed kez çağır → pos = ±1, ±2, … ±speed
                    ; Mod(pos, N) throttle'ları eski gibi çalışır
                    Loop speed {
                        g.callback.Call(sign > 0 ? A_Index : -A_Index)
                    }
                    this.__gestureFired := true
                }
            }

            ; ── Görsel geri bildirim ──────────────────────────────────
            this.__tip.Update(this.__BuildLabel(sign, rawValue, speed),
                this.__originX + 20,
                this.__originY - 50)

            ; ── Fareyi origin'e sıfırla (ivme için kritik) ───────────
            ; NOT: hook callback değil, normal while döngüsü → güvenli.
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

    __GetAxisValue(dx, dy) {
        switch this.__lockedDirection {
            case HotVectors.__dirType.strictUp, HotVectors.__dirType.strictDown: return dy
            case HotVectors.__dirType.strictRight, HotVectors.__dirType.strictLeft: return dx
            case HotVectors.__dirType.upRight: return (dx + dy) // 2
            case HotVectors.__dirType.upLeft: return (-dx + dy) // 2
            case HotVectors.__dirType.downRight: return (dx - dy) // 2
            case HotVectors.__dirType.downLeft: return (-dx - dy) // 2
        }
        return 0
    }

    __BuildLabel(sign, rawValue, speed) {
        ld := this.__lockedDirection
        lbl := HotVectors.__dirLabel.Has(ld) ? HotVectors.__dirLabel[ld] : { pos: "?", neg: "?" }

        dirText := sign >= 0 ? lbl.pos : lbl.neg
        valText := (sign >= 0 ? "+" : "") . rawValue
        dots := ""
        Loop Min(speed, 8)
            dots .= "●"
        return dirText . "   " . valText . "  " . dots
    }

    __Detect8WayDirection(dx, dy, absDx, absDy) {
        if (absDy < 3 && absDx > 6)
            return dx > 0 ? HotVectors.__dirType.strictRight : HotVectors.__dirType.strictLeft
        if (absDx < 3 && absDy > 6)
            return dy > 0 ? HotVectors.__dirType.strictUp : HotVectors.__dirType.strictDown
        if (absDx > 4 && absDy > 4)
            return dy > 0
                ? (dx > 0 ? HotVectors.__dirType.upRight : HotVectors.__dirType.upLeft)
                : (dx > 0 ? HotVectors.__dirType.downRight : HotVectors.__dirType.downLeft)
        if (absDy > absDx)
            return dy > 0 ? HotVectors.__dirType.strictUp : HotVectors.__dirType.strictDown
        return dx > 0 ? HotVectors.__dirType.strictRight : HotVectors.__dirType.strictLeft
    }

    __FilterGesturesByDirection() {
        for reg in this.__registrations {
            dir := reg.direction & ~HotVectors.bDir.once
            if (this.__IsDirectionMatch(dir, this.__lockedDirection))
                this.__activeGestures.Push(reg)
        }
    }

    __IsDirectionMatch(bDirFlags, detectedDir) {
        switch detectedDir {
            case HotVectors.__dirType.strictUp:
                return bDirFlags == HotVectors.bDir.up || bDirFlags == HotVectors.bDir.upDown
            case HotVectors.__dirType.strictDown:
                return bDirFlags == HotVectors.bDir.down || bDirFlags == HotVectors.bDir.upDown
            case HotVectors.__dirType.strictLeft:
                return bDirFlags == HotVectors.bDir.left || bDirFlags == HotVectors.bDir.leftRight
            case HotVectors.__dirType.strictRight:
                return bDirFlags == HotVectors.bDir.right || bDirFlags == HotVectors.bDir.leftRight
            case HotVectors.__dirType.upRight: return bDirFlags == HotVectors.bDir.upRight
            case HotVectors.__dirType.upLeft: return bDirFlags == HotVectors.bDir.upLeft
            case HotVectors.__dirType.downRight: return bDirFlags == HotVectors.bDir.downRight
            case HotVectors.__dirType.downLeft: return bDirFlags == HotVectors.bDir.downLeft
        }
        return false
    }

    __CheckDirection(direction, sign) {
        dir := direction & ~HotVectors.bDir.once
        switch this.__lockedDirection {
            case HotVectors.__dirType.strictUp, HotVectors.__dirType.strictDown:
                if (dir == HotVectors.bDir.upDown)
                    return true
                return (dir == HotVectors.bDir.up && sign > 0)
                || (dir == HotVectors.bDir.down && sign < 0)
            case HotVectors.__dirType.strictLeft, HotVectors.__dirType.strictRight:
                if (dir == HotVectors.bDir.leftRight)
                    return true
                return (dir == HotVectors.bDir.right && sign > 0)
                || (dir == HotVectors.bDir.left && sign < 0)
            default:
                return sign > 0
        }
    }

    ; ════════════════════════════════════════════════════════════════════
    ; İç sınıflar
    ; ════════════════════════════════════════════════════════════════════

    ; Gesture — EM.gesture() ile kullanım için (HotGestures uyumlu)
    class Gesture {
        __New(direction, callback) {
            this.Direction := direction
            this.Callback := callback
        }
    }

    ; VectorTip — unicode destekli, yeniden oluşturmadan güncellenen Gui.
    ; ToolTip() yerine: hem unicode ok, hem titreme yok, hem sabit konumlu.
    class VectorTip {
        __New() {
            g := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20 -DPIScale")
            g.BackColor := "1A1A2E"
            WinSetTransColor("1A1A2E 210", g)
            g.MarginX := 12
            g.MarginY := 8
            g.SetFont("s13 Bold c00FF88", "Segoe UI")
            this.__lbl := g.AddText("w320 Center", "")
            this.__gui := g
            this.__visible := false
        }

        Update(text, x, y) {
            this.__lbl.Value := text
            this.__gui.Move(x, y)
            if (!this.__visible) {
                this.__gui.Show("NA AutoSize NoActivate")
                this.__visible := true
            }
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