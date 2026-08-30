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
 * How a campaign session and the executors under its campaign talk to each
 * other. Normative. AGENTS.md carries the short form -- four messages and the
 * two-step shutdown; this file is the whole contract, and the parts of it that
 * can be checked are checked below rather than asserted in prose.
 *
 *   event             performed by
 *   Launch (executor) the `claude --session-id ... --name campaign-<N>-executor-<n>`
 *                     that starts an executor on the claim its launcher made
 *   Work              the executor edits its checkout
 *   Push              git push -- the one act that makes work survivable
 *   Status            STATUS, campaign -> executor
 *   Answer            the executor's reply to an outstanding STATUS
 *   Report            REPORT, executor -> campaign, unsolicited: the pull
 *                     request URL and the sha it sits at
 *   Blocked           BLOCKED, executor -> campaign, unsolicited
 *   Decide            the campaign session answers a BLOCKED
 *   Confirm           the session reads the executor's working tree ITSELF
 *   ConfirmElsewhere  the same check run from the wrong machine -- the defect
 *   Review            `/code-review <PR#>`, a reviewer a campaign session
 *                     launches -- any session, the author's included
 *   MergePR (guard)   on what terms it lands: this layer's half of session.als's
 *                     event
 *   StandDown         STAND DOWN, campaign -> executor
 *   Retire            the workspace is destroyed
 *   Release (guard)   what may be released: this layer's half of repos.als's event
 *   AgentDie          the process dies on its own
 *
 * The fifth message, CLAIMED, and its `Announce` event were retired by #59; the
 * self-written claim record replaced them, and the stub where `announce` stood
 * says how.
 *
 * `Agent` here is an EXECUTOR of a subtask. It comes in two kinds and the
 * difference is one field, `peer`:
 *
 *   a herdr DELEGATE, launched into a clone by a campaign session, `--name`d
 *   campaign-<N>-executor-<n> -- a delegate is an executor and gets no role
 *   word of its own -- so its address was chosen by its launcher and is known
 *   before the process exists; and
 *
 *   a CAMPAIGN SESSION WORKING A CLAIM WITH ITS OWN HANDS -- under one role
 *   (#59) any session whose machine the campaign is BOUND to may take a
 *   subtask and claim its branch. `peer` is that session, `launcher` is
 *   itself, and its address is `runtime/claims/<issue>`, the record it wrote
 *   for itself at the claim -- which is what `Addressed` carries.
 *
 * Everything else is shared. Both answer STATUS, send REPORT and BLOCKED, stop
 * on STAND DOWN, never write the anchor, and land nothing that lacks a current
 * review -- their own work included, which is `mergedOnCurrentReview` below.
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
 * campaign-<N>-executor-<n>), and a
 * session's own claim carries the address the session wrote for itself into
 * `runtime/claims/<issue>` at the claim -- its ListAgents name and its pid.
 * Before #59 that address travelled as a message, CLAIMED, whose absence was
 * invisible: an executor that never sent it looked like no executor at all,
 * and A1 below was that gap SAT. The record's write moved to the claimant and
 * the gap is UNSAT by construction -- A1 is the same scenario re-measured.
 *
 * A running session CAN be renamed -- by a person typing `/rename` into its
 * pane, or by another session driving that pane, which is the same act, its own
 * pane included. This supersedes the 2026-08-28 reading that only a person
 * could, which is dead. Whether a particular call is ALLOWED is a per-session
 * permission decision rather than a property of the tool: on 2026-08-30 one
 * session's self-rename was refused and the same call accepted later, while a
 * peer's was accepted throughout. Every session carries
 * campaign-<N>-<role>-<n>, AGENTS.md's one naming rule, so a name says what a
 * session does; the record stays the mechanism for tying that name to a claim,
 * because a name can be changed and the record is what a later reader has.
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
 *   1. STATUS every executor under the campaign tree, by its address -- a
 *      delegate's `--name`, a session claim's `runtime/claims/<issue>` record.
 *   2. For each that says it is finished: confirm in GitHub, and against the
 *      working tree, that nothing it holds exists only on this machine.
 *   3. Review the pull request, and land it or send it back. NOTHING LANDS
 *      WITHOUT A CURRENT REVIEW -- not a delegate's work, not a session's own.
 *      The executor pushes, REPORTs the URL and its sha once per round, and
 *      waits. A campaign session launches a reviewer on the pull request -- an
 *      in-process subagent by default, a herdr session only for a many-turn or
 *      `ultra` review -- reads the findings, and then either merges -- and
 *      tells the executor the work is durable, which is what lets the executor
 *      drop its worktree -- or briefs a fresh executor from the pull request
 *      and the review and runs the loop again. The author may be the merger,
 *      provided the review is current at the revision merged.
 *      `mergedOnCurrentReview` below is this step checked; A4 is the live
 *      collision it was re-derived from.
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
 * about a DIFFERENT object than `Local` is. `Addressed` is about a campaign
 * session's reach -- can anyone ask this executor anything at all -- and it is
 * why liveness and attribution are two predicates below rather than one.
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
 *     no registry", and the claim record contradicts it: the claiming session
 *     writes `<campaign>/runtime/claims/<issue>` for itself at the claim,
 *     because whoever runs a close or a sweep later -- any campaign session,
 *     possibly one that did not exist yet -- must be able to read it back. The
 *     amended clause is the rule that was actually meant -- no second copy of a
 *     GitHub fact, and nothing that outlives the cache it describes. Every
 *     exchange still stands alone; what the record carries is an ADDRESS,
 *     which is a fact about this machine and exists nowhere else.
 *   - STAND DOWN is a request, not an order. Whoever types into the executor's
 *     pane is its user; the campaign session reaches it as a peer, and a peer
 *     cannot command. An executor with a contradicting instruction from its own
 *     pane is right to refuse. Treat a refusal as information about a conflict,
 *     not as disobedience, and resolve the conflict at the pane.
 *
 * Two more, added with the review step:
 *   - The reviewer is a process, and this layer models processes only where
 *     their state matters. The reviewer's does not: it leaves exactly one
 *     durable mark and that mark is `Reviewed`, so `review` names the issue
 *     whose pull request is read rather than any process at all.
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
 * The three execution modes a campaign session chooses between -- its own
 * hands, an in-process subagent on a worktree, a herdr delegate in a clone --
 * are one `Launch` here on purpose. No construct below distinguishes them,
 * because nothing a model can say about reachable states differs between them:
 * the branch is the same claim, the completion is the same GitHub fact, and
 * the only differences are turn cost and whether a process boundary is
 * crossed.
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
 * at all: a session that draws a member-repository subtask becomes the
 * LAUNCHER of a delegate rather than the executor of it, and the delegate it
 * launches has no `peer` -- its address is the `--name` its launcher chose. So
 * `peer` is a property of the executor that ends up holding the claim, not of
 * the session that took the subtask, and `aDeleteDir` strips addresses by it
 * for exactly that reason: only a session claim's address is a file.
 *
 * And one open risk, named rather than solved: retiring at "pull request open"
 * means nobody is watching the review. Until a board exists, the person is the
 * one who notices.
 *
 *
 * VERDICTS
 *
 * Measured 2026-08-30 against this file. X is a counterexample; a check that
 * passes reads UNSAT.
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
 *   A1_UnrecordedExecutorAtTheClose  UNSAT the #37 gap, closed BY CONSTRUCTION:
 *                                          the claimant writes its own record,
 *                                          so no live claim is unattributable
 *   A3_RecordedExecutorRunsTheWholeProtocol
 *                                    SAT   control: the whole run still happens
 *   A4_ExecutorMergesItsOwnPR        SAT   the live collision as it happened:
 *                                          a self-merge with NO review
 *   A5_ReviewRuleBlocksTheCollision  UNSAT still caught, by what was missing
 *   A6_UnreviewedMerge               SAT   the same merge from the other chair
 *   A7_ReviewRuleBlocksUnreviewed    UNSAT nobody merges unread
 *   A8_ReviewRuleAdmitsTheLanding    SAT   control: two-session landing runs
 *   A9_RecordDiesWithTheDirectory    SAT   the record has the tree's lifetime
 *   A10_DeleteUnderRecordedExecutor  SAT   session.als's R3, reached from here
 *   A11_ReadableGateBlocksTheDelete  UNSAT and closed by reading the record
 *   A12_ReadableGateAdmitsTheDelete  SAT   control
 *   A13_PushAfterReviewUnReviews     SAT   a review is of a pull request at a
 *                                          revision, and a push retires it
 *   A14_UnaddressedExecutorIsRetirable
 *                                    SAT   a record dead with its directory
 *                                          still ends in a lawful retire
 *   A14b_UnaddressedExecutorCannotBeStoodDown
 *                                    UNSAT and never a stand-down: that one
 *                                          carries a message, so it stays gated
 *   A15_UnaddressedExecutorPRLands   SAT   and its pull request still lands
 *   A16_AuthorLandsOwnReviewedWork   SAT   THE ONE-SESSION LANDING: author
 *                                          merges own work on a current review
 *                                          it launched itself
 *   A16b_AuthorCannotMergeOnStaleReview
 *                                    UNSAT and a push retires that permission
 *   A17_PaneSeesWhatTheRecordLost    SAT   the pane proves an executor alive
 *                                          and cannot say whose claim it is:
 *                                          attribution, not liveness, is the
 *                                          split's subject
 *   A18_AgentLessLandingIsAdmitted   SAT   THE AGENT-LESS LANDING, run at
 *                                          `0 Agent`: hands-on work reviewed
 *                                          and merged by one session, which is
 *                                          how campaign #1's own subtasks are
 *                                          represented here. #73's review
 *                                          probed both directions by hand and
 *                                          left no command; this is that probe
 *                                          pinned.
 *   A18b_AgentLessUnreviewedMergeIsBlocked
 *                                    UNSAT and unreviewed it does not land.
 *                                          The pair matters because
 *                                          `mergedOnCurrentReview`'s confirm
 *                                          conjunct ranges over
 *                                          `executorsOf[Now.issue]`, empty at
 *                                          `0 Agent`, so it is VACUOUSLY true
 *                                          and the review half is holding the
 *                                          rule up alone. Dropping
 *                                          `mergedOnCurrentReview` from A18b
 *                                          turns it SAT, so the UNSAT is the
 *                                          rule and not the bounds.
 *   Cov_*                            SAT   every own event fires in some trace
 *
 * Every green was proved able to fail, re-run 2026-08-28 against the pre-#59
 * model and unchanged by #59's edits: letting `work` keep an earlier
 * confirmation instead of clearing it reddens TwoStepCoLocatedSuffices and
 * SilenceResolutionStaysSafe; narrowing `coLocatedShutdown` to the stand-down
 * alone reddens TwoStepCoLocatedSuffices; dropping the RemoveMember clause
 * reddens NoOrphanIfGuarded; and dropping `ledgerFrame` from ledger.als's
 * fall-through branch reddens NoLostWork -- which is the point of the
 * layering, since nothing written in THIS file holds a GitHub fact still while
 * an executor dies.
 *
 * The greens #59 added or re-derived were each proved able to fail by a named
 * mutation, run 2026-08-30 against this model on a copy and undone with it:
 *
 *   A1        restoring the conditional write at launch -- `no a.peer implies
 *             Addressed' = Addressed + a else keepAddress`, the pre-#59 rule
 *             where only a delegate is born addressed. SAT: the gap returns,
 *             which locates the whole repair in who writes the record.
 *   A5, A7    dropping the `Now.issue.pr in Reviewed` conjunct from
 *             `mergedOnCurrentReview`, leaving the confirmation in place. Both
 *             SAT: the rule's whole content is the review, so removing it
 *             readmits the collision from both chairs.
 *   A11       keying `noDeleteUnderReadableExecutor` on `no a.peer` instead of
 *             `reachable[a]`, so the gate reads delegates and ignores session
 *             claims. SAT: the delete lands under the recorded executor again,
 *             the blind spot the record exists to close.
 *   A14, A15  restoring the `reachable[a]` guard on `confirm`. Both UNSAT:
 *             the post-delete confirm becomes impossible, so the record-less
 *             executor is unretirable and its pull request unlandable -- the
 *             consequence that keeps the guard off.
 *   A14b      dropping the `reachable[a]` guard from `standDown`. SAT: the
 *             unaddressed stand-down fires, which is what the guard forbids.
 *   A16b      letting `push` keep `Reviewed` -- A13's own mutation, re-run
 *             under the new rule. SAT: the stale review carries the merge,
 *             so the currency half of the rule is `push`'s clearing line.
 *
 * WHAT #59 RETIRED, AND ITS FINAL MEASUREMENTS
 *
 * The holder role, the executor-session role, the CLAIMED message, and the
 * rules keyed to them. All measurements below were verified on the pre-#59
 * model, 2026-08-28/29.
 *
 *   A1_UnannouncedExecutorIsInvisible  SAT    THE FINDING #37 WAS FILED FOR:
 *          liveness was never the missing half, attribution was. Re-derived as
 *          A1 above, UNSAT: the state is unreachable once the claimant writes
 *          its own record.
 *   A2_AnnounceMakesEveryHolderActReachable  UNSAT   CLAIMED-at-the-claim, as
 *          a discipline, closed the gap -- for executors that obeyed it, which
 *          A1 measured as exactly the loophole. Folded into A1, and the fold
 *          answers "stronger, weaker, or the same": STRONGER. The property
 *          held conditionally on `announceAtClaim`; it now holds with no
 *          discipline conjoined, at the same bounds, over the same trace
 *          space. What bounds it instead is the record's lifetime -- a
 *          directory delete still unaddresses (A9), which is why the delete is
 *          gated (A10-A12) and what A14/A15 measure.
 *   A3_AnnounceAdmitsExecutorSession  SAT    its control; A3 above is the same
 *          control re-derived without the message.
 *   `mergedByHolder`  the separation of duties keyed to the holder role:
 *          A4 (reviewed, confirmed self-merge, blocked only by the merger's
 *          identity) SAT; A5 = rule + A4 UNSAT; A7 UNSAT; A8 SAT. Replaced by
 *          `mergedOnCurrentReview`, and the boundary was re-measured before
 *          the change with three probes kept here because the new rule's
 *          derivation rests on them:
 *            P1  holder merges its own hands-on subtask -- no Agent anywhere,
 *                which is how this file said hands-on work is represented --
 *                under mergedByHolder: UNSAT, but by ACCIDENT. `review` was
 *                keyed to an Agent, so agent-less work could never become
 *                Reviewed and the review conjunct could never be satisfied.
 *                The old rule blocked the case issue #59 says it missed --
 *                by making the work unreviewable, not by any rule about
 *                merging. (P1b, the same merge unguarded: SAT.)
 *            P2  a review commissioned by the author-session, `Review` with
 *                `By.actor = a.peer`: UNSAT. The old guard made the case
 *                inexpressible outright -- including the legal one-session
 *                landing, which is the reason the guard is gone.
 *            P3  the peer-agent form, review commissioned by ANOTHER session,
 *                holder merges its own work under mergedByHolder: SAT. The
 *                one form in which the old rule truly missed the self-merge.
 *          So "today's rule does not block the holder's hands-on self-merge"
 *          is REFUTED as stated and confirmed in the P3 form only; A16/A16b
 *          above are the boundary as the new rule draws it -- admitted when
 *          the review is current, blocked when it is stale or absent.
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
 *   Addressability guarded STATUS alone, so four other session-to-executor
 *   events fired against executors nobody could reach. `reachable` is one
 *   predicate now, over the three events that CARRY A MESSAGE -- status,
 *   decide, standDown -- which is what the retired A2 was renamed to certify
 *   before #59 folded it into A1. `confirm` and `review` read a working tree
 *   and a pull request instead of the executor, so they are not gated on it;
 *   A14 and A15 are what that costs when they are.
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
 *   The merge discipline had a silent-reparent history: first keyed to the
 *   issue's mutable membership, where a reparent emptied its antecedent, then
 *   to the merger's own campaign. `mergedOnCurrentReview` closes the file on
 *   it -- its conjuncts read the issue and its executors, which no reparent
 *   moves, so no scoping antecedent exists to empty.
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
     executor put itself there: a campaign session took a subtask, claimed its
     branch, and works it with its own hands. Everything else about it is an
     executor's -- it answers STATUS, sends REPORT and BLOCKED, stops on STAND
     DOWN, and never writes the anchor.

     The field is what makes the address question askable. A herdr delegate is
     `--name`d its branch at launch, so the launching session knows how to
     reach it by construction; a session's own claim is named by nothing
     anybody else chose, so the session writes its ListAgents name and pid into
     `runtime/claims/<issue>` at the claim -- which is what `Addressed` below
     records. */
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
var sig Addressed in Agent {}   -- a campaign session can reach it. A delegate
                                -- from its --name at launch; a session's own
                                -- claim from `<campaign>/runtime/claims/<issue>`,
                                -- which the claiming session wrote for itself
                                -- at the claim. THE RECORD IS A DIRECTORY
                                -- FACT: it dies with the tree, and it is keyed
                                -- to no reader, so any later session inherits
                                -- every address in it
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
  /* A session working its own claim is its own launcher, on its own machine. */
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
/* WHETHER ANY CAMPAIGN SESSION CAN REACH THIS EXECUTOR AT ALL. A delegate is
   reachable from its `--name`, which its launcher chose; a session's own claim
   from `runtime/claims/<issue>`, which the claiming session wrote for itself
   at the claim. One predicate, used by every message-carrying event below,
   because "I can see it in a list" and "I can send it a message" are different
   questions, and this is the second one. */
