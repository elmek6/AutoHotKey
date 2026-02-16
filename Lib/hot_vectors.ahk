/************************************************************************
 * @description Eksen kilitli mouse vector sistemi - 8-way direction detection
 * Fare sabit tutulur (polling, hook YOK). Vektör bilgisi Gui ile gösterilir.
 *
 * HotGestures ile birebir API uyumlu:
 *   bDir, Register, ClearRegistrations, Start, Stop, WasGestureFired, Gesture
 *
 * Callback: fn(pos)
 *   pos = +1 veya -1  (ivme kaldırıldı, her tetiklemede tek çağrı)
 *   +1 → sağ / yukarı / çapraz-ileri
 *   -1 → sol / aşağı  (iki yönlü gesture'larda)
 *
 * Ekran gösterimi örneği:
 *   ↔ LT: -3    (leftRight gesture, 3 kez sola gidildi)
 *   ↔ RT: +2    (leftRight gesture, 2 kez sağa gidildi)
 *   ↑  UP: +1   (tek yönlü up gesture)
 *
 * @version 2.0
 ***********************************************************************/

class HotVectors {

    ; ── Sabitler ────────────────────────────────────────────────────────
    static DIRECTION_THRESHOLD := 8    ; px — yön kilidi eşiği
    static STEP_SIZE           := 10   ; px — bir tetiklenme eşiği
    static MAX_TOTAL_DISTANCE  := 9000 ; px — toplam hareket güvenlik limiti
    static POLL_INTERVAL       := 10   ; ms — while döngüsü uyku süresi

    ; ── Public API: binary direction flag'leri (HotGestures uyumlu) ─────
    static bDir := {
        none:      0,
        once:      1,
        up:        2,
        down:      4,
        left:      8,
        right:     16,
        upDown:    2 | 4,    ; 6
        leftRight: 8 | 16,   ; 24
        upRight:   32,
        upLeft:    64,
        downRight: 128,
        downLeft:  256
    }

