import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"

export default class extends Controller {
  static values = { chatSessionId: Number }

  connect() {
    this.subscription = consumer.subscriptions.create(
      { channel: "ChatChannel", chat_session_id: this.chatSessionIdValue },
      { received: (event) => this.dispatchEvent(event) }
    )
  }

  disconnect() {
    this.subscription?.unsubscribe()
  }

  dispatchEvent(event) {
    switch (event.type) {
      case "content_block_start": return this.beginBlock(event)
      case "text_delta":          return this.appendText(event)
      case "thinking_delta":      return this.appendThinking(event)
      case "tool_use_input_delta":return this.appendToolInput(event)
      case "content_block_stop":  return this.endBlock(event)
      case "message_stop":        return this.finalize(event)
      case "error":               return this.showError(event)
    }
  }

  get streamingMessage() {
    return this.element.querySelector(".message--streaming, .message--pending")
  }

  beginBlock({ index, block }) {
    const target = this.streamingMessage
    if (!target) return
    const el = document.createElement("div")
    el.dataset.blockIndex = index
    el.dataset.blockType = block.type
    el.className = `block block--${block.type}`
    if (block.type === "tool_use") el.dataset.toolName = block.name
    target.appendChild(el)
  }

  appendText({ index, text }) {
    const target = this.element.querySelector(`[data-block-index="${index}"][data-block-type="text"]`)
    if (target) target.textContent += text
  }

  appendThinking({ index, thinking }) {
    const target = this.element.querySelector(`[data-block-index="${index}"][data-block-type="thinking"]`)
    if (target) target.textContent += thinking
  }

  appendToolInput({ index, partial_json }) {
    const target = this.element.querySelector(`[data-block-index="${index}"][data-block-type="tool_use"]`)
    if (target) target.dataset.input = (target.dataset.input ?? "") + partial_json
  }

  endBlock() {
    // Nothing yet — could parse tool_use input JSON here in a future pass.
  }

  finalize() {
    const streaming = this.element.querySelector(".message--streaming")
    streaming?.classList.replace("message--streaming", "message--completed")
  }

  showError({ message }) {
    const banner = document.createElement("p")
    banner.className = "chat-error txt-negative"
    banner.textContent = message
    this.element.appendChild(banner)
  }
}
