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
 * other. Normative: this file is the whole contract, and the parts of it that
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
 *   Review            `/code-review <PR#>`, a reviewer the session that wants
 *                     the merge launches -- the author's own included
 *   MergePR (guard)   on what terms it lands: this layer's half of session.als's
 *                     event
 *   StandDown         STAND DOWN, campaign -> executor
 *   Retire            the workspace is destroyed
 *   Release (guard)   what may be released: this layer's half of repos.als's event
 *   AgentDie          the process dies on its own
 *
 * `Agent` here is an EXECUTOR of a subtask. It comes in one of two kinds,
 * distinguished by one field, `peer` -- a herdr DELEGATE, `--name`d at
 * launch, or a CAMPAIGN SESSION WORKING ITS OWN CLAIM, whose `peer` is
 * itself. The `Agent` sig below carries the field-level detail of each.
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

 * The harness's own peer messaging. ListAgents resolves the address, not
 * herdr's pane label. A delegate's address was chosen at launch
 * (claude --name); a session's own claim carries the address it wrote for
 * itself into `runtime/claims/<issue>` at the claim -- its ListAgents name
 * and its pid.
 *
 * A running session CAN be renamed, by itself or by a peer driving its pane;
 * whether a call is ALLOWED is a per-session permission decision, not a
 * property of the tool. So a name can change, and the record -- not the name
 * -- is what a later reader relies on to tie a name to a claim.
 *
 * It is the right transport for two load-bearing reasons: it is not the
 * terminal screen (a pane shows only what is rendered, capped by the
 * emulator's buffer, where a message is delivered and queued), and it carries
 * no state (every exchange is a fresh question and answer, so a restarted or
 * second-machine session needs no handover to talk to an executor).
 *
 *
 * RETIREMENT, AND WHY THE PROTOCOL EXISTS AT ALL
 *
 * An executor does not close itself: it pushes, opens or updates a pull
 * request, then goes quiet, and the campaign session retires it once the work
 * has landed -- at the merge, never at the campaign's CLOSE, since a
 * long-lived campaign finishes subtasks continuously while it stays open.
 * Retirement does not wait for pull-request open either: a claim-holding
 * executor is the session that merges, so retiring it there would remove the
 * one thing that can; a long fix round goes to a fresh session instead,
 * briefed from the pull request and the review.
 *
 * The procedure is five steps, and `twoStepShutdown` plus `coLocatedShutdown`
 * below are steps 2 and 4 written as disciplines the model can check:
 *
 *   1. STATUS every executor under the campaign tree, by its address -- a
 *      delegate's `--name`, a session claim's `runtime/claims/<issue>` record.
 *   2. For each that says it is finished: confirm in GitHub, and against the
 *      working tree, that nothing it holds exists only on this machine.
 *   3. Review the pull request, and land it or send it back. NOTHING LANDS
 *      WITHOUT A CURRENT REVIEW -- not a delegate's work, not a session's own.
 *      The executor pushes, REPORTs the URL and its sha once per round, and
 *      waits; the session that wants the merge launches a reviewer -- an
 *      in-process subagent, always, the only mode, except an `ultra` review,
 *      which a person triggers and no session may -- reads the findings, and
 *      either merges (telling the executor the work is durable, which is what
 *      lets it drop its worktree) or briefs a fresh executor from the pull
 *      request and review and runs the loop again. The author may be the
 *      merger, provided the review is current at the revision merged. This
 *      step fixes WHO acts, not WHEN retirement may happen; a review that
 *      will not finish in one sitting is handed to a fresh session rather
 *      than held open. `mergedOnCurrentReview` below is this step checked;
 *      A4 is the live collision it was re-derived from.
 *   4. STAND DOWN the confirmed ones. Leave the rest, and say why.
 *   5. Retire the workspace once the executor has acknowledged.
 *
 * Self-termination, self-merging and self-reviewing are all refused for one
 * reason: the only thing that can verify an executor's work is something
 * other than that executor.
 *
 *
 * ONE ENCODING OF "ONLY ON THIS MACHINE"
 *
 * `Local` is it, and it is the whole of it. `Visible` is kept as a separate
 * bit because it is a genuinely different fact, readable from a different
 * place: the branch is on the remote. The two are independent and their gap
 * is the finding R5b names -- an executor whose branch is on the remote may
 * still hold work that is not.
 *
 * `Addressed` and `Reviewed` are each a fact about a DIFFERENT object than
 * `Local` is. `Addressed` is about a campaign
 * session's reach -- can anyone ask this executor anything at all -- and it is
 * why liveness and attribution are two predicates below rather than one.
 * `Reviewed` is about the pull request, so it outlives the executor exactly as
 * the pull request does and a fresh executor briefed from the review inherits
 * it.
 *
 *
 * UNMODELLED, STATED FOR THE RECORD
 *
 * Five rules of the contract have no construct here, each a fact about the
 * message medium rather than about reachable states:
 *   - The executor answers about itself only, never siblings, the campaign,
 *     or whether an issue should close.
 *   - NO STATE BEYOND WHAT `runtime/` HOLDS ON THE BOUND MACHINE, which dies
 *     with the campaign directory -- no second copy of a GitHub fact, and
 *     nothing that outlives the cache it describes. The one exception is the
 *     claim record, written by the claiming session for itself at the claim,
 *     because a later close or sweep -- by any campaign session, possibly one
 *     that did not exist yet -- must be able to read it back. What it carries
 *     is an ADDRESS, a fact about this machine that exists nowhere else.
 *   - STAND DOWN is a request, not an order: the campaign session reaches the
 *     executor as a peer, and a peer cannot command. A refusal from its own
 *     pane's user is information about a conflict, not disobedience, and is
 *     resolved at the pane.
 *   - The reviewer is a process, and this layer models processes only where
 *     their state matters; the reviewer's does not, it leaves one durable
 *     mark, `Reviewed`, so `review` names the issue rather than any process.
 *   - Adequacy is still unmodelled. `Reviewed` records that somebody looked,
 *     never what they concluded; ledger.als's header says the same of a
 *     merged pull request.
 *
 * Deliberately absent from the protocol itself: no self-termination, for the
 * reason above; no heartbeat (liveness is already a herdr fact, and a
 * heartbeat would be a second, worse copy that also stops when the executor
 * is merely busy); and no task assignment message (the handover brief is a
 * file, because the launch line has a 1024-byte ceiling and a brief must be
 * readable afterwards).
 *
 * WHO DOES THE WORK, AND WHY IT IS NOT MODELLED
 *
 * The three execution modes a campaign session chooses between -- its own
 * hands, an in-process subagent on a worktree, a herdr delegate in a clone --
 * are one `Launch` here on purpose: the branch is the same claim, the
 * completion is the same GitHub fact, and the only differences are turn cost
 * and whether a process boundary is crossed, none of which is a reachable
 * state. The choice between them turns on an operator's constraints -- which
 * process loads which skills, a fact about the harness a check could only
 * restate and pass by construction -- so it is not modelled, for the same
 * reason ledger.als states the delegation mechanics rather than modelling it.
 *
 * One consequence does reach this layer: a session that draws a
 * member-repository subtask becomes the LAUNCHER of a delegate rather than
 * its executor, and the delegate has no `peer` -- its address is the
 * `--name` its launcher chose. So `peer` marks the executor that ends up
 * holding the claim, not the session that took the subtask, and `aDeleteDir`
 * strips addresses by it for exactly that reason: only a session claim's
 * address is a file.
 *
 * One open risk, named rather than solved: retiring at "pull request open"
 * means nobody is watching the review. Until a board exists, the person is
 * the one who notices.
 *
 *
 * VERDICTS
 *
 * X is a counterexample; a check that passes reads UNSAT.
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
  /* AN EXECUTOR MAY BE A SESSION: `peer` is that session, which claimed its
     own branch and works it with its own hands, but otherwise acts as any
     executor does. The field is what makes the address question askable: a
     herdr delegate is `--name`d at launch, reachable by construction, while a
     session's own claim is named by nothing anybody else chose, so it writes
     its ListAgents name and pid into `runtime/claims/<issue>` at the claim --
     what `Addressed` below records. */
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

/* What a close gate can read AND ATTRIBUTE, a strictly smaller set than what
   it can see (`liveUnderLocally`). THE SPLIT'S SUBJECT IS ATTRIBUTION, NOT
   LIVENESS: a herdr delegate is listed with its subtask readable from `cwd`,
   but a campaign session's pane cannot say WHICH subtask it works -- its cwd
   is the container root like every other's, so only `runtime/claims/<issue>`
   ties the name to the claim. Liveness is readable for both kinds without
   any record; attribution is not, so a live-and-unattributable executor can
   pass `liveUnderLocally`. A17 below measures the residual gap: after a
   directory delete, the pane still shows a live executor the record can no
   longer attribute. */
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
   was found: campaign-<N>/<topic>. Two executors share it when the campaign
   and the topic match -- true by definition, not by proof. BRANCH NAMES
   CANNOT COLLIDE ACROSS CAMPAIGNS: an issue has at most one parent, so a
   subtask maps to exactly one campaign number, and sharing a number sequence
   with the anchor keeps <issue> and <N> distinct rather than letting them
   coincide -- which is why what R4 finds below is intra-campaign only. */
pred sameBranchByTopic[a1, a2: Agent] {
  campaignOf[a1.task] = campaignOf[a2.task] and a1.topic = a2.topic
}

/* The adopted form, campaign-<N>/<issue>-<topic>: two executors share a
   branch only when campaign, subtask and topic all match. What R4e asks is
   what this still leaves standing. */
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

/* The executor's half of a launch: the claim (a branch already on the
   remote, created by create-ref) and the checkout, on the topic that is its
   branch. That the launcher made the claim is `claimBeforeLaunch` below, a
   discipline rather than a guard -- a launch that skips claiming is what R4e
   is about. */
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
  /* Every executor is addressable the moment it exists: a delegate from its
     `--name`, a session's own claim from the record it wrote at the claim,
     which precedes every launch (`claimBeforeLaunch`). No message, no relay
     hop, no unaddressed state to fall into. */
  Addressed' = Addressed + a
  Local' = Local and Visible' = Visible and Confirmed' = Confirmed
  keepReview and keepMsgs and keepShutdown
  Target.agent = a
}

