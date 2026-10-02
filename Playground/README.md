# Playground

A stand-in for the Chat with Work server as `docs/server-contract.md`
describes it, so the app's signed-in shell and every bridge component can be
run without an account or a Rails checkout. See the main README, "The
playground".

- `server.py`: the server (Python 3, standard library only).
- `playground.js`, `playground.css`: Turbo, Stimulus, the bridge controllers
  from `web/controllers/bridge/`, and stand-ins for the web app's own
  controllers and editor.
- `icons.json`: the [Phosphor](https://phosphoricons.com) icons the pages use
  (bold weight), MIT licensed, copyright Phosphor Icons.

The pages are fixtures in the web app's markup, styled by its stylesheet,
which the server fetches from a running Chat with Work server (staging by
default) and serves as its own. Everything on them is made up.
