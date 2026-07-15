# Connecting to the `dev-weown-devbox` dev box with Zed

Welcome! This is the team's shared developer machine. You get your own account
on it, you connect from your laptop using [Zed](https://zed.dev), and your AI
agents run on your own OpenRouter key. This guide gets you from zero to coding
in about five minutes.

You only do **Steps 1-3 once**. After that, opening the box is one click.

---

## What your operator gives you

Before you start, whoever set up the box (your admin) will send you two things:

- **Your login** — it's your CCC Short ID in lowercase, e.g. `ccc-alice`.
- **The box's address** — an IP like `203.0.113.10` (or the hostname
  `dev.weown.tools`).

Your own SSH key already opens your account (you sent your **public** key to the
admin to be added). If `ssh` works, Zed will too.

> One key, one account: your key opens **only** your account. You don't have
> root, and you don't share a login with anyone. That's by design.

---

## Step 1 — Check you can SSH in

Open a terminal on your laptop and run (swap in your login and the IP):

```bash
ssh ccc-alice@203.0.113.10
```

The first time, SSH asks you to trust the host fingerprint — type `yes`. You
should land at a shell prompt on the box. If you get in, type `exit` and move
on. If it refuses you, send your admin the **public** key you're using
(`cat ~/.ssh/id_ed25519.pub`) and your CCC Short ID, and ask them to re-run the
deploy.

> Tip: if you have several SSH keys, point at the right one:
> `ssh -i ~/.ssh/id_ed25519 ccc-alice@203.0.113.10`. You can make this the
> default for the box by adding a `Host` block to `~/.ssh/config` — Zed reads
> that file, so it keeps things tidy on the Zed side too.

---

## Step 2 — Add the box as a remote in Zed

Zed has built-in **Remote Development**: your local Zed connects over SSH and
sets up its own server on the box automatically. Nothing to pre-install on the
box.

1. Open Zed on your laptop.
2. Open the project picker: **`Cmd-Shift-P`** (macOS) or **`Ctrl-Shift-P`**
   (Linux), then run **`projects: open remote`** (you can also click the project
   name in the title bar and choose **Open a Remote Project**).
3. Click **Connect New Server** (or the **+**) and enter the SSH destination —
   the same thing you typed in Step 1:

   ```
   ccc-alice@203.0.113.10
   ```

4. Zed connects, installs its remote server for you, and asks which folder to
   open. Pick your home directory (e.g. `/home/ccc-alice`) or a project folder
   inside it.

That's it — you're now editing on the box from your laptop. Next time, the
server shows up in **Open a Remote Project** and it's a single click.

---

## Step 3 — Run `setup-zed` to add your OpenRouter key

Your AI features (chat, inline assist, agents) run on **your own**
[OpenRouter](https://openrouter.ai) key. A one-time helper wires it up.

1. Open a terminal **on the box** — the quickest way is Zed's built-in terminal
   (**`Ctrl-` ``** in the remote window), or just `ssh` in from Step 1.
2. Run:

   ```bash
   setup-zed
   ```

3. It prompts you to **paste your OpenRouter API key** (get one at
   <https://openrouter.ai/keys>). The key is hidden as you type — it is never
   shown on screen, never logged, and never put in any shared file. It's saved
   only to your private
   `~/.config/dev_weown_devbox/openrouter.env` (readable
   only by you).
4. The script adds an OpenAI-compatible **`openrouter`** model provider to your
   Zed settings on the box, pointing at `https://openrouter.ai/api/v1`. The key
   itself is **not** written into settings — Zed reads it from the environment
   the helper set up for you.

> Want central rotation instead of a file? `setup-zed` will also offer an
> optional Infisical path: it logs in to **your own** Infisical account, stores
> the key there, and gives you a `zed-infisical` launcher so you can rotate the
> key without touching any file on the box. It's optional — the simple paste
> flow above works perfectly on its own.

After it finishes, open a **fresh** terminal (or run `exec $SHELL`) so the new
environment loads.

---

## Step 4 — Use your AI agents

Open the assistant in Zed (the sparkle/assistant icon in the right panel, or
**`Cmd-?`** / **`Ctrl-?`**), pick a model under the **OpenRouter** provider, and
start chatting, asking for edits, or running agents. Every request bills to
**your** OpenRouter key — nobody shares cost or quota.

> **Important — the assistant runs on your laptop, not the box.** In Zed Remote
> Development the editor lives on the box but the AI assistant runs **client-side
> (on your laptop)**. So you need the same OpenRouter provider configured in your
> **local** Zed too. `setup-zed` prints the exact JSON snippet to paste — open
> your local Zed settings with **`Cmd-,`** / **`Ctrl-,`** and add it (and set
> `OPENAI_API_KEY` to your OpenRouter key in your laptop's shell environment).
> One-time, and then your agents just work.

---

## Good to know

- **It's a shared machine.** Others have their own accounts here. Keep your work
  in your home directory, and be considerate with heavy builds — everyone shares
  the CPU and RAM.
- **Your files are backed up.** Home directories are backed up daily, so don't
  panic about losing work — but still push your code to git regularly.
- **The toolchain is already there.** git, Python, Node.js, ripgrep, OpenTofu,
  and the language servers Zed uses for Python/YAML/Ansible are pre-installed.
  Just start coding.
- **Docker?** Only some members have Docker access (it's granted on request
  because it's powerful enough to act like root). If you need it, ask your admin
  to set `docker: true` for you.
- **Stuck?** Re-running `setup-zed` is always safe (it won't overwrite your
  settings destructively). For access problems, your admin re-runs the deploy
  after fixing your entry in the roster.

Happy hacking!
