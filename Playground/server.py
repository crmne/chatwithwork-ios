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
PROVIDERS = {
    "google_drive": "Google Drive", "slack": "Slack", "dropbox": "Dropbox",
    "onedrive": "OneDrive", "gmail": "Gmail", "notion": "Notion",
}

STATE_LOCK = threading.Lock()
SESSIONS = {}  # cookie value -> {"flash": [(type, message)], "pinned": set()}
CHATS = {
    42: {"title": "Q3 launch commitments for Acme", "project": None, "when": "Today", "processing": False},
    41: {"title": "Summarize the security review thread", "project": "Acme launch", "when": "Today", "processing": False},
    38: {"title": "Which customers asked about SSO?", "project": None, "when": "Yesterday", "processing": False},
    35: {"title": "Draft the onboarding checklist", "project": "Onboarding", "when": "Previous 7 days", "processing": False},
    31: {"title": "Find the signed order form from Initech", "project": None, "when": "Previous 7 days", "processing": False},
}
PROJECTS = {
    1: {"name": "Acme", "hq": True, "summary": "Everyone in Acme", "chats": 12},
    2: {"name": "Acme launch", "hq": False, "summary": "Invite-only · 4 people", "chats": 7},
    3: {"name": "Onboarding", "hq": False, "summary": "All-Access", "chats": 3},
}
ASSETS = {"css": [], "cache": {}, "providers": {}}


def icon(name, cls="size-4"):
    return f'<svg viewBox="0 0 256 256" fill="currentColor" width="20" height="20" aria-hidden="true" class="{cls}">{ICONS[name]}</svg>'


def provider(key, cls=""):
    src = ASSETS["providers"].get(key, f"/assets/providers/{key}.svg")
    return f'<img alt="" width="64" height="64" class="{cls}" src="{src}">'