/* The campaign directory is deleted, and the claim records under `runtime/`
   go with it. Every other bit this layer holds outlives the tree; `Addressed`
   is the one that does not, because for a session working its own claim it
   IS a file in the tree.

   ONLY FOR SUCH A SESSION, and `some a.peer` is the whole of the guard: a
   delegate's address is the `--name` its launcher chose, living in the
   launch and in `herdr agent list`, not in `runtime/claims/` -- so stripping
   it here would make a live delegate permanently unreachable the moment an
   unrelated directory was deleted, with `retire` -- deliberately left
   unguarded -- the only thing left that could touch it.

   Scoped to the deleted tree's own campaign and machine: `Present - Present'`
   is the tree that just went, so two campaigns sharing a machine do not
   clear each other's records (repos.als's MachineIndependence claim, applied
   here). */
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
   pushes as soon as it has one commit, so a lost workspace costs only
   uncommitted work. Pushing puts the branch on the remote and clears the
   local-only work -- two different facts, and only the first is readable
   from elsewhere; it does not set Confirmed, since nothing here lets the
   session believe without looking.

   It clears `Reviewed` for the same reason `work` clears `Confirmed`: a
   fresh executor briefed from a bad review pushes new commits onto the same
   pull request, and a review is of a pull request AT A REVISION, not of
   whatever commits happen to sit under an old review bit. */
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

   Sent once per round, when it has pushed a branch and opened or updated a
   pull request. It names the pull request URL and the sha that URL sits at
   (a fix round adds the comment carrying its disposition table), which is
   what makes a verdict and a later push survive crossing.

   A report is a prompt to verify, never the verification: an executor
   asserting it is finished is the delegate verifying its own work, the one
   thing the design refuses, so this event writes NOTHING but the claim
   itself -- the campaign session reads GitHub before believing it.
   Fabrication is cheap to disprove this way, but the rule catches
   fabrication, not inadequacy: a real pushed branch with a real pull request
   that does not do what was asked passes every check. Verifying that the
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

