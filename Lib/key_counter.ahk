class KeyCounter {
    static instance := ""

    static getInstance() {
        if (!KeyCounter.instance) {
            KeyCounter.instance := KeyCounter()
        }
        return KeyCounter.instance
    }

    __New() {
        if (KeyCounter.instance) {
            throw Error("KeyCounter zaten oluÅŸturulmuÅŸ! getInstance kullan.")
        }
        this.counts := Map(
            "WriteCount",  0,
            "DoubleCount", 0,
            "LButton",     0,
            "RButton",     0,
            "MButton",     0,
            "F13",         0,
            "F14",         0,
            "F15",         0,
            "F16",         0,
            "F17",         0,
            "F18",         0,
            "F19",         0,
            "F20",         0,
            "CapsLock",    0,
            "Tab",         0,
            "^",           0,
            "ErrorCount",  0,
            "DayCount",    0
        )
    }

    inc(key) {
        if (this.counts.Has(key)) {
            this.counts[key]++
        }
    }

    get(key) {
        return this.counts.Has(key) ? this.counts[key] : 0
    }

    set(key, value) {
        if (this.counts.Has(key)) {
            this.counts[key] := value
        }
    }

    has(key) {
        return this.counts.Has(key)
    }

    getAll() {
        return this.counts
    }

}