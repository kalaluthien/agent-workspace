/*
 * The campaign-agent protocol.
 *
 * How a campaign session and the repository agents it launched talk to each
 * other. Normative. AGENTS.md carries the short form -- four messages and the
 * two-step shutdown; this file is the whole contract, and the parts of it that
 * can be checked are checked below rather than asserted in prose.
 *
 * Status: first design, 2026-08-28.
 *
 *
 * WHAT THE PROTOCOL IS FOR
 *
 * Three systems already answer questions about a delegate, and each answers a
 * different one:
 *
 *   question                              answered by   why not the others
 *   is the work finished?                 GitHub        survives the agent, the
 *                                                       pane and the machine
 *   is the process alive?                 herdr         knows nothing about the
 *                                                       work
 *   what is it doing, and what is it       the agent     nothing else can see
 *   waiting for?                          itself        intent or an unasked
 *                                                       question
 *
 * The protocol carries ONLY the third. A message that repeats a GitHub fact or
 * a herdr fact adds a second copy of something already true elsewhere, and the
 * copy is what goes stale. This is the whole design constraint, and it is why
 * `report` below writes no durable state at all.
 *
 *
 * TRANSPORT
 *
 * The harness's own peer messaging, addressed by the name given at launch
 * (claude --name, the branch with its slash flattened:
 * campaign-<N>-<issue>-<topic>). ListAgents resolves that name; herdr's pane
 * label is not an address.
 *
 * Two properties make it the right transport and both are load-bearing:
 *   - It is not the terminal screen. Reading a pane gives whatever happens to
 *     be rendered, capped by the emulator's buffer; a message is delivered and
 *     queued.
 *   - It carries no state. Every exchange is a fresh question and a fresh
 *     answer, so a campaign session that died and restarted talks to its agents
 *     with no handover, and a second machine's session can do the same.
 *
 *
 * RETIREMENT, AND WHY THE PROTOCOL EXISTS AT ALL
 *
 * An agent does not close itself. It finishes by pushing its branch and opening
 * or updating a pull request, then goes idle. The campaign session retires it
 * once the work is durable -- the branch pushed, the pull request open. It
 * deliberately does not wait for the merge: review can take days, and a pane
 * held open across them is the expensive thing. Review feedback gets a fresh
 * session, briefed from the pull request.
 *
 * In a long-lived campaign subtasks finish continuously while the campaign
 * stays open, so retirement cannot wait for the close. The procedure is four
 * steps, and `twoStepShutdown` plus `coLocatedShutdown` below are steps 2 and 3
 * written as disciplines the model can check:
 *
 *   1. STATUS every agent under the campaign tree.
 *   2. For each that says it is finished: confirm in GitHub, and against the
 *      working tree, that nothing it holds exists only on this machine.
 *   3. STAND DOWN the confirmed ones. Leave the rest, and say why.
 *   4. Retire the pane once the agent has acknowledged.
 *
 * Self-termination is refused for one reason: the only thing that can verify a
 * delegate's work is something other than that delegate.
 *
 *
 * WHAT THIS MODEL IS
 *
 * One campaign session, some agents, and the events by which work becomes
 * durable or fails to. The four messages are events; the two shutdown
 * disciplines are predicates; the defect the design records -- a one-step
 * "you're done, quit" -- is a counterexample below rather than a warning.
 *
 * Deliberately small. It is the contract's carrier, not a research model:
 * campaign-core.als owns completion, campaign-multi.als owns several sessions,
 * and neither is restated here.
 *
 * Run one:
 *   alloy exec -f -o /tmp/alloy-proto -t text -c 'Sanity' spec/alloy/agent-protocol.als
 * Run all:
 *   alloy exec -f -o /tmp/alloy-proto -t text -c '*' spec/alloy/agent-protocol.als
 *
 * Ten commands: five runs, five checks. X is a counterexample; a check that
 * passes reads UNSAT. Measured 2026-08-28 against this file.
 *
 *   Sanity                          SAT    the whole retirement procedure runs
 *   ReportIsNotEvidence             SAT    a REPORT changes nothing durable
 *   BlockedAgentDoesNotProceed      SAT    BLOCKED stops the agent
 *   SilentAgentIsRetirableUnderWait UNSAT  the finding: wait-for-the-answer
 *                                          strands a pane forever
 *   SilentAgentStillRetired         SAT    rule 3's repair still retires it
 *   UnguardedShutdownIsUnsafe       X      the baseline: work is destroyed
 *   OneStepShutdownSuffices         X      the defect the design records
 *   TwoStepShutdownSuffices         X      two steps run from the wrong machine
 *   TwoStepCoLocatedSuffices        pass   the contract as AGENTS.md states it
 *   SilenceResolutionStaysSafe      pass   rule 3's repair reopens nothing
 *
 * Both greens were proved able to fail, re-run 2026-08-28 against this model:
 * letting `work` keep an earlier confirmation instead of clearing it reddens
 * both, and narrowing `coLocatedShutdown` to the stand-down alone reddens
 * TwoStepCoLocatedSuffices.
 *
 *
 * UNMODELLED, STATED FOR THE RECORD
 *
 * Three rules of the contract have no construct here, because each is a fact
 * about the message medium rather than about reachable states:
 *   - The agent answers about itself only. It does not report on siblings, the
 *     campaign, or whether an issue should close.
 *   - No new state. The protocol keeps no file, no log and no registry. Every
 *     exchange stands alone, which is what lets a restarted or second-machine
 *     campaign session speak to the same agents.
 *   - STAND DOWN is a request, not an order. Whoever types into the agent's
 *     pane is its user; the campaign session reaches it as a peer, and a peer
 *     cannot command. An agent with a contradicting instruction from its own
 *     pane is right to refuse. Treat a refusal as information about a conflict,
 *     not as disobedience, and resolve the conflict at the pane.
 *
 * Deliberately absent from the protocol itself:
 *   - No self-termination, for the reason above.
 *   - No heartbeat. Liveness is already a herdr fact; a heartbeat would be a
 *     second, worse copy of it that also stops when the agent is merely busy.
 *   - No task assignment message. The handover brief is a file, because the
 *     launch line has a 1024-byte ceiling and a brief must be readable
 *     afterwards.
 *
 * And one open risk, named rather than solved: retiring at "pull request open"
 * means nobody is watching the review. Until a board exists, the person is the
 * one who notices.
 */
