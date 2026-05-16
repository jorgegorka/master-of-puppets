import { Controller } from "@hotwired/stimulus"
import { Terminal } from "xterm"
import { FitAddon } from "@xterm/addon-fit"
import consumer from "channels/consumer"

export default class extends Controller {
  static values = { sessionId: Number }

  connect() {
    this.term = new Terminal({
      convertEol: true,
      fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace",
      fontSize: 13,
      cursorBlink: true,
      theme: { background: "#0b0b10", foreground: "#e6e6f0" }
    })
    this.fit = new FitAddon()
    this.term.loadAddon(this.fit)
    this.term.open(this.element)
    this.fit.fit()

    this.subscription = consumer.subscriptions.create(
      { channel: "TerminalChannel", terminal_session_id: this.sessionIdValue },
      {
        connected: () => this.onResize(),
        received: (event) => this.onEvent(event)
      }
    )

    this.term.onData((data) => this.subscription?.perform("receive", { type: "input", data }))
    this.onResize = this.onResize.bind(this)
    window.addEventListener("resize", this.onResize)
  }

  disconnect() {
    window.removeEventListener("resize", this.onResize)
    this.subscription?.unsubscribe()
    this.term?.dispose()
  }

  onEvent(event) {
    switch (event.type) {
      case "scrollback":
        this.term.clear()
        this.term.write(event.data)
        break
      case "chunk":
        this.term.write(event.data)
        break
    }
  }

  onResize() {
    this.fit?.fit()
    if (this.subscription && this.term) {
      this.subscription.perform("receive", {
        type: "resize",
        cols: this.term.cols,
        rows: this.term.rows
      })
    }
  }
}
