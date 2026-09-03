/*
 * The witnesses over directory/system: what a campaign directory's presence
 * and absence buy. github/system.als is spec/'s entry point.
 */
module directory/scenarios

open directory/system

/* ---------------- witnesses ---------------- */

/* Two machines hold the campaign; one deletes its own tree while work
   continues, and the sub-issue still completes. */
pred S7_TwoMachinesOneDeletes {
  one c: Campaign | some i: c.members {
    #dirsOf[c] = 2
    mergeClosed[c.members]
    some m: Machine | eventually (Now.ev = DeleteDir and Site.mach = m and m in dirsOf[c])
    eventually complete[i]
  }
}

/* The reconstitution claim exercised rather than asserted: a whole campaign
   runs with no local directory on any machine. */
pred S15_NoLocalDirectory {
  one c: Campaign {
    always no dirsOf[c]
    #c.members = 2
    mergeClosed[c.members]
    always Now.ev not in AddMember + RemoveMember
    eventually (all i: c.members | complete[i])
    closeDiscipline[c]
    eventually (closable[c] and campaignClosed[c])
  }
}

/* ---------------- commands ---------------- */

run S7_TwoMachinesOneDeletes    for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 2 Machine, exactly 2 Repo, 1 Topic, 2 Tree, 10 steps expect 1
run S15_NoLocalDirectory        for exactly 3 Issue, 2 PR, exactly 1 Campaign, 1 Machine, exactly 3 Repo, 1 Topic, 1 Tree, 12 steps expect 1