pred reachable[a: Agent] { a in Addressed }

/* And what a close gate can read AND ATTRIBUTE, which is a strictly smaller
   set than what it can see. `liveUnderLocally` is the seeing; this narrows it
   to the executors the machine's `runtime/claims/` can name.

   THE SPLIT'S SUBJECT IS ATTRIBUTION, NOT LIVENESS, and saying so matters
   because the liveness half was misstated in prose. A herdr delegate is listed
   by `herdr agent list` with its `cwd` under the campaign tree -- name and
   subtask both readable. A campaign session working its own claim holds a pane
   and is listed too (observed 2026-08-30: three live sessions of campaign #1,
   all in `herdr agent list`), so AGENTS.md's stated reason for splitting the
   liveness readings -- "an executor session runs no herdr pane at all" -- is
   FALSE, and the observation is a counterexample to that reason, not to the
   split. What the pane cannot say is WHICH subtask the session works: a pane
   gives a name, and a campaign session's cwd is the container root like every
   other's, so only `runtime/claims/<issue>` ties the name to the claim.
   LIVENESS IS READABLE FOR BOTH KINDS WITHOUT ANY RECORD; ATTRIBUTION IS NOT,
   and the close gate needs attribution. This model has encoded exactly that
   since #37: `liveUnderLocally` reads peer agents with no record clause, and
   the pre-#59 A1 witness held `liveUnderLocally` TRUE at the close it slipped
   through -- the executor was visibly alive and unattributable. A17 below is
   the residual gap measured on this model: after a directory delete, the pane
   still shows a live executor the record can no longer attribute. */
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

