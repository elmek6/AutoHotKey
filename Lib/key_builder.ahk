; Ortak KeyBuilder - Hem Cascade hem Hotkey için tek yapı
class KeyBuilder {
    __New(short := 350, long := "", gap := "") {
        this.shortTime := short
        this.longTime := long
        this.gapTime := gap

        this.main_key := ""
        this.main_start := ""
        this.main_end := ""

        this.combos := []
        this._tips := []

        this.previewCallback := ""
        this.exitOnPressType := -1

        this.gestures := []
        this._extensions := []
    }

    ; Basım türü ayarları: short, long (opsiyonel), gap (double click için opsiyonel)
    setPressType(short := 350, long := "", gap := "") {
        this.shortTime := short
        this.longTime := long
        this.gapTime := gap
        return this
    }

    mainKey(fn) {
        this.main_key := fn
        return this
    }

    mainStart(fn) {
        this.main_start := fn
        return this
    }

    mainEnd(fn) {
        this.main_end := fn
        return this
    }

    ; Metod adı aynı kaldı: combos() – fluent interface bozulmasın diye
    combo(key, desc, fn) {
        this.combos.Push({ key: key, desc: desc, action: fn })
        this._tips.Push(key ": " desc)
        return this
    }

    setPreview(callback) {
        if (IsObject(callback)) {
            this.previewCallback := callback
        } else {
            throw Error("setPreview: Callback bir fonksiyon olmalı!")
        }
        return this
    }

    setExitOnPressType(type) {
        this.exitOnPressType := type
        return this
    }

    extend(extObj) {
        this._extensions.Push(extObj)
        return this ; Zincirleme kullanım için 'this' dönüyoruz
    }
    extensions => this._extensions

    build() {
        return this
    }

    tips {
        get => this._tips
    }

    ; Static metod olarak getPressType
    static getPressType(duration, shortTime, longTime) {
        if (longTime == "") {
            return (duration <= shortTime) ? 1 : 2
        }
        if (duration <= shortTime) {
            return 1 ; Short press
        } else if (duration < longTime) {
            return 2 ; Medium press
        } else {
            return 3 ; Long press
        }
    }
}
