import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { theme: String, accent: String, persistUrl: String }
  static targets = [ "themeSelect", "accentSelect" ]

  connect() {
    this.apply()
  }

  select(event) {
    const target = event.target
    if (target.dataset.themeKind === "theme")  this.themeValue  = target.value
    if (target.dataset.themeKind === "accent") this.accentValue = target.value
    this.apply()
    this.persist()
  }

  apply() {
    if (this.themeValue)  document.documentElement.dataset.theme  = this.themeValue
    if (this.accentValue) document.documentElement.dataset.accent = this.accentValue
  }

  async persist() {
    if (!this.persistUrlValue) return
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    await fetch(this.persistUrlValue, {
      method: "PATCH",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": token, "Accept": "application/json" },
      body: JSON.stringify({ user_setting: { theme: this.themeValue, accent: this.accentValue } })
    })
  }
}
