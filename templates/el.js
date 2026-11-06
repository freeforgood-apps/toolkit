// Build elements from data safely: text only, no event handlers, no javascript: links.
const URL_ATTRS = ['href', 'src', 'action', 'formaction', 'xlink:href'];

function safeUrl(value) {
  try {
    return ['http:', 'https:', 'mailto:'].includes(new URL(String(value), location.href).protocol);
  } catch {
    return false;
  }
}

function el(tag, text, attrs = {}) {
  const node = document.createElement(tag);
  if (text != null) node.textContent = String(text);
  for (const [name, value] of Object.entries(attrs)) {
    const n = name.toLowerCase();
    if (n.startsWith('on') || n === 'srcdoc') continue;
    if (URL_ATTRS.includes(n) && !safeUrl(value)) continue;
    node.setAttribute(name, String(value));
  }
  return node;
}
