#!/usr/bin/env python3
"""Chat with Work contract playground.

A stand-in for the Rails app as it will behave once it implements
docs/server-contract.md: native titles and layout, 401 for the app without a
session, recede after sign-in, flash as toasts, and the bridge controllers in
web/controllers/bridge. It lets you run the iOS app's whole signed-in shell,
and every bridge component, without an account or a Rails checkout.

The pages are fixtures written with the web app's real class names and
styled by its real stylesheet, fetched from a running server (staging by
default) and served from here, so they look like the product. They are not
the product: everything on them is made up.

    python3 Playground/server.py            # http://localhost:8765
    xcrun simctl launch booted com.chatwithwork.app.debug -CWWBaseURL http://localhost:8765

Options: --port, --assets-from https://staging.chatwithwork.com,
--legacy-auth to redirect to sign-in instead of answering 401, as the
server does before the contract, and --open to treat every request as
signed in.
"""

import argparse
import html
import json
import re
import threading
import time
import urllib.parse
import urllib.request
from http.cookies import SimpleCookie
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent
ICONS = json.loads((ROOT / "icons.json").read_text())
ACCOUNTS = {"1000001": "Acme", "2000002": "Initech"}

# What the made-up person has connected, in the order the new chat page fans
# out to them (chats/_reach), and the question each suggests
# (ChatsHelper::SERVICE_SUGGESTIONS).
SERVICES = [
    ("google_drive", "Google Drive", "Find the latest version of our planning doc in Drive"),
    ("dropbox", "Dropbox", "What changed in my Dropbox this week?"),
    ("slack", "Slack", "What did my team decide in Slack this week?"),
    ("notion", "Notion", "Summarize what changed in our Notion docs this week"),
]
INTERVIEW = (
    "Ask me how you can help",
    "Interview me, one question at a time, about what makes work confusing or stressful for me. "
    "Then suggest a few ways you could help, using what I've connected.",
)
# The model picker's choices, as ModelSetting.for_selection orders them: the
# default, then by price. The rates are made up.
MODELS = [
    ("gemini-3.8-flash", "vertexai", "Gemini 3.8 Flash", "gemini",
     "Google's latest Flash for documents, tool use, and everyday work", "About 2 credits per answer"),
    ("Qwen3.8-27B", "hetzner", "Qwen3.8-27B", "qwen",
     "Open-weight Qwen on Hetzner's EU inference, free for everyone", "Free"),
    ("gpt-6-luna", "azure", "GPT-6 Luna", "openai",
     "OpenAI's fast, affordable GPT-6 for high-volume work", "About 3 credits per answer"),
    ("gpt-6-sol", "azure", "GPT-6 Sol", "openai",
     "OpenAI's GPT-6 for complex reasoning and multi-step tool use", "About 9 credits per answer"),
]
# Single-color logos, which provider_icon turns white in dark mode (ProviderIcon::MONOCHROME).
MONOCHROME = {"basecamp", "brain", "github", "intercom", "ollama", "openai", "openrouter", "qwen", "xai"}

STATE_LOCK = threading.Lock()
SESSIONS = {}  # cookie value -> {"flash": [(type, message)], "pinned": set(), "asked": {}, "paused": set()}
CHATS = {
    42: {"title": "Q3 launch commitments for Acme", "project": None, "when": "Today", "processing": False},
    41: {"title": "Summarize the security review thread", "project": "Acme launch", "when": "Today", "processing": False},
    38: {"title": "Which customers asked about SSO?", "project": None, "when": "Yesterday", "processing": False},
    35: {"title": "Draft the onboarding checklist", "project": "Onboarding", "when": "Previous 7 days", "processing": False},
    31: {"title": "Find the signed order form from Initech", "project": None, "when": "Previous 7 days", "processing": False},
}
PROJECTS = {
    1: {"name": "Acme", "hq": True, "all_access": False, "summary": "Everyone in Acme", "audience": "everyone in Acme", "chats": 12},
    2: {"name": "Acme launch", "hq": False, "all_access": False, "summary": "Invite-only · 4 people", "audience": "4 people", "chats": 7},
    3: {"name": "Onboarding", "hq": False, "all_access": True, "summary": "All-Access · 3 people", "audience": "3 people", "chats": 3},
}
ASSETS = {"css": [], "cache": {}, "providers": {}}


def icon(name, cls=None, style="bold"):
    """A Phosphor icon as the app's icon_tag draws it: bold unless asked
    otherwise, with a class only when given one."""
    path = ICONS[name if style == "bold" else f"{name}:{style}"]
    class_attr = f' class="{cls}"' if cls else ""
    return f'<svg viewBox="0 0 256 256" fill="currentColor" width="20" height="20" aria-hidden="true"{class_attr}>{path}</svg>'


def provider_src(key):
    return ASSETS["providers"].get(key, f"/assets/providers/{key}.svg")


def provider(key, cls=None, alt=""):
    """A service's or model maker's logo as provider_icon draws it."""
    classes = " ".join(filter(None, [cls, "dark:brightness-0 dark:invert" if key in MONOCHROME else None]))
    class_attr = f' class="{classes}"' if classes else ""
    return f'<img alt="{esc(alt)}" width="64" height="64"{class_attr} src="{provider_src(key)}">'


def project_icon(project, cls=None):
    """HQ is a building, an All-Access project a group, the rest folders (Project#icon)."""
    return icon("buildings" if project["hq"] else "users-three" if project["all_access"] else "folder-simple", cls)


def project_named(name):
    return next(((number, project) for number, project in PROJECTS.items() if project["name"] == name), (None, None))


def esc(value):
    return html.escape(str(value), quote=True)


def turbo_stream(action, target, content):
    return f'<turbo-stream action="{action}" target="{target}"><template>{content}</template></turbo-stream>'


class Page:
    def __init__(self, title, body, *, body_class="", account="1000001"):
        self.title = title
        self.body = body
        self.body_class = body_class
        self.account = account


def layout(handler, page):
    native = handler.native_platform
    css = "\n".join(f'  <link rel="stylesheet" href="{href}">' for href in ASSETS["css"])
    flash = handler.render_flash()
    native_attr = f' data-native-app="{native}"' if native else ""
    return f"""<!DOCTYPE html>
<html lang="en"{native_attr}>
<head>
  <title>{esc(page.title)}</title>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
  <meta name="csrf-token" content="playground">
  <meta name="turbo-prefetch" content="false">
{css}
  <link rel="stylesheet" href="/web/native.css">
  <link rel="stylesheet" href="/playground/playground.css">
  <script type="importmap">
  {{
    "imports": {{
      "@hotwired/turbo": "https://cdn.jsdelivr.net/npm/@hotwired/turbo@8.0.23/+esm",
      "@hotwired/stimulus": "https://cdn.jsdelivr.net/npm/@hotwired/stimulus@3.2.2/+esm",
      "@hotwired/hotwire-native-bridge": "https://cdn.jsdelivr.net/npm/@hotwired/hotwire-native-bridge@1.2.2/+esm"
    }}
  }}
  </script>
  <script type="module" src="/playground/playground.js"></script>
</head>
<body class="min-h-screen bg-canvas text-ink {page.body_class}" data-controller="bridge--confirm">
  <div id="flash-messages">{flash}</div>
  <main class="native-main">
{page.body}
  </main>
</body>
</html>"""


# MARK: - Pages

