class Item {
    title := ""
    uuid := ""
    category := ""
    text := ""
    tags := []

    __New(title := "", category := "", text := "", tags := []) {
        this.title := title
        this.category := category
        this.text := text
        this.tags := tags
        this.uuid := FormatTime(A_Now, "dd/MM/yyyy_HH:mm") "_" A_TickCount
    }

    ShowInfo() {
        MsgBox("Title: " this.title "`nCategory: " this.category "`n`n" this.text "`n`nTags: " StrJoin(this.tags, ", "))
    }
}

class SingleRepository {
    static instance := ""

    static getInstance() {
        if (!SingleRepository.instance) {
            SingleRepository.instance := SingleRepository()
        }
        return SingleRepository.instance
    }

    __New() {
        if (SingleRepository.instance) {
            throw Error("Repository zaten oluşturulmuş! getInstance kullan.")
        }
        this.items := []
        this.filteredItems := []
        this.tags := []
        this.categories := []
        this.workingItem := ""
        this.loadAll()
        this.updateCategoriesAndTags()

        ; GUI referansları
        this.gui := ""
        this.searchEdit := ""
        this.categoryList := ""
        this.tagList := ""
        this.resultList := ""
        this.uuidLabel := ""
        this.titleEdit := ""
        this.categoryEdit := ""
        this.textEdit := ""
        this.tagsEdit := ""
        this.actionBtn := ""
    }

    __Delete() {
        SingleRepository.instance := ""
    }

    resetFilters() {
        this.filteredItems := this.items.Clone()
        this._updateResultList()
    }

    loadAll() {
        if !FileExist(Path.Repository)
            return false

        try {
            local file := FileOpen(Path.Repository, "r", "UTF-8")
            if (!file) {
                throw Error("repository.json okunamadı")
            }
            local data := file.Read()
            file.Close()

            local loaded := jsongo.Parse(data)

            this.items := []
            for itemData in loaded {
                ; Değerleri önce değişkenlere al
                local itemTitle := ""
                local itemCategory := ""
                local itemText := ""
                local tags := []

                if (itemData.Has("title"))
                    itemTitle := itemData["title"]
                if (itemData.Has("category"))
                    itemCategory := itemData["category"]
                if (itemData.Has("text"))
                    itemText := itemData["text"]
                if (itemData.Has("tags"))
                    tags := itemData["tags"]

                ; Item oluştur
                local newItem := Item(itemTitle, itemCategory, itemText, tags)

                ; UUID'yi sonradan ata
                if (itemData.Has("uuid"))
                    newItem.uuid := itemData["uuid"]

                this.items.Push(newItem)
            }
            return true
        } catch as err {
            App.ErrHandler.handleError("Repository yükleme başarısız: " . err.Message, err)
            this.items := []
            return false
        }
    }

    saveAll() {
        try {
            ; Item class'larını Map'e çevir
            local jsonData := []
            for item in this.items {
                ; item bir Item class
                jsonData.Push(Map(
                    "title", item.title,
                    "category", item.category,
                    "text", item.text,
                    "tags", item.tags,
                    "uuid", item.uuid
                ))
            }

            ; Stringify ve kaydet
            local jsonStr := jsongo.Stringify(jsonData)
            local file := FileOpen(Path.Repository, "w", "UTF-8")
            if (!file) {
                throw Error(Path.Repository . " yazılamadı")
            }
            file.Write(jsonStr)
            file.Close()
            return true
        } catch as err {
            App.ErrHandler.backupOnError("Repository.saveAll!", Path.Repository)
            return false
        }
    }

    AddItem(item) {
        this.items.Push(item)
        this.updateCategoriesAndTags()
        this.resetFilters()
        this.saveAll()
        this._refreshGuiElements()
    }

    UpdateItem(uuid, newTitle, newCategory, newText, newTags) {
        for item in this.items {
            if (item.uuid = uuid) {
                item.title := newTitle
                item.category := newCategory
                item.text := newText
                item.tags := StrSplit(newTags, "`n", "`r")
                this.updateCategoriesAndTags()
                this.resetFilters()
                this.saveAll()
                this._refreshGuiElements()
                return true
            }
        }
        return false
    }

    DeleteItem(uuid) {
        if (MsgBox("Silmek istediğinize emin misiniz?", "Uyarı", "YesNo") = "Yes") {
            newItems := []
            for item in this.items {
                if (item.uuid != uuid) {
                    newItems.Push(item)
                }
            }
            this.items := newItems
            this.updateCategoriesAndTags()
            this.resetFilters()
            this.saveAll()
            this._refreshGuiElements()
        }
    }

