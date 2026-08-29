/*
 * The executor: launch, work, the five messages, retirement -- and the whole
 * composition, since this is the top layer.
 *
 * ledger.als is spec/'s entry point and carries the orientation to all four
 * layers and the composition idiom. Running this file exercises all four at
 * once; running the other three exercises each on its own.
 *
 *
 * THIS LAYER
 *
 * How a campaign session and the executors it launched talk to each other.
 * Normative. AGENTS.md carries the short form -- five messages and the two-step
 * shutdown; this file is the whole contract, and the parts of it that can be
 * checked are checked below rather than asserted in prose.
 *
 *   event             performed by
 *   Launch (executor) the `claude --session-id ... --name campaign-<N>-<issue>-<topic>`
 *                     that starts an executor on the claim its launcher made
 *   Work              the executor edits its checkout
 *   Push              git push -- the one act that makes work survivable
 *   Announce          CLAIMED, executor -> campaign, once at the claim
 *   Status            STATUS, campaign -> executor
 *   Answer            the executor's reply to an outstanding STATUS
 *   Report            REPORT, executor -> campaign, unsolicited
 *   Blocked           BLOCKED, executor -> campaign, unsolicited
 *   Decide            the campaign session answers a BLOCKED
 *   Confirm           the session reads the executor's working tree ITSELF
 *   ConfirmElsewhere  the same check run from the wrong machine -- the defect
 *   Review            `/code-review <PR#>`, a session the holder launches
 *   MergePR (guard)   who may land it: this layer's half of session.als's event
 *   StandDown         STAND DOWN, campaign -> executor
 *   Retire            the workspace is destroyed
 *   Release (guard)   what may be released: this layer's half of repos.als's event
 *   AgentDie          the process dies on its own
 *
 * `Agent` here is an EXECUTOR of a subtask. It comes in two kinds and the
 * difference is one field, `peer`:
 *
 *   a herdr DELEGATE, launched into a clone by the holding session, `--name`d
 *   its branch with the slash flattened -- so its address was chosen by its
 *   launcher and is known before the process exists; and
 *
 *   an EXECUTOR SESSION, a Claude session opened in the container root that
 *   found a live holder, took a subtask and claimed its branch. Nothing the
 *   holder chose names it. `peer` is that session, `launcher` is itself, and its
 *   ListAgents name is the one fact about it nothing else carries -- which is
 *   what CLAIMED is for and what `Addressed` records.
 *
 * Everything else is shared. Both answer STATUS, send REPORT and BLOCKED, stop
 * on STAND DOWN, never write the anchor, and never merge their own pull request.
 * `standDown` and `retire` are guarded by the disciplines below rather than by
 * anything about how the executor is hosted.
 *
 *
 * WHAT THE PROTOCOL IS FOR
 *
 * Three systems already answer questions about an executor, and each answers a
 * different one:
 *
 *   question                              answered by   why not the others
 *   is the work finished?                 GitHub        survives the executor,
 *                                                       the pane and the machine
 *   is the process alive?                 herdr         knows nothing about the
 *                                                       work
 *   what is it doing, and what is it       the executor  nothing else can see
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
 * The harness's own peer messaging. ListAgents resolves the address; herdr's
 * pane label is not one. Where the address comes from is the difference between
 * the two kinds of executor: a delegate's was chosen at launch (claude --name,
 * the branch with its slash flattened: campaign-<N>-<issue>-<topic>), and an
 * executor session's was not chosen by anyone the holder knows, so the executor
 * sends it. That is CLAIMED, and it is the only message in the protocol whose
 * absence is invisible -- an executor that never sends it looks from the holding
 * session's side like no executor at all. A1 below is that measured.
 *
 * A running session CAN be renamed, but only by a person typing `/rename` into
 * its pane; a session cannot do it for itself (probed 2026-08-28). So renaming
 * to the flattened branch stays an optional courtesy and CLAIMED stays the
 * mechanism.
 *
 * Two properties make it the right transport and both are load-bearing:
 *   - It is not the terminal screen. Reading a pane gives whatever happens to
 *     be rendered, capped by the emulator's buffer; a message is delivered and
 *     queued.
 *   - It carries no state. Every exchange is a fresh question and a fresh
 *     answer, so a campaign session that died and restarted talks to its
 *     executors with no handover, and a second machine's session can do the
 *     same.
 *
 *
 * RETIREMENT, AND WHY THE PROTOCOL EXISTS AT ALL
 *
 * An executor does not close itself. It finishes by pushing its branch and
 * opening or updating a pull request, then goes quiet. The campaign session
 * retires it once the work is durable -- the branch pushed, the pull request
 * open. It deliberately does not wait for the merge: review can take days, and
 * a pane held open across them is the expensive thing. Review feedback gets a
 * fresh session, briefed from the pull request.
 *
 * In a long-lived campaign subtasks finish continuously while the campaign
 * stays open, so retirement cannot wait for the close. The procedure is five
 * steps, and `twoStepShutdown` plus `coLocatedShutdown` below are steps 2 and 4
 * written as disciplines the model can check:
 *
 *   1. STATUS every executor under the campaign tree, by the address it
 *      announced -- a delegate's `--name`, an executor session's CLAIMED.
 *   2. For each that says it is finished: confirm in GitHub, and against the
 *      working tree, that nothing it holds exists only on this machine.
 *   3. Review the pull request, and land it or send it back. THE EXECUTOR
 *      NEVER MERGES ITS OWN PULL REQUEST and never reviews it. It pushes,
 *      REPORTs the URL once, and waits. The holding session launches a reviewer
 *      on it -- an in-process subagent by default, a herdr session only for a
 *      many-turn or `ultra` review -- reads the findings, and then either
 *      merges --
 *      and tells the executor the work is durable, which is what lets the
 *      executor drop its worktree -- or briefs a fresh executor from the pull
 *      request and the review and runs the loop again. The holder never merges
 *      unreviewed. `mergedByHolder` below is this step checked; A4 is the live
 *      collision it was written from.
 *   4. STAND DOWN the confirmed ones. Leave the rest, and say why.
 *   5. Retire the workspace once the executor has acknowledged.
 *
 * Step 3 does not make retirement wait for the merge. A pull request that goes
 * to a review it cannot finish in one sitting is still retired at pull-request
 * open, and the feedback gets a fresh session; what the step fixes is WHO acts,
 * not how long the pane stays up.
 *
 * Self-termination is refused for one reason: the only thing that can verify an
 * executor's work is something other than that executor. Self-merging and
 * self-reviewing are refused for exactly the same reason, one step later.
 *
 *
 * ONE ENCODING OF "ONLY ON THIS MACHINE"
 *
 * `Local` is it, and it is the whole of it. The predecessors had four -- an
 * issue with no pull request while an agent was live, `Visible`, `Pushed`, and
 * `Local` -- and a widening had to be applied in two files at once because of
 * it. `Visible` is kept because it is a genuinely different fact, readable from
 * a different place: the branch is on the remote. The two are independent and
 * their gap is the finding R5b names -- an executor whose branch is on the
 * remote may still hold work that is not.
 *
 * `Idle` is gone. Its one claim -- "the agent went idle" is not completion --
 * is carried by ReportIsNotEvidence below, which says the same thing about the
 * stronger signal: not even an explicit REPORT moves a GitHub fact.
 *
 * `Addressed` and `Reviewed` are the two bits #37 added, and each is a fact
 * about a DIFFERENT object than `Local` is. `Addressed` is about the holding
 * session's reach -- can it ask this executor anything at all -- and it is why
 * liveness and attribution are two predicates below rather than one.
 * `Reviewed` is about the pull request, so it outlives the executor exactly as
 * the pull request does and a fresh executor briefed from the review inherits
 * it.
 *
 *
 * UNMODELLED, STATED FOR THE RECORD
 *
 * Three rules of the contract have no construct here, because each is a fact
 * about the message medium rather than about reachable states:
 *   - The executor answers about itself only. It does not report on siblings,
 *     the campaign, or whether an issue should close.
 *   - NO STATE BEYOND WHAT `runtime/` HOLDS ON THE BOUND MACHINE, which dies
 *     with the campaign directory. The clause used to read "no file, no log and
 *     no registry", and CLAIMED contradicts it: the holder writes
 *     `<campaign>/runtime/executors/<issue>` when an announcement arrives,
 *     because the holder is the thing that must read it back at a close or a
 *     sweep, possibly from a later session. The amended clause is the rule that
 *     was actually meant -- no second copy of a GitHub fact, and nothing that
 *     outlives the cache it describes. Every exchange still stands alone; what
 *     the record carries is an ADDRESS, which is a fact about this machine and
 *     exists nowhere else.
 *   - STAND DOWN is a request, not an order. Whoever types into the executor's
 *     pane is its user; the campaign session reaches it as a peer, and a peer
 *     cannot command. An executor with a contradicting instruction from its own
 *     pane is right to refuse. Treat a refusal as information about a conflict,
 *     not as disobedience, and resolve the conflict at the pane.
 *
 * Two more, added with the review step:
 *   - The reviewer is a process, and this layer models processes only where
 *     their state matters. The reviewer's does not: it leaves exactly one
 *     durable mark and that mark is `Reviewed`, so `review` names the executor
 *     whose work is read rather than the session doing the reading.
 *   - Adequacy is still unmodelled, and the review does not change that. What
 *     `Reviewed` records is that somebody looked, never what they concluded;
 *     ledger.als's header says the same thing about a merged pull request.
 *
 * Deliberately absent from the protocol itself:
 *   - No self-termination, for the reason above.
 *   - No heartbeat. Liveness is already a herdr fact; a heartbeat would be a
 *     second, worse copy of it that also stops when the executor is merely busy.
 *   - No task assignment message. The handover brief is a file, because the
 *     launch line has a 1024-byte ceiling and a brief must be readable
 *     afterwards.
 *
 * WHO DOES THE WORK, AND WHY IT IS NOT MODELLED
 *
 * The three execution modes the holding session chooses between -- its own
 * hands, an in-process subagent on a worktree, a herdr delegate in a clone --
 * plus the executor session, which is not a mode because nobody chooses it, are
 * one `Launch` here on purpose. No construct below distinguishes them, because
 * nothing a model can say about reachable states differs between them: the
 * branch is the same claim, the completion is the same GitHub fact, and the only
 * differences are turn cost and whether a process boundary is crossed.
 *
 * The rule that chooses between them is not about reachable states either, and
 * it is not restated here: AGENTS.md § Running a campaign carries it, in one
 * copy, because it is an instruction to an operator rather than a property. What
 * belongs here is WHY it is absent from the model.
 *
 * The rule turns on which process loads which skills. That is a fact about the
 * harness -- a subagent and an interactive session load the skills of where they
 * were started, and a `disable-model-invocation: true` skill is unusable by any
 * agent in any mode -- and no construct over reachable states can express it. A
 * check written from it would restate the guard it came from and pass by
 * construction. It is stated rather than modelled for the same reason ledger.als
 * states the delegation mechanics: it is a fact about a tool.
 *
 * One consequence does reach this layer, and it is why the rule is worth naming
 * at all: an executor session that draws a member-repository subtask becomes the
 * LAUNCHER of a delegate rather than the executor of it, and the delegate it
 * launches has no `peer` -- it is Addressed at its launch from the `--name` its
 * launcher chose, and nobody sends a CLAIMED for it. So `peer` is a property of
 * the executor that ends up holding the claim, not of the session that took the
 * subtask, and `announce` is guarded on it for exactly that reason.
 *
 * And one open risk, named rather than solved: retiring at "pull request open"
 * means nobody is watching the review. Until a board exists, the person is the
 * one who notices.
 *
 *
 * VERDICTS
 *
 * Measured 2026-08-28 against this file, A14 and A15 on 2026-08-29. X is a
 * counterexample; a check that passes reads UNSAT.
 *
 *   NoLostWork                       pass  a death or a delete never un-completes
 *   NoOrphan                         X     nothing enforces the retirement rule
 *   NoOrphanIfGuarded                pass  it does hold once enforced
 *   UnguardedShutdownIsUnsafe        X     the baseline: work is destroyed
 *   OneStepShutdownSuffices          X     the defect the design records
 *   TwoStepShutdownSuffices          X     two steps run from the wrong machine
 *   TwoStepCoLocatedSuffices         pass  the contract as AGENTS.md states it
 *   SilenceResolutionStaysSafe       pass  rule 3's repair reopens nothing
 *   Sanity                           SAT   the whole retirement procedure runs
 *   ReportIsNotEvidence              SAT   a REPORT changes nothing durable
 *   BlockedAgentDoesNotProceed       SAT   BLOCKED stops the executor
 *   SilentAgentIsRetirableUnderWait  UNSAT wait-for-the-answer strands a pane
 *   SilentAgentStillRetired          SAT   rule 3's repair still retires it
 *   S3_DelegateDiesAfterPushing      SAT
 *   S4_ReportWithoutPush             SAT
 *   S9_OrphanedByLocalDelete         SAT
 *   R3b_CloseFromAnotherMachine      SAT   a close over a delegate on M1
 *   R3c_GlobalCloseRuleBlocks        UNSAT the global rule would block it
 *   R4_SameBranchTwice               SAT   two delegates, one branch
 *   R4b_CrossCampaignCoexists        SAT   control: campaign-<N> still separates
 *   R4c_CheckoutSwitchedUnderAgent   SAT   an acquire moves a live agent's HEAD
 *   R4d_SameSubtaskTwice             SAT
 *   R4e_NumberedBranchStillShared    SAT   what the numbered branch leaves
 *   R4f_ClaimClosesSameSubtask       UNSAT the claim closes it
 *   R4g_ClaimWithoutAtomicityStillShared SAT control: the 422 is load-bearing
 *   R5b_VisibleNotPushed             SAT   the gap R5's finding rests on
 *   R5c_NonLauncherSameMachineIsFine SAT   co-location, not ownership, is the axis
 *   R6_ReleaseUnderRemoteAgent       SAT   a local release under a remote executor
 *   R6b_ReclaimAfterDeath            SAT   a dangling claim is reclaimable
 *   A1_UnannouncedExecutorIsInvisible
 *                                    SAT   THE FINDING: liveness was never the
 *                                          missing half -- attribution was
 *   A2_AnnounceMakesEveryHolderActReachable
 *                                    UNSAT CLAIMED, recorded, closes it
 *   A3_AnnounceAdmitsExecutorSession SAT   control: the whole run still happens
 *   A4_ExecutorMergesItsOwnPR        SAT   the live collision, reproduced
 *   A5_MergedByHolderBlocksExecutorMerge
 *                                    UNSAT the merge is the holder's
 *   A6_UnreviewedMerge               SAT   control: the second way to merge wrong
 *   A7_MergedByHolderBlocksUnreviewed
 *                                    UNSAT and the holder never merges unread
 *   A8_MergedByHolderAdmitsTheLanding SAT  control: the landing path still runs
 *   A9_RecordDiesWithTheDirectory    SAT   the record has the tree's lifetime
 *   A10_DeleteUnderAnnouncedExecutor SAT   session.als's R3d, reached from here
 *   A11_ReadableGateBlocksTheDelete  UNSAT and closed by reading the record
 *   A12_ReadableGateAdmitsTheDelete  SAT   control
 *   A13_PushAfterReviewUnReviews     SAT   a review is of a pull request at a
 *                                          revision, and a push retires it
 *   A14_UnannouncedExecutorIsRetirable
 *                                    SAT   `confirm` reads a tree, not the
 *                                          executor, so silence resolved
 *                                          externally still ends in a retire --
 *                                          of an executor that already died
 *   A14b_UnannouncedExecutorCannotBeStoodDown
 *                                    UNSAT and never a stand-down: that one
 *                                          carries a message, so it stays gated
 *   A15_UnannouncedExecutorPRLands   SAT   and its pull request still lands
 *   Cov_*                            SAT   every own event fires in some trace
 *
 * Every green was proved able to fail, re-run 2026-08-28 against this model:
 * letting `work` keep an earlier confirmation instead of clearing it reddens
 * TwoStepCoLocatedSuffices and SilenceResolutionStaysSafe; narrowing
 * `coLocatedShutdown` to the stand-down alone reddens TwoStepCoLocatedSuffices;
 * dropping the RemoveMember clause reddens NoOrphanIfGuarded; and dropping
 * `ledgerFrame` from ledger.als's fall-through branch reddens NoLostWork --
 * which is the point of the layering, since nothing written in THIS file holds
 * a GitHub fact still while an executor dies.
 *
 * The four greens #37 added were each proved able to fail by their own named
 * mutation, run 2026-08-29 and undone afterwards:
 *
 *   A2   exempting the executor session from `announceAtClaim` -- adding `no
 *        a.peer` to its first clause, which leaves it binding only the executors
 *        that satisfied it already. SAT: the gap returns, and the mutation names
 *        the discipline's whole content.
 *   A5   `mergedByHolder`'s holder conjunct rewritten to `some By.actor` -- a
 *        merge just needs a merger, which is the rule as it stood when #36
 *        collided. SAT.
 *   A7   dropping the `Now.issue.pr in Reviewed` conjunct alone, with the holder
 *        and the confirmation left in place. SAT, which isolates the review as
 *        the thing A7 turns on rather than the identity of the merger.
 *   A11  keying `noDeleteUnderReadableExecutor` on `no a.peer` instead of
 *        `reachable[a]`, so the gate reads delegates and ignores executor
 *        sessions. SAT: the delete lands under the announced executor again, and
 *        the mutation is exactly the blind spot the record was added to fix.
 *
 * WHAT THE FIRST DRAFT OF THIS FILE GOT WRONG
 *
 * Five things, found by review, each kept visible because each is a standing
 * hazard rather than a typo.
 *
 *   `Reviewed` was framed by `push` and omitted from `agentInit`. Framed, the
 *   loop the design documents -- brief a fresh executor from a bad review --
 *   landed unreviewed commits under the old review's bit; omitted from `init`,
 *   the bit could simply arrive, which weakened every green that reads it. A13
 *   is the first fixed, `agentInit` the second.
 *
 *   `mergedByHolder`'s confirm conjunct was existential, wrong in both
 *   directions at once. See the predicate.
 *
 *   Addressability guarded STATUS alone, so four other holder-to-executor events
 *   fired against executors the holder could not reach. `reachable` is one
 *   predicate now, over the three events that CARRY A MESSAGE -- status, decide,
 *   standDown -- and A2 is renamed for what that certifies. `confirm` and
 *   `review` read a working tree and a pull request instead of the executor, so
 *   they are not gated on it; A14 and A15 are what that costs when they are.
 *
 *   `announceAtClaim` was written over the step rather than per agent, which
 *   made it unsatisfiable for two unaddressed executors at once -- an artefact
 *   of `lone Target.agent`, invisible because every command using it ran at one
 *   Agent. A1-A3 run at two.
 *
 *   A4 left two things wrong at once, so A5's UNSAT had two independent causes
 *   and survived deleting its own headline conjunct. It is built the way A6 is
 *   built now: everything right except the one thing under test.
 *
 *   `mergedByHolder` was keyed to `campaignOf[Now.issue]`, a MUTABLE relation, so
 *   a reparent mid-review emptied the antecedent and permitted a self-merge. It
 *   reads `By.actor.holds` now. The `RemoveMember` pin A4 carried to work around
 *   it is gone, which means the rule is measured on every path rather than on the
 *   one where its hole is shut.
 *
 *   `aDeleteDir` stripped every executor on the machine, delegates included, so a
 *   live delegate went permanently unaddressable when a directory its `--name`
 *   never depended on was deleted. It strips executor sessions only.
 *
 *
 * TWO FINDINGS THE COMPOSITION PRODUCED
 *
 * Both are cases that were in no previous file, because each needs two things
 * the old split kept apart. They are stated here rather than filed away because
 * each changed a construct.
 *
 *   Several sessions x the protocol. `coLocatedShutdown` used to constrain the
 *   stand-down and the retire; with one session that is the whole of it, and
 *   with several it is not. A session on another machine runs the confirmation,
 *   a session on the executor's machine acts on it, and the retire destroys
 *   work: TwoStepCoLocatedSuffices measured X. The discipline now covers the
 *   confirmation too, which is what steps 2 and 3 of the retirement procedure
 *   already meant, and the verdict is back to pass. See `coLocatedShutdown`.
 *
 *   A subtask moved out of a campaign under a live executor. `liveUnder` reads
 *   membership OR co-location, so removing the subtask and deleting the tree
 *   turns the global close rule permissive again. The several-sessions model had
 *   no remove event and could not state it. R3c is scoped to traces without one
 *   and reproduces its UNSAT; the evasion is named beside it.
 *
 * WHAT MOVED, AND WHAT CHANGED WITH IT
 *
 *   R5_RemoteStandDownLosesWork is gone as a separate run: it is
 *   TwoStepShutdownSuffices' counterexample stated twice. Its write-up is beside
 *   that assertion, and its two controls (R5b, R5c) are kept because they pin
 *   the axis.
 *
 *   IdleImpliesComplete is gone as a separate check, merged into
 *   ReportIsNotEvidence -- see ONE ENCODING above.
 *
 * WHAT #37 ADDED, AND WHAT IT COST A LOWER LAYER
 *
 *   `status` gained one guard, `a in Addressed`. Every pre-existing verdict is
 *   unchanged under it, and that is not luck: a delegate is addressed at launch
 *   from its own `--name`, so the guard is satisfied by construction for every
 *   executor the old commands could build.
 *
 *   `MergePR` moved out of session.als's `unattended` set and gained an actor
 *   there, because a rule about who may merge needs a whose to talk about. This
 *   layer adds no disjunct for it -- only the discipline -- so the merge still
 *   falls through `agentStep` and frames every bit above.
 *
 *   `mergedByHolder` is scoped to a merge whose issue still has a campaign, so a
 *   subtask reparented out of one is unguarded by it. That is the silent-reparent
 *   residue ledger.als's header already names, reached from a new direction; A4
 *   pins `always Now.ev != RemoveMember` rather than let the scenario escape
 *   through it, and the escape is written down beside that conjunct.
 *
 *   Every command here carries a Session, because an executor is launched by
 *   one. The predecessors that had no session had no launcher either, and gave
 *   their agents to `init`. The bounds below pay for it in atoms rather than in
 *   steps: a session may already hold a campaign at time zero.
 */
