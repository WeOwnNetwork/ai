# Harbor View drag-drop upload instructions

Branch `fix/patrick-chat-dragdrop` was created from `fix/patrick-doc-scope-no-delete`.

MCP `create_or_update_file` / `push_files` could not carry the full ~48KB `server.js` and ~99KB `index.html` bodies in this agent session (writes truncated to literal short strings). Local builds are ready:

| File | Desktop path | SHA256 |
|------|--------------|--------|
| server.js | `/home/box/Desktop/weownchat-p0/server.js` | `1780592c7bd579c04d8682786d84d84604d9c5db03663a8bd5fbc4c782d74adc` |
| index.html | `/home/box/Desktop/weownchat-p0/public/index.html` | `c0c789c28c7478a7256726aa226a774e72b12617755de9a8a846747abd21cc64` |

## Browser upload (required)

1. Open https://github.com/SinachPat/weownchat/tree/fix/patrick-chat-dragdrop/anythingllm-docker/template/dashboard
2. Replace `server.js` with Desktop copy (edit → upload / paste).
3. Replace `public/index.html` the same way.
4. Delete `.dragdrop-marker.txt` and this instructions file if desired.
5. Open PR to `WeOwnNetwork/ai` base `main` head `SinachPat:fix/patrick-chat-dragdrop` (or fork PR if 403).

## What the full files implement

- **A**: preventDefault dragover/drop on private chat; drag-over affordance; unsupported types → `#chat-error`
- **B**: drop on chat/lib → `POST /api/upload` (private or `currentTab()`)
- **C**: paperclip queues ALLM chat `attachments` (`mime: application/anythingllm-document`); server forwards on `/api/chat`
