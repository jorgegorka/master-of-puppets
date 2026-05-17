import { Controller } from "@hotwired/stimulus"

// Wires an <input> to a Turbo Frame whose `src` updates as the user types,
// so /skills?q=<query> renders into the frame inline. 200ms debounce.
export default class extends Controller {
  static values = { url: String, frame: String, debounce: { type: Number, default: 200 } }

  connect() { this._timer = null }
  disconnect() { clearTimeout(this._timer) }

  update(event) {
    clearTimeout(this._timer)
    this._timer = setTimeout(() => this.#submit(event.target.value), this.debounceValue)
  }

  #submit(value) {
    const frame = document.getElementById(this.frameValue)
    if (!frame) return
    const url = new URL(this.urlValue, window.location.origin)
    url.searchParams.set("q", value)
    frame.src = url.toString()
  }
}
