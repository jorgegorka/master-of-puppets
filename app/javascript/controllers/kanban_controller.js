import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

// Drag-and-drop kanban board for swarm assignments. Each card represents one
// assignment; dropping it on another column PATCHes the assignment with the
// new state. The server (SwarmMissions::AssignmentsController#update) decides
// which transitions are allowed — the client just suggests.
export default class extends Controller {
  static targets = ["column"]

  connect() {
    this.sortables = this.columnTargets.map((col) => (
      Sortable.create(col, {
        group: "kanban",
        animation: 150,
        onEnd: (evt) => this.move(evt)
      })
    ))
  }

  disconnect() {
    this.sortables?.forEach((s) => s.destroy())
  }

  move(evt) {
    const card      = evt.item
    const id        = card.dataset.assignmentId
    const missionId = card.dataset.missionId
    const state     = evt.to.closest("[data-kanban-state-param]").dataset.kanbanStateParam
    const token     = document.querySelector('meta[name="csrf-token"]')?.content

    const form = new FormData()
    form.append("_method", "patch")
    form.append("state", state)
    if (token) form.append("authenticity_token", token)

    fetch(`/swarm/missions/${missionId}/assignments/${id}`, {
      method: "POST",
      headers: { "Accept": "text/vnd.turbo-stream.html, text/html" },
      body: form
    })
  }
}