/* The campaign session reads the executor's working tree ITSELF: no
   uncommitted changes, no unpushed commits, no branch absent from the remote.
   Stated as an absence because "the branch is pushed and the pull request is
   open" has no passing form for an executor that correctly produced nothing
   durable -- what is always checkable is the inverse, `a not in Local`.

   NO `reachable` GUARD, deliberately: this reads a working tree on the
   session's own machine and sends the executor nothing, so an address at the
   far end is not needed. Gating it made a record-less executor impossible to
   CONFIRM and so impossible to retire or land -- A14 and A15 measure exactly
   that. */
pred confirm[a: Agent] {
  coLocated[By.actor, a]
  a.task in By.actor.holds.members
  a not in Local
  Confirmed' = Confirmed + a
  Live' = Live and Local' = Local and Visible' = Visible
  keepReview and keepMsgs and keepAddress and keepShutdown and keepBorn
  Now.ev = Confirm and Now.issue = a.task and Target.agent = a
}

/* The same check run from another machine: it reads the SESSION's working
   tree, not the executor's, so it comes back clean whatever the executor
   holds -- no `a not in Local` guard because nothing on this machine could
   fail it. Not a modelling shortcut; it is the defect, surfacing at
   TwoStepShutdownSuffices below. A `reachable` guard would not have saved
   it either: what is wrong is the tree it reads, and no addressability rule
   reaches that. */
pred confirmElsewhere[a: Agent] {
  not coLocated[By.actor, a]
  a.task in By.actor.holds.members
  Confirmed' = Confirmed + a
  Live' = Live and Local' = Local and Visible' = Visible
  keepReview and keepMsgs and keepAddress and keepShutdown and keepBorn
  Now.ev = ConfirmElsewhere and Now.issue = a.task and Target.agent = a
}

/* REVIEW -- `/code-review <PR#>` run against a subtask's pull request.

   A pull request is reviewed before it is merged, by A REVIEWER THE SESSION
   THAT WANTS THE MERGE LAUNCHES. ONE MODE, NOT A DEFAULT: an IN-PROCESS
   SUBAGENT, because a review changes no repository working tree and needs
   none of what a process boundary is paid for. The one exception is an
   `ultra` review, which a person triggers and no session may.

   KEYED ON THE ISSUE, NOT ON AN AGENT, because the review is of the pull
   request -- `/code-review <PR#>` reads GitHub, and neither the executor's
   process nor its address is in that read.

   THE REVIEWER IS A SEPARATE AGENT WHOEVER LAUNCHES IT. The property needs
   INDEPENDENCE OF JUDGEMENT, NOT INDEPENDENCE OF TASKING: the reviewer that
   reads the diff is never the process that wrote it, which holds when the
   author-session launches it exactly as when any other session does -- the
   one-session campaign, the common case, has no other session to launch it.
   The named limit: the launcher writes the reviewer's brief, so an author can
   scope a brief to what it already believes and get a clean review of the
   wrong thing -- the same shape as briefing a reviewer of a delegate's work,
   which nobody wants to ban and no machinery here would tell apart.

   The reviewer is a process modelled only where its state matters, and it
   does not: it leaves one durable mark, `Reviewed`, so `no Target.agent`
   here too. No `reachable` guard either, for `confirm`'s reason: a record-
   less executor is unaddressable, not unlandable. */
