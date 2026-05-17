import { Controller } from "@hotwired/stimulus"

// Listens to the cron <input>, debounces 200ms, fetches the cron_preview
// endpoint with ?cron=… and writes the next-run-at into a sibling <output>
// target. On invalid cron the server returns 422 with { error: msg }; the
// controller renders that instead.
export default class extends Controller {
  static values  = { url: String, debounce: { type: Number, default: 200 } }
  static targets = [ "input", "result" ]

  connect() { this._timer = null }
  disconnect() { clearTimeout(this._timer) }

  update() {
    clearTimeout(this._timer)
    this._timer = setTimeout(() => this.#fetch(), this.debounceValue)
  }

  async #fetch() {
    const value = this.inputTarget.value.trim()
    if (!value) { this.resultTarget.textContent = ""; return }

    const url = new URL(this.urlValue, window.location.origin)
    url.searchParams.set("cron", value)

    try {
      const response = await fetch(url, { headers: { "Accept": "application/json" } })
      const data     = await response.json()
      if (response.ok) {
        this.resultTarget.textContent = `Next fire: ${data.next_run_at}`
      } else {
        this.resultTarget.textContent = `Invalid: ${data.error}`
      }
    } catch (e) {
      this.resultTarget.textContent = ""
    }
  }
}