module agent

open session

/* ==================== SYSTEM ==================== */

/* ---------------- static structure ---------------- */

sig Agent {
  task:     one Issue,          -- the member issue it works
  host:     one Machine,        -- the machine whose checkout it runs in
  launcher: one Session,        -- the session that put it there
  topic:    one Topic,          -- the <topic> half of its branch
  /* AN EXECUTOR MAY BE A SESSION. When it is, `peer` is that session and the
     executor put itself there: it arrived in the container root, found a live
     holder, took a subtask and claimed its branch. Everything else about it is
     an executor's -- it answers STATUS, sends REPORT and BLOCKED, stops on
     STAND DOWN, and never writes the anchor.

     The field is what makes the address question askable. A herdr delegate is
     `--name`d its branch at launch, so the launching session knows how to reach
     it by construction; an executor session was named by nothing the holder
     chose, and its ListAgents name is the one thing only it knows. That is what
     CLAIMED carries and what `Addressed` below records. */
  peer:     lone Session
}

var sig Launched in Agent {}    -- an executor exists, or existed, for this claim
var sig Live     in Agent {}    -- it can still act
var sig Local    in Agent {}    -- it holds work that exists ONLY on its host:
                                -- uncommitted, unpushed, or on a branch no
                                -- remote has. THE one encoding of that.