def chats_index(handler, account):
    groups = {}
    for number, chat in sorted(CHATS.items(), reverse=True):
        groups.setdefault(chat["when"], []).append((number, chat))

    ago = {"Today": "about 2 hours ago", "Yesterday": "1 day ago"}
    sections = []
    for label, chats in groups.items():
        rows = "\n".join(f"""
          <li class="chat-history__row" data-search-target="item" id="history_item_chat_{number}">
            <a class="chat-history__link" data-turbo-prefetch="false" href="/{account}/chats/{number}">
              {'<span class="dot dot--small dot--live dot--pulse" title="Working"></span>' if chat["processing"] else ''}
              <span class="chat-history__title">{esc(chat["title"])}</span>
              <time class="micro" datetime="2026-10-02T09:41:00Z">{ago.get(label, "4 days ago")}</time>
            </a>
          </li>""" for number, chat in chats)
        sections.append(f"""
      <section class="chat-history__group">
        <h2 class="micro">{label}</h2>
        <ul class="rows">{rows}
        </ul>
      </section>""")

    body = f"""
    <div class="chat-history" data-controller="search bridge--search">
      <header class="chat-history__header native-hidden">
        <div>
          <h1>Chats</h1>
          <p class="micro">{len(CHATS)} chats</p>
        </div>
        <a class="btn btn-primary btn-sm" href="/{account}/chats/new" data-controller="bridge--button" data-bridge-title="New chat"
           data-bridge-ios-image="square.and.pencil" data-bridge-android-image="edit_square">{icon("note-pencil", "size-4")} New chat</a>
      </header>
      <label class="input w-full native-search-field">
        {icon("magnifying-glass", "size-4 text-ink-faint")}
        <input type="search" placeholder="Search your chats" aria-label="Search your chats" autocomplete="off"
               data-search-target="input" data-bridge--search-target="input" data-action="input->search#filter">
      </label>
      {''.join(sections)}
    </div>"""
    return Page("Chats", body, account=account)


# MARK: - A conversation, in the markup of chats/show, messages/ and activities/

QUESTION = "What did we promise Acme for the Q3 launch?"
ANSWER = (
    "Acme launches on **September 30**, with single sign-on and EU-only hosting, as the plan and the signed "
    "order form say. Priya confirmed the date with their team on Monday.\n\n"
    "- Single sign-on with their identity provider from day one\n"
    "- Hosting in the EU only, written into the order form\n"
    "- A named contact for the first 90 days"
)
ANSWER_HTML = """<p>Acme launches on <strong>September 30</strong>, with single sign-on and EU-only hosting, as the plan and the signed order form say. Priya confirmed the date with their team on Monday.</p>
              <ul>
                <li>Single sign-on with their identity provider from day one</li>
                <li>Hosting in the EU only, written into the order form</li>
                <li>A named contact for the first 90 days</li>
              </ul>"""
SOURCES = [
    ("google_drive", "Acme launch plan", "https://docs.google.com/document/d/acme-launch-plan"),
    ("slack", "Launch date with Priya in #acme-launch", "https://acme.slack.com/archives/C0ACMELNCH/p1790000000000100"),
]
RECAP_REQUEST = "Post a recap to #acme-launch."
RECAP = "Recap: Acme launches September 30 with single sign-on and EU-only hosting, as the plan and the signed order form say."
RECAP_CALL = "toolu_recap01"
MADE_UP = "I looked in your connected services. This is a playground, so this answer is made up."


def copy_button():
    return f"""
              <button type="button" class="message__action tooltip" data-tip="Copy" data-action="clipboard#copy" aria-label="Copy message"
                      data-bridge--context-menu-target="item" data-bridge-title="Copy" data-bridge-ios-image="doc.on.doc"
                      data-bridge-android-image="content_copy" data-bridge-copy="true">
                <span class="inline-flex" data-clipboard-target="idleLabel">{icon("copy")}</span>
                <span class="hidden" data-clipboard-target="copiedLabel">{icon("check")}</span>
              </button>"""


def retry_button(account, number, message_id, question=False):
    """The apps ask with a native alert (server contract, section 7) instead
    of the web's retry dialog."""
    noun = "question" if question else "answer"
    description = (
        "The assistant will answer this question again. Any later messages will be removed." if question else
        "Everything after the question, including this reply, will be removed, and the assistant will answer it again."
    )
    return f"""
              <form class="contents" method="post" action="/{account}/chats/{number}/messages/{message_id}/retries" data-turbo-frame="_top"
                    data-turbo-confirm="Retry this {noun}?" data-bridge-confirm="Retry" data-bridge-description="{esc(description)}">
                <button type="submit" class="message__action tooltip" aria-label="Retry this {noun}" data-tip="Retry"
                        data-bridge--context-menu-target="item" data-bridge-title="Retry" data-bridge-ios-image="arrow.clockwise"
                        data-bridge-android-image="refresh">{icon("arrows-clockwise")}</button>
              </form>"""


def more_button():
    return f"""
              <button type="button" class="message__action message__more" aria-label="More actions"
                      data-bridge--context-menu-target="trigger" data-action="bridge--context-menu#show">{icon("dots-three")}</button>"""


def user_message(account, number, message_id, text, author=None):
    author_line = f'\n          <p class="message__author micro text-end">{esc(author)}</p>' if author else ""
    return f"""
          <turbo-frame id="message_{message_id}">{author_line}
            <div class="message message--user" tabindex="-1" data-controller="clipboard bridge--context-menu"
                 data-message-role="user" data-message-id="{message_id}">
              <div data-clipboard-target="source" data-bridge--context-menu-target="copySource" hidden>{esc(text)}</div>
              <div class="message__bubble">{esc(text)}</div>
              <div class="message__actions">{copy_button()}{retry_button(account, number, message_id, question=True)}{more_button()}
              </div>
            </div>
          </turbo-frame>"""


def sources_menu(sources):
    if not sources:
        return ""
    label = f"{len(sources)} source" + ("" if len(sources) == 1 else "s")
    avatars = "".join(
        f'<span class="avatar-stack__item"><img src="{provider_src(key)}" alt="" loading="lazy"></span>' for key, _, _ in sources[:3]
    )
    items = "".join(f"""
                  <li><a class="sources__item" href="{esc(url)}" target="_blank" rel="noopener"><img src="{provider_src(key)}" alt="" loading="lazy"><span>{esc(title)}</span>{icon("arrow-up-right")}</a></li>"""
                    for key, title, url in sources)
    return f"""
              <div class="sources dropdown dropdown-top dropdown-end">
                <div tabindex="0" role="button" class="sources__trigger" aria-label="{label}">
                  <span class="avatar-stack avatar-stack--small">{avatars}</span>
                  <span>Sources</span>
                  <span class="micro">{len(sources)}</span>
                </div>
                <ul tabindex="-1" class="dropdown-content menu sources__menu z-20">
                  <li class="menu-title">{label}</li>{items}
                </ul>
              </div>"""


def assistant_message(account, number, message_id, text, body_html, sources=(), project_chat=False):
    share = "" if project_chat else f"""
              <button type="button" class="message__action tooltip" data-tip="Share" aria-label="Share a public link to this chat"
                      data-controller="modal-opener" data-modal-opener-dialog-id-value="share_link_dialog_chat_{number}"
                      data-action="modal-opener#open" data-bridge--context-menu-target="item" data-bridge-title="Share link"
                      data-bridge-ios-image="link" data-bridge-android-image="link">{icon("export")}</button>"""
    return f"""
          <turbo-frame id="message_{message_id}">
            <div class="message message--assistant" tabindex="-1" data-controller="markdown clipboard bridge--context-menu"
                 data-markdown-hide-when-empty-value="true">
              <pre data-markdown-target="source" hidden id="message_{message_id}_source">{esc(text)}</pre>
              <pre data-clipboard-target="source" data-bridge--context-menu-target="copySource" hidden>{esc(text)}</pre>

              <div data-markdown-target="output" class="message__body prose">{body_html}</div>

              <footer class="message__footer">
                <div class="message__actions">{copy_button()}{retry_button(account, number, message_id)}
                  <form class="contents" method="post" action="/{account}/chats/{number}/messages/{message_id}/branches" data-turbo-frame="_top">
                    <button type="submit" class="message__action tooltip" aria-label="Branch into a new chat" data-tip="Branch into a new chat"
                            data-bridge--context-menu-target="item" data-bridge-title="Branch into a new chat"
                            data-bridge-ios-image="arrow.triangle.branch" data-bridge-android-image="call_split">{icon("git-branch")}</button>
                  </form>{share}{more_button()}
                </div>{sources_menu(sources)}
              </footer>
            </div>
          </turbo-frame>"""


