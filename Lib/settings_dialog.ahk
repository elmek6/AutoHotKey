; Ayar ekrani: ustte arama, solda kategori, sagda liste.
; Degistirilmis satirlar kalin gosterilir (NM_CUSTOMDRAW).

class SettingsDialog {
    static gui := ""
    static rows := []          ; ListView satir no -> Setting
    static curCat := ""        ; "" = Tumu
    static _hBold := 0
    static _boundNotify := ""

    static show() {
        if (IsObject(SettingsDialog.gui)) {
            SettingsDialog.gui.Show()
            return
        }

        g := Gui("+Resize", "Ayarlar")
        g.SetFont("s10")
        SettingsDialog.gui := g

        g.Add("Text", "x10 y13 w20", "🔎")
        SettingsDialog.search := g.Add("Edit", "x32 y10 w688")
        SettingsDialog.search.OnEvent("Change", (*) => SettingsDialog._refresh())

        SettingsDialog.catList := g.Add("ListBox", "x10 y46 w170 h360 Choose1")
        SettingsDialog.catList.OnEvent("Change", (*) => SettingsDialog._onCategory())

        lv := g.Add("ListView", "x190 y46 w530 h360 -Multi +Grid",
            ["Ayar", "Değer", "Varsayılan", "Açıklama"])
        lv.ModifyCol(1, 175), lv.ModifyCol(2, 95), lv.ModifyCol(3, 85), lv.ModifyCol(4, 155)
        lv.OnEvent("DoubleClick", (*) => SettingsDialog._edit())
        SettingsDialog.lv := lv

        resetBtn := g.Add("Button", "x190 y416 w130 h28", "↺ Seçiliyi sıfırla")
        resetBtn.OnEvent("Click", (*) => SettingsDialog._resetSelected())
        resetAllBtn := g.Add("Button", "x325 y416 w150 h28", "↺ Tümü varsayılana")
        resetAllBtn.OnEvent("Click", (*) => SettingsDialog._resetAll())
        jsonBtn := g.Add("Button", "x480 y416 w140 h28", "📝 settings.json")
        jsonBtn.OnEvent("Click", (*) => SettingsDialog._openJson())
        closeBtn := g.Add("Button", "x625 y416 w95 h28", "Kapat")
        closeBtn.OnEvent("Click", (*) => SettingsDialog._close())

        SettingsDialog.status := g.Add("Text", "x10 y422 w170", "")

        g.OnEvent("Close", (*) => SettingsDialog._close())
        g.OnEvent("Escape", (*) => SettingsDialog._close())

        SettingsDialog._fillCategories()
        SettingsDialog._refresh()
        SettingsDialog._enableBold()
        g.Show("w730 h456")
    }

    static _close() {
        SettingsDialog._disableBold()
        Settings.save()
        if (IsObject(SettingsDialog.gui))
            SettingsDialog.gui.Destroy()
        SettingsDialog.gui := ""
    }

    static _fillCategories() {
        items := ["Tümü (" Settings.all.Length ")"]
        for cat in Settings.catOrder
            items.Push(cat " (" Settings.tree[cat].Length ")")
        SettingsDialog.catList.Delete()
        SettingsDialog.catList.Add(items)
        SettingsDialog.catList.Choose(1)
    }

    static _onCategory() {
        i := SettingsDialog.catList.Value
        SettingsDialog.curCat := (i <= 1) ? "" : Settings.catOrder[i - 1]
        SettingsDialog._refresh()
    }

    static _refresh() {
        q := SettingsDialog.search.Value
        list := Settings.search(q)
        if (q != "")   ; arama varken kategori filtresi devre disi
            SettingsDialog.catList.Choose(1), SettingsDialog.curCat := ""

        lv := SettingsDialog.lv
        lv.Opt("-Redraw")
        lv.Delete()
        SettingsDialog.rows := []
        changed := 0
        for s in list {
            if (SettingsDialog.curCat != "" && s.category != SettingsDialog.curCat)
                continue
            lv.Add(, s.name, SettingsDialog._valueText(s), SettingsDialog._defaultText(s), s.desc)
            SettingsDialog.rows.Push(s)
            if (s.isChanged())
                changed++
        }
        lv.Opt("+Redraw")
        SettingsDialog.status.Value := SettingsDialog.rows.Length " ayar, " changed " değişmiş"
    }

    static _valueText(s) {
        switch s.typeOf() {
            case "action": return "▶ çalıştır"
            case "bool": return s.get() ? "✓ açık" : "✗ kapalı"
        }
        return String(s.get())
    }

    static _defaultText(s) {
        switch s.typeOf() {
            case "action": return ""
            case "bool": return s.default ? "açık" : "kapalı"
        }
        return String(s.default)
    }

    static _selected() {
        r := SettingsDialog.lv.GetNext(0)
        return (r && r <= SettingsDialog.rows.Length) ? SettingsDialog.rows[r] : ""
    }

