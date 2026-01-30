class singleQuickMenu {
    static instance := ""

    static getInstance() {
        if (!singleQuickMenu.instance) {
            singleQuickMenu.instance := singleQuickMenu()
        }
        return singleQuickMenu.instance
    }

    __New() {
        if (singleQuickMenu.instance) {
            throw Error("QuickMenu zaten oluşturulmuş! getInstance kullan.")
        }
    }

    ; Basit liste göster, callback'e seçilen text ve index döner
    Show(items, callback, title := "") {
        qm := Menu()

        if (title != "") {
            qm.Add(title, (*) => 0)
            qm.Disable(title)
            qm.Add()
        }

        for i, item in items {
            local text := IsObject(item) && item.Has("text") ? item.text : item
            local key := IsObject(item) && item.Has("key") ? item.key : i
            local display := key ": " text
            qm.Add(display, ((t, idx) => (*) => callback(t, idx))(text, i))
        }

        qm.Show()
    }

    ; Komut menüsü (sysCommands alternatifi)
    ; Commands(commandMap) {
    ;     qm := Menu()

    ;     for key, cmd in commandMap {
    ;         local display := cmd.Has("key") ? cmd.key ": " cmd.desc : key ": " cmd.desc
    ;         qm.Add(display, ((a) => (*) => a.Call())(cmd.action))
    ;     }

    ;     qm.Show()
    ; }
}