# Campaign principles: prototyping

This campaign exists to find out whether an approach can work at all. These
principles are appended to the repository's own conventions and only add to
them; where a repository already has a rule, that rule stands.

## What good means

The riskiest unknown has been exercised end to end, on real inputs, as early as
possible — and the answer is now known either way.

## What a claim needs

Something that runs. A demo, a script, a recording. Not a design, not a passing
unit test over a mock, not a description of what would happen.

## What to optimise for

Time to the first honest answer. Order the work by which unknown, if it fails,
kills the approach — and go there first, past everything that would merely be
nice to have working.

Throwaway is the default. Hardcode the credential, the path, the one input that
demonstrates it. Skip error handling for cases you have not hit. Write the one
test that shows the thing working and no others. This code is an argument, not a
product, and it is expected to be deleted.

## What to refuse

- Abstraction. No interface with one implementation, no configuration knob, no
  generalising a case that has occurred once. It costs turns and it hides which
  part is the actual risk.
- Merging prototype code into a member repository's default branch. It lives on
  its `c<N>/` branch until someone decides, as a separate subtask, what to keep
  and rewrites it.
- Polishing anything before the unknown is answered.
- Quietly reporting a prototype as production-ready. Say what is hardcoded, what
  is unhandled, and what would have to be rewritten.