var sig Visible  in Agent {}    -- its branch is on the remote: checkable from
                                -- anywhere, and a different fact from Local
var sig Reported in Agent {}    -- has sent REPORT: a claim, and nothing else
var sig Addressed in Agent {}   -- `<campaign>/runtime/executors/<issue>`: the
                                -- holder can reach it. A delegate is in it from
                                -- its --name at launch, an executor session only
                                -- once the holder recorded its CLAIMED. A
                                -- DIRECTORY FACT: it dies with the tree, and it
                                -- is keyed to no session, so a successor holder
                                -- inherits it
var sig Asked    in Agent {}    -- a STATUS is outstanding
var sig Answered in Agent {}    -- it answered the outstanding STATUS
var sig Waiting  in Agent {}    -- has sent BLOCKED and is waiting on a decision
var sig Confirmed in Agent {}   -- the SESSION has itself observed that this
                                -- executor holds nothing local-only
var sig StoodDown in Agent {}   -- STAND DOWN sent and acknowledged
var sig Retired  in Agent {}    -- the workspace is gone

/* A bit on the PULL REQUEST, not on the executor, because that is where it
   belongs: the review outlives the executor exactly as the pull request does,
   and a fresh executor briefed from the review inherits it. */
var sig Reviewed in PR {}       -- `/code-review` has been run on it

/* This layer's observer: which executor the event is about. */
one sig Target { var agent: lone Agent }

fact AgentWellFormed {
  all c: Campaign | c.anchor not in Agent.task
  /* An executor session is its own launcher and runs on its own machine. */
  all a: Agent | some a.peer implies (a.launcher = a.peer and a.host = a.peer.smach)
  always Live in Launched
  always Retired in Launched
  always no Live & Retired
  always Visible in Visible'     -- a branch on the remote stays on the remote
}

/* A session on the executor's own machine, versus one that is not. */
pred coLocated[s: Session, a: Agent] { s.smach = a.host }

pred liveUnder[c: Campaign] {
  some a: Agent | a in Live and (a.task in c.members or a.host in dirsOf[c])
}
/* What one session can actually read: `herdr agent list` on its own machine. */
pred liveUnderLocally[c: Campaign, m: Machine] {
  some a: Agent | a in Live and a.host = m and (a.task in c.members or m in dirsOf[c])
}
/* WHETHER THE HOLDER CAN REACH THIS EXECUTOR AT ALL. A delegate is reachable
   from its `--name`, which its launcher chose; an executor session is reachable
   only from the record the holder wrote when its CLAIMED arrived. One predicate,
   used by every holder-to-executor event below, because "I can see it in a list"
   and "I can send it a message" are the same question for both kinds. */
pred reachable[a: Agent] { a in Addressed }

/* And what a close gate can read AND ATTRIBUTE, which is a strictly smaller set
   than what it can see. `liveUnderLocally` is the seeing; this narrows it to the
   executors the machine's `runtime/executors/` can name.

   A herdr delegate is listed by `herdr agent list` with its `cwd` under the
   campaign tree, so the gate reads it whether or not anyone addressed it. An
   executor session is a peer in `ListAgents`: its name is visible and the
   subtask it works is not, so until its CLAIMED has been recorded the gate
   cannot tell it from a session working something else entirely. LIVENESS IS
   READABLE FOR BOTH; ATTRIBUTION IS NOT, and the close gate needs attribution.
   A1 below is that gap, and `announceAtClaim` is what closes it. */
pred liveAndReadable[c: Campaign, m: Machine] {
  some a: Agent | a in Live and a.host = m
    and (a.task in c.members or m in dirsOf[c])
    and (no a.peer or reachable[a])
}
/* ledger's `closable` is the GitHub half -- what scripts/campaign-settlement
   prints, and all it can see. These three add the half that needs an executor. */
pred closableWithAgents[c: Campaign]        { closable[c] and not liveUnder[c] }
pred closableLocally[s: Session, c: Campaign] { closable[c] and not liveUnderLocally[c, s.smach] }
pred closableAsRead[s: Session, c: Campaign]  { closable[c] and not liveAndReadable[c, s.smach] }

/* The branch an executor works, in the form the design carried when R4 below
   was found: campaign-<N>/<topic>. Two executors share it when the campaign and
   the topic match -- true by definition of the name, not by proof. */
/* BRANCH NAMES CANNOT COLLIDE ACROSS CAMPAIGNS, even though the container
   shares one number sequence between its anchors and its subtasks.
   campaign-<N>/<issue>-<topic> collides only on an equal <N> and <issue> pair.
   An issue has at most one parent, so a subtask maps to exactly one campaign
   number; two subtasks of one campaign have different numbers; and sharing a
   sequence with the anchor HELPS, because it makes <issue> and <N> distinct
   integers rather than allowing them to coincide. The collision case cannot be
   constructed -- which is why what R4 finds below is intra-campaign, and only
   that. */
pred sameBranchByTopic[a1, a2: Agent] {
  campaignOf[a1.task] = campaignOf[a2.task] and a1.topic = a2.topic
}

/* The form AGENTS.md adopted in answer to R4: campaign-<N>/<issue>-<topic>. The
   subtask's issue number joins the campaign number, so two executors share a
   branch only when campaign, subtask and topic all match. That it separates two
   subtasks is definitional and is not run; what R4e asks is what it leaves. */
pred sameBranch[a1, a2: Agent] {
  campaignOf[a1.task] = campaignOf[a2.task]
  and a1.task = a2.task
  and a1.topic = a2.topic
}

/* ---------------- observable events ---------------- */

one sig Work, Push, Announce, Status, Answer, Report, Blocked, Decide,
        Confirm, ConfirmElsewhere, Review, StandDown, Retire, AgentDie extends Event {}

fun agentOwn: set Event {
  Work + Push + Announce + Status + Answer + Report + Blocked + Decide
  + Confirm + ConfirmElsewhere + Review + StandDown + Retire + AgentDie
}
/* `DeleteDir` is here because this layer has a bit with the directory's
   lifetime -- see `aDeleteDir`. `MergePR` is NOT: session.als gives it an actor
   and this layer only guards who that actor may be, which is a discipline over
   the event rather than a disjunct on it, so the merge falls through and frames
   every bit above. */
fun agentActed: set Event { agentOwn + Launch + Release + DeleteDir }

/* One keeper per fact this layer holds, and every event names only the ones it
   moves. The bits divide by what writes them and by how long they live:
   `keepAddress` is a directory fact, `keepReview` is about a pull request, and
   the rest are about a process. */
