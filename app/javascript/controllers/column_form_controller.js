import { Controller } from "@hotwired/stimulus"

// On manual policy, the server nullifies the agent-only fields on save —
// hiding them in the DOM is purely cosmetic, so cached values are harmless.
export default class extends Controller {
  static targets = ["agentSection", "policySelect"]

  connect() {
    this.applyPolicy(this.policySelectTarget.value)
  }

  togglePolicy(event) {
    this.applyPolicy(event.target.value)
  }

  applyPolicy(policy) {
    this.agentSectionTarget.hidden = policy !== "agent"
  }
}