    static _edit() {
        s := SettingsDialog._selected()
        if (!s)
            return
        switch s.typeOf() {
            case "action":
                if (s.run)
                    s.run.Call()
                return
            case "bool":
                s.toggle()
                SettingsDialog._refresh()
                return
            case "hotkey":
                ShowTip("Bu ayar henüz ekrandan düzenlenemiyor", TipType.Info, 2000)
                return
        }
        SettingsDialog._prompt(s)
    }

    ; Deger duzenleme diyalogu: enum -> DropDownList, digerleri -> Edit
    static _prompt(s) {
        d := Gui("+Owner" SettingsDialog.gui.Hwnd " +ToolWindow", s.name)
        d.SetFont("s10")
        SettingsDialog.gui.Opt("+Disabled")

        d.Add("Text", "x10 y10 w340", s.desc != "" ? s.desc : s.key)
        if (s.typeOf() = "enum") {
            ctrl := d.Add("DropDownList", "x10 y40 w340", s.choices)
            for i, c in s.choices {
                if (c == s.get())
                    ctrl.Value := i
            }
        } else {
            ctrl := d.Add("Edit", "x10 y40 w340", String(s.get()))
        }
        d.Add("Text", "x10 y72 w340", "Varsayılan: " SettingsDialog._defaultText(s))
        errText := d.Add("Text", "x10 y96 w340 cRed", "")

        finish(*) {
            msg := s.set(s.typeOf() = "enum" ? ctrl.Text : ctrl.Value)
            if (msg != "") {
                errText.Value := msg
                return
            }
            close()
            SettingsDialog._refresh()
        }
        close(*) {
            SettingsDialog.gui.Opt("-Disabled")
            d.Destroy()
            SettingsDialog.gui.Show()
        }

        ok := d.Add("Button", "x185 y122 w80 h28 Default", "Tamam")
        ok.OnEvent("Click", finish)
        cancel := d.Add("Button", "x270 y122 w80 h28", "İptal")
        cancel.OnEvent("Click", close)
        d.OnEvent("Close", close)
        d.OnEvent("Escape", close)
        d.Show("w360 h162")
    }

    static _resetSelected() {
        s := SettingsDialog._selected()
        if (!s)
            return
        s.reset()
        SettingsDialog._refresh()
    }

    static _resetAll() {
        if (MsgBox("Tüm ayarlar varsayılana dönecek. Devam?", "Ayarlar", 4 + 32) != "Yes")
            return
        Settings.resetAll()
        SettingsDialog._refresh()
    }

    static _openJson() {
        Settings.saveNow()
        if (FileExist(Path.Settings))
            Run('notepad.exe "' Path.Settings '"')
        else
            ShowTip("Henüz varsayılandan farklı ayar yok", TipType.Info, 2000)
    }

    ; ── Degismis satirlari kalin goster ────────────────────────────────
    static _enableBold() {
        try {
            hFont := SendMessage(0x31, 0, 0, SettingsDialog.lv)   ; WM_GETFONT
            lf := Buffer(92, 0)
            if (!DllCall("GetObject", "ptr", hFont, "int", 92, "ptr", lf))
                return
            NumPut("int", 700, lf, 16)                            ; LOGFONT.lfWeight
            SettingsDialog._hBold := DllCall("CreateFontIndirectW", "ptr", lf, "ptr")
            if (!SettingsDialog._hBold)
                return
            SettingsDialog._boundNotify := ObjBindMethod(SettingsDialog, "_onNotify")
            OnMessage(0x4E, SettingsDialog._boundNotify)          ; WM_NOTIFY
        }
    }

    static _disableBold() {
        if (SettingsDialog._boundNotify) {
            try OnMessage(0x4E, SettingsDialog._boundNotify, 0)
            SettingsDialog._boundNotify := ""
        }
        if (SettingsDialog._hBold) {
            try DllCall("DeleteObject", "ptr", SettingsDialog._hBold)
            SettingsDialog._hBold := 0
        }
    }

    static _onNotify(wParam, lParam, msg, hwnd) {
        if (!IsObject(SettingsDialog.gui) || NumGet(lParam, 0, "ptr") != SettingsDialog.lv.Hwnd)
            return
        if (NumGet(lParam, 2 * A_PtrSize, "int") != -12)          ; NM_CUSTOMDRAW
            return
        stage := NumGet(lParam, 24, "uint")
        if (stage = 1)                                            ; CDDS_PREPAINT
            return 0x20                                           ; CDRF_NOTIFYITEMDRAW
        if (stage = 0x10001) {                                    ; CDDS_ITEMPREPAINT
            row := NumGet(lParam, 56, "uptr") + 1
            if (row <= SettingsDialog.rows.Length && SettingsDialog.rows[row].isChanged()) {
                DllCall("SelectObject", "ptr", NumGet(lParam, 32, "ptr"), "ptr", SettingsDialog._hBold)
                return 0x2                                        ; CDRF_NEWFONT
            }
            return 0
        }
    }
}