    updateCategoriesAndTags() {
        this.categories := []
        this.tags := []
        catMap := Map()
        tagMap := Map()
        for item in this.items {
            ; item artık Item class, Map değil!
            if (!catMap.Has(item.category) && item.category != "") {
                catMap[item.category] := true
                this.categories.Push(item.category)
            }
            for tag in item.tags {
                if (!tagMap.Has(tag) && tag != "") {
                    tagMap[tag] := true
                    this.tags.Push(tag)
                }
            }
        }
        ; Alfabetik sıralama
        this.categories := this._sortArray(this.categories)
        this.tags := this._sortArray(this.tags)
    }

    _sortArray(arr) {
        str := StrJoin(arr, "`n")
        Sort (str)
        return StrSplit(str, "`n", "`r")
    }

    FilterByTag(tagName) {
        results := []
        for item in this.items {
            if (this.HasTagMatch(item.tags, tagName)) {
                results.Push(item)
            }
        }
        return results
    }

    FilterByTags(tagArray, source := this.items) {
        results := []
        for item in source {
            matchAll := true
            for tag in tagArray {
                if (!this.HasTagMatch(item.tags, tag)) {
                    matchAll := false
                    break
                }
            }
            if (matchAll) {
                results.Push(item)
            }
        }
        return results
    }

    FilterByCategory(category, source := this.items) {
        results := []
        for item in source {
            if (item.category = category) {
                results.Push(item)
            }
        }
        return results
    }

    Search(query) {
        results := []
        if (query = "") {
            return this.items.Clone()
        }
        for item in this.items {
            if (RegExMatch(item.title, "i)" query) || RegExMatch(item.category, "i)" query) || RegExMatch(item.text, "i)" query)) {
                results.Push(item)
            }
        }
        return results
    }

    HasTagMatch(tags, query) {
        for tag in tags {
            if (RegExMatch(tag, "i)" query)) {
                return true
            }
        }
        return false
    }

    ShowAllTags() {
        MsgBox("All Tags:`n" StrJoin(this.tags, "`n"))
    }

    showGui() {
        if (this.gui && WinExist("ahk_id " this.gui.hwnd)) {
            this.gui.Show()
            return
        }
        this.gui := Gui("+Resize +MinSize800x500", "Repository Manager")
        this.gui.OnEvent("Close", (*) => this._onGuiClose())
        this.gui.OnEvent("Escape", (*) => this._onGuiClose())
        this.gui.SetFont("s9", "Segoe UI")

        ; Üst: Arama
        this.gui.Add("Text", "x10 y10 w100", "Arama:")
        this.searchEdit := this.gui.Add("Edit", "x120 y10 w760")
        this.searchEdit.OnEvent("Change", (*) => this._applyFilters())

        ; Sol: Kategoriler
        this.gui.Add("Text", "x10 y50 w270", "Kategoriler (Alfabetik):")
        this.categoryList := this.gui.Add("ListBox", "x10 y70 w270 h150 Sort", this.categories)
        this.categoryList.OnEvent("Change", (*) => this._applyFilters())

        ; Sol alt: Tag'ler
        this.gui.Add("Text", "x10 y230 w270", "Tagler (Alfabetik, Çoklu Seç):")
        this.tagList := this.gui.Add("ListBox", "x10 y250 w270 h200 Multi Sort", this.tags)
        this.tagList.OnEvent("Change", (*) => this._applyFilters())

        ; Orta: Sonuçlar
        this.gui.Add("Text", "x290 y50 w290", "Sonuçlar (Başlıklar):")
        this.resultList := this.gui.Add("ListBox", "x290 y70 w290 h400", [])
        this.resultList.OnEvent("DoubleClick", (*) => this._loadItemToDetails())
        this._updateResultList()

        ; Sağ: Detaylar
        this.gui.Add("Text", "x590 y50 w290", "UUID:")
        this.uuidLabel := this.gui.Add("Text", "x590 y70 w290", "(Yeni)")

        this.gui.Add("Text", "x590 y100 w290", "Title:")
        this.titleEdit := this.gui.Add("Edit", "x590 y120 w290")

        this.gui.Add("Text", "x590 y150 w290", "Category:")
        this.categoryEdit := this.gui.Add("Edit", "x590 y170 w290")

        this.gui.Add("Text", "x590 y200 w290", "Text:")
        this.textEdit := this.gui.Add("Edit", "x590 y220 w290 h150 Multi")

        this.gui.Add("Text", "x590 y380 w290", "Tags (Her satır bir tag):")
        this.tagsEdit := this.gui.Add("Edit", "x590 y400 w290 h100 Multi")

        this.actionBtn := this.gui.Add("Button", "x590 y510 w90 h30", "Add")
        this.actionBtn.OnEvent("Click", (*) => this._saveItem())

        refreshBtn := this.gui.Add("Button", "x680 y510 w90 h30", "Refresh")
        refreshBtn.OnEvent("Click", (*) => this._refreshGuiElements())

        delBtn := this.gui.Add("Button", "x770 y510 w90 h30", "Delete")
        delBtn.OnEvent("Click", (*) => this._deleteSelectedItem())

        this.gui.Show("w900 h560")
    }

    _applyFilters() {
        query := this.searchEdit.Value
        selectedCat := this.categoryList.Text
        selectedTags := []
        val := this.tagList.Value
        if (IsObject(val)) {  ; Güvenlik: Value array değilse (boş veya hata) atla
            for idx in val {
                selectedTags.Push(this.tags[idx])
            }
        }

        results := this.Search(query)
        if (selectedCat != "") {
            results := this.FilterByCategory(selectedCat, results)
        }
        if (selectedTags.Length > 0) {
            results := this.FilterByTags(selectedTags, results)
        }

        this.filteredItems := results
        this._updateResultList()
    }

    _updateResultList() {
        if (!this.resultList)
            return
        this.resultList.Delete()
        for item in this.filteredItems {
            this.resultList.Add([item.title " (" item.category ")"])
        }
    }

    _loadItemToDetails() {
        sel := this.resultList.Value
        if (sel < 1 || sel > this.filteredItems.Length) {
            return
        }
        item := this.filteredItems[sel]
        this.workingItem := item.uuid
        this.uuidLabel.Text := item.uuid
        this.titleEdit.Value := item.title
        this.categoryEdit.Value := item.category
        this.textEdit.Value := item.text
        this.tagsEdit.Value := StrJoin(item.tags, "`n")
        this.actionBtn.Text := "Update"
    }

    _saveItem() {
        title := Trim(this.titleEdit.Value)
        category := Trim(this.categoryEdit.Value)
        text := Trim(this.textEdit.Value)
        tagsStr := Trim(this.tagsEdit.Value)
        tags := StrSplit(tagsStr, "`n", "`r")

        if (title = "") {
            ShowTip("Title zorunlu!", TipType.Error, 2000)
            return
        }

        if (this.workingItem = "") {
            newItem := Item(title, category, text, tags)
            this.AddItem(newItem)
            ShowTip("Eklendi!", TipType.Success)
        } else {
            this.UpdateItem(this.workingItem, title, category, text, tagsStr)
            ShowTip("Güncellendi!", TipType.Success)
        }
        this._clearDetails()
    }

    _deleteSelectedItem() {
        if (this.workingItem = "") {
            ShowTip("Silmek için item seçin!", TipType.Warning, 2000)
            return
        }
        this.DeleteItem(this.workingItem)
        this._clearDetails()
    }

    _clearDetails() {
        this.workingItem := ""
        this.uuidLabel.Text := "(Yeni)"
        this.titleEdit.Value := ""
        this.categoryEdit.Value := ""
        this.textEdit.Value := ""
        this.tagsEdit.Value := ""
        this.actionBtn.Text := "Add"
    }

    _refreshGuiElements() {
        this.updateCategoriesAndTags()
        this.categoryList.Delete()
        this.categoryList.Add(this.categories)
        this.tagList.Delete()
        this.tagList.Add(this.tags)
        this._applyFilters()
    }

    _onGuiClose() {
        ; GUI kapanırken save YAPMA
        this.gui.Destroy()
        this.gui := ""
        this.searchEdit := ""
        this.categoryList := ""
        this.tagList := ""
        this.resultList := ""
        this.uuidLabel := ""
        this.titleEdit := ""
        this.categoryEdit := ""
        this.textEdit := ""
        this.tagsEdit := ""
        this.actionBtn := ""
    }
}

; Helper: StrJoin
StrJoin(arr, delim) {
    str := ""
    for i, v in arr {
        str .= (i > 1 ? delim : "") v
    }
    return str
}