def step(message_id, summary, *, logo=None, glyph=None, details=None, body=None):
    """One row of an activity's log (messages/tool_results/_row)."""
    lead = icon(glyph, "step__icon") if glyph else provider(logo, "step__icon") if logo else ""
    header = f'{lead}<span class="step__summary">{esc(summary)}</span>'
    details_html = f'<p class="step__details">{esc(details)}</p>' if details else ""
    if body:
        row = (f'<details class="step"><summary class="step__header">{header}{icon("caret-right", "step__caret")}</summary>'
               f'<div class="step__body">{details_html}{body}</div></details>')
    else:
        row = f'<div class="step"><div class="step__header">{header}</div>{details_html}</div>'
    return f'\n              <turbo-frame id="message_{message_id}">{row}</turbo-frame>'


def activity(activity_id, services, title, *, details=None, steps="", opened=False, waiting=False):
    """Tool work between two things said, folded into one line (activities/_activity)."""
    avatars = "".join(
        f'<span class="avatar-stack__item" title="{esc(name)}">{provider(key, alt=name)}</span>' for key, name in services
    )
    details_html = f'\n                <span class="activity__details">· {esc(details)}</span>' if details else ""
    return f"""
          <details id="activity_{activity_id}" class="activity"{' open' if opened else ''}>
            <summary class="activity__summary">
              <span class="activity__wire" aria-hidden="true"></span>
              <span id="activity_{activity_id}_summary" class="activity__line{' activity__line--waiting' if waiting else ''}">
                <span class="avatar-stack">{avatars}</span>
                <span class="activity__text">
                  <span class="activity__title">{esc(title)}</span>{details_html}
                </span>
              </span>
              {icon("caret-right", "activity__caret")}
            </summary>

            <div id="activity_{activity_id}_log" class="activity__log">{steps}
            </div>
          </details>"""


def approval_card(account, number):
    """A change waiting for its driver (messages/tool_calls/_approval), with
    the haptics the contract adds to its two forms."""
    return f"""
              <turbo-frame id="message_14">
                <section id="tool_call_{RECAP_CALL}" class="approval" aria-labelledby="approval_summary_tool_call_9">
                  <header class="approval__header">
                    <span class="avatar-stack"><span class="avatar-stack__item" title="Slack">{provider("slack", alt="Slack")}</span></span>
                    <div class="approval__heading">
                      <p class="approval__kicker">Needs your approval · Slack</p>
                      <h3 id="approval_summary_tool_call_9" class="approval__summary">Post a message to #acme-launch</h3>
                    </div>
                  </header>

                  <div class="approval__preview">
                    <div class="approval__letter">
                      <dl class="approval__envelope">
                        <div><dt>To</dt><dd>#acme-launch</dd></div>
                        <div><dt>As</dt><dd>You, from your Slack account</dd></div>
                      </dl>
                      <div class="approval__body">{esc(RECAP)}</div>
                    </div>
                  </div>

                  <form id="denial_tool_call_9" class="approval__reason" method="post" action="/{account}/chats/{number}/tool_calls/9/denial"
                        data-turbo-frame="_top" data-controller="bridge--haptic" data-bridge-feedback="warning"
                        data-action="turbo:submit-start->bridge--haptic#vibrate">
                    <details>
                      <summary>Deny with a reason</summary>
                      <label class="sr-only" for="denial_reason_tool_call_9">Why you're denying it</label>
                      <input type="text" name="reason" id="denial_reason_tool_call_9" maxlength="500" class="input input-sm"
                             placeholder="Say what to do instead (optional)" autocomplete="off">
                    </details>
                  </form>

                  <form id="approval_form_tool_call_9" class="approval__actions" method="post" action="/{account}/chats/{number}/tool_calls/9/approval"
                        data-turbo-frame="_top" data-controller="bridge--haptic" data-bridge-feedback="success"
                        data-action="turbo:submit-start->bridge--haptic#vibrate">
                    <label class="approval__allow">
                      <input type="checkbox" name="for_rest_of_chat" id="for_rest_of_chat_tool_call_9" value="1" class="checkbox checkbox-xs">
                      <span>Allow “Post message” in Slack for the rest of this chat</span>
                    </label>

                    <div class="approval__buttons">
                      <button type="submit" form="denial_tool_call_9" class="btn btn-sm btn-subtle">Deny</button>
                      <button type="submit" class="btn btn-sm btn-primary">Approve</button>
                    </div>
                  </form>
                </section>
              </turbo-frame>"""


def recap_activity(account, number, state, reason=None):
    """The recap's step: waiting for approval, posted, or denied (also when
    the person asked something else instead)."""
    slack = [("slack", "Slack")]
    if state == "waiting":
        return activity(14, slack, "Waiting for approval in Slack", waiting=True, opened=True, steps=approval_card(account, number))
    calls = '\n              <turbo-frame id="message_14"></turbo-frame>'
    if state == "approved":
        link = '<a href="https://acme.slack.com/archives/C0ACMELNCH/p1790000000000200" target="_blank" rel="noopener">Open in Slack</a>'
        result = step(15, "Posted to #acme-launch", logo="slack", body=link)
    else:
        result = step(15, "Denied: Post a message to #acme-launch", glyph="prohibit", details=reason and f"“{reason}”")
    return activity(14, slack, "Used Slack", details="ran 1 tool", steps=calls + result)


def typing_indicator(waiting):
    """messages/_typing_indicator: here only ever the wait for an approval."""
    inner = f"""
              <div class="thinking thinking--approval" role="status">
                <span class="thinking__mark">{icon("hand-palm")}</span>
                <span class="thinking__label">
                  Waiting for your approval.
                  <a href="#tool_call_{RECAP_CALL}" class="thinking__link">Review</a>
                </span>
              </div>""" if waiting else '<div class="hidden"></div>'
    return f'\n            <turbo-frame id="typing_indicator" data-scroll-target="resizable">{inner}\n            </turbo-frame>'


def exchange(account, number, index, text, author=None):
    """A question asked here, and the playground's made-up answer to it."""
    message_id = 100 + index * 2
    return (user_message(account, number, message_id, text, author)
            + assistant_message(account, number, message_id + 1, MADE_UP, f"<p>{esc(MADE_UP)}</p>"))