pred keepMsgs     { Reported' = Reported and Asked' = Asked and Answered' = Answered and Waiting' = Waiting }
pred keepAddress  { Addressed' = Addressed }
pred keepReview   { Reviewed' = Reviewed }
pred keepLife     { Live' = Live and Local' = Local and Visible' = Visible and Confirmed' = Confirmed }
pred keepShutdown { StoodDown' = StoodDown and Retired' = Retired }
pred keepBorn     { Launched' = Launched }
pred agentFrame   { keepLife and keepReview and keepMsgs and keepAddress and keepShutdown and keepBorn }

/* The executor's half of a launch. It needs the claim -- the branch exists on
   the remote, created by create-ref before any executor started -- and the
   checkout, on the topic that is its branch. That its launcher is the session
   that made the claim is `claimBeforeLaunch` below, a discipline rather than a
   guard, because a launch that skips claiming is exactly what R4e is about. */
pred launch[a: Agent] {
  Now.ev = Launch
  a not in Launched
  a.launcher = By.actor
  a.host = Site.mach
  Now.issue = a.task
  a.task in Claimed
  treeAt[By.actor.holds, a.host].co[a.task.home] = a.topic
  Launched' = Launched + a
  Live'     = Live + a
  /* A delegate is addressable the moment it exists: the launching session chose
     its `--name`, so the launch IS the record. An executor session is not --
     nothing the holder chose names it -- so it starts unaddressed and `announce`
     is the only thing that changes that. */
  (no a.peer implies Addressed' = Addressed + a else keepAddress)
  Local' = Local and Visible' = Visible and Confirmed' = Confirmed
  keepReview and keepMsgs and keepShutdown
  Target.agent = a
}

/* CLAIMED -- executor to campaign, sent once at the claim.

   It carries `<branch> <ListAgents name> <pid>` and nothing else. The branch and
   the subtask are already GitHub facts, readable by anyone with the anchor; the
   address and the process id are the two things only the executor knows, which
   is the same test every other message in this protocol has to pass. The pid
   earns its place the way `runtime/holder`'s does -- it is what makes the
   record's liveness a local `kill -0` rather than a guess -- and nothing but the
   executor can supply it. AGENTS.md carries the rest, including why renaming the
   session is not the mechanism.

   WHAT THE HOLDER DOES WITH IT IS THE POINT, and it is why `Addressed` is not a
   message bit. The holder writes `<campaign>/runtime/executors/<issue>` -- the
   announced name, the pid, the branch -- because the holder is the thing that
   must read it back later, at a close or a sweep, possibly in a different
   session. So the record has `runtime/holder`'s argument and `runtime/holder`'s
   lifetime: it is a file in the campaign directory on the bound machine, it
   dies with that directory (`aDeleteDir` below), and nothing about it is keyed
   to the session that received the announcement -- so a successor holder that
   takes a dead holder's directory inherits every address in it. No event below
   writes `Addressed` from a session's identity, which is that claim by
   construction.

   Guarded on `some a.peer` because a delegate has nothing to announce, and on
   `a not in Addressed` because it is sent once. */
pred announce[a: Agent] {
  a in Live
  some a.peer
  a not in Addressed
  Addressed' = Addressed + a
  keepLife and keepReview and keepMsgs and keepShutdown and keepBorn
  Now.ev = Announce and Now.issue = a.task and Target.agent = a and no By.actor
}

/* The campaign directory is deleted, and the executor records under `runtime/`
   go with it. Every other bit this layer holds is about a process or a pull
   request and outlives the tree; `Addressed` is the one that does not, because
   for an executor session it IS a file in the tree.

   ONLY FOR AN EXECUTOR SESSION, and the `some a.peer` guard is the whole of it.
   A delegate's address is the `--name` its launcher chose, which lives in the
   launch and in `herdr agent list`, not in `runtime/executors/` -- so a delegate
   is addressable for as long as it runs, whatever happens to the tree. Stripping
   it here would have made a live delegate permanently unreachable the moment a
   directory it does not depend on was deleted, and `retire` -- the one holder act
   deliberately left unguarded -- would then be the only thing left that could
   touch it.

   Scoped to the deleted tree's own campaign and machine besides: `Present -
   Present'` is the tree that just went, so two campaigns sharing a machine do
   not clear each other's records. That scoping is repos.als's
   MachineIndependence claim applied to a bit this layer owns. */
pred aDeleteDir {
  Now.ev = DeleteDir
  Addressed' = Addressed
    - { a: Agent | some a.peer
                   and a.host = Site.mach
                   and campaignOf[a.task] in (Present - Present').camp }
  keepLife and keepReview and keepMsgs and keepShutdown and keepBorn
  no Target.agent
}

/* The executor produces work that exists only on its own disk. Note what this
   clears: a confirmation the session made earlier is no longer true, so it is
   dropped here rather than at the point it is read. A stale green is worse than
   no green. */
pred work[a: Agent] {
  a in Live and a not in Waiting
  Local' = Local + a
  Confirmed' = Confirmed - a
  Live' = Live and Visible' = Visible
  keepReview and keepMsgs and keepAddress and keepShutdown and keepBorn
  Now.ev = Work and Now.issue = a.task and Target.agent = a and no By.actor
}

/* The one rule that makes a tree deleted under a live executor survivable: it
   pushes as soon as it has one commit, so what a lost workspace costs is
   uncommitted work and nothing more. Pushing puts the branch on the remote and
   clears the local-only work -- two different facts, and only the first is
   readable from another machine. It does not set Confirmed: the session has not
   looked yet, and nothing here lets it believe without looking.

   It clears `Reviewed` for the same reason `work` clears `Confirmed`, and the
   omission was a real hole: a fresh executor briefed from a bad review pushes
   new commits onto the same pull request, and under the old frame the old
   review bit still stood, so `mergedByHolder` was satisfied by a reading of
   commits nobody had read. A review is of a pull request AT A REVISION. */
pred push[a: Agent] {
  a in Live and a in Local
  Local'    = Local - a
  Visible'  = Visible + a
  Reviewed' = Reviewed - a.task.pr
  Live' = Live and Confirmed' = Confirmed
  keepMsgs and keepAddress and keepShutdown and keepBorn
  Now.ev = Push and Now.issue = a.task and Target.agent = a and no By.actor
}

/* STATUS -- campaign to executor.

   Asks four questions. The executor answers all four, in order, even when the
   answer is "nothing".

     1. What are you doing right now, or are you finished?
     2. Is anything blocking you or waiting on a decision that is not yours?
     3. Does any of your work exist only on this machine -- uncommitted,
        unpushed, or on a branch no remote has?
     4. Can you be shut down safely?

   Question 3 is the one the protocol exists for. A tree deleted under a live
   executor destroys exactly that work and nothing else can see it.

   STATUS queues behind the executor's current turn; it does not interrupt. A
   busy executor answers when its turn ends, which on a long turn is minutes.
   That makes a late reply ordinary rather than a symptom, and it is why asking
   and answering are two events here and why rule 3 exists. */
pred status[a: Agent] {
  reachable[a]
  a.task in By.actor.holds.members
  Asked' = Asked + a
  Answered' = Answered - a
  Reported' = Reported and Waiting' = Waiting
  keepLife and keepReview and keepAddress and keepShutdown and keepBorn
  Now.ev = Status and Now.issue = a.task and Target.agent = a
}

/* Only a live executor answers. A gone one leaves the question outstanding
   forever, which is the whole of rule 3. */
pred answer[a: Agent] {
  a in Live and a in Asked
  Answered' = Answered + a
  Asked' = Asked and Reported' = Reported and Waiting' = Waiting
  keepLife and keepReview and keepAddress and keepShutdown and keepBorn
  Now.ev = Answer and Now.issue = a.task and Target.agent = a and no By.actor
}

/* REPORT -- executor to campaign, unsolicited.

   Sent once, when it has pushed a branch and opened or updated a pull request.
   It names the pull request URL and stops.

   A report is a prompt to verify, never the verification. The campaign session
   reads GitHub before believing it. An executor asserting it is finished is the
   delegate verifying its own work, which is the one thing the design refuses --
   so this event writes NOTHING but the claim itself. Everything a command below
   cares about is untouched by it, and that is the model's statement of rule 1.

   A REPORT names a URL, which makes fabrication cheap to disprove; a false one
   was caught in about two seconds by four independent checks. But the rule
   catches fabrication, not inadequacy: a real pushed branch with a real pull
   request that does not do what was asked passes every check. Verifying that the
   work exists is not reviewing it. */
pred report[a: Agent] {
  a in Live
  Reported' = Reported + a
  Asked' = Asked and Answered' = Answered and Waiting' = Waiting
  keepLife and keepReview and keepAddress and keepShutdown and keepBorn
  Now.ev = Report and Now.issue = a.task and Target.agent = a and no By.actor
}

/* BLOCKED -- executor to campaign, unsolicited.

   Sent when it needs a decision that is not its to make. It names the decision
   and the options, and then it stops rather than guessing -- which is why `work`
   above refuses to fire while Waiting holds.

   Silence is not this message. An executor that stops without sending it looks
   identical to one that is thinking. */
pred blocked[a: Agent] {
  a in Live and a not in Waiting
  Waiting' = Waiting + a
  Reported' = Reported and Asked' = Asked and Answered' = Answered
  keepLife and keepReview and keepAddress and keepShutdown and keepBorn
  Now.ev = Blocked and Now.issue = a.task and Target.agent = a and no By.actor
}

pred decide[a: Agent] {
  reachable[a]
  a in Waiting
  a.task in By.actor.holds.members
  Waiting' = Waiting - a
  Reported' = Reported and Asked' = Asked and Answered' = Answered
  keepLife and keepReview and keepAddress and keepShutdown and keepBorn
  Now.ev = Decide and Now.issue = a.task and Target.agent = a
}

/* The campaign session reads the executor's working tree ITSELF.

   State the check as an absence: no uncommitted changes, no unpushed commits,
   no branch absent from the remote. "Confirm the branch is pushed and the pull
   request is open" has no passing form for an executor that correctly produced
   nothing durable, and a campaign session following it literally is stuck with
   nothing to verify. What is always checkable is the inverse, and that is the
   `a not in Local` guard here.

   NO `reachable` GUARD, deliberately: this event reads a working tree on the
   session's own machine and sends the executor nothing, so an address at the far
   end is not what it needs. Gating it made an executor that never announced
   impossible to CONFIRM, and every discipline that wants a confirmation before
   the retire then made it impossible to retire and its pull request impossible
   to land -- A14 and A15, both UNSAT with the guard in place and SAT without it,
   measured 2026-08-29. */
pred confirm[a: Agent] {
  coLocated[By.actor, a]
  a.task in By.actor.holds.members
  a not in Local
  Confirmed' = Confirmed + a
  Live' = Live and Local' = Local and Visible' = Visible
  keepReview and keepMsgs and keepAddress and keepShutdown and keepBorn
  Now.ev = Confirm and Now.issue = a.task and Target.agent = a
}

/* The same check run from another machine. It reads the SESSION's working tree,
   not the executor's, so it comes back clean whatever the executor holds --
   there is no `a not in Local` guard here because there is nothing on this
   machine that could fail it. That is not a modelling shortcut; it is the
   defect, and TwoStepShutdownSuffices below is where it surfaces.

   It shares `confirm`'s absence of a `reachable` guard, but not for `confirm`'s
   reason, and the guard would not have saved it either: `runtime/executors/` is
   on the bound machine, so a session elsewhere cannot read it and does not know
   there is anything it cannot address. What is wrong here is the tree it reads,
   and no addressability rule reaches that. */
pred confirmElsewhere[a: Agent] {
  not coLocated[By.actor, a]
  a.task in By.actor.holds.members
  Confirmed' = Confirmed + a
  Live' = Live and Local' = Local and Visible' = Visible
  keepReview and keepMsgs and keepAddress and keepShutdown and keepBorn
  Now.ev = ConfirmElsewhere and Now.issue = a.task and Target.agent = a
}

/* REVIEW -- `/code-review <PR#>` run against the executor's pull request.

   The owner's rule: a pull request is reviewed before it is merged, and the
   review is A REVIEWER THE HOLDER LAUNCHES. Two modes, and the default is the
   cheaper one: an IN-PROCESS SUBAGENT running `/code-review <PR#>`, because a
   review only reads and so needs none of what a process boundary is paid for --
   no handover file, no canary, no pane, no sweep. A HERDR SESSION is for a
   review that will take many turns, or an `ultra` review, which is
   person-triggered only and is never the default. `/code-review` is
   model-invocable, so that command is the whole opening prompt either way.

   The event does not distinguish them, for the reason the execution modes are
   one `Launch`: nothing a model can say about reachable states differs between
   a subagent and a pane. What differs is turn cost.

   The reviewer is not the executor, and the guard here is that negative:
   `By.actor != a.peer`. An executor reviewing its own pull request is the
   delegate verifying its own work -- the same thing `report` refuses to be
   evidence for, and the same thing `confirm` exists to replace. What the holder
   does with the findings is two-valued and only one half is a model event: it
   merges (guarded by `mergedByHolder`), or it briefs a fresh executor from the
   pull request and the review and the loop runs again, which is `launch` on the
   same subtask and needs no construct of its own.

   `Target.agent` names the executor whose work is reviewed, not the reviewer.
   The reviewer is a process, and this layer models processes only where their
   state matters; the reviewer's does not -- it leaves one durable mark, and that
   mark is `Reviewed`.

   No `reachable` guard, for `confirm`'s reason: `/code-review <PR#>` reads
   GitHub and `gh pr merge` needs only the number. An executor that skipped
   CLAIMED is unaddressable, not unlandable, and no prose ever said otherwise. */
pred review[a: Agent] {
  Now.ev = Review
  Now.issue = a.task
  some a.task.pr and a.task.pr not in Reviewed
  a.task in By.actor.holds.members
  By.actor != a.peer
  Reviewed' = Reviewed + a.task.pr
  keepLife and keepMsgs and keepAddress and keepShutdown and keepBorn
  Target.agent = a
}

/* STAND DOWN -- campaign to executor.

   Asks it to finish its current turn and stop. It does not destroy its own
   workspace: it acknowledges and goes quiet, and the campaign session retires it
   afterwards. That is why standing down and retiring are two events, and why the
   executor is still Live between them.

   Nothing guards this predicate beyond holding the campaign and being able to
   reach the executor. The rest are the discipline predicates below, applied per
   command, so that the unguarded protocol and each candidate repair can be
   measured against the same trace space. */
pred standDown[a: Agent] {
  reachable[a]
  a in Live and a not in StoodDown
  a.task in By.actor.holds.members
  StoodDown' = StoodDown + a
  Retired' = Retired
  keepLife and keepReview and keepMsgs and keepAddress and keepBorn
  Now.ev = StandDown and Now.issue = a.task and Target.agent = a
}

/* The workspace is destroyed. Anything still in Local at this instant is gone
   and GitHub never knew about it.

   The second disjunct is not a convenience: an executor that already died is
   retired without any stand-down, because there is nobody left to ask. That path
   skips every message in the protocol, which is exactly why the disciplines
   below guard the retire and not only the stand-down.

   No `reachable` guard, and it is the act that most obviously must not have one:
   an executor whose record went with a deleted directory, or which never
   announced, still has a workspace somebody has to be able to destroy. Retiring
   needs no answer from the far end.

   An unguarded `retire` was never the whole of that claim, though, and A14 is it
   measured: a discipline that wants a CONFIRMATION first kept such an executor
   alive forever while this predicate stood open, so `confirm` carries no guard
   for the same reason. `twoStepShutdown` strands it anyway, because its other
   conjunct is an ANSWER and an answer needs an address; `resolveSilenceExternally`,
   the rule the design adopted, asks for the confirmation alone and lets it go. */
pred retire[a: Agent] {
  (a in StoodDown or a not in Live) and a in Launched and a not in Retired
  a.task in By.actor.holds.members
  Retired' = Retired + a
  Live'    = Live - a
  Local' = Local and Visible' = Visible and Confirmed' = Confirmed
  StoodDown' = StoodDown
  keepReview and keepMsgs and keepAddress and keepBorn
  Now.ev = Retire and Now.issue = a.task and Target.agent = a
}

/* The process dies on its own. Its disk survives, so Local is untouched: an
   executor that died after pushing has still succeeded, and one that died
   holding uncommitted work has not yet lost it. */
pred agentDie[a: Agent] {
  a in Live
  Live' = Live - a
  Local' = Local and Visible' = Visible and Confirmed' = Confirmed
  keepReview and keepMsgs and keepAddress and keepShutdown and keepBorn
  Now.ev = AgentDie and Now.issue = a.task and Target.agent = a and no By.actor
}

/* This layer's half of repos.als's `release`: what may be released. The guard is
   what a session can actually read -- the remote branch holds nothing beyond
   main, and no executor on ITS OWN machine works the task. Liveness on another
   machine is not readable, so a live remote executor with no pushed work can
   still lose its claim under a rule correctly followed: R6 below is that
   residue, stated rather than implied away. */
pred aRelease {
  Now.ev = Release
  no a: Agent | a.task = Now.issue and a in Visible
  no a: Agent | a.task = Now.issue and a.host = By.actor.smach and a in Live
  agentFrame
  no Target.agent
}

pred agentInit {
  no Launched and no Live and no Local and no Visible
  no Reported and no Addressed and no Asked and no Answered
  no Waiting and no Confirmed and no Reviewed and no StoodDown and no Retired
}

pred agentStep {
  (Now.ev = Stutter and agentFrame and no Target.agent)
  or (some a: Agent |
        launch[a] or work[a] or push[a] or announce[a]
        or status[a] or answer[a] or report[a]
        or blocked[a] or decide[a] or confirm[a] or confirmElsewhere[a]
        or review[a] or standDown[a] or retire[a] or agentDie[a])
  or aRelease
  or aDeleteDir
  /* every other event: this layer stands still and is about no executor */
  or (Now.ev not in Stutter + agentActed and agentFrame and no Target.agent)
}

fact AgentTrace { agentInit and always agentStep }

/* ==================== SCENARIOS ==================== */

/* ---------------- the property ---------------- */

/* The one thing the protocol is for. Retiring an executor destroys its
   workspace, so retiring one that still holds work only its own disk has is the
   loss the whole two-step shutdown exists to prevent. */
pred noWorkDestroyed {
  always (Now.ev = Retire implies Target.agent not in Local)
}

/* ---------------- disciplines: the shutdown, three ways ---------------- */

/* THE DEFECT THE DESIGN RECORDS. A single "you're done, quit" sent on the
   strength of a REPORT makes the executor's own account the basis for
   destroying its workspace. */
pred oneStepShutdown {
  always (Now.ev in StandDown + Retire implies Target.agent in Reported)
}

/* Shutdown is two steps, never one: STATUS, then verify, then STAND DOWN.
   Both conjuncts are load-bearing -- the answer is what names work only the
   executor can see, and the confirmation is the session looking for itself. */
pred twoStepShutdown {
  always (Now.ev in StandDown + Retire implies
            (Target.agent in Answered and Target.agent in Confirmed))
}

/* Stand down only an executor on your own machine -- AND confirm it from there
   too. The verification in step 2 is read against a working tree, and a session
   on another machine reads its own.

   THE CONFIRM HALF IS NOT DECORATION, and the several-sessions world is what
   showed it. Written over the stand-down and the retire alone -- which is how
   the one-session model stated it, where it could not fail because there was
   only one session and it could not be in two places -- the contract is X here:
   a remote session runs the confirmation the local one then acts on, and the
   retire destroys work. Steps 2 and 3 of the retirement procedure are one
   session's steps, and this is that sentence made checkable. Narrowing this
   predicate back to `StandDown + Retire` reddens TwoStepCoLocatedSuffices, which
   is the mutation that proves the half is load-bearing. */
pred coLocatedShutdown {
  always (Now.ev in Confirm + ConfirmElsewhere + StandDown + Retire
            implies coLocated[By.actor, Target.agent])
}

/* Rule 3, as a discipline: silence is a liveness question, not a protocol
   answer. An unanswered STATUS is asked once more and then resolved through
   herdr and GitHub -- so an executor that is gone may be stood down on the
   confirmation alone, and only on the confirmation. A quiet executor is not a
   finished one, and waiting forever for a reply that cannot come is the failure
   mode this rule exists to stop. */
pred resolveSilenceExternally {
  always (Now.ev in StandDown + Retire implies
            (Target.agent in Confirmed
             and (Target.agent in Answered or Target.agent not in Live)))
}

/* The rule this one replaces: wait for the answer before standing down.
   SilentAgentIsRetirableUnderWait is the witness that it can wait forever. */
pred waitForAnswer {
  always (Now.ev in StandDown + Retire implies Target.agent in Answered)
}

/* What a session on another machine can check before STAND DOWN. */
pred remoteCheckedShutdown { always (Now.ev = StandDown implies Target.agent in Visible) }
/* What only a session on the executor's own machine can check. */
pred localCheckedShutdown  { always (Now.ev = StandDown implies Target.agent not in Local) }

/* The claim discipline, in two named halves. An executor is launched only onto
   a claim its launcher created; and a claim is created only where no ref exists,
   which is what create-ref's 422 enforces server-side. Together they close R4e
   (R4f UNSAT); the control R4g drops atomicity alone and the collision returns,
   so the refusal -- not the ritual -- is the load-bearing half. A session that
   launches without claiming bypasses the first, which is why the discipline
   lives in the launch procedure and R4e itself stays SAT. */
pred claimBeforeLaunch { always (Now.ev = Launch implies Now.issue in By.actor.claims) }
pred claimAtomic       { always (Now.ev = Claim  implies Now.issue not in Claimed) }

/* The close rule as written, plus the honest local reading of it, plus the
   reading a session can actually perform -- which is the local one narrowed to
   the executors it can attribute. */
pred closeDisciplineFull[c: Campaign] {
  always ((Now.ev = CloseIssue and Now.issue = c.anchor) implies closableWithAgents[c])
}
pred closeDisciplineLocal[c: Campaign] {
  always ((Now.ev = CloseIssue and Now.issue = c.anchor) implies closableLocally[By.actor, c])
}
pred closeDisciplineAsRead[c: Campaign] {
  always ((Now.ev = CloseIssue and Now.issue = c.anchor) implies closableAsRead[By.actor, c])
}

/* CLAIMED AT THE CLAIM, as a discipline, and QUANTIFIED PER AGENT.

   Two readings, both per agent: an executor that is live and unaddressed will
   announce, and it does not work before it has. A delegate satisfies both at
   launch from its `--name` and is never bound further; what this binds is the
   executor session, whose address nothing else carries.

   The per-agent form matters and the first draft got it wrong. Written as
   `always (all a | a in Live implies (a in Addressed or Now.ev = Announce and
   Target.agent = a))` it says every live unaddressed executor is announcing in
   THIS step -- and `Target.agent` is `lone`, so two of them at once is
   unsatisfiable. That is a property of the observer, not of the design, and it
   was invisible because every command using the discipline was scoped to one
   Agent. The commands below run it at two. */
pred announceAtClaim {
  all a: Agent | always {
    (a in Live and a not in Addressed) implies
      eventually (Now.ev = Announce and Target.agent = a)
    (Now.ev = Work and Target.agent = a) implies reachable[a]
  }
}

/* THE DELETE GATE, and it is where session.als's R3 finding is answered.

   session.als can say that a directory must not be deleted while another
   session is working the campaign, and cannot say how anyone would know: being
   the holder is a file, and a working peer is not. `runtime/executors/` is that
   file, so the gate belongs here, keyed on the record rather than on the peer.

   What it cannot cover is the executor that never announced, which is A1 from
   the delete's side rather than the close's: the same gap, the same repair. */
pred noDeleteUnderReadableExecutor {
  always (Now.ev = DeleteDir implies
            no a: Agent | a in Live and a.host = Site.mach and reachable[a]
                          and campaignOf[a.task] in (Present - Present').camp)
}

/* Every executor of one subtask. `mergedByHolder` quantifies over it, and the
   set is empty for a subtask the holding session did with its own hands. */
fun executorsOf[i: Issue]: set Agent { task.i }

/* AN EXECUTOR NEVER MERGES ITS OWN PULL REQUEST.

   Written after a live collision on 2026-08-28: the executor session for #36
   squash-merged its own pull request in the same minute the holding session sent
   "do not merge -- landing it is the campaign session's act". Nothing on disk
   said who merges. AGENTS.md said a subtask "lands by pull request" and the
   protocol ended at REPORT, so a REPORT that announced a merge was read as
   notice by the one who sent it and as a request by the one who got it. The rule
   retires that ambiguity from both ends: the merge is the holder's, and REPORT
   carries the pull request URL and nothing about what happens next.

   Three conjuncts, and the last two are the ones worth arguing about. The merge
   is the HOLDING session's (`mayWrite`, session.als's role reading), which is
   what excludes the executor -- an executor session is by definition not the
   holder of the campaign it works. The
   pull request has been REVIEWED, which is the owner's rule in item 9 and the
   reason the holder never merges unread. And the holder must have CONFIRMED the
   executor itself, co-located, before it merges: `Target.agent in Reported`
   would put the executor's own account under the merge, and
   claim-is-not-evidence binds the holder exactly as it binds everybody else. A
   REPORT says where to look.

   THE CONFIRM CONJUNCT IS UNIVERSAL, and it was existential in the first draft,
   which is wrong in both directions at once. Existential, one confirmed executor
   discharges it, so a second executor's unpushed work is merged and closed over
   -- and `some a: Agent` also requires that an executor exist at all, so a
   subtask the holding session did with its own hands, which is the ordinary
   first mode in AGENTS.md, could never be merged legally. `all a:
   executorsOf[i]` is right in both: every executor of that subtask, and
   vacuously true when there are none.

   Confirmation and review answer different questions and neither substitutes for
   the other. Confirmation asks whether anything exists only on this machine --
   an absence, checkable, and what the two-step shutdown is for. Review asks
   whether the work is any good, which nothing else in this model asks at all;
   ledger.als's header says adequacy is unmodelled, and this is the one place the
   design puts a reader in front of it.

   IT IS KEYED TO THE MERGER'S OWN CAMPAIGN, NOT THE ISSUE'S CURRENT MEMBERSHIP,
   and that is the second thing this predicate got wrong. Written as
   `Now.ev = MergePR and some campaignOf[Now.issue] implies mayWrite[By.actor,
   campaignOf[Now.issue]]`, it evaluated a MUTABLE relation: `removeMember` empties
   `campaignOf[i]`, the antecedent goes false, and the rule permits anything --
   so reparenting a subtask mid-review bought the executor a legal self-merge.
   A4 pinned `RemoveMember` out of its own trace, which measured the rule on the
   one path where the hole is shut and hid it everywhere else. `By.actor.holds`
   is the session's own campaign and no reparent can move it, so the guard now
   holds on every path and the scoping antecedent is gone with it. */
pred mergedByHolder {
  always (Now.ev = MergePR implies
            (mayWrite[By.actor, By.actor.holds]
             and Now.issue.pr in Reviewed
             and (all a: executorsOf[Now.issue] |
                    a in Confirmed and coLocated[By.actor, a])))
}

/* ---------------- properties ---------------- */

/* PASS. No lost work: an executor dying and a directory being deleted never
   un-complete a subtask.

   Nothing written in THIS file carries it. Completion is ledger's, and ledger
   frames its own state whenever an event it does not own fires -- so what this
   check tests is the composition idiom, and dropping `ledgerFrame` from ledger's
   fall-through branch is what reddens it. */
assert NoLostWork {
  always all i: Issue |
    (complete[i] and Now.ev in AgentDie + DeleteDir) implies after complete[i]
}

/* X. No orphan: no executor is live on a checkout whose campaign directory is
   gone. Nothing enforces "no campaign closes while an executor is live under its
   tree".

   The counterexample, and it is the reason the rule is stated as a local check
   with its blind spot named: two machines hold campaign #N; an executor is live
   on machine 0; the operator on machine 1 deletes its tree. "No campaign closes
   while an executor is live under its tree" is a local check blind to the other
   machine. Enforcing it, plus refusing to drop a member an executor is working,
   makes NoOrphanIfGuarded pass -- nothing enforces either today. */
pred noOrphanNow {
  all a: Agent | a in Live implies (some c: Campaign | a.task in c.members and a.host in dirsOf[c])
}

assert NoOrphan { always noOrphanNow }

// PASS. Same, assuming the design's stated retirement rule is actually
// enforced.
assert NoOrphanIfGuarded {
  ((always (Now.ev = DeleteDir implies (no a: Agent | a in Live and a.host = Site.mach)))
   and (always (Now.ev = RemoveMember implies (no a: Agent | a in Live and a.task = Now.issue))))
  implies (always noOrphanNow)
}

/* X. Unguarded: work is destroyed. The baseline the disciplines are measured
   against. Counterexample: an executor works, is stood down, is retired. */
assert UnguardedShutdownIsUnsafe { noWorkDestroyed }

/* X. THE ONE-STEP DEFECT. A REPORT is a claim about a pull request; it says
   nothing about a second, uncommitted change made after it. Counterexample:
   the executor reports, then works again, then is stood down on the strength of
   the report and retired with the new work still only on its disk. This is the
   assertion that makes "shutdown is two steps, never one" a checked statement
   rather than an instruction. */
assert OneStepShutdownSuffices { oneStepShutdown implies noWorkDestroyed }

/* X. THE REMOTE HOLE, and it is not a modelling artefact. Two steps are not
   enough when step 2 is run from the wrong machine: an executor launched
   elsewhere passes every check a remote session can make while its uncommitted
   work sits on a disk that session cannot see. Counterexample: confirmElsewhere
   fires, the executor still holds Local, and the retire destroys it. Ask the
   session that launched it, or leave it.

   THIS IS ALSO THE WHOLE OF "a remote stand-down destroys work", which the
   several-sessions model stated separately as a run: a session on another
   machine stands the executor down, the check it can actually run -- the branch
   is on the remote -- passes, and work that exists only on the executor's
   machine dies with the workspace. The two are one finding and one
   counterexample; R5b and R5c below are the controls that pin its axis. */
assert TwoStepShutdownSuffices { twoStepShutdown implies noWorkDestroyed }

/* PASS. The contract as AGENTS.md states it: two steps, on your own machine.
   Confirmed is cleared by any later `work`, which is what makes the green
   survive an executor that keeps working after being confirmed. */
assert TwoStepCoLocatedSuffices {
  (twoStepShutdown and coLocatedShutdown) implies noWorkDestroyed
}

/* PASS. Rule 3's repair does not reopen the hole: dropping the requirement for
   an ANSWER, for an executor that can no longer give one, is safe as long as the
   session's own confirmation is kept and read on the right machine. */
assert SilenceResolutionStaysSafe {
  (resolveSilenceExternally and coLocatedShutdown) implies noWorkDestroyed
}

/* ---------------- witnesses ---------------- */

/* The whole retirement procedure, reachable: the executor works and pushes, the
   session asks STATUS and gets an answer, confirms against the tree, stands it
   down and retires the workspace. SAT means the disciplines above forbid a
   counterexample rather than forbidding the protocol. */
pred Sanity {
  coLocatedShutdown and twoStepShutdown
  and eventually (some a: Agent | a in Retired)
  and eventually Now.ev = Work
  and eventually Now.ev = Push
}

/* Rule 1 as a witness, and the whole of "the agent went idle is not
   completion": the executor claims it is finished while still holding work only
   its machine has, and the claim leaves that fact exactly as it was -- and leaves
   the GitHub fact exactly as it was too, which is the stronger half. A signal
   weaker than an explicit REPORT, such as a pane falling quiet, says even less. */
pred ReportIsNotEvidence {
  some a: Agent | eventually (Now.ev = Report and Target.agent = a
    and a in Local and a in Local'
    and not complete[a.task] and after always not complete[a.task])
}

/* BLOCKED stops the executor rather than letting it guess: it is waiting, and
   no Work event fires while it does. */
pred BlockedAgentDoesNotProceed {
  some a: Agent | eventually (a in Waiting and always (a in Waiting and Now.ev != Work))
}

/* THE FAILURE RULE 3 FORBIDS. Under wait-for-the-answer, an executor asked for
   STATUS that then dies without replying can never be retired at all: the
   premise the discipline waits on is one the world can no longer supply.
   UNSAT is the finding -- there is no such trace, so the workspace stays open
   forever and the session waits for a reply that cannot come. */
pred SilentAgentIsRetirableUnderWait {
  waitForAnswer
  and (some a: Agent |
         eventually (a in Asked and a not in Live and a in Retired)
         and always a not in Answered)
}

/* Rule 3's repair, and the control that it is a repair rather than a
   prohibition: under resolveSilenceExternally the same never-answering executor
   is still retired. */
pred SilentAgentStillRetired {
  resolveSilenceExternally and coLocatedShutdown
  and (some a: Agent | eventually a in Retired and always a not in Answered)
}

/* The delegate dies after pushing. Completion is a GitHub fact, so it survives
   the death and never comes undone. */
/* FOR REAL -- real. Launch a delegate on a subtask. Wait until it has pushed
   and opened a pull request (`gh pr list -R <repo> --head
   campaign-$ANCHOR/<n>-<topic>` returns a row). Kill the pane -- `herdr agent
   list` to find it, then kill the process. Merge the pull request yourself.
   PASS: the row goes `complete` with no executor alive anywhere. Safe on real
   repositories: the branch is already pushed, so nothing local is lost. */
pred S3_DelegateDiesAfterPushing {
  one c: Campaign | one a: Agent {
    a.task in c.members
    always Now.ev not in AddMember + RemoveMember
    mergeClosed[c.members]
    eventually (Now.ev = OpenPR and Now.issue = a.task)
    eventually (Now.ev = AgentDie and some a.task.pr and a.task.pr not in Merged)
    eventually complete[a.task]
    always (complete[a.task] implies always complete[a.task])
  }
}

/* The delegate reports done while nothing is pushed. The campaign session must
   not believe it, and the trace shows why: the claim never becomes a GitHub fact
   on its own. */
/* FOR REAL -- real. Launch a delegate; when it sends REPORT, do not believe it.
   Run `scripts/campaign-settlement $ANCHOR` first.
   PASS: the row is `open` -- the claim was not evidence. Then confirm the
   absence directly, which is the form the protocol requires:

     git -C <campaign>/repos/<repo> status --porcelain           # must be empty
     git -C <campaign>/repos/<repo> log --branches --not --remotes --oneline
                                                                 # must be empty

   Only after both are empty may STAND DOWN be sent. A run where the campaign
   session closed the subtask on the strength of the message is a failure,
   however the work turned out. */
pred S4_ReportWithoutPush {
  one c: Campaign | one a: Agent {
    a.task in c.members
    always Now.ev not in AddMember + RemoveMember
    eventually (Now.ev = Report and Now.issue = a.task)
    eventually (a in Reported and no a.task.pr and a.task in Open)
    eventually always (not complete[a.task])
    always not closable[c]
  }
}

/* The delete lands on the machine the live executor runs on. This is NoOrphan's
   counterexample, requested as a witness so a run can be written that reproduces
   it on purpose. */
/* FOR REAL -- fixture. Launch a delegate, let it commit but NOT push, then
   delete `<campaign>/` from a second session.
   PASS is a demonstration of loss: the commits are unrecoverable and GitHub
   never knew about them. It is why STATUS question 3 exists. Fixture only, and
   never with a real delegate's work in the tree. */
pred S9_OrphanedByLocalDelete {
  one c: Campaign | one a: Agent {
    a.task in c.members
    -- deleted while the executor is live with nothing pushed: this is the only
    -- state where local-only work is actually destroyed
    eventually (Now.ev = DeleteDir and Site.mach = a.host and a in Live
                and a in Local and no a.task.pr)
    eventually (a in Live and a.host not in dirsOf[c])
  }
}

/* =================== a close during another session's work =================== */

/* R3b. The cross-machine form: session 2 closes the anchor from another machine
   while session 1's delegate is live on machine 1. The local gate reads
   closable; the campaign is not. */
/* WITNESS. S0 closes the anchor from M0 while S1's delegate is live on M1; the
   local gate reads closable because it is reading M0. R3c UNSAT below restates
   the close rule globally, so R3b reads as that rule being unreadable from one
   machine, not as the rule failing. */
pred R3b_CloseFromAnotherMachine {
  some c: Campaign, disj s1, s2: Session, a: Agent {
    s1.smach != s2.smach
    a.launcher = s1
    closeDisciplineLocal[c]
    eventually (Now.ev = CloseIssue and By.actor = s2 and Now.issue = c.anchor
                and a in Live and not closableWithAgents[c])
  }
}

/* R3c. Control for R3b: the global rule, if it could be read, blocks it.

   Scoped to traces with no RemoveMember, and the scope is a finding rather than
   a convenience. `liveUnder` reads an executor as under a campaign when its
   subtask is a member OR its machine holds the tree; move the subtask out and
   delete the tree and both go false while the executor is still running, so the
   global rule permits the close after all. The model this came from had no
   remove event and could not state it. Nothing in the design guards it, and it
   is the same shape as the residual risk ledger.als names: a reparent is silent
   and leaves no trace. */
pred R3c_GlobalCloseRuleBlocks {
  some c: Campaign, disj s1, s2: Session, a: Agent {
    s1.smach != s2.smach
    a.launcher = s1
    always Now.ev != RemoveMember
    closeDisciplineFull[c]
    eventually (Now.ev = CloseIssue and Now.issue = c.anchor and By.actor = s2 and a in Live)
  }
}

/* =================== two sessions, one repository =================== */

/* R4. Two sessions on the same campaign launch delegates into the same
   repository and pick the same topic. campaign-<N> keeps campaigns apart;
   nothing keeps two sessions of one campaign apart. */
/* WITNESS, against campaign-<N>/<topic> -- the branch form this was found on.
   Two subtasks in R0, two sessions, the same <topic>: one branch, two delegates,
   one checkout. R4d is the same with a single subtask. */
pred R4_SameBranchTwice {
  some disj a1, a2: Agent, r: Repo {
    r != Container
    a1.launcher != a2.launcher
    a1.task != a2.task                          -- two different subtasks
    a1.task.home = r and a2.task.home = r
    a1.topic = a2.topic
    eventually (a1 in Live and a2 in Live
                and some campaignOf[a1.task] and sameBranchByTopic[a1, a2])
  }
}

/* R4b. Positive control for R4: two executors of DIFFERENT campaigns, live in
   the same repository at the same time, with the same <topic> deliberately
   chosen. They do not share a branch. That is what the campaign-<N> prefix buys,
   and it isolates R4's collision as an intra-campaign one. */
pred R4b_CrossCampaignCoexists {
  some disj a1, a2: Agent, r: Repo {
    r != Container
    a1.task.home = r and a2.task.home = r
    a1.topic = a2.topic
    eventually (a1 in Live and a2 in Live
                and campaignOf[a1.task] != campaignOf[a2.task]
                and not sameBranchByTopic[a1, a2])
  }
}

/* R4c. The acquire race. One machine, one campaign directory, one checkout of
   the repository. Session 2 acquires it on another branch while session 1's
   delegate is live in it with work that is not on the remote. */
/* WITNESS. S0's acquire-repo switches the shared checkout off the branch S1's
   live delegate is working. */
pred R4c_CheckoutSwitchedUnderAgent {
  some c: Campaign, disj s1, s2: Session, a: Agent, r: Repo {
    r != Container
    s1.smach = s2.smach
    a.launcher = s1 and a.host = s1.smach and a.task.home = r
    -- pinned to one step, so the switch is attributable to s2 and not to an
    -- earlier acquire by the launching session itself.
    eventually (Now.ev = Acquire and By.actor = s2 and Site.repo = r
                and a in Live and a not in Visible
                and treeAt[c, a.host].co[r] = a.topic
                and after (treeAt[c, a.host].co[r] != a.topic))
  }
}

/* R4d. The sharper form the solver reached first when R4 left the tasks free:
   two sessions delegate the SAME subtask issue. Nothing in the design says a
   subtask has at most one executor. */
pred R4d_SameSubtaskTwice {
  some disj a1, a2: Agent {
    a1.launcher != a2.launcher
    a1.task = a2.task
    eventually (a1 in Live and a2 in Live)
  }
}

/* R4e. The adopted form, and what it does not fix. Two sessions that delegate
   the SAME subtask still land on one branch: the issue number separates two
   subtasks, and there is only ever one of it per subtask. AGENTS.md names the
   branch rule as answering the two-subtask collision only, and this is the
   residual it leaves standing. */
pred R4e_NumberedBranchStillShared {
  some disj a1, a2: Agent {
    a1.launcher != a2.launcher
    eventually (a1 in Live and a2 in Live
                and some campaignOf[a1.task] and sameBranch[a1, a2])
  }
}

/* R4f. The claim discipline closes R4e. Launch only a claim you created, and
   create-ref refuses an existing ref: the second session's claim fails before a
   second executor exists, so two live executors on one subtask from two
   launchers become unreachable. UNSAT at R4e's own bounds. */
pred R4f_ClaimClosesSameSubtask {
  claimBeforeLaunch and claimAtomic
  R4e_NumberedBranchStillShared
}

/* R4g. CONTROL: the ritual without the refusal. Both sessions claim -- nothing
   refuses the second create -- and both launch onto claims they hold. SAT: the
   collision returns, so the load-bearing half is the server's 422, not the
   procedure. */
pred R4g_ClaimWithoutAtomicityStillShared {
  claimBeforeLaunch
  some disj s1, s2: Session, i: Issue |
    eventually (i in s1.claims and i in s2.claims)
  R4e_NumberedBranchStillShared
}

/* =================== retiring another session's delegate =================== */

/* R5b. Control for TwoStepShutdownSuffices: the gap that finding rests on is
   reachable at all. An executor whose branch is on the remote may still hold
   work that is not. Without this, the remote hole could be an artefact of a
   state the model never enters. */
pred R5b_VisibleNotPushed { some a: Agent | eventually (a in Visible and a in Local) }

/* R5c. Ownership is not the axis. Under the local check, a session that did not
   launch the executor may still retire it safely, provided it shares its
   machine. */
pred R5c_NonLauncherSameMachineIsFine {
  localCheckedShutdown
  some disj s1, s2: Session, a: Agent {
    a.launcher = s1 and a.host = s1.smach and s2.smach = a.host
    eventually (Now.ev = StandDown and By.actor = s2 and Target.agent = a)
  }
}

/* R6. What release cannot read. The guard on release is local -- nothing on the
   remote branch, no LIVE executor on this machine -- because liveness elsewhere
   is not readable. A live executor on another machine that has not pushed loses
   its claim under a rule correctly followed. Same shape as the remote hole, same
   mitigation: push as soon as one commit exists. */
pred R6_ReleaseUnderRemoteAgent {
  some s: Session, a: Agent {
    a.host != s.smach
    eventually (a in Live and a not in Visible
                and Now.ev = Release and By.actor = s and Now.issue = a.task)
  }
}

/* R6b. Recovery: a dead delegate's dangling claim is released and the subtask
   claimed again by a survivor. The claim does not outlive its usefulness. */
pred R6b_ReclaimAfterDeath {
  some disj s1, s2: Session, a: Agent {
    a.launcher = s1
    eventually (a in Launched and a not in Live and a not in Visible
                and eventually (Now.ev = Release
                and eventually (Now.ev = Claim and By.actor = s2 and Now.issue = a.task)))
  }
}

/* =================== the executor session =================== */

/* A1. THE FINDING #37 WAS FILED FOR. An executor session that never sends
   CLAIMED is live, holds its subtask's claim, and cannot be addressed for
   STATUS -- and the local close gate reads straight past it, because ListAgents
   shows a peer's NAME and not the subtask it works. The holding session then
   closes the campaign over a running executor having broken no rule it could
   have read.

   The two readings side by side are what make it a finding rather than a
   restatement: `closableAsRead` says closable, `liveUnderLocally` says an
   executor is live on this very machine. Liveness was never the missing half;
   attribution was. */
/* WITNESS. S1 holds campaign c on machine M. S2 arrives, takes a subtask, is
   launched as its own executor, and never announces. S1 closes the anchor while
   S2 is live under it. */
pred A1_UnannouncedExecutorIsInvisible {
  some c: Campaign, disj s1, s2: Session, a: Agent {
    a.peer = s2 and a.task in c.members
    always a not in Addressed                   -- it never sends CLAIMED
    closeDisciplineAsRead[c]                    -- s1 obeys the gate it can read
    eventually (a in Live and a.task in Claimed
                and Now.ev = CloseIssue and Now.issue = c.anchor and By.actor = s1
                and liveUnderLocally[c, s1.smach])
  }
}

/* A2. The repair: CLAIMED at the claim, recorded by the holder, and every act
   the holder has against an executor becomes possible exactly when the executor
   becomes reachable. UNSAT at A1's own bounds.

   The name says what it certifies now rather than what the first draft claimed.
   That draft guarded STATUS alone, so `standDown` and `decide` still fired
   against executors the holder provably could not reach -- the green certified
   that one message was gated, not that the protocol was. `reachable` is the
   guard on all three message-carrying acts now, and this is that. A14 and A15
   are why `confirm` and `review` are not among them. */
pred A2_AnnounceMakesEveryHolderActReachable {
  announceAtClaim and A1_UnannouncedExecutorIsInvisible
}

/* A3. Control for A2, and for the discipline generally: it admits a normal run.
   An executor session launches, announces, works, pushes, is asked for STATUS
   and answers, is confirmed on its own machine, stands down and is retired --
   the whole retirement procedure, run by a session the holder never launched.
   An UNSAT here would mean A2 went green by forbidding executor sessions. */
pred A3_AnnounceAdmitsExecutorSession {
  announceAtClaim and coLocatedShutdown and twoStepShutdown
  some c: Campaign, disj s1, s2: Session, a: Agent {
    a.peer = s2 and a.task in c.members
    s1.smach = s2.smach
    eventually (Now.ev = Announce and Target.agent = a)
    eventually (Now.ev = Status and By.actor = s1 and Target.agent = a)
    eventually a in Retired
  }
}

/* A13. A PUSH UN-REVIEWS THE PULL REQUEST, which is `push` mirroring what `work`
   does to a confirmation, and the witness that the hole is shut. A review lands;
   the executor pushes again; the pull request is no longer reviewed, so
   `mergedByHolder` no longer holds over it.

   The hole it closes was real and quiet. `review` is guarded `pr not in
   Reviewed` and the first draft's `push` framed the bit, so the loop the design
   documents -- brief a fresh executor from the review, it pushes again -- landed
   new commits under the old review's bit and merged legally. A review is of a
   pull request AT A REVISION, and nothing else in this model had a reason to
   know that. SAT. */
pred A13_PushAfterReviewUnReviews {
  some a: Agent |
    eventually (Now.ev = Review and Target.agent = a
                and after eventually (Now.ev = Push and Target.agent = a
                                      and after (a.task.pr not in Reviewed)))
}

/* =================== who merges, and who reviews =================== */

/* A4. THE LIVE COLLISION, 2026-08-28. The executor session for #36 squash-merged
   its own pull request in the same minute the holding session sent a hold.
   Nothing forbade it: the protocol ended at REPORT and no rule anywhere named
   who lands a subtask. SAT is the defect, reproduced. */
/* FOR REAL -- it already happened. Pull request #42 on this repository, merged
   by the executor session that opened it. */
/* BUILT SO THAT ONLY ONE THING IS WRONG, which is how A6 is built and how A4
   should have been. The first draft left the executor unconfirmed as well, so
   A5's UNSAT had two independent causes and survived deleting its own headline
   conjunct -- a green that proves nothing. Here the pull request is reviewed and
   the executor is confirmed: every conjunct of `mergedByHolder` holds except the
   identity of the merger, so A5 turns on that and the mutation reddens it.

   `always s2.holds = c` replaces the `RemoveMember` pin the first draft carried.
   That pin existed because `mergedByHolder` was scoped to the issue's CURRENT
   membership, so a reparent made the rule vacuous and the scenario had to forbid
   one to measure anything -- which measured the rule on the single path where its
   hole is shut. The guard is keyed to `By.actor.holds` now, which no reparent
   moves, so the scenario needs no such pin and a reparented subtask is covered
   like any other. And s2 is
   pinned as a NON-holder, because a holding session that does a subtask with its
   own hands and merges it is the ordinary path, not the defect.

   `hasDirHere` at the merge is the fourth pin and it was found by measurement:
   without it A5 read SAT, because `mayWrite` falls back to the binding alone
   where this machine has no campaign directory, and the escape was to delete the
   tree first and merge afterwards. That is session.als's R1m residue reached
   from the merge's side -- with no `runtime/holder` there is nothing local that
   can tell a holder from an executor session, so no rule keyed on the difference
   can hold. It is the optional directory's price, named in both layers rather
   than patched in one. */
pred A4_ExecutorMergesItsOwnPR {
  some c: Campaign, disj s1, s2: Session, a: Agent {
    a.peer = s2 and a.task in c.members
    s1.smach = s2.smach
    always s2.holds = c                -- an executor session works the campaign it holds
    always isHolder[s1, c]
    always not isHolder[s2, c]
    eventually (Now.ev = Report and Target.agent = a)
    eventually (Now.ev = MergePR and By.actor = s2 and Now.issue = a.task
                and a in Confirmed and a.task.pr in Reviewed
                and hasDirHere[s2, c])
  }
}

/* A5. The rule: the merge is the holding session's. UNSAT at A4's own bounds --
   an executor session is not the holder of the campaign it works, so
   `isHolder` alone rules it out, and the confirmation and the review are two
   further reasons the same trace cannot be built. */
pred A5_MergedByHolderBlocksExecutorMerge {
  mergedByHolder and A4_ExecutorMergesItsOwnPR
}

/* =================== the record, and what it is worth =================== */

/* A9. `Addressed` HAS THE DIRECTORY'S LIFETIME, exercised rather than asserted.
   An executor announces, the holder records it, the directory is deleted, and
   the record goes with it. SAT.

   That lifetime is the whole reason the record is a file under `runtime/` and
   not a second copy of a GitHub fact: it answers a question only the bound
   machine has, it dies when that machine's cache of the campaign dies, and
   nothing off the machine ever reads it. Its cost is A10 -- after the delete
   the executor is unreachable again, which is why the delete is gated. */
pred A9_RecordDiesWithTheDirectory {
  some a: Agent {
    some a.peer                        -- a delegate's address is its --name, not a file
    eventually (reachable[a] and Now.ev = DeleteDir and Site.mach = a.host
                and after not reachable[a])
  }
}

/* A10. THE DELETE, UNGATED, under an executor the holder CAN see. This is
   session.als's R3d with the missing half supplied: the executor announced, the
   record names it, and the directory is deleted under it anyway because nothing
   reads the record. SAT. */
pred A10_DeleteUnderAnnouncedExecutor {
  some c: Campaign, a: Agent {
    some a.peer                        -- an executor SESSION: R3d's victim
    a.task in c.members
    eventually (a in Live and reachable[a] and a in Local
                and Now.ev = DeleteDir and Site.mach = a.host)
  }
}

/* A11. The gate that reads the record, and R3's shape is gone: UNSAT. The
   repair session.als could name and not state, stated in the layer that has the
   record. */
pred A11_ReadableGateBlocksTheDelete {
  noDeleteUnderReadableExecutor and A10_DeleteUnderAnnouncedExecutor
}

/* A12. Control for A11: the gate still admits a delete, once the executor it
   names is gone. An UNSAT here would mean the campaign directory could never be
   deleted at all. */
pred A12_ReadableGateAdmitsTheDelete {
  noDeleteUnderReadableExecutor
  some a: Agent |
    eventually (reachable[a] and eventually (a not in Live and Now.ev = DeleteDir
                                             and Site.mach = a.host))
}

/* A6. The second control on the same rule, and the owner's item 9: a merge with
   nothing having reviewed the pull request. SAT -- nothing in the protocol as it
   stood asked for a review at all, and the holder merging on its own confirmation
   is a check that the work EXISTS, never that it is right. */
pred A6_UnreviewedMerge {
  some c: Campaign, s: Session, a: Agent {
    a.task in c.members
    always Now.ev != RemoveMember
    -- the HOLDER merges, and it has confirmed the executor itself: the review is
    -- the only thing missing, so what A7 blocks is isolated to it
    always isHolder[s, c]
    eventually (Now.ev = MergePR and By.actor = s and Now.issue = a.task
                and a in Confirmed and no a.task.pr & Reviewed)
  }
}

/* A7. The rule against it: UNSAT at A6's own bounds. */
pred A7_MergedByHolderBlocksUnreviewed { mergedByHolder and A6_UnreviewedMerge }

/* A8. Control for A5 and A7 together: the whole landing path still runs. The
   executor pushes and REPORTs, the holder confirms it on their shared machine,
   a review lands on the pull request, and the holder merges. SAT, so neither
   UNSAT above is green by forbidding merges. */
pred A8_MergedByHolderAdmitsTheLanding {
  mergedByHolder
  some c: Campaign, disj s1, s2: Session, a: Agent {
    a.peer = s2 and a.task in c.members
    s1.smach = s2.smach and isHolder[s1, c]
    eventually (Now.ev = Report and Target.agent = a)
    eventually (Now.ev = Confirm and By.actor = s1 and Target.agent = a)
    eventually (Now.ev = Review and By.actor = s1 and Target.agent = a)
    eventually (Now.ev = MergePR and By.actor = s1 and Now.issue = a.task)
  }
}

/* ---------------- reachability floor ---------------- */

pred Cov_LaunchAgent      { eventually (Now.ev = Launch and some Target.agent) }
pred Cov_Work             { eventually Now.ev = Work }
pred Cov_Push             { eventually Now.ev = Push }
pred Cov_Status           { eventually Now.ev = Status }
pred Cov_Answer           { eventually Now.ev = Answer }
pred Cov_Report           { eventually Now.ev = Report }
pred Cov_Blocked          { eventually Now.ev = Blocked }
pred Cov_Decide           { eventually Now.ev = Decide }
pred Cov_Confirm          { eventually Now.ev = Confirm }
pred Cov_ConfirmElsewhere { eventually Now.ev = ConfirmElsewhere }
pred Cov_Announce        { eventually Now.ev = Announce }
pred Cov_Review           { eventually Now.ev = Review }
pred Cov_StandDown        { eventually Now.ev = StandDown }
pred Cov_Retire           { eventually Now.ev = Retire }
pred Cov_AgentDie         { eventually Now.ev = AgentDie }
pred Cov_GuardedRelease   { eventually Now.ev = Release }

/* A14. AN EXECUTOR THAT NEVER ANNOUNCED IS STILL RETIRABLE, which is what
   `retire`'s comment claims and could not make good while `confirm` was gated on
   `reachable`. Under the rule the design adopted -- silence resolved externally,
   the stand-down carried by the confirmation alone -- the holder walks up to the
   tree, reads it clean, and retires it, having never been able to address it.
   SAT, and UNSAT with the guard restored: that pair is the finding these two
   commands were added for.

   READ THE WITNESS FOR WHAT IT IS, and A14b is why it needs reading: the trace
   retires an executor that has already DIED. It cannot be stood down first --
   `standDown` carries `reachable` and this executor is unaddressable by
   construction -- so the only ending available to it is `retire`'s second
   disjunct, the one that needs no answer from the far end. That is the honest
   shape of the guarantee and it is the right one: an executor nobody can reach
   cannot be ASKED to stop, and dropping the guard buys the ability to destroy
   its workspace lawfully, not the ability to be polite about it. What it costs
   is stated where it lands -- an unannounced executor that is still running is
   not retirable at all, which is one more reason CLAIMED is not optional. */
pred A14_UnannouncedExecutorIsRetirable {
  resolveSilenceExternally and coLocatedShutdown
  some a: Agent { always a not in Addressed
                  eventually a in Retired }
}

/* A14b. AND IT CANNOT BE STOOD DOWN, which is the half of A14 that reads like a
   defect until it is stated. UNSAT at A14's own bounds: adding one stand-down to
   A14's witness empties it, because `standDown` is one of the three acts that
   carry a message and this executor has no address to carry one to. The command
   exists so the sentence above is re-runnable rather than remembered. */
pred A14b_UnannouncedExecutorCannotBeStoodDown {
  A14_UnannouncedExecutorIsRetirable
  some a: Agent { always a not in Addressed
                  eventually (Now.ev = StandDown and Target.agent = a) }
}

/* A15. And its pull request still lands. `mergedByHolder` wants every executor
   of the issue confirmed, so gating `confirm` made an unannounced executor's
   work permanently unmergeable -- a consequence no prose stated and `gh pr
   merge` does not have, since it needs only the number. SAT; UNSAT with the
   guard. */
pred A15_UnannouncedExecutorPRLands {
  mergedByHolder
  some a: Agent { always a not in Addressed
                  eventually (Now.ev = MergePR and Now.issue = a.task) }
}

/* ---------------- commands ---------------- */

check NoLostWork        for 3 Issue, 2 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 2 Repo, 1 Topic, 2 Tree, 10 steps
check NoOrphan          for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 2 Repo, 1 Topic, 2 Tree, 10 steps
check NoOrphanIfGuarded for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 2 Repo, 1 Topic, 2 Tree, 10 steps

check UnguardedShutdownIsUnsafe  for 2 Issue, 1 PR, 1 Campaign, 2 Session, 2 Agent, 2 Machine, 2 Repo, 1 Topic, 2 Tree, 10 steps
check OneStepShutdownSuffices    for 2 Issue, 1 PR, 1 Campaign, 2 Session, 2 Agent, 2 Machine, 2 Repo, 1 Topic, 2 Tree, 10 steps
check TwoStepShutdownSuffices    for 2 Issue, 1 PR, 1 Campaign, 2 Session, 2 Agent, 2 Machine, 2 Repo, 1 Topic, 2 Tree, 10 steps
check TwoStepCoLocatedSuffices   for 2 Issue, 1 PR, 1 Campaign, 2 Session, 2 Agent, 2 Machine, 2 Repo, 1 Topic, 2 Tree, 10 steps
check SilenceResolutionStaysSafe for 2 Issue, 1 PR, 1 Campaign, 2 Session, 2 Agent, 2 Machine, 2 Repo, 1 Topic, 2 Tree, 10 steps

run Sanity                          for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 1 Session, exactly 1 Agent, exactly 1 Machine, exactly 2 Repo, exactly 1 Topic, 1 Tree, 12 steps
run ReportIsNotEvidence             for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 1 Session, exactly 1 Agent, exactly 1 Machine, exactly 2 Repo, exactly 1 Topic, 1 Tree, 10 steps
run BlockedAgentDoesNotProceed      for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 1 Session, exactly 1 Agent, exactly 1 Machine, exactly 2 Repo, exactly 1 Topic, 1 Tree, 10 steps
run SilentAgentIsRetirableUnderWait for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 1 Session, exactly 1 Agent, exactly 1 Machine, exactly 2 Repo, exactly 1 Topic, 1 Tree, 12 steps
run SilentAgentStillRetired         for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 1 Session, exactly 1 Agent, exactly 1 Machine, exactly 2 Repo, exactly 1 Topic, 1 Tree, 12 steps

run S3_DelegateDiesAfterPushing for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 1 Session, exactly 1 Agent, exactly 1 Machine, exactly 2 Repo, exactly 1 Topic, 1 Tree, 12 steps
run S4_ReportWithoutPush        for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 1 Session, exactly 1 Agent, exactly 1 Machine, exactly 2 Repo, exactly 1 Topic, 1 Tree, 12 steps
run S9_OrphanedByLocalDelete    for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 2 Session, exactly 1 Agent, exactly 1 Machine, exactly 2 Repo, exactly 1 Topic, 1 Tree, 12 steps

run R3b_CloseFromAnotherMachine  for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 12 steps
run R3c_GlobalCloseRuleBlocks    for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 12 steps

run R4_SameBranchTwice           for 4 Issue, 1 PR, 1 Campaign, 2 Session, 2 Agent, 1 Machine, 3 Repo, 1 Topic, 1 Tree, 12 steps
run R4b_CrossCampaignCoexists    for 4 Issue, 1 PR, 2 Campaign, 2 Session, 2 Agent, 1 Machine, 3 Repo, 1 Topic, 2 Tree, 14 steps
run R4c_CheckoutSwitchedUnderAgent for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 3 Repo, 2 Topic, 1 Tree, 12 steps
run R4d_SameSubtaskTwice         for 4 Issue, 1 PR, 1 Campaign, 2 Session, 2 Agent, 1 Machine, 3 Repo, 1 Topic, 1 Tree, 12 steps
run R4e_NumberedBranchStillShared for 4 Issue, 1 PR, 1 Campaign, 2 Session, 2 Agent, 1 Machine, 3 Repo, 1 Topic, 1 Tree, 12 steps
run R4f_ClaimClosesSameSubtask    for 4 Issue, 1 PR, 1 Campaign, 2 Session, 2 Agent, 1 Machine, 3 Repo, 1 Topic, 1 Tree, 12 steps
run R4g_ClaimWithoutAtomicityStillShared for 4 Issue, 1 PR, 1 Campaign, 2 Session, 2 Agent, 1 Machine, 3 Repo, 1 Topic, 1 Tree, 12 steps

run R5b_VisibleNotPushed         for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 12 steps
run R5c_NonLauncherSameMachineIsFine for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 3 Repo, 1 Topic, 1 Tree, 12 steps
run R6_ReleaseUnderRemoteAgent   for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 12 steps
run R6b_ReclaimAfterDeath        for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 14 steps

/* A1-A3 run at TWO agents. The discipline they measure is `announceAtClaim`,
   whose first draft was unsatisfiable for two unaddressed executors at once --
   an artefact of `lone Target.agent` that one Agent could never expose. A4-A12
   need one executor each and say so; A9-A12 need a Tree to delete. */
run A1_UnannouncedExecutorIsInvisible        for 3 Issue, 1 PR, 1 Campaign, 2 Session, 2 Agent, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 12 steps
run A2_AnnounceMakesEveryHolderActReachable  for 3 Issue, 1 PR, 1 Campaign, 2 Session, 2 Agent, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 12 steps
run A3_AnnounceAdmitsExecutorSession         for 3 Issue, 1 PR, 1 Campaign, 2 Session, 2 Agent, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 14 steps

run A4_ExecutorMergesItsOwnPR                for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 14 steps
run A5_MergedByHolderBlocksExecutorMerge     for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 14 steps
run A6_UnreviewedMerge                       for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 12 steps
run A7_MergedByHolderBlocksUnreviewed        for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 12 steps
run A8_MergedByHolderAdmitsTheLanding        for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 14 steps

run A9_RecordDiesWithTheDirectory            for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 12 steps
run A10_DeleteUnderAnnouncedExecutor         for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 12 steps
run A11_ReadableGateBlocksTheDelete          for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 12 steps
run A12_ReadableGateAdmitsTheDelete          for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 12 steps
run A13_PushAfterReviewUnReviews             for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 14 steps
run A14_UnannouncedExecutorIsRetirable       for 3 Issue, 1 PR, 1 Campaign, 2 Session, 2 Agent, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 14 steps
run A14b_UnannouncedExecutorCannotBeStoodDown for 3 Issue, 1 PR, 1 Campaign, 2 Session, 2 Agent, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 14 steps
run A15_UnannouncedExecutorPRLands           for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 14 steps

run Cov_LaunchAgent      for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps
run Cov_Work             for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps
run Cov_Push             for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps
run Cov_Status           for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps
run Cov_Answer           for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps
run Cov_Report           for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps
run Cov_Blocked          for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps
run Cov_Decide           for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps
run Cov_Confirm          for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps
run Cov_ConfirmElsewhere for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps
run Cov_Announce         for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps
run Cov_Review           for 3 Issue, 2 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 12 steps
run Cov_StandDown        for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps
run Cov_Retire           for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps
run Cov_AgentDie         for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps
run Cov_GuardedRelease   for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps
