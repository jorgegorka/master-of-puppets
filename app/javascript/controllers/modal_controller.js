import { Controller } from "@hotwired/stimulus"

// Generic modal controller bound directly to a <dialog> element.
//
// Two usage modes:
//
// 1. Lazy-loaded via turbo-frame — the dialog is rendered inside a
//    turbo_frame_tag and swapped in by Turbo. On connect() we auto-open it,
//    and on close() we empty the parent frame so the next trigger refetches.
//
// 2. Static on the page — the dialog is rendered on initial page load and
//    opened programmatically by another controller calling open(). In this
//    mode the dialog is not inside a turbo-frame, so close() is a plain
//    dialog.close().
export default class extends Controller {
  initialize() {
    this.onDialogClose = () => this.parentFrame?.replaceChildren()
  }

  connect() {
    this.element.addEventListener("close", this.onDialogClose)
    if (this.parentFrame && !this.element.open) {
      this.element.showModal()
    }
  }

  disconnect() {
    this.element.removeEventListener("close", this.onDialogClose)
  }

  open() {
    if (!this.element.open) this.element.showModal()
  }

  close(e) {
    e?.preventDefault()
    this.element.close()
  }

  clickOutside(e) {
    if (e.target === this.element) this.element.close()
  }

  submitEnd(e) {
    if (e.detail.success) this.element.close()
  }

  get parentFrame() {
    return this.element.closest("turbo-frame")
  }
}
