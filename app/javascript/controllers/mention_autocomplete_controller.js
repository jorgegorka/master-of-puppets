import { Controller } from "@hotwired/stimulus"

// @-mention picker. Watches the textarea for an "@token" preceded by whitespace
// or start-of-input, queries /roles.json?q=token, and lets the user pick a role
// to insert as "@Role Title " (matching the substring rule in Triggerable).
export default class extends Controller {
  static targets = ["input", "panel", "list", "empty"]
  static values = { url: { type: String, default: "/roles.json" }, debounce: { type: Number, default: 120 } }

  connect() {
    this.results = []
    this.activeIndex = -1
    this.mentionStart = -1
    this.query = ""
    this.lastFetchedQuery = null
    this.inflight = null
    this.searchTimer = null
    this.onDocumentClick = this.onDocumentClick.bind(this)
    document.addEventListener("click", this.onDocumentClick)
  }

  disconnect() {
    document.removeEventListener("click", this.onDocumentClick)
    clearTimeout(this.searchTimer)
    this.abortInflight()
  }

  onInput() {
    this.updateMentionState()
    if (this.mentionStart < 0) {
      this.close()
      return
    }
    this.scheduleSearch()
  }

  onKeydown(event) {
    if (this.panelTarget.hidden) return
    switch (event.key) {
      case "ArrowDown":
        event.preventDefault()
        this.move(1)
        break
      case "ArrowUp":
        event.preventDefault()
        this.move(-1)
        break
      case "Enter":
      case "Tab":
        if (this.activeIndex >= 0 && this.results.length > 0) {
          event.preventDefault()
          this.applyResult(this.results[this.activeIndex])
        }
        break
      case "Escape":
        event.preventDefault()
        this.close()
        break
    }
  }

  onSelect(event) {
    event.preventDefault()
    const idx = parseInt(event.currentTarget.dataset.index, 10)
    if (Number.isNaN(idx)) return
    this.applyResult(this.results[idx])
    this.inputTarget.focus()
  }

  // The trigger token is the longest run of non-whitespace characters ending
  // at the caret that follows an "@" itself preceded by whitespace or BOF.
  updateMentionState() {
    const value = this.inputTarget.value
    const cursor = this.inputTarget.selectionStart ?? value.length

    for (let i = cursor - 1; i >= 0; i--) {
      const ch = value[i]
      if (ch === "@") {
        const prev = i === 0 ? "" : value[i - 1]
        if (i === 0 || /\s/.test(prev)) {
          this.mentionStart = i
          this.query = value.slice(i + 1, cursor)
          return
        }
        break
      }
      if (/\s/.test(ch)) break
    }
    this.mentionStart = -1
    this.query = ""
  }

  scheduleSearch() {
    clearTimeout(this.searchTimer)
    this.searchTimer = setTimeout(() => this.runSearch(), this.debounceValue)
  }

  async runSearch() {
    if (this.query === this.lastFetchedQuery) return

    this.abortInflight()
    const controller = new AbortController()
    this.inflight = controller
    const fetchedQuery = this.query

    const url = new URL(this.urlValue, window.location.origin)
    if (fetchedQuery) url.searchParams.set("q", fetchedQuery)

    try {
      const response = await fetch(url, {
        headers: { Accept: "application/json" },
        credentials: "same-origin",
        signal: controller.signal
      })
      if (!response.ok) {
        this.close()
        return
      }
      const results = await response.json()
      if (controller.signal.aborted) return
      this.lastFetchedQuery = fetchedQuery
      this.renderResults(Array.isArray(results) ? results : [])
    } catch (error) {
      if (error.name !== "AbortError") this.close()
    }
  }

  renderResults(results) {
    this.results = results
    this.listTarget.replaceChildren()

    if (results.length === 0) {
      if (this.hasEmptyTarget) this.emptyTarget.hidden = false
      this.activeIndex = -1
      this.panelTarget.hidden = false
      return
    }

    if (this.hasEmptyTarget) this.emptyTarget.hidden = true
    results.forEach((role, idx) => {
      const button = document.createElement("button")
      button.type = "button"
      button.className = "mention-autocomplete__item"
      button.dataset.action = "mousedown->mention-autocomplete#onSelect"
      button.dataset.index = idx
      button.textContent = role.title
      this.listTarget.appendChild(button)
    })
    this.activeIndex = 0
    this.updateActive()
    this.panelTarget.hidden = false
  }

  applyResult(role) {
    if (!role) return
    const value = this.inputTarget.value
    const cursor = this.inputTarget.selectionStart ?? value.length
    const before = value.slice(0, this.mentionStart)
    const after = value.slice(cursor)
    const insert = `@${role.title} `

    this.inputTarget.value = before + insert + after
    const newCursor = before.length + insert.length
    this.inputTarget.setSelectionRange(newCursor, newCursor)
    this.close()
    this.inputTarget.dispatchEvent(new Event("input", { bubbles: true }))
  }

  move(delta) {
    if (this.results.length === 0) return
    const len = this.results.length
    this.activeIndex = (this.activeIndex + delta + len) % len
    this.updateActive()
  }

  updateActive() {
    const items = this.listTarget.querySelectorAll(".mention-autocomplete__item")
    items.forEach((el, idx) => {
      const active = idx === this.activeIndex
      el.classList.toggle("mention-autocomplete__item--active", active)
      if (active) el.scrollIntoView({ block: "nearest" })
    })
  }

  close() {
    this.panelTarget.hidden = true
    this.activeIndex = -1
    this.results = []
    this.listTarget.replaceChildren()
    if (this.hasEmptyTarget) this.emptyTarget.hidden = true
    this.mentionStart = -1
    this.query = ""
    this.lastFetchedQuery = null
    this.abortInflight()
  }

  abortInflight() {
    if (this.inflight) {
      this.inflight.abort()
      this.inflight = null
    }
  }

  onDocumentClick(event) {
    if (!this.element.contains(event.target)) this.close()
  }
}