def composer(handler, account, number=None, placeholder="Reply to Chat with Work", working=False, project=None):
    """The chat form (chats/_form, _model_picker, _submit_button), with a
    textarea standing in for the Lexxy editor and the contract's haptic."""
    action = f"/{account}/chats/{number}/messages" if number else f"/{account}/messages"
    model_id, provider_key, name, logo, _, rate = MODELS[0]
    ctrl = "⌘" if handler.native_platform == "ios" else "Ctrl"
    if working:
        send = f"""
          <a id="submit_button" href="/{account}/chats/{number}/cancellation" data-turbo-method="post"
             class="btn btn-primary btn-square btn-sm tooltip tooltip-top chat-prompt__send chat-prompt__stop"
             data-tip="Stop" aria-label="Stop response">
            <span class="chat-prompt__ring" aria-hidden="true"></span>
            {icon("stop", "size-3.5", style="fill")}
          </a>"""
    else:
        send = f"""
          <button id="submit_button" type="submit"
                  class="btn btn-primary btn-square btn-sm tooltip tooltip-top chat-prompt__send"
                  data-composer-target="send" data-tip="Send" aria-label="Send message" disabled>
            {icon("arrow-up", "size-4")}
          </button>"""
    options = "".join(f"""
                <li>
                  <button type="button" role="option" aria-selected="{'true' if m_id == model_id else 'false'}"
                          class="model-picker__option{' active' if m_id == model_id else ''}"
                          data-model-select-target="option" data-action="click->model-select#select"
                          data-model-select-model-id-param="{esc(m_id)}" data-model-select-provider-param="{m_provider}"
                          data-model-select-name-param="{esc(m_name)}" data-model-select-rate-param="{esc(m_rate)}"
                          data-model-select-icon-param="{provider_src(m_logo)}"
                          data-model-select-invert-param="{'true' if m_logo in MONOCHROME else 'false'}">
                    {provider(m_logo)}
                    <strong>{esc(m_name)}</strong>
                    {icon("check")}
                    <p>{esc(m_description)}</p>
                    <span class="micro">{esc(m_rate)}</span>
                  </button>
                </li>""" for m_id, m_provider, m_name, m_logo, m_description, m_rate in MODELS)
    project_field = f'\n      <input type="hidden" name="project_id" value="{project}">' if project else ""
    return f"""
    <div id="new_message" class="composer rainbow-glow{' composer--working' if working else ''}"
         data-controller="composer bridge--haptic" data-bridge-feedback="light">
      <form class="print:hidden" action="{action}" method="post"
            data-action="submit->composer#submit turbo:submit-start->bridge--haptic#vibrate turbo:submit-end->composer#reset">
      <input type="hidden" name="message[content]" value="" data-composer-target="content">{project_field}

      <div class="chat-prompt">
        <div class="chat-prompt__field">
          <textarea rows="1" placeholder="{esc(placeholder)}" aria-label="Message"
                    class="block w-full chat-compose-editor playground-editor" data-composer-target="input"
                    data-action="input->composer#update keydown.meta+enter->composer#submit"></textarea>

          <span class="kbd-hint chat-prompt__hint max-sm:hidden" aria-hidden="true">
            <kbd class="kbd">{ctrl}</kbd><kbd class="kbd">/</kbd>
          </span>
        </div>

        <div class="chat-prompt__bar">
          <button type="button" class="btn btn-ghost btn-sm btn-square tooltip chat-prompt__attach"
                  aria-label="Attach files" data-tip="Attach files">
            <span class="chat-prompt__spinner" aria-hidden="true"></span>
            {icon("paperclip", "size-4")}
          </button>

          <div class="model-picker tooltip" data-tip="{esc(rate)}" data-controller="model-select">
            <input type="hidden" name="model" value="{esc(model_id)}" data-model-select-target="model">
            <input type="hidden" name="provider" value="{provider_key}" data-model-select-target="provider">

            <div class="dropdown dropdown-top dropdown-end">
              <div tabindex="0" role="button" class="model-picker__trigger" data-model-select-target="trigger"
                   aria-label="Model: {esc(name)}" aria-haspopup="listbox">
                {provider(logo).replace('<img ', '<img data-model-select-target="icon" ', 1)}
                <span data-model-select-target="label">{esc(name)}</span>
                {icon("caret-up-down")}
              </div>

              <ul tabindex="-1" class="dropdown-content menu model-picker__menu z-50" role="listbox" aria-label="Models">{options}
              </ul>
            </div>
          </div>
          {send}
        </div>
      </div>
      </form>
    </div>"""


def project_context(account, project_number, chat_number=None):
    """chats/_project_context: whose eyes are on a chat in a project."""
    project = PROJECTS[project_number]
    change = f"""
      <a class="chat-project__action" data-turbo-frame="_top" href="/{account}/chats/{chat_number}/project/edit">Change</a>""" if chat_number else ""
    return f"""
    <div class="chat-project">
      {project_icon(project, "size-4")}
      <span>
        <a class="chat-project__name" data-turbo-frame="_top" href="/{account}/projects/{project_number}">{esc(project["name"])}</a>
        · shared with {esc(project["audience"])}
      </span>{change}
    </div>"""


def share_dialog(handler, number, title):
    """chats/share_links/_dialog for a shared chat, with the contract's Share
    button beside Copy in the apps."""
    url = "https://chatwithwork.com/shared/3f9c2a"
    share = f"""
          <button type="button" class="btn btn-subtle btn-xs" data-controller="bridge--share" data-action="bridge--share#share"
                  data-bridge-url="{url}" data-bridge-title="{esc(title)}">Share</button>""" if handler.native_platform else ""
    return f"""
    <dialog id="share_link_dialog_chat_{number}" class="modal">
      <div class="modal-box max-w-lg" data-controller="clipboard">
        <header class="dialog__header">
          <h3>Share this chat</h3>
          <p>
            Anyone with this link, inside or outside your company, can read this conversation,
            its citations, and any messages you add later.
          </p>
        </header>

        <div class="share-link">
          <div class="share-link__field">
            {icon("globe-simple", "size-4 text-ink-faint")}
            <code data-clipboard-target="source">{url}</code>
            <button type="button" data-action="clipboard#copy" class="btn btn-primary btn-xs">
              <span class="inline-flex items-center gap-1.5" data-clipboard-target="idleLabel">{icon("copy", "size-3.5")} Copy</span>
              <span class="hidden items-center gap-1.5" data-clipboard-target="copiedLabel">{icon("check", "size-3.5")} Copied</span>
            </button>{share}
          </div>
          <p class="share-link__meta">
            <span class="state state--positive">Public</span>
            <span class="micro">Expires November 1, 2026</span>
          </p>
          <p class="share-link__note">You can stop sharing at any time, here or in Settings.</p>
        </div>

        <div class="modal-action justify-between">
          <form class="button_to" method="post" action="/1000001/chats/{number}/share_link">
            <input type="hidden" name="_method" value="delete">
            <button class="btn btn-subtle-negative" type="submit">Stop sharing</button>
          </form>
          <form method="dialog">
            <button class="btn btn-subtle">Done</button>
          </form>
        </div>
      </div>
      <form method="dialog" class="modal-backdrop">
        <button>close</button>
      </form>
    </dialog>"""


def conversation(handler, account, number):
    chat = CHATS.get(number)
    if chat is None:
        return None
    session = handler.session
    pinned = number in session["pinned"]
    project_number, _ = project_named(chat["project"])
    in_project = project_number is not None
    author = "Carmine" if in_project else None

    # The recap waits for approval in the first chat; elsewhere it was posted.
    state = session.get("approval", "waiting") if number == 42 else "approved"
    after = ""
    if state == "approved":
        after = assistant_message(account, number, 16, "Posted the recap to #acme-launch.", "<p>Posted the recap to #acme-launch.</p>",
                                  project_chat=in_project)
    elif state == "denied":
        after = assistant_message(account, number, 16, "Okay, I didn't post it.", "<p>Okay, I didn't post it.</p>", project_chat=in_project)
    asked = "".join(exchange(account, number, index, text, author) for index, text in enumerate(session.get("asked", {}).get(number, [])))

    share_item = "" if in_project else f"""
        <button type="button" data-bridge--menu-target="item" data-bridge-title="Share link" data-bridge-ios-image="link"
                data-bridge-android-image="link" data-controller="modal-opener"
                data-modal-opener-dialog-id-value="share_link_dialog_chat_{number}" data-action="modal-opener#open">Share link</button>"""
    menu_items = f"""
        <form class="contents" method="post" action="/{account}/chats/{number}/pin" id="chat_{number}_pin_form">
          {'<input type="hidden" name="_method" value="delete">' if pinned else ''}
          <button type="submit" id="chat_{number}_pin_item" data-bridge--menu-target="item"
                  data-bridge-title="{'Unpin' if pinned else 'Pin'}" data-bridge-ios-image="{'pin.slash' if pinned else 'pin'}"
                  data-bridge-android-image="{'keep_off' if pinned else 'keep'}">{'Unpin' if pinned else 'Pin'}</button>
        </form>{share_item}
        <a href="/{account}/chats/{number}/edit" data-bridge--menu-target="item" data-bridge-title="Rename"
           data-bridge-ios-image="pencil" data-bridge-android-image="edit">Rename</a>
        <a href="/{account}/chats/{number}/project/edit" data-bridge--menu-target="item" data-bridge-title="Move to project"
           data-bridge-ios-image="folder" data-bridge-android-image="drive_file_move">Move to project</a>
        <a href="/{account}/chats/{number}?recede=1" data-turbo-method="delete" data-turbo-confirm="Delete this chat?"
           data-bridge--menu-target="item" data-bridge-title="Delete" data-bridge-ios-image="trash"
           data-bridge-android-image="delete" data-bridge-destructive="true">Delete</a>"""

    searches = activity(
        7, [("google_drive", "Drive"), ("slack", "Slack")], "Searched Drive and Slack",
        details="2 searches, read 1 file and 1 thread",
        steps=('\n              <turbo-frame id="message_7"></turbo-frame>'
               + step(8, "Found 4 results for Acme Q3 launch", logo="google_drive")
               + step(9, "Found 6 messages for Acme launch date", logo="slack")
               + step(10, "Read Acme order form.pdf", logo="google_drive")
               + step(11, "Read a thread in #acme-launch", logo="slack")),
    )
    project_line = project_context(account, project_number, number) if in_project else ""
    new_chat_path = f"/{account}/chats/new" + (f"?project_id={project_number}" if in_project else "")

    body = f"""
    <div class="native-actions" hidden>
      <a href="{new_chat_path}" data-controller="bridge--button"
         data-bridge-ios-image="square.and.pencil" data-bridge-android-image="edit_square">New chat</a>
      <div data-controller="bridge--menu" data-bridge-label="Chat options">{menu_items}
      </div>
    </div>

    <turbo-frame id="chat_{number}" data-turbo-action="advance">
      <div class="conversation" data-controller="chat" data-chat-id-value="{number}">
        <div class="conversation__scroll">
          <turbo-frame id="chat_messages_frame" class="conversation__column">{project_line}
            <div id="chat_messages" data-scroll-target="resizable">{user_message(account, number, 6, QUESTION, author)}
{searches}
{assistant_message(account, number, 12, ANSWER, ANSWER_HTML, SOURCES, project_chat=in_project)}
{user_message(account, number, 13, RECAP_REQUEST, author)}
{recap_activity(account, number, state, session.get("denial_reason"))}{after}{asked}
            </div>
          </turbo-frame>

          <turbo-frame id="chat_errors" class="conversation__column">
            <div class="chat-notices" id="chat_errors_list"><div class="hidden" aria-hidden="true"></div></div>
          </turbo-frame>

          <turbo-frame id="typing_indicator_container" class="conversation__column">{typing_indicator(state == "waiting")}
          </turbo-frame>

          <div data-scroll-target="bottomSpacer resizable"></div>
        </div>

        <div class="conversation__dock" data-drawer-target="formWrapper">
          <div class="conversation__dock-inner">
            <button type="button" class="scroll-button" data-scroll-target="scrollButton" data-action="click->scroll#scrollToBottom"
                    aria-label="Scroll to the latest message" inert>{icon("arrow-down")}</button>
            <turbo-frame id="chat_form">{composer(handler, account, number)}
            </turbo-frame>
          </div>
        </div>
      </div>
    </turbo-frame>
{'' if in_project else share_dialog(handler, number, chat["title"])}"""
    return Page(chat["title"], body, body_class="chat-view", account=account)