one sig Work, Push, Status, Answer, Report, Blocked, Decide,
        Confirm, ConfirmElsewhere, Review, StandDown, Retire, AgentDie extends Event {}

fun agentOwn: set Event {
  Work + Push + Status + Answer + Report + Blocked + Decide
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
  /* Every executor is addressable the moment it exists (#59). A delegate is,
     because the launching session chose its `--name`; a session working the
     claim itself is, because THE CLAIMING SESSION WROTE ITS OWN RECORD,
     `runtime/claims/<issue>`, at the claim -- which precedes every launch
     (`claimBeforeLaunch`), so by the time the executor exists its address
     does. No message, no relay hop, and no unaddressed state to fall into:
     A1 below is the old gap measured closed. */
  Addressed' = Addressed + a
  Local' = Local and Visible' = Visible and Confirmed' = Confirmed
  keepReview and keepMsgs and keepShutdown
  Target.agent = a
}

/* CLAIMED, and the `announce` event that carried it, stood here and are
   retired by #59: with the record written by the claiming session itself at
   the claim, there is no holder to announce to and nothing left for a message
   to carry. The record keeps everything the message used to establish -- the
   branch, the address, the pid that makes its liveness a local `kill -0` --
   and gains what the message never had: it is complete, because the session
   that takes a claim is the one thing that always knows the claim was taken.
   The header carries the retired protocol's final measurements (A1-A3). */

