# TODO

Future plans for 有谱 (YouPu) - the proactive AI assistant.

## Vision: Spirit (L3)

An always-listening AI butler that works proactively.

```
Voice → Spirit → Note → Background Task → Inbox → Deliver
                                                    ↓
                                         Silent / Nudge / Interrupt
```

### Interrupt Formula
```
INTERRUPT = TIME-SENSITIVE + CONSEQUENCE

Both must be true:
- Time-sensitive: Opportunity will be lost soon
- Consequence: User will suffer if they miss it

Examples:
✓ INTERRUPT: "Flight boards in 10 min" (time + consequence)
✗ NUDGE: "Sale ends tonight" (time, but minor consequence)
✗ SILENT: Research ready (no urgency)
```

### Architecture

| Level | Name | Status | Purpose |
|-------|------|--------|---------|
| L1 | System Keeper | ✅ Done | Health monitor (pure code) |
| L2 | Verifier | ✅ Done | Quality assurance (LLM) |
| L3 | Spirit | ❌ TODO | Proactive orchestrator (continuous LLM) |

### Client-Cloud Split

```
CLIENT (Swift)              CLOUD (Container)
─────────────               ─────────────────
• Voice capture             • Spirit (L3)
• Whisper transcription     • Task agents
• Speaker ID                • World.log
• Hand tracking (MediaPipe) • L1/L2 supervisors
• UI rendering              • Tools (browser, etc)
        ←── WebSocket ──→
```

## TODO Items

### Spirit Pipeline
- [ ] Note stage (observation recording)
- [ ] Background stage (silent task spawning)
- [ ] Inbox query (verified AND NOT delivered)
- [ ] Delivery decision (silent/nudge/interrupt)
- [ ] Time-sensitive detection
- [ ] Consequence evaluation

### Swift Client
- [ ] Spirit floating window UI
- [ ] Visual states (idle/working/ready)
- [ ] Nudge bubbles (dismissable)
- [ ] Interrupt modals (must acknowledge)
- [ ] WebSocket connection to cloud

### Voice Integration
- [x] Whisper transcription (Python)
- [x] Speaker ID models
- [ ] Real-time streaming to Spirit
- [ ] Voice output (TTS)

### Gesture Control (MediaPipe + Three.js)
Camera-based hand tracking for Spirit UI control.

```
Webcam → MediaPipe Hands → 21 landmarks/hand → Three.js → Particle/UI control
```

**Use cases:**
- Wave to dismiss nudge
- Pinch to expand/collapse
- Swipe to navigate inbox
- Point to select

**Resources:**
- [Codrops Tutorial](https://tympanus.net/codrops/2024/10/24/creating-a-3d-hand-controller-using-a-webcam-with-mediapipe-and-three-js/)
- [threejs-handtracking-101](https://github.com/collidingScopes/threejs-handtracking-101)
- [Bolt.new particle effects](https://bolt.new/blog/build-rebuilds-interactive-particle-effects-with-hand-tracking)

Tasks:
- [ ] Prototype hand tracking in browser
- [ ] Define gesture vocabulary (dismiss, expand, scroll)
- [ ] Integrate with Spirit UI
- [ ] Particle effects responding to hand movement

### Infrastructure

**Architecture:**
```
LOCAL (iOS/macOS)           CLOUD (iMac Server)
────────────────            ───────────────────
User's device               Dedicated iMac hosting multiple containers
• Voice/gesture input       • Apple Container VMs (isolated workspaces)
• Spirit UI                 • Each agent gets own container + workspace folder
• Thin client               • Tools: browser, git, filesystem access
                            • World.log shared across containers
        ←── WebSocket ──→
```

**Workspace:** Each AI agent runs in its own Apple Container with:
- Dedicated folder (`/workspace/agent-{id}/`)
- Isolated filesystem
- Browser instance
- Git access

Tasks:
- [ ] Apple Container setup on iMac server
- [ ] Workspace folder provisioning per agent
- [ ] WebSocket server for client-cloud communication
- [ ] Continuous Spirit session management
- [ ] Task agent spawning into containers

---

## Lower Priority

### Progressive Help System
Standardize tool documentation with metadata.yaml.

```yaml
# Each tool has metadata.yaml
name: browser
description: Browser automation with CDP
commands:
  - name: open
    brief: Open URL
examples:
  - browser open "https://example.com"
```

Benefits:
- Single source of truth
- Auto-generate CLAUDE.md
- Consistent help output

Tasks:
- [ ] Create metadata.yaml schema
- [ ] Build lib/help.sh renderer
- [ ] Add `tools validate` command
- [ ] Update `tools sync` to use metadata