module agentProtocol

/* ---------------- static structure ---------------- */

sig Machine {}

sig Agent {
  host: one Machine             -- the machine whose checkout it runs in
}

/* One campaign session, pinned to the machine whose working trees it can read.
   It is static on purpose: the question this model asks about machines is
   whether a check made from the wrong one still passes, and a session that can
   walk between them cannot pose it. */
one sig Session {
  at: one Machine
}

var sig Live      in Agent {}   -- the process exists and can still act
var sig Local     in Agent {}   -- holds work that exists ONLY on its host:
                                -- uncommitted, unpushed, or on a branch no
                                -- remote has
var sig Reported  in Agent {}   -- has sent REPORT: a claim, and nothing else
var sig Asked     in Agent {}   -- a STATUS is outstanding
var sig Answered  in Agent {}   -- it answered the outstanding STATUS
var sig Waiting   in Agent {}   -- has sent BLOCKED and is waiting on a decision
var sig Confirmed in Agent {}   -- the SESSION has itself observed that this
                                -- agent holds nothing local-only
var sig StoodDown in Agent {}   -- STAND DOWN sent and acknowledged
var sig Retired   in Agent {}   -- pane destroyed, workspace gone

/* ---------------- observable events ---------------- */

abstract sig Event {}
one sig Stutter, Work, Push, Status, Answer, Report, Blocked, Decide,
        Confirm, ConfirmElsewhere, StandDown, Retire, AgentDie extends Event {}

one sig Now {
  var ev:      one Event,
  var evAgent: lone Agent
}