/* The campaign directory is deleted, and the claim records under `runtime/`
   go with it. Every other bit this layer holds is about a process or a pull
   request and outlives the tree; `Addressed` is the one that does not, because
   for a session working its own claim it IS a file in the tree,
   `runtime/claims/<issue>`.

   ONLY FOR SUCH A SESSION, and the `some a.peer` guard is the whole of it.
   A delegate's address is the `--name` its launcher chose, which lives in the
   launch and in `herdr agent list`, not in `runtime/claims/` -- so a delegate
   is addressable for as long as it runs, whatever happens to the tree. Stripping
   it here would have made a live delegate permanently unreachable the moment a
   directory it does not depend on was deleted, and `retire` -- the one campaign
   act deliberately left unguarded -- would then be the only thing left that
   could touch it.

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

   Sent once per round, when it has pushed a branch and opened or updated a pull
   request. It names the pull request URL and the sha that URL sits at, and
   stops; a fix round adds the URL of the comment carrying its disposition
   table. The sha is what makes a verdict and a later push survive crossing.

   A report is a prompt to verify, never the verification. The campaign session
   reads GitHub before believing it. An executor asserting it is finished is the
   delegate verifying its own work, which is the one thing the design refuses --
   so this event writes NOTHING but the claim itself. Everything a command below
   cares about is untouched by it, and that is the model's statement of rule 1.

   A REPORT names a URL and the sha it sits at, which makes fabrication cheap to
   disprove -- a false one was caught in about two seconds by four independent
   checks -- and makes a verdict crossing a later push harmless, because each
   names the revision it is about (#52). But the rule
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
   end is not what it needs. Gating it made an executor without a record --
   then one that never announced, now one whose record died with its directory
   -- impossible to CONFIRM, and every discipline that wants a confirmation
   before the retire then made it impossible to retire and its pull request
   impossible to land -- A14 and A15, both UNSAT with the guard in place and
   SAT without it (the header's mutation table). */
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
   reason, and the guard would not have saved it either: `runtime/claims/` is
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

/* REVIEW -- `/code-review <PR#>` run against a subtask's pull request.

   The owner's rule: a pull request is reviewed before it is merged, and the
   review is A REVIEWER A CAMPAIGN SESSION LAUNCHES. Two modes, and the default
   is the cheaper one: an IN-PROCESS SUBAGENT running `/code-review <PR#>`,
   because a review only reads and so needs none of what a process boundary is
   paid for -- no handover file, no canary, no pane, no sweep. A HERDR SESSION
   is for a review that will take many turns, or an `ultra` review, which is
   person-triggered only and is never the default. `/code-review` is
   model-invocable, so that command is the whole opening prompt either way.

   KEYED ON THE ISSUE, NOT ON AN AGENT (#59), because the review is of the pull
   request: `/code-review <PR#>` reads GitHub, and neither the executor's
   process nor its address is anywhere in that read. The old signature,
   `review[a: Agent]`, made a hands-on subtask -- one worked by a session with
   no Agent anywhere -- unreviewable, and `mergedByHolder` then blocked its
   merge as a side effect of the same blindness (measured on the pre-#59 model,
   2026-08-29: P1 in the header). A review is about work, and work does not
   need a process attached to be read.

   THE REVIEWER IS A SEPARATE AGENT WHOEVER LAUNCHES IT, and that is why the
   old guard `By.actor != a.peer` is gone rather than translated. What the
   property needs is INDEPENDENCE OF JUDGEMENT, NOT INDEPENDENCE OF TASKING:
   the reviewer that reads the diff is never the process that wrote it, and
   that holds when the author-session launches it exactly as it holds when any
   other session does -- the one-session campaign, the common case, has no
   other session to launch it. The named limit, stated rather than modelled: the
   launcher writes the reviewer's brief, so an author can scope a brief to what
   it already believes and get a clean review of the wrong thing. That shape is
   identical to a session briefing a reviewer of a delegate's work, nobody
   wants to ban that, and no machinery here would tell them apart. (The old
   guard also made the case issue #59 names -- a review the author commissioned
   -- inexpressible outright: P2 in the header, UNSAT on the pre-#59 model.)

   The reviewer is a process, and this layer models processes only where their
   state matters; the reviewer's does not -- it leaves one durable mark, and
   that mark is `Reviewed`. `no Target.agent` for the same reason: the event is
   about no executor.

   No `reachable` guard either, for `confirm`'s reason: an executor whose
   record died with the directory is unaddressable, not unlandable, and no
   prose ever said otherwise. */
