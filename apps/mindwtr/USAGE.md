# Using Mindwtr Well

Mindwtr is a strict **GTD (Getting Things Done)** app. That pins down "Projects vs. tags" more precisely than a generic to-do app, because GTD has firm opinions about what each is. Mindwtr's own vocabulary reflects this: **Projects** = multi-step outcomes, **Contexts** = "where or how you get things done" (Mindwtr's word for tags).

## Projects — anything that takes more than one action to finish

In GTD, a Project is **any outcome you can't complete in a single next action**. Not necessarily "big." If it needs 2+ steps, it's a project.

**Rule of thumb:** the project name should describe the **finished state**, not the activity. "Mom's 70th birthday planned and celebrated" beats "Mom's birthday."

**Good project examples:**

- "Understairs cluster stable on new Ubuntu LTS"
- "Reactive Resume OIDC group sync working end-to-end"
- "Kitchen faucet replaced"
- "Berlin apartment lease signed"
- "Q1 performance review submitted"
- "Guitar: play 'Blackbird' from memory"
- "Taxes 2025 filed"

**Not projects (single next actions — belong straight in a list):**

- "Reply to Marta's email"
- "Renew car insurance"
- "Buy milk"

**Areas** (Mindwtr supports these too) sit *above* projects — ongoing spheres of responsibility with no finish line: "Homelab," "Health," "Finances," "Team management." Projects live inside areas. Areas don't get "done"; projects do.

## Contexts (tags) — the situation required to do the task

This is the GTD-purist definition and the one Mindwtr enforces by calling them Contexts. A context answers: **"What do I need in order to actually do this?"** — a place, a tool, a person, an energy level, a chunk of time.

The point: at 9pm on the couch with only a phone, filter Focus to `@phone` or `@home` and instantly see only the things you can do right now. Everything else is invisible and stops nagging.

**Classic contexts (start with 5–7, don't over-engineer):**

- `@home` — needs to be at home (fix the shelf, sort mail)
- `@errands` — needs to be out (pharmacy, hardware store)
- `@computer` — needs a laptop and focus (write the report, review PR)
- `@phone` — a quick call or text
- `@waiting` — waiting on someone else (Mindwtr has a dedicated Waiting For list, so this tag may be redundant)
- `@office` — only doable at the office

**Useful extra dimensions (add only if you'll actually filter by them):**

- **Energy:** `@high-energy`, `@low-energy` — for "I'm fried, what can I still knock out?"
- **Time:** `@15min`, `@deep-work` — for "I have 15 min before a meeting" vs. "I have 2 hours"
- **People:** `@marta`, `@boss`, `@1on1-lead` — batch things to raise next time you talk to them (an agenda list)

Mindwtr also supports **nested contexts** — `@work/meetings` still matches when you filter `@work`. Nice for finer slicing without losing the parent view.

## Classic mistakes to avoid

1. **Using tags as project substitutes.** `#kitchen-reno` as a tag ≠ "Kitchen renovated" as a project. The project has structure, sequence, and a finish line. The tag doesn't.
2. **Topical tags (`#work`, `#personal`, `#finance`).** GTD says: that's what Areas are for. Contexts should be about *how to do it*, not *what it's about*. If you tag by topic, your Focus view stops being useful.
3. **Too many contexts.** If you have 30 tags you'll never filter by any of them. Start with `@home`, `@errands`, `@computer`, `@phone`, plus maybe `@low-energy`. Grow only when you catch yourself thinking "I wish I could see just the X ones."
4. **Project with one action.** If it only has one step, delete the project and put the action in the right context list.
5. **Vague project names ("Health," "Finances").** Those are Areas. A project is "Blood test results reviewed with GP."

## Worked example

You capture: *"call plumber about kitchen faucet."*

- If it's a one-off fix: **not a project**. Single action tagged `@phone`, done.
- If it's turning into "replace the whole faucet, tile the splash, redo caulking": **project** = "Kitchen faucet + splash refreshed." Next actions inside it get contexts:
  - "Call plumber for quote" → `@phone`
  - "Pick tile at Hornbach" → `@errands`
  - "Measure old faucet" → `@home`

The whole discipline: **Project = the outcome. Context = the situation to execute a next action inside it.**