pred review[i: Issue] {
  Now.ev = Review
  Now.issue = i
  some i.pr and i.pr not in Reviewed
  i in By.actor.holds.members
  Reviewed' = Reviewed + i.pr
  keepLife and keepMsgs and keepAddress and keepShutdown and keepBorn
  no Target.agent
}

/* STAND DOWN -- campaign to executor. Asks it to finish its current turn and
   stop; it does not destroy its own workspace, only acknowledges and goes
   quiet, which is why standing down and retiring are two events with the
   executor still Live between them.

   Nothing guards this predicate beyond holding the campaign and reaching the
   executor -- the discipline predicates below apply per command, so the
   unguarded protocol and each candidate repair are measured against the same
   trace space. */
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
   and GitHub never knew about it. The second disjunct is not a convenience:
   an executor that already died is retired without any stand-down, since
   nobody is left to ask -- that path skips every message in the protocol,
   which is why the disciplines below guard the retire and not only the
   stand-down.

   No `reachable` guard: an executor whose record went with a deleted
   directory still has a workspace somebody must be able to destroy, and
   retiring needs no answer from the far end. A14 measures what an unguarded
   `retire` is worth: a discipline that wants a CONFIRMATION first would keep
   such an executor alive forever if `confirm` were gated too, and
   `twoStepShutdown` strands it anyway on an ANSWER that needs an address --
   `resolveSilenceExternally` asks for the confirmation alone and lets it go. */
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

/* This layer's half of repos.als's `release`: what may be released, guarded
   by what a session can actually read -- nothing beyond main on the remote
   branch, no executor on ITS OWN machine working the task. Liveness
   elsewhere is not readable, so a live remote executor with no pushed work
   can still lose its claim under a rule correctly followed: R6 below is that
   residue. */
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

/* Stand down only an executor on your own machine -- AND confirm it from
   there too, since step 2's verification is read against a working tree, and
   a session elsewhere reads its own. THE CONFIRM HALF IS NOT DECORATION: a
   remote session running the confirmation for a local one to act on still
   lets the retire destroy work, so it covers Confirm and ConfirmElsewhere as
   well as StandDown and Retire -- narrowing it back to the latter two reddens
   TwoStepCoLocatedSuffices, proving the half load-bearing. */
pred coLocatedShutdown {
  always (Now.ev in Confirm + ConfirmElsewhere + StandDown + Retire
            implies coLocated[By.actor, Target.agent])
}

/* Rule 3, as a discipline: silence is a liveness question, not a protocol
   answer. An unanswered STATUS is asked once more and resolved through herdr
   and GitHub, so a gone executor may be stood down on the confirmation
   alone -- a quiet executor is not a finished one, and waiting forever for a
   reply that cannot come is the failure this rule stops. */
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

/* The claim discipline, in two halves: launch only onto a claim your
   launcher created, and create only where no ref exists (create-ref's 422,
   server-side). Together they close R4e (R4f UNSAT); R4g drops atomicity
   alone and the collision returns, so the refusal -- not the ritual -- is
   load-bearing. */
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

/* THE DELETE GATE, answering session.als's R3: a directory must not be
   deleted while another session works the campaign, and session.als cannot
   say how anyone would know, since a working peer was a fact no file
   carried. `runtime/claims/` is that file now, so the gate is keyed on the
   record rather than on the peer, and the record is complete -- no claim
   exists without a session having written its own at the claim. */