# MARK: - New chat, in the markup of chats/new, _reach and _suggestions

def reach(account, paused):
    """The fan-out from the composer to every service a question can reach,
    ending in a "+" that connects another (chats/_reach)."""
    count = len(SERVICES) + 1
    wires = []
    for index in range(count):
        x = round((index + 0.5) * 100 / count, 2)
        add = index == len(SERVICES)
        idle = add or SERVICES[index][0] in paused
        classes = "wire__path" + (" wire__path--idle" if idle else "") + (" wire__path--add" if add else "")
        wires.append(f'<path class="{classes}" d="M50 0 C 50 24, {x} 16, {x} 40"></path>')

    nodes = []
    for index, (key, name, _) in enumerate(SERVICES):
        is_paused = key in paused
        label, tone = ("Paused", "attention") if is_paused else ("Connected", "positive")
        align = "dropdown-start" if index < count / 3 else "dropdown-end" if index >= count * 2 / 3 else "dropdown-center"
        badge = f'\n                <span class="reach__badge">{icon("pause", style="fill")}</span>' if is_paused else ""
        node_classes = "reach__node" + (" reach__node--offline reach__node--paused" if is_paused else "")
        nodes.append(f"""
        <li class="{node_classes}">
          <div class="dropdown dropdown-bottom reach__menu {align}"
               data-controller="dropdown" data-dropdown-explicit-value="true" data-action="keydown.esc->dropdown#close">
            <button type="button" class="reach__toggle" title="{esc(name)} · {label}" aria-label="{esc(name)}, {label.lower()}"
                    aria-haspopup="menu" aria-expanded="false" data-dropdown-target="button" data-action="dropdown#toggle">
              <span class="reach__avatar">
                {provider(key)}{badge}
              </span>
              <span class="micro">{esc(name)}</span>
            </button>

            <ul class="dropdown-content menu reach__actions" role="menu" aria-label="{esc(name)}">
              <li class="menu-title"><span class="state state--{tone}">{label}</span></li>
              <li>
                <a role="menuitem" data-turbo-method="{'delete' if is_paused else 'post'}" data-turbo-frame="_top"
                   data-action="click->dropdown#close" class="flex w-full items-center gap-2"
                   href="/{account}/settings/connectors/{key}/pause">
                  {icon("play" if is_paused else "pause", "size-4")}
                  <span>{'Resume' if is_paused else 'Pause'}</span>
                </a>
              </li>
            </ul>
          </div>
        </li>""")

    return f"""
    <div id="reach" class="reach" style="--reach-count: {count}">
      <svg class="wire reach__wires" viewBox="0 0 100 40" preserveAspectRatio="none" aria-hidden="true">
        {''.join(wires)}
      </svg>

      <ul class="reach__nodes" aria-label="Services your assistant can ask">{''.join(nodes)}
        <li class="reach__node reach__node--add">
          <button type="button" class="reach__add" title="Connect a service" aria-haspopup="dialog"
                  data-controller="modal-opener" data-modal-opener-dialog-id-value="connect_dialog" data-action="modal-opener#open">
            <span class="reach__avatar">{icon("plus")}</span>
            <span class="micro">Connect</span>
          </button>
        </li>
      </ul>
    </div>"""


def suggestions(account, paused):
    """Questions to start from, each a button that starts a chat with it
    (chats/_suggestions)."""
    picks = [(text, text) for key, _, text in SERVICES if key not in paused][:3] + [INTERVIEW]
    items = "".join(f"""
      <li>
        <form class="button_to" method="post" action="/{account}/messages">
          <button class="suggestion" type="submit">{icon("arrow-up-right", "suggestion__icon")}
            <span>{esc(label)}</span>
          </button>
          <input type="hidden" name="message[content]" value="{esc(prompt)}">
        </form>
      </li>""" for label, prompt in picks)
    return f"""
    <ul id="suggestions" class="suggestions" aria-label="Questions to start with">{items}
    </ul>"""


def new_chat(handler, account, project_number=None):
    paused = handler.session.setdefault("paused", set())
    project = int(project_number) if project_number and project_number.isdigit() and int(project_number) in PROJECTS else None
    body = f"""
    <div class="new-chat">
      <div class="new-chat__backdrop dot-grid dot-grid--fade" aria-hidden="true"></div>

      <h1 class="new-chat__greeting">What are we working on, Carmine?</h1>
{project_context(account, project) if project else ''}{composer(handler, account, placeholder="Ask anything…", project=project)}
{reach(account, paused)}
{suggestions(account, paused)}
    </div>

    <dialog id="connect_dialog" class="modal">
      <div class="modal-box max-w-md">
        <header class="dialog__header">
          <h3>Connect a service</h3>
          <p>The web app lists every connector here, grouped by what it is. The playground stops at this dialog.</p>
        </header>
        <div class="modal-action">
          <form method="dialog"><button class="btn btn-primary">I'm done</button></form>
        </div>
      </div>
      <form method="dialog" class="modal-backdrop"><button>close</button></form>
    </dialog>"""
    return Page("New chat", body, account=account)