pred keepClaims   { Reported' = Reported and Asked' = Asked and Answered' = Answered and Waiting' = Waiting }
pred keepShutdown { StoodDown' = StoodDown and Retired' = Retired }
pred keepWork     { Live' = Live and Local' = Local and Confirmed' = Confirmed }

/* The agent produces work that exists only on its own disk. Note what this
   clears: a confirmation the session made earlier is no longer true, so it is
   dropped here rather than at the point it is read. A stale green is worse than
   no green. */
pred work[a: Agent] {
  a in Live and a not in Waiting
  Local' = Local + a
  Confirmed' = Confirmed - a
  Live' = Live and keepClaims and keepShutdown
  Now.ev = Work and Now.evAgent = a
}

/* The one rule that makes a tree deleted under a live agent survivable: a
   delegate pushes as soon as it has one commit, so what a lost workspace costs
   is uncommitted work and nothing more. Pushing does not set Confirmed -- the
   session has not looked yet, and nothing here lets it believe without looking. */
pred push[a: Agent] {
  a in Live and a in Local
  Local' = Local - a
  Live' = Live and Confirmed' = Confirmed and keepClaims and keepShutdown
  Now.ev = Push and Now.evAgent = a
}

/* STATUS -- campaign to agent.

   Asks four questions. The agent answers all four, in order, even when the
   answer is "nothing".

     1. What are you doing right now, or are you finished?
     2. Is anything blocking you or waiting on a decision that is not yours?
     3. Does any of your work exist only on this machine -- uncommitted,
        unpushed, or on a branch no remote has?
     4. Can you be shut down safely?

   Question 3 is the one the protocol exists for. A tree deleted under a live
   agent destroys exactly that work and nothing else can see it.

   STATUS queues behind the agent's current turn; it does not interrupt. A busy
   agent answers when its turn ends, which on a long turn is minutes. That makes
   a late reply ordinary rather than a symptom, and it is why asking and
   answering are two events here and why rule 3 exists. */
pred status[a: Agent] {
  Asked' = Asked + a
  Answered' = Answered - a
  Reported' = Reported and Waiting' = Waiting
  keepWork and keepShutdown
  Now.ev = Status and Now.evAgent = a
}

/* Only a live agent answers. A gone one leaves the question outstanding
   forever, which is the whole of rule 3. */
pred answer[a: Agent] {
  a in Live and a in Asked
  Answered' = Answered + a
  Asked' = Asked and Reported' = Reported and Waiting' = Waiting
  keepWork and keepShutdown
  Now.ev = Answer and Now.evAgent = a
}

/* REPORT -- agent to campaign, unsolicited.

   Sent once, when the agent has pushed a branch and opened or updated a pull
   request. It names the pull request URL and stops.

   A report is a prompt to verify, never the verification. The campaign session
   reads GitHub before believing it. An agent asserting it is finished is the
   delegate verifying its own work, which is the one thing the design refuses --
   so this event writes NOTHING but the claim itself. Everything an assertion
   below cares about is untouched by it, and that is the model's statement of
   rule 1.

   A REPORT names a URL, which makes fabrication cheap to disprove; a false one
   was caught in about two seconds by four independent checks. But the rule
   catches fabrication, not inadequacy: a real pushed branch with a real pull
   request that does not do what was asked passes every check. Verifying that
   the work exists is not reviewing it. */
pred report[a: Agent] {
  a in Live
  Reported' = Reported + a
  Asked' = Asked and Answered' = Answered and Waiting' = Waiting
  keepWork and keepShutdown
  Now.ev = Report and Now.evAgent = a
}

/* BLOCKED -- agent to campaign, unsolicited.

   Sent when the agent needs a decision that is not its to make. It names the
   decision and the options, and then the agent stops rather than guessing --
   which is why `work` above refuses to fire while Waiting holds.

   Silence is not this message. An agent that stops without sending it looks
   identical to one that is thinking. */
pred blocked[a: Agent] {
  a in Live and a not in Waiting
  Waiting' = Waiting + a
  Reported' = Reported and Asked' = Asked and Answered' = Answered
  keepWork and keepShutdown
  Now.ev = Blocked and Now.evAgent = a
}

pred decide[a: Agent] {
  a in Waiting
  Waiting' = Waiting - a
  Reported' = Reported and Asked' = Asked and Answered' = Answered
  keepWork and keepShutdown
  Now.ev = Decide and Now.evAgent = a
}

/* The campaign session reads the agent's working tree ITSELF.

   State the check as an absence: no uncommitted changes, no unpushed commits,
   no branch absent from the remote. "Confirm the branch is pushed and the pull
   request is open" has no passing form for an agent that correctly produced
   nothing durable, and a campaign session following it literally is stuck with
   nothing to verify. What is always checkable is the inverse, and that is the
   `a not in Local` guard here. */
pred confirm[a: Agent] {
  Session.at = a.host
  a not in Local
  Confirmed' = Confirmed + a
  Live' = Live and Local' = Local and keepClaims and keepShutdown
  Now.ev = Confirm and Now.evAgent = a
}

/* The same check run from another machine. It reads the SESSION's working tree,
   not the agent's, so it comes back clean whatever the agent holds -- there is
   no `a not in Local` guard here because there is nothing on this machine that
   could fail it. That is not a modelling shortcut; it is the defect, and
   TwoStepShutdownSuffices below is where it surfaces. */
pred confirmElsewhere[a: Agent] {
  Session.at != a.host
  Confirmed' = Confirmed + a
  Live' = Live and Local' = Local and keepClaims and keepShutdown
  Now.ev = ConfirmElsewhere and Now.evAgent = a
}

/* STAND DOWN -- campaign to agent.

   Asks the agent to finish its current turn and stop. The agent does not close
   its own pane: it acknowledges and goes idle, and the campaign session retires
   the pane afterwards. That is why standing down and retiring are two events,
   and why the agent is still Live between them.

   Nothing guards this predicate. The guards are the discipline predicates
   below, applied per command, so that the unguarded protocol and each candidate
   repair can be measured against the same trace space. */
pred standDown[a: Agent] {
  a in Live and a not in StoodDown
  StoodDown' = StoodDown + a
  Retired' = Retired
  keepWork and keepClaims
  Now.ev = StandDown and Now.evAgent = a
}

/* The pane and its workspace are destroyed. Anything still in Local at this
   instant is gone and GitHub never knew about it.

   The second disjunct is not a convenience: a pane whose agent already died is
   retired without any stand-down, because there is nobody left to ask. That
   path skips every message in the protocol, which is exactly why the
   disciplines below guard the retire and not only the stand-down. */
pred retire[a: Agent] {
  (a in StoodDown or a not in Live) and a not in Retired
  Retired' = Retired + a
  Live' = Live - a
  Local' = Local and Confirmed' = Confirmed and StoodDown' = StoodDown
  keepClaims
  Now.ev = Retire and Now.evAgent = a
}

/* The process dies on its own. Its disk survives, so Local is untouched: a
   delegate that died after pushing has still succeeded, and one that died
   holding uncommitted work has not yet lost it. */
pred agentDie[a: Agent] {
  a in Live
  Live' = Live - a
  Local' = Local and Confirmed' = Confirmed
  keepClaims and keepShutdown
  Now.ev = AgentDie and Now.evAgent = a
}

pred stutter {
  keepWork and keepClaims and keepShutdown
  Now.ev = Stutter and no Now.evAgent
}

pred init {
  all a: Agent | a in Live
  no Local and no Reported and no Asked and no Answered
  no Waiting and no Confirmed and no StoodDown and no Retired
}

pred step {
  stutter
  or (some a: Agent |
        work[a] or push[a] or status[a] or answer[a] or report[a]
        or blocked[a] or decide[a] or confirm[a] or confirmElsewhere[a]
        or standDown[a] or retire[a] or agentDie[a])
}

fact Trace { init and always step }

/* ---------------- the property ---------------- */

/* The one thing the protocol is for. Retiring an agent destroys its workspace,
   so retiring one that still holds work only its own disk has is the loss the
   whole two-step shutdown exists to prevent. */
pred noWorkDestroyed {
  always (Now.ev = Retire implies Now.evAgent not in Local)
}

/* ---------------- disciplines: the shutdown, three ways ---------------- */

/* THE DEFECT THE DESIGN RECORDS. A single "you're done, quit" sent on the
   strength of a REPORT makes the delegate's own account the basis for
   destroying its workspace. */
pred oneStepShutdown {
  always (Now.ev in StandDown + Retire implies Now.evAgent in Reported)
}

/* Shutdown is two steps, never one: STATUS, then verify, then STAND DOWN.
   Both conjuncts are load-bearing -- the answer is what names work only the
   agent can see, and the confirmation is the session looking for itself. */
pred twoStepShutdown {
  always (Now.ev in StandDown + Retire implies
            (Now.evAgent in Answered and Now.evAgent in Confirmed))
}

/* Stand down only an agent on your own machine. The verification in step 2 is
   read against a working tree, and a session on another machine reads its own. */
pred coLocatedShutdown {
  always (Now.ev in StandDown + Retire implies Session.at = Now.evAgent.host)
}

/* Rule 3, as a discipline: silence is a liveness question, not a protocol
   answer. An unanswered STATUS is asked once more and then resolved through
   herdr and GitHub -- so an agent that is gone may be stood down on the
   confirmation alone, and only on the confirmation. A quiet agent is not a
   finished one, and waiting forever for a reply that cannot come is the failure
   mode this rule exists to stop. */
pred resolveSilenceExternally {
  always (Now.ev in StandDown + Retire implies
            (Now.evAgent in Confirmed
             and (Now.evAgent in Answered or Now.evAgent not in Live)))
}

/* The rule this one replaces: wait for the answer before standing down.
   SilentAgentNeverStandsDown is the witness that it can wait forever. */
pred waitForAnswer {
  always (Now.ev in StandDown + Retire implies Now.evAgent in Answered)
}

/* ---------------- properties, per discipline ---------------- */

/* X. Unguarded: work is destroyed. The baseline the disciplines are measured
   against. Counterexample: an agent works, is stood down, is retired. */
assert UnguardedShutdownIsUnsafe { noWorkDestroyed }

/* X. THE ONE-STEP DEFECT. A REPORT is a claim about a pull request; it says
   nothing about a second, uncommitted change made after it. Counterexample:
   the agent reports, then works again, then is stood down on the strength of
   the report and retired with the new work still only on its disk. This is the
   assertion that makes "shutdown is two steps, never one" a checked statement
   rather than an instruction. */
assert OneStepShutdownSuffices { oneStepShutdown implies noWorkDestroyed }

/* X. THE REMOTE HOLE, and it is not a modelling artefact. Two steps are not
   enough when step 2 is run from the wrong machine: an agent launched elsewhere
   passes every check a remote session can make while its uncommitted work sits
   on a disk that session cannot see. Counterexample: confirmElsewhere fires,
   the agent still holds Local, and the retire destroys it. Ask the session that
   launched it, or leave it. */
assert TwoStepShutdownSuffices { twoStepShutdown implies noWorkDestroyed }

/* PASS. The contract as AGENTS.md states it: two steps, on your own machine.
   Confirmed is cleared by any later `work`, which is what makes the green
   survive an agent that keeps working after being confirmed. */
assert TwoStepCoLocatedSuffices {
  (twoStepShutdown and coLocatedShutdown) implies noWorkDestroyed
}

/* PASS. Rule 3's repair does not reopen the hole: dropping the requirement for
   an ANSWER, for an agent that can no longer give one, is safe as long as the
   session's own confirmation is kept and read on the right machine. */
assert SilenceResolutionStaysSafe {
  (resolveSilenceExternally and coLocatedShutdown) implies noWorkDestroyed
}

/* ---------------- commands ---------------- */

/* The whole retirement procedure, reachable: the agent works and pushes, the
   session asks STATUS and gets an answer, confirms against the tree, stands the
   agent down and retires the pane. SAT means the disciplines above forbid a
   counterexample rather than forbidding the protocol. */
run Sanity {
  coLocatedShutdown and twoStepShutdown
  and eventually (some a: Agent | a in Retired)
  and eventually Now.ev = Work
  and eventually Now.ev = Push
} for exactly 1 Agent, exactly 1 Machine, 12 steps

/* Rule 1 as a witness: a REPORT changes nothing an assertion reads. The agent
   claims it is finished while still holding work only its machine has, and the
   claim leaves that fact exactly as it was. */
run ReportIsNotEvidence {
  eventually (Now.ev = Report and Now.evAgent in Local and Now.evAgent in Local')
} for exactly 1 Agent, exactly 1 Machine, 8 steps

/* BLOCKED stops the agent rather than letting it guess: it is waiting, and no
   Work event fires while it does. */
run BlockedAgentDoesNotProceed {
  some a: Agent | eventually (a in Waiting and always (a in Waiting and Now.ev != Work))
} for exactly 1 Agent, exactly 1 Machine, 8 steps

/* THE FAILURE RULE 3 FORBIDS. Under wait-for-the-answer, an agent asked for
   STATUS that then dies without replying can never be retired at all: the
   premise the discipline waits on is one the world can no longer supply.
   UNSAT is the finding -- there is no such trace, so the pane stays open
   forever and the session waits for a reply that cannot come. */
run SilentAgentIsRetirableUnderWait {
  waitForAnswer
  and (some a: Agent |
         eventually (a in Asked and a not in Live and a in Retired)
         and always a not in Answered)
} for exactly 1 Agent, exactly 1 Machine, 10 steps

/* Rule 3's repair, and the control that it is a repair rather than a
   prohibition: under resolveSilenceExternally the same never-answering agent
   is still retired. */
run SilentAgentStillRetired {
  resolveSilenceExternally and coLocatedShutdown
  and (some a: Agent | eventually a in Retired and always a not in Answered)
} for exactly 1 Agent, exactly 1 Machine, 10 steps

check UnguardedShutdownIsUnsafe   for 2 Agent, 2 Machine, 10 steps
check OneStepShutdownSuffices     for 2 Agent, 2 Machine, 10 steps
check TwoStepShutdownSuffices     for 2 Agent, 2 Machine, 10 steps
check TwoStepCoLocatedSuffices    for 2 Agent, 2 Machine, 10 steps
check SilenceResolutionStaysSafe  for 2 Agent, 2 Machine, 10 steps
