import { Controller } from "@hotwired/stimulus"

// Only auto-scrolls when the user is already at the bottom — otherwise we
// must not yank the viewport while they're reading earlier output.
export default class extends Controller {
  static values = { tolerancePx: { type: Number, default: 24 } }

  connect() {
    this.observer = new MutationObserver(() => this.maybeScroll())
    this.observer.observe(this.element, { childList: true, subtree: true })
    this.scrollToEnd()
  }

  disconnect() {
    this.observer?.disconnect()
  }

  maybeScroll() {
    if (this.pinnedToBottom()) this.scrollToEnd()
  }

  pinnedToBottom() {
    const distance = this.element.scrollHeight - this.element.scrollTop - this.element.clientHeight
    return distance <= this.tolerancePxValue
  }

  scrollToEnd() {
    this.element.scrollTop = this.element.scrollHeight
  }
}
