# ADR-007: Spaced repetition with SM-2 and four ratings

## Status
Proposed

## Date
2026-10-04

## Context
Saved words must come back for review at growing intervals:
- The owner's first draft named SM-2.
- Reviews happen on flashcards and in quizzes.
- The schedule must be deterministic and unit-testable.
- It must behave sensibly across days in the learner's time zone.

## Decision
Use **classic SM-2** (SuperMemo 2) with four buttons mapped to SM-2 quality values:

| Rating | Quality q | Ease change (0.1 − (5−q)(0.08 + (5−q)·0.02)) |
| --- | --- | --- |
| Again | 2 | −0.32 |
| Hard | 3 | −0.14 |
| Good | 4 | 0.00 |
| Easy | 5 | +0.10 |

Per word we keep `ease` (start 2.5, minimum 1.3), `repetitions`, `lapses`, `intervalDays`, `dueAt`
and `lastReviewedAt`. Each review then works as follows:
1. **Again:**
   - `repetitions = 0`, `lapses += 1`, `intervalDays = 1`.
   - Within the current session the card is shown again before the session ends. That second showing
     does not change the schedule.
2. **Hard, Good or Easy:**
   - `repetitions += 1`.
   - `intervalDays` is 1 after the first success, 6 after the second, and after that
     `round(intervalDays × ease)`, using the ease value from before this review.
3. `ease = max(1.3, ease + Δq)`.
4. `dueAt = startOfDay(now) + intervalDays` days, in the learner's current calendar.
5. **At most one schedule change per word per calendar day.** Later answers on the same day (for
   example in a quiz) are logged but don't move the schedule.
6. **Quiz answers map to ratings:** correct → Good, wrong → Again.
7. **New words** are due immediately. Today shows at most `dailyNewLimit` new words (default 15)
   and `dailyReviewLimit` reviews (default 150). Both can be changed in Settings.
8. **Every review** writes a `ReviewLog` (time, rating, mode, interval before and after).

## Alternatives Considered
- **FSRS:**
  - Better retention modelling.
  - Needs parameter fitting and is harder to explain and test by hand.
  - Rejected for v1. Because every review is logged, switching later can replay the history.
- **Leitner boxes:**
  - Simple, but doesn't adapt to per-word difficulty.
  - Rejected.
- **Anki's modified SM-2 (learning steps in minutes, hard/easy multipliers):**
  - Better UX, but many more parameters.
  - Rejected for v1. Minute-level steps are replaced by the in-session re-queue.

## Consequences
- The scheduler is a pure function, `(CardState, rating, now, calendar) → CardState`, fully covered
  by unit tests.
- Pressing Easy on a new word still brings it back the next day, as in classic SM-2. This can be
  revisited later using the logs.
- Day boundaries follow the device's current time zone. A learner who travels may see a card a day
  early or late, which is acceptable.

## Sources
- SM-2 algorithm description (P. Woźniak, 1990): https://super-memory.com/english/ol/sm2.htm