    ; ── İç enum: kilitli yön ────────────────────────────────────────────
    static __dirType := {
        none:       0,
        strictUp:   1,
        strictDown: 2,
        strictLeft: 3,
        strictRight:4,
        upRight:    5,
        upLeft:     6,
        downRight:  7,
        downLeft:   8
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

        this.__originX         := x
        this.__originY         := y
        this.__directionLocked := false
        this.__lockedDirection := HotVectors.__dirType.none
        this.__activeGestures  := []
        this.__onceTriggered   := Map()
        this.__gestureFired    := false

        totalDistance := 0
        runningPos    := 0   ; görsel için kümülatif pos sayacı

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
                    this.__gestureFired    := true   ; yön kilitlendi = bir şey oldu
                    this.__FilterGesturesByDirection()
                }
                Sleep(HotVectors.POLL_INTERVAL)
                continue
            }

            ; ── Kilitli eksende büyüklük ──────────────────────────────
            rawValue := this.__GetAxisValue(dx, dy)
            absMag   := Abs(rawValue)

            if (absMag < HotVectors.STEP_SIZE) {
                Sleep(HotVectors.POLL_INTERVAL)
                continue
            }

            sign := rawValue >= 0 ? 1 : -1

            ; ── Güvenlik limiti ───────────────────────────────────────
            totalDistance += absMag
            if (totalDistance > HotVectors.MAX_TOTAL_DISTANCE) {
                SoundBeep(1000, 200)
                ; __gestureFired zaten true — key_handler_mouse menüyü açmaz
                break
            }

            ; ── Gesture'ları tetikle ─────────────────────────────────
            ; İvme kaldırıldı: her tetiklemede callback tam olarak 1 kez çağrılır.
            ; İleride ivme lazım olursa:
            ;   speed := Min(Floor(absMag / HotVectors.STEP_SIZE), 20)
            ;   Loop speed { g.callback.Call(sign > 0 ? A_Index : -A_Index) }
            for g in this.__activeGestures {
                if (!this.__CheckDirection(g.direction, sign))
                    continue

                if (g.direction & HotVectors.bDir.once) {
                    gKey := ObjPtr(g)
                    if (!this.__onceTriggered.Has(gKey))
                        this.__onceTriggered[gKey] := g.callback
                } else {
                    g.callback.Call(sign)
                    this.__gestureFired := true
                }
            }

            ; ── Kümülatif pos ve görsel ──────────────────────────────
            runningPos += sign
            this.__tip.Update(
                this.__BuildLabel(sign, runningPos),
                this.__originX,
                this.__originY + 22   ; imlecin hemen altı
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

    __GetAxisValue(dx, dy) {
        switch this.__lockedDirection {
            case HotVectors.__dirType.strictUp,    HotVectors.__dirType.strictDown:   return dy
            case HotVectors.__dirType.strictRight, HotVectors.__dirType.strictLeft:   return dx
            case HotVectors.__dirType.upRight:    return (dx + dy)  // 2
            case HotVectors.__dirType.upLeft:     return (-dx + dy) // 2
            case HotVectors.__dirType.downRight:  return (dx - dy)  // 2
            case HotVectors.__dirType.downLeft:   return (-dx - dy) // 2
        }
        return 0
    }

    ; ── Aktif gesture'lardan herhangi biri çift yönlü mü? ───────────────
    __IsBidirectional() {
        for g in this.__activeGestures {
            dir := g.direction & ~HotVectors.bDir.once
            if (dir == HotVectors.bDir.upDown || dir == HotVectors.bDir.leftRight)
                return true
        }
        return false
    }

    ; ── Görsel etiket üret ───────────────────────────────────────────────
    ; Tek yönlü:   "↑  UP: +2"
    ; Çift yönlü:  "↕  UP: +2"  veya  "↔  LT: -3"
    ; Çapraz:      "↗  UR: +1"
    __BuildLabel(sign, runningPos) {
        ld    := this.__lockedDirection
        isBidi := this.__IsBidirectional()
        valStr := (runningPos >= 0 ? "+" : "") . runningPos

        switch ld {
            case HotVectors.__dirType.strictUp, HotVectors.__dirType.strictDown:
                prefix  := isBidi ? "↕" : (sign > 0 ? "↑" : "↓")
                dirName := sign > 0 ? "UP" : "DN"
                return prefix . "  " . dirName . ": " . valStr

            case HotVectors.__dirType.strictLeft, HotVectors.__dirType.strictRight:
                prefix  := isBidi ? "↔" : (sign > 0 ? "→" : "←")
                dirName := sign > 0 ? "RT" : "LT"
                return prefix . "  " . dirName . ": " . valStr

            case HotVectors.__dirType.upRight:    return "↗  UR: " . valStr
            case HotVectors.__dirType.upLeft:     return "↖  UL: " . valStr
            case HotVectors.__dirType.downRight:  return "↘  DR: " . valStr
            case HotVectors.__dirType.downLeft:   return "↙  DL: " . valStr
        }
        return "? " . valStr
    }

    __Detect8WayDirection(dx, dy, absDx, absDy) {
        if (absDy < 3 && absDx > 6)
            return dx > 0 ? HotVectors.__dirType.strictRight : HotVectors.__dirType.strictLeft
        if (absDx < 3 && absDy > 6)
            return dy > 0 ? HotVectors.__dirType.strictUp    : HotVectors.__dirType.strictDown
        if (absDx > 4 && absDy > 4)
            return dy > 0
                ? (dx > 0 ? HotVectors.__dirType.upRight   : HotVectors.__dirType.upLeft)
                : (dx > 0 ? HotVectors.__dirType.downRight : HotVectors.__dirType.downLeft)
        if (absDy > absDx)
            return dy > 0 ? HotVectors.__dirType.strictUp    : HotVectors.__dirType.strictDown
        return     dx > 0 ? HotVectors.__dirType.strictRight : HotVectors.__dirType.strictLeft
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
                return bDirFlags == HotVectors.bDir.up     || bDirFlags == HotVectors.bDir.upDown
            case HotVectors.__dirType.strictDown:
                return bDirFlags == HotVectors.bDir.down   || bDirFlags == HotVectors.bDir.upDown
            case HotVectors.__dirType.strictLeft:
                return bDirFlags == HotVectors.bDir.left   || bDirFlags == HotVectors.bDir.leftRight
            case HotVectors.__dirType.strictRight:
                return bDirFlags == HotVectors.bDir.right  || bDirFlags == HotVectors.bDir.leftRight
            case HotVectors.__dirType.upRight:    return bDirFlags == HotVectors.bDir.upRight
            case HotVectors.__dirType.upLeft:     return bDirFlags == HotVectors.bDir.upLeft
            case HotVectors.__dirType.downRight:  return bDirFlags == HotVectors.bDir.downRight
            case HotVectors.__dirType.downLeft:   return bDirFlags == HotVectors.bDir.downLeft
        }
        return false
    }

    __CheckDirection(direction, sign) {
        dir := direction & ~HotVectors.bDir.once
        switch this.__lockedDirection {
            case HotVectors.__dirType.strictUp, HotVectors.__dirType.strictDown:
                if (dir == HotVectors.bDir.upDown)
                  return true
                return (dir == HotVectors.bDir.up   && sign > 0)
                    || (dir == HotVectors.bDir.down  && sign < 0)
            case HotVectors.__dirType.strictLeft, HotVectors.__dirType.strictRight:
                if (dir == HotVectors.bDir.leftRight) 
                  return true
                return (dir == HotVectors.bDir.right && sign > 0)
                    || (dir == HotVectors.bDir.left  && sign < 0)
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
            this.Callback  := callback
        }
    }

    ; VectorTip — unicode destekli, yeniden oluşturmadan güncellenen Gui.
    ; Her Update() çağrısında sadece text + pozisyon değişir, Gui destroy edilmez.
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
            
            ; Çoklu monitör desteği: mevcut monitörün sınırlarını al
            monitorIndex := this.__GetMonitorIndexFromCoords(x, y)
            MonitorGetWorkArea(monitorIndex, &monLeft, &monTop, &monRight, &monBottom)
            
            ; x: imleç merkezine hizala (yaklaşık 120px offset)
            guiX := x - 120
            guiY := y
            
            ; GUI'nin monitör sınırları içinde kalmasını sağla
            guiWidth := 240  ; w240 text control'den
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
            ; Hangi monitörde olduğumuzu tespit et
            Loop MonitorGetCount() {
                MonitorGet(A_Index, &mLeft, &mTop, &mRight, &mBottom)
                if (x >= mLeft && x <= mRight && y >= mTop && y <= mBottom)
                    return A_Index
            }
            return 1  ; Varsayılan olarak birinci monitör
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
