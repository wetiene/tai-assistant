# Tai Product Principles

Constitutional principles for product, UX and engineering judgment.

Related: `Docs/README.md`, `Docs/TAI_MANIFESTO.md`, `Docs/PRODUCT_DECISIONS.md`, `Docs/AI_ARCHITECTURE.md`.

Canonical terms: Conversation, Artifact, Memory, Archive, Human Summary, AI Context Prompt, Context Prompt, Recommendation, Evidence, Confidence, User Decision, Trusted Integrations, Confirmed Artifacts.

---

## Tai is an AI coach, not a tracker

Tai exists to help users make better health decisions. Tracking only exists to support better coaching.

## Coaching is the product

Nutrition, workouts, recovery and health data are supporting inputs. The primary user value is timely, practical guidance.

## AI suggests. Humans decide.

Tai may interpret, recommend and explain, but users remain responsible for confirming important actions (User Decision before durable Artifact changes).

## Never silently modify user data

Tai must not silently change meals, workouts, goals, programs, reminders or preferences — Confirmed Artifacts and preferences change only through User Decision.

## Do not ask for information another trusted source already knows

When Trusted Integrations exist, Tai should use them rather than creating duplicate manual entry.

## Apple Health is the preferred source for health metrics

Weight, sleep and other supported health signals should come from Apple Health where available and explicitly authorised.

## Every Recommendation must be explainable

Users should be able to understand what Tai recommends, why it recommends it, and which Evidence was used.

## AI uncertainty must be visible

Tai must not present uncertain interpretation as confirmed fact. Confidence must be visible. Users should be able to correct it.

## Home is a daily briefing

Home should explain what matters now, what Tai has noticed and what the user should do next — typically one clear Recommendation.

## Tai is an ongoing relationship

The experience should feel continuous. Tai uses Memory, Archive-derived context and confirmed history so the relationship persists across sessions.

## Conversation is the interaction layer

Users interact with Tai through natural Conversation, interactive cards, attachments and quick actions.

## Structured Artifacts are the source of truth

Meals, workouts, goals, plans and other confirmed records must exist as Artifacts outside the Conversation.

## Conversation is not the database

Conversation history is interaction history and context, but it must not replace durable Artifacts.

## One obvious next action

Each surface should make the most useful next step clear.

## Reduce friction wherever possible

The best interaction is the one that removes unnecessary effort without reducing control or accuracy.

## User corrections improve Tai

Corrections should improve the current result and update Memory where appropriate so future interpretation improves.

## Every interaction should move the user closer to their goals

An interaction should create useful data, improve understanding, reduce effort or guide a better decision.

## Navigation should remain minimal

New capabilities should first justify whether they belong on Home or inside Tai before creating another navigation destination.

## Prefer proactive coaching over passive reporting

Tai should provide useful guidance before decisions matter, not merely report what has already happened.

## Avoid fake precision

Nutrition, training and health estimates should reflect Confidence, uncertainty and data quality.

## Health and safety are more important than engagement

Tai must prioritise safe guidance over streaks, notifications, retention or aggressive optimisation.

## Keep users in control

Users must be able to review, confirm, correct, dismiss and delete important information and Recommendations.

## Privacy is a feature

Permissions, Memory, health data and location use must be transparent, proportionate and controllable.

## Build long-term trust over short-term engagement

Tai should favour accurate, restrained and honest guidance over frequent or emotionally manipulative interaction.

## Calm, premium and native

The product should feel focused, polished and consistent with high-quality Apple platform experiences.

## Avoid feature bloat

A feature should only be added when it strengthens the core coaching experience.

## How to use these principles

Use these principles to evaluate product, UX and engineering decisions. When a proposed feature conflicts with them, the principles should win unless the product owner explicitly records a superseding decision in `Docs/PRODUCT_DECISIONS.md`. Conceptual AI behaviour must follow `Docs/AI_ARCHITECTURE.md` (including the core loop and AI Decision Hierarchy).
