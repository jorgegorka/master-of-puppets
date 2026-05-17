import { Controller } from "@hotwired/stimulus"
import Chart from "chart.js"

export default class extends Controller {
  static values = { type: String, data: Object }

  connect() {
    const canvas = this.element.querySelector("canvas")
    this.chart = new Chart(canvas, this.#config())
  }

  disconnect() { this.chart?.destroy() }

  #config() {
    if (this.typeValue === "line") {
      const rows = Array.isArray(this.dataValue) ? this.dataValue : []
      return {
        type: "line",
        data: {
          labels: rows.map(r => r.day),
          datasets: [{ label: "Tokens", data: rows.map(r => r.tokens) }]
        }
      }
    }
    if (this.typeValue === "bar") {
      const rows = this.dataValue || {}
      return {
        type: "bar",
        data: {
          labels: Object.keys(rows),
          datasets: [{ label: "Cost (USD)", data: Object.values(rows) }]
        }
      }
    }
    return { type: this.typeValue, data: {} }
  }
}
