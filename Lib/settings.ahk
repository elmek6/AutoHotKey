; Ayar sistemi. Tanim dagitik (her modul kendi ayarini yaninda tanimlar),
; kayit merkezi. Deger okuma HER ZAMAN get() uzerinden olmali.
;
; static prefX := Setting({ key:"modul.ad", name:"Gorunen ad", default:14,
;                           category:Cat.Fare, tags:"fare hassasiyet",
;                           desc:"", kind:"", choices:[], validate:"", onChange:"" })
;   kind : "" (default'tan cikarilir) | "bool" | "hotkey" (rezerve)
;          AHK'da true = 1 oldugu icin mantiksal ayarlarda kind:"bool" ZORUNLU
;   validate(v) : "" = gecerli, dolu string = ret gerekcesi
;   onChange / subscribe(cb) : cb(yeni, eski) - sadece bildirim, ret edemez

class Cat {
    static Genel := "Genel"
    static Fare := "Fare"
    static Macro := "Macro"
    static Pano := "Pano"
    static Liste := "Liste"
    static Pencere := "Pencere"
}

class Setting {
    __New(def) {
        this.key := def.key
        this.name := def.name
        this.default := def.default
        this.category := def.HasProp("category") ? def.category : Cat.Genel
        this.kind := def.HasProp("kind") ? def.kind : ""
        this.tags := def.HasProp("tags") ? def.tags : ""
        this.desc := def.HasProp("desc") ? def.desc : ""
        this.choices := def.HasProp("choices") ? def.choices : []
        this.validate := def.HasProp("validate") ? def.validate : ""
        this.isAction := false
        this._subs := []
        this._value := this.default
        if (def.HasProp("onChange") && def.onChange)
            this._subs.Push(def.onChange)
        Settings.register(this)
    }

    ; "bool" | "enum" | "int" | "float" | "str" | "hotkey"
    typeOf() {
        if (this.kind != "")
            return this.kind
        if (this.choices.Length)
            return "enum"
        switch Type(this.default) {
            case "Integer": return "int"
            case "Float": return "float"
        }
        return "str"
    }

    get() => this._value
    isChanged() => this._value != this.default

    ; "" = basarili, dolu string = ret gerekcesi
    set(v) {
        ok := true
        v := this._coerce(v, &ok)
        if (!ok)
            return "Gecersiz deger: " this.name
        if (this.validate) {
            msg := this.validate.Call(v)
            if (msg != "")
                return msg
        }
        old := this._value
        if (old == v)
            return ""
        this._value := v
        Settings.dirty := true
        this._notify(v, old)
        return ""
    }

    toggle() => this.set(this.get() ? 0 : 1)
    reset() => this.set(this.default)

    subscribe(cb) {
        this._subs.Push(cb)
        return cb
    }

    unsubscribe(cb) {
        for i, c in this._subs {
            if (c == cb) {
                this._subs.RemoveAt(i)
                return
            }
        }
    }

    _notify(val, old) {
        for cb in this._subs {
            try {
                cb.Call(val, old)
            } catch as err {
                App.ErrHandler.handleError("Setting dinleyici hatasi: " this.key, err)
            }
        }
    }

    ; Bozuk/elle duzenlenmis json'a karsi: tip tutmuyorsa ok=false, default doner
    _coerce(v, &ok) {
        ok := true
        switch this.typeOf() {
            case "bool":
                if (v = 1 || v = "true")
                    return 1
                if (v = 0 || v = "false")
                    return 0
                ok := false
                return this.default
            case "int":
                if (IsInteger(v))
                    return Integer(v)
                ok := false
                return this.default
            case "float":
                if (IsNumber(v))
                    return Float(v)
                ok := false
                return this.default
            case "enum":
                for c in this.choices {
                    if (c == v)
                        return v
                }
                ok := false
                return this.default
        }
        return String(v)
    }
}

; Ayar ekraninda dugme satiri: deger tutmaz, cift tiklaninca run() calisir
class SettingAction {
    __New(def) {
        this.key := def.key
        this.name := def.name
        this.category := def.HasProp("category") ? def.category : Cat.Genel
        this.tags := def.HasProp("tags") ? def.tags : ""
        this.desc := def.HasProp("desc") ? def.desc : ""
        this.choices := []
        this.run := def.HasProp("run") ? def.run : ""
        this.isAction := true
        Settings.register(this)
    }
    typeOf() => "action"
    get() => ""
    isChanged() => false
    reset() => ""
    _notify(a, b) => ""
}

class Settings {
    static VERSION := 1
    static all := []
    static byKey := Map()
    static tree := Map()        ; kategori -> [Setting]
    static catOrder := []       ; Map siralamasina guvenme, tanim sirasi burada
    static dirty := false
    static _orphans := Map()    ; su an include edilmemis modulun ayari - silinmesin

    static register(s) {
        if (Settings.byKey.Has(s.key))
            throw Error("Ayar anahtari iki kez tanimlanmis: " s.key)
        Settings.byKey[s.key] := s
        Settings.all.Push(s)
        if (!Settings.tree.Has(s.category)) {
            Settings.tree[s.category] := []
            Settings.catOrder.Push(s.category)
        }
        Settings.tree[s.category].Push(s)
    }

    static has(key) => Settings.byKey.Has(key)
    static item(key) => Settings.byKey.Has(key) ? Settings.byKey[key] : ""
    static get(key) => Settings.byKey.Has(key) ? Settings.byKey[key].get() : ""

    static load() {
        if (!FileExist(Path.Settings))
            return false
        try {
            local file := FileOpen(Path.Settings, "r", "UTF-8")
            if (!file)
                throw Error("settings.json okunamadi")
            local data := file.Read()
            file.Close()

            local root := jsongo.Parse(data)
            if (!(root is Map) || !root.Has("values"))
                return false

            for key, raw in root["values"] {
                if (!Settings.byKey.Has(key)) {
                    Settings._orphans[key] := raw
                    continue
                }
                local s := Settings.byKey[key]
                if (s.isAction)
                    continue
                local ok := true
                local v := s._coerce(raw, &ok)
                s._value := ok ? v : s.default
                if (!ok)
                    Settings.dirty := true
            }
            return true
        } catch as err {
            App.ErrHandler.handleError("Settings.load basarisiz: " err.Message, err)
            return false
        }
    }

    ; load() sonrasi BIR KEZ cagrilmali, yoksa moduller kodun icindeki
    ; sabitlerle calismaya devam eder ("ayar kaydediliyor ama etkisi yok")
    static applyAll() {
        for s in Settings.all
            s._notify(s.get(), s.get())
    }

    static save() => Settings.dirty ? Settings.saveNow() : false

    static saveNow() {
        try {
            local values := Map()
            for key, raw in Settings._orphans
                values[key] := raw
            for s in Settings.all {
                if (s.isChanged())
                    values[s.key] := s.get()
            }
            local root := Map("_v", Settings.VERSION, "values", values)
            FileIO.writeText(Path.Settings, jsongo.Stringify(root, , 2), "UTF-8")
            Settings.dirty := false
            return true
        } catch as err {
            App.ErrHandler.backupOnError("Settings.saveNow!", Path.Settings)
            return false
        }
    }

    static resetAll() {
        for s in Settings.all
            s.reset()
    }

    ; arama: bosluk = AND, name + key + desc + tags + choices icinde
    static search(query) {
        local out := []
        query := Trim(query)
        if (query == "")
            return Settings.all.Clone()
        local terms := StrSplit(query, " ", " `t")
        for s in Settings.all {
            local hay := s.name " " s.key " " s.desc " " s.tags " " s.category
            for c in s.choices
                hay .= " " c
            local hit := true
            for t in terms {
                if (t == "")
                    continue
                if (!InStr(hay, t)) {
                    hit := false
                    break
                }
            }
            if (hit)
                out.Push(s)
        }
        return out
    }
}
