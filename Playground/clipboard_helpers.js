// Stands in for the web app's helpers/clipboard_helpers, which the
// context-menu bridge controller imports for copyHtml. The real one renders
// the answer's Markdown with marked; this one keeps paragraphs and escapes
// the rest, which is enough to send copyHtml from the playground.
export async function clipboardHTML(markdown) {
  return markdown
    .split(/\n{2,}/)
    .map(paragraph => {
      const element = document.createElement("p")
      element.textContent = paragraph
      return element.outerHTML
    })
    .join("")
}