pred noDeleteUnderReadableExecutor {
  always (Now.ev = DeleteDir implies
            no a: Agent | a in Live and a.host = Site.mach and reachable[a]
                          and campaignOf[a.task] in (Present - Present').camp)
}

/* Every executor of one subtask. `mergedOnCurrentReview` quantifies over it,
   and the set is empty for a subtask a session did with its own hands. */
fun executorsOf[i: Issue]: set Agent { task.i }

/* NO SESSION LANDS ITS OWN WORK UNREVIEWED -- and nobody lands anyone's.

   The property is about the work, not the identity: what a bad merge lacks
   is not a different merger but a review, so no conjunct here names who may
   merge -- the author may merge exactly as anyone else may, once the review
   is current. The identity phrasing, "merged by a session that did not push
   it", was weighed and rejected: in the one-session campaign, the common
   case, no second session exists to merge, so that rule makes the normal
   landing unreachable and calls it safety. A16 is the sanctioned author-merge
   measured SAT; A16b is the same author stopped by a stale review; A4/A5 are
   the collision, still caught.

   CURRENT means current for the revision being merged: `Reviewed` is cleared
   by `push` (A13), so the bit reads "read at the pull request's head as it
   stands now". A squash merge produces a commit that did not exist when the
   review ran, so pinning the review to the MERGED COMMIT would call every
   squash merge unreviewed; pinning it to the head instead means a reviewed
   head squash-merges as reviewed, and only a new push un-reviews it.

   The second conjunct is claim-is-not-evidence: every executor of the
   subtask has been CONFIRMED, by a session on its own machine, before the
   merge -- universal, not existential, so vacuously true when there are
   none, which is the hands-on case. Confirmation and review answer different
   questions: confirmation asks whether anything exists only on this machine,
   an absence, checkable; review asks whether the work is any good, which
   nothing else in this model asks (ledger.als's header calls adequacy
   unmodelled).

   No conjunct names the merger or a campaign: `Reviewed` and `Confirmed` are
   keyed to the issue and its executors, which no reparent can move, so no
   silent-reparent hole can arise.

   TWO OF AGENTS.md's THREE MERGE CONDITIONS ARE UNMODELLED HERE. The
   NON-AUTHOR condition -- the review is written by an agent that did not
   write the commits -- is axiomatized by `review`'s shape but has no
   conjunct enforcing it: `Reviewed` records that somebody looked, not who,
   so the condition needs a reviewer identity this layer does not carry, and
   has no reader on GitHub either, where one account signs every comment. The
   CONTAINS-CURRENT-MAIN condition is unexpressible for a different reason:
   this model has one pull request per issue, no notion of a shared branch
   moving under another, so the trace it forbids -- two reviewed branches,
   both merged, combined state read by nobody -- cannot be built without
   giving `main` a state and branches a base. It is unmodelled but not
   unenforced: a required status check on `main` refuses a merge whose
   branch is behind, even under an admin token, and accepts once the base is
   merged in. A16/A16b measure only the sha half. */
pred mergedOnCurrentReview {
  always (Now.ev = MergePR implies
            (Now.issue.pr in Reviewed
             and (all a: executorsOf[Now.issue] |
                    a in Confirmed and coLocated[By.actor, a])))
}

/* ---------------- properties ---------------- */

/* PASS. No lost work: an executor dying and a directory being deleted never
   un-complete a subtask. Nothing written in THIS file carries it -- completion
   is ledger's, so what this check tests is the composition idiom: dropping
   `ledgerFrame` from ledger's fall-through branch is what reddens it. */
assert NoLostWork {
  always all i: Issue |
    (complete[i] and Now.ev in AgentDie + DeleteDir) implies after complete[i]
}

/* X. No orphan: no executor is live on a checkout whose campaign directory is
   gone. Nothing enforces "no campaign closes while an executor is live under
   its tree" -- named as a local check with its blind spot: two machines hold
   campaign #N, an executor is live on machine 0, and the operator on machine
   1 deletes its tree, which no local check can see. */
pred noOrphanNow {
  all a: Agent | a in Live implies (some c: Campaign | a.task in c.members and a.host in dirsOf[c])
}

assert NoOrphan { always noOrphanNow }

// PASS, once the retirement rule the design states is actually enforced.
assert NoOrphanIfGuarded {
  ((always (Now.ev = DeleteDir implies (no a: Agent | a in Live and a.host = Site.mach)))
   and (always (Now.ev = RemoveMember implies (no a: Agent | a in Live and a.task = Now.issue))))
  implies (always noOrphanNow)
}

/* X. Unguarded: work is destroyed. The baseline the disciplines are measured
   against -- an executor works, is stood down, is retired. */
assert UnguardedShutdownIsUnsafe { noWorkDestroyed }

/* X. THE ONE-STEP DEFECT: a REPORT says nothing about a second, uncommitted
   change made after it. Counterexample: the executor reports, works again, is
   stood down on the strength of the report, and is retired with the new work
   still only on its disk. */
assert OneStepShutdownSuffices { oneStepShutdown implies noWorkDestroyed }

/* X. THE REMOTE HOLE, not a modelling artefact: two steps are not enough
   when step 2 runs from the wrong machine. Counterexample: confirmElsewhere
   fires, the executor still holds Local, and the retire destroys it -- a
   remote session's check passes because the branch is on the remote, while
   uncommitted work on the executor's disk dies with the workspace. R5b and
   R5c below are the controls that pin its axis. */
assert TwoStepShutdownSuffices { twoStepShutdown implies noWorkDestroyed }

/* PASS: two steps, on your own machine. Confirmed is cleared by any later
   `work`, so the green survives an executor that keeps working after being
   confirmed. */
assert TwoStepCoLocatedSuffices {
  (twoStepShutdown and coLocatedShutdown) implies noWorkDestroyed
}

/* PASS: rule 3's repair does not reopen the hole. Dropping the requirement
   for an ANSWER an executor can no longer give is safe as long as the
   session's own confirmation is kept and read on the right machine. */
assert SilenceResolutionStaysSafe {
  (resolveSilenceExternally and coLocatedShutdown) implies noWorkDestroyed
}

/* ---------------- witnesses ---------------- */

/* The whole retirement procedure, reachable: works, pushes, STATUS answered,
   confirmed, stood down, retired. SAT means the disciplines above forbid a
   counterexample rather than forbidding the protocol. */
pred Sanity {
  coLocatedShutdown and twoStepShutdown
  and eventually (some a: Agent | a in Retired)
  and eventually Now.ev = Work
  and eventually Now.ev = Push
}

/* Rule 1 as a witness, and the whole of "the agent went idle is not
   completion": the executor claims it is finished while still holding work
   only its machine has, and the claim leaves both that fact and the GitHub
   fact exactly as they were. A weaker signal, such as a pane falling quiet,
   says even less. */
pred ReportIsNotEvidence {
  some a: Agent | eventually (Now.ev = Report and Target.agent = a
    and a in Local and a in Local'
    and not complete[a.task] and after always not complete[a.task])
}

/* BLOCKED stops the executor rather than letting it guess: waiting, with no
   Work event firing while it does. */
pred BlockedAgentDoesNotProceed {
  some a: Agent | eventually (a in Waiting and always (a in Waiting and Now.ev != Work))
}

/* THE FAILURE RULE 3 FORBIDS: under wait-for-the-answer, an executor asked
   for STATUS that dies without replying can never be retired -- the premise
   the discipline waits on is one the world can no longer supply. UNSAT: no
   such trace, so the session waits forever for a reply that cannot come. */
pred SilentAgentIsRetirableUnderWait {
  waitForAnswer
  and (some a: Agent |
         eventually (a in Asked and a not in Live and a in Retired)
         and always a not in Answered)
}

/* Rule 3's repair, and the control that it is a repair rather than a
   prohibition: the same never-answering executor is still retired. */
pred SilentAgentStillRetired {
  resolveSilenceExternally and coLocatedShutdown
  and (some a: Agent | eventually a in Retired and always a not in Answered)
}

/* The delegate dies after pushing: completion is a GitHub fact, so it
   survives the death and never comes undone. */
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

/* The delegate reports done while nothing is pushed: the claim never becomes
   a GitHub fact on its own, and the campaign session must not believe it. */
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

/* The delete lands on the machine the live executor runs on: NoOrphan's
   counterexample, as a witness a run can reproduce on purpose. */
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

/* R3b. The cross-machine form: session 2 closes the anchor from M0 while
   session 1's delegate is live on M1. The local gate reads closable because
   it reads only M0; the campaign is not. R3c below restates the close rule
   globally and blocks it, so this is the rule unreadable from one machine,
   not the rule failing. */
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
   Scoped to traces with no RemoveMember, a finding rather than a convenience:
   `liveUnder` reads an executor as under a campaign when its subtask is a
   member OR its machine holds the tree, and moving the subtask out while
   deleting the tree turns both false, permitting the close after all -- the
   same silent-reparent risk ledger.als names. */
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

/* R4. Two sessions of one campaign launch delegates into the same repository
   on the same topic: campaign-<N> keeps campaigns apart, nothing keeps two
   sessions of one campaign apart. Against campaign-<N>/<topic>, the branch
   form this was found on -- two subtasks, two delegates, one checkout; R4d
   is the same with a single subtask. */
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

/* R4b. Positive control for R4: two executors of DIFFERENT campaigns, same
   repository, same <topic> deliberately chosen, do not share a branch --
   what campaign-<N> buys, isolating R4's collision as intra-campaign. */
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

/* R4c. The acquire race: one machine, one checkout of the repository, and
   session 2 acquires it onto another branch while session 1's delegate is
   live in it with work not on the remote -- the shared checkout switches off
   the branch S1's delegate is working. */
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

/* R4d. The sharper form: two sessions delegate the SAME subtask issue.
   Nothing in the design caps a subtask at one executor. */
pred R4d_SameSubtaskTwice {
  some disj a1, a2: Agent {
    a1.launcher != a2.launcher
    a1.task = a2.task
    eventually (a1 in Live and a2 in Live)
  }
}

/* R4e. The adopted branch form, and what it does not fix: two sessions
   delegating the SAME subtask still land on one branch, since AGENTS.md's
   rule only answers the two-subtask collision. */
pred R4e_NumberedBranchStillShared {
  some disj a1, a2: Agent {
    a1.launcher != a2.launcher
    eventually (a1 in Live and a2 in Live
                and some campaignOf[a1.task] and sameBranch[a1, a2])
  }
}

/* R4f. The claim discipline closes R4e: launch only a claim you created, and
   create-ref refuses an existing ref, so the second session's claim fails
   before a second executor exists. UNSAT at R4e's own bounds. */
pred R4f_ClaimClosesSameSubtask {
  claimBeforeLaunch and claimAtomic
  R4e_NumberedBranchStillShared
}

/* R4g. CONTROL: the ritual without the refusal -- both sessions claim,
   nothing refuses the second create, both launch. SAT: the server's 422 is
   the load-bearing half, not the procedure. */
pred R4g_ClaimWithoutAtomicityStillShared {
  claimBeforeLaunch
  some disj s1, s2: Session, i: Issue |
    eventually (i in s1.claims and i in s2.claims)
  R4e_NumberedBranchStillShared
}

/* =================== retiring another session's delegate =================== */

/* R5b. Control for TwoStepShutdownSuffices: an executor whose branch is on
   the remote may still hold work that is not -- the gap that finding rests
   on is reachable at all. */
pred R5b_VisibleNotPushed { some a: Agent | eventually (a in Visible and a in Local) }

/* R5c. Ownership is not the axis: under the local check, a session that did
   not launch the executor may still retire it safely, provided it shares its
   machine. */
pred R5c_NonLauncherSameMachineIsFine {
  localCheckedShutdown
  some disj s1, s2: Session, a: Agent {
    a.launcher = s1 and a.host = s1.smach and s2.smach = a.host
    eventually (Now.ev = StandDown and By.actor = s2 and Target.agent = a)
  }
}

/* R6. What release cannot read: the guard is local -- nothing on the remote
   branch, no live executor on THIS machine -- because liveness elsewhere is
   not readable, so a live remote executor with unpushed work loses its claim
   under a rule correctly followed. Same mitigation as the remote hole: push
   as soon as one commit exists. */
pred R6_ReleaseUnderRemoteAgent {
  some s: Session, a: Agent {
    a.host != s.smach
    eventually (a in Live and a not in Visible
                and Now.ev = Release and By.actor = s and Now.issue = a.task)
  }
}

/* R6b. Recovery: a dead delegate's dangling claim is released and reclaimed
   by a survivor. The claim does not outlive its usefulness. */
pred R6b_ReclaimAfterDeath {
  some disj s1, s2: Session, a: Agent {
    a.launcher = s1
    eventually (a in Launched and a not in Live and a not in Visible
                and eventually (Now.ev = Release
                and eventually (Now.ev = Claim and By.actor = s2 and Now.issue = a.task)))
  }
}

/* =================== the claim record =================== */

/* A1. Whether an executor whose claim record was never written is still
   attributable at a close. UNSAT: the claiming session writes
   `runtime/claims/<issue>` before any executor exists, so `launch` sets
   `Addressed` unconditionally. What remains is the post-delete window -- a
   record dies with the directory (A9), gated at A10-A12, and what A14/A15
   measure. */
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

/* A3. Control for A1: the whole retirement procedure still runs for a
   session's own executor -- launched addressed from birth, working, pushing,
   answering STATUS, confirmed, stood down, retired. An UNSAT here would mean
   A1 went green by forbidding the executor's life altogether. */
pred A3_RecordedExecutorRunsTheWholeProtocol {
  coLocatedShutdown and twoStepShutdown
  some c: Campaign, disj s1, s2: Session, a: Agent {
    a.peer = s2 and a.task in c.members
    s1.smach = s2.smach
    eventually (Now.ev = Status and By.actor = s1 and Target.agent = a)
    eventually a in Retired
  }
}

/* A13. A PUSH UN-REVIEWS THE PULL REQUEST, mirroring what `work` does to a
   confirmation: a review lands, the executor pushes again, and the pull
   request is no longer reviewed, so `mergedOnCurrentReview` no longer holds
   over it. A review is of a pull request AT A REVISION, so new commits under
   an old review's bit must not merge legally. SAT. */
pred A13_PushAfterReviewUnReviews {
  some a: Agent |
    eventually (Now.ev = Review and Now.issue = a.task
                and after eventually (Now.ev = Push and Target.agent = a
                                      and after (a.task.pr not in Reviewed)))
}

/* =================== who merges, and who reviews =================== */

/* A4. THE LIVE COLLISION: an executor session squash-merged its own pull
   request in the same minute a holding session sent a hold, with the
   protocol ending at REPORT and no rule naming who lands a subtask. SAT: the
   executor is confirmed, a REPORT preceded the merge, and nobody had
   reviewed it. A5 turns on the review conjunct alone. The reviewed, current
   self-merge did not disappear: it is the sanctioned landing now, and A16
   measures it admitted. */
pred A4_ExecutorMergesItsOwnPR {
  some c: Campaign, s2: Session, a: Agent {
    a.peer = s2 and a.task in c.members
    always s2.holds = c                -- the session works the campaign it holds
    eventually (Now.ev = Report and Target.agent = a)
    eventually (Now.ev = MergePR and By.actor = s2 and Now.issue = a.task
                and a in Confirmed and no a.task.pr & Reviewed)
  }
}

/* A5. The rule catches it: UNSAT at A4's own bounds, since the merge fires
   with `no a.task.pr & Reviewed` and the rule requires the review, so the
   collision as it happened cannot be built. */
pred A5_ReviewRuleBlocksTheCollision {
  mergedOnCurrentReview and A4_ExecutorMergesItsOwnPR
}

/* =================== the record, and what it is worth =================== */

/* A9. `Addressed` HAS THE DIRECTORY'S LIFETIME: the claim record is written
   at the claim, the directory is deleted, and the record goes with it. SAT.
   That is why it is a file under `runtime/` and not a second copy of a
   GitHub fact -- it answers a question only the bound machine has. Its cost
   is A10. */
pred A9_RecordDiesWithTheDirectory {
  some a: Agent {
    some a.peer                        -- a delegate's address is its --name, not a file
    eventually (reachable[a] and Now.ev = DeleteDir and Site.mach = a.host
                and after not reachable[a])
  }
}

/* A10. THE DELETE, UNGATED, under an executor the deleting session CAN see:
   session.als's R3 with the missing half supplied -- the claim record names
   the working session, and the directory is deleted under it anyway because
   nothing reads the record. SAT. */
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
   the subtask merges it, confirmed but unreviewed. SAT -- with A4 this pair
   says the rule's subject is the review, not the merger: both chairs reach
   the same illegal merge, and A5/A7 block both with the one conjunct. */
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

/* A8. Control for A5 and A7 together: the whole two-session landing still
   runs -- pushed, REPORTed, confirmed by another session sharing its
   machine, reviewed, merged. SAT, so neither UNSAT above is green by
   forbidding merges. The one-session landing is A16's subject. */
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

/* A14. AN EXECUTOR WHOSE RECORD DIED IS STILL RETIRABLE, which `retire`'s
   comment claims and could not make good while `confirm` was gated on
   `reachable`. The record goes with the directory, and under the design's
   rule -- silence resolved externally, stand-down carried by the
   confirmation alone -- a session reads what remains clean and retires it
   with no way left to address it. SAT, and UNSAT with the `reachable` guard
   restored on `confirm`. Read it for what it is, not more: nothing can ASK
   this executor to stop (`standDown` still carries `reachable`, A14b), so
   dropping the guard on `confirm` buys a lawful destruction, not a polite
   one. */
pred A14_UnaddressedExecutorIsRetirable {
  resolveSilenceExternally and coLocatedShutdown
  some a: Agent {
    some a.peer
    eventually (a not in Addressed and Now.ev = Confirm and Target.agent = a)
    eventually (a not in Addressed and Now.ev = Retire and Target.agent = a)
  }
}

/* A14b. AND IT CANNOT BE STOOD DOWN ONCE THE RECORD IS GONE. UNSAT at A14's
   own bounds: `standDown` carries a message, this executor has no address to
   carry one to, and nothing re-creates an address after the delete. */
pred A14b_UnaddressedExecutorCannotBeStoodDown {
  A14_UnaddressedExecutorIsRetirable
  some a: Agent {
    some a.peer
    eventually (a not in Addressed and Now.ev = StandDown and Target.agent = a)
  }
}

/* A15. And its pull request still lands. Gating `confirm` on `reachable`
   would have made a record-less executor's work permanently unmergeable, a
   consequence no prose stated and `gh pr merge` does not carry. SAT; UNSAT
   with the guard restored. */
pred A15_UnaddressedExecutorPRLands {
  mergedOnCurrentReview
  some a: Agent {
    some a.peer
    eventually (a not in Addressed and Now.ev = Confirm and Target.agent = a)
    eventually (Now.ev = MergePR and Now.issue = a.task)
  }
}

/* A16. THE ONE-SESSION LANDING: one session, its own hands-on work, a review
   by a separate agent it launched itself, current at the merged revision --
   ADMITTED. SAT. The trace the identity-based rule would have forbidden, no
   second session existing to merge for the author; run at exactly one
   Session so that absence is the scope, not an accident of the witness. */
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

/* A16b. AND A STALE REVIEW DOES NOT CARRY IT: the same author, a review,
   then a push, then no review ever again -- no merge of that subtask can
   happen. UNSAT: A13 composed with the rule, since the push retired the
   review and the author gets no special door on an unreviewed merge. */
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

/* A18. THE AGENT-LESS LANDING: a session working its own subtask launches no
   Agent at all, how this file represents hands-on work throughout. It
   matters because `mergedOnCurrentReview`'s confirm conjunct, universally
   quantified over `executorsOf[Now.issue]`, is VACUOUSLY true when that set
   is empty -- the review half alone holds the rule up here, which A16 cannot
   see since it has an Agent to range over. SAT. */
pred A18_AgentLessLandingIsAdmitted {
  mergedOnCurrentReview
  no Agent
  some s: Session, i: Issue {
    eventually (Now.ev = Review  and By.actor = s and Now.issue = i)
    eventually (Now.ev = MergePR and By.actor = s and Now.issue = i)
  }
}

/* A18b. AND THE OTHER DIRECTION, the half a vacuous conjunct could have
   swallowed: no Agent, no Review anywhere, and a merge. If the review half
   were ever weakened the way the confirm half is vacated here, this would go
   SAT and hands-on work would land unreviewed -- the same collision A4
   reproduces. UNSAT. */
pred A18b_AgentLessUnreviewedMergeIsBlocked {
  mergedOnCurrentReview
  no Agent
  always Now.ev != Review
  some i: Issue | eventually (Now.ev = MergePR and Now.issue = i)
}

/* A17. SEEN LIVE, NO LONGER ATTRIBUTABLE: a session's own executor is live
   and in the pane listing (`liveUnderLocally`), its directory is deleted so
   its record is gone, and `liveAndReadable` no longer names it -- the
   residual gap `liveAndReadable`'s comment locates. SAT. The only door to
   the unattributed state is the delete, gated at A10-A12: the pane proves
   the executor ALIVE and cannot say WHOSE CLAIM it is, which no liveness
   listing can. */
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

/* A1 and A3 keep the two-agent bounds needed to hold the UNSAT at the bounds
   where the gap was widest. A4-A12 need one executor each and say so; A9-A12
   need a Tree to delete; A14-A15 need one to delete mid-trace. A16 and A16b
   run at exactly ONE Session, because the absence of a second merger is
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