def projects_index(handler, account):
    rows = "".join(f"""
        <a class="rows__row" href="/{account}/projects/{number}">
          <span class="rows__logo">{project_icon(project, "size-4")}</span>
          <div class="rows__body">
            <h3>{esc(project["name"])}</h3>
            <p class="micro">{esc(project["summary"])} · {project["chats"]} chats</p>
          </div>
          {icon("caret-right", "size-4 text-ink-faint")}
        </a>""" for number, project in PROJECTS.items())
    body = f"""
    <div class="page">
      <header class="page__header native-hidden">
        <div class="page__heading"><span class="micro">{ACCOUNTS[account]}</span><h1>Projects</h1></div>
      </header>
      <a href="/{account}/projects/new" class="native-hidden" data-controller="bridge--button" data-bridge-title="New project"
         data-bridge-ios-image="plus" data-bridge-android-image="add">New project</a>
      <p class="page__lede">Chats in a project are shared with the people on it. Everything else stays private to whoever started it.</p>
      <section class="page__section">
        <div class="rows">{rows}
        </div>
      </section>
    </div>"""
    return Page("Projects", body, account=account)


def project_page(handler, account, number):
    project = PROJECTS.get(number)
    if project is None:
        return None
    chats = [(n, c) for n, c in CHATS.items() if c["project"] == project["name"]]
    rows = "".join(f"""
          <li class="chat-history__row"><a class="chat-history__link" href="/{account}/chats/{n}">
            <span class="chat-history__title">{esc(c["title"])}</span><time class="micro">2 hours ago</time></a></li>""" for n, c in chats)
    body = f"""
    <div class="page">
      <header class="page__header">
        <div class="page__heading"><span class="micro">{esc(project["summary"])}</span></div>
      </header>
      <a href="/{account}/chats/new?project_id={number}" class="native-hidden" data-controller="bridge--button"
         data-bridge-title="New chat here" data-bridge-ios-image="square.and.pencil" data-bridge-android-image="edit_square">New chat here</a>
      <section class="page__section">
        <header><h2>Chats</h2><span class="micro text-ink-faint">{len(chats)} chats</span></header>
        <ul class="rows">{rows or '<li class="rows__row"><p class="text-ink-muted">No chats yet.</p></li>'}</ul>
      </section>
    </div>"""
    return Page(project["name"], body, account=account)


def project_form(handler, account):
    body = f"""
    <form class="page native-form" method="post" action="/{account}/projects"
          data-controller="bridge--form" data-action="turbo:submit-start->bridge--form#submitStart turbo:submit-end->bridge--form#submitEnd">
      <div class="rows">
        <label class="rows__field"><span>Name</span><input class="input" name="project[name]" placeholder="Acme launch" required></label>
        <label class="rows__field"><span>Description</span><input class="input" name="project[description]" placeholder="What this project is for"></label>
      </div>
      <p class="rows__hint">Chats in a project are shared with the people on it.</p>
      <input type="submit" value="Create project" class="btn btn-primary btn-sm" data-bridge--form-target="submit" data-bridge-title="Create">
    </form>"""
    return Page("New project", body, account=account)


def rename_form(handler, account, number):
    chat = CHATS.get(number)
    body = f"""
    <form class="page native-form" method="post" action="/{account}/chats/{number}"
          data-controller="bridge--form" data-action="turbo:submit-start->bridge--form#submitStart turbo:submit-end->bridge--form#submitEnd">
      <input type="hidden" name="_method" value="patch">
      <input type="hidden" name="recede" value="1">
      <div class="rows"><label class="rows__field"><span>Title</span>
        <input class="input" name="chat[title]" value="{esc(chat['title'])}" required></label></div>
      <input type="submit" value="Save" class="btn btn-primary btn-sm" data-bridge--form-target="submit" data-bridge-title="Save">
    </form>"""
    return Page("Rename chat", body, account=account)


def move_form(handler, account, number):
    chat = CHATS.get(number)
    if chat is None:
        return None
    choices = "".join(f"""
        <label class="settings__row settings__row--choice">
          <span class="settings__row-body"><span class="settings__row-title">{esc(project["name"])}</span>
            <span class="settings__row-text">{esc(project["summary"])}</span></span>
          <input type="radio" class="radio radio-sm" name="project" value="{number}" {'checked' if chat["project"] == project["name"] else ''}>
        </label>""" for number, project in PROJECTS.items())
    body = f"""
    <form class="page native-form" method="post" action="/{account}/chats/{number}/project"
          data-controller="bridge--form" data-action="turbo:submit-start->bridge--form#submitStart turbo:submit-end->bridge--form#submitEnd">
      <input type="hidden" name="_method" value="patch">
      <input type="hidden" name="recede" value="1">
      <p class="rows__hint">Everyone on the project can read this chat and ask in it.</p>
      <div class="settings__group">
        <label class="settings__row settings__row--choice">
          <span class="settings__row-body"><span class="settings__row-title">No project</span>
            <span class="settings__row-text">Only you can see it</span></span>
          <input type="radio" class="radio radio-sm" name="project" value="" {'checked' if not chat["project"] else ''}>
        </label>{choices}
      </div>
      <input type="submit" value="Move chat" class="btn btn-primary btn-sm" data-bridge--form-target="submit" data-bridge-title="Move">
    </form>"""
    return Page("Move to project", body, account=account)


def settings_page(handler, account, tab):
    if tab == "notifications":
        body = f"""
    <div class="settings native-settings">
      <section class="settings__section">
        <header><h2>Notifications on this device</h2>
          <p>Approval requests and answers you're waiting for. Only which service is asking, never what's in your chats.</p></header>
        <div class="settings__group" data-controller="bridge--notification-token"
             data-bridge--notification-token-url-value="/native/push_registrations">
          <div class="settings__row push-row">
            <div class="settings__row-body"><h3>Push notifications</h3>
              <p class="push-row__status" data-status="authorized">On for this device.</p>
              <p class="push-row__status" data-status="denied">Turned off in iOS Settings.</p>
              <p class="push-row__status" data-status="not_determined">Off.</p>
            </div>
            <div class="settings__row-actions">
              <button class="btn btn-sm btn-primary push-row__action" data-status="not_determined" data-action="bridge--notification-token#enable">Turn on</button>
              <button class="btn btn-sm btn-subtle push-row__action" data-status="denied" data-action="bridge--notification-token#openSettings">Open Settings</button>
            </div>
          </div>
        </div>
      </section>
      <section class="settings__section">
        <header><h2>Email notifications</h2><p>Choose what Chat with Work sends to carmine@example.com.</p></header>
        <div class="settings__group">
          <label class="settings__row settings__row--choice"><span class="settings__row-body"><span class="settings__row-title">Account and usage updates</span>
            <span class="settings__row-text">Access grants and monthly credit reset emails.</span></span>
            <input type="checkbox" class="toggle toggle-sm" checked></label>
        </div>
      </section>
    </div>"""
        return Page("Notifications", body, account=account)

    sections = [
        ("Account", "user-circle", "account"), ("People", "users-three", "people"), ("Projects", "folders", "projects"),
        ("Billing", "credit-card", "billing"), ("Models", "sparkle", "models"), ("Connectors", "plugs-connected", "connectors"),
        ("Notifications", "bell", "notifications"), ("Sharing", "link", "sharing"),
    ]
    rows = "".join(f"""
        <a class="rows__row" href="/{account}/settings?tab={key}">
          <span class="rows__logo">{icon(symbol, "size-4")}</span>
          <div class="rows__body"><h3>{label}</h3></div>
          {icon("caret-right", "size-4 text-ink-faint")}
        </a>""" for label, symbol, key in sections)
    switcher_items = "".join(f"""
        <a href="/{slug}/chats" data-bridge--menu-target="item" data-bridge-title="{esc(name)}"
           data-bridge-checked="{'true' if slug == account else 'false'}">{esc(name)}</a>""" for slug, name in ACCOUNTS.items())
    body = f"""
    <div class="page native-settings">
      <div class="native-actions" hidden>
        <div data-controller="bridge--menu" data-bridge-side="left" data-bridge-label="{esc(ACCOUNTS[account])}"
             data-bridge-header="Organizations">{switcher_items}
        </div>
      </div>
      <p class="micro native-settings__who">carmine@example.com · {esc(ACCOUNTS[account])}</p>
      <div class="rows">{rows}
      </div>
      <div class="rows">
        <form class="contents" method="post" action="/users/sign_out" data-turbo-confirm="Log out of Chat with Work?" data-bridge-confirm="Log out">
          <input type="hidden" name="_method" value="delete">
          <button type="submit" class="rows__row text-negative-ink">
            <span class="rows__logo">{icon("sign-out", "size-4")}</span><div class="rows__body"><h3>Log out</h3></div>
          </button>
        </form>
      </div>
    </div>"""
    return Page("Settings", body, account=account)