pred review[i: Issue] {
  Now.ev = Review
  Now.issue = i
  some i.pr and i.pr not in Reviewed
  i in By.actor.holds.members
  Reviewed' = Reviewed + i.pr
  keepLife and keepMsgs and keepAddress and keepShutdown and keepBorn
  no Target.agent
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

   No `reachable` guard, and it is the act that most obviously must not have
   one: an executor whose record went with a deleted directory still has a
   workspace somebody has to be able to destroy. Retiring needs no answer from
   the far end.

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
        launch[a] or work[a] or push[a]
        or status[a] or answer[a] or report[a]
        or blocked[a] or decide[a] or confirm[a] or confirmElsewhere[a]
        or standDown[a] or retire[a] or agentDie[a])
  or (some i: Issue | review[i])
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

/* `announceAtClaim` stood here -- CLAIMED at the claim, as a discipline an
   executor session had to obey -- and is retired by #59 with the message it
   disciplined. What it bought is now structural: `launch` writes `Addressed`
   unconditionally, because the claim record was written by the claiming
   session before any executor existed. A discipline binds only the obedient,
   and A1 was exactly the disobedient case; a construction has no disobedient
   case, which is the whole trade. The header carries the final measurements. */

/* THE DELETE GATE, and it is where session.als's R3 finding is answered.

   session.als can say that a directory must not be deleted while another
   session is working the campaign, and cannot say how anyone would know: a
   working peer is a fact no file carried. `runtime/claims/` is that file now,
   one record per claim written by the claiming session itself, so the gate
   belongs here, keyed on the record rather than on the peer -- and since #59
   the record is complete, because no claim exists without a session having
   written its own record at the claim. */
