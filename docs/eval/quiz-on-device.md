# On-device quiz evaluation

- Date: Oct 4, 2026 at 7:43 AM
- System: macOS Version 26.5.2 (Build 25F84), Apple on-device model (one question per call)
- Command: `swift run --package-path Packages/VocabularyKit vos-eval quiz`
- Result: valid 10/10 without the local fallback, first question 0.00 s, median 0.00 s (targets: all valid, first question < 5 s — met)
- The right answer always comes from the saved word. Distractors come from the other saved
  words, and the model writes the cloze sentences. Brackets mark the right answer.

Valid 10/10.

| Kind | Word | Question | Seconds |
| --- | --- | --- | --- |
| meaning | cookies (en) | cookies → elma / bank / sunum / [çerez] | 0.0 |
| reverse | pitch (en) | sunum → ran / cookies / [pitch] / apple | 0.0 |
| cloze | umbrella (en) | I put my ____ under the tree to protect myself from the rain. → [umbrella] / cookies / ran / pitch | 1.3 |
| listening | apple (en) | apple → anahtar / [elma] / tren / bank | 0.0 |
| cloze | ran (en) | The coach ____ the players through the drills before the game. → [ran] / umbrella / cookies / pitch | 0.8 |
| meaning | Bank (de) | Bank → sunum / [bank] / elma / yönetmek | 0.0 |
| reverse | Schlüssel (de) | anahtar → Zug / Apfel / [Schlüssel] / Bank | 0.0 |
| cloze | Zug (de) | Der ____ fuhr durch die Landschaft. → [Zug] / Schlüssel / Apfel / Bank | 0.9 |
| listening | Tasse (de) | Tasse → [fincan] / sunum / şemsiye / elma | 0.0 |
| reverse | Apfel (de) | elma → Tasse / Bank / [Apfel] / Schlüssel | 0.0 |

## Model-written distractors (diagnostic)

Valid 5/10.

| Kind | Word | Question | Seconds |
| --- | --- | --- | --- |
| meaning | cookies (en) | error: guardrailViolation | 0.7 |
| reverse | pitch (en) | sunum → presentation / [pitch] / speech / talk | 0.4 |
| cloze | umbrella (en) | I put my ____ under the tree to protect myself from the rain. → parachute / hat / coat / [umbrella] | 0.9 |
| listening | apple (en) | error: invalidOutput("distractors must be words for other things, all different, without the right answer in them") | 1.0 |
| cloze | ran (en) | error: invalidOutput("sentence must use the target word") | 1.7 |
| meaning | Bank (de) | error: invalidOutput("distractors must be words for other things, all different, without the right answer in them") | 1.0 |
| reverse | Schlüssel (de) | error: invalidOutput("distractors must be words for other things, all different, without the right answer in them") | 1.0 |
| cloze | Zug (de) | Der ____ fuhr durch die Landschaft. → Straür / Bahn / [Zug] / Bus | 0.9 |
| listening | Tasse (de) | Tasse → [fincan] / su / kahve / çay | 1.4 |
| reverse | Apfel (de) | elma → Bir muz / Bir kivi / Bir çilek / [Apfel] | 0.6 |
