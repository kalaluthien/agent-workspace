# Campaign principles: migration

This campaign exists to move a working system from one form to another without
changing what it does. These principles add to the container's rules and each
repository's own conventions; where a repository already has a rule, that rule
stands.

## What good means

Behaviour is unchanged, and that was verified rather than argued. Every step can
be undone by a rollback that has actually been run.

## What a claim needs

- An equivalence check: old path and new path over the same inputs, outputs
  diffed, the diff empty or every difference explained. Real recorded inputs
  beat synthetic ones.
- A rollback that was executed at least once, not merely described. A rollback
  path nobody has run is a plan, not a property.

## What to optimise for

Reversibility at every step. Prefer many small cutovers each of which can be
undone alone to one large one that can only be undone whole.

Coexistence over replacement. Run old and new side by side, compare in the
background, and switch only once that comparison has been quiet for a full
cycle of real traffic.

## What to refuse

- A behaviour change inside a migration commit. Fix it before or after, in its
  own commit, so the equivalence check stays meaningful and the diff stays
  reviewable.
- Deleting the old path in the same change that enables the new one. Removal is
  a later subtask, filed once the new path has carried real load.
- A cutover with no rollback, or one whose rollback needs data it destroys.
- Silence about a difference you found and accepted. Write it down with the
  reason; it is the thing an incident will point at.