def sign_in_page(handler, error=None):
    providers = "".join(f"""
          <form method="post" action="/users/auth/{key}" data-turbo="false" data-controller="bridge--auth-session"
                data-action="submit->bridge--auth-session#signIn" data-bridge--auth-session-url-value="/native/sign_ins/new?provider={key}">
            <button class="btn btn-subtle" type="submit">{provider(icon_key, "size-4")}<span>Sign in with {label}</span></button>
          </form>""" for key, icon_key, label in [("google_oauth2", "google_drive", "Google"), ("slack", "slack", "Slack")])
    body = f"""
    <div class="auth">
      <div class="auth__panel">
        <div class="auth__providers">{providers}
        </div>
        <div class="auth__divider"><span>or with email</span></div>
        {'<p class="field__error">' + esc(error) + '</p>' if error else ''}
        <form class="auth__form" method="post" action="/users/sign_in" data-turbo="false">
          <div class="field"><label for="email">Email</label>
            <input id="email" class="input" type="email" name="identity[email]" autocomplete="username" autocapitalize="none" value="carmine@example.com"></div>
          <div class="field"><label for="password">Password</label>
            <input id="password" class="input" type="password" name="identity[password]" autocomplete="current-password" value="playground"></div>
          <input type="hidden" name="identity[remember_me]" value="1">
          <input type="submit" value="Sign in" class="btn btn-primary w-full">
        </form>
        <p class="auth__links">New to Chat with Work? <a href="/users/sign_up">Create an account</a></p>
      </div>
    </div>"""
    return Page("Sign in", body, body_class="auth-view")


def sign_up_page(handler):
    body = """
    <div class="auth">
      <div class="auth__panel">
        <form class="auth__form" method="post" action="/users" data-turbo="false">
          <div class="field"><label for="email">Email</label><input id="email" class="input" type="email" name="identity[email]"></div>
          <div class="field"><label for="password">Password</label><input id="password" class="input" type="password" name="identity[password]"></div>
          <input type="submit" value="Create account" class="btn btn-primary w-full">
        </form>
        <p class="auth__links">Already have an account? <a href="/users/sign_in">Sign in</a></p>
      </div>
    </div>"""
    return Page("Create an account", body, body_class="auth-view")


# MARK: - Server