pred noDeleteUnderReadableExecutor {
  always (Now.ev = DeleteDir implies
            no a: Agent | a in Live and a.host = Site.mach and reachable[a]
                          and campaignOf[a.task] in (Present - Present').camp)
}

/* Every executor of one subtask. `mergedOnCurrentReview` quantifies over it,
   and the set is empty for a subtask a session did with its own hands. */
fun executorsOf[i: Issue]: set Agent { task.i }

/* NO SESSION LANDS ITS OWN WORK UNREVIEWED -- and nobody lands anyone's.

   Written after a live collision on 2026-08-28: the executor session for #36
   squash-merged its own pull request in the same minute the holding session
   sent "do not merge". The rule of that day, `mergedByHolder`, answered it by
   making the merge the holder's act; #59 retired the holder, and this
   predicate is the separation of duties re-derived WITH NO ROLE IN IT. What
   the collision actually lacked was not a different merger -- it was a review:
   the pull request went in with nobody having read it. So the property is
   about the work, not the identity. A MERGE REQUIRES A CURRENT REVIEW, and
   the author may then merge exactly as anyone else may.

   The identity phrasing -- "merged by a session that did not push it" -- was
   weighed and rejected before this was written: in the one-session campaign,
   the common case, no second session exists to merge, so that rule makes the
   normal landing unreachable and calls it safety. A16 below is the sanctioned
   author-merge measured SAT; A16b is the same author stopped by a stale
   review; A4/A5 are the collision, re-derived, still caught.

   CURRENT means current for the revision being merged, and the encoding is
   `Reviewed` cleared by `push` (A13): the bit reads "the review was read at
   the pull request's head as it stands now". Two neighbouring traps, one on
   each side of the merge. A push after the review retires the review -- A13,
   with A16b as it doing its work under this rule. And a squash merge produces
   a commit that did not exist when the review ran, so a reading that pinned
   the review to the MERGED COMMIT would call every squash merge unreviewed.
   The encoding pins the revision THE REVIEW WAS READ AT instead -- the pull
   request's head -- which the model states naturally because the squash
   artifact is no revision it carries: a reviewed head squash-merges as
   reviewed, and only a new push un-reviews.

   The second conjunct is claim-is-not-evidence, unchanged from the old rule:
   every executor of the subtask has been CONFIRMED, by a session on its own
   machine, before the merge -- `Target.agent in Reported` would put the
   executor's own account under the merge. UNIVERSAL, not existential: every
   executor of that subtask, and vacuously true when there are none, which is
   the hands-on case.

   Confirmation and review answer different questions and neither substitutes
   for the other. Confirmation asks whether anything exists only on this
   machine -- an absence, checkable, and what the two-step shutdown is for.
   Review asks whether the work is any good, which nothing else in this model
   asks at all; ledger.als's header says adequacy is unmodelled, and this is
   the one place the design puts a reader in front of it.

   No conjunct names the merger, and none names a campaign: the predecessor's
   `isHolder` conjunct went with the role, and its membership scoping went with
   it -- `Reviewed` and `Confirmed` are keyed to the issue and its executors,
   which no reparent can move, so the silent-reparent hole the old rule had to
   argue itself out of does not arise.

   TWO OF AGENTS.md's THREE MERGE CONDITIONS ARE UNMODELLED HERE, and both are
   named rather than left to be discovered.

   The NON-AUTHOR condition -- the review is written by an agent that did not
   write the commits -- is axiomatized by `review`'s shape and by P2 in the
   header, and there is no conjunct enforcing it. `Reviewed` is a bit on a pull
   request; nothing in this model records WHO set it, so the condition cannot be
   stated at all without a reviewer identity this layer does not carry. It is
   therefore a discipline with no reader here and none on GitHub either, where
   one account signs every session's comments. AGENTS.md says so at the rule.

   The CONTAINS-CURRENT-MAIN condition is not expressible for a different
   reason: this model has one pull request per issue and no notion of a shared
   branch moving under another, so "two reviewed branches, both merged, combined
   state read by nobody" -- the trace that condition exists to forbid -- cannot
   be built. Extending the model to see it means giving `main` a state and
   branches a base, which is a layer's worth of work and its own subtask (#95).
   Until then the condition is enforced by GitHub's behind-count and by nothing
   here, and A16/A16b measure only the sha half. */
pred mergedOnCurrentReview {
  always (Now.ev = MergePR implies
            (Now.issue.pr in Reviewed
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

/* =================== the claim record =================== */

/* A1. THE GAP #37 FOUND, MEASURED CLOSED BY CONSTRUCTION. On the pre-#59 model
   this was SAT and THE FINDING: a session working a claim that never sent
   CLAIMED was live, held its subtask's claim, and could not be attributed --
   ListAgents shows a peer's NAME and not the subtask it works -- so the local
   close gate read straight past it and the campaign closed over a running
   executor that had broken no rule it could have read. Liveness was never the
   missing half; attribution was.

   #59 moves the record's write from the recipient of a message to the taker of
   the claim: `runtime/claims/<issue>` is written by the claiming session, at
   the claim, before any executor exists, so `launch` sets `Addressed`
   unconditionally and the unrecorded live executor is not a state this model
   has. UNSAT -- the same scenario, no discipline conjoined, nothing left to
   disobey. What remains outside it is the post-delete window: a record dies
   with the directory (A9), which is why the delete is gated (A10-A12) and why
   A14/A15 measure what an executor without a record is still owed.

   The old repair pair is folded in here, and the fold is the answer to
   "stronger, weaker, or the same": A2 was this scenario plus `announceAtClaim`
   -- UNSAT only for executors that OBEYED the discipline, and A1 was exactly
   the disobedient case. The self-written record needs no discipline conjunct,
   so the property that was conditional is now unconditional: strictly
   stronger, at the same bounds, with the same trace space. */
pred A1_UnrecordedExecutorAtTheClose {
  some c: Campaign, disj s1, s2: Session, a: Agent {
    a.peer = s2 and a.task in c.members
    always a not in Addressed                   -- a claim with no record: unreachable now
    closeDisciplineAsRead[c]                    -- s1 obeys the gate it can read
    eventually (a in Live and a.task in Claimed
                and Now.ev = CloseIssue and Now.issue = c.anchor and By.actor = s1
                and liveUnderLocally[c, s1.smach])
  }
}

/* A3. Control for A1: the whole run still happens. A session's own executor
   launches -- addressed from birth, its claim record written at the claim --
   works, pushes, is asked for STATUS by another campaign session and answers,
   is confirmed on its own machine, stands down and is retired: the whole
   retirement procedure, under the full shutdown disciplines. An UNSAT here
   would mean A1 went green by forbidding the executor's life altogether. */
pred A3_RecordedExecutorRunsTheWholeProtocol {
  coLocatedShutdown and twoStepShutdown
  some c: Campaign, disj s1, s2: Session, a: Agent {
    a.peer = s2 and a.task in c.members
    s1.smach = s2.smach
    eventually (Now.ev = Status and By.actor = s1 and Target.agent = a)
    eventually a in Retired
  }
}

/* A13. A PUSH UN-REVIEWS THE PULL REQUEST, which is `push` mirroring what `work`
   does to a confirmation, and the witness that the hole is shut. A review lands;
   the executor pushes again; the pull request is no longer reviewed, so
   `mergedOnCurrentReview` no longer holds over it.

   The hole it closes was real and quiet. `review` is guarded `pr not in
   Reviewed` and the first draft's `push` framed the bit, so the loop the design
   documents -- brief a fresh executor from the review, it pushes again -- landed
   new commits under the old review's bit and merged legally. A review is of a
   pull request AT A REVISION, and nothing else in this model had a reason to
   know that. SAT. */
pred A13_PushAfterReviewUnReviews {
  some a: Agent |
    eventually (Now.ev = Review and Now.issue = a.task
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
/* BUILT SO THAT ONLY ONE THING IS WRONG, and #59 changed which thing that is.
   The old rule made the merger's identity the wrong thing, so the old A4
   pinned the review IN -- reviewed, confirmed, everything right except who
   merged. Under `mergedOnCurrentReview` the identity is free and THE REVIEW is
   the wrong thing, so this scenario pins it OUT: the session that worked the
   subtask merges it confirmed but with nobody having read it, which is what
   PR #42 actually was -- the review step did not exist yet, so no review had
   run when the merge landed. Everything else holds: the executor is confirmed,
   a REPORT preceded the merge. A5 turns on the review conjunct alone and the
   mutation that drops it reddens A5.

   The old encoding's trace -- the reviewed, current self-merge -- did not
   disappear: it is the sanctioned landing now, and A16 measures it admitted.
   The role pins (`isHolder[s1,c]`, `not isHolder[s2,c]`) went with the roles;
   `always s2.holds = c` stays, so the merger is a campaign session and the
   trace is the collision rather than an outsider's write. */
pred A4_ExecutorMergesItsOwnPR {
  some c: Campaign, s2: Session, a: Agent {
    a.peer = s2 and a.task in c.members
    always s2.holds = c                -- the session works the campaign it holds
    eventually (Now.ev = Report and Target.agent = a)
    eventually (Now.ev = MergePR and By.actor = s2 and Now.issue = a.task
                and a in Confirmed and no a.task.pr & Reviewed)
  }
}

/* A5. The rule: no session lands its own work unreviewed. UNSAT at A4's own
   bounds -- the merge fires with `no a.task.pr & Reviewed`, and the rule
   requires the review, so the collision as it happened cannot be built.
   Coordinator's measurement 1 for #59: the re-derived rule still catches the
   live collision, by the conjunct that names what was actually missing. */
pred A5_ReviewRuleBlocksTheCollision {
  mergedOnCurrentReview and A4_ExecutorMergesItsOwnPR
}

/* =================== the record, and what it is worth =================== */

/* A9. `Addressed` HAS THE DIRECTORY'S LIFETIME, exercised rather than asserted.
   A session's claim record is written at the claim, the directory is deleted,
   and the record goes with it. SAT.

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

/* A10. THE DELETE, UNGATED, under an executor the deleting session CAN see.
   This is session.als's R3 with the missing half supplied: the claim record
   names the working session, and the directory is deleted under it anyway
   because nothing reads the record. SAT. */
pred A10_DeleteUnderRecordedExecutor {
  some c: Campaign, a: Agent {
    some a.peer                        -- a session working its own claim: R3's victim
    a.task in c.members
    eventually (a in Live and reachable[a] and a in Local
                and Now.ev = DeleteDir and Site.mach = a.host)
  }
}

/* A11. The gate that reads the record, and R3's shape is gone: UNSAT. The
   repair session.als could name and not state, stated in the layer that has the
   record. */
pred A11_ReadableGateBlocksTheDelete {
  noDeleteUnderReadableExecutor and A10_DeleteUnderRecordedExecutor
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

/* A6. The same wrong merge from the other chair: a session that did NOT work
   the subtask merges it with nothing having reviewed the pull request, its
   executor confirmed. SAT -- a confirmation is a check that the work EXISTS,
   never that it is right, and with A4 this pair says the rule's subject is the
   review, not the merger: both chairs reach the same illegal merge and A5/A7
   block both with the one conjunct. */
pred A6_UnreviewedMerge {
  some c: Campaign, s: Session, a: Agent {
    a.task in c.members
    s != a.peer                        -- the merger did not work it
    always s.holds = c
    eventually (Now.ev = MergePR and By.actor = s and Now.issue = a.task
                and a in Confirmed and no a.task.pr & Reviewed)
  }
}

/* A7. The rule against it: UNSAT at A6's own bounds. */
pred A7_ReviewRuleBlocksUnreviewed { mergedOnCurrentReview and A6_UnreviewedMerge }

/* A8. Control for A5 and A7 together: the whole two-session landing path still
   runs. The executor pushes and REPORTs, another campaign session confirms it
   on their shared machine, a review lands on the pull request, and that
   session merges. SAT, so neither UNSAT above is green by forbidding merges.
   The one-session landing is A16's subject. */
pred A8_ReviewRuleAdmitsTheLanding {
  mergedOnCurrentReview
  some c: Campaign, disj s1, s2: Session, a: Agent {
    a.peer = s2 and a.task in c.members
    s1.smach = s2.smach and always s1.holds = c
    eventually (Now.ev = Report and Target.agent = a)
    eventually (Now.ev = Confirm and By.actor = s1 and Target.agent = a)
    eventually (Now.ev = Review and By.actor = s1 and Now.issue = a.task)
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
pred Cov_Review           { eventually Now.ev = Review }
pred Cov_StandDown        { eventually Now.ev = StandDown }
pred Cov_Retire           { eventually Now.ev = Retire }
pred Cov_AgentDie         { eventually Now.ev = AgentDie }
pred Cov_GuardedRelease   { eventually Now.ev = Release }

/* A14. AN EXECUTOR WHOSE RECORD DIED IS STILL RETIRABLE, which is what
   `retire`'s comment claims and could not make good while `confirm` was gated
   on `reachable`. Before #59 the unaddressed state had two doors, an executor
   that skipped CLAIMED and a record deleted with the tree; the self-written
   record closed the first (A1), so the delete is the one door left and this
   witness walks through it: the record goes with the directory, and under the
   rule the design adopted -- silence resolved externally, the stand-down
   carried by the confirmation alone -- a session walks up to what remains,
   reads it clean, and retires it, having no way left to address it. SAT, and
   UNSAT with the `reachable` guard restored on `confirm`: that pair is the
   finding these commands keep re-runnable.

   READ THE WITNESS FOR WHAT IT IS, and A14b is why it needs reading: nothing
   can ASK this executor to stop -- `standDown` carries `reachable` -- so its
   ending is a stand-down taken while the record still stood, or `retire`'s
   second disjunct, the one that needs no answer from the far end. Dropping the
   guard on `confirm` buys the ability to destroy its workspace lawfully, not
   the ability to be polite about it. */
pred A14_UnaddressedExecutorIsRetirable {
  resolveSilenceExternally and coLocatedShutdown
  some a: Agent {
    some a.peer
    eventually (a not in Addressed and Now.ev = Confirm and Target.agent = a)
    eventually (a not in Addressed and Now.ev = Retire and Target.agent = a)
  }
}

/* A14b. AND IT CANNOT BE STOOD DOWN ONCE THE RECORD IS GONE, which is the half
   of A14 that reads like a defect until it is stated. UNSAT at A14's own
   bounds: `standDown` is one of the three acts that carry a message, this
   executor has no address to carry one to, and nothing re-creates an address
   after the delete. The command exists so the sentence above is re-runnable
   rather than remembered. */
pred A14b_UnaddressedExecutorCannotBeStoodDown {
  A14_UnaddressedExecutorIsRetirable
  some a: Agent {
    some a.peer
    eventually (a not in Addressed and Now.ev = StandDown and Target.agent = a)
  }
}

/* A15. And its pull request still lands. `mergedOnCurrentReview` wants every
   executor of the issue confirmed, so gating `confirm` on `reachable` made a
   record-less executor's work permanently unmergeable -- a consequence no
   prose stated and `gh pr merge` does not have, since it needs only the
   number. SAT; UNSAT with the guard restored. */
pred A15_UnaddressedExecutorPRLands {
  mergedOnCurrentReview
  some a: Agent {
    some a.peer
    eventually (a not in Addressed and Now.ev = Confirm and Target.agent = a)
    eventually (Now.ev = MergePR and Now.issue = a.task)
  }
}

/* A16. THE ONE-SESSION LANDING, and the control #59 was corrected to demand:
   one session, its own hands-on work, a review by a separate agent it launched
   itself, current at the merged revision -- and the merge is ADMITTED. SAT.

   This is the trace the identity-based rule would have forbidden -- no second
   session exists here to merge for the author -- and the trace the pre-#59
   model could not even express, in either representation it offered: with no
   Agent the work was unreviewable (P1, header), and with this one the review's
   old `By.actor != a.peer` guard refused the author's launch (P2). Run at
   exactly one Session so the absence of a second merger is the scope, not an
   accident of the witness. */
pred A16_AuthorLandsOwnReviewedWork {
  mergedOnCurrentReview
  some s: Session, a: Agent {
    a.peer = s
    eventually (Now.ev = Push and Target.agent = a)
    eventually (Now.ev = Review and By.actor = s and Now.issue = a.task)
    eventually (Now.ev = Confirm and By.actor = s and Target.agent = a)
    eventually (Now.ev = MergePR and By.actor = s and Now.issue = a.task)
  }
}

/* A16b. AND A STALE REVIEW DOES NOT CARRY IT: the same author, a review, then
   a push, then no review ever again -- and no merge of that subtask can
   happen. UNSAT. This is A13 composed with the rule: the push retired the
   review, so the merge that follows is an unreviewed merge whoever performs
   it, and the author gets no special door. The case issue #59 filed against
   the old rule -- a session merging its own work on a review it commissioned
   -- is legal exactly as long as the review is current, and this command is
   the boundary measured from the far side. */
pred A16b_AuthorCannotMergeOnStaleReview {
  mergedOnCurrentReview
  some s: Session, a: Agent {
    a.peer = s
    eventually (Now.ev = Review and Now.issue = a.task
                and after eventually (Now.ev = Push and Target.agent = a
                                      and after ((always Now.ev != Review)
                                                 and eventually (Now.ev = MergePR
                                                                 and Now.issue = a.task))))
  }
}

/* A18. THE AGENT-LESS LANDING, which nothing pinned. #73's review probed it by
   hand -- `0 Agent` behaves correctly in both directions -- and left no command
   behind, so a later edit could lose it in silence. This is the representation
   of hands-on work this file has used since P1 in the header: a session working
   its own subtask launches no Agent at all, which is how every container
   subtask of campaign #1 was actually done.

   It matters because `mergedOnCurrentReview`'s confirm conjunct is universally
   quantified over `executorsOf[Now.issue]`, and with no Agent that set is
   empty, so the conjunct is VACUOUSLY true. Everything holding the rule up in
   this case is the review half alone. A16 cannot see that: it has an Agent, so
   its confirm conjunct has something to range over. SAT. */
pred A18_AgentLessLandingIsAdmitted {
  mergedOnCurrentReview
  no Agent
  some s: Session, i: Issue {
    eventually (Now.ev = Review  and By.actor = s and Now.issue = i)
    eventually (Now.ev = MergePR and By.actor = s and Now.issue = i)
  }
}

/* A18b. AND THE OTHER DIRECTION, which is the half a vacuous conjunct could
   have swallowed: no Agent, no Review anywhere in the trace, and a merge. If
   the review half were ever weakened the way the confirm half is vacated here,
   this would go SAT and hands-on work would land unreviewed with every rule
   obeyed -- the 2026-08-28 collision, reachable again through the one shape the
   model represents campaign #1's own subtasks with. UNSAT. */
pred A18b_AgentLessUnreviewedMergeIsBlocked {
  mergedOnCurrentReview
  no Agent
  always Now.ev != Review
  some i: Issue | eventually (Now.ev = MergePR and Now.issue = i)
}

/* A17. SEEN LIVE, NO LONGER ATTRIBUTABLE -- the residual gap between the two
   liveness readings, measured where `liveAndReadable`'s comment locates it. A
   session's own executor is live and in the pane listing (`liveUnderLocally`),
   its directory is deleted so its record is gone, and `liveAndReadable` no
   longer names it. SAT.

   This is what is left of pre-#59 A1 -- there, never-announced was the whole
   window; here the only door to the unattributed state is the delete, which
   A10-A12 gate. The command exists so the split's real justification stays
   measured rather than asserted: the pane proves the executor ALIVE and cannot
   say WHOSE CLAIM it is, which no liveness listing can. */
pred A17_PaneSeesWhatTheRecordLost {
  some c: Campaign, a: Agent {
    some a.peer
    a.task in c.members
    eventually (a in Live and liveUnderLocally[c, a.host]
                and not liveAndReadable[c, a.host])
  }
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

/* A1 and A3 keep the two-agent bounds the retired `announceAtClaim` demanded
   -- its per-agent artefact is history, and the UNSAT is held at the bounds
   where the old gap was widest. A4-A12 need one executor each and say so;
   A9-A12 need a Tree to delete; A14-A15 need one to delete mid-trace. A16 and
   A16b run at exactly ONE Session, because the absence of a second merger is
   their subject. */
run A1_UnrecordedExecutorAtTheClose          for 3 Issue, 1 PR, 1 Campaign, 2 Session, 2 Agent, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 12 steps
run A3_RecordedExecutorRunsTheWholeProtocol  for 3 Issue, 1 PR, 1 Campaign, 2 Session, 2 Agent, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 14 steps

run A4_ExecutorMergesItsOwnPR                for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 14 steps
run A5_ReviewRuleBlocksTheCollision          for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 14 steps
run A6_UnreviewedMerge                       for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 12 steps
run A7_ReviewRuleBlocksUnreviewed            for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 12 steps
run A8_ReviewRuleAdmitsTheLanding            for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 14 steps

run A9_RecordDiesWithTheDirectory            for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 12 steps
run A10_DeleteUnderRecordedExecutor          for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 12 steps
run A11_ReadableGateBlocksTheDelete          for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 12 steps
run A12_ReadableGateAdmitsTheDelete          for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 12 steps
run A13_PushAfterReviewUnReviews             for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 14 steps
run A14_UnaddressedExecutorIsRetirable       for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 14 steps
run A14b_UnaddressedExecutorCannotBeStoodDown for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 14 steps
run A15_UnaddressedExecutorPRLands           for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 16 steps
run A16_AuthorLandsOwnReviewedWork           for 3 Issue, 1 PR, 1 Campaign, 1 Session, 1 Agent, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 14 steps
run A16b_AuthorCannotMergeOnStaleReview      for 3 Issue, 1 PR, 1 Campaign, 1 Session, 1 Agent, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 14 steps
run A17_PaneSeesWhatTheRecordLost            for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 12 steps
run A18_AgentLessLandingIsAdmitted           for 3 Issue, 1 PR, 1 Campaign, 1 Session, 0 Agent, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 12 steps
run A18b_AgentLessUnreviewedMergeIsBlocked   for 3 Issue, 1 PR, 1 Campaign, 1 Session, 0 Agent, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 12 steps

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
run Cov_Review           for 3 Issue, 2 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 12 steps
run Cov_StandDown        for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps
run Cov_Retire           for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps
run Cov_AgentDie         for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps
run Cov_GuardedRelease   for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps
