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

class singleRepository {
    static instance := ""

    static getInstance() {
        if (!singleRepository.instance) {
            singleRepository.instance := singleRepository()
        }
        return singleRepository.instance
    }

    __New() {
        if (singleRepository.instance) {
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
        this._gui := ""
        this._searchEdit := ""
        this._categoryList := ""
        this._tagList := ""
        this._resultList := ""
        this._uuidLabel := ""
        this._titleEdit := ""
        this._categoryEdit := ""
        this._textEdit := ""
        this._tagsEdit := ""
        this._actionBtn := ""
    }

    resetFilters() {
        this.filteredItems := this.items.Clone()
        this._updateResultList()
    }

    loadAll() {
        if !FileExist(AppConst.FILE_REPO)
            return false

        try {
            local file := FileOpen(AppConst.FILE_REPO, "r", "UTF-8")
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
            gErrHandler.handleError("Repository yükleme başarısız: " . err.Message, err)
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
            local file := FileOpen(AppConst.FILE_REPO, "w", "UTF-8")
            if (!file) {
                throw Error(AppConst.FILE_REPO . " yazılamadı")
            }
            file.Write(jsonStr)
            file.Close()
            return true
        } catch as err {
            gErrHandler.handleError("Repository kaydetme başarısız: " . err.Message, err)
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
        if (this._gui && WinExist("ahk_id " this._gui.hwnd)) {
            this._gui.Show()
            return
        }
        this._gui := Gui("+Resize +MinSize800x500", "Repository Manager")
        this._gui.OnEvent("Close", (*) => this._onGuiClose())
        this._gui.OnEvent("Escape", (*) => this._onGuiClose())
        this._gui.SetFont("s9", "Segoe UI")

        ; Üst: Arama
        this._gui.Add("Text", "x10 y10 w100", "Arama:")
        this._searchEdit := this._gui.Add("Edit", "x120 y10 w760")
        this._searchEdit.OnEvent("Change", (*) => this._applyFilters())

        ; Sol: Kategoriler
        this._gui.Add("Text", "x10 y50 w270", "Kategoriler (Alfabetik):")
        this._categoryList := this._gui.Add("ListBox", "x10 y70 w270 h150 Sort", this.categories)
        this._categoryList.OnEvent("Change", (*) => this._applyFilters())

        ; Sol alt: Tag'ler
        this._gui.Add("Text", "x10 y230 w270", "Tagler (Alfabetik, Çoklu Seç):")
        this._tagList := this._gui.Add("ListBox", "x10 y250 w270 h200 Multi Sort", this.tags)
        this._tagList.OnEvent("Change", (*) => this._applyFilters())

        ; Orta: Sonuçlar
        this._gui.Add("Text", "x290 y50 w290", "Sonuçlar (Başlıklar):")
        this._resultList := this._gui.Add("ListBox", "x290 y70 w290 h400", [])
        this._resultList.OnEvent("DoubleClick", (*) => this._loadItemToDetails())
        this._updateResultList()

        ; Sağ: Detaylar
        this._gui.Add("Text", "x590 y50 w290", "UUID:")
        this._uuidLabel := this._gui.Add("Text", "x590 y70 w290", "(Yeni)")

        this._gui.Add("Text", "x590 y100 w290", "Title:")
        this._titleEdit := this._gui.Add("Edit", "x590 y120 w290")

        this._gui.Add("Text", "x590 y150 w290", "Category:")
        this._categoryEdit := this._gui.Add("Edit", "x590 y170 w290")

        this._gui.Add("Text", "x590 y200 w290", "Text:")
        this._textEdit := this._gui.Add("Edit", "x590 y220 w290 h150 Multi")

        this._gui.Add("Text", "x590 y380 w290", "Tags (Her satır bir tag):")
        this._tagsEdit := this._gui.Add("Edit", "x590 y400 w290 h100 Multi")

        this._actionBtn := this._gui.Add("Button", "x590 y510 w90 h30", "Add")
        this._actionBtn.OnEvent("Click", (*) => this._saveItem())

        refreshBtn := this._gui.Add("Button", "x680 y510 w90 h30", "Refresh")
        refreshBtn.OnEvent("Click", (*) => this._refreshGuiElements())

        delBtn := this._gui.Add("Button", "x770 y510 w90 h30", "Delete")
        delBtn.OnEvent("Click", (*) => this._deleteSelectedItem())

        this._gui.Show("w900 h560")
    }

    _applyFilters() {
        query := this._searchEdit.Value
        selectedCat := this._categoryList.Text
        selectedTags := []
        val := this._tagList.Value
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
        if (!this._resultList)
            return
        this._resultList.Delete()
        for item in this.filteredItems {
            this._resultList.Add([item.title " (" item.category ")"])
        }
    }

    _loadItemToDetails() {
        sel := this._resultList.Value
        if (sel < 1 || sel > this.filteredItems.Length) {
            return
        }
        item := this.filteredItems[sel]
        this.workingItem := item.uuid
        this._uuidLabel.Text := item.uuid
        this._titleEdit.Value := item.title
        this._categoryEdit.Value := item.category
        this._textEdit.Value := item.text
        this._tagsEdit.Value := StrJoin(item.tags, "`n")
        this._actionBtn.Text := "Update"
    }

    _saveItem() {
        title := Trim(this._titleEdit.Value)
        category := Trim(this._categoryEdit.Value)
        text := Trim(this._textEdit.Value)
        tagsStr := Trim(this._tagsEdit.Value)
        tags := StrSplit(tagsStr, "`n", "`r")

        if (title = "") {
            MsgBox("Title zorunlu!")
            return
        }

        if (this.workingItem = "") {
            newItem := Item(title, category, text, tags)
            this.AddItem(newItem)
            ToolTip("Eklendi!")
        } else {
            this.UpdateItem(this.workingItem, title, category, text, tagsStr)
            ToolTip("Güncellendi!")
        }
        SetTimer(() => ToolTip(), -1000)
        this._clearDetails()
    }

    _deleteSelectedItem() {
        if (this.workingItem = "") {
            MsgBox("Silmek için item seçin!")
            return
        }
        this.DeleteItem(this.workingItem)
        this._clearDetails()
    }

    _clearDetails() {
        this.workingItem := ""
        this._uuidLabel.Text := "(Yeni)"
        this._titleEdit.Value := ""
        this._categoryEdit.Value := ""
        this._textEdit.Value := ""
        this._tagsEdit.Value := ""
        this._actionBtn.Text := "Add"
    }

    _refreshGuiElements() {
        this.updateCategoriesAndTags()
        this._categoryList.Delete()
        this._categoryList.Add(this.categories)
        this._tagList.Delete()
        this._tagList.Add(this.tags)
        this._applyFilters()
    }

    _onGuiClose() {
        ; GUI kapanırken save YAPMA
        this._gui.Destroy()
        this._gui := ""
        this._searchEdit := ""
        this._categoryList := ""
        this._tagList := ""
        this._resultList := ""
        this._uuidLabel := ""
        this._titleEdit := ""
        this._categoryEdit := ""
        this._textEdit := ""
        this._tagsEdit := ""
        this._actionBtn := ""
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