class Handler(BaseHTTPRequestHandler):
    server_version = "ChatWithWorkPlayground/1"
    legacy_auth = False
    open_access = False

    def log_message(self, format, *args):
        print(f"{self.command} {self.path} -> {format % args}", flush=True)

    # Request helpers

    @property
    def user_agent(self):
        return self.headers.get("User-Agent", "")

    @property
    def native_platform(self):
        match = re.search(r"Chat with Work; platform=(\w+);", self.user_agent)
        if match:
            return match.group(1)
        return "ios" if re.search(r"(Turbo|Hotwire) Native", self.user_agent) else None

    @property
    def cookies(self):
        cookie = SimpleCookie(self.headers.get("Cookie", ""))
        return {key: morsel.value for key, morsel in cookie.items()}

    @property
    def signed_in(self):
        return Handler.open_access or self.cookies.get("pg_session") in SESSIONS

    @property
    def session(self):
        key = self.cookies.get("pg_session")
        with STATE_LOCK:
            return SESSIONS.setdefault(key or "anonymous", {"flash": [], "pinned": set(), "asked": {}, "paused": set()})

    def flash(self, kind, message):
        self.session["flash"].append((kind, message))

    def render_flash(self):
        messages, self.session["flash"] = self.session["flash"], []
        return "".join(
            f'<div data-controller="bridge--toast" data-bridge-type="{kind}" data-turbo-temporary hidden>{esc(message)}</div>'
            for kind, message in messages
        )

    def form(self):
        length = int(self.headers.get("Content-Length") or 0)
        data = self.rfile.read(length).decode() if length else ""
        if self.headers.get("Content-Type", "").startswith("application/json"):
            return json.loads(data or "{}")
        return {key: values[-1] for key, values in urllib.parse.parse_qs(data).items()}

    # Responses

    def send(self, status, body, content_type="text/html; charset=utf-8", headers=None):
        payload = body.encode() if isinstance(body, str) else body
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Cache-Control", "no-store")
        for key, value in (headers or {}).items():
            self.send_header(key, value)
        self.end_headers()
        self.wfile.write(payload)

    def redirect(self, location, status=303, headers=None):
        self.send_response(status)
        self.send_header("Location", location)
        self.send_header("Content-Length", "0")
        for key, value in (headers or {}).items():
            self.send_header(key, value)
        self.end_headers()

    def page(self, page, status=200):
        self.send(status, layout(self, page))

    def unauthorized(self):
        if self.native_platform and not Handler.legacy_auth:
            self.send(401, "You need to sign in.", "text/plain; charset=utf-8")
        else:
            self.redirect("/users/sign_in", 302)

    def recede(self, notice=None):
        query = "?" + urllib.parse.urlencode({"notice": notice}) if notice else ""
        self.redirect(f"/recede_historical_location{query}")

    # Routing

    def do_GET(self):
        url = urllib.parse.urlsplit(self.path)
        path, query = url.path, urllib.parse.parse_qs(url.query)

        if path.startswith("/assets/"):
            return self.proxy_asset(path)
        if path.startswith("/web/"):
            return self.static(REPO / path.lstrip("/"))
        if path.startswith("/playground/"):
            return self.static(ROOT / path.removeprefix("/playground/"))
        if path == "/configurations/ios_v1.json":
            return self.static(REPO / "ChatWithWork/Resources/path-configuration.json")
        if re.fullmatch(r"(/\d{7,})?/(recede|resume|refresh)_historical_location", path):
            return self.send(200, "Going back…")
        if path == "/users/sign_in":
            return self.page(sign_in_page(self))
        if path == "/users/sign_up":
            return self.page(sign_up_page(self))
        if path == "/":
            return self.redirect("/chats" if self.signed_in else "/users/sign_in", 302)

        if not self.signed_in:
            return self.unauthorized()

        match = re.fullmatch(r"(?:/(\d{7,}))?(/.*)", path)
        account, rest = match.group(1), match.group(2)
        if account is None:
            if rest in ("/chats", "/projects", "/settings", "/chats/new"):
                return self.redirect(f"/1000001{rest}" + (f"?{url.query}" if url.query else ""), 302)
            return self.send(404, "Not found", "text/plain")
        if account not in ACCOUNTS:
            return self.send(404, "Not found", "text/plain")

        page = None
        if rest == "/chats":
            page = chats_index(self, account)
        elif rest == "/chats/new":
            page = new_chat(self, account, (query.get("project_id") or [None])[0])
        elif m := re.fullmatch(r"/chats/(\d+)", rest):
            page = conversation(self, account, int(m.group(1)))
        elif m := re.fullmatch(r"/chats/(\d+)/edit", rest):
            page = rename_form(self, account, int(m.group(1)))
        elif m := re.fullmatch(r"/chats/(\d+)/project/edit", rest):
            page = move_form(self, account, int(m.group(1)))
        elif rest == "/projects":
            page = projects_index(self, account)
        elif rest == "/projects/new":
            page = project_form(self, account)
        elif m := re.fullmatch(r"/projects/(\d+)", rest):
            page = project_page(self, account, int(m.group(1)))
        elif rest == "/settings":
            page = settings_page(self, account, (query.get("tab") or [""])[0])

        if page is None:
            return self.send(404, "Not found", "text/plain")
        self.page(page)

    def do_POST(self):
        url = urllib.parse.urlsplit(self.path)
        path = url.path
        form = self.form()
        method = (form.get("_method") or "post").lower() if isinstance(form, dict) else "post"

        if path == "/users/sign_in":
            token = f"session-{time.time_ns()}"
            with STATE_LOCK:
                SESSIONS[token] = {"flash": [("notice", "Signed in.")], "pinned": set(), "asked": {}, "paused": set()}
            cookie = f"pg_session={token}; Path=/; HttpOnly; Max-Age=1209600; SameSite=Lax"
            target = "/recede_historical_location" if self.native_platform else "/1000001/chats/new"
            return self.redirect(target, 302, {"Set-Cookie": cookie})
        if path == "/users/sign_out" and method == "delete":
            with STATE_LOCK:
                SESSIONS.pop(self.cookies.get("pg_session"), None)
            return self.redirect("/users/sign_in", 303, {"Set-Cookie": "pg_session=; Path=/; Max-Age=0"})
        if path == "/native/push_registrations":
            print(f"push registration: {json.dumps(form)}", flush=True)
            return self.send(201, json.dumps({"ok": True}), "application/json")

        if not self.signed_in:
            return self.unauthorized()

        match = re.fullmatch(r"/(\d{7,})(/.*)", path)
        if not match:
            return self.send(404, "Not found", "text/plain")
        account, rest = match.groups()

        if rest == "/messages":
            number = max(CHATS) + 1
            project = PROJECTS.get(int(form.get("project_id") or 0))
            CHATS[number] = {"title": (form.get("message[content]") or "New chat")[:60], "project": project and project["name"],
                             "when": "Today", "processing": False}
            self.session["asked"][number] = [form.get("message[content]") or ""]
            return self.redirect(f"/{account}/chats/{number}")
        if m := re.fullmatch(r"/chats/(\d+)/messages", rest):
            # The server answers a reply with 200 and broadcasts the messages;
            # the playground has no cable, so it sends them as Turbo Streams.
            number = int(m.group(1))
            text = form.get("message[content]") or ""
            asked = self.session["asked"].setdefault(number, [])
            asked.append(text)
            if "text/vnd.turbo-stream.html" not in self.headers.get("Accept", ""):
                return self.redirect(f"/{account}/chats/{number}")
            author = "Carmine" if CHATS.get(number, {}).get("project") else None
            streams = [turbo_stream("append", "chat_messages", exchange(account, number, len(asked) - 1, text, author))]
            if number == 42 and self.session.get("approval", "waiting") == "waiting":
                # Asking something else passes on the change that was waiting.
                self.session["approval"] = "passed"
                streams.append(turbo_stream("replace", "activity_14", recap_activity(account, number, "passed")))
                streams.append(turbo_stream("update", "typing_indicator", '<div class="hidden"></div>'))
            return self.send(200, "".join(streams), "text/vnd.turbo-stream.html; charset=utf-8")
        if m := re.fullmatch(r"/chats/(\d+)/pin", rest):
            number = int(m.group(1))
            pinned = self.session["pinned"]
            if method == "delete":
                pinned.discard(number)
                self.flash("notice", "Unpinned from the sidebar.")
            else:
                pinned.add(number)
                self.flash("notice", "Pinned to the sidebar.")
            return self.redirect(f"/{account}/chats/{number}")
        if m := re.fullmatch(r"/chats/(\d+)", rest):
            number = int(m.group(1))
            if method == "delete":
                CHATS.pop(number, None)
                return self.recede("Chat deleted.")
            if method == "patch":
                CHATS[number]["title"] = form.get("chat[title]") or CHATS[number]["title"]
                return self.recede("Chat renamed.")
        if m := re.fullmatch(r"/chats/(\d+)/project", rest):
            number = int(m.group(1))
            project = PROJECTS.get(int(form.get("project") or 0))
            CHATS[number]["project"] = project["name"] if project else None
            return self.recede(f"Moved to {project['name']}." if project else "Moved out of its project.")
        if m := re.fullmatch(r"/chats/(\d+)/tool_calls/\d+/(approval|denial)", rest):
            approved = m.group(2) == "approval"
            self.session["approval"] = "approved" if approved else "denied"
            self.session["denial_reason"] = None if approved else (form.get("reason") or "").strip() or None
            self.flash("notice", "Approved. Posting to Slack." if approved else "Denied. The assistant won't post it.")
            return self.redirect(f"/{account}/chats/{m.group(1)}")
        if m := re.fullmatch(r"/chats/(\d+)/share_link", rest):
            self.flash("notice", "Stopped sharing. The link no longer works.")
            return self.redirect(f"/{account}/chats/{m.group(1)}")
        if m := re.fullmatch(r"/settings/connectors/(\w+)/pause", rest):
            paused = self.session["paused"]
            (paused.discard if method == "delete" else paused.add)(m.group(1))
            return self.redirect(f"/{account}/chats/new")
        if m := re.fullmatch(r"/chats/(\d+)/messages/\d+/(retries|branches)", rest):
            self.flash("notice", "Asking again." if m.group(2) == "retries" else "Branched into a new chat.")
            return self.redirect(f"/{account}/chats/{m.group(1)}")
        if rest == "/projects":
            number = max(PROJECTS) + 1
            PROJECTS[number] = {"name": form.get("project[name]") or "Untitled", "hq": False, "all_access": False,
                                "summary": "Invite-only · 1 person", "audience": "1 person", "chats": 0}
            self.flash("notice", "Project created.")
            return self.redirect(f"/{account}/projects/{number}")
        return self.send(404, "Not found", "text/plain")

    # Files

    def static(self, file):
        try:
            data = Path(file).read_bytes()
        except OSError:
            return self.send(404, "Not found", "text/plain")
        types = {".js": "text/javascript", ".css": "text/css", ".json": "application/json", ".svg": "image/svg+xml"}
        self.send(200, data, types.get(Path(file).suffix, "application/octet-stream") + "; charset=utf-8")

    def proxy_asset(self, path):
        cached = ASSETS["cache"].get(path)
        if cached is None:
            try:
                with urllib.request.urlopen(ASSETS["origin"] + path, timeout=20) as response:
                    cached = (response.read(), response.headers.get("Content-Type", "application/octet-stream"))
            except Exception:
                return self.send(404, "Not found", "text/plain")
            ASSETS["cache"][path] = cached
        self.send(200, cached[0], cached[1], {"Cache-Control": "max-age=3600"})


def discover_stylesheets(origin):
    with urllib.request.urlopen(origin + "/users/sign_in", timeout=20) as response:
        page = response.read().decode()
    found = re.findall(r'href="(/assets/(?:application|tailwind)-[0-9a-f]+\.css)"', page)
    return list(dict.fromkeys(found))


def discover_provider_icons(origin):
    """Assets are only served under their digested names. The integrations
    page shows every service's logo and the homepage the model makers', so
    read the names from those."""
    icons = {}
    for page_path in ("/integrations", "/"):
        with urllib.request.urlopen(origin + page_path, timeout=30) as response:
            page = response.read().decode()
        for path, name in re.findall(r'(/assets/providers/([a-z0-9_]+)-[0-9a-f]{8}\.(?:svg|png))', page):
            icons.setdefault(name, path)
    return icons


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--assets-from", default="https://staging.chatwithwork.com")
    parser.add_argument("--legacy-auth", action="store_true", help="redirect to sign-in instead of answering 401")
    parser.add_argument("--open", action="store_true", help="treat every request as signed in")
    args = parser.parse_args()

    Handler.legacy_auth = args.legacy_auth
    Handler.open_access = args.open
    ASSETS["origin"] = args.assets_from.rstrip("/")
    ASSETS["css"] = discover_stylesheets(ASSETS["origin"])
    ASSETS["providers"] = discover_provider_icons(ASSETS["origin"])
    print(f"Stylesheets from {ASSETS['origin']}: {', '.join(ASSETS['css'])}; {len(ASSETS['providers'])} provider icons", flush=True)

    server = ThreadingHTTPServer(("0.0.0.0", args.port), Handler)
    print(f"Playground on http://localhost:{args.port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
