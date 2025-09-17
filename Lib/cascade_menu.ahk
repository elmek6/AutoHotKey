class cascadeBuilder {
	__New() {
		this._mainStart := ""
		this._mainDefault := ""
		this._mainEnd := ""
		this.shortTime := 500		
		; this.longTime := 1400		
		this.pairs := []
		this.tips := []
	}

	

	shortKey(fn) {
		this._mainStart := fn
		return this
	}

	longKey(fn) {
		this._mainStart := fn
		return this
	}

    setPreview(list := []) {
        this.tips := list
        return this.tips
    }

	pairs{key, desc, fn} {
		
	}
}


class CascadeMenu {
	static instance := ""

	static getInstance(short, long) {
		if (!CascadeMenu.instance) {
			CascadeMenu.instance := CascadeMenu(short, long)
		}
		return CascadeMenu.instance
	}

	__New() {
		if (CascadeMenu.instance) {
			throw Error("CascadeMenu zaten oluşturulmuş! getInstance kullan.")
		}
	}

	handleKey(key) {
		static builder := FKeyBuilder()
			.mainDefault(this.handleDefault.bind(this, key))
		this.CascadeKey(builder, key)
	}

	handleDefault(key) {
		startTime := A_TickCount
		if (SubStr(key, 1, 1) == "~") {
			key := SubStr(key, 2)
		}

		; InputHook: 5 saniye boyunca 1 tuş bekler, Esc ile çıkılır
		ih := InputHook("L1 T5", "{Esc}")
		ih.Start()

		beepCount := 1
		longPressTriggered := false

		; Tuş basılıyken kontrol
		while (GetKeyState(key, "P")) {
			duration := A_TickCount - startTime

			; Uzun basma (≥ 300ms): SoundBeep ile uyarı
			if (duration >= 300 && beepCount > 0) {
				SoundBeep(600, 100)
				beepCount--
				longPressTriggered := true
				OutputDebug("LONG press detected (" duration " ms)`n")
				; Opsiyonel: Uzun basmada dur
				; if (true) {
				;     ih.Stop()
				;     return
				; }
			}

			; Birlikte basılan yancı tuş kontrolü
			if (ih.Input != "" || ih.EndKey != "") {
				pressedKey := ih.Input != "" ? ih.Input : ih.EndKey
				OutputDebug("Pressed together with key: " key "_" pressedKey "`n")
				ih.Stop()
				return
			}

			Sleep(10)
		}

		; Tuş bırakıldıktan sonra
		duration := A_TickCount - startTime

		; Kısa veya uzun basma
		if (duration < 300) {
			OutputDebug("SHORT press (" duration " ms)`n")
			; Opsiyonel: Kısa basmada dur
			; if (true) {
			;     ih.Stop()
			;     return
			; }
		} else if (!longPressTriggered) {
			OutputDebug("LONG press (" duration " ms)`n")
		}

		; Sonradan basılan yancı tuş kontrolü
		ih.Wait(0.2) ; 0.2 saniye bekle
		if (ih.Input != "" || ih.EndKey != "") {
			pressedKey := ih.Input != "" ? ih.Input : ih.EndKey
			OutputDebug("Pressed after release: " key "_" pressedKey "`n")
		}

		ih.Stop()
	}

	CascadeKey(builder, key) {
		mainDefault := builder._mainDefault

		if (state.getBusy() > 0) {
			OutputDebug("Busy state, ignoring key: " key "`n")
			return
		}

		try {
			state.setBusy(1)
			keyCounts.inc(key)

			if (mainDefault != "" && IsObject(mainDefault)) {
				mainDefault.Call()
			}
		} catch Error as err {
			errHandler.handleError(err.Message " " key)
		} finally {
			state.setBusy(0)
		}
	}
}