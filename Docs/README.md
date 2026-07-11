# Tai documentation

This folder is the entry point for every engineer, designer and AI coding agent working on Tai.

## Constitutional layer

These documents form the **constitutional layer** of Tai: why the product exists, what must never change lightly, what has already been decided, and how AI coaching is conceptually structured.

Implementation must follow this layer unless the Product Owner explicitly supersedes it in `PRODUCT_DECISIONS.md`.

Product discussions that change behaviour should **update `PRODUCT_DECISIONS.md`** rather than silently changing the product.

Canonical terms used across the constitutional documents:

Conversation · Artifact · Memory · Archive · Human Summary · AI Context Prompt · Context Prompt · Recommendation · Evidence · Confidence · User Decision · Trusted Integrations · Confirmed Artifacts

---

## Required reading order

Read in this order before designing or implementing product behaviour:

1. **[`TAI_MANIFESTO.md`](TAI_MANIFESTO.md)**  
   Why Tai exists.

2. **[`PRODUCT_PRINCIPLES.md`](PRODUCT_PRINCIPLES.md)**  
   Permanent product principles.

3. **[`PRODUCT_DECISIONS.md`](PRODUCT_DECISIONS.md)**  
   Decisions that have already been made.

4. **[`AI_ARCHITECTURE.md`](AI_ARCHITECTURE.md)**  
   Conceptual AI architecture.

5. **[`../TAI_PRODUCT_V2_P0_BLUEPRINT.md`](../TAI_PRODUCT_V2_P0_BLUEPRINT.md)**  
   Current implementation roadmap (repository root).  
   The blueprint must obey the documents above. If it conflicts, the constitutional documents win until the Product Owner records a superseding decision.

---

## Other documents in this folder

These are useful but are **not** constitutional:

| Document | Role |
|----------|------|
| [`dev-workflow.md`](dev-workflow.md) | Branching, multi-agent ownership, TestFlight proxy auth |
| [`ai-proxy-meal-interpretation-contract.md`](ai-proxy-meal-interpretation-contract.md) | Implementation contract for meal interpretation via the AI proxy |

Operational and contract docs may change with engineering work. They must not contradict the constitutional layer.

---

## How to use this layer

- **New capability?** Check principles and decisions first; extend within Home / Tai and the AI architecture loop.
- **Behaviour change?** Record it in `PRODUCT_DECISIONS.md` with date, decision, reason and optional future review.
- **AI behaviour?** Follow `AI_ARCHITECTURE.md` (core loop, AI Decision Hierarchy, Architectural Rules).
- **Implementation sequencing?** Follow the P0 blueprint only where it aligns with the constitution.
