import { Controller } from "@hotwired/stimulus"
import { patch, post } from "@rails/request.js"

export default class extends Controller {
  static targets = [
    "card", "column", "count",
    "checkbox", "toolbar", "selectedCount",
    "idsField"
  ]
  static values = { updateUrl: String }

  connect() {
    this.selected = new Set()
    this.refreshSelectionUI()
  }

  toggleSelection(event) {
    const checkbox = event.currentTarget
    const id = checkbox.value
    if (checkbox.checked) {
      this.selected.add(id)
    } else {
      this.selected.delete(id)
    }
    this.refreshSelectionUI()
  }

  refreshSelectionUI() {
    const count = this.selected.size
    if (this.hasSelectedCountTarget) {
      this.selectedCountTarget.textContent = count
    }
    if (this.hasToolbarTarget) {
      this.toolbarTarget.hidden = count === 0
    }
    const csv = Array.from(this.selected).join(",")
    this.idsFieldTargets.forEach(field => { field.value = csv })

    this.cardTargets.forEach(card => {
      card.classList.toggle("kanban-card--selected", this.selected.has(card.dataset.taskId))
    })
  }

  submitBulk(event) {
    const select = event.currentTarget
    if (!select.value) return
    const form = select.closest("form")
    if (form) form.requestSubmit()
  }

  dragStart(event) {
    const card = event.currentTarget
    const id = card.dataset.taskId

    let payload = id
    if (this.selected.has(id) && this.selected.size > 1) {
      payload = Array.from(this.selected).join(",")
      this.cardTargets.forEach(c => {
        if (this.selected.has(c.dataset.taskId)) c.classList.add("kanban-card--dragging")
      })
    } else {
      card.classList.add("kanban-card--dragging")
    }

    event.dataTransfer.setData("text/plain", payload)
    event.dataTransfer.effectAllowed = "move"
  }

  dragEnd() {
    this.cardTargets.forEach(c => c.classList.remove("kanban-card--dragging"))
    this.columnTargets.forEach(col => col.classList.remove("kanban__column--drag-over"))
  }

  dragOver(event) {
    event.preventDefault()
    event.dataTransfer.dropEffect = "move"
  }

  dragEnter(event) {
    event.preventDefault()
    event.currentTarget.classList.add("kanban__column--drag-over")
  }

  dragLeave(event) {
    const column = event.currentTarget
    // dragleave fires when entering a child element; only clear when truly leaving the column.
    if (!column.contains(event.relatedTarget)) {
      column.classList.remove("kanban__column--drag-over")
    }
  }

  drop(event) {
    event.preventDefault()
    const column = event.currentTarget
    column.classList.remove("kanban__column--drag-over")

    const payload = event.dataTransfer.getData("text/plain")
    const newStatus = column.dataset.status
    if (!payload) return

    if (payload.includes(",")) {
      this.#bulkDrop(payload, newStatus, column)
    } else {
      this.#singleDrop(payload, newStatus, column)
    }
  }

  async #singleDrop(taskId, newStatus, column) {
    const card = this.cardTargets.find(c => c.dataset.taskId === taskId)
    if (!card) return

    const columnBody = column.querySelector(".kanban__column-body")
    columnBody.appendChild(card)
    this.#updateColumnCounts()

    const response = await patch(`/tasks/${taskId}`, {
      body: { task: { status: newStatus } },
      responseKind: "turbo-stream"
    })
    if (!response.ok) window.location.reload()
  }

  async #bulkDrop(idsCsv, newStatus, column) {
    const ids = idsCsv.split(",")
    const columnBody = column.querySelector(".kanban__column-body")

    ids.forEach(id => {
      const card = this.cardTargets.find(c => c.dataset.taskId === id)
      if (card) columnBody.appendChild(card)
    })
    this.#updateColumnCounts()

    const body = new FormData()
    body.append("attribute", "status")
    body.append("value", newStatus)
    body.append("ids", idsCsv)

    const response = await post(this.updateUrlValue, { body, responseKind: "html" })
    if (!response.ok) window.location.reload()
  }

  #updateColumnCounts() {
    this.columnTargets.forEach(column => {
      const count = column.querySelectorAll(".kanban-card").length
      const countEl = column.querySelector(".kanban__column-count")
      if (countEl) countEl.textContent = count
    })
  }
}