def esc(value):
    return html.escape(str(value), quote=True)


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

    sections = []
    for label, chats in groups.items():
        rows = "\n".join(f"""
          <li class="chat-history__row" data-search-target="item">
            <a class="chat-history__link" href="/{account}/chats/{number}">
              {'<span class="dot dot--small dot--live dot--pulse" title="Working"></span>' if chat["processing"] else ''}
              <span class="chat-history__title">{esc(chat["title"])}</span>
              <time class="micro">{'2 hours ago' if label == 'Today' else '1 day ago' if label == 'Yesterday' else '4 days ago'}</time>
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
        <div><h1>Chats</h1><p class="micro">{len(CHATS)} chats</p></div>
      </header>
      <a href="/{account}/chats/new" class="btn btn-primary btn-sm native-hidden"
         data-controller="bridge--button" data-bridge-title="New chat"
         data-bridge-ios-image="square.and.pencil" data-bridge-android-image="edit_square">{icon("note-pencil")} New chat</a>
      <label class="input w-full native-search-field">
        {icon("magnifying-glass", "size-4 text-ink-faint")}
        <input type="search" placeholder="Search your chats" aria-label="Search your chats" autocomplete="off"
               data-search-target="input" data-bridge--search-target="input" data-action="input->search#filter">
      </label>
      {''.join(sections)}
    </div>"""
    return Page("Chats", body, account=account)


def message_actions(number, message_id, copy_text, project_chat=False):
    share = "" if project_chat else f"""
        <button type="button" class="message__action tooltip" data-tip="Share" aria-label="Share a public link to this chat"
                data-bridge--context-menu-target="item" data-bridge-title="Share link" data-bridge-ios-image="link"
                data-bridge-android-image="link" onclick="document.getElementById('share-dialog').showModal()">{icon("export")}</button>"""
    return f"""
      <footer class="message__footer">
        <div class="message__actions" data-controller="bridge--context-menu">
          <pre hidden data-bridge--context-menu-target="copySource">{esc(copy_text)}</pre>
          <button type="button" class="message__action tooltip" data-tip="Copy" aria-label="Copy message"
                  data-bridge--context-menu-target="item" data-bridge-title="Copy" data-bridge-ios-image="doc.on.doc"
                  data-bridge-android-image="content_copy" data-bridge-copy="true">{icon("copy")}</button>
          <form class="contents" method="post" action="/1000001/chats/{number}/messages/{message_id}/retries"
                data-turbo-confirm="Retry this answer?" data-bridge-confirm="Retry"
                data-bridge-description="Everything after the question, including this reply, will be removed, and the assistant will answer it again.">
            <button type="submit" class="message__action tooltip" data-tip="Retry" aria-label="Retry this answer"
                    data-bridge--context-menu-target="item" data-bridge-title="Retry" data-bridge-ios-image="arrow.clockwise"
                    data-bridge-android-image="refresh">{icon("arrows-clockwise")}</button>
          </form>
          <form class="contents" method="post" action="/1000001/chats/{number}/messages/{message_id}/branches">
            <button type="submit" class="message__action tooltip" data-tip="Branch into a new chat" aria-label="Branch into a new chat"
                    data-bridge--context-menu-target="item" data-bridge-title="Branch into a new chat"
                    data-bridge-ios-image="arrow.triangle.branch" data-bridge-android-image="call_split">{icon("git-branch")}</button>
          </form>{share}
          <button type="button" class="message__action message__more" aria-label="More actions"
                  data-bridge--context-menu-target="trigger" data-action="bridge--context-menu#show">{icon("dots-three")}</button>
        </div>
        <div class="sources">
          <div class="sources__trigger" role="button" tabindex="0" aria-label="2 sources">
            <span class="avatar-stack avatar-stack--small">
              <span class="avatar-stack__item">{provider("google_drive")}</span>
              <span class="avatar-stack__item">{provider("slack")}</span>
            </span>
            <span>Sources</span><span class="micro">2</span>
          </div>
        </div>
      </footer>"""


def composer(account, number=None, placeholder="Reply to Chat with Work", working=False):
    action = f"/{account}/chats/{number}/messages" if number else f"/{account}/messages"
    send = f"""
          <a id="submit_button" href="/{account}/chats/{number}/cancellation" data-turbo-method="post"
             class="btn btn-primary btn-square btn-sm chat-prompt__send chat-prompt__stop" aria-label="Stop response">
            <span class="chat-prompt__ring" aria-hidden="true"></span>{icon("stop", "size-3.5")}
          </a>""" if working else f"""
          <button id="submit_button" type="submit" class="btn btn-primary btn-square btn-sm chat-prompt__send"
                  aria-label="Send message" data-composer-target="send" disabled>{icon("arrow-up")}</button>"""
    return f"""
    <div id="new_message" class="composer rainbow-glow{' composer--working' if working else ''}"
         data-controller="composer bridge--haptic" data-bridge-feedback="light">
      <form action="{action}" method="post" data-action="submit->composer#submit turbo:submit-start->bridge--haptic#vibrate">
        <div class="chat-prompt">
          <div class="chat-prompt__field">
            <textarea name="message[content]" rows="1" placeholder="{esc(placeholder)}" aria-label="Message"
                      class="chat-compose-editor playground-editor" data-composer-target="input"
                      data-action="input->composer#update keydown.meta+enter->composer#submit"></textarea>
          </div>
          <div class="chat-prompt__bar">
            <button type="button" class="btn btn-ghost btn-sm btn-square chat-prompt__attach" aria-label="Attach files">
              {icon("paperclip")}
            </button>
            <button type="button" class="model-picker__trigger btn btn-ghost btn-sm">
              {provider("gemini", "size-4")}<span>Gemini 3.8 Flash</span>
            </button>
            {send}
          </div>
        </div>
      </form>
    </div>"""


def conversation(handler, account, number):
    chat = CHATS.get(number)
    if chat is None:
        return None
    session = handler.session
    pinned = number in session["pinned"]
    copy = "Acme launches on September 30, with single sign-on and EU-only hosting, as the plan and the signed order form say. Priya confirmed the date with their team on Monday."
    project_line = f"""
      <div class="chat-project">{icon("folder-simple")}<span><a class="chat-project__name" href="/{account}/projects/2">{esc(chat["project"])}</a> · shared with 4 people</span></div>""" if chat["project"] else ""

    approval = f"""
      <section id="tool_call_9" class="approval" aria-labelledby="approval_summary_9">
        <header class="approval__header">
          <span class="avatar-stack"><span class="avatar-stack__item">{provider("slack")}</span></span>
          <div class="approval__heading">
            <p class="approval__kicker">Needs your approval · Slack</p>
            <h3 id="approval_summary_9" class="approval__summary">Post a message to #acme-launch</h3>
          </div>
        </header>
        <div class="approval__preview">
          <div class="approval__letter">
            <dl class="approval__envelope">
              <div><dt>To</dt><dd>#acme-launch</dd></div>
              <div><dt>As</dt><dd>You, from your Slack account</dd></div>
            </dl>
            <div class="approval__body">Recap: Acme launches September 30 with single sign-on and EU-only hosting, as the plan and the signed order form say.</div>
          </div>
        </div>
        <form id="denial_9" class="approval__reason" method="post" action="/{account}/chats/{number}/tool_calls/9/denial"
              data-controller="bridge--haptic" data-bridge-feedback="warning" data-action="turbo:submit-start->bridge--haptic#vibrate">
          <details><summary>Deny with a reason</summary>
            <input type="text" name="reason" class="input input-sm" placeholder="Say what to do instead (optional)" autocomplete="off">
          </details>
        </form>
        <form class="approval__actions" method="post" action="/{account}/chats/{number}/tool_calls/9/approval"
              data-controller="bridge--haptic" data-bridge-feedback="success" data-action="turbo:submit-start->bridge--haptic#vibrate">
          <label class="approval__allow">
            <input type="checkbox" name="for_rest_of_chat" value="1" class="checkbox checkbox-xs">
            <span>Allow “Post message” in Slack for the rest of this chat</span>
          </label>
          <div class="approval__buttons">
            <button type="submit" form="denial_9" class="btn btn-sm btn-subtle">Deny</button>
            <button type="submit" class="btn btn-sm btn-primary">Approve</button>
          </div>
        </form>
      </section>
      <p class="thinking thinking--approval"><span class="thinking__mark">{icon("hand")}</span>
        <span class="thinking__label">Waiting for your approval. <a class="thinking__link" href="#tool_call_9">Review</a></span></p>""" if handler.session.get("approval", "waiting") == "waiting" and number == 42 else ""

    extra = "".join(f"""
      <turbo-frame id="message_{100 + index * 2}"><div class="message message--user" tabindex="-1"><div class="message__bubble">{esc(text)}</div></div></turbo-frame>
      <turbo-frame id="message_{101 + index * 2}"><div class="message message--assistant" tabindex="-1"><div class="message__body prose"><p>I looked in your connected services. This is a playground, so this answer is made up.</p></div>
      </div></turbo-frame>""" for index, text in enumerate(session.get("asked", {}).get(number, [])))

    menu_items = f"""
        <form class="contents" method="post" action="/{account}/chats/{number}/pin" id="chat_{number}_pin_form">
          {'<input type="hidden" name="_method" value="delete">' if pinned else ''}
          <button type="submit" id="chat_{number}_pin_item" data-bridge--menu-target="item"
                  data-bridge-title="{'Unpin' if pinned else 'Pin'}" data-bridge-ios-image="{'pin.slash' if pinned else 'pin'}"
                  data-bridge-android-image="keep">{'Unpin' if pinned else 'Pin'}</button>
        </form>
        <button type="button" data-bridge--menu-target="item" data-bridge-title="Share link" data-bridge-ios-image="link"
                data-bridge-android-image="link" onclick="document.getElementById('share-dialog').showModal()">Share link</button>
        <a href="/{account}/chats/{number}/edit" data-bridge--menu-target="item" data-bridge-title="Rename"
           data-bridge-ios-image="pencil" data-bridge-android-image="edit">Rename</a>
        <a href="/{account}/chats/{number}/project/edit" data-bridge--menu-target="item" data-bridge-title="Move to project"
           data-bridge-ios-image="folder" data-bridge-android-image="drive_file_move">Move to project</a>
        <a href="/{account}/chats/{number}?recede=1" data-turbo-method="delete" data-turbo-confirm="Delete this chat?"
           data-bridge--menu-target="item" data-bridge-title="Delete" data-bridge-ios-image="trash"
           data-bridge-android-image="delete" data-bridge-destructive="true">Delete</a>"""

    body = f"""
    <div class="native-actions" hidden>
      <a href="/{account}/chats/new" data-controller="bridge--button" data-bridge-title="New chat"
         data-bridge-ios-image="square.and.pencil" data-bridge-android-image="edit_square">New chat</a>
      <div data-controller="bridge--menu" data-bridge-label="Chat options">{menu_items}
      </div>
    </div>

    <div class="conversation">
      <div class="conversation__scroll">
        <div class="conversation__column">{project_line}
          <div id="chat_messages">
            <turbo-frame id="message_6"><div class="message message--user" tabindex="-1">
              <div class="message__bubble">What did we promise Acme for the Q3 launch?</div>
            </div></turbo-frame>

            <details class="activity">
              <summary class="activity__line">
                <span class="avatar-stack avatar-stack--small">
                  <span class="avatar-stack__item">{provider("google_drive")}</span>
                  <span class="avatar-stack__item">{provider("slack")}</span>
                </span>
                <span class="activity__summary">Read 2 documents in Google Drive and Slack</span>
              </summary>
            </details>

            <turbo-frame id="message_7"><div class="message message--assistant" tabindex="-1">
              <div class="message__body prose">
                <p>Acme launches on <strong>September 30</strong>, with single sign-on and EU-only hosting, as the plan and the signed order form say. Priya confirmed the date with their team on Monday.</p>
                <ul>
                  <li>Single sign-on with their identity provider from day one</li>
                  <li>Hosting in the EU only, written into the order form</li>
                  <li>A named contact for the first 90 days</li>
                </ul>
              </div>{message_actions(number, 7, copy, project_chat=bool(chat["project"]))}
            </div></turbo-frame>

            <turbo-frame id="message_8"><div class="message message--user" tabindex="-1">
              <div class="message__bubble">Post a recap to #acme-launch.</div>
            </div></turbo-frame>{approval}{extra}
          </div>
        </div>
      </div>

      <div class="conversation__dock">
        <div class="conversation__dock-inner">{composer(account, number)}
        </div>
      </div>
    </div>

    <dialog id="share-dialog" class="modal">
      <div class="modal-box max-w-md">
        <header class="dialog__header"><h3>Share this chat</h3>
          <p>Anyone with the link can read the questions and answers, not what your tools returned.</p></header>
        <div class="share-link"><input class="input w-full" readonly value="https://chatwithwork.com/shared/3f9c2a"></div>
        <div class="modal-action">
          <form method="dialog"><button class="btn btn-subtle">Done</button></form>
          <button class="btn btn-primary" data-controller="bridge--share" data-action="bridge--share#share"
                  data-bridge-url="https://chatwithwork.com/shared/3f9c2a" data-bridge-title="{esc(chat['title'])}">Share link</button>
        </div>
      </div>
      <form method="dialog" class="modal-backdrop"><button>close</button></form>
    </dialog>"""
    return Page(chat["title"], body, body_class="chat-view", account=account)


def new_chat(handler, account):
    suggestions = [
        ("google_drive", "What changed in our Q3 plan since last week?"),
        ("slack", "Summarize #acme-launch from the last three days"),
        ("gmail", "Which customers are waiting on a reply from me?"),
    ]
    rows = "".join(f"""
          <button type="button" class="suggestion" data-action="composer#suggest" data-text="{esc(text)}">
            <span class="avatar-stack avatar-stack--small"><span class="avatar-stack__item">{provider(key)}</span></span>
            <span>{esc(text)}</span>
          </button>""" for key, text in suggestions)
    body = f"""
    <div class="new-chat">
      <div class="new-chat__backdrop dot-grid dot-grid--fade" aria-hidden="true"></div>
      <h1 class="new-chat__greeting">Good afternoon, Carmine</h1>
      {composer(account, placeholder="Ask anything…")}
      <div class="playground-suggestions">{rows}
      </div>
    </div>"""
    return Page("New chat", body, account=account)


def projects_index(handler, account):
    rows = "".join(f"""
        <a class="rows__row" href="/{account}/projects/{number}">
          <span class="rows__logo">{icon("buildings" if project["hq"] else "folder-simple")}</span>
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
          <span class="rows__logo">{icon(symbol)}</span>
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
            <span class="rows__logo">{icon("sign-out")}</span><div class="rows__body"><h3>Log out</h3></div>
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
            return SESSIONS.setdefault(key or "anonymous", {"flash": [], "pinned": set(), "asked": {}})

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
            page = new_chat(self, account)
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
                SESSIONS[token] = {"flash": [("notice", "Signed in.")], "pinned": set(), "asked": {}}
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
            CHATS[number] = {"title": (form.get("message[content]") or "New chat")[:60], "project": None, "when": "Today", "processing": False}
            self.session["asked"][number] = [form.get("message[content]") or ""]
            return self.redirect(f"/{account}/chats/{number}")
        if m := re.fullmatch(r"/chats/(\d+)/messages", rest):
            number = int(m.group(1))
            self.session["asked"].setdefault(number, []).append(form.get("message[content]") or "")
            return self.redirect(f"/{account}/chats/{number}")
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
            self.session["approval"] = "decided"
            self.flash("notice", "Approved. Posting to Slack." if m.group(2) == "approval" else "Denied. The assistant won't post it.")
            return self.redirect(f"/{account}/chats/{m.group(1)}")
        if m := re.fullmatch(r"/chats/(\d+)/messages/\d+/(retries|branches)", rest):
            self.flash("notice", "Asking again." if m.group(2) == "retries" else "Branched into a new chat.")
            return self.redirect(f"/{account}/chats/{m.group(1)}")
        if rest == "/projects":
            number = max(PROJECTS) + 1
            PROJECTS[number] = {"name": form.get("project[name]") or "Untitled", "hq": False, "summary": "Invite-only · 1 person", "chats": 0}
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
    """Assets are only served under their digested names; the integrations
    page shows every provider's icon, so read the names from there."""
    icons = {}
    with urllib.request.urlopen(origin + "/integrations", timeout=30) as response:
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
