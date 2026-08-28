# The campaign–agent protocol

How a campaign session and the repository agents it launched talk to each
other. Normative. `AGENTS.md` carries the short form; this file is the whole
contract.

Status: first design, 2026-08-28.

## What the protocol is for

Three systems already answer questions about a delegate, and each answers a
different one:

| question | answered by | why not the others |
| --- | --- | --- |
| is the work finished? | GitHub | survives the agent, the pane and the machine |
| is the process alive? | herdr | knows nothing about the work |
| **what is it doing, and what is it waiting for?** | **the agent itself** | nothing else can see intent or an unasked question |

The protocol carries **only the third**. A message that repeats a GitHub fact or
a herdr fact adds a second copy of something already true elsewhere, and the
copy is what goes stale. This is the whole design constraint.

## Transport

The harness's own peer messaging, addressed by the name given at launch
(`claude --name <role>-<slug>`). `ListAgents` resolves that name; herdr's pane
label is not an address.

Two properties make it the right transport and both are load-bearing:

- **It is not the terminal screen.** Reading a pane gives whatever happens to be
  rendered, capped by the emulator's buffer; a message is delivered and queued.
- **It carries no state.** Every exchange is a fresh question and a fresh
  answer, so a campaign session that died and restarted talks to its agents with
  no handover, and a second machine's session can do the same.

## The messages

Four, and no more. Each names what only the sender knows.

### `STATUS` — campaign → agent

Asks four questions. The agent answers all four, in order, even when the answer
is "nothing".

1. What are you doing right now, or are you finished?
2. Is anything blocking you or waiting on a decision that is not yours?
3. Does any of your work exist only on this machine — uncommitted, unpushed, or
   on a branch no remote has?
4. Can you be shut down safely?

Question 3 is the one the protocol exists for. A tree deleted under a live agent
destroys exactly that work and nothing else can see it.

### `REPORT` — agent → campaign, unsolicited

Sent once, when the agent has pushed a branch and opened or updated a pull
request. It names the pull request URL and stops.

**A report is a prompt to verify, never the verification.** The campaign session
reads GitHub before believing it. An agent asserting it is finished is the
delegate verifying its own work, which is the one thing the design refuses.

### `BLOCKED` — agent → campaign, unsolicited

Sent when the agent needs a decision that is not its to make. It names the
decision and the options, and then the agent stops rather than guessing.

Silence is not this message. An agent that stops without sending it looks
identical to one that is thinking.

### `STAND DOWN` — campaign → agent

Instructs the agent to finish its current turn and stop. It is sent **only
after** the campaign session has itself confirmed, in GitHub, that the work is
durable — never on the strength of a `REPORT`.

The agent does not close its own pane. It acknowledges and goes idle; the
campaign session retires the pane.

## Rules

1. **A claim in a message is never evidence.** It says where to look. The
   campaign session then looks, in GitHub, itself.
2. **Shutdown is two steps, never one.** `STATUS`, then verify, then
   `STAND DOWN`. A single "you're done, quit" message makes the delegate's own
   account the basis for destroying its workspace.
3. **Silence is a liveness question, not a protocol answer.** An unanswered
   `STATUS` is asked once more, and then resolved through herdr and GitHub — a
   quiet agent is not a finished one, and waiting forever for a reply that
   cannot come is the failure mode this rule exists to stop.
4. **The agent answers about itself only.** It does not report on siblings,
   the campaign, or whether an issue should close.
5. **No new state.** The protocol keeps no file, no log, and no registry. Every
   exchange stands alone, which is what lets a restarted or second-machine
   campaign session speak to the same agents.

## Retiring a finished agent

The reason the protocol exists. In a long-lived campaign, subtasks finish
continuously while the campaign stays open, so retirement cannot wait for the
close.

1. `STATUS` every agent under the campaign tree.
2. For each that says it is finished: confirm in GitHub that its branch is
   pushed and its pull request is open.
3. `STAND DOWN` the confirmed ones. Leave the rest, and say why.
4. Retire the pane once the agent has acknowledged.

An agent whose pull request is open is retired, not kept for the review. Review
feedback gets a fresh session briefed from the pull request; a pane held across
a multi-day review costs more than a relaunch.

## Deliberately absent

- **No self-termination.** The only thing that can verify a delegate's work is
  something other than that delegate.
- **No heartbeat.** Liveness is already a herdr fact; a heartbeat would be a
  second, worse copy of it that also stops when the agent is merely busy.
- **No task assignment message.** The handover brief is a file, because the
  launch line has a 1024-byte ceiling and a brief must be readable afterwards.
