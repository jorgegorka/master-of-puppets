import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"

export default class extends Controller {
  static values = { missionId: Number }

  connect() {
    this.subscription = consumer.subscriptions.create(
      { channel: "SwarmChannel", swarm_mission_id: this.missionIdValue },
      { received: (data) => this.onMessage(data) }
    )
  }

  disconnect() {
    this.subscription?.unsubscribe()
  }

  onMessage(data) {
    if (data.type === "worker_output") {
      const pre = this.element.querySelector(`pre.worker-output[data-assignment-id="${data.assignment_id}"]`)
      if (pre) pre.appendChild(document.createTextNode(data.chunk))
    }
  }
}
